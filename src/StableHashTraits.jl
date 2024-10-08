module StableHashTraits

using TupleTools, Tables, Compat, StructTypes
using SHA: SHA, sha256
using StructTypes: StructType

include("main_interface.jl")
export stable_hash, HashVersion, nameof_string, pick_fields, omit_fields
# main_interface defines: Transformer, transformer, transform_type, transform_type_value,
# @context, module_nameof_string

include("transformer_traits.jl")
# transformer_traits defines: stable_hash_helper, type_identifier, type_value_identifier,
# type_structure

include("hash_algorithms.jl")
# hash_algorithms defines: update_hash!, HashState, compute_hash!, start_nested_hash!,
# end_nested_hash!, similar_hash_state

include("special_contexts.jl")
export TablesEq, ViewsEq, WithTypeNames

end
