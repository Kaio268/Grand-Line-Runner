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
local CometMerchantScreen = require(UiFolder:WaitForChild("CometMerchant"):WaitForChild("CometMerchantScreen"))

local PurchaseRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("CometMerchantPurchase")

local rootContainer = Instance.new("Folder")
rootContainer.Name = "ReactCometMerchantRoot"

local root = ReactRoblox.createRoot(rootContainer)
local modalAdapter = ReactFrameModalAdapter.new({
	playerGui = playerGui,
	frameName = "CometMerchant",
	hostName = "ReactCometMerchantHost",
	backdropName = "ReactCometMerchantBackdrop",
	modalStateKey = "CometMerchantModal",
	minSize = Vector2.new(700, 520),
	maxSize = Vector2.new(980, 760),
	frameSize = UDim2.fromScale(0.62, 0.72),
	createFrameIfMissing = true,
	standalone = true,
})

local destroyed = false
local renderQueued = false
local connections = {}
local offerConnections = {}
local scheduleRender

local unregisterModal = ReactModalRegistry.Register("CometMerchant", {
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

local function disconnectConnections(list)
	for _, connection in ipairs(list) do
		connection:Disconnect()
	end
	table.clear(list)
end

local function buildOffers()
	local merchant = player:FindFirstChild("CometMerchant")
	if not merchant then
		return {}
	end

	local offers = {}
	for _, instance in ipairs(merchant:GetChildren()) do
		if instance:IsA("NumberValue") and instance:GetAttribute("IsOffer") == true then
			offers[#offers + 1] = {
				source = instance,
				fullPath = tostring(instance:GetAttribute("FullPath") or instance.Name),
				name = "+" .. tostring(instance:GetAttribute("Display_name") or ""),
				description = tostring(instance:GetAttribute("Desc") or ""),
				icon = tostring(instance:GetAttribute("Icon") or ""),
				price = tonumber(instance:GetAttribute("Price")) or 0,
				stock = tonumber(instance.Value) or 0,
				index = tonumber(instance:GetAttribute("OfferIndex")) or 0,
			}
		end
	end

	table.sort(offers, function(a, b)
		return a.index < b.index
	end)

	while #offers > 3 do
		table.remove(offers)
	end

	return offers
end

local function render()
	local host = modalAdapter:EnsureHost()
	if not host then
		return
	end

	root:render(ReactRoblox.createPortal(React.createElement(CometMerchantScreen, {
		offers = buildOffers(),
		onBuy = function(fullPath)
			PurchaseRemote:FireServer(fullPath)
		end,
		onClose = function()
			ReactModalRegistry.Close("CometMerchant")
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

local function bindOfferSignals()
	disconnectConnections(offerConnections)
	local merchant = player:FindFirstChild("CometMerchant")
	if not merchant then
		return
	end

	for _, offer in ipairs(buildOffers()) do
		offerConnections[#offerConnections + 1] = offer.source:GetPropertyChangedSignal("Value"):Connect(scheduleRender)
		offerConnections[#offerConnections + 1] = offer.source:GetAttributeChangedSignal("IsOffer"):Connect(function()
			bindOfferSignals()
			scheduleRender()
		end)
		offerConnections[#offerConnections + 1] = offer.source:GetAttributeChangedSignal("OfferIndex"):Connect(function()
			bindOfferSignals()
			scheduleRender()
		end)
	end
end

local merchant = player:WaitForChild("CometMerchant")
connections[#connections + 1] = merchant.ChildAdded:Connect(function()
	bindOfferSignals()
	scheduleRender()
end)
connections[#connections + 1] = merchant.ChildRemoved:Connect(function()
	bindOfferSignals()
	scheduleRender()
end)

bindOfferSignals()
render()

script.Destroying:Connect(function()
	destroyed = true
	disconnectConnections(connections)
	disconnectConnections(offerConnections)
	unregisterModal()
	modalAdapter:Destroy()
	root:unmount()
end)
