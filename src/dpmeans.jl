module dpmeans
using Distributions, Random
using BSON
using Formatting: format

dropdim1(x) = dropdims(x, dims=1)
#= groupinds(x)
  for x isa Vector{Signed}.
  Extract the group of indices which match each unique value in x.
  Return, both the list of groups, and the unique elements they correspond to.
  adapted from GroupSlices.jl
 =#
function groupinds(ic::Vector{T}) where T <: Signed  # SignedInt
    d = Dict{T, T}()
    ia = unique(ic)
    n = length(ia)
    for i = 1:n
        d[ia[i]]= i
    end

    ib = Array{Vector{T}}(undef, n)
    for k = 1:n
        ib[k] = T[]
    end

    for h = 1:length(ic)
        push!(ib[d[ic[h]]], h)
    end
    return ib, ia
end


#=
  dist_to_centers.
  Helper function for dpmeans: calculate all distances ||x_i - μ_j|| over i, j.
 =#
function dist_to_centers(X::Matrix{T}, M::Matrix{T}; sq=false) where T <: Real
    n, d = size(X)
    k, _d2 = size(M)
    @assert (d == _d2) "X and M must have the same row dimension."

    X2    = sum(X .* X, dims=2)
    X_Mt  = X * M'
    M2    = sum(M .* M, dims=2)
    norm2 = (X2 .- 2X_Mt) .+ M2'
    if sq
        return norm2
    else
        return sqrt.(norm2)
    end
end


function dist_to_centers_colmajor(X::Matrix{T}, M::Matrix{T}; sq=false) where T <: Real
    d, n = size(X)
    _d2, k = size(M)
    @assert (d == _d2) "X and M must have the same row dimension."

    X2    = sum(X .* X, dims=1)
    X_Mt  = M' * X
    M2    = sum(M .* M, dims=1)
    norm2 = (X2 .- 2X_Mt) .+ M2'
    if sq
        return norm2
    else
        return sqrt.(norm2)
    end
end
#=
  row_mins.
  Helper function for dpmeans. Calculate the minimum of each row, and return
  the argmin in the second argument. MUCH MUCH faster than mapslices to
  `findmin`.
=#
function row_mins(X::Matrix{T}) where T <: Real
    n, d = size(X)
    out_v = Vector{T}(undef, n)
    out_ind = Vector{Int32}(undef, n)
    for nn = 1:n
        _min = X[nn, 1]
        _argmin = 1
        for dd = 2:d
            if X[nn, dd] < _min
                _min = X[nn, dd]
                _argmin = dd
            end
        end
        out_v[nn] = _min
        out_ind[nn] = _argmin
    end
    return out_v, out_ind
end


#=
  col_mins.
  Helper function for dpmeans. Calculate the minimum of each col, and return
  the argmin in the second argument. MUCH MUCH faster than mapslices to
  `findmin`.
=#
function col_mins(X::Matrix{T}) where T <: Real
    d, n = size(X)
    out_v = Vector{T}(undef, n)
    out_ind = Vector{Int32}(undef, n)
    for nn = 1:n
        _min = X[1, nn]
        _argmin = 1
        for dd = 2:d
            if X[dd, nn] < _min
                _min = X[dd, nn]
                _argmin = dd
            end
        end
        out_v[nn] = _min
        out_ind[nn] = _argmin
    end
    return out_v, out_ind
end


function pwise_mins(x::Vector{T}, y::Vector{T}, y_ind_id::Int32=Int32(2),
                    ind_if_x_wins::Union{Vector{Int32}, Nothing}=nothing,
                    val_if_x_wins::Union{Vector{T}, Nothing}=nothing) where T <: Real
    n = length(x)
    out_v = something(val_if_x_wins, copy(x))
    out_ind = something(ind_if_x_wins, ones(Int32, n))
    for nn = 1:n
        if x[nn] > y[nn]
            out_v[nn] = y[nn]
            out_ind[nn] = y_ind_id
        end
    end
    return out_v, out_ind
end

# function kpp_init(X::Array{Float64,2}, k::Int64)
#
#     n, d = size(X)
#     mu = zeros(k, d)
#     dist = Inf * ones(n)
#     λ = 1
#
#     idx = rand(1:n)
#     mu[1,:] = X[idx,:]
#     for i = 2:k
#         D = X .- mu[i-1,:]'
#         dist = min.(dist, sum(D.*D, dims=2))
#         idx_cond = rand() .< cumsum(dist/sum(dist))
#         idx_mu = findfirst(idx_cond)
#         mu[i,:] = X[idx_mu,:]
#         λ = maximum(dist)
#         println(λ)
#     end
#     return mu, λ
# end


# #= Batch version of dpmeans.
#     Nonparametric-like asymptotic σ->0 version of k-means with DP prior on k.
#     Loosely based / adapted from code originally written by Vadim Smolyakov.
#     https://github.com/vsmolyakov.
#     BATCH VERSION:
#     This actually works fairly poorly in general. A great counter example of why
#     one shouldn't do this is to imagine a dataset with a spherical distribution,
#     and initialising the first mean in the center. All points with distance λ from
#     the center will be moved to a new cluster, but the new cluster will also have
#     its mean.... at the center (or very close). Thus the routine will keep adding
#     new means without reducing the objective.
# =#
# function dpmeans_fit_batch(X::Array{T, 2}; k_init::Int64=3, max_iter::Int64=100) where T <: Number
#
#     #init params
#     k = k_init
#     n, d = size(X)
#
#     mu = mean(X, dims=1)
#     # display(mu)
#     # throw("Need to set lambda intelligently otherwise will continually add clusters.")
#     λ = 3
#     # mu, λ = kpp_init(X, k)
#
#     # println("lambda: ", λ)
#
#     obj = zeros(max_iter)
#     obj_tol = 1e-3
#
#     for iter = 1:max_iter
#         dist = zeros(n, k)
#
#         #assignment step
#         # custom functions are > order of magnitude faster
#         dist = dist_to_centers(X, mu; sq=true)
#         dmin, z = row_mins(dist)
#
#         #find(dist->dist==0, dist)
#         bad_idx = findall(dmin .> λ)
#         if length(bad_idx) > 0
#             k += 1
#             z[bad_idx] .= k
#             new_mean = mean(view(X, bad_idx, :), dims=1)
#             mu = vcat(mu, new_mean)
#             Xm = X .- new_mean
#             dist = hcat(dist, sum(Xm.*Xm, dims=2))
#         end
#
#         #update step
#         k_inds, ks = groupinds(z)
#         for j = 1:length(ks)
#             @views mu[ks[j],:] = mean(X[k_inds[j], :], dims=1)
#             @views obj[iter] += sum(dist[k_inds[j], ks[j]])
#         end
#         obj[iter] = obj[iter] + λ * k
#
#         #check convergence
#         if (iter > 1 && abs(obj[iter] - obj[iter-1]) < obj_tol * obj[iter])
#             println("converged in ", iter, " iterations.")
#             global Z = z
#             break
#         elseif iter == max_iter
#             @warn "DPmeans not converged"
#             global Z = z
#         end
#     end
#
#     return Z, mu, obj
# end


#= Gibbs version of dpmeans.
    Nonparametric-like asymptotic σ->0 version of k-means with DP prior on k.
    This version actually works, unlike the batch version! Recommend that the
    `shuffleX` option is used, as the algo is very sensitive to data order.
    Also there is a `collapse_thrsh` threshold which can remove small clusters
    if desired. I found these could be quite reasonable, and quite common, but
    annoying.

    > Expecting tall matrix: n * d. This is orders of magnitude slower than the
    default (wide) version for large matrices: it is not advised.
=#
function dpmeans_fit_tall(X::Matrix{T}; max_iter::Int=100, shuffleX::Bool=true,
                     lambda::T=1., collapse_thrsh::Int=0, suppress_warn=false) where T <: Number

    #init params
    k = 1
    n, d = size(X)
    @assert (n > d) "matrix must be arranged to be in tall format: n * d; found: tall format."

    # shuffling (and reordering for end)
    if shuffleX
        new_order = randperm(n)
        X = X[new_order, :]
        return_order(y::Vector) = y[sortperm(new_order)]
    else
        return_order = identity
    end

    mu = mean(X, dims=1)
    λ = lambda
    # mu, λ = kpp_init(X, k)

    obj = zeros(max_iter)
    nks = zeros(Int32, max_iter)

    obj_tol = 1e-3
    Z = Vector{Int}(undef, n)

    x_norm² = sum(X .* X, dims=2) |> _x -> dropdims(_x, dims=2)

    for iter = 1:max_iter

        # @timeit to "munorm" mu_norm² = sum(mu .* mu, dims=2)
        mu_terms = -2.0*X * mu' .+ sum(mu .* mu, dims=2)'
        c_mu_term_min, c_z = row_mins(mu_terms)

        for nn = 1:n
            dist = x_norm²[nn] + c_mu_term_min[nn]
            need_new_cls = dist > λ
            if need_new_cls
                k += 1
                # append new mean to mu
                mu = vcat(mu, X[nn,:]')
                addl_mu_terms = -2.0*X[nn:end,:] * X[nn,:] .+ sum(X[nn,:] .* X[nn,:])
                # update c_min / c_z
                c_mu_term_min[nn:end], c_z[nn:end] = pwise_mins(c_mu_term_min[nn:end], addl_mu_terms,
                                                                Int32(k), c_z[nn:end])
                dist = 0.
            end
            Z[nn] = c_z[nn]
            obj[iter] += dist
        end

        obj[iter] = obj[iter] + λ * k

        # update means
        k_inds, ks = groupinds(Z)
        for j = 1:length(ks)
            @views mu[ks[j],:] = mean(X[k_inds[j], :], dims=1)
        end
        nks[iter] = length(ks)

        #check convergence
        if (iter > 1 && abs(obj[iter] - obj[iter-1]) < obj_tol * obj[iter])
            # println("converged in ", iter, " iterations.")
            obj = obj[1:iter]
            nks = nks[1:iter]
            break
        elseif iter == max_iter
            !suppress_warn && @warn "DPmeans not converged"
        end
    end

    # collapse tiny clusters
    @info format("collapse thrsh is {:d}", collapse_thrsh)
    if collapse_thrsh > 0
        k_inds, ks = groupinds(Z)
        bad_ks_bool = map(length, k_inds) .< collapse_thrsh
        if sum(bad_ks_bool) > 0
            @info format("cluster(s) {:s} have <= 1 datapoint", findall(bad_ks_bool))
        end
        n_bad_k = sum(bad_ks_bool)
        if n_bad_k > 0
            bad_ixs = reduce(vcat, k_inds[findall(bad_ks_bool)])
            mu = mu[.!bad_ks_bool, :]

            dist = dist_to_centers(X[bad_ixs,:], mu; sq=true)
            _dmin, z = row_mins(dist)
            Z[bad_ixs] .= z
            nks[end] -= sum(bad_ks_bool)
            # not re-calculating obj because... who cares?
        end
    end
    return return_order(Z), mu, obj, nks
end


#= Gibbs version of dpmeans.
    Nonparametric-like asymptotic σ->0 version of k-means with DP prior on k.
    This version actually works, unlike the batch version! Recommend that the
    `shuffleX` option is used, as the algo is very sensitive to data order.
    Also there is a `collapse_thrsh` threshold which can remove small clusters
    if desired. I found these could be quite reasonable, and quite common, but
    annoying.
=#
function dpmeans_fit(X::Matrix{T}; max_iter::Int=100, shuffleX::Bool=true,
                     lambda::T=1., collapse_thrsh::Int=0, suppress_warn=false) where T <: Number

    #init params
    k = 1
    d, n = size(X)
    @assert (n > d) "matrix must be arranged to be in wide format: d * n; found: tall format."

    # shuffling (and reordering for end)
    if shuffleX
        new_order = randperm(n)
        X = X[:, new_order]
        return_order(y::Vector) = y[sortperm(new_order)]
    else
        return_order = identity
    end

    mu = mean(X, dims=2)
    λ = lambda

    obj = zeros(max_iter)
    nks = zeros(Int32, max_iter)

    obj_tol = 1e-3
    Z = Vector{Int}(undef, n)

    x_norm² = sum(X .* X, dims=1) |> dropdim1

    for iter = 1:max_iter

        # @timeit to "munorm" mu_norm² = sum(mu .* mu, dims=2)
        mu_terms = -2.0*mu'*X .+ sum(mu .* mu, dims=1)'
        c_mu_term_min, c_z = col_mins(mu_terms)

        for nn = 1:n
            dist = x_norm²[nn] + c_mu_term_min[nn]
            need_new_cls = dist > λ
            if need_new_cls
                k += 1
                # append new mean to mu
                mu = hcat(mu, X[:, nn])
                addl_mu_terms = -2.0*X[:, nn]' * X[:, nn:end] .+ sum(X[:, nn] .* X[:, nn]) |> dropdim1
                # update c_min / c_z
                c_mu_term_min[nn:end], c_z[nn:end] = pwise_mins(c_mu_term_min[nn:end], addl_mu_terms,
                                                                Int32(k), c_z[nn:end])
                dist = 0.
            end
            Z[nn] = c_z[nn]
            obj[iter] += dist
        end

        obj[iter] = obj[iter] + λ * k

        # update means
        k_inds, ks = groupinds(Z)
        for j = 1:length(ks)
            @views mu[:, ks[j]] = mean(X[:, k_inds[j]], dims=2)
        end
        nks[iter] = length(ks)

        #check convergence
        if (iter > 1 && abs(obj[iter] - obj[iter-1]) < obj_tol * obj[iter])
            # println("converged in ", iter, " iterations.")
            obj = obj[1:iter]
            nks = nks[1:iter]
            break
        elseif iter == max_iter
            !suppress_warn && @warn "DPmeans not converged"
        end
    end

    # collapse tiny clusters
    # bson("dbg/dpmean.bson", Z=Z, mu=mu, X=X)
    @info format("collapse thrsh is {:d}", collapse_thrsh)
    if collapse_thrsh > 0
        k_inds, ks = groupinds(Z)
        if minimum(ks) > 1   # only the first cluster can possibly be unused.
            mu = mu[:, 2:end]
            nks[end] -= 1
            k_inds, ks = groupinds(Z)
        end

        bad_ks_bool = map(length, k_inds) .< collapse_thrsh
        if sum(bad_ks_bool) > 0
            @info format("cluster(s) {:s} have <= 1 datapoint", findall(bad_ks_bool))
        end
        n_bad_k = sum(bad_ks_bool)
        # unlikely case that *all clusters* are too small
        !suppress_warn && n_bad_k == nks[end] && @warn "reducing collapse_thrsh as no clusters qualify"
        while n_bad_k == nks[end]
            collapse_thrsh *= 0.9
            bad_ks_bool = map(length, k_inds) .< collapse_thrsh
            n_bad_k = sum(bad_ks_bool)
        end
        if n_bad_k > 0
            bad_ixs = reduce(vcat, k_inds[findall(bad_ks_bool)])
            mu = mu[:, .!bad_ks_bool]

            dist = dist_to_centers_colmajor(X[:, bad_ixs], mu; sq=true)
            _dmin, z = col_mins(dist)
            Z[bad_ixs] .= z
            nks[end] -= sum(bad_ks_bool)
            # not re-calculating obj because... who cares?
        end
    end
    return return_order(Z), mu, obj, nks
end

end  # module
