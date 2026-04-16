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

local ShopFolder = UiFolder:WaitForChild("Shop")
local ShopShell = require(ShopFolder:WaitForChild("ShopShell"))
local Catalog = require(ShopFolder:WaitForChild("Catalog"))
local PurchaseAdapter = require(ShopFolder:WaitForChild("PurchaseAdapter"))

local rootContainer = Instance.new("Folder")
rootContainer.Name = "ReactShopRoot"

local root = ReactRoblox.createRoot(rootContainer)

local destroyed = false
local renderQueued = false
local noticeText = nil
local noticeToken = 0

local modalAdapter = ReactFrameModalAdapter.new({
	playerGui = playerGui,
	frameName = "Store",
	hostName = "ReactStoreHost",
	backdropName = "ReactStoreBackdrop",
	modalStateKey = "ShopModal",
	minSize = Vector2.new(980, 680),
	maxSize = Vector2.new(1340, 860),
	createFrameIfMissing = true,
})

local purchaseAdapter = PurchaseAdapter.new(player)
local cleanupConnections = {}

local scheduleRender

local function suppressLegacyStoreDecor()
	local storeFrame = modalAdapter:GetFrame()
	local shopHost = storeFrame and storeFrame:FindFirstChild("ReactStoreHost")
	if not storeFrame then
		return
	end

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
	local storeFrame = modalAdapter:GetFrame()
	local shopHost = storeFrame and storeFrame:FindFirstChild("ReactStoreHost")
	if not (storeFrame and shopHost) then
		return
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
	modalAdapter:SyncOverlayState()
end

local function disconnectAll()
	for _, connection in ipairs(cleanupConnections) do
		connection:Disconnect()
	end
	table.clear(cleanupConnections)
end

local function hideLegacyStoreContents()
	local storeFrame = modalAdapter:GetFrame()
	local shopHost = storeFrame and storeFrame:FindFirstChild("ReactStoreHost")
	if not (storeFrame and shopHost) then
		return
	end

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
	local host = modalAdapter:EnsureHost()
	if not host then
		return
	end
	hideLegacyStoreContents()

	local catalogView = buildCatalogViewModel()
	root:render(ReactRoblox.createPortal(React.createElement(ShopShell, {
		catalog = catalogView,
		noticeText = noticeText,
		onClose = function()
			modalAdapter:Close()
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

purchaseAdapter:primeCatalog(Catalog)

table.insert(cleanupConnections, purchaseAdapter:subscribe(scheduleRender))
modalAdapter:SetScheduleRender(scheduleRender)
modalAdapter:BindFramesFolderTracking()
table.insert(cleanupConnections, playerGui.ChildAdded:Connect(function(child)
	if child.Name == "Frames" or child.Name == "OpenUI" then
		modalAdapter:HandlePlayerGuiChildAdded(child)
	end
end))
table.insert(cleanupConnections, playerGui.ChildRemoved:Connect(function(child)
	if child.Name == "Frames" or child.Name == "OpenUI" then
		modalAdapter:HandlePlayerGuiChildRemoved(child)
	end
end))

render()

script.Destroying:Connect(function()
	destroyed = true
	disconnectAll()
	purchaseAdapter:destroy()
	modalAdapter:Destroy()
	root:unmount()
end)
