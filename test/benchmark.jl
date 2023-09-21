# usage: with StableHashTraits project activated, you can call:
# `using TestEnv; TestEnv.activate(); include("test/benchmark.jl")`

using BenchmarkTools
using StableHashTraits
using DataFrames
using SHA
using CRC32c

# only `collect` when we have to
crc(x, s=0x000000) = crc32c(collect(x), s)
crc(x::Union{SubArray{UInt8},Vector{UInt8}}, s=0x000000) = crc32c(x, s)

struct BenchTest
    a::Int
    b::Int
end

const N = 10_000
data = rand(Int, N)
data1 = vec(rand(Int, 2, N))
data2 = tuple.(rand(Int, N), rand(Int, N))
strings = [String(rand('a':'z', 30)) for _ in 1:N]
strdata = [c for str in strings for c in str]
symbols = [Symbol(String(rand('a':'z', 30))) for _ in 1:N]
symdata = [c for sym in symbols for c in String(sym)]
structs = [BenchTest(rand(Int), rand(Int)) for _ in 1:N]
struct_data = [x for st in structs for x in (st.a, st.b)]
df = DataFrame(; x=1:N, y=1:N)

# Define a parent BenchmarkGroup to contain our suite
const suite = BenchmarkGroup()

benchmarks = [(; name="dataframes", a=data1, b=df);
              (; name="structs", a=struct_data, b=structs);
              (; name="symbols", a=symdata, b=symbols);
              (; name="strings", a=strdata, b=strings);
              (; name="tuples", a=data1, b=data2);
              (; name="vnumbers", a=data, b=data);
              (; name="numbers", a=data, b=data)]

for V in (2, 3)
    for hashfn in (crc, sha256)
        hstr = nameof(hashfn)
        for (; name, a, b) in benchmarks
            suite["$(name)_$(hstr)_$(V)"] = BenchmarkGroup([name])
            a_run = @benchmarkable $(hashfn)(reinterpret(UInt8, $a))
            suite["$(name)_$(hstr)_$(V)"]["base"] = a_run
            if name == "vnumbers"
                b_run = @benchmarkable $(stable_hash)($b, ViewsEq(HashVersion{$V}()); alg=$(hashfn))
                suite["$(name)_$(hstr)_$(V)"]["trait"] = b_run
            else
                b_run = @benchmarkable $(stable_hash)($b, HashVersion{$V}(); alg=$(hashfn))
                suite["$(name)_$(hstr)_$(V)"]["trait"] = b_run
            end
        end
    end
end

# NOTE: I think we caught an intersting bug by trying to hash the benchmark

# If a cache of tuned parameters already exists, use it, otherwise, tune and cache
# the benchmark parameters. Reusing cached parameters is faster and more reliable
# than re-tuning `suite` every time the file is included.
paramspath = joinpath(dirname(@__FILE__), "benchparams.json")

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
    return (; version, benchmark, hash, base=timestr(m2), trait=timestr(m1), ratio=r1.time)
end
display(sort(DataFrame(rows), [:version, :hash, order(:ratio; rev=true)]))
