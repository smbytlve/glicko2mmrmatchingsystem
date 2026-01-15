-- ServerScriptService/Modules/MatchmakingService5v5.lua

local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")

local TierService = require(script.Parent.TierService)

local MatchmakingService5v5 = {}
MatchmakingService5v5.__index = MatchmakingService5v5

-- ===== Tunables =====
local TEAM_SIZE = 5
local MATCH_SIZE = TEAM_SIZE * 2

local BASE_RANGE = 80        -- 처음 허용범위(±)
local RANGE_PER_SEC = 8      -- 대기 1초당 허용범위 확장
local MAX_RANGE = 800

local TICK_RATE = 1.0

local function now()
	return os.clock()
end

local function getRange(waitSec)
	local range = BASE_RANGE + RANGE_PER_SEC * waitSec
	return math.min(range, MAX_RANGE)
end

local function isValidPlayer(p)
	return p and p.Parent == Players
end

-- 10명 eff 합 차 최소화: 10C5=252 전수로 최적 분할
local function bestSplit10(entries)
	-- entries: array size 10, each has .eff
	local n = 10
	local bestMask = nil
	local bestDiff = math.huge

	-- precompute total sum
	local total = 0
	for i = 1, n do
		total += entries[i].eff
	end

	-- choose 5 of 10 => mask bits 1..10
	-- iterate combinations using bitmask from 0..(2^10-1)
	-- only masks with popcount=5
	for mask = 0, (1 << n) - 1 do
		-- quick popcount
		local c = 0
		local tmp = mask
		while tmp ~= 0 do
			tmp = tmp & (tmp - 1)
			c += 1
		end
		if c == 5 then
			local sumA = 0
			for i = 1, n do
				if (mask & (1 << (i - 1))) ~= 0 then
					sumA += entries[i].eff
				end
			end
			local sumB = total - sumA
			local diff = math.abs(sumA - sumB)
			if diff < bestDiff then
				bestDiff = diff
				bestMask = mask
				if bestDiff <= 1 then -- 거의 완벽하면 조기 종료
					break
				end
			end
		end
	end

	local teamA, teamB = {}, {}
	for i = 1, n do
		if (bestMask & (1 << (i - 1))) ~= 0 then
			table.insert(teamA, entries[i])
		else
			table.insert(teamB, entries[i])
		end
	end

	return teamA, teamB, bestDiff
end

local function avgTeamRating(teamEntries)
	-- teamEntries: entries with .rating = {r,rd,sigma}
	-- 팀 평균을 단순 평균으로 (실무에서 흔함)
	local sumR, sumRD = 0, 0
	for _, e in ipairs(teamEntries) do
		sumR += e.rating.r
		sumRD += e.rating.rd
	end
	local n = #teamEntries
	return {
		r = sumR / n,
		rd = sumRD / n,
		-- sigma는 팀 평균으로 굳이 안 써도 됨(업데이트 입력엔 opp_r, opp_rd만 사용)
	}
end

function MatchmakingService5v5.new(ratingStore)
	local self = setmetatable({}, MatchmakingService5v5)
	self._store = ratingStore
	self._queue = {}      -- entries array
	self._inQueue = {}    -- [userId]=true
	self._running = false

	self._activeMatches = {} -- [matchId] = matchTable

	-- hooks
	self.OnMatchCreated = function(match) end

	return self
end

function MatchmakingService5v5:enqueue(player)
	local userId = player.UserId
	if self._inQueue[userId] then return false end
	if not isValidPlayer(player) then return false end

	local rating = self._store:get(userId)
	local _, eff = TierService.getTier(rating)

	local e = {
		player = player,
		userId = userId,
		joinAt = now(),
		rating = rating,
		eff = eff,
	}

	table.insert(self._queue, e)
	self._inQueue[userId] = true
	return true
end

function MatchmakingService5v5:dequeue(player)
	local userId = player.UserId
	if not self._inQueue[userId] then return false end

	self._inQueue[userId] = nil
	for i = #self._queue, 1, -1 do
		if self._queue[i].userId == userId then
			table.remove(self._queue, i)
			break
		end
	end
	return true
end

function MatchmakingService5v5:isQueued(player)
	return self._inQueue[player.UserId] == true
end

function MatchmakingService5v5:_clean()
	for i = #self._queue, 1, -1 do
		local e = self._queue[i]
		if not isValidPlayer(e.player) then
			self._inQueue[e.userId] = nil
			table.remove(self._queue, i)
		end
	end
end

function MatchmakingService5v5:_allowedTogether(a, b)
	local waitA = now() - a.joinAt
	local waitB = now() - b.joinAt
	local rangeA = getRange(waitA)
	local rangeB = getRange(waitB)
	local allowed = math.min(rangeA, rangeB)
	return math.abs(a.eff - b.eff) <= allowed
end

function MatchmakingService5v5:_tryMakeMatch()
	if #self._queue < MATCH_SIZE then return end

	-- eff 기준 정렬
	table.sort(self._queue, function(x, y)
		return x.eff < y.eff
	end)

	-- 전략: 큐에서 연속된 10명 윈도우를 훑어서
	-- "서로 허용범위 내로 묶일 수 있는" 10명을 찾는다.
	for startIdx = 1, (#self._queue - MATCH_SIZE + 1) do
		local window = {}
		for i = startIdx, startIdx + MATCH_SIZE - 1 do
			table.insert(window, self._queue[i])
		end

		-- window 내 최소/최대가 너무 멀면 매치 불가(대기시간에 따라 완화되긴 함)
		-- 보다 안전하게: window 양 끝이 서로 허용범위로 연결 가능한지 체크
		if self:_allowedTogether(window[1], window[#window]) then
			-- 최적 5:5 분할
			local teamA, teamB, diff = bestSplit10(window)
			local teamAvgA = avgTeamRating(teamA)
			local teamAvgB = avgTeamRating(teamB)

			-- 큐에서 window 제거 (뒤에서부터 제거)
			for i = startIdx + MATCH_SIZE - 1, startIdx, -1 do
				local removed = table.remove(self._queue, i)
				self._inQueue[removed.userId] = nil
			end

			local matchId = HttpService:GenerateGUID(false)
			local match = {
				matchId = matchId,
				createdAt = now(),
				teamA = teamA, -- entries
				teamB = teamB,
				teamAvgA = teamAvgA,
				teamAvgB = teamAvgB,
				balanceDiff = diff,
				state = "CREATED",
			}

			self._activeMatches[matchId] = match

			task.spawn(function()
				self.OnMatchCreated(match)
			end)

			return
		end
	end
end

function MatchmakingService5v5:start()
	if self._running then return end
	self._running = true
	task.spawn(function()
		while self._running do
			self:_clean()
			self:_tryMakeMatch()
			task.wait(TICK_RATE)
		end
	end)
end

function MatchmakingService5v5:stop()
	self._running = false
end

function MatchmakingService5v5:getMatch(matchId)
	return self._activeMatches[matchId]
end

function MatchmakingService5v5:closeMatch(matchId)
	self._activeMatches[matchId] = nil
end

return MatchmakingService5v5
