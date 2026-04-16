local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local Modules = ReplicatedStorage:WaitForChild("Modules")
local UiFolder = ReplicatedStorage:WaitForChild("UI")

local React = require(Packages:WaitForChild("React"))
local ReactRoblox = require(Packages:WaitForChild("ReactRoblox"))
local ReactFrameModalAdapter = require(Modules:WaitForChild("ReactFrameModalAdapter"))
local QuestScreen = require(UiFolder:WaitForChild("Quest"):WaitForChild("QuestScreen"))

local Remotes = ReplicatedStorage:WaitForChild("Remotes", 10)
local requestRemote = Remotes and Remotes:WaitForChild("GrandLineRushQuestRequest", 10)
local stateRemote = Remotes and Remotes:WaitForChild("GrandLineRushQuestState", 10)

local rootContainer = Instance.new("Folder")
rootContainer.Name = "ReactQuestRoot"

local root = ReactRoblox.createRoot(rootContainer)
local modalAdapter = ReactFrameModalAdapter.new({
	playerGui = playerGui,
	frameName = "Quest",
	hostName = "ReactQuestHost",
	backdropName = "ReactQuestBackdrop",
	modalStateKey = "QuestModal",
	minSize = Vector2.new(760, 520),
	maxSize = Vector2.new(1080, 720),
	createFrameIfMissing = true,
})

local destroyed = false
local renderQueued = false
local questState = nil
local noticeText = nil
local noticeToken = 0
local watchedFrame = nil
local watchedFrameConnection = nil
local cleanupConnections = {}

local scheduleRender
local requestQuestState

local function disconnectAll()
	for _, connection in ipairs(cleanupConnections) do
		connection:Disconnect()
	end
	table.clear(cleanupConnections)

	if watchedFrameConnection then
		watchedFrameConnection:Disconnect()
		watchedFrameConnection = nil
	end
end

local function getClaimableCount()
	return math.max(0, tonumber(questState and questState.claimableCount) or 0)
end

local function syncHudQuestBadge()
	local hud = playerGui:FindFirstChild("HUD")
	local lButtons = hud and hud:FindFirstChild("LButtons")
	local questButton = lButtons and lButtons:FindFirstChild("Quest")
	if not questButton then
		return
	end

	local badge = questButton:FindFirstChild("Not")
	if not badge then
		return
	end

	local claimableCount = getClaimableCount()
	badge.Visible = claimableCount > 0

	local textLabel = badge:FindFirstChild("TextLB", true)
	if textLabel and textLabel:IsA("TextLabel") then
		textLabel.Text = tostring(math.min(99, claimableCount))
	end
end

local function applyQuestState(nextState)
	if typeof(nextState) == "table" then
		questState = nextState
		syncHudQuestBadge()
		if scheduleRender then
			scheduleRender()
		end
	end
end

local function setNotice(text)
	noticeText = text
	noticeToken += 1
	local currentToken = noticeToken

	if scheduleRender then
		scheduleRender()
	end

	if text then
		task.delay(2.8, function()
			if destroyed or currentToken ~= noticeToken then
				return
			end

			noticeText = nil
			if scheduleRender then
				scheduleRender()
			end
		end)
	end
end

requestQuestState = function()
	if not requestRemote then
		setNotice("Quest service is starting.")
		return
	end

	local ok, response = pcall(function()
		return requestRemote:InvokeServer("GetState")
	end)
	if ok and typeof(response) == "table" and typeof(response.state) == "table" then
		applyQuestState(response.state)
	elseif not ok then
		setNotice("Quest data could not be loaded.")
	end
end

local function claimQuest(categoryId, questId)
	if not requestRemote then
		setNotice("Quest service is starting.")
		return
	end

	local ok, response = pcall(function()
		return requestRemote:InvokeServer("ClaimQuest", {
			Category = categoryId,
			QuestId = questId,
		})
	end)

	if ok and typeof(response) == "table" then
		if typeof(response.state) == "table" then
			applyQuestState(response.state)
		end
		if response.message then
			setNotice(response.message)
		end
	else
		setNotice("Couldn't claim that quest.")
	end
end

local function prepareQuestFrame()
	local frame = modalAdapter:GetFrame()
	local host = frame and frame:FindFirstChild("ReactQuestHost")
	if not frame then
		return
	end

	frame.BackgroundTransparency = 1
	frame.BorderSizePixel = 0
	frame.ClipsDescendants = true
	frame.Size = UDim2.new(0.86, 0, 0.8, 0)
	frame.ZIndex = 120
	if host then
		host.ZIndex = 140
	end

	if watchedFrame ~= frame then
		if watchedFrameConnection then
			watchedFrameConnection:Disconnect()
		end
		watchedFrame = frame
		watchedFrameConnection = frame:GetPropertyChangedSignal("Visible"):Connect(function()
			modalAdapter:SyncOverlayState()
			if frame.Visible then
				requestQuestState()
			end
		end)
	end
end

local function render()
	local host = modalAdapter:EnsureHost()
	if not host then
		return
	end

	prepareQuestFrame()
	syncHudQuestBadge()

	root:render(ReactRoblox.createPortal(React.createElement(QuestScreen, {
		state = questState,
		noticeText = noticeText,
		onClose = function()
			modalAdapter:Close()
		end,
		onClaimQuest = claimQuest,
	}), host))
end

scheduleRender = function()
	if renderQueued or destroyed then
		return
	end

	renderQueued = true
	task.defer(function()
		renderQueued = false
		if not destroyed then
			render()
		end
	end)
end

modalAdapter:SetScheduleRender(scheduleRender)
modalAdapter:BindFramesFolderTracking()

if stateRemote then
	table.insert(cleanupConnections, stateRemote.OnClientEvent:Connect(function(nextState)
		applyQuestState(nextState)
	end))
end

table.insert(cleanupConnections, playerGui.ChildAdded:Connect(function(child)
	if child.Name == "Frames" or child.Name == "OpenUI" then
		modalAdapter:HandlePlayerGuiChildAdded(child)
	elseif child.Name == "HUD" then
		task.defer(syncHudQuestBadge)
	end
end))

table.insert(cleanupConnections, playerGui.ChildRemoved:Connect(function(child)
	if child.Name == "Frames" or child.Name == "OpenUI" then
		modalAdapter:HandlePlayerGuiChildRemoved(child)
	end
end))

table.insert(cleanupConnections, playerGui.DescendantAdded:Connect(function(descendant)
	if descendant.Name == "Quest" or descendant.Name == "Not" or descendant.Name == "TextLB" then
		task.defer(syncHudQuestBadge)
	end
end))

requestQuestState()
render()

script.Destroying:Connect(function()
	destroyed = true
	disconnectAll()
	modalAdapter:Destroy()
	root:unmount()
end)
