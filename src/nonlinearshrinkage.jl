"""
    AnalyticalNonlinearShrinkage

Analytical nonlinear shrinkage estimator. See docs for
`analytical_nonlinear_shrinkage` for details.
"""
struct AnalyticalNonlinearShrinkage{TEigen<:Union{Eigen,Nothing}} <: CovarianceEstimator
    decomp::TEigen
    corrected::Bool
    function AnalyticalNonlinearShrinkage(;corrected=false)
        new{Nothing}(nothing, corrected)
    end
    function AnalyticalNonlinearShrinkage(decomp::Eigen; corrected=false)
        new{Eigen}(decomp, corrected)
    end
end


const SQRT5  = sqrt(5.0)
const INVPI  = 1.0 / π
const EPAN_1 = 3.0/(4.0 * SQRT5)
const EPAN_2 = EPAN_1 * INVPI
const EPAN_3 = 0.3 * INVPI

"""
    epanechnikov(x)

Return the Epanechnikov kernel evaluated at `x`.
"""
epanechnikov(x::Real) = EPAN_1 * max(0.0, 1.0 - x^2/5.0)

"""
    epnanechnikov_HT(x)

Return the Hilbert Transform of the Epanechnikov kernel evaluated at `x`
if `|x|≂̸√5`.
"""
function epanechnikov_HT1(x::Real)
    -EPAN_3 * x + EPAN_2 * (1.0 - x^2/5.0) * log(abs((SQRT5 - x)/(SQRT5 + x)))
end


"""
    analytical_nonlinear_shrinkage(S; decomp)

Internal implementation of the analytical nonlinear shrinkage. The
implementation is inspired from the Matlab code given in section C of
Olivier Ledoit and Michael Wolf's paper "Analytical Nonlinear
Shrinkage of Large-Dimensional Covariance Matrices". (Nov 2018)
http://www.econ.uzh.ch/static/wp/econwp264.pdf
"""
function analytical_nonlinear_shrinkage(S::AbstractMatrix{<:Real},
                                        n::Int, p::Int;
                                        decomp::Union{Nothing,Eigen}=nothing)

    # sample eigenvalues sorted in ascending order and eigenvectors
    F    = isa(decomp, Nothing) ? eigen(S) : decomp # O(p^3)
    perm = sortperm(F.values)
    λ    = F.values[perm]
    U    = F.vectors[:, perm]

    # dominant cost forming of S or eigen(S) --> O(max{np^2, p^3})

    # compute analytical nonlinear shrinkage kernel formula
    η = ifelse(p < n, n, n-1) # effective sample size
    λ = λ[max(1, (p - η) + 1):p]
    L = repeat(λ, outer=(1, min(p, η)))

    # Equation (4.9)
    h = η^(-1//3)
    H = h * L'
    x = (L - L') ./ H

    # additional useful definitions
    γ  = p/η
    πλ = π * λ

    # Equation (4.7) in http://www.econ.uzh.ch/static/wp/econwp264.pdf
    f̃ = mean(epanechnikov.(x) ./ H, dims=2)[:]

    # Equation (4.8)
    Hf̃_tmp = epanechnikov_HT1.(x)
    # if by any chance there are x such that |x| ≈ √5 ...
    mask = (@. abs(x) ≈ SQRT5)
    any(mask) && (Hf̃_tmp[mask] = epanechnikov_HT2.(x[mask]))
    Hf̃ = mean(Hf̃_tmp ./ H, dims=2)[:]

    # dominant cost up to here: elementwise ops on x --> O(max{p^2, η^2})

    if p < n
        # Equation (4.3)
        πγλ = γ * πλ
        denom = @. (πγλ * f̃)^2 + (1.0 - γ - πγλ * Hf̃)^2
        d̃ = λ ./ denom
    else
        # Equation (C.8)
        hs5  = h * SQRT5
        Hf̃0  = (0.3/h^2 + 0.75/hs5 * (1.0 - 0.2/h^2) * log((1+hs5)/(1-hs5)))
        Hf̃0 *= mean(1.0 ./ πλ)
        # Equation (C.5)
        d̃0 = INVPI / ((γ - 1.0) * Hf̃0)
        # Eq. (C.4)
        d̃1 = @. 1.0 / (π * πλ * (f̃^2 + Hf̃^2))
        d̃  = [d̃0 * ones(p - η, 1); d̃1]
    end

    # Equation (4.4)
    return U*(d̃ .* U')
end

"""
    cov(X, ans::AnalyticalNonlinearShrinkage; dims=1)

Nonlinear covariance estimator derived from the sample covariance estimator `S`
and its eigenvalue decomposition (which can be given through `decomp`).
See Ledoit and Wolf's paper http://www.econ.uzh.ch/static/wp/econwp264.pdf

* Time complexity (including formation of `S`)
    - (p<n): O(np^2 + n^2) with moderate constant
    - (p>n): O(p^3) with low constant (dominated by eigendecomposition of S)
"""
function cov(X::AbstractMatrix{<:Real}, ans::AnalyticalNonlinearShrinkage;
             dims::Int=1, mean=nothing)

    @assert dims ∈ [1, 2] "Argument dims can only be 1 or 2 (given: $dims)"

    szx    = size(X)
    (n, p) = ifelse(dims==1, szx, reverse(szx))

    # explained in the paper there must be at least 12 samples
    (n < 12) && throw(ArgumentError("The number of samples `n` must be at " *
                                    "least 12 (given: $n)."))

    S  = cov(X, Simple(corrected=ans.corrected); dims=dims, mean=mean)
    return analytical_nonlinear_shrinkage(S, n, p; decomp=ans.decomp)
end
