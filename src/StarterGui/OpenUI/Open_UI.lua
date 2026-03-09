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

local function tween(obj: Instance, props: {[string]: any}, time: number, style, dir)
	return TweenService:Create(obj, TweenInfo.new(time, style, dir), props)
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
		if f:IsA("Frame") and f ~= self.PlantInventory and f.Visible then
			table.insert(list, f)
		end
	end
	return list
end

function UIController:_forceHide(frame: Frame)
	local scale = frame:FindFirstChildOfClass("UIScale")
	if scale then scale.Scale = 0 end
	frame.Visible = false
	if self.CurrentFrame == frame then
		self.CurrentFrame = nil
	end
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
	if t2 then t2:Play() end
	t1.Completed:Wait()
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
	if not self.PlantVisible then return end
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
	frame.Visible = false
	self.PlantVisible = false
	if not (self.CurrentFrame and self.CurrentFrame.Visible) then
		self:_applyBlurCam(false)
	end
	self.IsAnimating = false
end

function UIController:_cacheButtons()
	self.Buttons = {}
	for _, obj in ipairs(self.Main:GetDescendants()) do
		if (obj:IsA("TextButton") or obj:IsA("ImageButton")) then
			table.insert(self.Buttons, obj)
		end
	end
	for _, btn: Instance in ipairs(self.Buttons) do
		if btn:IsA("TextButton") or btn:IsA("ImageButton") then
			btn.MouseButton1Click:Connect(function()
				if self.ActiveErrorFrame or self.IsAnimating then return end
				local target = self.FramesFolder:FindFirstChild(btn.Name)
				if target and target:IsA("Frame") then
					self:ToggleFrame(target)
				end
			end)
		end
	end
end

function UIController:_initializeFrames()
	self.PlantInventory = self.FramesFolder:FindFirstChild("PlantInventory") :: Frame?
	for _, frame in ipairs(self.FramesFolder:GetChildren()) do
		if frame:IsA("Frame") then
			local uiScale = frame:FindFirstChildOfClass("UIScale")
			if not uiScale then
				uiScale = Instance.new("UIScale")
				uiScale.Scale = 0
				uiScale.Parent = frame
			else
				uiScale.Scale = 0
			end
			frame.Visible = false
			frame.Position = UDim2.new(0.5, 0, 10, 0)
			for _, obj in ipairs(frame:GetDescendants()) do
				if (obj:IsA("TextButton") or obj:IsA("ImageButton")) and obj.Name == "X" then
					obj.MouseButton1Click:Connect(function()
						if frame.Visible then
							self:ToggleFrame(frame)
						end
					end)
				end
			end
		end
	end
end

function UIController:_initializePartTriggers()
	self._hookedParts = self._hookedParts or {}

	local function hookPart(part: Instance, forcedFrameName: string?)
		if not part:IsA("BasePart") then return end
		if self._hookedParts[part] then return end
		self._hookedParts[part] = true

		part.Touched:Connect(function(hit)
			if self.ActiveErrorFrame or self.IsAnimating then return end
			local char = self.Player.Character
			if not char or not hit:IsDescendantOf(char) then return end

			local frameName = forcedFrameName
			if not frameName then
				local attr = part:GetAttribute("FrameName")
				if typeof(attr) == "string" and attr ~= "" then
					frameName = attr
				end
			end
			if not frameName then return end

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
	if self.ActiveErrorFrame then return end
	if self.IsAnimating then return end

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
	if self.ActiveErrorFrame or self.IsAnimating then return end
	self:_closeNonPlant()
	self:_closePlant()
	for _, f in ipairs(self:_getVisibleNonPlantFrames()) do
		self:_forceHide(f)
	end
	self:_applyBlurCam(false)
end

function UIController:OpenFrame(frameName: string)
	if self.ActiveErrorFrame or self.IsAnimating then return end
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
	self.Main = self.PlayerGui:WaitForChild("HUD")
	self.FramesFolder = self.PlayerGui:WaitForChild("Frames")
	self.CurrentFrame = nil
	self.IsAnimating = false
	self.PlantVisible = false
	self.ActiveErrorFrame = nil

	self:_ensureBlurEffect()
	self:_initializeFrames()
	self:_cacheButtons()
	self:_initializePartTriggers()
	return self
end

local player = Players.LocalPlayer
local controller = UIController.new(player)
print("UIController initialized for player:", player and player.Name or "Unknown")

return controller
