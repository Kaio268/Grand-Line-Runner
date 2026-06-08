local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local Modules = ReplicatedStorage:WaitForChild("Modules")
local UiFolder = ReplicatedStorage:WaitForChild("UI")
local ReactModalRegistry = require(Modules:WaitForChild("ReactModalRegistry"))
local Responsive = require(UiFolder:WaitForChild("Responsive"))
local NamiSellValueUpdater = require(script.Parent:WaitForChild("NamiSellValueUpdater"))

local WipInstanceModalBridge = {}

local boundModalGuis = setmetatable({}, { __mode = "k" })
local boundResponsiveGuis = setmetatable({}, { __mode = "k" })
local boundStoreReferenceGridGuis = setmetatable({}, { __mode = "k" })
local boundSellGuis = setmetatable({}, { __mode = "k" })
local boundSpeedTutorialGuis = setmetatable({}, { __mode = "k" })
local pendingOwnedGuiBinds = {}
local pendingWatchers = {}
local RECENT_TOGGLE_WINDOW_SECONDS = 0.12
local WIP_MODAL_REGISTRY_PRIORITY = 100
local RESPONSIVE_SCALE_NAME = "WipResponsiveFitScale"
local DEFAULT_RESPONSIVE_MARGIN = 24
local REFERENCE_DESIGN_VIEWPORT = Vector2.new(1920, 1080)

local DEFAULT_EXCLUSIVE_MODALS = {
	"Gifts",
	"Index",
	"Inventory",
	"NamiShop",
	"Quest",
	"Rebirth",
	"Settings",
	"SpeedUpgrade",
	"Store",
}

local function isScreenGui(instance)
	return instance and instance:IsA("ScreenGui")
end

local function findStarterGuiSource(guiName)
	local source = StarterGui:FindFirstChild(guiName)
	if isScreenGui(source) then
		return source
	end

	return nil
end

local function findDescendant(root, name, className)
	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant.Name == name and (className == nil or descendant:IsA(className)) then
			return descendant
		end
	end

	return nil
end

local function connectButton(button, callback)
	if not (button and button:IsA("GuiButton")) then
		return nil
	end

	return button.Activated:Connect(callback)
end

local function getViewportSize()
	local camera = Workspace.CurrentCamera
	return camera and camera.ViewportSize or Vector2.new(1280, 720)
end

local function resolveDesignSize(root, options)
	local requestedSize = options and options.designSize
	if typeof(requestedSize) == "Vector2" then
		return requestedSize
	end

	local size = root.Size
	local width = (size.X.Scale * REFERENCE_DESIGN_VIEWPORT.X) + size.X.Offset
	local height = (size.Y.Scale * REFERENCE_DESIGN_VIEWPORT.Y) + size.Y.Offset
	local constraint = root:FindFirstChildOfClass("UISizeConstraint")

	if constraint then
		width = math.clamp(width, constraint.MinSize.X, constraint.MaxSize.X)
		height = math.clamp(height, constraint.MinSize.Y, constraint.MaxSize.Y)
	end

	return Vector2.new(math.max(width, 1), math.max(height, 1))
end

local function getOrCreateResponsiveScale(root)
	local scale = root:FindFirstChild(RESPONSIVE_SCALE_NAME)
	if scale and scale:IsA("UIScale") then
		return scale
	end

	scale = Instance.new("UIScale")
	scale.Name = RESPONSIVE_SCALE_NAME
	scale.Scale = 1
	scale.Parent = root
	return scale
end

local function computeResponsiveScale(root, options)
	local viewportSize = getViewportSize()
	local margin = tonumber(options and options.margin) or DEFAULT_RESPONSIVE_MARGIN
	local availableWidth = math.max(1, viewportSize.X - (margin * 2))
	local availableHeight = math.max(1, viewportSize.Y - (margin * 2))
	local baseSize = resolveDesignSize(root, options)
	local scale = math.min(availableWidth / baseSize.X, availableHeight / baseSize.Y, 1)
	local phoneScaleMultiplier = tonumber(options and options.phoneScaleMultiplier) or 1
	if phoneScaleMultiplier > 0 then
		scale = math.min(scale * phoneScaleMultiplier, 1)
	end

	return math.clamp(scale, 0.1, 1)
end

local function applyPhoneConstraintLayout(root, originalLayout, designSize)
	local constraint = originalLayout and originalLayout.Constraint
	if constraint and constraint.Parent then
		constraint.MinSize = originalLayout.ConstraintMinSize
		constraint.MaxSize = Vector2.new(
			math.max(originalLayout.ConstraintMaxSize.X, designSize.X),
			math.max(originalLayout.ConstraintMaxSize.Y, designSize.Y)
		)
	end

	root.AnchorPoint = Vector2.new(0.5, 0.5)
	root.Position = UDim2.fromScale(0.5, 0.5)
	root.Size = UDim2.fromOffset(designSize.X, designSize.Y)
end

local function restoreOriginalLayout(root, originalLayout)
	if originalLayout then
		local constraint = originalLayout.Constraint
		if constraint and constraint.Parent then
			constraint.MinSize = originalLayout.ConstraintMinSize
			constraint.MaxSize = originalLayout.ConstraintMaxSize
		end

		root.AnchorPoint = originalLayout.AnchorPoint
		root.Position = originalLayout.Position
		root.Size = originalLayout.Size
	end
end

local function isPhoneViewport()
	return Responsive.isPhoneViewport(getViewportSize())
end

function WipInstanceModalBridge.BindResponsiveModal(gui, options)
	if not isScreenGui(gui) then
		return gui
	end

	local existing = boundResponsiveGuis[gui]
	if existing then
		existing.update()
		return gui
	end

	options = if typeof(options) == "table" then options else {}
	local displayOrder = tonumber(options.displayOrder)
	local rootName = tostring(options.rootName or "")
	local root = nil
	local fitScale = nil
	local originalRootLayout = nil

	if rootName ~= "" then
		local candidate = gui:FindFirstChild(rootName)
		if candidate and candidate:IsA("GuiObject") then
			root = candidate
			fitScale = getOrCreateResponsiveScale(root)
			local constraint = root:FindFirstChildOfClass("UISizeConstraint")
			originalRootLayout = {
				AnchorPoint = root.AnchorPoint,
				Position = root.Position,
				Size = root.Size,
				Constraint = constraint,
				ConstraintMinSize = constraint and constraint.MinSize or nil,
				ConstraintMaxSize = constraint and constraint.MaxSize or nil,
			}
		end
	end

	local cameraConnection = nil
	local connections = {}
	local function track(connection)
		table.insert(connections, connection)
		return connection
	end

	local function update()
		if displayOrder then
			gui.DisplayOrder = displayOrder
		end

		if root and root.Parent and fitScale then
			if isPhoneViewport() then
				local designSize = resolveDesignSize(root, options)
				applyPhoneConstraintLayout(root, originalRootLayout, designSize)
				fitScale.Scale = computeResponsiveScale(root, options)
			else
				restoreOriginalLayout(root, originalRootLayout)
				fitScale.Scale = 1
			end
		end
	end

	local function bindCamera()
		if cameraConnection then
			cameraConnection:Disconnect()
			cameraConnection = nil
		end

		local camera = Workspace.CurrentCamera
		if camera then
			cameraConnection = camera:GetPropertyChangedSignal("ViewportSize"):Connect(update)
		end
	end

	bindCamera()
	track(gui:GetPropertyChangedSignal("Enabled"):Connect(update))
	track(Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
		bindCamera()
		update()
	end))

	boundResponsiveGuis[gui] = {
		update = update,
	}

	gui.Destroying:Connect(function()
		for _, connection in ipairs(connections) do
			connection:Disconnect()
		end
		if cameraConnection then
			cameraConnection:Disconnect()
			cameraConnection = nil
		end
		boundResponsiveGuis[gui] = nil
	end)

	task.defer(update)

	return gui
end

function WipInstanceModalBridge.BindStoreReferenceGrid(gui, options)
	if not isScreenGui(gui) then
		return gui
	end

	local existing = boundStoreReferenceGridGuis[gui]
	if existing then
		existing.update()
		return gui
	end

	options = if typeof(options) == "table" then options else {}
	local rootName = tostring(options.rootName or "ShopCard")
	local contentName = tostring(options.contentName or "Content")
	local root = gui:FindFirstChild(rootName)
	local content = root and root:FindFirstChild(contentName)
	if not (content and content:IsA("GuiObject")) then
		return gui
	end

	local referenceContentWidth = tonumber(options.referenceContentWidth) or 1688
	local preferredColumns = math.max(1, math.floor(tonumber(options.columns) or 3))
	local fallbackColumns = math.max(1, math.floor(tonumber(options.fallbackColumns) or math.max(1, preferredColumns - 1)))
	local padPx = math.max(0, math.floor(tonumber(options.padding) or 14))
	local usableInset = math.max(0, tonumber(options.usableInset) or 22)
	local minCellWidth = math.max(1, math.floor(tonumber(options.minCellWidth) or 150))
	local minPhysicalCellWidth = math.max(1, math.floor(tonumber(options.minPhysicalCellWidth) or 128))
	local defaultCellHeight = math.max(1, math.floor(tonumber(options.defaultCellHeight) or 284))

	local gridRecords = {}
	local connections = {}
	local cameraConnection = nil
	local applying = false

	local function track(connection)
		table.insert(connections, connection)
		return connection
	end

	local function computeCellWidth(columnCount)
		return math.max(
			minCellWidth,
			math.floor(((referenceContentWidth - usableInset) - ((columnCount - 1) * padPx)) / columnCount)
		)
	end

	local function getCurrentFitScale()
		local scale = root:FindFirstChild(RESPONSIVE_SCALE_NAME)
		if scale and scale:IsA("UIScale") then
			return math.clamp(tonumber(scale.Scale) or 1, 0.1, 1)
		end

		return computeResponsiveScale(root, options)
	end

	local function resolveCellWidth()
		local preferredCellWidth = computeCellWidth(preferredColumns)
		if (preferredCellWidth * getCurrentFitScale()) >= minPhysicalCellWidth then
			return preferredCellWidth
		end

		return computeCellWidth(fallbackColumns)
	end

	local function applyGrid(grid)
		if not (grid and grid.Parent and grid:IsA("UIGridLayout")) then
			return
		end
		if not isPhoneViewport() then
			return
		end

		local height = tonumber(grid.CellSize.Y.Offset) or 0
		if height <= 0 then
			height = defaultCellHeight
		end

		applying = true
		grid.CellSize = UDim2.fromOffset(resolveCellWidth(), height)
		grid.CellPadding = UDim2.fromOffset(padPx, padPx)
		applying = false
	end

	local function applyBoundGrids()
		for grid in pairs(gridRecords) do
			applyGrid(grid)
		end
	end

	local function bindGrid(grid)
		if gridRecords[grid] or not grid:IsA("UIGridLayout") then
			return
		end

		gridRecords[grid] = true
		track(grid:GetPropertyChangedSignal("CellSize"):Connect(function()
			if not applying then
				applyGrid(grid)
			end
		end))
		track(grid:GetPropertyChangedSignal("CellPadding"):Connect(function()
			if not applying then
				applyGrid(grid)
			end
		end))
		track(grid.Destroying:Connect(function()
			gridRecords[grid] = nil
		end))

		applyGrid(grid)
	end

	for _, descendant in ipairs(content:GetDescendants()) do
		if descendant:IsA("UIGridLayout") then
			bindGrid(descendant)
		end
	end

	track(content.DescendantAdded:Connect(function(descendant)
		if descendant:IsA("UIGridLayout") then
			bindGrid(descendant)
		end
	end))
	track(content:GetPropertyChangedSignal("AbsoluteSize"):Connect(applyBoundGrids))
	local fitScale = root:FindFirstChild(RESPONSIVE_SCALE_NAME)
	if fitScale and fitScale:IsA("UIScale") then
		track(fitScale:GetPropertyChangedSignal("Scale"):Connect(applyBoundGrids))
	end
	track(root.ChildAdded:Connect(function(child)
		if child.Name == RESPONSIVE_SCALE_NAME and child:IsA("UIScale") then
			track(child:GetPropertyChangedSignal("Scale"):Connect(applyBoundGrids))
			applyBoundGrids()
		end
	end))

	local function bindCamera()
		if cameraConnection then
			cameraConnection:Disconnect()
			cameraConnection = nil
		end

		local camera = Workspace.CurrentCamera
		if camera then
			cameraConnection = camera:GetPropertyChangedSignal("ViewportSize"):Connect(applyBoundGrids)
		end
	end

	bindCamera()
	track(Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
		bindCamera()
		applyBoundGrids()
	end))

	boundStoreReferenceGridGuis[gui] = {
		update = applyBoundGrids,
	}

	gui.Destroying:Connect(function()
		for _, connection in ipairs(connections) do
			connection:Disconnect()
		end
		if cameraConnection then
			cameraConnection:Disconnect()
			cameraConnection = nil
		end
		boundStoreReferenceGridGuis[gui] = nil
	end)

	task.defer(applyBoundGrids)

	return gui
end

function WipInstanceModalBridge.HasSourceGui(guiName)
	return findStarterGuiSource(tostring(guiName or "")) ~= nil
end

function WipInstanceModalBridge.FindGui(guiName, timeoutSeconds)
	local existing = playerGui:FindFirstChild(guiName)
	if isScreenGui(existing) then
		return existing
	end

	local timeout = tonumber(timeoutSeconds) or 0
	if timeout <= 0 then
		return nil
	end

	local waited = playerGui:WaitForChild(guiName, timeout)
	if isScreenGui(waited) then
		return waited
	end

	return nil
end

function WipInstanceModalBridge.FindOwnedGui(guiName, timeoutSeconds)
	guiName = tostring(guiName or "")
	if guiName == "" then
		return nil, false
	end

	local existing = WipInstanceModalBridge.FindGui(guiName, 0)
	if existing then
		return existing, true
	end

	if not WipInstanceModalBridge.HasSourceGui(guiName) then
		return nil, false
	end

	local gui = WipInstanceModalBridge.FindGui(guiName, timeoutSeconds or 10)
	return gui, true
end

function WipInstanceModalBridge.CloseExclusiveModals(exceptName)
	for _, modalName in ipairs(DEFAULT_EXCLUSIVE_MODALS) do
		if modalName ~= exceptName then
			pcall(function()
				ReactModalRegistry.Close(modalName)
			end)
		end
	end
end

function WipInstanceModalBridge.BindModal(options)
	if typeof(options) ~= "table" then
		return nil
	end

	local gui = options.gui or WipInstanceModalBridge.FindGui(options.guiName, options.timeoutSeconds)
	if not isScreenGui(gui) then
		return nil
	end

	if boundModalGuis[gui] then
		return gui
	end

	local modalName = tostring(options.modalName or "")
	if modalName == "" then
		return gui
	end

	local lastEnabledChangedAt = -math.huge
	gui:GetPropertyChangedSignal("Enabled"):Connect(function()
		lastEnabledChangedAt = os.clock()
	end)

	local function open(payload)
		if options.closeExclusive ~= false then
			WipInstanceModalBridge.CloseExclusiveModals(modalName)
		end
		if typeof(options.onOpen) == "function" then
			options.onOpen(gui, payload)
		else
			gui.Enabled = true
		end
	end

	local function close()
		if typeof(options.onClose) == "function" then
			options.onClose(gui)
		else
			gui.Enabled = false
		end
	end

	local handlers = {
		open = open,
		close = close,
		isVisible = function()
			return gui.Enabled == true
		end,
	}

	if options.allowToggle == true then
		handlers.toggle = function(payload)
			if options.consumeRecentExternalToggle == true
				and (os.clock() - lastEnabledChangedAt) <= RECENT_TOGGLE_WINDOW_SECONDS
			then
				return
			end

			local targetVisible = gui.Enabled ~= true
			if gui.Enabled then
				close()
			else
				open(payload)
			end

			if options.reconcileToggle == true then
				task.defer(function()
					if not gui.Parent or gui.Enabled == targetVisible then
						return
					end

					if targetVisible then
						open(payload)
					else
						close()
					end
				end)
			end
		end
	end

	local unregister = ReactModalRegistry.Register(modalName, handlers, {
		priority = tonumber(options.registryPriority) or WIP_MODAL_REGISTRY_PRIORITY,
	})
	boundModalGuis[gui] = {
		modalName = modalName,
		unregister = unregister,
	}

	gui.Destroying:Connect(function()
		local binding = boundModalGuis[gui]
		boundModalGuis[gui] = nil
		if binding and typeof(binding.unregister) == "function" then
			binding.unregister()
		end
	end)

	return gui
end

function WipInstanceModalBridge.BindOwnedModal(options)
	if typeof(options) ~= "table" then
		return nil, false
	end

	local guiName = tostring(options.guiName or "")
	local gui, ownsRoute = WipInstanceModalBridge.FindOwnedGui(guiName, options.timeoutSeconds)
	local modalName = tostring(options.modalName or "")

	local function bind(resolvedGui)
		local bindOptions = table.clone(options)
		bindOptions.gui = resolvedGui
		local boundGui = WipInstanceModalBridge.BindModal(bindOptions) or resolvedGui
		if typeof(options.onBound) == "function" then
			options.onBound(boundGui)
		end
	end

	if gui then
		bind(gui)
	elseif ownsRoute and modalName ~= "" and guiName ~= "" then
		local key = modalName .. ":" .. guiName
		if not pendingOwnedGuiBinds[key] then
			pendingOwnedGuiBinds[key] = playerGui.ChildAdded:Connect(function(child)
				if child.Name ~= guiName or not isScreenGui(child) then
					return
				end

				local connection = pendingOwnedGuiBinds[key]
				pendingOwnedGuiBinds[key] = nil
				if connection then
					connection:Disconnect()
				end
				bind(child)
			end)
		end
	end

	return gui, ownsRoute
end

function WipInstanceModalBridge.WatchGui(guiName, callback)
	guiName = tostring(guiName or "")
	if guiName == "" or typeof(callback) ~= "function" then
		return nil
	end

	local existing = WipInstanceModalBridge.FindGui(guiName, 0)
	if existing then
		task.defer(callback, existing)
		return nil
	end

	local key = guiName .. ":" .. tostring(callback)
	if pendingWatchers[key] then
		return pendingWatchers[key]
	end

	local connection
	connection = playerGui.ChildAdded:Connect(function(child)
		if child.Name ~= guiName or not isScreenGui(child) then
			return
		end

		pendingWatchers[key] = nil
		if connection then
			connection:Disconnect()
		end
		callback(child)
	end)

	pendingWatchers[key] = connection
	return connection
end

function WipInstanceModalBridge.BindNamiSellButtons(gui)
	if not isScreenGui(gui) then
		return gui
	end

	NamiSellValueUpdater.BindGui(gui)

	if boundSellGuis[gui] then
		return gui
	end

	local connections = {}
	local function requestDirectCrewSell(source, mode)
		NamiSellValueUpdater.RequestUpdate()
		ReactModalRegistry.Close("NamiShop")
		ReactModalRegistry.Open("Inventory", {
			ActiveCategory = "CrewMembers",
			ActiveView = "Inventory",
			DirectSell = true,
			NamiSellMode = mode,
			Source = source,
		})
	end

	local function bindNamedButton(buttonName, source, mode)
		local button = findDescendant(gui, buttonName, "GuiButton")
		if button then
			local connection = connectButton(button, function()
				requestDirectCrewSell(source, mode)
			end)
			if connection then
				table.insert(connections, connection)
			end
		end
	end

	bindNamedButton("SellHotbarButton", "NamiSellHotbar", "Hotbar")
	bindNamedButton("SellHandButton", "NamiSellHand", "Hand")

	boundSellGuis[gui] = connections
	gui.Destroying:Connect(function()
		for _, connection in ipairs(connections) do
			connection:Disconnect()
		end
		boundSellGuis[gui] = nil
	end)

	return gui
end

function WipInstanceModalBridge.BindSpeedUpgradeTutorialRefs(gui)
	if not isScreenGui(gui) or boundSpeedTutorialGuis[gui] then
		return gui
	end

	local SpeedUpgradeTutorialBridge = require(Modules:WaitForChild("SpeedUpgradeTutorialBridge"))
	local connections = {}
	local closeButton = findDescendant(gui, "CloseButton", "GuiButton")
	local buyButton = findDescendant(gui, "Buy", "GuiButton") or findDescendant(gui, "BuyButton", "GuiButton")

	local function publishRefs()
		closeButton = closeButton or findDescendant(gui, "CloseButton", "GuiButton")
		buyButton = buyButton or findDescendant(gui, "Buy", "GuiButton") or findDescendant(gui, "BuyButton", "GuiButton")
		if closeButton and buyButton then
			SpeedUpgradeTutorialBridge.SetRefs({
				buyButton = buyButton,
				closeButton = closeButton,
				root = gui,
			})
		end
	end

	publishRefs()
	table.insert(connections, gui.DescendantAdded:Connect(function(descendant)
		if descendant:IsA("GuiButton") and (descendant.Name == "Buy" or descendant.Name == "BuyButton" or descendant.Name == "CloseButton") then
			if descendant.Name == "CloseButton" then
				closeButton = descendant
			else
				buyButton = descendant
			end
			publishRefs()
		end
	end))

	boundSpeedTutorialGuis[gui] = connections
	gui.Destroying:Connect(function()
		for _, connection in ipairs(connections) do
			connection:Disconnect()
		end
		boundSpeedTutorialGuis[gui] = nil
		SpeedUpgradeTutorialBridge.ClearRefs()
	end)

	return gui
end

return WipInstanceModalBridge
