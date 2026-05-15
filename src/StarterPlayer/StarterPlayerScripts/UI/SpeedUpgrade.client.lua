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
local SpeedUpgradeTutorialBridge = require(Modules:WaitForChild("SpeedUpgradeTutorialBridge"))
local SpeedUpgrade = require(Modules:WaitForChild("Configs"):WaitForChild("SpeedUpgrade"))
local CurrencyUtil = require(Modules:WaitForChild("CurrencyUtil"))
local Shorten = require(Modules:WaitForChild("Shorten"))
local SpeedUpgradeScreen = require(UiFolder:WaitForChild("SpeedUpgrade"):WaitForChild("SpeedUpgradeScreen"))

local BuySpeedUpgradeRemote = ReplicatedStorage:WaitForChild("BuySpeedUpgrade")

local rootContainer = Instance.new("Folder")
rootContainer.Name = "ReactSpeedUpgradeRoot"

local root = ReactRoblox.createRoot(rootContainer)
local modalAdapter = ReactFrameModalAdapter.new({
	playerGui = playerGui,
	frameName = "SpeedUpgrade",
	hostName = "ReactSpeedUpgradeHost",
	backdropName = "ReactSpeedUpgradeBackdrop",
	modalStateKey = "SpeedUpgradeModal",
	minSize = Vector2.new(620, 480),
	maxSize = Vector2.new(900, 680),
	frameSize = UDim2.fromScale(0.62, 0.64),
	createFrameIfMissing = true,
	standalone = true,
})

local destroyed = false
local renderQueued = false
local connections = {}
local productPriceCache = {}
local scheduleRender

local unregisterModal = ReactModalRegistry.Register("SpeedUpgrade", {
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

local hiddenStats = player:WaitForChild("HiddenLeaderstats")
local speedValue = hiddenStats:WaitForChild("Speed")

local upgradeKeys = {}
for key in pairs(SpeedUpgrade) do
	upgradeKeys[#upgradeKeys + 1] = key
end
table.sort(upgradeKeys)

local function disconnectAll()
	for _, connection in ipairs(connections) do
		connection:Disconnect()
	end
	table.clear(connections)
end

local function getProductPrice(productId)
	if typeof(productId) ~= "number" then
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

local function computeCost(config, currentSpeed)
	local starterPrice = tonumber(config.Starter_Price) or 0
	local priceMultiplier = tonumber(config.Price_Mult) or 1
	local addSpeed = tonumber(config.AddSpeed) or 1
	local speed = math.max(tonumber(currentSpeed) or 1, 1)
	local currentLevel = math.max(speed - 1, 0)
	local total = 0

	for offset = 0, addSpeed - 1 do
		total += starterPrice * (priceMultiplier ^ (currentLevel + offset))
	end

	return math.floor(total + 0.5)
end

local function buildViewModel()
	local currentSpeed = tonumber(speedValue.Value) or 0
	local items = {}

	for index, key in ipairs(upgradeKeys) do
		local config = SpeedUpgrade[key]
		local addSpeed = tonumber(config.AddSpeed) or 0
		local productId = tonumber(config.ProductID)
		local cost = computeCost(config, currentSpeed)
		items[index] = {
			key = tostring(key),
			title = string.format("+%s Speed", Shorten.roundNumber(addSpeed)),
			currentText = string.format("Current: %s", Shorten.roundNumber(currentSpeed)),
			afterText = string.format("After: %s", Shorten.roundNumber(currentSpeed + addSpeed)),
			buyText = Shorten.roundNumber(cost) .. CurrencyUtil.getCompactSuffix(),
			robuxText = "" .. Shorten.roundNumber(getProductPrice(productId)),
			productId = productId,
		}
	end

	return items
end

local function syncTutorialRefs(buyButton, closeButton, rootFrame)
	SpeedUpgradeTutorialBridge.SetRefs({
		buyButton = buyButton,
		closeButton = closeButton,
		root = rootFrame,
	})
end

local function render()
	local host = modalAdapter:EnsureHost()
	if not host then
		return
	end

	root:render(ReactRoblox.createPortal(React.createElement(SpeedUpgradeScreen, {
		items = buildViewModel(),
		onBuy = function(key)
			BuySpeedUpgradeRemote:FireServer(key)
		end,
		onClose = function()
			ReactModalRegistry.Close("SpeedUpgrade")
		end,
		onRobux = function(productId)
			if typeof(productId) == "number" then
				MarketplaceService:PromptProductPurchase(player, productId)
			end
		end,
		onRefsChanged = syncTutorialRefs,
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

modalAdapter:SetScheduleRender(scheduleRender)
modalAdapter:BindFramesFolderTracking()

connections[#connections + 1] = speedValue:GetPropertyChangedSignal("Value"):Connect(scheduleRender)
connections[#connections + 1] = playerGui.ChildAdded:Connect(function(child)
	modalAdapter:HandlePlayerGuiChildAdded(child)
end)
connections[#connections + 1] = playerGui.ChildRemoved:Connect(function(child)
	modalAdapter:HandlePlayerGuiChildRemoved(child)
end)
render()

script.Destroying:Connect(function()
	destroyed = true
	disconnectAll()
	unregisterModal()
	SpeedUpgradeTutorialBridge.ClearRefs()
	modalAdapter:Destroy()
	root:unmount()
end)
