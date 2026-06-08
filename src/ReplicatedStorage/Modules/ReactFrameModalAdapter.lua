local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local Responsive = require(ReplicatedStorage:WaitForChild("UI"):WaitForChild("Responsive"))
local UiModalState = require(Modules:WaitForChild("UiModalState"))

local ReactFrameModalAdapter = {}
ReactFrameModalAdapter.__index = ReactFrameModalAdapter

local FRAMES_DISPLAY_ORDER = 120
local STANDALONE_LAYER_NAME = "ReactModalLayer"
local BYPASS_OPEN_UI_SCALE_ANIMATION_ATTRIBUTE = "OpenUIBypassScaleAnimation"
local ADAPTER_FRAME_ATTRIBUTE = "ReactFrameModalAdapterFrame"
local ADAPTER_HOST_ATTRIBUTE = "ReactFrameModalAdapterHost"
local ADAPTER_BACKDROP_ATTRIBUTE = "ReactFrameModalAdapterBackdrop"
local ADAPTER_MODAL_NAME_ATTRIBUTE = "ReactFrameModalAdapterModalName"
local VIEWPORT_MARGIN = Vector2.new(24, 24)
local MOBILE_FRAME_SCALE = Vector2.new(0.74, 0.8)
local MOBILE_CONTENT_SCALE = 0.62

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

local function isManagedForModal(child, managedAttribute, modalName)
	if child:GetAttribute(managedAttribute) ~= true then
		return false
	end

	local childModalName = child:GetAttribute(ADAPTER_MODAL_NAME_ATTRIBUTE)
	return modalName == nil or childModalName == nil or childModalName == modalName
end

local function scoreManagedChild(child, options)
	local score = 0
	local descendantCount = #child:GetDescendants()

	if child:IsA("GuiObject") and child.Visible then
		score += 10000
	end

	score += descendantCount

	if options and options.hostName then
		local host = child:FindFirstChild(options.hostName)
		if host and host:IsA("Frame") then
			score += 1000
			if isManagedForModal(host, options.hostAttribute, options.modalName) then
				score += 1000
			end

			local hostDescendantCount = #host:GetDescendants()
			if hostDescendantCount > 1 then
				score += 5000 + hostDescendantCount
			end

			if host:IsA("GuiObject") and host.Visible then
				score += 100
			end
		end
	end

	if options and options.modalName and child:GetAttribute(ADAPTER_MODAL_NAME_ATTRIBUTE) == options.modalName then
		score += 100
	end

	return score
end

local function findManagedNamedChild(parent, childName, className, managedAttribute, options)
	local selected = nil
	local selectedScore = -math.huge
	local modalName = options and options.modalName or nil

	for _, child in ipairs(parent:GetChildren()) do
		if
			child.Name == childName
			and child:IsA(className)
			and isManagedForModal(child, managedAttribute, modalName)
		then
			local score = scoreManagedChild(child, options)
			if selected == nil or score > selectedScore then
				selected = child
				selectedScore = score
			end
		end
	end

	if selected then
		for _, child in ipairs(parent:GetChildren()) do
			if
				child ~= selected
				and child.Name == childName
				and child:IsA(className)
				and isManagedForModal(child, managedAttribute, modalName)
			then
				child:Destroy()
			end
		end
	end

	return selected
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
	self.backdropActive = options.backdropActive ~= false
	self.minSize = options.minSize
	self.maxSize = options.maxSize
	self.frameSize = options.frameSize
	self.useResponsiveUiScale = options.useResponsiveUiScale ~= false
	self.allowFallback = options.allowFallback == true
	self.createFrameIfMissing = options.createFrameIfMissing == true
	self.standalone = options.standalone == true
	self.frameBackgroundTransparency = options.frameBackgroundTransparency
	self.frameZIndex = options.frameZIndex or 120
	self.hostZIndex = options.hostZIndex or 140
	self.bypassLegacyScaleAnimation = options.bypassLegacyScaleAnimation == true
	self.scheduleRender = nil
	self.destroyed = false
	self.uiController = nil
	self.legacyFrame = nil
	self.backdrop = nil
	self.fallbackGui = nil
	self.legacyConnections = {}
	self.framesFolderConnections = {}
	self.viewportConnections = {}
	self.boundLegacySuppressionFrame = nil
	self.boundLegacySuppressionHost = nil
	self:_bindViewportTracking()

	return self
end

function ReactFrameModalAdapter:_getAvailableViewportSize()
	local viewport = Responsive.getViewport()
	return Vector2.new(
		math.max(1, viewport.X - VIEWPORT_MARGIN.X),
		math.max(1, viewport.Y - VIEWPORT_MARGIN.Y)
	)
end

function ReactFrameModalAdapter:_usesPhoneModalLayout()
	return Responsive.isPhoneViewport()
end

function ReactFrameModalAdapter:_getFrameConstraintScale()
	if self:_usesPhoneModalLayout() then
		return 1
	end

	if not self.useResponsiveUiScale then
		return 1
	end

	return Responsive.getUiScale()
end

function ReactFrameModalAdapter:_getContentScale()
	if self:_usesPhoneModalLayout() then
		return MOBILE_CONTENT_SCALE
	end

	if not self.useResponsiveUiScale then
		return 1
	end

	return self:_getFrameConstraintScale()
end

function ReactFrameModalAdapter:_bindViewportTracking()
	disconnectAll(self.viewportConnections)

	local camera = Workspace.CurrentCamera
	if camera then
		trackConnection(camera:GetPropertyChangedSignal("ViewportSize"), function()
			if self.legacyFrame and self.legacyFrame.Parent then
				self:_applyFrameStyling(self.legacyFrame)
			end
			if self.scheduleRender then
				task.defer(self.scheduleRender)
			end
		end, self.viewportConnections)
	end

	trackConnection(Workspace:GetPropertyChangedSignal("CurrentCamera"), function()
		self:_bindViewportTracking()
		if self.legacyFrame and self.legacyFrame.Parent then
			self:_applyFrameStyling(self.legacyFrame)
		end
	end, self.viewportConnections)
end

function ReactFrameModalAdapter:SetScheduleRender(callback)
	self.scheduleRender = callback
end

function ReactFrameModalAdapter:_tryLoadUiController()
	if self.standalone then
		return nil
	end

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
	if self.standalone then
		local existing = self.playerGui:FindFirstChild(STANDALONE_LAYER_NAME)
		if existing and existing:IsA("ScreenGui") then
			return existing
		end

		if existing then
			existing:Destroy()
		end

		local layer = Instance.new("ScreenGui")
		layer.Name = STANDALONE_LAYER_NAME
		layer.DisplayOrder = FRAMES_DISPLAY_ORDER
		layer.IgnoreGuiInset = true
		layer.ResetOnSpawn = false
		layer.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
		layer.Parent = self.playerGui
		return layer
	end

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

	local backdrop = findManagedNamedChild(framesGui, self.backdropName, "Frame", ADAPTER_BACKDROP_ATTRIBUTE, {
		modalName = self.frameName,
	})
	local existingBackdrop = framesGui:FindFirstChild(self.backdropName)
	if not backdrop and existingBackdrop and existingBackdrop:IsA("Frame") then
		backdrop = existingBackdrop
	end
	if not backdrop then
		backdrop = Instance.new("Frame")
		backdrop.Name = self.backdropName
		backdrop.BackgroundColor3 = Color3.fromRGB(3, 8, 18)
		backdrop.BackgroundTransparency = 0.42
		backdrop.BorderSizePixel = 0
		backdrop.Size = UDim2.fromScale(1, 1)
		backdrop.Visible = false
		backdrop.ZIndex = 80
		backdrop.Active = self.backdropActive
		backdrop.Parent = framesGui
	end

	backdrop:SetAttribute(ADAPTER_BACKDROP_ATTRIBUTE, true)
	backdrop:SetAttribute(ADAPTER_MODAL_NAME_ATTRIBUTE, self.frameName)
	backdrop.Active = self.backdropActive
	self.backdrop = backdrop
	return backdrop
end

function ReactFrameModalAdapter:SyncOverlayState()
	local frame = self:_findOrCreateFrame()
	local isVisible = frame ~= nil and frame.Parent ~= nil and frame.Visible == true
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

	frame:SetAttribute(ADAPTER_FRAME_ATTRIBUTE, true)
	frame:SetAttribute(ADAPTER_MODAL_NAME_ATTRIBUTE, self.frameName)
	frame.Active = true
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.BackgroundTransparency = self.frameBackgroundTransparency ~= nil and self.frameBackgroundTransparency or 1
	frame.BorderSizePixel = 0
	frame.ClipsDescendants = true
	if self.bypassLegacyScaleAnimation then
		frame:SetAttribute(BYPASS_OPEN_UI_SCALE_ANIMATION_ATTRIBUTE, true)
		local scale = frame:FindFirstChildOfClass("UIScale")
		if scale then
			scale.Scale = 1
		end
	end
	if self.standalone or frame.Visible ~= true then
		frame.Position = UDim2.fromScale(0.5, 0.5)
	end
	local phoneLayout = self:_usesPhoneModalLayout()
	local desiredSize = if phoneLayout
		then UDim2.fromScale(MOBILE_FRAME_SCALE.X, MOBILE_FRAME_SCALE.Y)
		else (self.frameSize or UDim2.fromScale(0.9, 0.84))
	if self.standalone or frame.Visible ~= true then
		frame.Size = desiredSize
	end
	frame.ZIndex = self.frameZIndex

	if self.minSize or self.maxSize then
		local sizeConstraint = frame:FindFirstChild(self.hostName .. "SizeConstraint")
		if not sizeConstraint then
			sizeConstraint = Instance.new("UISizeConstraint")
			sizeConstraint.Name = self.hostName .. "SizeConstraint"
			sizeConstraint.Parent = frame
		end

		local availableSize = self:_getAvailableViewportSize()
		local constraintScale = self:_getFrameConstraintScale()
		local scaledMaxSize = self.maxSize and Vector2.new(
			self.maxSize.X * constraintScale,
			self.maxSize.Y * constraintScale
		) or nil
		local scaledMinSize = self.minSize and Vector2.new(
			self.minSize.X * constraintScale,
			self.minSize.Y * constraintScale
		) or nil
		local configuredMaxSize = scaledMaxSize and Vector2.new(
			math.min(scaledMaxSize.X, availableSize.X),
			math.min(scaledMaxSize.Y, availableSize.Y)
		) or availableSize
		local maxSize = if phoneLayout
			then Vector2.new(availableSize.X * MOBILE_FRAME_SCALE.X, availableSize.Y * MOBILE_FRAME_SCALE.Y)
			else configuredMaxSize
		local minSize = if phoneLayout
			then Vector2.new(1, 1)
			else scaledMinSize and Vector2.new(
				math.min(scaledMinSize.X, maxSize.X),
				math.min(scaledMinSize.Y, maxSize.Y)
			) or Vector2.zero

		sizeConstraint.MinSize = minSize
		sizeConstraint.MaxSize = maxSize
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
			if
				instance.Parent
				and instance:IsDescendantOf(frame)
				and (not host or not instance:IsDescendantOf(host))
				and instance.Visible
			then
				instance.Visible = false
			end
		end, self.legacyConnections)
	elseif instance:IsA("UIStroke") or instance:IsA("UIGradient") then
		trackConnection(instance:GetPropertyChangedSignal("Enabled"), function()
			if
				instance.Parent
				and instance:IsDescendantOf(frame)
				and (not host or not instance:IsDescendantOf(host))
				and instance.Enabled
			then
				instance.Enabled = false
			end
		end, self.legacyConnections)
	end
end

function ReactFrameModalAdapter:_disconnectLegacySuppression()
	disconnectAll(self.legacyConnections)
	self.boundLegacySuppressionFrame = nil
	self.boundLegacySuppressionHost = nil
end

function ReactFrameModalAdapter:_setLegacyFrame(frame)
	if self.legacyFrame == frame then
		return
	end

	self:_disconnectLegacySuppression()
	self.legacyFrame = frame
end

function ReactFrameModalAdapter:_bindLegacyChildSuppression(frame, host, child)
	if child == nil or child == host or (host and child:IsDescendantOf(host)) then
		return
	end

	self:_suppressLegacyChild(child, host)
	self:_guardSuppressedInstance(child, frame, host)

	for _, descendant in ipairs(child:GetDescendants()) do
		self:_guardSuppressedInstance(descendant, frame, host)
	end

	trackConnection(child.DescendantAdded, function(descendant)
		task.defer(function()
			if self.destroyed then
				return
			end

			self:_suppressLegacyChild(descendant, host)
			self:_guardSuppressedInstance(descendant, frame, host)
		end)
	end, self.legacyConnections)
end

function ReactFrameModalAdapter:_bindLegacySuppression(frame, host)
	if not frame then
		self:_disconnectLegacySuppression()
		return
	end

	if self.boundLegacySuppressionFrame == frame and self.boundLegacySuppressionHost == host then
		return
	end

	self:_disconnectLegacySuppression()
	self.boundLegacySuppressionFrame = frame
	self.boundLegacySuppressionHost = host

	self:_applyFrameStyling(frame)

	for _, child in ipairs(frame:GetChildren()) do
		self:_bindLegacyChildSuppression(frame, host, child)
	end

	trackConnection(frame.ChildAdded, function(child)
		task.defer(function()
			if self.destroyed then
				return
			end

			self:_bindLegacyChildSuppression(frame, host, child)
		end)
	end, self.legacyConnections)

	trackConnection(frame.ChildRemoved, function(child)
		if child == host and self.scheduleRender then
			self.boundLegacySuppressionHost = nil
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
	local framesGui = self:_getFramesGui(2)
	if not framesGui then
		self:_setLegacyFrame(nil)
		return nil
	end

	local frame = findManagedNamedChild(framesGui, self.frameName, "Frame", ADAPTER_FRAME_ATTRIBUTE, {
		modalName = self.frameName,
		hostName = self.hostName,
		hostAttribute = ADAPTER_HOST_ATTRIBUTE,
	})

	if not frame and self.legacyFrame and self.legacyFrame.Parent == framesGui and self.legacyFrame.Name == self.frameName then
		frame = self.legacyFrame
	end

	frame = frame or framesGui:FindFirstChild(self.frameName) or framesGui:WaitForChild(self.frameName, 1)
	if frame and frame:IsA("Frame") then
		self:_setLegacyFrame(frame)
		return frame
	end

	if not self.createFrameIfMissing then
		return nil
	end

	frame = Instance.new("Frame")
	frame.Name = self.frameName
	frame.Visible = false
	frame.Parent = framesGui
	self:_setLegacyFrame(frame)

	return frame
end

function ReactFrameModalAdapter:EnsureHost()
	local frame = self:_findOrCreateFrame()
	if not frame then
		self:_disconnectLegacySuppression()
		return nil
	end

	self:_applyFrameStyling(frame)

	local host = findManagedNamedChild(frame, self.hostName, "Frame", ADAPTER_HOST_ATTRIBUTE, {
		modalName = self.frameName,
	})
	local existingHost = frame:FindFirstChild(self.hostName)
	if not host and existingHost and existingHost:IsA("Frame") then
		host = existingHost
	end
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

	host:SetAttribute(ADAPTER_HOST_ATTRIBUTE, true)
	host:SetAttribute(ADAPTER_MODAL_NAME_ATTRIBUTE, self.frameName)
	local contentScale = self:_getContentScale()
	local scale = host:FindFirstChild(self.hostName .. "ContentScale")
	if not scale then
		scale = Instance.new("UIScale")
		scale.Name = self.hostName .. "ContentScale"
		scale.Parent = host
	end
	scale.Scale = contentScale
	host.AnchorPoint = Vector2.new(0.5, 0.5)
	host.Position = UDim2.fromScale(0.5, 0.5)
	host.Size = UDim2.fromScale(1 / contentScale, 1 / contentScale)
	host.Visible = true
	host.ClipsDescendants = true
	self:_bindLegacySuppression(frame, host)
	self:SyncOverlayState()

	self:_setLegacyFrame(frame)
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

	if self.standalone then
		return
	end

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
			self:_disconnectLegacySuppression()
			if self.scheduleRender then
				task.defer(self.scheduleRender)
			end
		end
	end, self.framesFolderConnections)
end

function ReactFrameModalAdapter:HandlePlayerGuiChildAdded(child)
	if self.standalone then
		return
	end

	if child.Name == "Frames" then
		self.legacyFrame = nil
		self.backdrop = nil
		self:_disconnectLegacySuppression()
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
	if self.standalone then
		return
	end

	if child.Name == "Frames" then
		self.legacyFrame = nil
		self.backdrop = nil
		self:_disconnectLegacySuppression()
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
	return self:_findOrCreateFrame()
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
	self:_disconnectLegacySuppression()
	disconnectAll(self.framesFolderConnections)
	disconnectAll(self.viewportConnections)
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
