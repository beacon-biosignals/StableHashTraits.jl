module StableHashTraits

include("StableNames.jl")
using .StableNames: cleanup_name, NAMED_TUPLES_PRETTY_PRINT_VERSION

export stable_hash, WriteHash, IterateHash, StructHash, FnHash, ConstantHash, @ConstantHash,
       HashAndContext, HashVersion, qualified_name, qualified_type, TablesEq, ViewsEq,
       WithTypeNames,stable_typename_id, stable_type_id
using TupleTools, Tables, Compat, StructTypes
using SHA: SHA, sha256
using StructTypes: StructType

include("extract_readme_docs.jl")

include("public_interface.jl")
export stable_hash, HashVersion

include("caching_context.jl")
# CachingContext

include("hash_algorithms.jl")
# update_hash!, HashState, compute_hash!, start_nested_hash!, end_nested_hash!, similar_hash_state

include("hash_traits.jl")
# stable_hash_helper

include("deprecated.jl")
# old API: hash_method, FnHash, StructHash, etc...

include("special_contexts.jl")
# TablesEq and ViewsEq

end
