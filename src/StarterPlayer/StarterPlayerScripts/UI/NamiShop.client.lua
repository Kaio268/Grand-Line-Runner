local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local WipInstanceModalBridge = require(script.Parent:WaitForChild("WipInstanceModalBridge"))

local function bindWipNamiSellGui(gui)
	WipInstanceModalBridge.BindResponsiveModal(gui, {
		displayOrder = 200,
	})
	WipInstanceModalBridge.BindNamiSellButtons(gui)
end

local wipNamiSellGui, ownsWipNamiSell = WipInstanceModalBridge.FindOwnedGui("NamiSellGui", 10)
if wipNamiSellGui then
	bindWipNamiSellGui(wipNamiSellGui)
elseif ownsWipNamiSell then
	WipInstanceModalBridge.WatchGui("NamiSellGui", function(gui)
		bindWipNamiSellGui(gui)
	end)
end
if ownsWipNamiSell then
	return
end

local Packages = ReplicatedStorage:WaitForChild("Packages")
local Modules = ReplicatedStorage:WaitForChild("Modules")
local UiFolder = ReplicatedStorage:WaitForChild("UI")

local React = require(Packages:WaitForChild("React"))
local ReactRoblox = require(Packages:WaitForChild("ReactRoblox"))
local ReactFrameModalAdapter = require(Modules:WaitForChild("ReactFrameModalAdapter"))
local ReactModalRegistry = require(Modules:WaitForChild("ReactModalRegistry"))
local NamiShopScreen = require(UiFolder:WaitForChild("NamiShop"):WaitForChild("NamiShopScreen"))

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
local statusText = "Choose what you want to do."
local statusColor3 = nil
local scheduleRender

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

local function shutdownReactFallback()
	if destroyed then
		return
	end

	destroyed = true
	disconnectAll()
	unregisterModal()
	modalAdapter:Destroy()
	root:unmount()
end

local function openCrewmateInventory()
	ReactModalRegistry.Close("NamiShop")
	ReactModalRegistry.Open("Inventory", {
		ActiveCategory = "CrewMembers",
		ActiveView = "Inventory",
		Source = "NamiShop",
	})
end

local function buildViewModel()
	return {
		inventoryValueText = "Use Inventory",
		equippedItemText = "Stored crewmates only",
		equippedValueText = "Exact sale required",
		hasEquippedValue = false,
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
			openCrewmateInventory()
		end,
		onSellInventory = function()
			openCrewmateInventory()
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

local lateWipNamiConnection = WipInstanceModalBridge.WatchGui("NamiSellGui", function(gui)
	shutdownReactFallback()
	WipInstanceModalBridge.BindNamiSellButtons(gui)
end)
if lateWipNamiConnection then
	connections[#connections + 1] = lateWipNamiConnection
end

render()

script.Destroying:Connect(function()
	shutdownReactFallback()
end)
