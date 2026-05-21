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
local CrewCatalog = require(Modules:WaitForChild("Crew"):WaitForChild("CrewCatalog"))
local CurrencyUtil = require(Modules:WaitForChild("CurrencyUtil"))
local NamiShopScreen = require(UiFolder:WaitForChild("NamiShop"):WaitForChild("NamiShopScreen"))

local LegacyCrewConfig = CrewCatalog.GetLegacyConfig()
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local SellEvent = remotes:WaitForChild("SellItemEvent")
local InventorySnapshotRequest = ReplicatedStorage:WaitForChild("CrewMemberInventorySnapshotRequest", 15)
if InventorySnapshotRequest and not InventorySnapshotRequest:IsA("RemoteFunction") then
	InventorySnapshotRequest = nil
end
local SellDialogDisplayNameRequest = remotes:FindFirstChild("CrewMemberSellDialogDisplayNameRequest")
if SellDialogDisplayNameRequest and not SellDialogDisplayNameRequest:IsA("RemoteFunction") then
	SellDialogDisplayNameRequest = nil
end

local SELL_TIME_SECONDS = 15

local rootContainer = Instance.new("Folder")
rootContainer.Name = "ReactNamiShopRoot"

local root = ReactRoblox.createRoot(rootContainer)
local modalAdapter = ReactFrameModalAdapter.new({
	playerGui = playerGui,
	frameName = "NamiShop",
	hostName = "ReactNamiShopHost",
	backdropName = "ReactNamiShopBackdrop",
	modalStateKey = "NamiShopModal",
	minSize = Vector2.new(430, 360),
	maxSize = Vector2.new(620, 430),
	frameSize = UDim2.fromScale(0.42, 0.42),
	createFrameIfMissing = true,
	standalone = true,
})

local destroyed = false
local renderQueued = false
local connections = {}
local inventoryConnections = {}
local characterConnections = {}
local statusText = "Choose what you want to do."
local statusColor3 = nil
local scheduleRender
local requestInventorySnapshot
local cachedCrewSnapshotEntries = nil
local snapshotRequestInFlight = false
local lastSnapshotRequestAt = 0
local SNAPSHOT_REFRESH_SECONDS = 0.75

local unregisterModal = ReactModalRegistry.Register("NamiShop", {
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
		requestInventorySnapshot(true)
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
	for _, connection in ipairs(connections) do
		connection:Disconnect()
	end
	table.clear(connections)
end

local function disconnectBucket(bucket)
	for _, connection in ipairs(bucket) do
		connection:Disconnect()
	end
	table.clear(bucket)
end

local function getCrewInfo(name)
	return CrewCatalog.GetInfoById(name) or LegacyCrewConfig[name]
end

local function getCrewDisplayName(name)
	local info = getCrewInfo(name)
	if not info then
		return name
	end

	return tostring(info.DisplayName or info.Name or name)
end

local function getSellDialogDisplayName(name)
	local fallbackName = getCrewDisplayName(name)
	if not SellDialogDisplayNameRequest then
		local remote = remotes:FindFirstChild("CrewMemberSellDialogDisplayNameRequest")
		if remote and remote:IsA("RemoteFunction") then
			SellDialogDisplayNameRequest = remote
		end
	end
	if not SellDialogDisplayNameRequest then
		return fallbackName
	end

	local ok, result = pcall(function()
		return SellDialogDisplayNameRequest:InvokeServer(name)
	end)
	if ok and type(result) == "string" and result ~= "" then
		return result
	end
	return fallbackName
end

local function cleanName(raw)
	raw = tostring(raw or "")
	raw = raw:gsub("%(", ""):gsub("%)", "")
	return raw:gsub("^%s+", ""):gsub("%s+$", "")
end

local function getSellPrice(brainrotName)
	local data = getCrewInfo(brainrotName)
	if not data then
		return nil
	end

	if data.SellPrice then
		return tonumber(data.SellPrice)
	end

	local income = tonumber(data.Income)
	if not income then
		return nil
	end

	return income * SELL_TIME_SECONDS
end

local function moneyStr(n)
	n = tonumber(n) or 0
	if math.floor(n) == n then
		return tostring(n)
	end
	return string.format("%.2f", n)
end

local function getEquippedTool()
	return player.Character and player.Character:FindFirstChildOfClass("Tool")
end

local function getClientInventoryFolder()
	return player:FindFirstChild("Inventory")
end

local function getTotalInventorySellValue()
	if typeof(cachedCrewSnapshotEntries) == "table" then
		local total = 0
		for _, entry in ipairs(cachedCrewSnapshotEntries) do
			if typeof(entry) == "table" then
				local name = tostring(entry.CrewMemberId or entry.Name or entry.name or "")
				local quantity = math.max(0, math.floor(tonumber(entry.Quantity or entry.quantity or entry.Qty or 0) or 0))
				if name ~= "" and quantity > 0 then
					total += (getSellPrice(name) or 0) * quantity
				end
			end
		end
		return total
	end

	local inv = getClientInventoryFolder()
	if not inv then
		return 0
	end

	local total = 0
	for _, brainrotFolder in ipairs(inv:GetChildren()) do
		local name = brainrotFolder.Name
		local qObj = brainrotFolder:FindFirstChild("Quantity")
		local qty = qObj and tonumber(qObj.Value) or 0

		if qty > 0 then
			local price = getSellPrice(name) or 0
			total += price * qty
		end
	end

	return total
end

requestInventorySnapshot = function(force)
	if not InventorySnapshotRequest or snapshotRequestInFlight then
		return
	end

	local now = os.clock()
	if force ~= true and now - lastSnapshotRequestAt < SNAPSHOT_REFRESH_SECONDS then
		return
	end

	lastSnapshotRequestAt = now
	snapshotRequestInFlight = true
	task.spawn(function()
		local ok, snapshot = pcall(function()
			return InventorySnapshotRequest:InvokeServer()
		end)
		snapshotRequestInFlight = false

		if ok and typeof(snapshot) == "table" and snapshot.Ready ~= false and typeof(snapshot.Crew) == "table" then
			cachedCrewSnapshotEntries = snapshot.Crew
			if scheduleRender then
				scheduleRender()
	end
end
	end)
end

local function setStatus(text, color)
	statusText = text
	statusColor3 = color
end

local function buildViewModel()
	requestInventorySnapshot(false)

	local tool = getEquippedTool()
	local toolName = tool and cleanName(tool.Name) or nil
	local equippedPrice = toolName and getSellPrice(toolName) or nil
	local currencySuffix = CurrencyUtil.getCompactSuffix()

	return {
		inventoryValueText = moneyStr(getTotalInventorySellValue()) .. currencySuffix,
		equippedItemText = toolName and getSellDialogDisplayName(toolName) or "None",
		equippedValueText = equippedPrice and (moneyStr(equippedPrice) .. currencySuffix) or "Unavailable",
		hasEquippedValue = equippedPrice ~= nil and equippedPrice > 0,
	}
end

local function render()
	local host = modalAdapter:EnsureHost()
	if not host then
		return
	end

	local viewModel = buildViewModel()
	root:render(ReactRoblox.createPortal(React.createElement(NamiShopScreen, {
		equippedItemText = viewModel.equippedItemText,
		equippedValueText = viewModel.equippedValueText,
		hasEquippedValue = viewModel.hasEquippedValue,
		inventoryValueText = viewModel.inventoryValueText,
		onClose = function()
			ReactModalRegistry.Close("NamiShop")
		end,
		onSellEquipped = function()
			local tool = getEquippedTool()
			if not tool then
				setStatus("You do not have any item equipped.", Color3.fromRGB(239, 199, 109))
				task.defer(render)
				return
			end

			local name = cleanName(tool.Name)
			local price = getSellPrice(name)
			if not price or price <= 0 then
				setStatus("You cannot sell this item.", Color3.fromRGB(239, 199, 109))
				task.defer(render)
				return
			end

			SellEvent:FireServer("SINGLE", tool.Name)
			cachedCrewSnapshotEntries = nil
			setStatus(
				("%s sold for %s%s."):format(
					getSellDialogDisplayName(name),
					moneyStr(price),
					CurrencyUtil.getCompactSuffix()
				),
				Color3.fromRGB(132, 220, 158)
			)
			task.delay(0.25, function()
				requestInventorySnapshot(true)
			end)
			task.defer(render)
		end,
		onSellInventory = function()
			local total = getTotalInventorySellValue()
			SellEvent:FireServer("ALL")
			cachedCrewSnapshotEntries = nil
			setStatus(
				("Inventory sold for %s%s."):format(moneyStr(total), CurrencyUtil.getCompactSuffix()),
				Color3.fromRGB(132, 220, 158)
			)
			task.delay(0.25, function()
				requestInventorySnapshot(true)
			end)
			task.defer(render)
		end,
		statusColor3 = statusColor3,
		statusText = statusText,
	}), host))
	modalAdapter:SyncOverlayState()
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

local inventory = player:WaitForChild("Inventory")

local function bindInventoryFolder(folder)
	disconnectBucket(inventoryConnections)

	local function bindQuantity(child)
		local quantity = child:FindFirstChild("Quantity")
		if quantity and quantity:IsA("ValueBase") then
			inventoryConnections[#inventoryConnections + 1] = quantity:GetPropertyChangedSignal("Value"):Connect(scheduleRender)
		end
	end

	for _, child in ipairs(folder:GetChildren()) do
		bindQuantity(child)
	end

	inventoryConnections[#inventoryConnections + 1] = folder.ChildAdded:Connect(function(child)
		bindQuantity(child)
		scheduleRender()
	end)
	inventoryConnections[#inventoryConnections + 1] = folder.ChildRemoved:Connect(scheduleRender)
end

local function bindCharacter(character)
	disconnectBucket(characterConnections)
	if not character then
		return
	end

	characterConnections[#characterConnections + 1] = character.ChildAdded:Connect(scheduleRender)
	characterConnections[#characterConnections + 1] = character.ChildRemoved:Connect(scheduleRender)
end

bindInventoryFolder(inventory)
bindCharacter(player.Character)
connections[#connections + 1] = player.CharacterAdded:Connect(function(character)
	bindCharacter(character)
	scheduleRender()
end)

render()

script.Destroying:Connect(function()
	destroyed = true
	disconnectAll()
	disconnectBucket(inventoryConnections)
	disconnectBucket(characterConnections)
	unregisterModal()
	modalAdapter:Destroy()
	root:unmount()
end)
