#####
##### Internal Hash Algorithm Interface
#####

# This is a well defined interface that is used internally to compute hashes from bytes;
# each type of hashing function that `stable_hash` accepts is setup to implement it. (See
# bottom of this file for the implementations)

"""
    update_hash!(state::HashState, bytes)

Returns the updated hash state given a set of bytes (either a tuple or array of UInt8
values).

    update_hash!(state::HashState, obj, context)

Returns the updated hash, given an object and some context. The object will
be written to some bytes using `StableHashTraits.write(io, obj, context)`.
"""
function update_hash! end

# when a hasher has no internal buffer, we allocate one for each call to `update_hash!`
function update_hash!(hasher, x, context)
    io = IOBuffer()
    write(io, x, context)
    return update_hash!(hasher, take!(io))
end

"""
    HashState(alg, context)

Given a function that implements the hash algorithm to use and the current hash context,
setup the necessary state to track updates to hashing as we traverse an object's structure
and return it.
"""
abstract type HashState end

"""
    compute_hash!(state::HashState)

Return the final hash value to return for `state`
"""
function compute_hash! end

"""
    start_nested_hash!(state::HashState)

Return an updated state that delimits hashing of a nested structure; calls made to
`update_hash!` after start_nested_hash! will be handled as nested elements up until
`end_nested_hash!` is called.
"""
function start_nested_hash! end

"""
    end_nested_hash!(state::HashState)

Return an updated state that delimints the end of a nested structure.
"""
function end_nested_hash! end

"""
    similar_hash_state(state::HashState)

Akin to `similar` for arrays, this constructs a new object of the same concrete type
as `state`
"""
function similar_hash_state end

#####
##### SHA Hashing: support use of `sha256` and related hash functions
#####

for fn in filter(startswith("sha") ∘ string, names(SHA))
    CTX = Symbol(uppercase(string(fn)), :_CTX)
    if CTX in names(SHA)
        # we cheat a little here, technically `SHA_CTX` and friends are not `HashState`
        # but we make them satisfy the same interface below
        @eval function HashState(::typeof(SHA.$(fn)), context)
            root_version(context) < 2 && return SHA.$(CTX)()
            return BufferedHashState(SHA.$(CTX)())
        end
    end
end

# NOTE: while BufferedHashState is a faster implementation of `start/end_nested_hash!`
# we still need a recursive hash implementation to implement `HashVersion{1}()`
start_nested_hash!(ctx::SHA.SHA_CTX) = typeof(ctx)()
function update_hash!(sha::SHA.SHA_CTX, bytes::AbstractVector{UInt8})
    SHA.update!(sha, bytes)
    return sha
end
function end_nested_hash!(hash_state::SHA.SHA_CTX, nested_hash_state)
    SHA.update!(hash_state, SHA.digest!(nested_hash_state))
    return hash_state
end
compute_hash!(sha::SHA.SHA_CTX) = SHA.digest!(sha)
similar_hash_state(::T) where {T<:SHA.SHA_CTX} = T()

#####
##### RecursiveHashState: handles a function of the form hash64(bytes, [old_hash])
#####

function HashState(fn::Function, context)
    root_version(context) < 2 && return RecursiveHashState(fn)
    return BufferedHashState(RecursiveHashState(fn))
end

struct RecursiveHashState{F,T} <: HashState
    fn::F
    val::T
    init::T
end
function RecursiveHashState(fn)
    hash = fn(UInt8[])
    return RecursiveHashState(fn, hash, hash)
end
start_nested_hash!(x::RecursiveHashState) = RecursiveHashState(x.fn, x.init, x.init)
function update_hash!(hasher::RecursiveHashState, bytes::AbstractVector{UInt8})
    return RecursiveHashState(hasher.fn, hasher.fn(bytes, hasher.val), hasher.init)
end
function end_nested_hash!(fn::RecursiveHashState, nested::RecursiveHashState)
    return update_hash!(fn, reinterpret(UInt8, [nested.val;]))
end
compute_hash!(x::RecursiveHashState) = x.val
similar_hash_state(x::RecursiveHashState) = RecursiveHashState(x.fn, x.init, x.init)

#####
##### BufferedHashState: wrapper that buffers bytes before passing them to the hash algorithm
#####

mutable struct BufferedHashState{T} <: HashState
    content_hash_state::T
    delimiter_hash_state::T
    total_bytes_hashed::Int
    delimiters::Vector{Int} # delimits the start of nested structures (for `start_nested_hash!`), positive is start, negative is stop
    limit::Int # the preferred limit on the size of `io`'s buffer
    io::IOBuffer
end
const HASH_BUFFER_SIZE = 2^14
function BufferedHashState(state, size=HASH_BUFFER_SIZE)
    bytes = Vector{UInt8}(undef, size)
    delimiters = sizehint!(Vector{Int}(), 2size)
    io = IOBuffer(bytes; write=true, read=false)
    return BufferedHashState(state, similar_hash_state(state), 0, delimiters, size, io)
end

# flush bytes that are stored internally to the underlying hasher
function flush_bytes!(x::BufferedHashState, limit=x.limit - (x.limit >> 2))
    # the default `limit` tries to flush before the allocated buffer has to be increased in
    # size
    if position(x.io) ≥ limit
        x.total_bytes_hashed += position(x.io) # tack total number of bytes that have been hashed
        x.content_hash_state = update_hash!(x.content_hash_state, take!(x.io))
        # we copy reinterpreted because, e.g. `crc32c` will not accept a reinterpreted array
        # (and copying here does not noticeably worsen the benchmarks)
        x.delimiter_hash_state = update_hash!(x.delimiter_hash_state,
                                              copy(reinterpret(UInt8, x.delimiters)))

        empty!(x.delimiters)
    end
    return x
end

function start_nested_hash!(x::BufferedHashState)
    push!(x.delimiters, position(x.io) + x.total_bytes_hashed + 1) # position can be zero
    return x
end

function end_nested_hash!(root::BufferedHashState, x::BufferedHashState)
    push!(x.delimiters, -(position(x.io) + x.total_bytes_hashed + 1))
    return x
end

function update_hash!(hasher::BufferedHashState, obj, context)
    # TODO: when we remove `deprecated.jl`, change this to `Base.write` and remove the
    # `context` parameters
    write(hasher.io, obj, context)
    flush_bytes!(hasher)
    return hasher
end

function update_hash!(hasher::BufferedHashState, obj)
    write(hasher.io, obj)
    flush_bytes!(hasher)
    return hasher
end

function compute_hash!(x::BufferedHashState)
    flush_bytes!(x, 0)
    # recursively hash the delimiter hash state into the content hash
    delimiter_hash = compute_hash!(x.delimiter_hash_state)
    # we copy reinterpreted because, e.g. `crc32c` will not accept a reinterpreted array
    # (and copying here does not noticeably worsen the benchmarks)
    state = update_hash!(x.content_hash_state, copy(reinterpret(UInt8, [delimiter_hash;])))

    return compute_hash!(state)
end
function similar_hash_state(x::BufferedHashState)
    return BufferedHashState(similar_hash_state(x.content_hash_state), x.limit)
end
