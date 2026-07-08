module DataStructuresExt

using DataStructures
using StableHashTraits

# treat these objects as array types
for T in [:DeBitVector, :Dequeue, :CircularBuffer, :CircularDequeue, :Stack, :Queue]
    @eval function StableHashTraits.transformer(::Type{<:$T})
        return StableHashTraits.Transformer(identity, StableHashTraits.StructTypes.ArrayType())
    end
end

# order these objects
for T in [:OrderedDict, :OrderedSet, :SortedDict, :SortedMultiDict, :SortedSet]
    @eval StableHashTraits.is_ordered(::$T) = true
end

# treat these objects as dict types
for T in [:Accumulator, :BinaryMinHeap, :BinaryMaxHeap, :BinaryHeap, :DefaultDict, :PriorityQueue, :SortedMultiDict]
    @eval function StableHashTraits.transformer(::Type{<:$T})
        return StableHashTraits.Transformer(identity, StableHashTraits.StructTypes.DictType())
    end
end

end
