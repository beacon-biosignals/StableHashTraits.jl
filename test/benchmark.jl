# usage: with StableHashTraits project activated, you can call:
# `using TestEnv; TestEnv.activate(); include("test/benchmark.jl")`

using BenchmarkTools
using StableHashTraits
using DataFrames
using SHA
using CRC32c
using Random

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

const N = 10_000
data = rand(Int, N)
data1 = vec(rand(Int, 2, N))
data2 = tuple.(rand(Int, N), rand(Int, N))
strings = [String(rand('a':'z', 30)) for _ in 1:N]
symbols = [Symbol(String(rand('a':'z', 30))) for _ in 1:N]
structs = [BenchTest(rand(Int), rand(Int)) for _ in 1:N]
struct_data = [x for st in structs for x in (st.a, st.b)]
df = DataFrame(; x=1:N, y=1:N)
missings_data = shuffle!([rand(Int, N); fill(missing, N >> 4)])
non_missings_data = rand(Int, N + (N >> 4))

# ideally we'd change the size here depending on the hash
type_stand_in = rand(1:4, round(Int, N*(256/64)))
types = rand((Int, String, Float64, Char), N)

# Define a parent BenchmarkGroup to contain our suite
const suite = BenchmarkGroup()

benchmarks = [(; name="dataframes", a=data1, b=df);
              (; name="structs", a=struct_data, b=structs);
              (; name="symbols", a=symbols, b=symbols);
              (; name="strings", a=strings, b=strings);
              (; name="tuples", a=data1, b=data2);
              (; name="missings", a=non_missings_data, b=missings_data);
              (; name="numbers", a=data, b=data);
              (; name="repeated", a=data, b=(data, data, data, data));
              (; name="types", a=type_stand_in, b=types)]

for hashfn in (crc, sha256)
    hstr = nameof(hashfn)
    for V in (3, 4)
        for (; name, a, b) in benchmarks
            suite["$(name)_$(hstr)_$V"] = BenchmarkGroup([name])
            if name in ("strings", "symbols")
                suite["$(name)_$(hstr)_$V"]["base"] = @benchmarkable begin
                    $(hashfn)(str_to_data($a))
                end
            else
                suite["$(name)_$(hstr)_$V"]["base"] = @benchmarkable begin
                    $(hashfn)(reinterpret(UInt8, $a))
                end

            end
            suite["$(name)_$(hstr)_$V"]["trait"] = @benchmarkable begin
                $(stable_hash)($b, HashVersion{$(V)}(); alg=$(hashfn))
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
