local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local UiModalState = require(Modules:WaitForChild("UiModalState"))

local ReactFrameModalAdapter = {}
ReactFrameModalAdapter.__index = ReactFrameModalAdapter

local FRAMES_DISPLAY_ORDER = 120

local function disconnectAll(bucket)
	for _, connection in ipairs(bucket) do
		connection:Disconnect()
	end

	table.clear(bucket)
end

local function trackConnection(signal, callback, bucket)
	local connection = signal:Connect(callback)
	table.insert(bucket, connection)
	return connection
end

local function isUsableUiController(controller)
	if not controller or not controller.Main or not controller.Main.Parent then
		return false
	end

	if typeof(controller._isActiveController) == "function" then
		local ok, isActive = pcall(controller._isActiveController, controller)
		if ok and isActive ~= true then
			return false
		end
	end

	return true
end

function ReactFrameModalAdapter.new(options)
	local self = setmetatable({}, ReactFrameModalAdapter)

	self.playerGui = assert(options.playerGui, "playerGui is required")
	self.frameName = assert(options.frameName, "frameName is required")
	self.hostName = options.hostName or ("React" .. self.frameName .. "Host")
	self.backdropName = options.backdropName
	self.modalStateKey = options.modalStateKey
	self.minSize = options.minSize
	self.maxSize = options.maxSize
	self.allowFallback = options.allowFallback == true
	self.createFrameIfMissing = options.createFrameIfMissing == true
	self.frameBackgroundTransparency = options.frameBackgroundTransparency
	self.frameZIndex = options.frameZIndex or 120
	self.hostZIndex = options.hostZIndex or 140
	self.scheduleRender = nil
	self.destroyed = false
	self.uiController = nil
	self.legacyFrame = nil
	self.backdrop = nil
	self.fallbackGui = nil
	self.legacyConnections = {}
	self.framesFolderConnections = {}

	return self
end

function ReactFrameModalAdapter:SetScheduleRender(callback)
	self.scheduleRender = callback
end

function ReactFrameModalAdapter:_tryLoadUiController()
	if isUsableUiController(self.uiController) then
		return self.uiController
	end

	self.uiController = nil

	local openUiScript = self.playerGui:FindFirstChild("OpenUI") or self.playerGui:WaitForChild("OpenUI", 1)
	if not openUiScript then
		return nil
	end

	local openUiModule = openUiScript:FindFirstChild("Open_UI")
	if not openUiModule then
		return nil
	end

	local ok, result = pcall(require, openUiModule)
	if ok and isUsableUiController(result) then
		self.uiController = result
		return result
	end

	return nil
end

function ReactFrameModalAdapter:InvalidateUiController()
	self.uiController = nil
end

function ReactFrameModalAdapter:GetUiController()
	return self:_tryLoadUiController()
end

function ReactFrameModalAdapter:_getFramesGui(waitTimeout)
	return self.playerGui:FindFirstChild("Frames") or self.playerGui:WaitForChild("Frames", waitTimeout or 2)
end

function ReactFrameModalAdapter:_ensureBackdrop()
	if not self.backdropName then
		return nil
	end

	local framesGui = self:_getFramesGui(1)
	if not framesGui then
		return nil
	end

	if self.backdrop and self.backdrop.Parent == framesGui then
		return self.backdrop
	end

	local backdrop = framesGui:FindFirstChild(self.backdropName)
	if not backdrop then
		backdrop = Instance.new("Frame")
		backdrop.Name = self.backdropName
		backdrop.BackgroundColor3 = Color3.fromRGB(3, 8, 18)
		backdrop.BackgroundTransparency = 0.42
		backdrop.BorderSizePixel = 0
		backdrop.Size = UDim2.fromScale(1, 1)
		backdrop.Visible = false
		backdrop.ZIndex = 80
		backdrop.Active = true
		backdrop.Parent = framesGui
	end

	self.backdrop = backdrop
	return backdrop
end

function ReactFrameModalAdapter:SyncOverlayState()
	local isVisible = self.legacyFrame ~= nil and self.legacyFrame.Parent ~= nil and self.legacyFrame.Visible == true
	local backdrop = self:_ensureBackdrop()
	if backdrop then
		backdrop.Visible = isVisible
	end

	if self.modalStateKey then
		UiModalState.SetOpen(self.modalStateKey, isVisible)
	end
end

function ReactFrameModalAdapter:_applyFrameStyling(frame)
	local framesGui = frame.Parent
	if framesGui and framesGui:IsA("ScreenGui") then
		framesGui.DisplayOrder = math.max(framesGui.DisplayOrder, FRAMES_DISPLAY_ORDER)
		framesGui.IgnoreGuiInset = true
		framesGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	end

	frame.Active = true
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.BackgroundTransparency = self.frameBackgroundTransparency ~= nil and self.frameBackgroundTransparency or 1
	frame.BorderSizePixel = 0
	frame.ClipsDescendants = true
	frame.Position = UDim2.fromScale(0.5, 0.5)
	frame.Size = UDim2.new(0.9, 0, 0.84, 0)
	frame.ZIndex = self.frameZIndex

	if self.minSize or self.maxSize then
		local sizeConstraint = frame:FindFirstChild(self.hostName .. "SizeConstraint")
		if not sizeConstraint then
			sizeConstraint = Instance.new("UISizeConstraint")
			sizeConstraint.Name = self.hostName .. "SizeConstraint"
			sizeConstraint.Parent = frame
		end

		if self.minSize then
			sizeConstraint.MinSize = self.minSize
		end
		if self.maxSize then
			sizeConstraint.MaxSize = self.maxSize
		end
	end
end

function ReactFrameModalAdapter:_suppressLegacyChild(child, host)
	if child == nil or child == host or (host and child:IsDescendantOf(host)) then
		return
	end

	if child:IsA("GuiObject") then
		child.Visible = false
	elseif child:IsA("UIStroke") or child:IsA("UIGradient") then
		child.Enabled = false
	end

	for _, descendant in ipairs(child:GetDescendants()) do
		if descendant ~= host and not (host and descendant:IsDescendantOf(host)) then
			if descendant:IsA("GuiObject") then
				descendant.Visible = false
			elseif descendant:IsA("UIStroke") or descendant:IsA("UIGradient") then
				descendant.Enabled = false
			end
		end
	end
end

function ReactFrameModalAdapter:_guardSuppressedInstance(instance, frame, host)
	if instance == nil or instance == host or (host and instance:IsDescendantOf(host)) then
		return
	end

	if instance:IsA("GuiObject") then
		trackConnection(instance:GetPropertyChangedSignal("Visible"), function()
			if instance.Parent and instance:IsDescendantOf(frame) and (not host or not instance:IsDescendantOf(host)) and instance.Visible then
				instance.Visible = false
			end
		end, self.legacyConnections)
	elseif instance:IsA("UIStroke") or instance:IsA("UIGradient") then
		trackConnection(instance:GetPropertyChangedSignal("Enabled"), function()
			if instance.Parent and instance:IsDescendantOf(frame) and (not host or not instance:IsDescendantOf(host)) and instance.Enabled then
				instance.Enabled = false
			end
		end, self.legacyConnections)
	end
end

function ReactFrameModalAdapter:_bindLegacySuppression(frame, host)
	disconnectAll(self.legacyConnections)

	if not frame then
		return
	end

	self:_applyFrameStyling(frame)

	for _, child in ipairs(frame:GetChildren()) do
		self:_suppressLegacyChild(child, host)
		self:_guardSuppressedInstance(child, frame, host)

		for _, descendant in ipairs(child:GetDescendants()) do
			self:_guardSuppressedInstance(descendant, frame, host)
		end
	end

	trackConnection(frame.ChildAdded, function(child)
		task.defer(function()
			if self.destroyed then
				return
			end

			self:_suppressLegacyChild(child, host)
			self:_bindLegacySuppression(frame, host)
		end)
	end, self.legacyConnections)

	trackConnection(frame.DescendantAdded, function(descendant)
		task.defer(function()
			if self.destroyed or descendant == host or (host and descendant:IsDescendantOf(host)) then
				return
			end

			self:_suppressLegacyChild(descendant, host)
			self:_guardSuppressedInstance(descendant, frame, host)
		end)
	end, self.legacyConnections)

	trackConnection(frame.ChildRemoved, function(child)
		if child == host and self.scheduleRender then
			task.defer(self.scheduleRender)
		end
	end, self.legacyConnections)

	trackConnection(frame:GetPropertyChangedSignal("Visible"), function()
		task.defer(function()
			if self.destroyed then
				return
			end

			self:_applyFrameStyling(frame)
			self:SyncOverlayState()
			if self.scheduleRender then
				self.scheduleRender()
			end
		end)
	end, self.legacyConnections)
end

function ReactFrameModalAdapter:_findOrCreateFrame()
	if self.legacyFrame and self.legacyFrame.Parent ~= nil then
		return self.legacyFrame
	end

	self.legacyFrame = nil

	local framesGui = self:_getFramesGui(2)
	if not framesGui then
		return nil
	end

	local frame = framesGui:FindFirstChild(self.frameName) or framesGui:WaitForChild(self.frameName, 1)
	if frame and frame:IsA("Frame") then
		self.legacyFrame = frame
		return frame
	end

	if not self.createFrameIfMissing then
		return nil
	end

	frame = Instance.new("Frame")
	frame.Name = self.frameName
	frame.Visible = false
	frame.Parent = framesGui
	self.legacyFrame = frame

	return frame
end

function ReactFrameModalAdapter:EnsureHost()
	local frame = self:_findOrCreateFrame()
	if not frame then
		disconnectAll(self.legacyConnections)
		return nil
	end

	self:_applyFrameStyling(frame)

	local host = frame:FindFirstChild(self.hostName)
	if not host then
		host = Instance.new("Frame")
		host.Name = self.hostName
		host.Active = true
		host.BackgroundTransparency = 1
		host.BorderSizePixel = 0
		host.Size = UDim2.fromScale(1, 1)
		host.ZIndex = self.hostZIndex
		host.Parent = frame
	end

	host.Visible = true
	host.ClipsDescendants = true
	self:_bindLegacySuppression(frame, host)
	self:SyncOverlayState()

	self.legacyFrame = frame
	return host
end

function ReactFrameModalAdapter:EnsureFallbackHost()
	if not self.allowFallback then
		return nil
	end

	if self.fallbackGui then
		return self.fallbackGui:WaitForChild(self.hostName)
	end

	local fallbackGui = Instance.new("ScreenGui")
	fallbackGui.Name = self.frameName .. "FallbackGui"
	fallbackGui.DisplayOrder = 160
	fallbackGui.IgnoreGuiInset = true
	fallbackGui.ResetOnSpawn = false
	fallbackGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	fallbackGui.Parent = self.playerGui

	local host = Instance.new("Frame")
	host.Name = self.hostName
	host.Active = true
	host.BackgroundTransparency = 1
	host.BorderSizePixel = 0
	host.Size = UDim2.fromScale(1, 1)
	host.Parent = fallbackGui

	self.fallbackGui = fallbackGui
	return host
end

function ReactFrameModalAdapter:SetFallbackEnabled(enabled)
	if self.fallbackGui then
		self.fallbackGui.Enabled = enabled == true
	end
end

function ReactFrameModalAdapter:HideBackdrop()
	if self.backdrop then
		self.backdrop.Visible = false
	end
end

function ReactFrameModalAdapter:BindFramesFolderTracking()
	disconnectAll(self.framesFolderConnections)

	local framesGui = self.playerGui:FindFirstChild("Frames")
	if not framesGui then
		return
	end

	trackConnection(framesGui.ChildAdded, function(child)
		if child.Name == self.frameName then
			self.legacyFrame = nil
			if self.scheduleRender then
				task.defer(self.scheduleRender)
			end
		end
	end, self.framesFolderConnections)

	trackConnection(framesGui.ChildRemoved, function(child)
		if child.Name == self.frameName then
			self.legacyFrame = nil
			if self.scheduleRender then
				task.defer(self.scheduleRender)
			end
		end
	end, self.framesFolderConnections)
end

function ReactFrameModalAdapter:HandlePlayerGuiChildAdded(child)
	if child.Name == "Frames" then
		self.legacyFrame = nil
		self.backdrop = nil
		self:BindFramesFolderTracking()
		if self.scheduleRender then
			task.defer(self.scheduleRender)
		end
	elseif child.Name == "OpenUI" then
		self:InvalidateUiController()
		if self.scheduleRender then
			task.defer(self.scheduleRender)
		end
	end
end

function ReactFrameModalAdapter:HandlePlayerGuiChildRemoved(child)
	if child.Name == "Frames" then
		self.legacyFrame = nil
		self.backdrop = nil
		disconnectAll(self.framesFolderConnections)
		if self.scheduleRender then
			task.defer(self.scheduleRender)
		end
	elseif child.Name == "OpenUI" then
		self:InvalidateUiController()
		if self.scheduleRender then
			task.defer(self.scheduleRender)
		end
	end
end

function ReactFrameModalAdapter:GetFrame()
	return self.legacyFrame or self:_findOrCreateFrame()
end

function ReactFrameModalAdapter:IsVisible()
	local frame = self:GetFrame()
	return frame ~= nil and frame.Parent ~= nil and frame.Visible == true
end

function ReactFrameModalAdapter:Toggle()
	local frame = self:GetFrame()
	if not frame then
		return false
	end

	local controller = self:_tryLoadUiController()
	if controller and controller.ToggleFrame then
		controller:ToggleFrame(frame)
	else
		frame.Visible = not frame.Visible
		self:SyncOverlayState()
	end

	return true
end

function ReactFrameModalAdapter:Close()
	local frame = self:GetFrame()
	if not frame or not frame.Visible then
		return
	end

	local controller = self:_tryLoadUiController()
	if controller and controller.ToggleFrame then
		controller:ToggleFrame(frame)
	else
		frame.Visible = false
		self:SyncOverlayState()
	end
end

function ReactFrameModalAdapter:Destroy()
	self.destroyed = true
	disconnectAll(self.legacyConnections)
	disconnectAll(self.framesFolderConnections)
	if self.modalStateKey then
		UiModalState.SetOpen(self.modalStateKey, false)
	end
	if self.backdrop then
		self.backdrop.Visible = false
	end
	if self.fallbackGui then
		self.fallbackGui:Destroy()
		self.fallbackGui = nil
	end
end

return ReactFrameModalAdapter
