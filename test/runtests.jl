include("setup_tests.jl")

@testset "StableHashTraits.jl" begin
    bytes2hex_(x::Number) = x
    bytes2hex_(x) = bytes2hex(x)
    crc(x, s=0x000000) = crc32c(collect(x), s)
    crc(x::Union{SubArray{UInt8},Vector{UInt8}}, s=0x000000) = crc32c(x, s)

    @testset "Old hash versions generate an error" begin
        for version in (1, 3, 3)
            @test_throws ArgumentError stable_hash(1; version)
        end
    end

    for V in (4,), hashfn in (sha256, sha1, crc32c)
        @testset "Hash: $(nameof(hashfn)); context: $V" begin
            ctx = HashVersion{V}()
            test_hash(x, c=ctx) = stable_hash(x, c; alg=hashfn)

            # reference tests to ensure hashfn consistency
            @testset "Reference Tests" begin
                @test_reference("references/ref00_$(V)_$(nameof(hashfn)).txt",
                                bytes2hex_(test_hash(())))
                @test_reference("references/ref01_$(V)_$(nameof(hashfn)).txt",
                                bytes2hex_(test_hash([1, 2, 3])))
                @test_reference("references/ref02_$(V)_$(nameof(hashfn)).txt",
                                bytes2hex_(test_hash([1 2; 3 4])))
                @test_reference("references/ref03_$(V)_$(nameof(hashfn)).txt",
                                bytes2hex_(test_hash((a=1, b=2))))
                @test_reference("references/ref04_$(V)_$(nameof(hashfn)).txt",
                                bytes2hex_(test_hash(Set(1:3))))
                @test_reference("references/ref05_$(V)_$(nameof(hashfn)).txt",
                                bytes2hex_(test_hash(sin)))
                @test_reference("references/ref06_$(V)_$(nameof(hashfn)).txt",
                                bytes2hex_(test_hash(TestType2(1, 2))))
                @test_reference("references/ref07_$(V)_$(nameof(hashfn)).txt",
                                bytes2hex_(test_hash(TypeType(Array))))
                @test_reference("references/ref08_$(V)_$(nameof(hashfn)).txt",
                                bytes2hex_(test_hash(TestType5("bobo"))))
                @test_reference("references/ref09_$(V)_$(nameof(hashfn)).txt",
                                bytes2hex_(test_hash(Nothing)))
                @test_reference("references/ref10_$(V)_$(nameof(hashfn)).txt",
                                bytes2hex_(test_hash(Missing)))
                @test_reference("references/ref11_$(V)_$(nameof(hashfn)).txt",
                                bytes2hex_(test_hash(v"0.1.0")))
                @test_reference("references/ref12_$(V)_$(nameof(hashfn)).txt",
                                bytes2hex_(test_hash(UUID("8d70055f-1864-48ff-8a94-2c16d4e1d1cd"))))
                @test_reference("references/ref13_$(V)_$(nameof(hashfn)).txt",
                                bytes2hex_(test_hash(Date("2002-01-01"))))
                @test_reference("references/ref14_$(V)_$(nameof(hashfn)).txt",
                                bytes2hex_(test_hash(Time("12:00"))))
                @test_reference("references/ref15_$(V)_$(nameof(hashfn)).txt",
                                bytes2hex_(test_hash(TimePeriod(Nanosecond(0)))))
                @test_reference("references/ref16_$(V)_$(nameof(hashfn)).txt",
                                bytes2hex_(test_hash(Hour(1) + Minute(2))))
                @test_reference("references/ref17_$(V)_$(nameof(hashfn)).txt",
                                bytes2hex_(test_hash(DataFrame(; x=1:10, y=1:10))))
                @test_reference("references/ref18_$(V)_$(nameof(hashfn)).txt",
                                bytes2hex_(test_hash(Dict(:a => "1", :b => "2"))))
                @test_reference("references/ref19_$(V)_$(nameof(hashfn)).txt",
                                bytes2hex_(test_hash(ExtraTypeParams{:A,Int}(2))))
                @test_reference("references/ref20_$(V)_$(nameof(hashfn)).txt",
                                bytes2hex_(test_hash(==("test"))))
                @test_reference("references/ref21_$(V)_$(nameof(hashfn)).txt",
                                bytes2hex_(test_hash((1, (a=1, b=(x=1, y=2), c=(1, 2))))))
                @test_reference("references/ref22_$(V)_$(nameof(hashfn)).txt",
                                bytes2hex_(test_hash((;))))
                @test_reference("references/ref23_$(V)_$(nameof(hashfn)).txt",
                                ((; kwargs...) -> test_hash(kwargs))(; b=2, a=1))
                @test_reference("references/ref24_$(V)_$(nameof(hashfn)).txt",
                                bytes2hex_(test_hash((; a=1))))
                @test_reference("references/ref25_$(V)_$(nameof(hashfn)).txt",
                                bytes2hex_(test_hash((a=1, b=(;), c=(; c1=1),
                                                      d=(d1=1, d2=2)))))
                @test_reference("references/ref26_$(V)_$(nameof(hashfn)).txt",
                                bytes2hex_(test_hash(2 => 3)))
            end

            # dictionary like
            @testset "Associative Data" begin
                @test test_hash(Dict(:a => 1, :b => 2)) == test_hash(Dict(:b => 2, :a => 1))
                @test ((; kwargs...) -> test_hash(kwargs))(; a=1, b=2) ==
                      ((; kwargs...) -> test_hash(kwargs))(; b=2, a=1)
                @test test_hash((; a=1, b=2)) == test_hash((; b=2, a=1))
                @test test_hash((; a=1, b=2)) != test_hash((; a=2, b=1))
            end

            @testset "DataStructures.jl" begin
                @test test_hash(Accumulator("a" => 2, "b" => 3, "c" => 1)) !=
                      test_hash(Accumulator("a" => 2, "b" => 3, "c" => 2))
                let
                    t = AVLTree{Int}()
                    insert!(t, 1)
                    before_insert = test_hash(t)
                    insert!(t, 101)
                    after_insert = test_hash(t)
                    @test before_insert != after_insert
                end
                @test test_hash(BinaryHeap([1, 2])) != test_hash(BinaryHeap([1, 2, 3]))
                @test test_hash(BinaryMaxHeap([1, 2])) != test_hash(BinaryMaxHeap([1, 2, 3]))
                @test test_hash(BinaryMinHeap([1, 2])) != test_hash(BinaryMinHeap([1, 2, 3]))
                @test test_hash(CircularBuffer{Int}([1, 2])) != test_hash(CircularBuffer{Int}([1, 2, 3]))
                @test test_hash(CircularDeque{Int}([1, 2])) != test_hash(CircularDeque{Int}([1, 2, 3]))
                @test test_hash(DefaultDict(0.0, 1 => 1.0)) != test_hash(DefaultDict(0.0, 1 => 1.0, 2 => 2.0))
                @test test_hash(Dequeue{Int}([1,2])) != test_hash(Dequeue{Int}([1,2,3]))
                @test test_hash(DiBitVector(10)) != test_hash( DiBitVector(10, 0))
                # TODO: stopped here in my process of looking through DataStructures.jl tests

                @test test_hash(OrderedDict(:a => 1, :b => 2)) !=
                      test_hash(OrderedDict(:b => 2, :a => 1))
                @test test_hash(OrderedSet(["a", "b"])) != test_hash(OrderedSet(["b", "a"]))
                @test test_hash(SortedDict(:b => 1, :a => 2)) == test_hash(SortedDict(:a => 2, :b => 1))
                @test test_hash(SortedMultiDict(:b => 1, :a => 2)) == test_hash(SortedMultiDict(:a => 2, :b => 1))
                @test test_hash(SortedSet(["a", "b"])) == test_hash(SortedSet(["b", "a"]))

                # TODO: add reference tests
            end

            # table like
            @testset "Tables" begin
                @test test_hash((; x=collect(1:10), y=collect(1:10))) !=
                      test_hash([(; x=i, y=i) for i in 1:10])
                @test test_hash([(; x=i, y=i) for i in 1:10]) !=
                      test_hash(DataFrame(; x=1:10, y=1:10))
                @test test_hash((; x=collect(1:10), y=collect(1:10)), TablesEq(ctx)) ==
                      test_hash([(; x=i, y=i) for i in 1:10], TablesEq(ctx))
                @test test_hash([(; x=i, y=i) for i in 1:10], TablesEq(ctx)) ==
                      test_hash(DataFrame(; x=1:10, y=1:10), TablesEq(ctx))
                @test test_hash(DataFrame(; x=1:10, y=1:10)) !=
                      test_hash(NonTableStruct(1:10, 1:10))
                @test test_hash(DataFrame(; x=1:10, y=1:10), TablesEq(ctx)) !=
                      test_hash(NonTableStruct(1:10, 1:10), TablesEq(ctx))
            end

            # test out HashAndContext
            @testset "Contexts" begin
                @test_throws MethodError test_hash("bob", BadRootContext())
            end

            @testset "Sequences" begin
                @test test_hash([1 2; 3 4]) != test_hash(vec([1 2; 3 4]))
                @test test_hash([1 2; 3 4]) == test_hash([1 3; 2 4]')
                @test test_hash([1 2; 3 4]) != test_hash([1 3; 2 4])
                @test test_hash(reshape(1:10, 2, 5)) != test_hash(reshape(1:10, 5, 2))
                @test test_hash(view(collect(1:5), 1:2)) == test_hash([1, 2])
                @test test_hash(view(collect(1:5), 1:2), WithTypeNames(ctx)) !=
                      test_hash([1, 2], WithTypeNames(ctx))

                @test test_hash([]) != test_hash([(), (), ()])
                @test test_hash([(), ()]) != test_hash([(), (), ()])

                @test test_hash(1:10) != test_hash((; start=1, stop=10))
                @test test_hash(1:10) != test_hash(collect(1:10))
                @test test_hash([1, 2, 3]) != test_hash([3, 2, 1])
                @test test_hash((1, 2, 3)) != test_hash([1, 2, 3])
                @test test_hash(Set(1:20)) == test_hash(Set(reverse(1:20)))
            end

            @testset "Version Strings" begin
                @test test_hash(v"0.1.0") != test_hash(v"0.1.2")
            end

            @testset "Strings" begin
                @test test_hash([:ab]) != test_hash([:a, :b])
                @test test_hash("foo") != test_hash("bar")
                @test test_hash(("a", "b")) != test_hash("ab")
                @test test_hash(["ab"]) != test_hash(["a", "b"])
                @test test_hash(:foo) != test_hash("foo")
                @test test_hash(:foo) != test_hash(:bar)
                @test test_hash(view("bob", 1:2)) == test_hash("bo")
                @test test_hash(view("bob", 1:2), WithTypeNames(ctx)) !=
                      test_hash("bo", WithTypeNames(ctx))
                @test test_hash(S3Path("s3://foo/bar")) != test_hash(S3Path("s3://foo/baz"))
            end

            @testset "Singletons and nulls" begin
                @test test_hash(missing) != test_hash(nothing)
                @test test_hash(Singleton1()) != test_hash(Singleton2())
            end

            @testset "Regex" begin
                r1 = r"regex"
                r2 = r"regex"
                # Check that they got different Ptrs for the compiled regex.
                # Because that's what causes problems for V <= 3.
                @test r1.regex != r2.regex
                if V <= 3
                    @test_broken test_hash(r1) == test_hash(r2)
                else
                    # Hash shouldn't care about pointer to compiled regex
                    @test test_hash(r1) == test_hash(r2)

                    # test inequalities (including flags)
                    hashes = [test_hash(r1),
                              test_hash(r"abcde"),
                              test_hash(r"regex"i),
                              test_hash(r"regex"m),
                              test_hash(r"regex"s),
                              test_hash(r"regex"x),
                              test_hash(r"regex"a)]
                    @test unique(hashes) == hashes

                    @test_reference("references/regex01_$(V)_$(nameof(hashfn)).txt",
                                    bytes2hex_(test_hash(r"regex")))
                    @test_reference("references/regex02_$(V)_$(nameof(hashfn)).txt",
                                    bytes2hex_(test_hash(r"^\d+_(.+)$")))
                    @test_reference("references/regex03_$(V)_$(nameof(hashfn)).txt",
                                    bytes2hex_(test_hash(r"regex"a)))
                end
            end

            @testset "Functions" begin
                @test test_hash(sin) != test_hash(cos)
                @test test_hash(sin) != test_hash(:sin)
                @test test_hash(sin) != test_hash("sin")
                @test test_hash(sin) != test_hash("Base.sin")
                @test test_hash(==("foo")) == test_hash(==("foo"))
                @test test_hash(Base.Fix1(-, 1)) == test_hash(Base.Fix1(-, 1))
                @test test_hash(Base.Fix1(-, 1)) != test_hash(Base.Fix1(-, 2))
                @test test_hash(==("foo")) != test_hash(==("bar"))
                @test_throws ArgumentError test_hash(x -> x + 1)
            end

            if V >= 4
                @testset "Nested Any" begin
                    @test test_hash(Dict{Symbol,Any}(:a => NumberTypeA(1))) !=
                          test_hash(Dict{Symbol,Any}(:a => NumberTypeB(1)))
                    @test test_hash(Pair{Symbol,Any}(:a, NumberTypeA(1))) !=
                          test_hash(Pair{Symbol,Any}(:a, NumberTypeB(1)))
                    @test test_hash(Pair{Symbol,Any}[:a => NumberTypeA(1)]) !=
                          test_hash(Pair{Symbol,Any}[:a => NumberTypeB(1)])
                end
            end

            @testset "Types" begin
                @test test_hash(Float64) != test_hash(Int)
                @test test_hash(missing) != test_hash("Base.Missing")
                @test test_hash(nothing) != test_hash("Base.Nothing")
                @test test_hash(Vector{Int}) != test_hash(Vector{String})
                @test test_hash(Array{Int}) != test_hash(Array{String})
                @test test_hash(Float64) != test_hash("Float64")
                @test test_hash(Int) != test_hash("Int")
                @test test_hash(WeirdTypeValue) == test_hash(Int)
                @test test_hash(typeof(identity)) != test_hash(identity)
                @test test_hash(Array{Int,3}) != test_hash(Array{Int,4})
                @test test_hash(Array{<:Any,3}) != test_hash(Array{<:Any,4})

                # NOTE: these should run without an `StackOverflowError` (previously it
                # did overflow)
                @test test_hash((; a=Vector{Int})) != test_hash((; a=Vector{String}))
                @test test_hash((; a=Array{T,1} where {T})) !=
                      test_hash((; a=Array{T,2} where {T}))
            end

            @testset "Custom transformer method" begin
                @test test_hash(ExtraTypeParams{:A,Int}(2)) !=
                      test_hash(ExtraTypeParams{:B,Int}(2))
                @test test_hash(TestType(1, 2)) == test_hash(TestType(1, 2))
                @test test_hash(TestType(1, 2)) != test_hash((a=1, b=2))
                @test test_hash(TestType2(1, 2)) != test_hash((a=1, b=2))
                @test test_hash(TestType4(1, 2)) == test_hash(TestType4(1, 2))
                @test test_hash(TestType4(1, 2)) != test_hash(TestType3(1, 2))
                @test test_hash(TestType(1, 2)) != test_hash(TestType4(2, 1))
                @test test_hash(TestType(1, 2)) == test_hash(TestType3(2, 1))
                @test_throws TypeError test_hash(BadHashMethod())
                @test_throws r"Unrecognized trait" test_hash(BadHashMethod2())
            end

            @testset "Pluto-defined structs are stable, even for `module_nameof_string`" begin
                notebook_project_dir = joinpath(@__DIR__, "..")
                @info "Notebook project: $notebook_project_dir"

                notebook_str = """
                ### A Pluto.jl notebook ###
                # v0.19.36

                using Markdown
                using InteractiveUtils

                # ╔═╡ 3592b099-9c96-4939-94b8-7ef2614b0955
                import Pkg

                # ╔═╡ 72871656-ae6e-11ee-2b23-251ac2aa38a3
                begin
                    Pkg.activate("$notebook_project_dir")
                    using StableHashTraits
                end

                # ╔═╡ 1c505fa8-75fa-4ed2-8c3f-43e28135b55d
                begin
                    bytes2hex_(x::Number) = x
                    bytes2hex_(x) = bytes2hex(x)
                end

                # ╔═╡ b449d8e9-7ede-4171-a5ab-044c338ebae2
                begin
                    struct MyStruct end
                    # In hash version 4 types do not have their module hashed
                    # but here we're trying to test that a Pluto module name is properly
                    # regularized, so we need to require that the module name be part of the
                    # hash
                    StableHashTraits.transform_type(::Type{T}) where {T<:MyStruct} = StableHashTraits.module_nameof_string(T)
                end

                # ╔═╡ 1e683f1d-f5f6-4064-970c-1facabcf61cc
                stable_hash(MyStruct(); version=$(V)) |> bytes2hex_

                # ╔═╡ f8f3a7a4-544f-456f-ac63-5b5ce91a071a
                stable_hash((a=MyStruct, b=(c=MyStruct(), d=2)); version=$(V)) |> bytes2hex_

                # ╔═╡ Cell order:
                # ╠═3592b099-9c96-4939-94b8-7ef2614b0955
                # ╠═72871656-ae6e-11ee-2b23-251ac2aa38a3
                # ╠═1c505fa8-75fa-4ed2-8c3f-43e28135b55d
                # ╠═b449d8e9-7ede-4171-a5ab-044c338ebae2
                # ╠═1e683f1d-f5f6-4064-970c-1facabcf61cc
                # ╠═f8f3a7a4-544f-456f-ac63-5b5ce91a071a
                """

                server = Pluto.ServerSession()
                server.options.evaluation.workspace_use_distributed = false
                olddir = pwd()
                nb = mktempdir() do dir
                    path = joinpath(dir, "notebook.pluto.jl")
                    write(path, notebook_str)
                    nb = Pluto.load_notebook(path)
                    Pluto.update_run!(server, nb, nb.cells)
                    return nb
                end
                # pluto changes pwd
                cd(olddir)

                # NOTE: V refers to the hash version currently in the `for` loop at the top
                # of this file
                if nb.cells[5].output.body isa Dict
                    error("Failed notebook eval: $(nb.cells[5].output.body[:msg])")
                else
                    @test_reference("references/pluto01_$(V)_$(nameof(hashfn)).txt",
                                    strip(nb.cells[5].output.body, '"'))
                end

                if nb.cells[6].output.body isa Dict
                    error("Failed notebook eval: $(nb.cells[6].output.body[:msg])")
                else
                    @test_reference("references/pluto02_$(V)_$(nameof(hashfn)).txt",
                                    strip(nb.cells[6].output.body, '"'))
                end
            end

            @testset "Type-stable vs. type-unstable hashing" begin
                # arrays
                xs = [isodd(n) ? Char(n) : Int32(n) for n in 1:10]
                ys = [iseven(n) ? Char(n) : Int32(n) for n in 1:10]
                @test test_hash(xs) != test_hash(ys)

                xs = zeros(Int32, 10)
                ys = Char.(xs)
                @test test_hash(xs) != test_hash(ys)

                # dicts
                xs = Dict(n => isodd(n) ? Char(n) : Int32(n) for n in 1:10)
                ys = Dict(n => iseven(n) ? Char(n) : Int32(n) for n in 1:10)
                @test test_hash(xs) != test_hash(ys)

                xs = Dict(1:10 .=> Int32.(1:10))
                ys = Dict(1:10 .=> Char.(1:10))
                @test test_hash(xs) != test_hash(ys)

                # structs
                xs = [(; n=isodd(n) ? Char(n) : Int32(n)) for n in 1:10]
                ys = [(; n=iseven(n) ? Char(n) : Int32(n)) for n in 1:10]
                @test test_hash(xs) != test_hash(ys)

                xs = [(; n) for n in Int32.(1:10)]
                ys = [(; n) for n in Char.(1:10)]
                @test test_hash(xs) != test_hash(ys)

                # union-splitting tests
                xs = [fill(missing, 3); collect(1:10)]
                ys = [collect(1:10); fill(missing, 3)]
                @test test_hash(xs) != test_hash(ys)

                xs = Union{Int32,UInt32,Char}[Int32(1), Int32(1), UInt32(1), UInt32(1),
                                              Char(1), Char(1)]
                ys = Union{Int32,UInt32,Char}[Int32(1), UInt32(1), Int32(1), Char(1),
                                              UInt32(1), Char(1)]
                @test test_hash(xs) != test_hash(ys)

                # narrowing fields doesn't generate hashing bugs
                @test test_hash(UnstableStruct1(nothing, 1)) !=
                      test_hash(UnstableStruct1(missing, 2))
                @test test_hash(UnstableStruct1(1, 1)) !=
                      test_hash(UnstableStruct1(2, 2))
                @test test_hash(UnstableStruct2(nothing, 1)) !=
                      test_hash(UnstableStruct2(missing, 2))
                @test test_hash(UnstableStruct2(1, 1)) !=
                      test_hash(UnstableStruct2(2, 2))

                # but if we use NamedTuple selection with `hoist_type=true`
                # we do get a bug
                @test test_hash(UnstableStruct3(nothing, 1)) ==
                      test_hash(UnstableStruct3(missing, 2))
            end

            @testset "Hash-invariance to buffer size" begin
                data = (rand(Int8, 2), rand(Int8, 2))
                wrapped1 = StableHashTraits.HashState(sha256, HashVersion{V}())
                alg_small = begin
                    CountedBufferState(StableHashTraits.BufferedHashState(wrapped1, 3))
                end

                wrapped2 = StableHashTraits.HashState(sha256, HashVersion{V}())
                alg_large = begin
                    CountedBufferState(StableHashTraits.BufferedHashState(wrapped2, 20))
                end

                # verify that the hashes are the same...
                @test stable_hash(data, ctx; alg=alg_small) ==
                      stable_hash(data, ctx; alg=alg_large)
                # ...and that the distinct buffer sizes actually lead to a distinct set of
                # buffer sizes while updating the hash state...
                @test alg_small.positions != alg_large.positions
            end
        end # @testset
    end # for
end # @testset

@testset "Aqua" begin
    # NOTE: aqua incorrectly flags the split_union method as having unbound type arguments
    Aqua.test_all(StableHashTraits; unbound_args=(; broken=true))
end
