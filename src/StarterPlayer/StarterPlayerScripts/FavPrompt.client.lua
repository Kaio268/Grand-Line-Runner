local Players = game:GetService("Players")
local AvatarEditorService = game:GetService("AvatarEditorService")

local player = Players.LocalPlayer

local PROMPT_THRESHOLD_SECONDS = 200
local GAME_FAVORITE_ID = game.PlaceId
local GAME_FAVORITE_TYPE = Enum.AvatarItemType.Asset

local totalStats = player:WaitForChild("TotalStats")
local timePlayed = totalStats:WaitForChild("TimePlayed")
local lastTimePlayed = tonumber(timePlayed.Value) or 0
local promptedThisSession = false

local function getTimePlayed()
	return tonumber(timePlayed.Value) or 0
end

local function crossedPromptThreshold(currentTimePlayed)
	return lastTimePlayed < PROMPT_THRESHOLD_SECONDS and currentTimePlayed >= PROMPT_THRESHOLD_SECONDS
end

local function promptFavoriteGame()
	if GAME_FAVORITE_ID <= 0 then
		return
	end

	local ok, err = pcall(function()
		AvatarEditorService:PromptSetFavorite(GAME_FAVORITE_ID, GAME_FAVORITE_TYPE, true)
	end)

	if not ok then
		warn("[FavoritePrompt] Failed to show favorite prompt:", err)
	end
end

local function updateFavoritePrompt()
	local currentTimePlayed = getTimePlayed()
	if not promptedThisSession and crossedPromptThreshold(currentTimePlayed) then
		promptedThisSession = true
		promptFavoriteGame()
	end
	lastTimePlayed = currentTimePlayed
end

timePlayed:GetPropertyChangedSignal("Value"):Connect(function()
	updateFavoritePrompt()
end)
