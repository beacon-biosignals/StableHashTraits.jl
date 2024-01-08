### A Pluto.jl notebook ###
# v0.19.36

using Markdown
using InteractiveUtils

# ╔═╡ 3592b099-9c96-4939-94b8-7ef2614b0955
import Pkg

# ╔═╡ 72871656-ae6e-11ee-2b23-251ac2aa38a3
begin
    Pkg.activate("StableHashTraits.jl")
    using StableHashTraits
end

# ╔═╡ b449d8e9-7ede-4171-a5ab-044c338ebae2
struct MyStruct end

# ╔═╡ 1e683f1d-f5f6-4064-970c-1facabcf61cc
StableHashTraits.stable_hash(MyStruct()) |> bytes2hex

# ╔═╡ Cell order:
# ╠═3592b099-9c96-4939-94b8-7ef2614b0955
# ╠═72871656-ae6e-11ee-2b23-251ac2aa38a3
# ╠═b449d8e9-7ede-4171-a5ab-044c338ebae2
# ╠═1e683f1d-f5f6-4064-970c-1facabcf61cc
