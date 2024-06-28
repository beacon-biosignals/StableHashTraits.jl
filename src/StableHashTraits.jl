module StableHashTraits

include("StableNames.jl")
using .StableNames: cleanup_name, NAMED_TUPLES_PRETTY_PRINT_VERSION

using TupleTools, Tables, Compat
using SHA: SHA, sha256

include("copy_readme_to_docs.jl")

include("main_interface.jl")
export stable_hash, HashVersion

include("hash_algorithms.jl")
# update_hash!, HashState, compute_hash!, start_nested_hash!, end_nested_hash!, similar_hash_state

include("caching_context.jl")
export CachedHash
# StableHashTraits.UseCache

include("hash_traits.jl")
export HashAndContext, stable_typename_id, stable_type_id,
       WriteHash, IterateHash, StructHash, FnHash, ConstantHash, @ConstantHash,
       qualified_name, qualified_type # these two are deprecated
# stable_hash_helper

include("special_contexts.jl")
export TablesEq, ViewsEq

end
