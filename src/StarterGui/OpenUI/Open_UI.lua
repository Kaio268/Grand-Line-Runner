local UIController = {}
UIController.__index = UIController

local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")

local CONFIG = {
	OPEN_TIME = 0.16,
	CLOSE_TIME = 0.16,
	POPUP_TIME = 0.16,
	DEFAULT_FOV = 70,
	OPEN_FOV = 90,
	BLUR_OPEN = 15,
	BLUR_CLOSED = 0,
	EASING_STYLE = Enum.EasingStyle.Quad,
	EASING_DIR_IN = Enum.EasingDirection.In,
	EASING_DIR_OUT = Enum.EasingDirection.Out,
}

local FRAMES_DISPLAY_ORDER = 120
local CONTROLLER_GENERATION_ATTRIBUTE = "OpenUIControllerGeneration"
local OPENED_FRAME_ATTRIBUTE = "OpenUIOpened"
local GIFT_OPENUI_DEBUG = true
local GIFT_OPENUI_DEBUG_VERSION = "gifts-openui-x-debug-2026-05-01"
local CLOSE_BUTTON_DEBUG = true
local CLOSE_BUTTON_DEBUG_VERSION = "close-buttons-live-debug-2026-05-01"
local REACT_MODAL_FRAME_NAMES = {
	Index = true,
	Quest = true,
	Store = true,
}
local CLOSE_DIAGNOSTIC_FRAME_NAMES = {
	Gifts = true,
	Rebirth = true,
}

local function safeName(inst)
	if not inst then
		return "nil"
	end
	local ok, full = pcall(function()
		return inst:GetFullName()
	end)
	return ok and full or tostring(inst)
end

local function giftOpenUiLog(...)
	if GIFT_OPENUI_DEBUG then
		print("[GIFT][OPENUI]", ...)
	end
end

local function closeButtonLog(frameName: string, ...)
	if CLOSE_BUTTON_DEBUG and CLOSE_DIAGNOSTIC_FRAME_NAMES[frameName] then
		print("[UI][CLOSE]", ...)
	end
end

local function closeButtonWarn(frameName: string, ...)
	if CLOSE_DIAGNOSTIC_FRAME_NAMES[frameName] then
		warn("[UI][CLOSE][WARN]", ...)
	end
end

local function countFrameChildrenByName(framesFolder: Instance?, frameName: string): number
	if not framesFolder then
		return 0
	end

	local count = 0
	for _, child in ipairs(framesFolder:GetChildren()) do
		if child.Name == frameName and child:IsA("Frame") then
			count += 1
		end
	end
	return count
end

local function nextControllerGeneration(playerGui: PlayerGui): number
	local nextGeneration = (tonumber(playerGui:GetAttribute(CONTROLLER_GENERATION_ATTRIBUTE)) or 0) + 1
	playerGui:SetAttribute(CONTROLLER_GENERATION_ATTRIBUTE, nextGeneration)
	return nextGeneration
end

local function isReactModalChrome(frame: Instance): boolean
	return frame.Name:match("^React") ~= nil and frame.Name:match("Backdrop$") ~= nil
end

local function isManagedFrame(frame: Instance): boolean
	return frame:IsA("Frame") and not isReactModalChrome(frame)
end

local function shouldPreserveVisibleFrame(frame: Frame): boolean
	return frame:GetAttribute(OPENED_FRAME_ATTRIBUTE) == true or REACT_MODAL_FRAME_NAMES[frame.Name] == true
end

local function tween(obj: Instance, props: {[string]: any}, time: number, style, dir)
	return TweenService:Create(obj, TweenInfo.new(time, style, dir), props)
end

function UIController:_isActiveController(): boolean
	return self.Destroyed ~= true
		and self.PlayerGui ~= nil
		and self.PlayerGui.Parent ~= nil
		and self.PlayerGui:GetAttribute(CONTROLLER_GENERATION_ATTRIBUTE) == self.ControllerGeneration
end

function UIController:_ensureBlurEffect()
	local blur = Lighting:FindFirstChild("BlurUI") :: BlurEffect?
	if not blur then
		blur = Instance.new("BlurEffect")
		blur.Name = "BlurUI"
		blur.Size = CONFIG.BLUR_CLOSED
		blur.Parent = Lighting
	end
	self.BlurEffect = blur
end

function UIController:_playAndWait(tw: Tween)
	tw:Play()
	tw.Completed:Wait()
end

function UIController:_applyBlurCam(opening: boolean)
	local blur: BlurEffect = self.BlurEffect
	local cam = workspace.CurrentCamera
	local toSize = opening and CONFIG.BLUR_OPEN or CONFIG.BLUR_CLOSED
	local toFov = opening and CONFIG.OPEN_FOV or CONFIG.DEFAULT_FOV
	local t1 = tween(blur, { Size = toSize }, opening and CONFIG.OPEN_TIME or CONFIG.CLOSE_TIME, CONFIG.EASING_STYLE, opening and CONFIG.EASING_DIR_OUT or CONFIG.EASING_DIR_IN)
	local t2 = tween(cam, { FieldOfView = toFov }, opening and CONFIG.OPEN_TIME or CONFIG.CLOSE_TIME, CONFIG.EASING_STYLE, opening and CONFIG.EASING_DIR_OUT or CONFIG.EASING_DIR_IN)
	t1:Play()
	t2:Play()
end

function UIController:_moveFrame(frame: Frame, y: number, time: number?)
	tween(frame, { Position = UDim2.new(0.5, 0, y, 0) }, time or CONFIG.OPEN_TIME, CONFIG.EASING_STYLE, y < 0.5 and CONFIG.EASING_DIR_OUT or CONFIG.EASING_DIR_IN):Play()
end

function UIController:_getVisibleNonPlantFrames()
	local list = {}
	for _, f in ipairs(self.FramesFolder:GetChildren()) do
		if isManagedFrame(f) and f ~= self.PlantInventory and f.Visible then
			table.insert(list, f)
		end
	end
	return list
end

function UIController:_forceHide(frame: Frame)
	local scale = frame:FindFirstChildOfClass("UIScale")
	if scale then
		scale.Scale = 0
	end
	frame:SetAttribute(OPENED_FRAME_ATTRIBUTE, false)
	frame.Visible = false
	if self.CurrentFrame == frame then
		self.CurrentFrame = nil
	end
end

function UIController:_forceCloseFromButton(frame: Frame, button: GuiButton, source: string)
	if not self:_isActiveController() then
		return
	end

	local now = os.clock()
	self._lastCloseClickAtByFrame = self._lastCloseClickAtByFrame or {}
	local lastClickAt = self._lastCloseClickAtByFrame[frame]
	if lastClickAt and now - lastClickAt < 0.08 then
		return
	end
	self._lastCloseClickAtByFrame[frame] = now

	closeButtonLog(
		frame.Name,
		"xClicked",
		"version",
		CLOSE_BUTTON_DEBUG_VERSION,
		"source",
		source,
		"frame",
		safeName(frame),
		"button",
		safeName(button),
		"frameVisibleBefore",
		tostring(frame.Visible),
		"isAnimatingBefore",
		tostring(self.IsAnimating),
		"currentFrame",
		safeName(self.CurrentFrame)
	)

	frame:SetAttribute(OPENED_FRAME_ATTRIBUTE, false)
	local scale = frame:FindFirstChildOfClass("UIScale")
	if scale then
		scale.Scale = 0
	end
	frame.Visible = false
	frame.Position = UDim2.new(0.5, 0, 10, 0)
	for _, candidate in ipairs(self.FramesFolder:GetChildren()) do
		if candidate ~= frame and candidate:IsA("Frame") and candidate.Name == frame.Name then
			closeButtonWarn(
				frame.Name,
				"duplicateFrameClosed",
				"version",
				CLOSE_BUTTON_DEBUG_VERSION,
				"wiredFrame",
				safeName(frame),
				"duplicate",
				safeName(candidate),
				"duplicateVisibleBefore",
				tostring(candidate.Visible)
			)
			self:_forceHide(candidate)
		end
	end

	if self.PlantInventory and frame == self.PlantInventory then
		self.PlantVisible = false
	end
	if self.CurrentFrame == frame then
		self.CurrentFrame = nil
	end

	if not (self.CurrentFrame and self.CurrentFrame.Visible) and not self.PlantVisible then
		self:_applyBlurCam(false)
	end
	self.IsAnimating = false

	closeButtonLog(
		frame.Name,
		"xClosed",
		"version",
		CLOSE_BUTTON_DEBUG_VERSION,
		"source",
		source,
		"frame",
		safeName(frame),
		"frameVisibleAfter",
		tostring(frame.Visible),
		"scale",
		tostring(scale and scale.Scale or "nil"),
		"currentFrameAfter",
		safeName(self.CurrentFrame)
	)

	task.delay(0.12, function()
		if frame.Parent and frame.Visible then
			closeButtonWarn(
				frame.Name,
				"xCloseOverridden",
				"version",
				CLOSE_BUTTON_DEBUG_VERSION,
				"frame",
				safeName(frame),
				"button",
				safeName(button),
				"source",
				source,
				"currentFrame",
				safeName(self.CurrentFrame),
				"isAnimating",
				tostring(self.IsAnimating)
			)
		end
	end)
end

function UIController:_connectFrameCloseButton(frame: Frame, button: Instance)
	if not (button:IsA("TextButton") or button:IsA("ImageButton")) then
		return
	end
	if button.Name ~= "X" then
		return
	end

	self._closeButtonConnections = self._closeButtonConnections or {}
	if self._closeButtonConnections[button] then
		return
	end

	if CLOSE_DIAGNOSTIC_FRAME_NAMES[frame.Name] then
		button.Active = true
		button.Selectable = true
		button.ZIndex = math.max(button.ZIndex, 100)
		pcall(function()
			button.Modal = false
		end)

		local ancestor = button.Parent
		while ancestor and ancestor ~= frame do
			if ancestor:IsA("GuiObject") then
				ancestor.ZIndex = math.max(ancestor.ZIndex, 90)
				pcall(function()
					ancestor.Modal = false
				end)
			end
			ancestor = ancestor.Parent
		end
	end

	local connections = {}
	if CLOSE_DIAGNOSTIC_FRAME_NAMES[frame.Name] then
		connections[#connections + 1] = button.MouseButton1Click:Connect(function()
			self:_forceCloseFromButton(frame, button, "MouseButton1Click")
		end)
		connections[#connections + 1] = button.Activated:Connect(function()
			self:_forceCloseFromButton(frame, button, "Activated")
		end)
	else
		connections[#connections + 1] = button.MouseButton1Click:Connect(function()
			if frame.Visible then
				self:ToggleFrame(frame)
			end
		end)
	end
	self._closeButtonConnections[button] = connections

	if frame.Name == "Gifts" then
		giftOpenUiLog(
			"xConnectionMade",
			"version",
			GIFT_OPENUI_DEBUG_VERSION,
			"signals",
			"MouseButton1Click,Activated",
			"frame",
			safeName(frame),
			"button",
			safeName(button),
			"visible",
			tostring(button.Visible),
			"active",
			tostring(button.Active),
			"z",
			button.ZIndex
		)
	end

	closeButtonLog(
		frame.Name,
		"xConnectionMade",
		"version",
		CLOSE_BUTTON_DEBUG_VERSION,
		"signals",
		"MouseButton1Click,Activated",
		"frame",
		safeName(frame),
		"button",
		safeName(button),
		"visible",
		tostring(button.Visible),
		"active",
		tostring(button.Active),
		"z",
		button.ZIndex,
		"sameNamedFrameCount",
		countFrameChildrenByName(self.FramesFolder, frame.Name),
		"visibleInstanceIsWired",
		tostring(self.FramesFolder and self.FramesFolder:FindFirstChild(frame.Name) == frame)
	)
end

function UIController:_initializeFrame(frame: Instance)
	if not isManagedFrame(frame) then
		return
	end

	local typedFrame = frame :: Frame
	local shouldPreserve = typedFrame.Visible == true and shouldPreserveVisibleFrame(typedFrame)
	local uiScale = typedFrame:FindFirstChildOfClass("UIScale")
	if not uiScale then
		uiScale = Instance.new("UIScale")
		uiScale.Parent = typedFrame
	end

	if shouldPreserve then
		uiScale.Scale = 1
		typedFrame.Visible = true
		if typedFrame == self.PlantInventory then
			self.PlantVisible = true
			typedFrame.Position = UDim2.new(0.5, 0, 0.712, 0)
		else
			self.CurrentFrame = typedFrame
			typedFrame.Position = UDim2.new(0.5, 0, self.PlantVisible and 0.4 or 0.5, 0)
		end
	else
		typedFrame:SetAttribute(OPENED_FRAME_ATTRIBUTE, false)
		uiScale.Scale = 0
		typedFrame.Visible = false
		typedFrame.Position = UDim2.new(0.5, 0, 10, 0)
	end

	for _, obj in ipairs(typedFrame:GetDescendants()) do
		self:_connectFrameCloseButton(typedFrame, obj)
	end

	self._frameDescendantConnections = self._frameDescendantConnections or {}
	if self._frameDescendantConnections[typedFrame] then
		self._frameDescendantConnections[typedFrame]:Disconnect()
	end
	self._frameDescendantConnections[typedFrame] = typedFrame.DescendantAdded:Connect(function(obj)
		self:_connectFrameCloseButton(typedFrame, obj)
	end)
end

function UIController:_closeNonPlant()
	local f: Frame? = self.CurrentFrame
	if not f or not f.Visible then
		return
	end
	self.IsAnimating = true
	local scale = f:FindFirstChildOfClass("UIScale")
	if scale then
		self:_playAndWait(tween(scale, { Scale = 1.15 }, CONFIG.POPUP_TIME, CONFIG.EASING_STYLE, CONFIG.EASING_DIR_OUT))
	end
	local t1 = tween(f, { Position = UDim2.new(0.5, 0, 10, 0) }, CONFIG.CLOSE_TIME, CONFIG.EASING_STYLE, CONFIG.EASING_DIR_IN)
	local t2 = scale and tween(scale, { Scale = 0 }, CONFIG.CLOSE_TIME, CONFIG.EASING_STYLE, CONFIG.EASING_DIR_IN)
	t1:Play()
	if t2 then
		t2:Play()
	end
	t1.Completed:Wait()
	f:SetAttribute(OPENED_FRAME_ATTRIBUTE, false)
	f.Visible = false
	self.CurrentFrame = nil
	if not self.PlantVisible then
		self:_applyBlurCam(false)
	end
	self.IsAnimating = false
end

function UIController:_openNonPlant(frame: Frame)
	self.IsAnimating = true
	self.CurrentFrame = frame
	frame:SetAttribute(OPENED_FRAME_ATTRIBUTE, true)
	frame.Visible = true
	frame.Position = UDim2.new(0.5, 0, 10, 0)
	local uiScale = frame:FindFirstChildOfClass("UIScale")
	if not uiScale then
		uiScale = Instance.new("UIScale")
		uiScale.Parent = frame
	end
	uiScale.Scale = 0
	local t1 = tween(frame, { Position = UDim2.new(0.5, 0, self.PlantVisible and 0.4 or 0.5, 0) }, CONFIG.OPEN_TIME, CONFIG.EASING_STYLE, CONFIG.EASING_DIR_OUT)
	local t2 = tween(uiScale, { Scale = 1 }, CONFIG.OPEN_TIME, CONFIG.EASING_STYLE, CONFIG.EASING_DIR_OUT)
	t1:Play()
	t2:Play()
	self:_applyBlurCam(true)
	t1.Completed:Wait()
	self.IsAnimating = false
end

function UIController:_repositionForDual()
	if self.CurrentFrame and self.CurrentFrame.Visible and self.PlantVisible then
		self:_moveFrame(self.CurrentFrame, 0.4)
		self:_moveFrame(self.PlantInventory, 0.712)
	end
end

function UIController:_openPlant()
	local frame: Frame = self.PlantInventory
	if self.PlantVisible then
		self:_closePlant()
		return
	end
	self.PlantVisible = true
	frame:SetAttribute(OPENED_FRAME_ATTRIBUTE, true)
	frame.Visible = true
	frame.Position = UDim2.new(0.5, 0, 10, 0)
	local uiScale = frame:FindFirstChildOfClass("UIScale")
	if not uiScale then
		uiScale = Instance.new("UIScale")
		uiScale.Parent = frame
	end
	uiScale.Scale = 0
	local t1 = tween(frame, { Position = UDim2.new(0.5, 0, 0.712, 0) }, CONFIG.OPEN_TIME, CONFIG.EASING_STYLE, CONFIG.EASING_DIR_OUT)
	local t2 = tween(uiScale, { Scale = 1 }, CONFIG.OPEN_TIME, CONFIG.EASING_STYLE, CONFIG.EASING_DIR_OUT)
	t1:Play(); t2:Play()
	t1.Completed:Wait()
	self:_repositionForDual()
end

function UIController:_closePlant()
	if not self.PlantVisible then
		return
	end
	local frame: Frame = self.PlantInventory
	self.IsAnimating = true
	local scale = frame:FindFirstChildOfClass("UIScale")
	if scale then
		self:_playAndWait(tween(scale, { Scale = 1.15 }, CONFIG.POPUP_TIME, CONFIG.EASING_STYLE, CONFIG.EASING_DIR_OUT))
	end
	local t1 = tween(frame, { Position = UDim2.new(0.5, 0, 10, 0) }, CONFIG.CLOSE_TIME, CONFIG.EASING_STYLE, CONFIG.EASING_DIR_IN)
	local t2 = scale and tween(scale, { Scale = 0 }, CONFIG.CLOSE_TIME, CONFIG.EASING_STYLE, CONFIG.EASING_DIR_IN)
	t1:Play(); if t2 then t2:Play() end
	t1.Completed:Wait()
	frame:SetAttribute(OPENED_FRAME_ATTRIBUTE, false)
	frame.Visible = false
	self.PlantVisible = false
	if not (self.CurrentFrame and self.CurrentFrame.Visible) then
		self:_applyBlurCam(false)
	end
	self.IsAnimating = false
end

function UIController:_cacheButtons()
	self.Buttons = {}
	self._buttonConnections = self._buttonConnections or {}

	local function connectButton(btn: Instance)
		if not (btn:IsA("TextButton") or btn:IsA("ImageButton")) then
			return
		end

		if self._buttonConnections[btn] then
			return
		end

		table.insert(self.Buttons, btn)
		self._buttonConnections[btn] = btn.MouseButton1Click:Connect(function()
			if not self:_isActiveController() or self.ActiveErrorFrame or self.IsAnimating then
				return
			end
			local target = self.FramesFolder:FindFirstChild(btn.Name)
			if target and target:IsA("Frame") then
				self:ToggleFrame(target)
			end
		end)
	end

	local function disconnectButton(btn: Instance)
		local connection = self._buttonConnections[btn]
		if connection then
			connection:Disconnect()
			self._buttonConnections[btn] = nil
		end

		for index = #self.Buttons, 1, -1 do
			if self.Buttons[index] == btn then
				table.remove(self.Buttons, index)
			end
		end
	end

	for _, obj in ipairs(self.Main:GetDescendants()) do
		connectButton(obj)
	end

	if self._buttonAddedConnection then
		self._buttonAddedConnection:Disconnect()
	end
	self._buttonAddedConnection = self.Main.DescendantAdded:Connect(connectButton)

	if self._buttonRemovingConnection then
		self._buttonRemovingConnection:Disconnect()
	end
	self._buttonRemovingConnection = self.Main.DescendantRemoving:Connect(disconnectButton)
end

function UIController:RefreshButtons()
	if not self.Main or not self.Main.Parent then
		return
	end

	self:_cacheButtons()
end

function UIController:_initializeFrames()
	self.PlantInventory = self.FramesFolder:FindFirstChild("PlantInventory") :: Frame?
	for _, frame in ipairs(self.FramesFolder:GetChildren()) do
		self:_initializeFrame(frame)
	end

	if self._frameAddedConnection then
		self._frameAddedConnection:Disconnect()
	end
	self._frameAddedConnection = self.FramesFolder.ChildAdded:Connect(function(frame)
		self:_initializeFrame(frame)
	end)

	if self._frameRemovingConnection then
		self._frameRemovingConnection:Disconnect()
	end
	self._frameRemovingConnection = self.FramesFolder.ChildRemoved:Connect(function(frame)
		if self._frameDescendantConnections and self._frameDescendantConnections[frame] then
			self._frameDescendantConnections[frame]:Disconnect()
			self._frameDescendantConnections[frame] = nil
		end
	end)
end

function UIController:_initializePartTriggers()
	self._hookedParts = self._hookedParts or {}

	local function hookPart(part: Instance, forcedFrameName: string?)
		if not part:IsA("BasePart") then
			return
		end
		if self._hookedParts[part] then
			return
		end
		self._hookedParts[part] = true

		part.Touched:Connect(function(hit)
			if not self:_isActiveController() or self.ActiveErrorFrame or self.IsAnimating then
				return
			end
			local char = self.Player.Character
			if not char or not hit:IsDescendantOf(char) then
				return
			end

			local frameName = forcedFrameName
			if not frameName then
				local attr = part:GetAttribute("FrameName")
				if typeof(attr) == "string" and attr ~= "" then
					frameName = attr
				end
			end
			if not frameName then
				return
			end

			local frame = self.FramesFolder:FindFirstChild(frameName)
			if frame and frame:IsA("Frame") and not frame.Visible then
				self:ToggleFrame(frame)
			end
		end)
	end

	local openPartsFolder = workspace:FindFirstChild("OpenParts")
	if openPartsFolder then
		for _, part in ipairs(openPartsFolder:GetChildren()) do
			hookPart(part, part.Name)
		end
		openPartsFolder.ChildAdded:Connect(function(child)
			hookPart(child, child.Name)
		end)
	end

	for _, inst in ipairs(CollectionService:GetTagged("Open")) do
		hookPart(inst, nil)
	end
	CollectionService:GetInstanceAddedSignal("Open"):Connect(function(inst)
		hookPart(inst, nil)
	end)
	CollectionService:GetInstanceRemovedSignal("Open"):Connect(function(inst)
		self._hookedParts[inst] = nil
	end)
end

function UIController:ToggleFrame(frame: Frame)
	if not self:_isActiveController() then
		return
	end
	if self.ActiveErrorFrame then
		return
	end
	if self.IsAnimating then
		return
	end

	for _, other in ipairs(self:_getVisibleNonPlantFrames()) do
		if other ~= frame then
			self:_forceHide(other)
		end
	end

	if self.PlantInventory and frame == self.PlantInventory then
		if self.PlantVisible then
			self:_closePlant()
		else
			self:_openPlant()
			self:_repositionForDual()
		end
		return
	end

	if frame.Visible and self.CurrentFrame == frame then
		self:_closeNonPlant()
		return
	end

	if self.CurrentFrame and self.CurrentFrame.Visible and self.CurrentFrame ~= frame then
		self:_closeNonPlant()
	end

	self:_openNonPlant(frame)
	self:_repositionForDual()
end

function UIController:CloseAllFrames()
	if not self:_isActiveController() then
		return
	end
	if self.ActiveErrorFrame or self.IsAnimating then
		return
	end
	self:_closeNonPlant()
	self:_closePlant()
	for _, f in ipairs(self:_getVisibleNonPlantFrames()) do
		self:_forceHide(f)
	end
	self:_applyBlurCam(false)
end

function UIController:OpenFrame(frameName: string)
	if not self:_isActiveController() then
		return
	end
	if self.ActiveErrorFrame or self.IsAnimating then
		return
	end
	local frame = self.FramesFolder:FindFirstChild(frameName)
	if frame and frame:IsA("Frame") then
		self:ToggleFrame(frame)
	else
		warn(("UIController: Frame '%s' not found!"):format(frameName))
	end
end

function UIController.new(player: Player)
	local self = setmetatable({}, UIController)
	self.Player = player
	self.PlayerGui = player:WaitForChild("PlayerGui")
	self.ControllerGeneration = nextControllerGeneration(self.PlayerGui)
	self.Destroyed = false
	self.Main = self.PlayerGui:WaitForChild("HUD")
	self.FramesFolder = self.PlayerGui:WaitForChild("Frames")
	if self.FramesFolder:IsA("ScreenGui") then
		self.FramesFolder.DisplayOrder = math.max(self.FramesFolder.DisplayOrder, FRAMES_DISPLAY_ORDER)
		self.FramesFolder.IgnoreGuiInset = true
		self.FramesFolder.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	end
	self.CurrentFrame = nil
	self.IsAnimating = false
	self.PlantVisible = false
	self.ActiveErrorFrame = nil

	giftOpenUiLog(
		"start",
		"version",
		GIFT_OPENUI_DEBUG_VERSION,
		"player",
		player and player.Name or "nil",
		"playerGui",
		safeName(self.PlayerGui)
	)
	self:_ensureBlurEffect()
	self:_initializeFrames()
	self:_cacheButtons()
	self:_initializePartTriggers()
	return self
end

function UIController:Destroy()
	if self.Destroyed then
		return
	end

	self.Destroyed = true

	for _, connection in pairs(self._buttonConnections or {}) do
		connection:Disconnect()
	end
	self._buttonConnections = {}
	self.Buttons = {}

	if self._buttonAddedConnection then
		self._buttonAddedConnection:Disconnect()
		self._buttonAddedConnection = nil
	end
	if self._buttonRemovingConnection then
		self._buttonRemovingConnection:Disconnect()
		self._buttonRemovingConnection = nil
	end
	if self._frameAddedConnection then
		self._frameAddedConnection:Disconnect()
		self._frameAddedConnection = nil
	end
	if self._frameRemovingConnection then
		self._frameRemovingConnection:Disconnect()
		self._frameRemovingConnection = nil
	end
	for _, connection in pairs(self._frameDescendantConnections or {}) do
		connection:Disconnect()
	end
	self._frameDescendantConnections = {}
	for _, connections in pairs(self._closeButtonConnections or {}) do
		for _, connection in ipairs(connections) do
			connection:Disconnect()
		end
	end
	self._closeButtonConnections = {}
end

local player = Players.LocalPlayer
local controller = UIController.new(player)
print("UIController initialized for player:", player and player.Name or "Unknown")

script.Destroying:Connect(function()
	controller:Destroy()
end)

return controller
