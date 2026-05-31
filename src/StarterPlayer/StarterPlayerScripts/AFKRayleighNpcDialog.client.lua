local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local Modules = ReplicatedStorage:WaitForChild("Modules")
local DialogModule = require(ReplicatedStorage:WaitForChild("DialogModule"))
local MapResolver = require(Modules:WaitForChild("MapResolver"))
local PopUpModule = require(Modules:WaitForChild("PopUpModule"))

local ENTRY_REQUEST_NAME = "AFKGoldChestEntryRequest"
local SUCCESS_COLOR = Color3.fromRGB(255, 230, 145)
local ERROR_COLOR = Color3.fromRGB(255, 125, 108)
local POPUP_STROKE = Color3.fromRGB(66, 42, 4)

local refs = MapResolver.WaitForRefs(
	{ "AFKRayleighNpc" },
	nil,
	{
		warn = true,
		context = "AFKRayleighNpcDialog",
	}
)
local npc = refs.AFKRayleighNpc
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

local function waitForEntryRequest()
	local remotes = ReplicatedStorage:WaitForChild("Remotes", 20)
	if not remotes then
		return nil
	end

	local remote = remotes:WaitForChild(ENTRY_REQUEST_NAME, 20)
	if remote and remote:IsA("RemoteFunction") then
		return remote
	end

	return nil
end

if not npc.PrimaryPart then
	warn("[AFKRayleighNpcDialog] Rayleigh NPC is missing a PrimaryPart.")
	return
end

if not npc.PrimaryPart:WaitForChild("gui", 20) then
	warn("[AFKRayleighNpcDialog] Rayleigh NPC is missing the expected PrimaryPart.gui.")
	return
end

local prompt = waitForNpcPrompt(npc)
if not prompt then
	return
end

local entryRequest = waitForEntryRequest()
if not entryRequest then
	warn("[AFKRayleighNpcDialog] AFK entry request remote is unavailable.")
	return
end

local dialogObject = DialogModule.new("Rayleigh", npc, prompt)
dialogObject:addDialog("Do you want to train in the AFK World?", { "Train", "Not now" })

prompt.Triggered:Connect(function(triggeringPlayer)
	dialogObject:triggerDialog(triggeringPlayer or player, 1)
end)

dialogObject.responded:Connect(function(responseNum, dialogNum)
	if dialogNum ~= 1 then
		return
	end

	if responseNum == 2 then
		dialogObject:hideGui("Train whenever you're ready.")
		return
	end

	local ok, response = pcall(function()
		return entryRequest:InvokeServer()
	end)

	if ok and typeof(response) == "table" and response.ok == true then
		dialogObject:hideGui("Good. Train hard.")
		PopUpModule:Local_SendPopUp(tostring(response.message or "AFK training started."), SUCCESS_COLOR, POPUP_STROKE, 3, false)
	else
		local message = if ok and typeof(response) == "table"
			then tostring(response.message or "AFK training is unavailable.")
			else "AFK training is unavailable."
		dialogObject:hideGui("Not yet.")
		PopUpModule:Local_SendPopUp(message, ERROR_COLOR, POPUP_STROKE, 3, false)
	end
end)
