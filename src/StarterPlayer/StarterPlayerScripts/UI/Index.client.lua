local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local Modules = ReplicatedStorage:WaitForChild("Modules")
local UiFolder = ReplicatedStorage:WaitForChild("UI")

local React = require(Packages:WaitForChild("React"))
local ReactRoblox = require(Packages:WaitForChild("ReactRoblox"))
local UiModalState = require(Modules:WaitForChild("UiModalState"))
local ReactFrameModalAdapter = require(Modules:WaitForChild("ReactFrameModalAdapter"))

local IndexFolder = UiFolder:WaitForChild("Index")

local e = React.createElement

local rootContainer = Instance.new("Folder")
rootContainer.Name = "ReactIndexRoot"

local FRAMES_DISPLAY_ORDER = 120

local root = ReactRoblox.createRoot(rootContainer)
local destroyed = false
local renderQueued = false
local moduleRetryQueued = false

local fallbackGui
local indexBackdrop
local legacyFrame = nil
local uiController = nil
local inventoryFolder = nil
local indexCollectionFolder = nil
local brainrotInventoryFolder = nil
local devilFruitStateFolder = nil
local indexRewardsFolder = nil
local claimRemote = nil

local cleanupConnections = {}
local legacyConnections = {}
local framesFolderConnections = {}
local inventoryConnections = {}
local indexCollectionConnections = {}
local brainrotInventoryConnections = {}
local devilFruitStateConnections = {}
local rewardConnections = {}

local scheduleRender
local fireClaimReward
local indexDataModule = nil
local indexScreenModule = nil
local lastIndexModuleError = nil
local lastIndexViewModelError = nil
local claimRemoteConnection = nil
local pendingClaimRequests = {}
local claimedRewardOverrides = {}
local modalAdapter = ReactFrameModalAdapter.new({
	playerGui = playerGui,
	frameName = "Index",
	hostName = "ReactIndexHost",
	backdropName = "ReactIndexBackdrop",
	modalStateKey = "IndexModal",
	minSize = Vector2.new(1080, 680),
	maxSize = Vector2.new(1360, 860),
	allowFallback = true,
})

local function buildEmptyViewModel()
	return {
		tabs = {
			{ id = "index", label = "Index", eyebrow = "Collection" },
			{ id = "fruits", label = "Fruits", eyebrow = "Devil Fruits" },
			{ id = "rewards", label = "Rewards", eyebrow = "Milestones" },
		},
		categories = {},
		units = {},
		collectionStats = {
			collected = 0,
			total = 0,
			claimableCount = 0,
		},
		devilFruitCollection = {
			label = "Devil Fruits",
			units = {},
			collectionStats = {
				collected = 0,
				total = 0,
			},
		},
		rewards = {},
		claimableCount = 0,
	}
end

local function warnOnce(kind, message)
	if kind == "module" then
		if lastIndexModuleError == message then
			return
		end

		lastIndexModuleError = message
	elseif kind == "viewModel" then
		if lastIndexViewModelError == message then
			return
		end

		lastIndexViewModelError = message
	end

	warn(message)
end

local function scheduleModuleRetry()
	if moduleRetryQueued or destroyed then
		return
	end

	moduleRetryQueued = true
	task.delay(0.5, function()
		moduleRetryQueued = false
		if destroyed then
			return
		end

		if scheduleRender then
			scheduleRender()
		end
	end)
end

local function loadIndexModules()
	if indexDataModule and indexScreenModule then
		return indexDataModule, indexScreenModule
	end

	local indexDataScript = IndexFolder:FindFirstChild("IndexData") or IndexFolder:WaitForChild("IndexData", 1)
	local indexScreenScript = IndexFolder:FindFirstChild("IndexScreen") or IndexFolder:WaitForChild("IndexScreen", 1)
	if not indexDataScript or not indexScreenScript then
		warnOnce("module", "[IndexReact] Waiting for Index modules to replicate before mounting the React Index.")
		scheduleModuleRetry()
		return nil, nil
	end

	local okData, dataOrError = pcall(require, indexDataScript)
	if not okData then
		warnOnce("module", "[IndexReact] Failed to load IndexData: " .. tostring(dataOrError))
		scheduleModuleRetry()
		return nil, nil
	end

	local okScreen, screenOrError = pcall(require, indexScreenScript)
	if not okScreen then
		warnOnce("module", "[IndexReact] Failed to load IndexScreen: " .. tostring(screenOrError))
		scheduleModuleRetry()
		return nil, nil
	end

	indexDataModule = dataOrError
	indexScreenModule = screenOrError
	lastIndexModuleError = nil

	return indexDataModule, indexScreenModule
end

local function disconnectAll(bucket)
	for _, connection in ipairs(bucket) do
		connection:Disconnect()
	end

	table.clear(bucket)
end

local function trackConnection(signal, callback, bucket)
	local connection = signal:Connect(callback)
	table.insert(bucket, connection)
	return connection
end

local function bindLiveValueTree(folder, bucket)
	disconnectAll(bucket)

	if not folder then
		return
	end

	local function bindValueObserver(descendant)
		if descendant:IsA("ValueBase") then
			trackConnection(descendant:GetPropertyChangedSignal("Value"), function()
				task.defer(scheduleRender)
			end, bucket)
		end
	end

	trackConnection(folder.ChildAdded, function()
		task.defer(scheduleRender)
	end, bucket)

	trackConnection(folder.ChildRemoved, function()
		task.defer(scheduleRender)
	end, bucket)

	for _, descendant in ipairs(folder:GetDescendants()) do
		bindValueObserver(descendant)
	end

	trackConnection(folder.DescendantAdded, function(descendant)
		bindValueObserver(descendant)
		task.defer(scheduleRender)
	end, bucket)

	trackConnection(folder.DescendantRemoving, function()
		task.defer(scheduleRender)
	end, bucket)
end

local function ensureIndexBackdrop()
	local framesGui = playerGui:FindFirstChild("Frames")
	if not framesGui then
		return nil
	end

	if indexBackdrop and indexBackdrop.Parent == framesGui then
		return indexBackdrop
	end

	indexBackdrop = framesGui:FindFirstChild("ReactIndexBackdrop")
	if not indexBackdrop then
		indexBackdrop = Instance.new("Frame")
		indexBackdrop.Name = "ReactIndexBackdrop"
		indexBackdrop.BackgroundColor3 = Color3.fromRGB(3, 8, 18)
		indexBackdrop.BackgroundTransparency = 0.42
		indexBackdrop.BorderSizePixel = 0
		indexBackdrop.Size = UDim2.fromScale(1, 1)
		indexBackdrop.Visible = false
		indexBackdrop.ZIndex = 80
		indexBackdrop.Active = true
		indexBackdrop.Parent = framesGui
	end

	return indexBackdrop
end

local function syncOverlayState()
	local isVisible = legacyFrame ~= nil and legacyFrame.Parent ~= nil and legacyFrame.Visible == true
	local backdrop = ensureIndexBackdrop()
	if backdrop then
		backdrop.Visible = isVisible
	end

	UiModalState.SetOpen("IndexModal", isVisible)
end

local function tryLoadUiController()
	local openUiScript = playerGui:FindFirstChild("OpenUI") or playerGui:WaitForChild("OpenUI", 1)
	if not openUiScript then
		return nil
	end

	local openUiModule = openUiScript:FindFirstChild("Open_UI")
	if not openUiModule then
		return nil
	end

	local ok, result = pcall(require, openUiModule)
	if ok then
		return result
	end

	return nil
end

local function bindInventoryFolder(folder)
	inventoryFolder = folder
	bindLiveValueTree(folder, inventoryConnections)
end

local function bindIndexCollectionFolder(folder)
	indexCollectionFolder = folder
	bindLiveValueTree(folder, indexCollectionConnections)
end

local function bindBrainrotInventoryFolder(folder)
	brainrotInventoryFolder = folder
	bindLiveValueTree(folder, brainrotInventoryConnections)
end

local function bindDevilFruitStateFolder(folder)
	devilFruitStateFolder = folder
	bindLiveValueTree(folder, devilFruitStateConnections)
end

local function bindIndexRewardsFolder(folder)
	disconnectAll(rewardConnections)
	indexRewardsFolder = folder

	if not indexRewardsFolder then
		return
	end

	local function bindRewardValue(child)
		if child:IsA("BoolValue") then
			trackConnection(child:GetPropertyChangedSignal("Value"), function()
				task.defer(scheduleRender)
			end, rewardConnections)
		end
	end

	for _, child in ipairs(indexRewardsFolder:GetChildren()) do
		bindRewardValue(child)
	end

	trackConnection(indexRewardsFolder.ChildAdded, function(child)
		bindRewardValue(child)
		task.defer(scheduleRender)
	end, rewardConnections)

	trackConnection(indexRewardsFolder.ChildRemoved, function()
		task.defer(scheduleRender)
	end, rewardConnections)
end

local function refreshLiveFolders()
	bindInventoryFolder(player:FindFirstChild("Inventory") or player:WaitForChild("Inventory", 1))
	bindIndexCollectionFolder(player:FindFirstChild("IndexCollection") or player:WaitForChild("IndexCollection", 1))
	bindBrainrotInventoryFolder(player:FindFirstChild("BrainrotInventory") or player:WaitForChild("BrainrotInventory", 1))
	bindDevilFruitStateFolder(player:FindFirstChild("DevilFruit"))
	bindIndexRewardsFolder(player:FindFirstChild("IndexRewards"))
end

local function getEquippedDevilFruit()
	local devilFruitFolder = devilFruitStateFolder or player:FindFirstChild("DevilFruit")
	local equippedValue = devilFruitFolder and devilFruitFolder:FindFirstChild("Equipped")
	if equippedValue and equippedValue:IsA("StringValue") then
		local value = tostring(equippedValue.Value or "")
		if value ~= "" and value ~= "None" then
			return value
		end
	end

	local equippedAttribute = player:GetAttribute("EquippedDevilFruit")
	if typeof(equippedAttribute) == "string" and equippedAttribute ~= "" and equippedAttribute ~= "None" then
		return equippedAttribute
	end

	return nil
end

local function buildViewModel(previewMode)
	local indexData = select(1, loadIndexModules())
	if not indexData then
		return buildEmptyViewModel()
	end

	local ok, viewModelOrError = pcall(indexData.buildViewModel, {
		brainrotInventory = brainrotInventoryFolder,
		claimedRewardOverrides = claimedRewardOverrides,
		equippedDevilFruit = getEquippedDevilFruit(),
		indexCollection = indexCollectionFolder,
		indexRewardsFolder = indexRewardsFolder,
		inventory = inventoryFolder,
		previewMode = previewMode == true,
	})
	if ok and typeof(viewModelOrError) == "table" then
		lastIndexViewModelError = nil
		return viewModelOrError
	end

	warnOnce("viewModel", "[IndexReact] Failed to build the Index view model: " .. tostring(viewModelOrError))

	if typeof(indexData.getDefaultViewModel) == "function" then
		local defaultOk, defaultViewModel = pcall(indexData.getDefaultViewModel)
		if defaultOk and typeof(defaultViewModel) == "table" then
			return defaultViewModel
		end
	end

	return buildEmptyViewModel()
end

local function findRemoteEventByName(parent, remoteName)
	for _, child in ipairs(parent:GetChildren()) do
		if child.Name == remoteName and child:IsA("RemoteEvent") then
			return child
		end
	end

	return nil
end

local function waitForRemoteEventByName(parent, remoteName, timeoutSeconds)
	local deadline = os.clock() + (timeoutSeconds or 2)

	repeat
		local remote = findRemoteEventByName(parent, remoteName)
		if remote then
			return remote
		end

		task.wait(0.1)
	until os.clock() >= deadline

	return findRemoteEventByName(parent, remoteName)
end

local function bindClaimRemote(remote)
	if claimRemoteConnection then
		claimRemoteConnection:Disconnect()
		claimRemoteConnection = nil
	end

	if not remote then
		return
	end

	claimRemoteConnection = remote.OnClientEvent:Connect(function(actionName, success, rewardId)
		if actionName ~= "ClaimResult" then
			return
		end

		local rewardKey = tostring(rewardId or "")
		if rewardKey ~= "" then
			pendingClaimRequests[rewardKey] = nil
			if success == true then
				claimedRewardOverrides[rewardKey] = true
			end
		end

		task.defer(scheduleRender)
	end)
end

local function getClaimRemote()
	if claimRemote and claimRemote.Parent ~= nil and claimRemote:IsA("RemoteEvent") then
		if not claimRemoteConnection then
			bindClaimRemote(claimRemote)
		end
		return claimRemote
	end

	local remote = findRemoteEventByName(ReplicatedStorage, "ClaimIndexReward")
		or waitForRemoteEventByName(ReplicatedStorage, "ClaimIndexReward", 2)
	if remote and remote:IsA("RemoteEvent") then
		claimRemote = remote
		bindClaimRemote(claimRemote)
		return claimRemote
	end

	return nil
end

local function findLegacyIndexFrame()
	if legacyFrame and legacyFrame.Parent ~= nil then
		return legacyFrame
	end

	legacyFrame = nil

	local framesGui = playerGui:FindFirstChild("Frames") or playerGui:WaitForChild("Frames", 2)
	if not framesGui then
		return nil
	end

	local frame = framesGui:FindFirstChild("Index") or framesGui:WaitForChild("Index", 1)
	if frame and frame:IsA("Frame") then
		return frame
	end

	return nil
end

local function bindFramesFolderTracking()
	disconnectAll(framesFolderConnections)

	local framesGui = playerGui:FindFirstChild("Frames")
	if not framesGui then
		return
	end

	trackConnection(framesGui.ChildAdded, function(child)
		if child.Name == "Index" then
			legacyFrame = nil
			task.defer(scheduleRender)
		end
	end, framesFolderConnections)

	trackConnection(framesGui.ChildRemoved, function(child)
		if child.Name == "Index" then
			legacyFrame = nil
			task.defer(scheduleRender)
		end
	end, framesFolderConnections)
end

local function applyLegacyFrameStyling(frame)
	local framesGui = frame.Parent
	if framesGui and framesGui:IsA("ScreenGui") then
		framesGui.DisplayOrder = math.max(framesGui.DisplayOrder, FRAMES_DISPLAY_ORDER)
		framesGui.IgnoreGuiInset = true
		framesGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	end

	frame.Active = true
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.BackgroundTransparency = 1
	frame.BorderSizePixel = 0
	frame.ClipsDescendants = true
	frame.Position = UDim2.fromScale(0.5, 0.5)
	frame.Size = UDim2.new(0.9, 0, 0.84, 0)
	frame.ZIndex = 120

	local sizeConstraint = frame:FindFirstChild("ReactIndexSizeConstraint")
	if not sizeConstraint then
		sizeConstraint = Instance.new("UISizeConstraint")
		sizeConstraint.Name = "ReactIndexSizeConstraint"
		sizeConstraint.Parent = frame
	end

	sizeConstraint.MinSize = Vector2.new(1080, 680)
	sizeConstraint.MaxSize = Vector2.new(1360, 860)
end

local function suppressLegacyChild(child, host)
	if child == nil or child == host or (host and child:IsDescendantOf(host)) then
		return
	end

	if child:IsA("GuiObject") then
		child.Visible = false
	elseif child:IsA("UIStroke") or child:IsA("UIGradient") then
		child.Enabled = false
	end

	for _, descendant in ipairs(child:GetDescendants()) do
		if descendant ~= host and not (host and descendant:IsDescendantOf(host)) then
			if descendant:IsA("GuiObject") then
				descendant.Visible = false
			elseif descendant:IsA("UIStroke") or descendant:IsA("UIGradient") then
				descendant.Enabled = false
			end
		end
	end
end

local function guardSuppressedInstance(instance, frame, host)
	if instance == nil or instance == host or (host and instance:IsDescendantOf(host)) then
		return
	end

	if instance:IsA("GuiObject") then
		trackConnection(instance:GetPropertyChangedSignal("Visible"), function()
			if instance.Parent and instance:IsDescendantOf(frame) and (not host or not instance:IsDescendantOf(host)) and instance.Visible then
				instance.Visible = false
			end
		end, legacyConnections)
	elseif instance:IsA("UIStroke") or instance:IsA("UIGradient") then
		trackConnection(instance:GetPropertyChangedSignal("Enabled"), function()
			if instance.Parent and instance:IsDescendantOf(frame) and (not host or not instance:IsDescendantOf(host)) and instance.Enabled then
				instance.Enabled = false
			end
		end, legacyConnections)
	end
end

local function bindLegacySuppression(frame, host)
	disconnectAll(legacyConnections)

	if not frame then
		return
	end

	applyLegacyFrameStyling(frame)

	for _, child in ipairs(frame:GetChildren()) do
		suppressLegacyChild(child, host)
		guardSuppressedInstance(child, frame, host)

		for _, descendant in ipairs(child:GetDescendants()) do
			guardSuppressedInstance(descendant, frame, host)
		end
	end

	trackConnection(frame.ChildAdded, function(child)
		task.defer(function()
			if destroyed then
				return
			end

			suppressLegacyChild(child, host)
			bindLegacySuppression(frame, host)
		end)
	end, legacyConnections)

	trackConnection(frame.DescendantAdded, function(descendant)
		task.defer(function()
			if destroyed or descendant == host or (host and descendant:IsDescendantOf(host)) then
				return
			end

			suppressLegacyChild(descendant, host)
			guardSuppressedInstance(descendant, frame, host)
		end)
	end, legacyConnections)

	trackConnection(frame.ChildRemoved, function(child)
		if child == host then
			task.defer(scheduleRender)
		end
	end, legacyConnections)

	trackConnection(frame:GetPropertyChangedSignal("Visible"), function()
		task.defer(function()
			if destroyed then
				return
			end

			applyLegacyFrameStyling(frame)
			syncOverlayState()
		end)
	end, legacyConnections)
end

local function ensureLegacyHost()
	legacyFrame = findLegacyIndexFrame()

	if not legacyFrame then
		disconnectAll(legacyConnections)
		return nil
	end

	applyLegacyFrameStyling(legacyFrame)

	local host = legacyFrame:FindFirstChild("ReactIndexHost")
	if not host then
		host = Instance.new("Frame")
		host.Name = "ReactIndexHost"
		host.Active = true
		host.BackgroundTransparency = 1
		host.BorderSizePixel = 0
		host.Size = UDim2.fromScale(1, 1)
		host.ZIndex = 140
		host.Parent = legacyFrame
	end

	host.Visible = true
	host.ClipsDescendants = true
	bindLegacySuppression(legacyFrame, host)
	syncOverlayState()

	return host
end

local function ensureFallbackHost()
	if fallbackGui then
		return fallbackGui:WaitForChild("ReactIndexHost")
	end

	fallbackGui = Instance.new("ScreenGui")
	fallbackGui.Name = "ReactIndexGui"
	fallbackGui.DisplayOrder = 160
	fallbackGui.IgnoreGuiInset = true
	fallbackGui.ResetOnSpawn = false
	fallbackGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	fallbackGui.Parent = playerGui

	local host = Instance.new("Frame")
	host.Name = "ReactIndexHost"
	host.Active = true
	host.BackgroundTransparency = 1
	host.BorderSizePixel = 0
	host.Size = UDim2.fromScale(1, 1)
	host.Parent = fallbackGui

	return host
end

local function statusShell(titleText, bodyText, onClose)
	return e("Frame", {
		BackgroundColor3 = Color3.fromRGB(4, 10, 18),
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
	}, {
		Panel = e("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = Color3.fromRGB(9, 18, 31),
			BorderSizePixel = 0,
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(420, 180),
		}, {
			Corner = e("UICorner", {
				CornerRadius = UDim.new(0, 18),
			}),
			Stroke = e("UIStroke", {
				Color = Color3.fromRGB(45, 74, 108),
				Transparency = 0.12,
				Thickness = 1.2,
			}),
			Title = e("TextLabel", {
				BackgroundTransparency = 1,
				Font = Enum.Font.FredokaOne,
				Position = UDim2.fromOffset(22, 20),
				Size = UDim2.new(1, -44, 0, 28),
				Text = titleText,
				TextColor3 = Color3.fromRGB(245, 250, 255),
				TextSize = 24,
				TextXAlignment = Enum.TextXAlignment.Left,
			}),
			Body = e("TextLabel", {
				BackgroundTransparency = 1,
				Font = Enum.Font.FredokaOne,
				Position = UDim2.fromOffset(22, 58),
				Size = UDim2.new(1, -44, 0, 46),
				Text = bodyText,
				TextColor3 = Color3.fromRGB(184, 198, 220),
				TextSize = 14,
				TextWrapped = true,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextYAlignment = Enum.TextYAlignment.Top,
			}),
			Close = onClose and e("TextButton", {
				AnchorPoint = Vector2.new(1, 1),
				AutoButtonColor = false,
				BackgroundColor3 = Color3.fromRGB(255, 198, 85),
				BorderSizePixel = 0,
				Position = UDim2.new(1, -22, 1, -18),
				Size = UDim2.fromOffset(118, 38),
				Text = "Close",
				TextColor3 = Color3.fromRGB(15, 24, 42),
				TextSize = 16,
				Font = Enum.Font.FredokaOne,
				[React.Event.Activated] = onClose,
			}, {
				Corner = e("UICorner", {
					CornerRadius = UDim.new(0, 12),
				}),
			}) or nil,
		}),
	})
end

local function StandaloneIndexApp()
	local _, indexScreen = loadIndexModules()
	local hasLiveState = inventoryFolder ~= nil
		or indexCollectionFolder ~= nil
		or brainrotInventoryFolder ~= nil
		or devilFruitStateFolder ~= nil
		or indexRewardsFolder ~= nil
	local viewModel = buildViewModel(not hasLiveState)
	local isOpen, setIsOpen = React.useState(true)

	if not isOpen then
		return e("Frame", {
			BackgroundColor3 = Color3.fromRGB(4, 10, 18),
			BorderSizePixel = 0,
			Size = UDim2.fromScale(1, 1),
		}, {
			OpenButton = e("TextButton", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				AutoButtonColor = false,
				BackgroundColor3 = Color3.fromRGB(255, 198, 85),
				BorderSizePixel = 0,
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromOffset(180, 48),
				Text = "Open Index",
				TextColor3 = Color3.fromRGB(15, 24, 42),
				TextSize = 18,
				Font = Enum.Font.FredokaOne,
				[React.Event.Activated] = function()
					setIsOpen(true)
				end,
			}, {
				Corner = e("UICorner", {
					CornerRadius = UDim.new(0, 14),
				}),
			}),
		})
	end

	if not indexScreen then
		return statusShell("Loading Index", "Preparing the new Index view. This should only take a moment.", function()
			setIsOpen(false)
		end)
	end

	return e("Frame", {
		BackgroundColor3 = Color3.fromRGB(4, 10, 18),
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
	}, {
		Backdrop = e("Frame", {
			BackgroundColor3 = Color3.fromRGB(4, 10, 18),
			BackgroundTransparency = 0.14,
			BorderSizePixel = 0,
			Size = UDim2.fromScale(1, 1),
		}),
		Panel = e("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundTransparency = 1,
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.new(0.9, 0, 0.84, 0),
		}, {
			Constraint = e("UISizeConstraint", {
				MaxSize = Vector2.new(1360, 860),
				MinSize = Vector2.new(1080, 680),
			}),
			Screen = e(indexScreen, {
				categories = viewModel.categories,
				claimableCount = viewModel.claimableCount,
				collectionStats = viewModel.collectionStats,
				devilFruitCollection = viewModel.devilFruitCollection,
				onClaimRewardRequested = fireClaimReward,
				onClose = function()
					setIsOpen(false)
				end,
				rewards = viewModel.rewards,
				tabs = viewModel.tabs,
				units = viewModel.units,
			}),
		}),
	})
end

fireClaimReward = function(rewardId)
	local rewardKey = tostring(rewardId or "")
	if rewardKey == "" or pendingClaimRequests[rewardKey] then
		return
	end

	local remote = getClaimRemote()
	if remote then
		pendingClaimRequests[rewardKey] = true
		remote:FireServer(rewardId)
		task.delay(6, function()
			if pendingClaimRequests[rewardKey] then
				pendingClaimRequests[rewardKey] = nil
				task.defer(scheduleRender)
			end
		end)
		task.defer(scheduleRender)
	else
		warn("[IndexReact] ClaimIndexReward remote was unavailable when trying to claim a milestone reward.")
	end
end

local function render()
	if destroyed then
		return
	end

	uiController = modalAdapter:GetUiController()

	local host = modalAdapter:EnsureHost()
	if host then
		legacyFrame = modalAdapter:GetFrame()
		local _, indexScreen = loadIndexModules()
		local viewModel = buildViewModel(false)

		modalAdapter:SetFallbackEnabled(false)

		local content
		if indexScreen then
			content = e(indexScreen, {
				categories = viewModel.categories,
				claimableCount = viewModel.claimableCount,
				collectionStats = viewModel.collectionStats,
				devilFruitCollection = viewModel.devilFruitCollection,
				onClaimRewardRequested = fireClaimReward,
				onClose = function()
					modalAdapter:Close()
				end,
				rewards = viewModel.rewards,
				tabs = viewModel.tabs,
				units = viewModel.units,
			})
		else
			content = statusShell(
				"Loading Index",
				"Preparing the new Index view. This should only take a moment.",
				function()
					modalAdapter:Close()
				end
			)
		end

		root:render(ReactRoblox.createPortal(content, host))
		modalAdapter:SyncOverlayState()
		return
	end

	local fallbackHost = modalAdapter:EnsureFallbackHost()
	modalAdapter:SetFallbackEnabled(true)
	modalAdapter:HideBackdrop()
	UiModalState.SetOpen("IndexModal", false)

	root:render(ReactRoblox.createPortal(e(StandaloneIndexApp), fallbackHost))
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

refreshLiveFolders()

trackConnection(player.ChildAdded, function(child)
	if child.Name == "Inventory" then
		bindInventoryFolder(child)
		task.defer(scheduleRender)
	elseif child.Name == "IndexCollection" then
		bindIndexCollectionFolder(child)
		task.defer(scheduleRender)
	elseif child.Name == "BrainrotInventory" then
		bindBrainrotInventoryFolder(child)
		task.defer(scheduleRender)
	elseif child.Name == "DevilFruit" then
		bindDevilFruitStateFolder(child)
		task.defer(scheduleRender)
	elseif child.Name == "IndexRewards" then
		bindIndexRewardsFolder(child)
		task.defer(scheduleRender)
	end
end, cleanupConnections)

trackConnection(player.ChildRemoved, function(child)
	if child == inventoryFolder then
		bindInventoryFolder(nil)
		task.defer(scheduleRender)
	elseif child == indexCollectionFolder then
		bindIndexCollectionFolder(nil)
		task.defer(scheduleRender)
	elseif child == brainrotInventoryFolder then
		bindBrainrotInventoryFolder(nil)
		task.defer(scheduleRender)
	elseif child == devilFruitStateFolder then
		bindDevilFruitStateFolder(nil)
		task.defer(scheduleRender)
	elseif child == indexRewardsFolder then
		bindIndexRewardsFolder(nil)
		task.defer(scheduleRender)
	end
end, cleanupConnections)

trackConnection(player:GetAttributeChangedSignal("EquippedDevilFruit"), function()
	task.defer(scheduleRender)
end, cleanupConnections)

trackConnection(playerGui.ChildAdded, function(child)
	if child.Name == "Frames" or child.Name == "OpenUI" or child.Name == "HUD" then
		if child.Name == "Frames" then
			legacyFrame = nil
			indexBackdrop = nil
		end
		modalAdapter:HandlePlayerGuiChildAdded(child)

		task.defer(scheduleRender)
	end
end, cleanupConnections)

trackConnection(playerGui.ChildRemoved, function(child)
	if child.Name == "Frames" or child.Name == "OpenUI" then
		if child.Name == "Frames" then
			legacyFrame = nil
			indexBackdrop = nil
		end
		modalAdapter:HandlePlayerGuiChildRemoved(child)

		task.defer(scheduleRender)
	end
end, cleanupConnections)

modalAdapter:SetScheduleRender(scheduleRender)
modalAdapter:BindFramesFolderTracking()
render()

script.Destroying:Connect(function()
	destroyed = true
	disconnectAll(cleanupConnections)
	disconnectAll(legacyConnections)
	disconnectAll(framesFolderConnections)
	disconnectAll(inventoryConnections)
	disconnectAll(indexCollectionConnections)
	disconnectAll(brainrotInventoryConnections)
	disconnectAll(devilFruitStateConnections)
	disconnectAll(rewardConnections)
	if claimRemoteConnection then
		claimRemoteConnection:Disconnect()
		claimRemoteConnection = nil
	end
	modalAdapter:Destroy()
	root:unmount()

	if fallbackGui then
		fallbackGui:Destroy()
		fallbackGui = nil
	end
end)
