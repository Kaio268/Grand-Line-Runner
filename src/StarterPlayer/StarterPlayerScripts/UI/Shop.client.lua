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

local ShopFolder = UiFolder:WaitForChild("Shop")
local ShopShell = require(ShopFolder:WaitForChild("ShopShell"))
local Catalog = require(ShopFolder:WaitForChild("Catalog"))
local PurchaseAdapter = require(ShopFolder:WaitForChild("PurchaseAdapter"))

local rootContainer = Instance.new("Folder")
rootContainer.Name = "ReactShopRoot"

local FRAMES_DISPLAY_ORDER = 120

local root = ReactRoblox.createRoot(rootContainer)

local destroyed = false
local renderQueued = false
local noticeText = nil
local noticeToken = 0

local framesGui = playerGui:WaitForChild("Frames")
local storeFrame = framesGui:WaitForChild("Store")
local shopBackdrop = framesGui:FindFirstChild("ReactStoreBackdrop")
if not shopBackdrop then
	shopBackdrop = Instance.new("Frame")
	shopBackdrop.Name = "ReactStoreBackdrop"
	shopBackdrop.BackgroundColor3 = Color3.fromRGB(3, 8, 18)
	shopBackdrop.BackgroundTransparency = 0.42
	shopBackdrop.BorderSizePixel = 0
	shopBackdrop.Size = UDim2.fromScale(1, 1)
	shopBackdrop.Visible = false
	shopBackdrop.ZIndex = 80
	shopBackdrop.Active = true
	shopBackdrop.Parent = framesGui
end

local shopHost = storeFrame:FindFirstChild("ReactStoreHost")
if not shopHost then
	shopHost = Instance.new("Frame")
	shopHost.Name = "ReactStoreHost"
	shopHost.BackgroundTransparency = 1
	shopHost.BorderSizePixel = 0
	shopHost.Size = UDim2.fromScale(1, 1)
	shopHost.ZIndex = 140
	shopHost.Active = true
	shopHost.Parent = storeFrame
end

local openUiScript = playerGui:WaitForChild("OpenUI")
local openUiModule = openUiScript:WaitForChild("Open_UI")
local uiController = require(openUiModule)

local purchaseAdapter = PurchaseAdapter.new(player)
local cleanupConnections = {}

local scheduleRender

local function suppressLegacyStoreDecor()
	for _, child in ipairs(storeFrame:GetChildren()) do
		if child ~= shopHost then
			if child:IsA("GuiObject") then
				child.Visible = false
			elseif child:IsA("UIStroke") or child:IsA("UIGradient") then
				child.Enabled = false
			end
		end
	end
end

local function ensureStoreFrameLayout()
	if framesGui:IsA("ScreenGui") then
		framesGui.DisplayOrder = math.max(framesGui.DisplayOrder, FRAMES_DISPLAY_ORDER)
		framesGui.IgnoreGuiInset = true
		framesGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	end

	storeFrame.AnchorPoint = Vector2.new(0.5, 0.5)
	storeFrame.Position = UDim2.fromScale(0.5, 0.5)
	storeFrame.Size = UDim2.new(0.9, 0, 0.84, 0)
	storeFrame.ClipsDescendants = true
	storeFrame.Active = true
	storeFrame.ZIndex = 120
	shopHost.ZIndex = 140

	local sizeConstraint = storeFrame:FindFirstChild("ReactStoreSizeConstraint")
	if not sizeConstraint then
		sizeConstraint = Instance.new("UISizeConstraint")
		sizeConstraint.Name = "ReactStoreSizeConstraint"
		sizeConstraint.Parent = storeFrame
	end

	sizeConstraint.MinSize = Vector2.new(980, 680)
	sizeConstraint.MaxSize = Vector2.new(1340, 860)
end

local function syncOverlayState()
	local isVisible = storeFrame.Visible
	shopBackdrop.Visible = isVisible
	UiModalState.SetOpen("ShopModal", isVisible)
end

local function disconnectAll()
	for _, connection in ipairs(cleanupConnections) do
		connection:Disconnect()
	end
	table.clear(cleanupConnections)
end

local function hideLegacyStoreContents()
	ensureStoreFrameLayout()
	syncOverlayState()
	storeFrame.BackgroundTransparency = 1
	storeFrame.BorderSizePixel = 0
	storeFrame.ClipsDescendants = true
	suppressLegacyStoreDecor()

	for _, child in ipairs(storeFrame:GetChildren()) do
		if child ~= shopHost and child:IsA("GuiObject") then
			child.Visible = false
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
			if destroyed or noticeToken ~= currentToken then
				return
			end

			noticeText = nil
			if scheduleRender then
				scheduleRender()
			end
		end)
	end
end

local function buildCatalogViewModel()
	local catalog = {
		title = Catalog.title,
		subtitle = Catalog.subtitle,
		heroEyebrow = Catalog.heroEyebrow,
		heroHeadline = Catalog.heroHeadline,
		heroCopy = Catalog.heroCopy,
		codesPanel = Catalog.codesPanel,
		featuredOffers = {},
		sections = {},
	}

	for index, item in ipairs(Catalog.featuredOffers or {}) do
		catalog.featuredOffers[index] = purchaseAdapter:getViewModel(item)
	end

	for sectionIndex, section in ipairs(Catalog.sections or {}) do
		local sectionModel = {
			key = section.key,
			title = section.title,
			eyebrow = section.eyebrow,
			description = section.description,
			themeKey = section.themeKey,
			items = {},
		}

		for itemIndex, item in ipairs(section.items or {}) do
			sectionModel.items[itemIndex] = purchaseAdapter:getViewModel(item)
		end

		catalog.sections[sectionIndex] = sectionModel
	end

	return catalog
end

local function render()
	hideLegacyStoreContents()

	local catalogView = buildCatalogViewModel()
	root:render(ReactRoblox.createPortal(React.createElement(ShopShell, {
		catalog = catalogView,
		noticeText = noticeText,
		onClose = function()
			if uiController and uiController.ToggleFrame then
				uiController:ToggleFrame(storeFrame)
			else
				storeFrame.Visible = false
			end
		end,
		onPurchaseRequested = function(item)
			local success, message = purchaseAdapter:requestPurchase(item)
			if not success and message then
				setNotice(message)
			end
		end,
		onGiftRequested = function(item)
			local itemTitle = item and item.title or "This offer"
			setNotice(itemTitle .. " gifting is not available yet.")
		end,
		onRedeemRequested = function(codeText)
			local trimmed = string.gsub(tostring(codeText or ""), "^%s*(.-)%s*$", "%1")
			if trimmed == "" then
				setNotice("Enter a code before redeeming.")
				return
			end

			setNotice("Code redemption is not active right now. Watch for update and event drops.")
		end,
		onSectionSelected = function()
		end,
	}), shopHost))
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

purchaseAdapter:primeCatalog(Catalog)

table.insert(cleanupConnections, purchaseAdapter:subscribe(scheduleRender))
table.insert(cleanupConnections, storeFrame.ChildAdded:Connect(function()
		task.defer(hideLegacyStoreContents)
	end))
table.insert(cleanupConnections, storeFrame:GetPropertyChangedSignal("Visible"):Connect(function()
		task.defer(syncOverlayState)
		task.defer(hideLegacyStoreContents)
	end))

hideLegacyStoreContents()
render()

script.Destroying:Connect(function()
	destroyed = true
	UiModalState.SetOpen("ShopModal", false)
	disconnectAll()
	purchaseAdapter:destroy()
	shopBackdrop.Visible = false
	root:unmount()
end)
