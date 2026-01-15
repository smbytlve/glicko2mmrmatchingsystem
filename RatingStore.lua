-- ServerScriptService/Modules/RatingStore.lua

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")

local RatingStore = {}
RatingStore.__index = RatingStore

local STORE_NAME = "Glicko2Ratings_v1"

function RatingStore.new()
	local self = setmetatable({}, RatingStore)
	self._ds = DataStoreService:GetDataStore(STORE_NAME)
	self._cache = {} -- [userId] = {r, rd, sigma}
	return self
end

function RatingStore:_default()
	return { r = 1500, rd = 350, sigma = 0.06 }
end

function RatingStore:get(userId)
	if self._cache[userId] then
		return self._cache[userId]
	end

	local ok, data = pcall(function()
		return self._ds:GetAsync(tostring(userId))
	end)

	if ok and type(data) == "table" and data.r and data.rd and data.sigma then
		self._cache[userId] = data
		return data
	end

	local d = self:_default()
	self._cache[userId] = d
	return d
end

function RatingStore:set(userId, ratingTable)
	self._cache[userId] = ratingTable
end

function RatingStore:flush(userId)
	local data = self._cache[userId]
	if not data then return end

	local ok, err = pcall(function()
		self._ds:SetAsync(tostring(userId), data)
	end)

	if not ok then
		warn("[RatingStore] flush failed:", userId, err)
	end
end

function RatingStore:flushAll()
	for userId, _ in pairs(self._cache) do
		self:flush(userId)
	end
end

return RatingStore
