module StableNames

const NAMED_TUPLES_PRETTY_PRINT_VERSION = v"1.10.0-DEV.885"

# we need this to parse and re-arrange type string outputs in Julia 1.10 and later.
@static if VERSION >= NAMED_TUPLES_PRETTY_PRINT_VERSION
    using PikaParser
end

# NOTE: over time, generating a stable name for a type that is consistent across julia
# versions has become quite complicated. In particular, julia has not considered the string
# output of a type to be a breaking change and so minor versions often include improvements
# to the legibiltiy of types

# the overall goal of `clenaup_name` is to generate a name that is consistent with the
# OLDEST version of julia supported by `StableHashTraits.jl`

function cleanup_name(str)
    # We treat all uses of the `Core` namespace as `Base` across julia versions. What is in
    # `Core` changes, e.g. Base.Pair in 1.6, becomes Core.Pair in 1.9; also see
    # https://discourse.julialang.org/t/difference-between-base-and-core/37426
    str = replace(str, r"^Core\." => "Base.")
    str = replace(str, ", " => ",") # spacing in type names vary across minor julia versions
    # in 1.6 and older AbstractVector and AbstractMatrix types get a `where` clause, but in
    # later versions of julia, they do not
    str = replace(str, "AbstractVector{T} where T" => "AbstractVector")
    str = replace(str, "AbstractMatrix{T} where T" => "AbstractMatrix")

    # cleanup pluto workspace names

    # TODO: eventually, when we create hash version 3 (which will generate strings from
    # scratch rather than leveraging `string(T)`), we should handle pluto symbols by
    # checking `is_inside_pluto` as defined here
    # https://github.com/JuliaPluto/PlutoHooks.jl/blob/f6bc0a3962a700257641c3449db344cf0ddeae1d/src/notebook.jl#L89-L98

    # NOTE: in more recent julia versions (>= 1.8) the values are surrounded by `var`
    # qualifiers
    str = replace(str, r"var\"workspace#[0-9]+\"" => "PlutoWorkspace")
    str = replace(str, r"workspace#[0-9]+" => "PlutoWorkspace")

    # in 1.10 NamedTuples get a cleaned up format that we need to revert
    # to the old output
    # In particular: we need to change something like
    # "@NamedTuple{a::Int64, b::@NamedTuple{x::Int64, y::Int64}}"
    # to be
    # "Base.NamedTuple{(:a,:b),Tuple{Int64,NamedTuple{(:x,:y),Tuple{Int64,Int64}}}}"
    str = cleanup_named_tuple_type(str)
    return str
end

@static if VERSION >= NAMED_TUPLES_PRETTY_PRINT_VERSION
    # As I see it we have two options for how to handle things moving forward with 1.10: we
    # could start to create a function that generates a string (or some other stable
    # representation) from the internal representation of a type OR we can parse the string
    # generated in 1.10 to generate the string of a type from 1.9 and lower. The former may
    # be the best way forward long term but would almost certainly involve changing existing
    # hashes, and so needs to be done as a separate hash version.

    # So we're going with the latter option for now to maintain the behavior from 1.9 in
    # 1.10

    # We make use of PikaParser (docs linked below) as a way to generate a simple grammar
    # and parser that looks at comma and/or space separated clauses surrounded by brackets;
    # all other syntactic bits and bobs are treated as "elements" i.e. space/comma delimited
    # text blobs

    # https://lcsb-biocore.github.io/PikaParser.jl/stable/reference/
    BracketParser = let P = PikaParser
        rules = Dict(:element => P.some(P.satisfy(x -> x ∉ ",{}" && !isspace(x))),
                     :space => P.satisfy(isspace),
                     :sep => P.first(P.seq(P.many(:space), P.token(','), P.many(:space)),
                                     P.some(:space)),
                     :brackets => P.first(P.seq(P.token('{'), P.many(:sep), P.token('}')),
                                          P.seq(P.token('{'), :clause, P.token('}'))),
                     :head_brackets => P.seq(:element, :brackets),
                     :inclause => P.first(:head_brackets, :brackets, :element),
                     :clause => P.seq(P.many(:sep),
                                      :inclause,
                                      P.many(:sepclause => P.seq(:sep, :inclause)),
                                      P.many(:sep)))
        P.make_grammar([:clause], P.flatten(rules, Char))
    end

    struct Parsed
        name::Symbol
        args::Vector{Any}
        Parsed(val, args...) = new(val, collect(args))
    end
    function Base.:(==)(x::Parsed, y::Parsed)
        x.name != y.name && return false
        x.args != y.args && return false
        return true
    end

    function fold_parsed(match, state, vals)
        return if match.rule ∈ (:element, :space, :sep)
            String(match.view)
        elseif match.rule == :brackets
            Parsed(:Brackets, (isnothing(vals[1][2]) ? [""] : vals[1][2])...)
        elseif match.rule == :clause
            reduce(vcat, filter(!isnothing, vals); init=[])
        elseif match.rule == :head_brackets
            Parsed(:Head, vals...)
        elseif match.rule == :sepclause
            Parsed(:SepClause, vals...)
        elseif match.rule == :inclause
            vals[1]
        else
            length(vals) > 0 ? vals : nothing
        end
    end

    struct ParseError <: Exception
        msg::String
    end

    # After passing text through `parse_brackest`, we have a set of `Parsed`
    # objects that can be transformed into new strings
    function parse_brackets(str::String)
        parsed = PikaParser.parse(BracketParser, str)
        m = PikaParser.find_match_at!(parsed, :clause, 1)
        # NOTE: pika parser is robust to errors; we only know that the string was fully
        # parsed if it finds a match starting at the first character and ending at the last
        # character of the string
        if m === 0 || parsed.matches[m].last != length(str)
            throw(ParseError("Cannot properly parse type string, unable to create a stable" *
                             " hash of it: " * str))
        end
        return PikaParser.traverse_match(parsed, m; fold=fold_parsed)
    end
    # TODO: we will also probably have to do something with @Kwargs or whatnot

    # parse_walker is the function used to actually generate a new string. if `fn` == (fn,
    # parsed) -> nothing, `parse_walker` generates exactly the same string that was passed
    # into `parse_brackets`. `fn` can be used to transform the parsed output in some way
    # returning nothing when it doesn't need to do anything. It accepts `fn` as its first
    # argument because it may need to recursively call `parse_walker(fn,...)`, and in
    # general fn could be a composition of multiple transformers, each of which would need
    # to apply the entire set of transformers passed to `parse_walker` if/when the
    # individual transformers call it recursively
    function parse_walker(fn, parsed::Parsed)
        result = fn(fn, parsed)
        !isnothing(result) && return result

        if parsed.name == :Brackets
            return "{" * join(parse_walker(fn, parsed.args)) * "}"
        elseif parsed.name == :Head
            return parsed.args[1] * parse_walker(fn, parsed.args[2])
        elseif parsed.name == :SepClause
            return parsed.args[1] * parse_walker(fn, parsed.args[2])
        else
            throw(ArgumentError("Unexpected name $(parsed.name)"))
        end
    end

    parse_walker(fn, parsed::Nothing) = ""
    function parse_walker(fn, parsed::AbstractString)
        result = fn(fn, parsed)
        !isnothing(result) && return result
        return parsed
    end
    function parse_walker(fn, parsed::Vector)
        result = fn(fn, parsed)
        !isnothing(result) && return result
        return mapreduce(x -> parse_walker(fn, x), *, parsed)
    end

    # revise_named_tuples actually grabs a parsed named tuple type and
    # re-arranges it to the pre Julia 1.10 format. Note that we remove
    # spaces between commas because `cleanup_name` also removes those
    function revise_named_tuples(fn, parsed)
        if parsed isa Parsed && parsed.name == :Head &&
           endswith(parsed.args[1], "@NamedTuple")
            symbols_and_types = split_symbol_and_type.(parsed.args[2].args)
            symbol_tuple = join(":" .* filter(!isempty, first.(symbols_and_types)), ",")
            types = map(t -> parse_walker(fn, t), last.(symbols_and_types))
            types_tuple = join(types, ",")
            prefix = replace(parsed.args[1], "@NamedTuple" => "")
            return prefix * "NamedTuple{($symbol_tuple),Tuple{$types_tuple}}"
        end
    end

    # split_symbol_and_type splits out parsed expressions of the form name::Type accounting
    # for the cases where some part of `Type` is itself parsed (e.g. `a::Tuple{Int, Int}`)
    # NOTE: we could have also included "::" as part of the grammar we parse above but it
    # seemed easier to deal with them here, when I'm generating a new string from the parse
    # tree
    split_symbol_and_type(arg::String) = Tuple(split(arg, "::"))
    function split_symbol_and_type(parsed::Parsed)
        if parsed.name == :SepClause
            return split_symbol_and_type(parsed.args[2])
        elseif parsed.name == :Head
            symbol, type = split_symbol_and_type(parsed.args[1])
            return symbol, Parsed(:Head, type, parsed.args[2:end]...)
        elseif parsed.name == :Brackets
            throw(ArgumentError("Did not expect brackets in this position"))
        else
            throw(ArgumentError("Unexpected name $(parsed.name)"))
        end
    end

    # in principle we may need to apply multiple transformations; this function would
    # compose these transformers so we can pass a single function to `parse_walker`
    # function transformers(fns...)
    #     function (entirefn, parsed)
    #         for fn in fns
    #             result = fn(entirefn, parsed)
    #             !isnothing(result) && return result
    #         end
    #         return nothing
    #     end
    # end

    @inline function cleanup_named_tuple_type(str)
        if contains(str, "@NamedTuple")
            return parse_walker(revise_named_tuples, parse_brackets(str))
        end
        return str
    end
else
    @inline cleanup_named_tuple_type(str) = str
end

end
