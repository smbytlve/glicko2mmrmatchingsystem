-- ServerScriptService/Modules/Glicko2.lua
-- Glicko-2 implementation for Roblox (LuaU)

local Glicko2 = {}

-- ===== Tunables =====
Glicko2.TAU = 0.5              -- volatility constraint (0.3~1.2 정도가 흔함)
Glicko2.DEFAULT_R = 1500
Glicko2.DEFAULT_RD = 350
Glicko2.DEFAULT_SIGMA = 0.06

-- Glicko-2 constants
local PI = math.pi
local SCALE = 173.7178         -- r <-> mu 변환 상수

local function clamp(x, a, b)
	return math.max(a, math.min(b, x))
end

local function g(phi)
	return 1 / math.sqrt(1 + (3 * phi * phi) / (PI * PI))
end

local function E(mu, mu_j, phi_j)
	return 1 / (1 + math.exp(-g(phi_j) * (mu - mu_j)))
end

local function ratingToMu(r)
	return (r - 1500) / SCALE
end

local function rdToPhi(rd)
	return rd / SCALE
end

local function muToRating(mu)
	return mu * SCALE + 1500
end

local function phiToRd(phi)
	return phi * SCALE
end

-- f(x) used by volatility iteration
local function fFactory(delta, phi, v, a, tau)
	local function f(x)
		local ex = math.exp(x)
		local num = ex * (delta * delta - phi * phi - v - ex)
		local den = 2 * (phi * phi + v + ex) * (phi * phi + v + ex)
		return (num / den) - ((x - a) / (tau * tau))
	end
	return f
end

-- Robust root finding (Illinois / bisection hybrid)
local function solveForSigma(delta, phi, v, sigma, tau)
	local a = math.log(sigma * sigma)
	local f = fFactory(delta, phi, v, a, tau)

	local A = a
	local B

	if delta * delta > phi * phi + v then
		B = math.log(delta * delta - phi * phi - v)
	else
		-- find B such that f(B) < 0
		local k = 1
		B = A - k * tau
		while f(B) > 0 do
			k += 1
			B = A - k * tau
			if k > 100 then
				break
			end
		end
	end

	local fA = f(A)
	local fB = f(B)

	-- If fA and fB are not opposite, fallback to current sigma
	if fA * fB > 0 then
		return sigma
	end

	-- iterate
	local EPS = 1e-6
	for _ = 1, 60 do
		local C = (A + B) / 2
		local fC = f(C)

		if math.abs(B - A) < EPS then
			return math.exp(C / 2)
		end

		if fC * fA < 0 then
			B = C
			fB = fC
		else
			A = C
			fA = fC
		end
	end

	return sigma
end

-- ===== Public API =====
-- player: {r=number, rd=number, sigma=number}
-- results: array of matches
-- each match: {opp_r=number, opp_rd=number, score=number} score: 1 win / 0 lose / 0.5 draw
function Glicko2.update(player, results)
	local r = player.r or Glicko2.DEFAULT_R
	local rd = player.rd or Glicko2.DEFAULT_RD
	local sigma = player.sigma or Glicko2.DEFAULT_SIGMA

	-- Step 1: convert to Glicko-2 scale
	local mu = ratingToMu(r)
	local phi = rdToPhi(rd)

	-- If no games played: only RD increases by system? (period-based) - 여기서는 단순 유지
	if not results or #results == 0 then
		-- You can optionally inflate RD over time here.
		return {
			r = r,
			rd = rd,
			sigma = sigma,
		}
	end

	-- Step 2: compute v
	local v_inv = 0
	local delta_sum = 0

	for _, m in ipairs(results) do
		local mu_j = ratingToMu(m.opp_r)
		local phi_j = rdToPhi(m.opp_rd)
		local E_ = E(mu, mu_j, phi_j)
		local g_ = g(phi_j)
		v_inv += (g_ * g_) * E_ * (1 - E_)
	end

	local v = 1 / v_inv

	-- Step 3: delta
	for _, m in ipairs(results) do
		local mu_j = ratingToMu(m.opp_r)
		local phi_j = rdToPhi(m.opp_rd)
		local E_ = E(mu, mu_j, phi_j)
		local g_ = g(phi_j)
		delta_sum += g_ * (m.score - E_)
	end

	local delta = v * delta_sum

	-- Step 4: new sigma
	local sigmaPrime = solveForSigma(delta, phi, v, sigma, Glicko2.TAU)

	-- Step 5: phi* (pre-rating deviation)
	local phiStar = math.sqrt(phi * phi + sigmaPrime * sigmaPrime)

	-- Step 6: new phi, mu
	local phiPrime = 1 / math.sqrt((1 / (phiStar * phiStar)) + (1 / v))

	local muPrime = mu
	for _, m in ipairs(results) do
		local mu_j = ratingToMu(m.opp_r)
		local phi_j = rdToPhi(m.opp_rd)
		local E_ = E(mu, mu_j, phi_j)
		local g_ = g(phi_j)
		muPrime += (phiPrime * phiPrime) * g_ * (m.score - E_)
	end

	-- convert back
	local newR = muToRating(muPrime)
	local newRD = phiToRd(phiPrime)

	-- clamp RD reasonable bounds
	newRD = clamp(newRD, 30, 350)

	return {
		r = newR,
		rd = newRD,
		sigma = sigmaPrime,
	}
end

return Glicko2
