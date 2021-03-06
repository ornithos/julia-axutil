module Random

using Distributions, Sobol
using LinearAlgebra
using Random: GLOBAL_RNG, MersenneTwister
 #=================================================================================
                        Multinomial *Index* Sampling.

        (Returns the respective *indices* of the generated random nums
        as opp. to the *one-hot* representation as is usual for multinomial.)
 ==================================================================================#

function multinomial_indices(n::Int, p::Vector{Float64})
    #=  Returns the respective *indices* of the generated random nums
        as opp. to the *one-hot* representation as is usual for multinomial
        (adapted from Distributions.jl/src/samplers/multinomial.jl)
        -----------------------------------------------------------
        ===> Uses a binomial for each element of the multinomial
        vector. This is efficient when the number of trials is large,
        but if trials is small, and length is large, use `_linear` version.
    =#

    k = length(p)
    rp = 1.0  # remaining total probability
    i = 0
    km1 = k - 1
    x = zeros(Int32, n)
    op_ix = 1

    while i < km1 && n > 0
        i += 1
        @inbounds pi = p[i]
        if pi < rp
            xi = rand(Binomial(n, pi / rp))
            x[op_ix:(op_ix+xi-1)] .= i
            op_ix += xi
            n -= xi
            rp -= pi
        else
            # In this case, we don't even have to sample
            # from Binomial. Just assign remaining counts
            # to xi.
            x[op_ix:(op_ix+n-1)] .= i
            n = 0
        end
    end

    if i == km1
        x[op_ix:end] .= i+1
    end

    return xx
end


function smp_from_logprob(n_samples::Int, logp::Vector{Float64})
    #= multinomial sampling from log probability vector. Performs
       softmax and then multinomial sampling. Not sure why this
       has its own softmax calc: should be updated to use NNlibs.
    =#
    p = exp.(logp .- maximum(logp))
    p /= sum(p)
    return multinomial_indices(n_samples, p)
end


function multinomial_indices_linear(n::Int, p::AbstractArray)
    #= multinomial sampling for when n is small, and length(p)
       is large. This performs n * (linear) scans of
       the vector `p`, with very little extra overhead.
       More efficiency could be achieved here with larger n.
    =#
    m = length(p)
    x = zeros(Int32, n)

    function linearsearch(p::AbstractArray, m::Int64, rn)
        cs = 0.0
        for ii in 1:m
            @inbounds cs += p[ii]
            if cs > rn
                return ii
            end
        end
        return m
    end

    for i in 1:n
        rn = rand()
        @inbounds x[i] = linearsearch(p, m, rn)
    end
    return x
end


function multinomial_indices_binsearch(n::Int, p::Vector{T}) where T <: AbstractFloat
    #= multinomial sampling that makes sense if n ≈ 10.
       Calculates the cumsum of probabilities and uses binary search on a
       uniform random for each draw to return the index.
    =#
    x = zeros(Int32, n)
    cump = cumsum(p)
    for i in 1:n
        x[i] = searchsortedfirst(cump, rand()*cump[end])
    end
    return x
end


#=================================================================================
                        Quasi Monte Carlo
 ==================================================================================#

randomised_sobol(n, d) = randomised_sobol(GLOBAL_RNG, n, d)
uniform_rand_sobol(n, lims...) = uniform_rand_sobol(GLOBAL_RNG, n, lims...)
sobol_gaussian(n, d) = sobol_gaussian(GLOBAL_RNG, n, d)

function randomised_sobol(rng::MersenneTwister, n, d)
    s = SobolSeq(d)
    p = reduce(hcat, [next!(s) for i = 1:n])
    ϵ = rand(rng, d)
    prand = [(p[j,:] .+ ϵ[j]) .% 1.0 for j in 1:d]
    return hcat(prand...)
end

# randomised Sobol within rectangle
function uniform_rand_sobol(rng::MersenneTwister, n, lims...)
    d = length(lims)
    rsob = randomised_sobol(rng, n, d)
    for (i, interval) in enumerate(lims)
        @assert (length(interval) == 2) format("interval {:d} does not have length 2", i)
        rsob[:,i] .*= diff(interval)
        rsob[:,i] .+= interval[1]
    end
    return rsob
end

# randomised Sobol Gaussian random variates
function sobol_gaussian(rng::MersenneTwister, n, d)
    (n == 0) && return zeros(d,0)'
    s = SobolSeq(d)
    p = reduce(hcat, [next!(s) for i = 1:n])
    ϵ = rand(rng, d)
    prand = [(p[j,:] .+ ϵ[j]) .% 1.0 for j in 1:d]
    p = reduce(vcat, [quantile.(Normal(), prand[j])' for j in 1:d])'
    return p
end

#=================================================================================
                                Misc stuff
 ==================================================================================#

function psd_matrix(d; ϵ=0.)
    A = randn(d, d)
    U = eigvecs((A + A')/2) # (Don't really have to divide by 2)
    P = U*diagm(0=>abs.(randn(d)) .+ ϵ)*U';
    return (P + P')/2
end


end  # module
