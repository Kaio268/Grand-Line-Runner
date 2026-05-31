local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local PopUpModule = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("PopUpModule"))

local STATE_EVENT_NAME = "AFKGoldChestState"
local STATE_REQUEST_NAME = "AFKGoldChestStateRequest"

local DISPLAY_ORDER = 122
local GOLD = Color3.fromRGB(255, 199, 82)
local GOLD_BRIGHT = Color3.fromRGB(255, 230, 145)
local TEXT_MAIN = Color3.fromRGB(255, 250, 226)
local TEXT_MUTED = Color3.fromRGB(221, 210, 174)
local CARD_COLOR = Color3.fromRGB(10, 24, 42)
local CARD_COLOR_2 = Color3.fromRGB(21, 45, 54)
local POPUP_STROKE = Color3.fromRGB(66, 42, 4)

local stateEvent = nil
local stateRequest = nil
local currentState = nil
local stateReceivedAt = 0

local function createInstance(className, props, children)
	local instance = Instance.new(className)

	for key, value in pairs(props or {}) do
		instance[key] = value
	end

	for _, child in ipairs(children or {}) do
		child.Parent = instance
	end

	return instance
end

local screenGui = createInstance("ScreenGui", {
	Name = "AFKGoldChestStatusGui",
	DisplayOrder = DISPLAY_ORDER,
	Enabled = true,
	IgnoreGuiInset = true,
	ResetOnSpawn = false,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
})
screenGui.Parent = playerGui

local root = createInstance("Frame", {
	Name = "StatusBanner",
	AnchorPoint = Vector2.new(0.5, 0),
	BackgroundColor3 = CARD_COLOR,
	BackgroundTransparency = 0.06,
	BorderSizePixel = 0,
	Position = UDim2.new(0.5, 0, 0, 118),
	Size = UDim2.fromOffset(360, 58),
	Visible = false,
	ZIndex = 20,
}, {
	createInstance("UICorner", {
		CornerRadius = UDim.new(0, 12),
	}),
	createInstance("UIStroke", {
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Color = GOLD,
		Thickness = 1.2,
		Transparency = 0.18,
	}),
	createInstance("UIGradient", {
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, CARD_COLOR:Lerp(Color3.fromRGB(92, 69, 25), 0.26)),
			ColorSequenceKeypoint.new(0.55, CARD_COLOR_2),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(8, 18, 34)),
		}),
		Rotation = 10,
	}),
	createInstance("UISizeConstraint", {
		MinSize = Vector2.new(280, 58),
		MaxSize = Vector2.new(390, 58),
	}),
})
root.Parent = screenGui

local titleLabel = createInstance("TextLabel", {
	Name = "Title",
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBold,
	Position = UDim2.fromOffset(16, 8),
	Size = UDim2.new(1, -32, 0, 22),
	Text = "",
	TextColor3 = TEXT_MAIN,
	TextSize = 16,
	TextStrokeTransparency = 1,
	TextTruncate = Enum.TextTruncate.AtEnd,
	TextWrapped = false,
	TextXAlignment = Enum.TextXAlignment.Center,
	TextYAlignment = Enum.TextYAlignment.Center,
	ZIndex = 21,
})
titleLabel.Parent = root

local detailLabel = createInstance("TextLabel", {
	Name = "Detail",
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamMedium,
	Position = UDim2.fromOffset(16, 31),
	Size = UDim2.new(1, -32, 0, 18),
	Text = "",
	TextColor3 = TEXT_MUTED,
	TextSize = 12,
	TextStrokeTransparency = 1,
	TextTruncate = Enum.TextTruncate.AtEnd,
	TextWrapped = false,
	TextXAlignment = Enum.TextXAlignment.Center,
	TextYAlignment = Enum.TextYAlignment.Center,
	ZIndex = 21,
})
detailLabel.Parent = root

local function formatDuration(seconds)
	seconds = math.max(0, math.ceil(tonumber(seconds) or 0))
	local minutes = math.floor(seconds / 60)
	local remainingSeconds = seconds % 60
	return string.format("%02d:%02d", minutes, remainingSeconds)
end

local function getRemainingSeconds()
	if typeof(currentState) ~= "table" then
		return 0
	end

	local baseRemaining = math.max(0, tonumber(currentState.SecondsUntilNext) or 0)
	local elapsed = math.max(0, os.clock() - stateReceivedAt)
	return math.max(0, baseRemaining - elapsed)
end

local function renderState()
	if typeof(currentState) ~= "table" or currentState.SessionActive ~= true then
		root.Visible = false
		return
	end

	root.Visible = true

	local earnedToday = math.max(0, math.floor(tonumber(currentState.EarnedToday) or 0))
	local dailyCap = math.max(1, math.floor(tonumber(currentState.DailyCap) or 1))

	if currentState.CapReached == true then
		titleLabel.Text = "Daily AFK Gold Chest limit reached."
	elseif currentState.InZone ~= true then
		titleLabel.Text = "Enter the AFK World to begin."
	else
		local prefix = if currentState.IsPremium == true then "Premium: " else ""
		titleLabel.Text = string.format("%sNext Gold Chest in: %s", prefix, formatDuration(getRemainingSeconds()))
	end

	detailLabel.Text = string.format("AFK Gold Chests Today: %d/%d", earnedToday, dailyCap)
	titleLabel.TextColor3 = if currentState.IsPremium == true then GOLD_BRIGHT else TEXT_MAIN
end

local function applyState(state)
	if typeof(state) ~= "table" then
		return
	end

	currentState = state
	stateReceivedAt = os.clock()
	renderState()
end

local function showReward(payload)
	if typeof(payload) ~= "table" then
		return
	end

	local message = tostring(payload.Message or "")
	if message == "" then
		message = if payload.IsPremium == true
			then "Premium AFK Reward: +1 Gold Chest"
			else "AFK Reward: +1 Gold Chest"
	end

	PopUpModule:Local_SendPopUp(message, GOLD_BRIGHT, POPUP_STROKE, 3, false)

	if typeof(payload.State) == "table" then
		applyState(payload.State)
	end
end

local function waitForRemote(parent, name, className, timeoutSeconds)
	local found = parent:FindFirstChild(name)
	if found and found:IsA(className) then
		return found
	end

	found = parent:WaitForChild(name, timeoutSeconds)
	if found and found:IsA(className) then
		return found
	end

	return nil
end

local function requestInitialState()
	if not stateRequest then
		return
	end

	local ok, state = pcall(function()
		return stateRequest:InvokeServer()
	end)
	if ok then
		applyState(state)
	end
end

local remotes = ReplicatedStorage:WaitForChild("Remotes", 20)
if remotes then
	stateEvent = waitForRemote(remotes, STATE_EVENT_NAME, "RemoteEvent", 20)
	stateRequest = waitForRemote(remotes, STATE_REQUEST_NAME, "RemoteFunction", 20)
end

if stateEvent then
	stateEvent.OnClientEvent:Connect(function(action, payload)
		if action == "State" then
			applyState(payload)
		elseif action == "Reward" then
			showReward(payload)
		end
	end)
end

requestInitialState()

task.spawn(function()
	while true do
		renderState()
		task.wait(0.5)
	end
end)
