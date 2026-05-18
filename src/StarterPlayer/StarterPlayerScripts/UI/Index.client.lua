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
local ReactModalRegistry = require(Modules:WaitForChild("ReactModalRegistry"))

local IndexFolder = UiFolder:WaitForChild("Index")

local e = React.createElement

local rootContainer = Instance.new("Folder")
rootContainer.Name = "ReactIndexRoot"

local root = ReactRoblox.createRoot(rootContainer)
local destroyed = false
local renderQueued = false
local moduleRetryQueued = false

local inventoryFolder = nil
local indexCollectionFolder = nil
local crewMemberInventoryFolder = nil
local devilFruitStateFolder = nil
local indexRewardsFolder = nil
local claimRemote = nil

local cleanupConnections = {}
local inventoryConnections = {}
local indexCollectionConnections = {}
local crewMemberInventoryConnections = {}
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
local CLAIM_REWARD_RENDER_HOLD_TIME = 0.32
local INDEX_DISPLAY_METADATA_REMOTE_NAME = "IndexDisplayMetadataRequest"
local INDEX_DISPLAY_METADATA_RETRY_SECONDS = 5
local INDEX_DISPLAY_METADATA_MAX_CACHE_SECONDS = 30
local claimRewardRenderHoldUntil = 0
local claimRewardRenderHoldQueued = false
local indexDisplayMetadata = nil
local indexDisplayMetadataExpiresAt = 0
local indexDisplayMetadataRequestInFlight = false
local indexDisplayMetadataNextRefreshAt = 0
local lastFruitLifetimeMismatchWarning = nil
local modalAdapter = ReactFrameModalAdapter.new({
	playerGui = playerGui,
	frameName = "Index",
	hostName = "ReactIndexHost",
	backdropName = "ReactIndexBackdrop",
	backdropActive = false,
	modalStateKey = "IndexModal",
	minSize = Vector2.new(1080, 680),
	maxSize = Vector2.new(1360, 860),
	allowFallback = true,
	createFrameIfMissing = true,
	standalone = true,
	bypassLegacyScaleAnimation = true,
})

local unregisterModal = ReactModalRegistry.Register("Index", {
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

local function buildEmptyViewModel()
	return {
		tabs = {
			{ id = "index", label = "Index", eyebrow = "Collection" },
			{ id = "fruits", label = "Fruits", eyebrow = "Devil Fruits" },
			{ id = "rewards", label = "Rewards", eyebrow = "Milestones" },
		},
		categories = {},
		units = {},
		unitsByCategory = {},
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

local function holdClaimRewardRenders()
	claimRewardRenderHoldUntil = math.max(claimRewardRenderHoldUntil, os.clock() + CLAIM_REWARD_RENDER_HOLD_TIME)
end

local function scheduleClaimAwareRender()
	if destroyed then
		return
	end

	local remainingHold = claimRewardRenderHoldUntil - os.clock()
	if remainingHold > 0 then
		if claimRewardRenderHoldQueued then
			return
		end

		claimRewardRenderHoldQueued = true
		task.delay(remainingHold, function()
			claimRewardRenderHoldQueued = false
			if destroyed then
				return
			end

			if claimRewardRenderHoldUntil > os.clock() then
				scheduleClaimAwareRender()
				return
			end

			if scheduleRender then
				scheduleRender()
			end
		end)
		return
	end

	if scheduleRender then
		task.defer(scheduleRender)
	end
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

local function bindInventoryFolder(folder)
	if inventoryFolder == folder then
		return false
	end

	inventoryFolder = folder
	bindLiveValueTree(folder, inventoryConnections)
	return true
end

local function bindIndexCollectionFolder(folder)
	if indexCollectionFolder == folder then
		return false
	end

	indexCollectionFolder = folder
	bindLiveValueTree(folder, indexCollectionConnections)
	return true
end

local function bindCrewMemberInventoryFolder(folder)
	if crewMemberInventoryFolder == folder then
		return false
	end

	crewMemberInventoryFolder = folder
	bindLiveValueTree(folder, crewMemberInventoryConnections)
	return true
end

local function bindDevilFruitStateFolder(folder)
	if devilFruitStateFolder == folder then
		return false
	end

	devilFruitStateFolder = folder
	bindLiveValueTree(folder, devilFruitStateConnections)
	return true
end

local function bindIndexRewardsFolder(folder)
	if indexRewardsFolder == folder then
		return false
	end

	disconnectAll(rewardConnections)
	indexRewardsFolder = folder

	if not indexRewardsFolder then
		return true
	end

	local function bindRewardValue(child)
		if child:IsA("BoolValue") then
			trackConnection(child:GetPropertyChangedSignal("Value"), function()
				scheduleClaimAwareRender()
			end, rewardConnections)
		end
	end

	for _, child in ipairs(indexRewardsFolder:GetChildren()) do
		bindRewardValue(child)
	end

	trackConnection(indexRewardsFolder.ChildAdded, function(child)
		bindRewardValue(child)
		scheduleClaimAwareRender()
	end, rewardConnections)

	trackConnection(indexRewardsFolder.ChildRemoved, function()
		scheduleClaimAwareRender()
	end, rewardConnections)

	return true
end

local function getLivePlayerChild(childName, shouldWait)
	local child = player:FindFirstChild(childName)
	if not child and shouldWait == true then
		child = player:WaitForChild(childName, 1)
	end

	return child
end

local function refreshLiveFolders(shouldWait)
	local changed = false

	changed = bindInventoryFolder(getLivePlayerChild("Inventory", shouldWait)) or changed
	changed = bindIndexCollectionFolder(getLivePlayerChild("IndexCollection", shouldWait)) or changed
	changed = bindCrewMemberInventoryFolder(getLivePlayerChild("CrewMemberInventory", shouldWait)) or changed
	changed = bindDevilFruitStateFolder(player:FindFirstChild("DevilFruit")) or changed
	changed = bindIndexRewardsFolder(player:FindFirstChild("IndexRewards")) or changed

	return changed
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

local function countReplicatedLifetimeDevilFruits()
	local liveIndexCollection = player:FindFirstChild("IndexCollection")
	local devilFruits = liveIndexCollection and liveIndexCollection:FindFirstChild("DevilFruits")
	if not devilFruits then
		return 0, false
	end

	local count = 0
	for _, child in ipairs(devilFruits:GetChildren()) do
		if child:IsA("BoolValue") and child.Value == true then
			count += 1
		end
	end

	return count, true
end

local function warnIfFruitCollectionTrailsLifetime(viewModel)
	local lifetimeCount, hasLifetimeFolder = countReplicatedLifetimeDevilFruits()
	if not hasLifetimeFolder then
		return
	end

	local devilFruitCollection = viewModel and viewModel.devilFruitCollection
	local stats = devilFruitCollection and devilFruitCollection.collectionStats
	local renderedCount = if typeof(stats) == "table" then tonumber(stats.collected) or 0 else 0
	if renderedCount >= lifetimeCount then
		return
	end

	local signature = tostring(renderedCount) .. "/" .. tostring(lifetimeCount)
	if lastFruitLifetimeMismatchWarning == signature then
		return
	end

	lastFruitLifetimeMismatchWarning = signature
	warn(
		string.format(
			"[IndexReact] Fruits view model is behind replicated lifetime data: rendered=%d lifetime=%d",
			renderedCount,
			lifetimeCount
		)
	)
end

local function findRemoteFunctionByName(parent, remoteName)
	for _, child in ipairs(parent:GetChildren()) do
		if child.Name == remoteName and child:IsA("RemoteFunction") then
			return child
		end
	end

	return nil
end

local function waitForRemoteFunctionByName(parent, remoteName, timeoutSeconds)
	local deadline = os.clock() + (timeoutSeconds or 2)

	repeat
		local remote = findRemoteFunctionByName(parent, remoteName)
		if remote then
			return remote
		end

		task.wait(0.1)
	until os.clock() >= deadline

	return findRemoteFunctionByName(parent, remoteName)
end

local function getActiveIndexDisplayMetadata()
	if typeof(indexDisplayMetadata) == "table" and os.clock() < indexDisplayMetadataExpiresAt then
		return indexDisplayMetadata
	end

	indexDisplayMetadata = nil
	indexDisplayMetadataExpiresAt = 0
	return nil
end

local function refreshIndexDisplayMetadata(reason, force)
	if indexDisplayMetadataRequestInFlight or destroyed then
		return
	end

	local now = os.clock()
	if force ~= true and now < indexDisplayMetadataNextRefreshAt then
		return
	end

	indexDisplayMetadataNextRefreshAt = now + INDEX_DISPLAY_METADATA_RETRY_SECONDS
	indexDisplayMetadataRequestInFlight = true

	task.spawn(function()
		local remote = findRemoteFunctionByName(ReplicatedStorage, INDEX_DISPLAY_METADATA_REMOTE_NAME)
			or waitForRemoteFunctionByName(ReplicatedStorage, INDEX_DISPLAY_METADATA_REMOTE_NAME, 2)
		local nextMetadata = nil
		local nextExpiresAt = 0

		if remote then
			local ok, response = pcall(function()
				return remote:InvokeServer(reason or "index_display")
			end)

			if
				ok
				and typeof(response) == "table"
				and response.Ready == true
				and typeof(response.Metadata) == "table"
			then
				nextMetadata = response.Metadata
				local expiresAfter = math.clamp(
					tonumber(response.ExpiresAfterSeconds) or INDEX_DISPLAY_METADATA_MAX_CACHE_SECONDS,
					1,
					INDEX_DISPLAY_METADATA_MAX_CACHE_SECONDS
				)
				nextExpiresAt = os.clock() + expiresAfter
			end
		end

		indexDisplayMetadata = nextMetadata
		indexDisplayMetadataExpiresAt = nextExpiresAt
		indexDisplayMetadataRequestInFlight = false

		if scheduleRender and not destroyed then
			task.defer(scheduleRender)
		end
	end)
end

local function buildViewModel(previewMode)
	refreshLiveFolders(false)

	local indexData = select(1, loadIndexModules())
	if not indexData then
		return buildEmptyViewModel()
	end

	local activeIndexDisplayMetadata = getActiveIndexDisplayMetadata()
	if activeIndexDisplayMetadata == nil and previewMode ~= true then
		refreshIndexDisplayMetadata("view_model")
	end

	local ok, viewModelOrError = pcall(indexData.buildViewModel, {
		crewMemberInventory = crewMemberInventoryFolder,
		claimedRewardOverrides = claimedRewardOverrides,
		equippedDevilFruit = getEquippedDevilFruit(),
		indexDisplayMetadata = activeIndexDisplayMetadata,
		indexCollection = indexCollectionFolder,
		indexRewardsFolder = indexRewardsFolder,
		inventory = inventoryFolder,
		previewMode = previewMode == true,
	})
	if ok and typeof(viewModelOrError) == "table" then
		lastIndexViewModelError = nil
		if previewMode ~= true then
			warnIfFruitCollectionTrailsLifetime(viewModelOrError)
		end
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

local function syncHudIndexBadge(viewModel)
	local hud = playerGui:FindFirstChild("HUD")
	local lButtons = hud and hud:FindFirstChild("LButtons")
	local indexButton = lButtons and lButtons:FindFirstChild("Index")
	local badge = indexButton and indexButton:FindFirstChild("Not", true)
	if not badge then
		return
	end

	local claimableCount = math.max(0, tonumber(viewModel and viewModel.claimableCount) or 0)
	badge.Visible = claimableCount > 0

	local textLabel = badge:FindFirstChild("TextLB", true)
	if textLabel and textLabel:IsA("TextLabel") then
		textLabel.Text = tostring(math.min(99, claimableCount))
	end
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
				holdClaimRewardRenders()
			end
		end

		if success == true then
			scheduleClaimAwareRender()
		else
			task.defer(scheduleRender)
		end
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
		or crewMemberInventoryFolder ~= nil
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
			Size = UDim2.fromScale(0.9, 0.84),
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
				unitsByCategory = viewModel.unitsByCategory,
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
		holdClaimRewardRenders()
		remote:FireServer(rewardId)
		task.delay(6, function()
			if pendingClaimRequests[rewardKey] then
				pendingClaimRequests[rewardKey] = nil
			end
		end)
	else
		warn("[IndexReact] ClaimIndexReward remote was unavailable when trying to claim a milestone reward.")
	end
end

local function render()
	if destroyed then
		return
	end

	local host = modalAdapter:EnsureHost()
	if host then
		modalAdapter:SetFallbackEnabled(false)

		local content
		local _, indexScreen = loadIndexModules()
		if indexScreen then
			local viewModel = buildViewModel(false)

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
				unitsByCategory = viewModel.unitsByCategory,
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

refreshLiveFolders(true)
refreshIndexDisplayMetadata("startup", true)

trackConnection(player.ChildAdded, function(child)
	if child.Name == "Inventory" then
		bindInventoryFolder(child)
		refreshIndexDisplayMetadata("inventory_added")
		task.defer(scheduleRender)
	elseif child.Name == "IndexCollection" then
		bindIndexCollectionFolder(child)
		refreshIndexDisplayMetadata("index_collection_added")
		task.defer(scheduleRender)
	elseif child.Name == "CrewMemberInventory" then
		bindCrewMemberInventoryFolder(child)
		refreshIndexDisplayMetadata("crew_member_inventory_added")
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
		refreshIndexDisplayMetadata("inventory_removed")
		task.defer(scheduleRender)
	elseif child == indexCollectionFolder then
		bindIndexCollectionFolder(nil)
		refreshIndexDisplayMetadata("index_collection_removed")
		task.defer(scheduleRender)
	elseif child == crewMemberInventoryFolder then
		bindCrewMemberInventoryFolder(nil)
		refreshIndexDisplayMetadata("crew_member_inventory_removed")
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
		modalAdapter:HandlePlayerGuiChildAdded(child)

		task.defer(scheduleRender)
	end
end, cleanupConnections)

trackConnection(playerGui.ChildRemoved, function(child)
	if child.Name == "Frames" or child.Name == "OpenUI" then
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
	disconnectAll(inventoryConnections)
	disconnectAll(indexCollectionConnections)
	disconnectAll(crewMemberInventoryConnections)
	disconnectAll(devilFruitStateConnections)
	disconnectAll(rewardConnections)
	if claimRemoteConnection then
		claimRemoteConnection:Disconnect()
		claimRemoteConnection = nil
	end
	unregisterModal()
	modalAdapter:Destroy()
	root:unmount()
end)
