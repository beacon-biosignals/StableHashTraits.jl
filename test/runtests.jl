include("setup_tests.jl")

@testset "StableHashTraits.jl" begin
    bytes2hex_(x::Number) = x
    bytes2hex_(x) = bytes2hex(x)
    crc(x, s=0x000000) = crc32c(collect(x), s)
    crc(x::Union{SubArray{UInt8},Vector{UInt8}}, s=0x000000) = crc32c(x, s)

    @testset "Older Reference Tests" begin
        @test_reference "references/ref20.txt" stable_hash([1, 2, 3]; alg=crc)
        @test_reference "references/ref21.txt" stable_hash(v"0.1.0"; alg=crc)
        @test_reference "references/ref22.txt" stable_hash(sin; alg=crc)
        @test_reference "references/ref23.txt" stable_hash(Set(1:3); alg=crc)
        @test_reference "references/ref24.txt" stable_hash(DataFrame(; x=1:10, y=1:10),
                                                           TablesEq(); alg=crc)
        @test_reference "references/ref25.txt" stable_hash([1 2; 3 4]; alg=crc)

        # get some code coverage (and reference tests) for sha1
        @test_reference "references/ref26.txt" bytes2hex(stable_hash([1, 2, 3]; alg=sha1))
        @test_reference "references/ref27.txt" bytes2hex(stable_hash(v"0.1.0"; alg=sha1))
        @test_reference "references/ref28.txt" bytes2hex(stable_hash(sin; alg=sha1))
        @test_reference "references/ref29.txt" bytes2hex(stable_hash(Set(1:3); alg=sha1))
        @test_reference "references/ref30.txt" bytes2hex(stable_hash(DataFrame(; x=1:10,
                                                                               y=1:10),
                                                                     TablesEq(); alg=sha1))
        @test_reference "references/ref31.txt" bytes2hex(stable_hash([1 2; 3 4]; alg=sha1))
    end

    for V in (1, 2, 3, 4), hashfn in (sha256, sha1, crc)
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
            end

            # verifies that transform can be called recursively
            @testset "FnHash" begin
                @test test_hash(GoodTransform(2)) == test_hash(GoodTransform("-0.2"))
                @test test_hash(GoodTransform(3)) != test_hash(GoodTransform("-0.2"))

                # various (in)equalities
                @test_throws ArgumentError test_hash(BadTransform())
            end

            # dictionary like
            @testset "Associative Data" begin
                if V > 1
                    @test test_hash(Dict{Symbol, Any}(:a => 1)) != test_hash(Dict{Symbol, Any}(:a => UInt(1)))
                else
                    @test test_hash(Dict{Symbol, Any}(:a => 1)) == test_hash(Dict{Symbol, Any}(:a => UInt(1)))
                end

                @test test_hash(Dict(:a => 1, :b => 2)) == test_hash(Dict(:b => 2, :a => 1))
                @test ((; kwargs...) -> test_hash(kwargs))(; a=1, b=2) ==
                      ((; kwargs...) -> test_hash(kwargs))(; b=2, a=1)
                @test test_hash((; a=1, b=2)) != test_hash((; b=2, a=1))
                @test test_hash((; a=1, b=2)) != test_hash((; a=2, b=1))
            end

            # table like
            @testset "Tables" begin
                @test test_hash((; x=collect(1:10), y=collect(1:10))) !=
                      test_hash([(; x=i, y=i) for i in 1:10])
                @test test_hash([(; x=i, y=i) for i in 1:10]) !=
                      test_hash(DataFrame(; x=1:10, y=1:10))
                @test test_hash((; x=collect(1:10), y=collect(1:10)), TablesEq()) ==
                      test_hash([(; x=i, y=i) for i in 1:10], TablesEq())
                @test test_hash([(; x=i, y=i) for i in 1:10], TablesEq()) ==
                      test_hash(DataFrame(; x=1:10, y=1:10), TablesEq())
                @test test_hash(DataFrame(; x=1:10, y=1:10)) !=
                      test_hash(NonTableStruct(1:10, 1:10))
                @test test_hash(DataFrame(; x=1:10, y=1:10), TablesEq()) !=
                      test_hash(NonTableStruct(1:10, 1:10), TablesEq())
            end

            # test out HashAndContext
            @testset "Contexts" begin
                @test test_hash(CustomHashObject(1:5, 1:10)) !=
                      test_hash(BasicHashObject(1:5, 1:10))
                @test test_hash(Set(1:20)) == test_hash(Set(reverse(1:20)))
                @test test_hash([]) != test_hash([(), (), ()])
                @test_throws ArgumentError test_hash("bob", BadRootContext())
                @test test_hash(1, BadRootContext()) isa Union{Unsigned,Vector{UInt8}}
            end

            @testset "Sequences" begin
                if V > 2
                    @test test_hash(Any[1, 2]) != test_hash(Any[UInt(1), UInt(2)])
                    @test test_hash(Any[1, 2], ViewsEq(HashVersion{V}())) != 
                          test_hash(Any[UInt(1), UInt(2)], ViewsEq(HashVersion{V}()))
                else
                    @test test_hash(Any[1, 2]) == test_hash(Any[UInt(1), UInt(2)])
                    @test test_hash(Any[1, 2], ViewsEq(HashVersion{V}())) == 
                          test_hash(Any[UInt(1), UInt(2)], ViewsEq(HashVersion{V}()))
                end

                @test test_hash([1 2; 3 4]) != test_hash(vec([1 2; 3 4]))
                @test test_hash([1 2; 3 4]) != test_hash([1 3; 2 4]')
                @test test_hash([1 2; 3 4]) != test_hash([1 3; 2 4])
                # TODO: setup some tests for eltype elision in ViewsEq (also add benchmark)
                @test test_hash([1 2; 3 4], ViewsEq(HashVersion{V}())) !=
                      test_hash(vec([1 2; 3 4]), ViewsEq(HashVersion{V}()))
                @test test_hash([1 2; 3 4], ViewsEq(HashVersion{V}())) == test_hash([1 3; 2 4]', ViewsEq(HashVersion{V}()))
                @test test_hash([1 2; 3 4], ViewsEq(HashVersion{V}())) != test_hash([1 3; 2 4], ViewsEq(HashVersion{V}()))
                @test test_hash(reshape(1:10, 2, 5)) != test_hash(reshape(1:10, 5, 2))
                @test test_hash(view(collect(1:5), 1:2)) != test_hash([1, 2])
                @test test_hash(view(collect(1:5), 1:2), ViewsEq(HashVersion{V}())) ==
                      test_hash([1, 2], ViewsEq(HashVersion{V}()))

                @test test_hash([(), ()]) != test_hash([(), (), ()])

                @test test_hash(1:10) != test_hash((; start=1, stop=10))
                @test test_hash(1:10) != test_hash(collect(1:10))
                @test test_hash([1, 2, 3]) != test_hash([3, 2, 1])
                @test test_hash((1, 2, 3)) != test_hash([1, 2, 3])
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
                @test test_hash(view("bob", 1:2)) != test_hash("bo")
                @test test_hash(view("bob", 1:2), ViewsEq()) == test_hash("bo", ViewsEq())
                @test test_hash(S3Path("s3://foo/bar")) != test_hash(S3Path("s3://foo/baz"))
            end

            @testset "Functions" begin
                @test test_hash(sin) != test_hash(cos)
                @test test_hash(sin) != test_hash(:sin)
                @test test_hash(sin) != test_hash("sin")
                @test test_hash(sin) != test_hash("Base.sin")
                @test test_hash(Int) != test_hash("Base.Int")
                @test_throws ArgumentError test_hash(x -> x + 1)
            end

            @testset "Types" begin
                @test test_hash(Float64) != test_hash("Base.Float64")
                @test test_hash(Float64) != test_hash(Int)
                @test test_hash(Array{Int,3}) != test_hash(Array{Int,4})
            end

            @testset "Structs" begin
                if V > 2
                    @test test_hash(TestAnyField(1, 2)) != test_hash(TestAnyField(1, UInt(2)))
                else
                    @test test_hash(TestAnyField(1, 2)) == test_hash(TestAnyField(1, UInt(2)))
                end
            end

            @testset "Custom hash_method" begin
                @test @ConstantHash(5).constant isa UInt64
                @test @ConstantHash("foo").constant isa UInt64
                if V > 1
                    @test test_hash(TestType(1, 2)) != TestType(UInt(1), UInt(2))
                end
                @test test_hash(ExtraTypeParams{:A,Int}(2)) !=
                      test_hash(ExtraTypeParams{:B,Int}(2))
                @test test_hash(TestType(1, 2)) == test_hash(TestType(1, 2))
                @test test_hash(TestType(1, 2)) != test_hash((a=1, b=2))
                @test test_hash(TestType2(1, 2)) != test_hash((a=1, b=2))
                @test test_hash(TestType4(1, 2)) == test_hash(TestType4(1, 2))
                @test test_hash(TestType4(1, 2)) != test_hash(TestType3(1, 2))
                @test test_hash(TestType(1, 2)) == test_hash(TestType3(2, 1))
                @test test_hash(TestType(1, 2)) != test_hash(TestType4(2, 1))
                @test_throws ArgumentError test_hash(BadHashMethod())
            end
        end
    end
    @testset "Deprecations" begin
        @test (@test_deprecated(r"`parent_context`",
                                stable_hash([1, 2], MyOldContext()))) !=
              stable_hash([1, 2], HashVersion{1}())
        @test (@test_deprecated(r"`parent_context`",
                                stable_hash("12", MyOldContext()))) ==
              stable_hash("12", HashVersion{1}())
        @test_deprecated(HashVersion{1}())
        @test_deprecated(HashVersion{2}())
        @test_deprecated(UseProperties(:ByName))
        @test_deprecated(UseQualifiedName())
        @test_deprecated(UseSize(UseIterate()))
        @test_deprecated(ConstantHash("foo"))
        @test_deprecated(UseTable())
    end
end

@testset "Aqua" begin
    Aqua.test_all(StableHashTraits)
end
