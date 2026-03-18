local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local DialogModule = require(ReplicatedStorage:WaitForChild("DialogModule"))

local function findChildPath(root, names)
	local current = root
	for _, name in ipairs(names) do
		if not current then
			return nil
		end
		current = current:FindFirstChild(name)
	end
	return current
end

local npc = findChildPath(workspace, { "Map", "MainMap", "Model", "Normal" })
local prompt = npc and npc:FindFirstChild("ProximityPrompt")
if not npc or not prompt then
	return
end

local dialogObject = DialogModule.new("OpenFishingShop", npc, prompt)
dialogObject:addDialog("Do You Want To Open Gears Store?", {"Yea", "Nope"})

local open = require(player:WaitForChild("PlayerGui"):WaitForChild("OpenUI"):WaitForChild("Open_UI"))

prompt.Triggered:Connect(function(triggeringPlayer)
	dialogObject:triggerDialog(triggeringPlayer or player, 1)
end)

dialogObject.responded:Connect(function(responseNum, dialogNum)
	if dialogNum ~= 1 then
		return
	end

	if responseNum == 1 then
		dialogObject:hideGui("Okay!!")
		open:OpenFrame("GearStore")
	elseif responseNum == 2 then
		dialogObject:hideGui("Alr, bye!")
	end
end)
