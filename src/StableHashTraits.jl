module StableHashTraits

include("StableNames.jl")
using .StableNames: cleanup_name, NAMED_TUPLES_PRETTY_PRINT_VERSION

using WeakKeyIdDicts
using TupleTools, Tables, Compat, StructTypes
using SHA: SHA, sha256
using StructTypes: StructType

const FULLY_CONCRETE_CACHE = Ref{IdDict{Type,Bool}}()
function __init__()
    return global FULLY_CONCRETE_CACHE[] = IdDict{Type,Bool}()
end

include("main_interface.jl")
export stable_hash, HashVersion, nameof_string, pick_fields, omit_fields
# main_interface defines: Transformer, transformer, transform_type, transform_type_value,
# @context, module_nameof_string

include("hash_algorithms.jl")
# hash_algorithms defines: update_hash!, HashState, compute_hash!, start_nested_hash!,
# end_nested_hash!, similar_hash_state

# deprecated type used by `hash_method` that needs to be defined earlier than the other
# `deprecated.jl` content (to be used for a deprecation check in `transformer_traits.jl`)
struct NotImplemented end
is_implemented(::NotImplemented) = false
is_implemented(_) = true

include("transformer_traits.jl")
# transformer_traits defines: stable_hash_helper, type_identifier, type_value_identifier,
# type_structure

include("hash_traits.jl")
export WriteHash, IterateHash, StructHash, FnHash, ConstantHash, @ConstantHash,
       HashAndContext, HashVersion, qualified_name, qualified_type, TablesEq, ViewsEq,
       stable_typename_id, stable_type_id

include("special_contexts.jl")
export TablesEq, ViewsEq, WithTypeNames

end
