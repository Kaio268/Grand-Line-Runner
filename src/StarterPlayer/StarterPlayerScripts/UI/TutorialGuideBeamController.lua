local Players = game:GetService("Players")

local TutorialGuideBeamController = {}
TutorialGuideBeamController.__index = TutorialGuideBeamController

local ORIGIN_ATTACHMENT_NAME = "TutorialGuideOriginAttachment"
local TARGET_ATTACHMENT_NAME = "TutorialGuideTargetAttachment"
local BEAM_NAME = "TutorialGuideBeam"
local CHEVRON_IMAGE = "rbxassetid://133002224706646"

local ORIGIN_OFFSET = Vector3.new(0, -0.6, -0.35)
local DEFAULT_TARGET_OFFSET = Vector3.new(0, -0.35, 0)

local BEAM_COLOR = ColorSequence.new(Color3.new(1, 1, 1))
local BEAM_TRANSPARENCY = NumberSequence.new(0.05)

local function disconnectAll(connections)
	for _, connection in ipairs(connections) do
		connection:Disconnect()
	end
	table.clear(connections)
end

local function getHumanoidRootPart(character)
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

local function getTargetGuidePart(target)
	if typeof(target) ~= "table" then
		return nil
	end

	local guidePart = target.guidePart or target.targetPart or target.part
	if typeof(guidePart) == "Instance" and guidePart:IsA("BasePart") and guidePart.Parent ~= nil then
		return guidePart
	end

	local instance = target.instance or target.model
	if typeof(instance) ~= "Instance" or instance.Parent == nil then
		return nil
	end

	if instance:IsA("BasePart") then
		return instance
	end
	if instance:IsA("Model") then
		local primaryPart = instance.PrimaryPart
		if primaryPart and primaryPart:IsA("BasePart") then
			return primaryPart
		end

		for _, childName in ipairs({ "HumanoidRootPart", "RootPart", "Handle" }) do
			local part = instance:FindFirstChild(childName, true)
			if part and part:IsA("BasePart") then
				return part
			end
		end

		return instance:FindFirstChildWhichIsA("BasePart", true)
	end

	return instance:FindFirstChildWhichIsA("BasePart", true)
end

local function getTargetOffset(target)
	if typeof(target) == "table" and typeof(target.guideOffset) == "Vector3" then
		return target.guideOffset
	end

	return DEFAULT_TARGET_OFFSET
end

local function getReusableAttachment(part, name)
	local found = nil
	for _, child in ipairs(part:GetChildren()) do
		if child.Name == name and child:IsA("Attachment") then
			if not found then
				found = child
			else
				child:Destroy()
			end
		end
	end

	if found then
		return found
	end

	local attachment = Instance.new("Attachment")
	attachment.Name = name
	attachment.Parent = part
	return attachment
end

function TutorialGuideBeamController.new(player)
	player = if typeof(player) == "Instance" and player:IsA("Player") then player else Players.LocalPlayer

	local self = setmetatable({
		_destroyed = false,
		_player = player,
		_target = nil,
		_targetPart = nil,
		_targetKey = "",
		_beam = nil,
		_originAttachment = nil,
		_targetAttachment = nil,
		_characterConnections = {},
		_targetConnections = {},
	}, TutorialGuideBeamController)

	table.insert(
		self._characterConnections,
		player.CharacterAdded:Connect(function()
			self:_clearVisuals()
			task.defer(function()
				self:_refresh()
			end)
		end)
	)
	table.insert(
		self._characterConnections,
		player.CharacterRemoving:Connect(function()
			self:_clearVisuals()
		end)
	)

	return self
end

function TutorialGuideBeamController:_clearVisuals()
	disconnectAll(self._targetConnections)

	if self._beam then
		self._beam:Destroy()
		self._beam = nil
	end
	if self._targetAttachment then
		self._targetAttachment:Destroy()
		self._targetAttachment = nil
	end
	if self._originAttachment then
		self._originAttachment:Destroy()
		self._originAttachment = nil
	end

	self._targetPart = nil
	self._targetKey = ""
end

function TutorialGuideBeamController:_ensureOriginAttachment()
	local root = getHumanoidRootPart(self._player.Character)
	if not root then
		return nil
	end

	local attachment = getReusableAttachment(root, ORIGIN_ATTACHMENT_NAME)
	attachment.Position = ORIGIN_OFFSET
	return attachment
end

function TutorialGuideBeamController:_createBeam(originAttachment, targetAttachment)
	local beam = Instance.new("Beam")
	beam.Name = BEAM_NAME
	beam.Attachment0 = originAttachment
	beam.Attachment1 = targetAttachment
	beam.Texture = CHEVRON_IMAGE
	beam.TextureMode = Enum.TextureMode.Wrap
	beam.TextureSpeed = 5.5
	beam.TextureLength = 2.8
	beam.FaceCamera = true
	beam.LightEmission = 1
	beam.Segments = 12
	beam.Width0 = 2.15
	beam.Width1 = 2.15
	beam.CurveSize0 = 0
	beam.CurveSize1 = 0
	beam.Color = BEAM_COLOR
	beam.Transparency = BEAM_TRANSPARENCY
	beam.Parent = originAttachment
	return beam
end

function TutorialGuideBeamController:_bindTargetLifecycle(targetPart)
	disconnectAll(self._targetConnections)

	table.insert(
		self._targetConnections,
		targetPart.Destroying:Connect(function()
			self:Clear()
		end)
	)
	table.insert(
		self._targetConnections,
		targetPart.AncestryChanged:Connect(function(_, parent)
			if parent == nil then
				self:Clear()
			end
		end)
	)
end

function TutorialGuideBeamController:_refresh()
	if self._destroyed or typeof(self._target) ~= "table" then
		self:_clearVisuals()
		return
	end

	local targetPart = getTargetGuidePart(self._target)
	if not targetPart then
		self:_clearVisuals()
		return
	end

	local targetKey = tostring(self._target.id or "")
		.. "|"
		.. tostring(self._target.kind or "")
		.. "|"
		.. targetPart:GetFullName()
	if self._beam and self._targetPart == targetPart and self._targetKey == targetKey then
		local targetAttachment = self._targetAttachment
		if targetAttachment then
			targetAttachment.Position = getTargetOffset(self._target)
		end
		return
	end

	self:_clearVisuals()

	local originAttachment = self:_ensureOriginAttachment()
	if not originAttachment then
		return
	end

	local targetAttachment = getReusableAttachment(targetPart, TARGET_ATTACHMENT_NAME)
	targetAttachment.Position = getTargetOffset(self._target)

	self._originAttachment = originAttachment
	self._targetAttachment = targetAttachment
	self._targetPart = targetPart
	self._targetKey = targetKey
	self._beam = self:_createBeam(originAttachment, targetAttachment)
	self:_bindTargetLifecycle(targetPart)
end

function TutorialGuideBeamController:SetTarget(target)
	if self._destroyed then
		return
	end

	if typeof(target) ~= "table" then
		self:Clear()
		return
	end

	self._target = target
	self:_refresh()
end

function TutorialGuideBeamController:Clear()
	if self._destroyed then
		return
	end

	self._target = nil
	self:_clearVisuals()
end

function TutorialGuideBeamController:Destroy()
	if self._destroyed then
		return
	end

	self._destroyed = true
	self._target = nil
	self:_clearVisuals()
	disconnectAll(self._characterConnections)
end

return TutorialGuideBeamController
