### A Pluto.jl notebook ###
# v0.19.36

using Markdown
using InteractiveUtils

# ╔═╡ 3592b099-9c96-4939-94b8-7ef2614b0955
import Pkg

# ╔═╡ 72871656-ae6e-11ee-2b23-251ac2aa38a3
begin
    Pkg.activate("/Users/davidlittle/Documents/beacon/StableHashTraits.jl-stable-plut")
    using StableHashTraits
end

# ╔═╡ 1c505fa8-75fa-4ed2-8c3f-43e28135b55d
begin
    bytes2hex_(x::Number) = x
	bytes2hex_(x) = bytes2hex(x)
end

# ╔═╡ b449d8e9-7ede-4171-a5ab-044c338ebae2
struct MyStruct end

# ╔═╡ 1e683f1d-f5f6-4064-970c-1facabcf61cc
StableHashTraits.stable_hash(MyStruct()) |> bytes2hex_

# ╔═╡ Cell order:
# ╠═3592b099-9c96-4939-94b8-7ef2614b0955
# ╠═72871656-ae6e-11ee-2b23-251ac2aa38a3
# ╠═1c505fa8-75fa-4ed2-8c3f-43e28135b55d
# ╠═b449d8e9-7ede-4171-a5ab-044c338ebae2
# ╠═1e683f1d-f5f6-4064-970c-1facabcf61cc
