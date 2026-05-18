local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local ReactModalRegistry = require(Modules:WaitForChild("ReactModalRegistry"))

local player = Players.LocalPlayer

local function promptTextContains(prompt, needle)
	local haystack = string.lower(table.concat({
		tostring(prompt.Name or ""),
		tostring(prompt.ActionText or ""),
		tostring(prompt.ObjectText or ""),
	}, " "))
	return string.find(haystack, string.lower(needle), 1, true) ~= nil
end

ProximityPromptService.PromptTriggered:Connect(function(prompt, triggeringPlayer)
	if triggeringPlayer and triggeringPlayer ~= player then
		return
	end

	if not promptTextContains(prompt, "nami") then
		return
	end

	ReactModalRegistry.Open("NamiShop")
end)
