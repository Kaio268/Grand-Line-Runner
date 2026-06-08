local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local player = Players.LocalPlayer
local Modules = ReplicatedStorage:WaitForChild("Modules")
local MapResolver = require(Modules:WaitForChild("MapResolver"))
local ReactModalRegistry = require(Modules:WaitForChild("ReactModalRegistry"))

local refs = MapResolver.WaitForRefs(
	{ "SellNpc" },
	nil,
	{
		warn = true,
		context = "SellNpcDialog",
	}
)
local npc = refs.SellNpc
if not npc then
	return
end

local function waitForNpcPrompt(model)
	local prompt = model:FindFirstChildWhichIsA("ProximityPrompt", true)
	if prompt then
		return prompt
	end

	while model.Parent do
		local descendant = model.DescendantAdded:Wait()
		if descendant:IsA("ProximityPrompt") then
			return descendant
		end
	end

	return nil
end

local prompt = waitForNpcPrompt(npc)
if not prompt then
	return
end

local function openNamiSell()
	if ReactModalRegistry.Open("NamiShop", {
		Source = "Nami",
	}) then
		return
	end

	ReactModalRegistry.Open("Inventory", {
		ActiveCategory = "CrewMembers",
		ActiveView = "Inventory",
		Source = "NamiFallback",
	})
end

prompt.Triggered:Connect(function(triggeringPlayer)
	if triggeringPlayer and triggeringPlayer ~= player then
		return
	end

	openNamiSell()
end)
