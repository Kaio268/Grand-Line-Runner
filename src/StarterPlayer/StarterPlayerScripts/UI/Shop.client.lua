local Players = game:GetService("Players")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local WipInstanceModalBridge = require(script.Parent:WaitForChild("WipInstanceModalBridge"))
local RobuxShopCodesPanel = require(script.Parent:WaitForChild("RobuxShopCodesPanel"))

local SHOP_GUI_NAME = "RobuxShopGui"
local STORE_MODAL_NAME = "Store"

local function configureRobuxShopGui(gui)
	if not (gui and gui:IsA("ScreenGui")) then
		return
	end

	WipInstanceModalBridge.BindResponsiveModal(gui, {
		rootName = "ShopCard",
		displayOrder = 200,
		margin = 24,
		designSize = Vector2.new(1728, 972),
	})
	WipInstanceModalBridge.BindStoreReferenceGrid(gui, {
		rootName = "ShopCard",
		contentName = "Content",
		referenceContentWidth = 1688,
		columns = 3,
		fallbackColumns = 2,
		padding = 14,
		usableInset = 22,
		minPhysicalCellWidth = 128,
		designSize = Vector2.new(1728, 972),
		margin = 24,
	})
	RobuxShopCodesPanel.BindGui(gui)
end

local function bindRobuxShopGui(gui)
	if not (gui and gui:IsA("ScreenGui")) then
		return
	end

	WipInstanceModalBridge.BindModal({
		gui = gui,
		modalName = STORE_MODAL_NAME,
		allowToggle = true,
		consumeRecentExternalToggle = true,
		reconcileToggle = true,
	})
	configureRobuxShopGui(gui)
end

local boundGui, ownsWipShop = WipInstanceModalBridge.BindOwnedModal({
	guiName = SHOP_GUI_NAME,
	modalName = STORE_MODAL_NAME,
	timeoutSeconds = 10,
	allowToggle = true,
	consumeRecentExternalToggle = true,
	reconcileToggle = true,
	onBound = configureRobuxShopGui,
})

if not ownsWipShop then
	warn("[Shop] RobuxShopGui was not found in PlayerGui or StarterGui. Store has no live shop GUI to bind.")

	local lateConnection = WipInstanceModalBridge.WatchGui(SHOP_GUI_NAME, bindRobuxShopGui)
	if lateConnection then
		script.Destroying:Connect(function()
			lateConnection:Disconnect()
		end)
	end
elseif not boundGui then
	task.delay(10, function()
		if playerGui:FindFirstChild(SHOP_GUI_NAME) then
			return
		end

		warn("[Shop] RobuxShopGui is expected from StarterGui but was not added to PlayerGui yet.")
	end)
end
