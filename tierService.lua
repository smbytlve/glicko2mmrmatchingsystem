-- ServerScriptService/Modules/TierService.lua

local TierService = {}

-- 티어 커트라인 예시 (원하는대로 조정)
-- 기준은 "effective = r - RD" (불확실성 큰 유저는 보수적으로 낮게 반영)
TierService.BANDS = {
	{ name = "Bronze",  min = -math.huge },
	{ name = "Silver",  min = 1300 },
	{ name = "Gold",    min = 1500 },
	{ name = "Platinum",min = 1700 },
	{ name = "Diamond", min = 1900 },
	{ name = "Master",  min = 2100 },
}

TierService.RD_WEIGHT = 1.0

function TierService.effective(rating)
	local r = rating.r
	local rd = rating.rd
	return r - TierService.RD_WEIGHT * rd
end

function TierService.getTier(rating)
	local eff = TierService.effective(rating)
	local current = TierService.BANDS[1].name
	for _, band in ipairs(TierService.BANDS) do
		if eff >= band.min then
			current = band.name
		end
	end
	return current, eff
end

return TierService
