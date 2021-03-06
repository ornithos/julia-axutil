module Arr

using LinearAlgebra
using Formatting: format

arange(start; kwargs...) = collect(range(start; kwargs...))

unpack_arr(x::AbstractArray) = [x[:,i] for i in range(1,stop=size(x,2))]
hstack(x) = reduce(hcat, x)
vstack(x) = reduce(vcat, x)
eye(d) = Matrix(I, d, d)

arr2str(X::Vector{T}; digits=2) where T <: Number = "[" * join(map(x->format("{:." * string(digits) * "f}", x), X), ",") * "]"
arr2str(X::Number; digits=2) = "(scalar) " * format("{:." * string(digits) * "f}", X)

@inline zero_arrays!(x::Array{T, 1}) where T <: AbstractArray = for y in x; zero_arrays!(y); end
@inline zero_arrays!(x::Array{T, 1}) where T <: Real = (x .= 0.);
@inline zero_arrays!(x::Array{T, 2}) where T <: Real = (x .= 0.);
end
