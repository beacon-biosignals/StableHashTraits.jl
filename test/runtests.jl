include("setup_tests.jl")

@testset "StableHashTraits.jl" begin
    # reference tests to ensure hash consistency
    @test_reference "references/ref00.txt" stable_hash(())
    @test_reference "references/ref01.txt" stable_hash([1, 2, 3])
    @test_reference "references/ref02.txt" stable_hash([1 2; 3 4])
    @test_reference "references/ref03.txt" stable_hash((a=1, b=2))
    @test_reference "references/ref04.txt" stable_hash(Set(1:3))
    @test_reference "references/ref05.txt" stable_hash(sin)
    @test_reference "references/ref06.txt" stable_hash(TestType2(1, 2))
    @test_reference "references/ref07.txt" stable_hash(TypeType(Array))
    @test_reference "references/ref08.txt" stable_hash(TestType5("bobo"))
    @test_reference "references/ref09.txt" stable_hash(Nothing)
    @test_reference "references/ref10.txt" stable_hash(Missing)
    @test_reference "references/ref11.txt" stable_hash(v"0.1.0")
    @test_reference "references/ref12.txt" stable_hash(UUID("8d70055f-1864-48ff-8a94-2c16d4e1d1cd"))
    @test_reference "references/ref13.txt" stable_hash(Date("2002-01-01"))
    @test_reference "references/ref14.txt" stable_hash(Time("12:00"))
    @test_reference "references/ref15.txt" stable_hash(TimePeriod(Nanosecond(0)))
    @test_reference "references/ref16.txt" stable_hash(Hour(1) + Minute(2))
    @test_reference "references/ref17.txt" stable_hash(DataFrame(; x=1:10, y=1:10))
    @test_reference "references/ref18.txt" stable_hash(Dict(:a => "1", :b => "2"))

    # get some code coverage (and reference tests) for sha256
    @test_reference "references/ref19.txt" stable_hash([1, 2, 3]; alg=sha256)
    @test_reference "references/ref20.txt" stable_hash(v"0.1.0"; alg=sha256)
    @test_reference "references/ref21.txt" stable_hash(sin; alg=sha256)
    @test_reference "references/ref22.txt" stable_hash(Set(1:3); alg=sha256)
    @test_reference "references/ref23.txt" stable_hash(DataFrame(; x=1:10, y=1:10),
                                                       TablesEq(); alg=sha256)
    @test_reference "references/ref24.txt" stable_hash([1 2; 3 4]; alg=sha256)

    # get some code coverage (and reference tests) for sha1
    @test_reference "references/ref25.txt" stable_hash([1, 2, 3]; alg=sha1)
    @test_reference "references/ref26.txt" stable_hash(v"0.1.0"; alg=sha1)
    @test_reference "references/ref27.txt" stable_hash(sin; alg=sha1)
    @test_reference "references/ref28.txt" stable_hash(Set(1:3); alg=sha1)
    @test_reference "references/ref29.txt" stable_hash(DataFrame(; x=1:10, y=1:10),
                                                       TablesEq(); alg=sha1)
    @test_reference "references/ref30.txt" stable_hash([1 2; 3 4]; alg=sha1)

    # verifies that transform can be called recurisvely
    @test stable_hash(GoodTransform(2)) == stable_hash(GoodTransform("-0.2"))
    @test stable_hash(GoodTransform(3)) != stable_hash(GoodTransform("-0.2"))

    # various (in)equalities
    @test_throws ArgumentError stable_hash(BadTransform())

    @test stable_hash(Dict(:a => "1", :b => "2")) == stable_hash(Dict(:b => "2", :a => "1"))
    @test stable_hash((; a = "1", b = "2")) != stable_hash((; b = "2", a = "1"))
    
    @test stable_hash((; x=collect(1:10), y=collect(1:10))) !=
          stable_hash([(; x=i, y=i) for i in 1:10])
    @test stable_hash([(; x=i, y=i) for i in 1:10]) !=
          stable_hash(DataFrame(; x=1:10, y=1:10))
    @test stable_hash((; x=collect(1:10), y=collect(1:10)), TablesEq()) ==
          stable_hash([(; x=i, y=i) for i in 1:10], TablesEq())
    @test stable_hash([(; x=i, y=i) for i in 1:10], TablesEq()) ==
          stable_hash(DataFrame(; x=1:10, y=1:10), TablesEq())
    @test stable_hash(DataFrame(; x=1:10, y=1:10)) !=
          stable_hash(NonTableStruct(1:10, 1:10))
    @test stable_hash(DataFrame(; x=1:10, y=1:10), TablesEq()) ==
          stable_hash(NonTableStruct(1:10, 1:10), TablesEq())

    @test stable_hash(CustomHashObject(1:5, 1:10)) !=
          stable_hash(BasicHashObject(1:5, 1:10))
    @test stable_hash(Set(1:20)) == stable_hash(Set(reverse(1:20)))
    @test stable_hash([]) != stable_hash([(), (), ()])

    @test stable_hash([1 2; 3 4]) != stable_hash(vec([1 2; 3 4]))
    @test stable_hash([1 2; 3 4]) != stable_hash([1 3; 2 4]')
    @test stable_hash([1 2; 3 4]) != stable_hash([1 3; 2 4])
    @test stable_hash([1 2; 3 4], ViewsEq()) != stable_hash(vec([1 2; 3 4]), ViewsEq())
    @test stable_hash([1 2; 3 4], ViewsEq()) == stable_hash([1 3; 2 4]', ViewsEq())
    @test stable_hash([1 2; 3 4], ViewsEq()) != stable_hash([1 3; 2 4], ViewsEq())
    @test stable_hash(reshape(1:10, 2, 5)) != stable_hash(reshape(1:10, 5, 2))
    @test stable_hash(view(collect(1:5), 1:2)) != stable_hash([1, 2])
    @test stable_hash(view(collect(1:5), 1:2), ViewsEq()) == stable_hash([1, 2], ViewsEq())
    @test stable_hash(view("bob", 1:2)) != stable_hash("bo")
    @test stable_hash(view("bob", 1:2), ViewsEq()) == stable_hash("bo", ViewsEq())

    @test stable_hash([(), ()]) != stable_hash([(), (), ()])

    @test stable_hash(1:10) != stable_hash((; start=1, stop=10))
    @test stable_hash(1:10) != stable_hash(collect(1:10))
    @test stable_hash([1, 2, 3]) != stable_hash([3, 2, 1])
    @test stable_hash((1, 2, 3)) != stable_hash([1, 2, 3])

    @test stable_hash(v"0.1.0") != stable_hash(v"0.1.2")

    @test stable_hash((a=1, b=2)) != stable_hash((b=2, a=1))
    @test stable_hash((a=1, b=2)) != stable_hash((a=2, b=1))
    @test stable_hash([:ab]) != stable_hash([:a, :b])
    @test stable_hash("a", "b") != stable_hash("ab")
    @test stable_hash(["ab"]) != stable_hash(["a", "b"])
    @test stable_hash(:foo) != stable_hash("foo")
    @test stable_hash(:foo) != stable_hash(:bar)

    @test stable_hash(sin) != stable_hash(cos)
    @test stable_hash(sin) != stable_hash(:sin)
    @test stable_hash(sin) != stable_hash("sin")
    @test stable_hash(sin) != stable_hash("Base.sin")
    @test_throws ErrorException stable_hash(x -> x + 1)

    @test stable_hash(ExtraTypeParams{:A,Int}(2)) != stable_hash(ExtraTypeParams{:B,Int}(2))
    @test stable_hash(TestType(1, 2)) == stable_hash(TestType(1, 2))
    @test stable_hash(TestType(1, 2)) != stable_hash((a=1, b=2))
    @test stable_hash(TestType2(1, 2)) != stable_hash((a=1, b=2))
    @test stable_hash(TestType4(1, 2)) == stable_hash(TestType4(1, 2))
    @test stable_hash(TestType4(1, 2)) != stable_hash(TestType3(1, 2))
    @test stable_hash(TestType(1, 2)) == stable_hash(TestType3(2, 1))
    @test stable_hash(TestType(1, 2)) != stable_hash(TestType4(2, 1))

    @test (@test_deprecated(r"`parent_context`", stable_hash([1, 2], MyOldContext()))) !=
          stable_hash([1, 2])
    @test (@test_deprecated(r"`parent_context`", stable_hash("12", MyOldContext()))) ==
          stable_hash("12")
end

@testset "Aqua" begin
    Aqua.test_all(StableHashTraits)
end
