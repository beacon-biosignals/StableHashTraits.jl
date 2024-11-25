module TimeZonesExt

using TimeZones
using TimeZones.Dates
using StableHashTraits
using StableHashTraits: Transformer

# don't change existing hashes; keep hash version 4 the same; this method is very
# inefficient as it leads StableHashTraits to hash a very large object that has to track the
# history of time zones. We don't' want to break old hashes since this isn't really an
# inaccurate hash (worthy of being called a bug), but merely a very slow hash to calculate
function StableHashTraits.transformer(::Type{<:ZonedDateTime}, ::HashVersion{4})
    return Transformer(identity)
end

# NOTE: by default we consider identical "absolute" times as the same time (e.g. 1:00 pm
# UTC+1:00, is the same as 2:00pm UTC+0:00).
function StableHashTraits.transformer(::Type{<:ZonedDateTime})
    return Transformer(x -> DateTime(x, UTC); hoist_type=true)
end

end
