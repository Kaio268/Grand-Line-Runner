local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MarketplaceService = game:GetService("MarketplaceService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local Modules = ReplicatedStorage:WaitForChild("Modules")
local UiFolder = ReplicatedStorage:WaitForChild("UI")

local React = require(Packages:WaitForChild("React"))
local ReactRoblox = require(Packages:WaitForChild("ReactRoblox"))
local ReactFrameModalAdapter = require(Modules:WaitForChild("ReactFrameModalAdapter"))
local ReactModalRegistry = require(Modules:WaitForChild("ReactModalRegistry"))
local Gears = require(Modules:WaitForChild("Configs"):WaitForChild("Gears"))
local MonetizationConfig = require(Modules:WaitForChild("Configs"):WaitForChild("Monetization"))
local CurrencyUtil = require(Modules:WaitForChild("CurrencyUtil"))
local Shorten = require(Modules:WaitForChild("Shorten"))
local PopUpModule = require(Modules:WaitForChild("PopUpModule"))
local GearStoreScreen = require(UiFolder:WaitForChild("GearStore"):WaitForChild("GearStoreScreen"))

local BuyRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("GearStore")
local RobuxRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("GearStoreRobux")

local rootContainer = Instance.new("Folder")
rootContainer.Name = "ReactGearStoreRoot"

local root = ReactRoblox.createRoot(rootContainer)
local modalAdapter = ReactFrameModalAdapter.new({
	playerGui = playerGui,
	frameName = "GearStore",
	hostName = "ReactGearStoreHost",
	backdropName = "ReactGearStoreBackdrop",
	modalStateKey = "GearStoreModal",
	minSize = Vector2.new(700, 520),
	maxSize = Vector2.new(980, 760),
	frameSize = UDim2.fromScale(0.62, 0.72),
	createFrameIfMissing = true,
	standalone = true,
})

local gearList = {}
local productPriceCache = {}
local connections = {}
local destroyed = false
local renderQueued = false
local scheduleRender

local unregisterModal = ReactModalRegistry.Register("GearStore", {
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

local gearsFolder = player:FindFirstChild("Gears") or player:WaitForChild("Gears", 10)
local backpack = player:FindFirstChildOfClass("Backpack") or player:WaitForChild("Backpack", 10)
if not gearsFolder or not backpack then
	warn("[GearStore] Player Gears or Backpack folder missing; gear store UI disabled.")
	return
end

for gearName, gearData in pairs(Gears) do
	gearList[#gearList + 1] = {
		name = gearName,
		data = gearData,
		price = tonumber(gearData.Price) or 0,
	}
end

table.sort(gearList, function(a, b)
	if a.price == b.price then
		return a.name < b.name
	end
	return a.price < b.price
end)

local function disconnectAll()
	for _, connection in ipairs(connections) do
		connection:Disconnect()
	end
	table.clear(connections)
end

local function hasTool(gearName)
	if backpack:FindFirstChild(gearName) then
		return true
	end
	local character = player.Character
	return character ~= nil and character:FindFirstChild(gearName) ~= nil
end

local function getDevProductPrice(productId)
	if typeof(productId) ~= "number" then
		return 0
	end
	if not MonetizationConfig.CanPromptDeveloperProduct(productId) then
		return 0
	end
	if productPriceCache[productId] ~= nil then
		return productPriceCache[productId]
	end

	local price = 0
	local ok, info = pcall(function()
		return MarketplaceService:GetProductInfo(productId, Enum.InfoType.Product)
	end)
	if ok and typeof(info) == "table" and typeof(info.PriceInRobux) == "number" then
		price = info.PriceInRobux
	end
	productPriceCache[productId] = price
	return price
end

local function showPurchaseUnavailable(productId)
	warn(string.format(
		"[GearStore] Blocked disabled/non-GTR gear product prompt productId=%s",
		tostring(productId)
	))
	pcall(function()
		PopUpModule:Local_SendPopUp(
			MonetizationConfig.UnavailableMessage,
			Color3.fromRGB(255, 104, 104),
			Color3.fromRGB(0, 0, 0),
			3,
			true
		)
	end)
end

local function buildViewModel()
	local items = {}
	for index, gear in ipairs(gearList) do
		local boolValue = gearsFolder:FindFirstChild(gear.name)
		local owned = boolValue and boolValue:IsA("BoolValue")
		local equipped = owned and boolValue.Value == true
		local productId = tonumber(gear.data.ProductID)
		local canPromptRobux = MonetizationConfig.CanPromptDeveloperProduct(productId)
		items[index] = {
			name = gear.name,
			typeText = tostring(gear.data.Type or "Gear"),
			icon = tostring(gear.data.Icon or ""),
			buyText = if equipped then "Equipped" elseif owned then "Equip" else Shorten.roundNumber(gear.price) .. CurrencyUtil.getCompactSuffix(),
			robuxText = if canPromptRobux then "Robux " .. Shorten.roundNumber(getDevProductPrice(productId)) else "Coming Soon",
			robuxEnabled = canPromptRobux,
			showRobux = not owned and not hasTool(gear.name),
		}
	end
	return items
end

local function render()
	local host = modalAdapter:EnsureHost()
	if not host then
		return
	end

	root:render(ReactRoblox.createPortal(React.createElement(GearStoreScreen, {
		items = buildViewModel(),
		onBuy = function(gearName)
			BuyRemote:FireServer(gearName)
		end,
		onClose = function()
			ReactModalRegistry.Close("GearStore")
		end,
		onRobux = function(gearName)
			local gearData = Gears[gearName]
			local productId = gearData and tonumber(gearData.ProductID)
			if not MonetizationConfig.CanPromptDeveloperProduct(productId) then
				showPurchaseUnavailable(productId)
				return
			end
			RobuxRemote:FireServer(gearName)
		end,
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

local function hookBoolValue(child)
	if child:IsA("BoolValue") then
		connections[#connections + 1] = child:GetPropertyChangedSignal("Value"):Connect(scheduleRender)
	end
end

for _, child in ipairs(gearsFolder:GetChildren()) do
	hookBoolValue(child)
end

connections[#connections + 1] = gearsFolder.ChildAdded:Connect(function(child)
	hookBoolValue(child)
	scheduleRender()
end)
connections[#connections + 1] = gearsFolder.ChildRemoved:Connect(scheduleRender)
connections[#connections + 1] = backpack.ChildAdded:Connect(scheduleRender)
connections[#connections + 1] = backpack.ChildRemoved:Connect(scheduleRender)
connections[#connections + 1] = player.CharacterAdded:Connect(scheduleRender)

render()

script.Destroying:Connect(function()
	destroyed = true
	disconnectAll()
	unregisterModal()
	modalAdapter:Destroy()
	root:unmount()
end)
