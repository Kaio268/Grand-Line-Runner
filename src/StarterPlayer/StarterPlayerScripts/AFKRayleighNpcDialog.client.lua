local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local Modules = ReplicatedStorage:WaitForChild("Modules")
local DialogModule = require(ReplicatedStorage:WaitForChild("DialogModule"))
local EconomyConfig = require(Modules:WaitForChild("Configs"):WaitForChild("GrandLineRushEconomy"))
local MapResolver = require(Modules:WaitForChild("MapResolver"))
local PopUpModule = require(Modules:WaitForChild("PopUpModule"))

local afkTeleportConfig = if typeof(EconomyConfig.AFKTeleport) == "table" then EconomyConfig.AFKTeleport else {}
local afkTeleportRemotes = if typeof(afkTeleportConfig.Remotes) == "table" then afkTeleportConfig.Remotes else {}
local ENTRY_REQUEST_NAME = tostring(afkTeleportRemotes.EntryRequestName or "AFKTeleportEntryRequest")
local SUCCESS_COLOR = Color3.fromRGB(255, 230, 145)
local ERROR_COLOR = Color3.fromRGB(255, 125, 108)
local POPUP_STROKE = Color3.fromRGB(66, 42, 4)
local OVERHEAD_GUI_NAME = "RayleighAFKOverheadGui"

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

local dialogGui = npc.PrimaryPart:WaitForChild("gui", 20)
if not dialogGui then
	warn("[AFKRayleighNpcDialog] Rayleigh NPC is missing the expected PrimaryPart.gui.")
	return
end
dialogGui:SetAttribute("DialogSuppressNameLabel", true)

local function ensureAlwaysVisibleAfkLabel()
	local primaryPart = npc.PrimaryPart
	if not primaryPart then
		return
	end

	local existing = primaryPart:FindFirstChild(OVERHEAD_GUI_NAME)
	if existing and existing:IsA("BillboardGui") then
		existing.Enabled = true
		existing.AlwaysOnTop = true
		return existing
	elseif existing then
		existing:Destroy()
	end

	local sourceDialogGui = primaryPart:FindFirstChild("gui")
	local sourceLabel = sourceDialogGui and sourceDialogGui:FindFirstChild("name")
	local billboard = Instance.new("BillboardGui")
	billboard.Name = OVERHEAD_GUI_NAME
	billboard.AlwaysOnTop = true
	billboard.Enabled = true
	billboard.LightInfluence = 0
	billboard.MaxDistance = if sourceDialogGui and sourceDialogGui:IsA("BillboardGui") then sourceDialogGui.MaxDistance else 70
	billboard.Size = if sourceDialogGui and sourceDialogGui:IsA("BillboardGui")
		then sourceDialogGui.Size
		else UDim2.fromOffset(200, 50)
	billboard.StudsOffset = if sourceDialogGui and sourceDialogGui:IsA("BillboardGui")
		then sourceDialogGui.StudsOffset + Vector3.new(0, 0.45, 0)
		else Vector3.new(0, 10.45, 0)
	billboard.Parent = primaryPart

	local label
	if sourceLabel and sourceLabel:IsA("TextLabel") then
		label = sourceLabel:Clone()
	else
		label = Instance.new("TextLabel")
		label.AnchorPoint = Vector2.new(0.5, 0.5)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.GothamBlack
		label.Position = UDim2.fromScale(0.5, 0.5)
		label.Size = UDim2.fromScale(1, 1)
		label.TextColor3 = SUCCESS_COLOR
		label.TextScaled = true
	end

	label.Name = "name"
	label.Visible = true
	label.Text = "AFK"
	label.TextTransparency = 0
	label.BackgroundTransparency = 1
	label.Parent = billboard

	local stroke = label:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Transparency = 0
	end

	return billboard
end

local overheadGui = ensureAlwaysVisibleAfkLabel()
local dialogNameLabel = dialogGui:FindFirstChild("name")
if dialogNameLabel and dialogNameLabel:IsA("TextLabel") then
	dialogNameLabel.TextTransparency = 1
	dialogNameLabel.Visible = false
	local stroke = dialogNameLabel:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Transparency = 1
	end
end
script.Destroying:Connect(function()
	if overheadGui and overheadGui.Parent then
		overheadGui:Destroy()
	end
end)

local prompt = waitForNpcPrompt(npc)
if not prompt then
	return
end
prompt.ObjectText = "Dark King"
prompt.ActionText = "AFK"

local entryRequest = waitForEntryRequest()
if not entryRequest then
	warn("[AFKRayleighNpcDialog] AFK entry request remote is unavailable.")
	return
end

local dialogObject = DialogModule.new("Dark King", npc, prompt)
dialogObject:addDialog("Do you want to enter the AFK lobby?", { "Enter AFK", "Not now" })

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
		dialogObject:hideGui("Good. Rest your sea legs.")
		PopUpModule:Local_SendPopUp(tostring(response.message or "Traveling to the AFK lobby..."), SUCCESS_COLOR, POPUP_STROKE, 3, false)
	else
		local message = if ok and typeof(response) == "table"
			then tostring(response.message or "AFK lobby is unavailable.")
			else "AFK lobby is unavailable."
		dialogObject:hideGui("Not yet.")
		PopUpModule:Local_SendPopUp(message, ERROR_COLOR, POPUP_STROKE, 3, false)
	end
end)
