local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local Modules = ReplicatedStorage:WaitForChild("Modules")
local UiFolder = ReplicatedStorage:WaitForChild("UI")

local React = require(Packages:WaitForChild("React"))
local ReactRoblox = require(Packages:WaitForChild("ReactRoblox"))
local ShipSlotLevelPanelState = require(Modules:WaitForChild("Crew"):WaitForChild("ShipSlotLevelPanelState"))
local ShipSlotLevelPanel = require(UiFolder:WaitForChild("Crew"):WaitForChild("ShipSlotLevelPanel"))

local Binder = {}

local ROOT_FRAME_NAME = "ReactRootFrame"
local LEGACY_ROOT_NAME = "LevelUp"

local mountedBySurface = setmetatable({}, { __mode = "k" })

local function disconnectAll(connections)
	for _, connection in ipairs(connections) do
		connection:Disconnect()
	end
	table.clear(connections)
end

local function getLegacyRoot(surfaceGui)
	local legacyRoot = surfaceGui:FindFirstChild(LEGACY_ROOT_NAME)
	if legacyRoot and legacyRoot:IsA("GuiObject") then
		return legacyRoot
	end

	return nil
end

local function applyLegacyLayout(rootFrame, legacyRoot)
	local legacyZIndex = legacyRoot and legacyRoot.ZIndex or 1

	rootFrame.AnchorPoint = Vector2.new(0, 0)
	rootFrame.BackgroundTransparency = 1
	rootFrame.BorderSizePixel = 0
	rootFrame.ClipsDescendants = false
	rootFrame.Position = UDim2.fromScale(0, 0)
	rootFrame.Rotation = 0
	rootFrame.Size = UDim2.fromScale(1, 1)
	rootFrame.Visible = true
	rootFrame.ZIndex = legacyZIndex
end

local function getOrCreateRootFrame(surfaceGui, legacyRoot)
	local rootFrame = surfaceGui:FindFirstChild(ROOT_FRAME_NAME)
	if rootFrame and not rootFrame:IsA("Frame") then
		rootFrame:Destroy()
		rootFrame = nil
	end

	if not rootFrame then
		rootFrame = Instance.new("Frame")
		rootFrame.Name = ROOT_FRAME_NAME
		rootFrame.Parent = surfaceGui
	end

	applyLegacyLayout(rootFrame, legacyRoot)
	return rootFrame
end

function Binder.Mount(surfaceGui, onActivated)
	if typeof(surfaceGui) ~= "Instance" or not surfaceGui:IsA("SurfaceGui") then
		return nil
	end

	local existing = mountedBySurface[surfaceGui]
	if existing then
		existing:SetActivatedCallback(onActivated)
		return existing
	end

	local legacyRoot = getLegacyRoot(surfaceGui)
	local rootFrame = getOrCreateRootFrame(surfaceGui, legacyRoot)

	local createOk, rootOrError = pcall(function()
		return ReactRoblox.createRoot(rootFrame)
	end)
	if not createOk then
		warn(("[ShipSlotLevelPanelBinder] Failed to create React root for %s: %s"):format(
			surfaceGui:GetFullName(),
			tostring(rootOrError)
		))
		return nil
	end

	local handle = {
		activatedCallback = onActivated,
		connections = {},
		destroyed = false,
		legacyRoot = legacyRoot,
		renderQueued = false,
		renderWarned = false,
		root = rootOrError,
		rootFrame = rootFrame,
		surfaceGui = surfaceGui,
	}

	function handle:SetActivatedCallback(callback)
		self.activatedCallback = callback
	end

	function handle:Render()
		if self.destroyed or not self.surfaceGui.Parent then
			return
		end

		local state = ShipSlotLevelPanelState.Read(self.surfaceGui)
		self.rootFrame.Visible = true

		self.root:render(React.createElement(ShipSlotLevelPanel, {
			currentXP = state and state.CurrentXP or 0,
			foodText = ShipSlotLevelPanelState.FormatFoodText(state),
			hasFood = state and state.HasFood == true,
			isLoading = state == nil,
			isMaxLevel = state and state.IsMaxLevel == true,
			levelText = ShipSlotLevelPanelState.FormatLevelText(state),
			nextLevelText = ShipSlotLevelPanelState.FormatNextLevelText(state),
			nextLevelXP = state and state.NextLevelXP or 0,
			onActivated = function()
				if typeof(self.activatedCallback) == "function" then
					self.activatedCallback()
				end
			end,
			progressRatio = ShipSlotLevelPanelState.GetProgressRatio(state),
			progressText = ShipSlotLevelPanelState.FormatProgressText(state),
			upgradeCostText = ShipSlotLevelPanelState.FormatUpgradeCostText(state),
			xpText = ShipSlotLevelPanelState.FormatXPText(state),
		}))

		if self.legacyRoot and self.legacyRoot.Parent then
			self.legacyRoot.Visible = false
		end
	end

	function handle:ScheduleRender()
		if self.destroyed or self.renderQueued then
			return
		end

		self.renderQueued = true
		task.defer(function()
			if self.destroyed then
				return
			end

			self.renderQueued = false
			local ok, err = pcall(function()
				self:Render()
			end)
			if not ok and not self.renderWarned then
				self.renderWarned = true
				warn(("[ShipSlotLevelPanelBinder] Failed to update React panel for %s: %s"):format(
					self.surfaceGui:GetFullName(),
					tostring(err)
				))
			end
		end)
	end

	function handle:Destroy()
		if self.destroyed then
			return
		end

		self.destroyed = true
		mountedBySurface[self.surfaceGui] = nil
		disconnectAll(self.connections)

		if self.root then
			self.root:unmount()
		end
		if self.rootFrame and self.rootFrame.Parent then
			self.rootFrame:Destroy()
		end
		if self.legacyRoot and self.legacyRoot.Parent then
			self.legacyRoot.Visible = true
		end
	end

	mountedBySurface[surfaceGui] = handle

	for _, attributeName in ipairs(ShipSlotLevelPanelState.AttributeList) do
		table.insert(handle.connections, surfaceGui:GetAttributeChangedSignal(attributeName):Connect(function()
			handle:ScheduleRender()
		end))
	end

	if legacyRoot then
		table.insert(handle.connections, legacyRoot:GetPropertyChangedSignal("Visible"):Connect(function()
			if not handle.destroyed and legacyRoot.Visible then
				legacyRoot.Visible = false
			end
		end))
	end

	local renderOk, renderError = pcall(function()
		handle:Render()
	end)
	if not renderOk then
		warn(("[ShipSlotLevelPanelBinder] Failed to render React panel for %s: %s"):format(
			surfaceGui:GetFullName(),
			tostring(renderError)
		))
		handle:Destroy()
		return nil
	end

	return handle
end

return Binder
