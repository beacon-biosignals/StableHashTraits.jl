# usage: with StableHashTraits project activated, you can call:
# `using TestEnv; TestEnv.activate(); include("test/benchmark.jl")`

using BenchmarkTools
using StableHashTraits
using DataFrames
using SHA
using CRC32c
using Random
using Serialization

# only `collect` when we have to
crc(x, s=0x000000) = crc32c(collect(x), s)
crc(x::Union{SubArray{UInt8},Vector{UInt8}}, s=0x000000) = crc32c(x, s)

struct BenchTest
    a::Int
    b::Int
end

function str_to_data(strs)
    io = IOBuffer()
    for str in strings
        write(io, str)
    end
    return take!(io)
end

function build_nested_dict(width, depth)
    key_blob = rand('a':'z', width*5)
    keys = [Symbol(String(chars)) for chars in Iterators.partition(key_blob, 5)]
    if depth > 1
        return Dict{Any, Any}(k => build_nested_dict(width, depth-1) for k in keys)
    else
        return Dict{Any, Any}(keys .=> rand(width))
    end
end

const N = 10_000
data = rand(Int, N)
tuples = tuple.(rand(Int, N), rand(Int, N))
strings = [String(rand('a':'z', 30)) for _ in 1:N]
symbols = [Symbol(String(rand('a':'z', 30))) for _ in 1:N]
structs = [BenchTest(rand(Int), rand(Int)) for _ in 1:N]
df = DataFrame(; x=1:N, y=1:N)
missings_values = shuffle!([rand(Int, N); fill(missing, N >> 4)])
dicts = build_nested_dict(10, 4);

function serialized_bytes(x)
    io = IOBuffer()
    serialize(io, x)
    return take!(io)
end

# Define a parent BenchmarkGroup to contain our suite
const suite = BenchmarkGroup()

benchmarks = [(; name="dataframes", data=df);
              (; name="structs", data=structs);
              (; name="symbols", data=symbols);
              (; name="strings", data=strings);
              (; name="tuples", data=tuples);
              (; name="missings", data=missings_values);
              (; name="numbers", data=data);
              (; name="dicts", data=dicts)]

for hashfn in (crc, sha256)
    hstr = nameof(hashfn)
    for V in (3, 4)
        for (; name, data) in benchmarks
            suite["$(name)_$(hstr)_$V"] = BenchmarkGroup([name])
            suite["$(name)_$(hstr)_$V"]["base"] = begin
                @benchmarkable $(hashfn)($(serialized_bytes)($data))
            end
            suite["$(name)_$(hstr)_$V"]["trait"] = begin
                @benchmarkable $(stable_hash)($data, HashVersion{$(V)}(); alg=$(hashfn))
            end
        end
    end
end

# If a cache of tuned parameters already exists, use it, otherwise, tune and cache
# the benchmark parameters. Reusing cached parameters is faster and more reliable
# than re-tuning `suite` every time the file is included.
paramspath = joinpath(dirname(@__FILE__), "benchparams3.json")

if isfile(paramspath)
    loadparams!(suite, BenchmarkTools.load(paramspath)[1], :evals)
else
    tune!(suite)
    BenchmarkTools.save(paramspath, params(suite))
end

result = run(suite)

timestr(x) = replace(sprint(show, x), r"TrialEstimate\((.*)\)" => s"\1")
rows = map(collect(keys(result))) do case
    m2 = minimum(result[case]["base"])
    m1 = minimum(result[case]["trait"])
    r1 = ratio(m1, m2)
    benchmark, hash, version = split(case, "_")
    return (; benchmark, hash, version, base=timestr(m2), trait=timestr(m1), ratio=r1.time)
end
display(sort(DataFrame(rows), [:version, :hash, order(:ratio; rev=true)]))
