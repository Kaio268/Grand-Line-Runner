local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local Modules = ReplicatedStorage:WaitForChild("Modules")
local ReactModalRegistry = require(Modules:WaitForChild("ReactModalRegistry"))

local WipInstanceModalBridge = {}

local boundModalGuis = setmetatable({}, { __mode = "k" })
local boundSellGuis = setmetatable({}, { __mode = "k" })
local boundSpeedTutorialGuis = setmetatable({}, { __mode = "k" })
local pendingOwnedGuiBinds = {}
local pendingWatchers = {}
local RECENT_TOGGLE_WINDOW_SECONDS = 0.12

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

	local unregister = ReactModalRegistry.Register(modalName, handlers)
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
	if not isScreenGui(gui) or boundSellGuis[gui] then
		return gui
	end

	local connections = {}
	local function requestDirectCrewSell(source, mode)
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
