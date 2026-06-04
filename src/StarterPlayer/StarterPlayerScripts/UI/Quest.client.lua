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
local ReactModalRegistry = require(Modules:WaitForChild("ReactModalRegistry"))
local QuestScreen = require(UiFolder:WaitForChild("Quest"):WaitForChild("QuestScreen"))

local REQUEST_REMOTE_NAME = "GrandLineRushQuestRequest"
local STATE_REMOTE_NAME = "GrandLineRushQuestState"

local remotes = nil
local requestRemote = nil
local stateRemote = nil
local stateRemoteConnection = nil
local remotesChildConnection = nil
local requestedInitialState = false

local rootContainer = Instance.new("Folder")
rootContainer.Name = "ReactQuestRoot"

local root = ReactRoblox.createRoot(rootContainer)
local modalAdapter = ReactFrameModalAdapter.new({
	playerGui = playerGui,
	frameName = "Quest",
	hostName = "ReactQuestHost",
	backdropName = "ReactQuestBackdrop",
	backdropActive = false,
	modalStateKey = "QuestModal",
	minSize = Vector2.new(760, 520),
	maxSize = Vector2.new(1080, 720),
	createFrameIfMissing = true,
	standalone = true,
})

local destroyed = false
local renderQueued = false
local questState = nil
local noticeText = nil
local noticeToken = 0
local watchedFrame = nil
local watchedFrameConnection = nil
local hudDescendantConnection = nil
local cleanupConnections = {}
local scheduleRender
local requestQuestState
local refreshRemotes
local bindRemotesFolder

local unregisterModal = ReactModalRegistry.Register("Quest", {
	toggle = function()
		modalAdapter:Toggle()
		if scheduleRender then
			scheduleRender()
		end
	end,
	open = function()
		if not modalAdapter:IsVisible() then
			modalAdapter:Toggle()
		end
		if scheduleRender then
			scheduleRender()
		end
	end,
	close = function()
		modalAdapter:Close()
	end,
	isVisible = function()
		return modalAdapter:IsVisible()
	end,
})

local function disconnectAll()
	for _, connection in ipairs(cleanupConnections) do
		connection:Disconnect()
	end
	table.clear(cleanupConnections)

	if watchedFrameConnection then
		watchedFrameConnection:Disconnect()
		watchedFrameConnection = nil
	end

	if stateRemoteConnection then
		stateRemoteConnection:Disconnect()
		stateRemoteConnection = nil
	end

	if remotesChildConnection then
		remotesChildConnection:Disconnect()
		remotesChildConnection = nil
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
	if refreshRemotes then
		refreshRemotes()
	end

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
	if refreshRemotes then
		refreshRemotes()
	end

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
	frame.Size = UDim2.fromScale(0.86, 0.8)
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
				if scheduleRender then
					scheduleRender()
				end
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

local function bindStateRemote(remote)
	if stateRemote == remote and stateRemoteConnection then
		return
	end

	if stateRemoteConnection then
		stateRemoteConnection:Disconnect()
		stateRemoteConnection = nil
	end

	stateRemote = remote
	stateRemoteConnection = remote.OnClientEvent:Connect(function(nextState)
		applyQuestState(nextState)
	end)
	table.insert(cleanupConnections, stateRemoteConnection)
end

refreshRemotes = function()
	if not remotes then
		return
	end

	local foundRequest = remotes:FindFirstChild(REQUEST_REMOTE_NAME)
	if foundRequest and foundRequest:IsA("RemoteFunction") then
		requestRemote = foundRequest
	end

	local foundState = remotes:FindFirstChild(STATE_REMOTE_NAME)
	if foundState and foundState:IsA("RemoteEvent") then
		bindStateRemote(foundState)
	end

	if requestRemote and not requestedInitialState then
		requestedInitialState = true
		requestQuestState()
	end
end

bindRemotesFolder = function(folder)
	if not folder or folder.Name ~= "Remotes" then
		return
	end

	if remotes == folder then
		refreshRemotes()
		return
	end

	if remotesChildConnection then
		remotesChildConnection:Disconnect()
		remotesChildConnection = nil
	end

	remotes = folder
	remotesChildConnection = folder.ChildAdded:Connect(function(child)
		if child.Name == REQUEST_REMOTE_NAME or child.Name == STATE_REMOTE_NAME then
			task.defer(refreshRemotes)
		end
	end)
	table.insert(cleanupConnections, remotesChildConnection)

	refreshRemotes()
end

table.insert(cleanupConnections, playerGui.ChildAdded:Connect(function(child)
	if child.Name == "Frames" or child.Name == "OpenUI" then
		modalAdapter:HandlePlayerGuiChildAdded(child)
	elseif child.Name == "HUD" then
		if hudDescendantConnection then
			hudDescendantConnection:Disconnect()
		end
		hudDescendantConnection = child.DescendantAdded:Connect(function(descendant)
			if descendant.Name == "Quest" or descendant.Name == "Not" or descendant.Name == "TextLB" then
				task.defer(syncHudQuestBadge)
			end
		end)
		task.defer(syncHudQuestBadge)
	end
end))

table.insert(cleanupConnections, playerGui.ChildRemoved:Connect(function(child)
	if child.Name == "Frames" or child.Name == "OpenUI" then
		modalAdapter:HandlePlayerGuiChildRemoved(child)
	elseif child.Name == "HUD" and hudDescendantConnection then
		hudDescendantConnection:Disconnect()
		hudDescendantConnection = nil
	end
end))

local existingRemotes = ReplicatedStorage:FindFirstChild("Remotes")
if existingRemotes then
	bindRemotesFolder(existingRemotes)
end

table.insert(cleanupConnections, ReplicatedStorage.ChildAdded:Connect(function(child)
	if child.Name == "Remotes" then
		bindRemotesFolder(child)
	end
end))

local initialHud = playerGui:FindFirstChild("HUD")
if initialHud then
	hudDescendantConnection = initialHud.DescendantAdded:Connect(function(descendant)
		if descendant.Name == "Quest" or descendant.Name == "Not" or descendant.Name == "TextLB" then
			task.defer(syncHudQuestBadge)
		end
	end)
end

if not requestedInitialState then
	requestQuestState()
end
render()

script.Destroying:Connect(function()
	destroyed = true
	if hudDescendantConnection then
		hudDescendantConnection:Disconnect()
	end
	disconnectAll()
	unregisterModal()
	modalAdapter:Destroy()
	root:unmount()
end)
