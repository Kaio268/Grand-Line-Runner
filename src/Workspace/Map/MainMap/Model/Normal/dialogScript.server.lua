local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DialogModule = require(ReplicatedStorage.DialogModule)

local player = game.Players.LocalPlayer
local npc = script.Parent  
local npcGui = npc:WaitForChild("Mesh"):WaitForChild("gui")
local prompt = npc:WaitForChild("ProximityPrompt")

local dialogObject = DialogModule.new("OpenFishingShop", npc, prompt)
dialogObject:addDialog("Do You Want To Open Gears Store?", {"Yea", "Nope"})

local open = require(player.PlayerGui:WaitForChild(`OpenUI`):WaitForChild(`Open_UI`))

--

prompt.Triggered:Connect(function(player)
	dialogObject:triggerDialog(player, 1)
end)

dialogObject.responded:Connect(function(responseNum, dialogNum)
	if dialogNum == 1 then
		if responseNum == 1 then
			dialogObject:hideGui("Okay!!")
			open:OpenFrame("GearStore")
		elseif responseNum == 2 then
			dialogObject:hideGui("Alr, bye!")
		end
	end
end)
