local Players = game:GetService("Players")

local TutorialGuideBeamController = {}
TutorialGuideBeamController.__index = TutorialGuideBeamController

local ORIGIN_ATTACHMENT_NAME = "LocalObjectiveGuideOriginAttachment"
local TARGET_ATTACHMENT_NAME = "LocalObjectiveGuideTargetAttachment"
local BEAM_NAME = "LocalObjectiveGuideBeam"
local CHEVRON_IMAGE = "rbxassetid://140380652730254"

local ORIGIN_OFFSET = Vector3.new(0, -0.6, -0.35)
local DEFAULT_TARGET_OFFSET = Vector3.new(0, -0.35, 0)
local DEFAULT_PRIORITY = 50

local BEAM_COLOR = ColorSequence.new(Color3.new(1, 1, 1))
local BEAM_TRANSPARENCY = NumberSequence.new(0.05)

local sharedStatesByPlayer = setmetatable({}, { __mode = "k" })

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

local function getGuideBasePart(instance)
	if typeof(instance) ~= "Instance" or instance.Parent == nil then
		return nil
	end

	if instance:IsA("BasePart") then
		return instance
	end
	if instance:IsA("Attachment") then
		local parent = instance.Parent
		return if parent and parent:IsA("BasePart") then parent else nil
	end
	if instance:IsA("Model") then
		local primaryPart = instance.PrimaryPart
		if primaryPart and primaryPart:IsA("BasePart") then
			return primaryPart
		end

		for _, childName in ipairs({ "HumanoidRootPart", "RootPart", "Handle", "LevelUp" }) do
			local part = instance:FindFirstChild(childName, true)
			if part and part:IsA("BasePart") then
				return part
			end
		end

		return instance:FindFirstChildWhichIsA("BasePart", true)
	end

	return instance:FindFirstChildWhichIsA("BasePart", true)
end

local function getTargetGuidePart(target)
	if typeof(target) == "Instance" then
		return getGuideBasePart(target)
	end

	if typeof(target) ~= "table" then
		return nil
	end
	local guidePart = target.guidePart or target.targetPart or target.part
	local resolvedGuidePart = getGuideBasePart(guidePart)
	if resolvedGuidePart then
		return resolvedGuidePart
	end

	local instance = target.instance or target.model
	local resolvedInstancePart = getGuideBasePart(instance)
	if resolvedInstancePart then
		return resolvedInstancePart
	end

	return nil
end

local function hasExplicitTargetInstance(target)
	if typeof(target) == "Instance" then
		return true
	end
	if typeof(target) ~= "table" then
		return false
	end

	return typeof(target.guidePart) == "Instance"
		or typeof(target.targetPart) == "Instance"
		or typeof(target.part) == "Instance"
		or typeof(target.instance) == "Instance"
		or typeof(target.model) == "Instance"
end

local function getTargetOffset(target, options)
	if typeof(options) == "table" and typeof(options.TargetOffset or options.targetOffset) == "Vector3" then
		return options.TargetOffset or options.targetOffset
	end
	if typeof(target) == "table" and typeof(target.guideOffset) == "Vector3" then
		return target.guideOffset
	end

	return DEFAULT_TARGET_OFFSET
end

local function getTargetPosition(target)
	if typeof(target) ~= "table" then
		return nil
	end

	local position = target.position or target.Position
	return if typeof(position) == "Vector3" then position else nil
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

local SharedGuideState = {}
SharedGuideState.__index = SharedGuideState

function SharedGuideState.new(player)
	local self = setmetatable({
		_destroyed = false,
		_player = player,
		_requests = {},
		_activeRequestKey = nil,
		_activeTarget = nil,
		_activeOptions = nil,
		_targetPart = nil,
		_targetKey = "",
		_beam = nil,
		_originAttachment = nil,
		_targetAttachment = nil,
		_positionTargetPart = nil,
		_characterConnections = {},
		_targetConnections = {},
	}, SharedGuideState)

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

function SharedGuideState:_clearVisuals()
	disconnectAll(self._targetConnections)

	if self._beam then
		self._beam:Destroy()
		self._beam = nil
	end
	if self._targetAttachment then
		self._targetAttachment:Destroy()
		self._targetAttachment = nil
	end
	if self._positionTargetPart then
		self._positionTargetPart:Destroy()
		self._positionTargetPart = nil
	end
	if self._originAttachment then
		self._originAttachment:Destroy()
		self._originAttachment = nil
	end

	self._targetPart = nil
	self._targetKey = ""
end

function SharedGuideState:_ensureOriginAttachment()
	local root = getHumanoidRootPart(self._player.Character)
	if not root then
		return nil
	end

	local attachment = getReusableAttachment(root, ORIGIN_ATTACHMENT_NAME)
	attachment.Position = ORIGIN_OFFSET
	return attachment
end

function SharedGuideState:_createBeam(originAttachment, targetAttachment)
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

function SharedGuideState:_bindTargetLifecycle(targetPart)
	disconnectAll(self._targetConnections)

	table.insert(
		self._targetConnections,
		targetPart.Destroying:Connect(function()
			self:_refresh()
		end)
	)
	table.insert(
		self._targetConnections,
		targetPart.AncestryChanged:Connect(function(_, parent)
			if parent == nil then
				self:_refresh()
			end
		end)
	)
end

function SharedGuideState:_ensurePositionTargetPart(position)
	local part = self._positionTargetPart
	if not part or part.Parent == nil then
		part = Instance.new("Part")
		part.Name = "LocalObjectiveGuidePositionTarget"
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.Transparency = 1
		part.Size = Vector3.new(0.2, 0.2, 0.2)
		part.Parent = workspace.CurrentCamera or workspace
		self._positionTargetPart = part
	end

	part.CFrame = CFrame.new(position)
	return part
end

function SharedGuideState:_selectRequest()
	local selectedKey = nil
	local selectedRequest = nil

	for key, request in pairs(self._requests) do
		local targetType = if typeof(request) == "table" then typeof(request.target) else "nil"
		if targetType == "table" or targetType == "Instance" then
			local shouldSelect = selectedRequest == nil
				or request.priority > selectedRequest.priority
				or (request.priority == selectedRequest.priority and request.generation > selectedRequest.generation)
			if shouldSelect then
				selectedKey = key
				selectedRequest = request
			end
		end
	end

	self._activeRequestKey = selectedKey
	self._activeTarget = selectedRequest and selectedRequest.target or nil
	self._activeOptions = selectedRequest and selectedRequest.options or nil
end

function SharedGuideState:_refresh()
	if self._destroyed then
		self:_clearVisuals()
		return
	end

	self:_selectRequest()
	local target = self._activeTarget
	local options = self._activeOptions
	local targetType = typeof(target)
	if targetType ~= "table" and targetType ~= "Instance" then
		self:_clearVisuals()
		return
	end

	local position = getTargetPosition(target)
	local targetPart = getTargetGuidePart(target)
	if not targetPart and position and not hasExplicitTargetInstance(target) then
		targetPart = self:_ensurePositionTargetPart(position)
	end
	if not targetPart then
		self:_clearVisuals()
		return
	end

	local targetKey = tostring(self._activeRequestKey or "")
		.. "|"
		.. tostring(target.id or "")
		.. "|"
		.. tostring(target.kind or "")
		.. "|"
		.. targetPart:GetFullName()
	if position then
		targetKey = targetKey .. string.format("|%.2f|%.2f|%.2f", position.X, position.Y, position.Z)
	end
	if self._beam and self._targetPart == targetPart and self._targetKey == targetKey then
		local targetAttachment = self._targetAttachment
		if targetAttachment then
			targetAttachment.Position = getTargetOffset(target, options)
		end
		return
	end

	self:_clearVisuals()

	local originAttachment = self:_ensureOriginAttachment()
	if not originAttachment then
		return
	end

	local targetAttachment = getReusableAttachment(targetPart, TARGET_ATTACHMENT_NAME)
	targetAttachment.Position = getTargetOffset(target, options)

	self._originAttachment = originAttachment
	self._targetAttachment = targetAttachment
	self._targetPart = targetPart
	self._targetKey = targetKey
	self._beam = self:_createBeam(originAttachment, targetAttachment)
	self:_bindTargetLifecycle(targetPart)
end

function SharedGuideState:ShowGuide(requestKey, target, options, priority, generation)
	if self._destroyed then
		return
	end

	requestKey = tostring(requestKey or "")
	if requestKey == "" then
		return
	end

	local targetType = typeof(target)
	if targetType ~= "table" and targetType ~= "Instance" then
		self:HideGuide(requestKey)
		return
	end

	self._requests[requestKey] = {
		target = target,
		options = if typeof(options) == "table" then options else {},
		priority = math.floor(tonumber(priority) or DEFAULT_PRIORITY),
		generation = math.floor(tonumber(generation) or 0),
	}
	self:_refresh()
end

function SharedGuideState:HideGuide(requestKey)
	self._requests[tostring(requestKey or "")] = nil
	self:_refresh()
end

function SharedGuideState:Destroy()
	if self._destroyed then
		return
	end

	self._destroyed = true
	table.clear(self._requests)
	self._activeRequestKey = nil
	self._activeTarget = nil
	self._activeOptions = nil
	self:_clearVisuals()
	disconnectAll(self._characterConnections)
end

local function getSharedState(player)
	player = if typeof(player) == "Instance" and player:IsA("Player") then player else Players.LocalPlayer
	local state = sharedStatesByPlayer[player]
	if not state or state._destroyed then
		state = SharedGuideState.new(player)
		sharedStatesByPlayer[player] = state
	end

	return state
end

function TutorialGuideBeamController.new(player, options)
	player = if typeof(player) == "Instance" and player:IsA("Player") then player else Players.LocalPlayer
	options = if typeof(options) == "table" then options else {}

	local requestKey = tostring(options.RequestKey or options.requestKey or "")
	if requestKey == "" then
		requestKey = "guide_" .. tostring({})
	end

	local self = setmetatable({
		_destroyed = false,
		_player = player,
		_priority = math.floor(tonumber(options.Priority or options.priority) or DEFAULT_PRIORITY),
		_requestKey = requestKey,
		_generation = 0,
		_state = getSharedState(player),
	}, TutorialGuideBeamController)

	return self
end

function TutorialGuideBeamController:ShowGuide(target, options)
	if self._destroyed then
		return
	end

	self._generation += 1
	self._state:ShowGuide(self._requestKey, target, options, self._priority, self._generation)
end

function TutorialGuideBeamController:UpdateTarget(target, options)
	self:ShowGuide(target, options)
end

function TutorialGuideBeamController:HideGuide(_reason)
	if self._destroyed then
		return
	end

	self._generation += 1
	self._state:HideGuide(self._requestKey)
end

function TutorialGuideBeamController:SetTarget(target)
	local targetType = typeof(target)
	if targetType ~= "table" and targetType ~= "Instance" then
		self:Clear()
		return
	end

	self:ShowGuide(target)
end

function TutorialGuideBeamController:Clear()
	self:HideGuide("clear")
end

function TutorialGuideBeamController:Destroy()
	if self._destroyed then
		return
	end

	self._destroyed = true
	self._generation += 1
	self._state:HideGuide(self._requestKey)
end

return TutorialGuideBeamController
