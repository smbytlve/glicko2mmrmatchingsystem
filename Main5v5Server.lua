-- ServerScriptService/Main5v5.server.lua

local Players = game:GetService("Players")

local Glicko2 = require(script.Parent.Modules.Glicko2)
local RatingStore = require(script.Parent.Modules.RatingStore)
local TierService = require(script.Parent.Modules.TierService)
local MatchmakingService5v5 = require(script.Parent.Modules.MatchmakingService5v5)

local store = RatingStore.new()
local mm = MatchmakingService5v5.new(store)

-- ====== 실제 게임에선 라운드 종료 시점에 이 함수를 호출하면 됨 ======
-- winningTeam: "A" or "B"
local function ReportMatchResult(matchId, winningTeam)
	local match = mm:getMatch(matchId)
	if not match or match.state ~= "CREATED" then
		return
	end
	match.state = "FINISHED"

	local teamA = match.teamA
	local teamB = match.teamB
	local oppA = match.teamAvgB
	local oppB = match.teamAvgA

	local scoreA = (winningTeam == "A") and 1.0 or 0.0
	local scoreB = 1.0 - scoreA

	-- update each player vs opponent team average
	for _, e in ipairs(teamA) do
		if e and e.player and e.player.Parent == Players then
			local current = store:get(e.userId)
			local newRating = Glicko2.update(current, {
				{ opp_r = oppA.r, opp_rd = oppA.rd, score = scoreA }
			})
			store:set(e.userId, newRating)
			store:flush(e.userId)
		end
	end

	for _, e in ipairs(teamB) do
		if e and e.player and e.player.Parent == Players then
			local current = store:get(e.userId)
			local newRating = Glicko2.update(current, {
				{ opp_r = oppB.r, opp_rd = oppB.rd, score = scoreB }
			})
			store:set(e.userId, newRating)
			store:flush(e.userId)
		end
	end

	-- summary log
	for _, e in ipairs(teamA) do
		local r = store:get(e.userId)
		local tier, eff = TierService.getTier(r)
		print(("[RESULT] A %s -> R=%.1f RD=%.1f eff=%.1f tier=%s")
			:format(e.player.Name, r.r, r.rd, eff, tier))
	end
	for _, e in ipairs(teamB) do
		local r = store:get(e.userId)
		local tier, eff = TierService.getTier(r)
		print(("[RESULT] B %s -> R=%.1f RD=%.1f eff=%.1f tier=%s")
			:format(e.player.Name, r.r, r.rd, eff, tier))
	end

	mm:closeMatch(matchId)
end

mm.OnMatchCreated = function(match)
	-- match.teamA/teamB는 entry 배열. entry.player로 접근.
	local namesA, namesB = {}, {}
	for _, e in ipairs(match.teamA) do table.insert(namesA, e.player.Name) end
	for _, e in ipairs(match.teamB) do table.insert(namesB, e.player.Name) end

	print(("=== MATCH %s CREATED ==="):format(match.matchId))
	print(("TeamA (%d): %s"):format(#namesA, table.concat(namesA, ", ")))
	print(("TeamB (%d): %s"):format(#namesB, table.concat(namesB, ", ")))
	print(("Balance diff (sum eff): %.1f"):format(match.balanceDiff))
	print(("TeamAvgA: R=%.1f RD=%.1f | TeamAvgB: R=%.1f RD=%.1f")
		:format(match.teamAvgA.r, match.teamAvgA.rd, match.teamAvgB.r, match.teamAvgB.rd))

	-- 여기서 TeleportService로 경기 서버로 보내거나, 팀 지정/스폰 배치를 하면 됨.
	-- 테스트용: 10초 뒤 랜덤 승리
	task.delay(10, function()
		local winningTeam = (math.random() < 0.5) and "A" or "B"
		print(("=== MATCH %s FINISH: Winner %s ==="):format(match.matchId, winningTeam))
		ReportMatchResult(match.matchId, winningTeam)
	end)
end

mm:start()

-- ===== 테스트 커맨드 =====
Players.PlayerAdded:Connect(function(plr)
	plr.Chatted:Connect(function(msg)
		msg = msg:lower()
		if msg == "/queue" then
			local ok = mm:enqueue(plr)
			if ok then
				local r = store:get(plr.UserId)
				local tier, eff = TierService.getTier(r)
				print(("[QUEUE] %s | R=%.1f RD=%.1f eff=%.1f tier=%s"):format(plr.Name, r.r, r.rd, eff, tier))
			end
		elseif msg == "/leave" then
			mm:dequeue(plr)
			print("[QUEUE] left:", plr.Name)
		elseif msg == "/rating" then
			local r = store:get(plr.UserId)
			local tier, eff = TierService.getTier(r)
			print(("[RATING] %s | R=%.1f RD=%.1f sigma=%.4f eff=%.1f tier=%s")
				:format(plr.Name, r.r, r.rd, r.sigma, eff, tier))
		end
	end)
end)

game:BindToClose(function()
	store:flushAll()
end)
