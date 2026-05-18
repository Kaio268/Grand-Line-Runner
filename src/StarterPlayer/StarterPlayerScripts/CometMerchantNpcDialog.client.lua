local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local Modules = ReplicatedStorage:WaitForChild("Modules")
local DialogModule = require(ReplicatedStorage:WaitForChild("DialogModule"))
local MapResolver = require(Modules:WaitForChild("MapResolver"))
local ReactModalRegistry = require(Modules:WaitForChild("ReactModalRegistry"))

local refs = MapResolver.WaitForRefs(
	{ "CometMerchantNpc" },
	nil,
	{
		warn = true,
		context = "CometMerchantNpcDialog",
	}
)
local npc = refs.CometMerchantNpc
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

local dialogObject = DialogModule.new("OpenCometMerchant", npc, prompt)
dialogObject:addDialog("Do You Want To Open Comet Merchant?", { "Yea", "Nope" })

prompt.Triggered:Connect(function(triggeringPlayer)
	dialogObject:triggerDialog(triggeringPlayer or player, 1)
end)

dialogObject.responded:Connect(function(responseNum, dialogNum)
	if dialogNum ~= 1 then
		return
	end

	if responseNum == 1 then
		dialogObject:hideGui("Okay!!")
		ReactModalRegistry.Open("CometMerchant")
	elseif responseNum == 2 then
		dialogObject:hideGui("Alr, bye!")
	end
end)
