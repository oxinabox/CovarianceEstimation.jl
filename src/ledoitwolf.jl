"""
    LedoitWolf()

Ledoit-Wolf covariance estimator target type.
"""
struct LedoitWolf <: TargetType end

function lw_optimalshrinkage(Xc::AbstractMatrix, S::AbstractMatrix,
                             s::AbstractVector, F::AbstractMatrix,
                             r::Real, n::Int, p::Int)
    # steps leading to equation 5 of http://www.ledoit.net/honey.pdf in
    # appendix B. (notations follow the paper)
    tmat  = @inbounds [(Xc[t,:] * Xc[t,:]' - S) for t ∈ 1:n]
    π̂mat  = sum(tmat[t].^2 for t ∈ 1:n) / n
    π̂     = sum(π̂mat)
    dS    = diag(S)
    tdiag = @inbounds [Diagonal(Xc[t,:].^2 - dS) for t ∈ 1:n]
    ϑ̂ᵢᵢ   = @inbounds sum(tdiag[t] * tmat[t] for t ∈ 1:n) / n # row scaling
    ϑ̂ⱼⱼ   = @inbounds sum(tmat[t] * tdiag[t] for t ∈ 1:n) / n # col scaling
    ρ̂₂    = zero(eltype(Xc))
    @inbounds for i ∈ 1:p, j ∈ 1:p
        (j == i) && continue
        αᵢⱼ = s[j]/s[i]
        ρ̂₂ += ϑ̂ᵢᵢ[i,j]*αᵢⱼ + ϑ̂ⱼⱼ[i,j]/αᵢⱼ
    end
    ρ̂ = sum(diag(π̂mat)) + (r/2)*ρ̂₂
    γ̂ = sum((F - S).^2)
    # if γ̂ is very small it may lead to NaNs or infinities
    (γ̂ ≤ eps()) && return ifelse(π̂ ≤ ρ̂, 0.0, 1.0)
    κ̂ = (π̂ - ρ̂)/γ̂
    return clamp(κ̂/n, 0.0, 1.0)
end

function lw_shrinkagetarget(S::AbstractMatrix, s::AbstractVector, p::Int)
    s_ = @inbounds [s[i]*s[j] for i ∈ 1:p, j ∈ 1:p]
    r  = (sum(S ./ s_) - p)/(p * (p - 1))
    F_ = s_ .* r
    F  = F_ + Diagonal(diag(s_) .- diag(F_))
    return F, r
end

"""
    targetandshrinkage(::LedoitWolf, X::AbstractMatrix; dims::Int=1)

Calculates shrunk covariance matrix for data in `X` with Ledoit-Wolf
optimal shrinkage.

# Arguments
- `dims::Int`: the dimension along which the variables are organized.
When `dims = 1`, the variables are considered columns with observations
in rows; when `dims = 2`, variables are in rows with observations in columns.

Implements shrinkage target and optimal shrinkage according to
O. Ledoit and M. Wolf, “Honey, I Shrunk the Sample Covariance Matrix,”
The Journal of Portfolio Management, vol. 30, no. 4, pp. 110–119, Jul. 2004.
"""
function targetandshrinkage(lw::LedoitWolf, S::AbstractMatrix{<:Real},
                            X::AbstractMatrix{<:Real})
    n, p = size(X)
    s    = sqrt.(diag(S))
    # shrinkage
    F, r = lw_shrinkagetarget(S, s, p)
    ρ    = lw_optimalshrinkage(X, S, s, F, r, n, p)
    return F, ρ
end
