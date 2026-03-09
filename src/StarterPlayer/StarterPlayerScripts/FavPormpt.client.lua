local Players = game:GetService("Players")
local AvatarEditorService = game:GetService("AvatarEditorService")

local player = Players.LocalPlayer

local totalStats = player:WaitForChild("TotalStats")
local timePlayed = totalStats:WaitForChild("TimePlayed")

local function checkTime()
	if timePlayed.Value == 200 then
		AvatarEditorService:PromptSetFavorite(129073777843683, Enum.AvatarItemType.Asset, true)
	end
end

checkTime()

timePlayed:GetPropertyChangedSignal("Value"):Connect(function()
	checkTime()
end)
