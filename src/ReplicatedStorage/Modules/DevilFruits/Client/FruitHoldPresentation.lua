local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local DevilFruitConfig = require(Modules:WaitForChild("Configs"):WaitForChild("DevilFruits"))
local DevilFruits = Modules:WaitForChild("DevilFruits")
local FruitGripController = require(DevilFruits:WaitForChild("FruitGripController"))
local DiagnosticLogLimiter = require(DevilFruits:WaitForChild("DiagnosticLogLimiter"))

local FruitHoldPresentation = {}

local TOOL_ATTR_KIND = "InventoryItemKind"
local TOOL_ATTR_FRUIT_KEY = "FruitKey"
local TOOL_KIND_DEVIL_FRUIT = "DevilFruit"
local INFO_COOLDOWN = 0.35
local WARN_COOLDOWN = 4
local POSE_DEBUG_INTERVAL = 0.75
local CLEANUP_WEIGHT = 0.01
local DEFAULT_FADE_SPEED = 14
local BLEND_MODE_ADDITIVE = "Additive"
local BLEND_MODE_REPLACE = "Replace"
local JOINT_MODE_STATIC = "Static"
local JOINT_MODE_ARM_TARGET = "ArmTarget"

local statesByCharacter = setmetatable({}, { __mode = "k" })
local started = false
local renderConnection = nil
local updateSignalName = "RenderStepped"

local function getConfig()
	local gripDefaults = type(DevilFruitConfig.GripDefaults) == "table" and DevilFruitConfig.GripDefaults or nil
	local config = gripDefaults and gripDefaults.EquippedPresentation
	return type(config) == "table" and config or {}
end

local function shouldDebug(config)
	config = config or getConfig()
	local debugAttribute = typeof(config.DebugAttribute) == "string" and config.DebugAttribute or "DebugFruitHoldPresentation"
	return RunService:IsStudio() or ReplicatedStorage:GetAttribute(debugAttribute) == true
end

local function logInfo(message, ...)
	if not shouldDebug() then
		return
	end

	if not DiagnosticLogLimiter.ShouldEmit("FruitHoldPresentation:INFO", DiagnosticLogLimiter.BuildKey(message, ...), INFO_COOLDOWN) then
		return
	end

	print(string.format("[FRUIT HOLD] " .. message, ...))
end

local function logWarn(message, ...)
	if not DiagnosticLogLimiter.ShouldEmit("FruitHoldPresentation:WARN", DiagnosticLogLimiter.BuildKey(message, ...), WARN_COOLDOWN) then
		return
	end

	warn(string.format("[FRUIT HOLD][WARN] " .. message, ...))
end

local function formatCFrame(value)
	if typeof(value) ~= "CFrame" then
		return tostring(value)
	end

	local x, y, z = value:ToOrientation()
	return string.format("pos=(%.2f, %.2f, %.2f) rot=(%.1f, %.1f, %.1f)",
		value.Position.X,
		value.Position.Y,
		value.Position.Z,
		math.deg(x),
		math.deg(y),
		math.deg(z)
	)
end

local function formatVector3(value)
	if typeof(value) ~= "Vector3" then
		return tostring(value)
	end

	return string.format("(%.2f, %.2f, %.2f)", value.X, value.Y, value.Z)
end

local function getUpdateSignal()
	local ok, signal = pcall(function()
		return RunService.PreSimulation
	end)

	if ok and signal then
		return signal, "PreSimulation"
	end

	return RunService.RenderStepped, "RenderStepped"
end

local function isDevilFruitTool(instance)
	return typeof(instance) == "Instance"
		and instance:IsA("Tool")
		and instance:GetAttribute(TOOL_ATTR_KIND) == TOOL_KIND_DEVIL_FRUIT
		and typeof(instance:GetAttribute(TOOL_ATTR_FRUIT_KEY)) == "string"
end

local function findEquippedFruitTool(character)
	if typeof(character) ~= "Instance" then
		return nil
	end

	for _, child in ipairs(character:GetChildren()) do
		if isDevilFruitTool(child) then
			return child
		end
	end

	return nil
end

local function getRigKey(humanoid)
	if humanoid and humanoid.RigType == Enum.HumanoidRigType.R6 then
		return "R6"
	end

	return "R15"
end

local function normalizeBlendMode(value)
	local text = typeof(value) == "string" and string.lower(value) or ""
	if text == "replace" or text == "override" then
		return BLEND_MODE_REPLACE
	end

	return BLEND_MODE_ADDITIVE
end

local function normalizeJointMode(value)
	local text = typeof(value) == "string" and string.lower(value) or ""
	if text == "armtarget" or text == "r6armtarget" then
		return JOINT_MODE_ARM_TARGET
	end

	return JOINT_MODE_STATIC
end

local function safeUnit(vector, fallback)
	if vector.Magnitude > 0.001 then
		return vector.Unit
	end

	return fallback
end

local function findMotor(character, motorName)
	for _, descendant in ipairs(character:GetDescendants()) do
		if descendant:IsA("Motor6D") and descendant.Name == motorName then
			return descendant
		end
	end

	return nil
end

local function collectJoints(character, humanoid, config)
	local rigKey = getRigKey(humanoid)
	local rigConfig = type(config[rigKey]) == "table" and config[rigKey] or nil
	local jointConfig = rigConfig and type(rigConfig.Joints) == "table" and rigConfig.Joints or nil
	local blendMode = normalizeBlendMode(rigConfig and rigConfig.BlendMode or config.BlendMode)
	local jointMode = normalizeJointMode(rigConfig and rigConfig.Mode or config.Mode)
	local joints = {}

	for motorName, targetTransform in pairs(jointConfig or {}) do
		if typeof(targetTransform) ~= "CFrame" then
			continue
		end

		local motor = findMotor(character, motorName)
		if motor then
			joints[#joints + 1] = {
				BlendMode = blendMode,
				Mode = jointMode,
				RigConfig = rigConfig,
				Motor = motor,
				TargetTransform = targetTransform,
			}
		else
			logWarn("missing hold joint character=%s rig=%s motor=%s", character.Name, rigKey, tostring(motorName))
		end
	end

	return joints, rigKey
end

local function resetStateTransforms(state)
	for _, joint in ipairs(state and state.Joints or {}) do
		local motor = joint.Motor
		if typeof(motor) == "Instance" and motor.Parent then
			motor.Transform = CFrame.new()
		end
	end
end

local function getFruitGeometryCenter(tool)
	if typeof(tool) ~= "Instance" then
		return nil
	end

	local totalPosition = Vector3.new()
	local partCount = 0
	for _, descendant in ipairs(tool:GetDescendants()) do
		if descendant:IsA("BasePart") and descendant.Name ~= "Handle" and descendant.Transparency < 1 then
			totalPosition += descendant.Position
			partCount += 1
		end
	end

	if partCount > 0 then
		return totalPosition / partCount
	end

	local handle = tool:FindFirstChild("Handle")
	if handle and handle:IsA("BasePart") then
		return handle.Position
	end

	return nil
end

local function emitPoseDebug(state)
	if not shouldDebug() then
		return
	end

	if not state or state.RigKey ~= "R6" or typeof(state.LastSolvedHandWorld) ~= "Vector3" then
		return
	end

	local now = os.clock()
	if state.LastPoseDebugAt and (now - state.LastPoseDebugAt) < POSE_DEBUG_INTERVAL then
		return
	end
	state.LastPoseDebugAt = now

	local joint = state.Joints and state.Joints[1]
	local motor = joint and joint.Motor
	local torso = motor and motor.Part0
	if not (torso and torso:IsA("BasePart")) then
		return
	end

	local fruitCenter = getFruitGeometryCenter(state.Tool)
	if typeof(fruitCenter) ~= "Vector3" then
		return
	end

	local handLocal = torso.CFrame:PointToObjectSpace(state.LastSolvedHandWorld)
	local fruitLocal = torso.CFrame:PointToObjectSpace(fruitCenter)
	local fruitMinusHandLocal = torso.CFrame:VectorToObjectSpace(fruitCenter - state.LastSolvedHandWorld)

	if state.Tool and state.Tool.Parent then
		state.Tool:SetAttribute("FruitHoldSolvedHandLocal", handLocal)
		state.Tool:SetAttribute("FruitHoldCenterMinusHandLocal", fruitMinusHandLocal)
	end

	logInfo(
		"pose fruit=%s player=%s handLocal=%s fruitLocal=%s fruitMinusHand=%s grip=%s",
		tostring(state.FruitKey),
		state.Player and state.Player.Name or "?",
		formatVector3(handLocal),
		formatVector3(fruitLocal),
		formatVector3(fruitMinusHandLocal),
		formatCFrame(state.Tool and state.Tool.Grip)
	)
end

local function getR6ArmTargetTransform(state, joint)
	local motor = joint.Motor
	local part0 = motor and motor.Part0
	local arm = motor and motor.Part1
	if not (part0 and arm and part0:IsA("BasePart") and arm:IsA("BasePart")) then
		return joint.TargetTransform, false
	end

	local rigConfig = type(joint.RigConfig) == "table" and joint.RigConfig or {}
	local handTargetLocal = rigConfig.HandTargetLocal
	if typeof(handTargetLocal) ~= "Vector3" then
		return joint.TargetTransform, false
	end

	local shoulderWorld = (part0.CFrame * motor.C0).Position
	local desiredHandWorld = part0.CFrame:PointToWorldSpace(handTargetLocal)
	local armLength = math.max(0.1, arm.Size.Y)
	local shoulderToHand = safeUnit(desiredHandWorld - shoulderWorld, -part0.CFrame.LookVector)
	local solvedHandWorld = shoulderWorld + shoulderToHand * armLength
	local armCenterWorld = shoulderWorld + shoulderToHand * (armLength * 0.5)
	local yAxis = -shoulderToHand
	local preferredXAxis = part0.CFrame.RightVector
	if math.abs(preferredXAxis:Dot(yAxis)) > 0.94 then
		preferredXAxis = part0.CFrame.LookVector
	end

	local xAxis = safeUnit(preferredXAxis - yAxis * preferredXAxis:Dot(yAxis), part0.CFrame.RightVector)
	local zAxis = xAxis:Cross(yAxis)
	if zAxis.Magnitude <= 0.001 then
		zAxis = part0.CFrame.BackVector
	else
		zAxis = zAxis.Unit
	end

	local targetArmCFrame = CFrame.fromMatrix(armCenterWorld, xAxis, yAxis, zAxis)
	local rollDegrees = tonumber(rigConfig.ArmRollDegrees)
	if rollDegrees and rollDegrees ~= 0 then
		targetArmCFrame *= CFrame.Angles(0, math.rad(rollDegrees), 0)
	end

	state.LastSolvedHandWorld = solvedHandWorld
	return motor.C0:Inverse() * part0.CFrame:ToObjectSpace(targetArmCFrame) * motor.C1, true
end

local function getJointTargetTransform(state, joint)
	if joint.Mode == JOINT_MODE_ARM_TARGET and state.RigKey == "R6" then
		return getR6ArmTargetTransform(state, joint)
	end

	return joint.TargetTransform, true
end

local function startState(player, character, tool, config)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return nil
	end

	local fruitKey = tool:GetAttribute(TOOL_ATTR_FRUIT_KEY)
	FruitGripController.ApplyToolGrip(tool, fruitKey, {
		Tool = tool,
		Player = player,
		Character = character,
	})

	local joints, rigKey = collectJoints(character, humanoid, config)
	local state = {
		Player = player,
		Character = character,
		Tool = tool,
		FruitKey = fruitKey,
		Humanoid = humanoid,
		RigKey = rigKey,
		Joints = joints,
		Weight = 0,
		LastContext = nil,
		LastActive = nil,
	}

	tool:SetAttribute("FruitHoldPresentationRig", rigKey)
	tool:SetAttribute("FruitHoldPresentationJointCount", #joints)

	if #joints == 0 then
		logWarn("no hold joints fruit=%s player=%s rig=%s", tostring(fruitKey), player.Name, rigKey)
	else
		local jointNames = {}
		for _, joint in ipairs(joints) do
			jointNames[#jointNames + 1] = string.format("%s/%s/%s", joint.Motor.Name, joint.Mode, joint.BlendMode)
		end
		logInfo(
			"start fruit=%s player=%s rig=%s joints=%s grip=%s",
			tostring(fruitKey),
			player.Name,
			rigKey,
			table.concat(jointNames, ","),
			formatCFrame(tool.Grip)
		)
	end

	return state
end

local function shouldSuppressForContext(tool, config)
	local contextName = tool and tool:GetAttribute("FruitGripResolvedContext") or nil
	local disabledContexts = type(config.DisableContexts) == "table" and config.DisableContexts or nil
	return typeof(contextName) == "string" and contextName ~= "" and disabledContexts and disabledContexts[contextName] == true
end

local function updateState(player, character, dt, config)
	local tool = findEquippedFruitTool(character)
	local state = statesByCharacter[character]

	if tool and (not state or state.Tool ~= tool) then
		if state then
			resetStateTransforms(state)
		end
		state = startState(player, character, tool, config)
		statesByCharacter[character] = state
	elseif not tool and not state then
		return
	end

	if not state then
		return
	end

	local toolContext = state.Tool and state.Tool:GetAttribute("FruitGripResolvedContext") or ""
	local active = tool ~= nil
		and state.Tool == tool
		and state.Humanoid
		and state.Humanoid.Parent == character
		and state.Humanoid.Health > 0
		and config.Enabled ~= false
		and not shouldSuppressForContext(state.Tool, config)

	if state.LastContext ~= toolContext or state.LastActive ~= active then
		state.LastContext = toolContext
		state.LastActive = active
		logInfo(
			"state fruit=%s player=%s active=%s context=%s weight=%.2f",
			tostring(state.FruitKey),
			player.Name,
			tostring(active),
			tostring(toolContext == "" and "default" or toolContext),
			state.Weight
		)
	end

	local fadeSpeed = math.max(0.1, tonumber(config.FadeSpeed) or DEFAULT_FADE_SPEED)
	local alpha = 1 - math.exp(-fadeSpeed * math.max(0, dt))
	local targetWeight = active and 1 or 0
	state.Weight += (targetWeight - state.Weight) * alpha

	for _, joint in ipairs(state.Joints) do
		local motor = joint.Motor
		if typeof(motor) == "Instance" and motor.Parent then
			local resolvedTransform, solved = getJointTargetTransform(state, joint)
			if not solved then
				logWarn("falling back to static hold transform fruit=%s player=%s joint=%s", tostring(state.FruitKey), player.Name, motor.Name)
			end

			local targetTransform = CFrame.new():Lerp(resolvedTransform, state.Weight)
			if joint.BlendMode == BLEND_MODE_REPLACE then
				motor.Transform = targetTransform
			else
				motor.Transform = motor.Transform * targetTransform
			end
		end
	end
	emitPoseDebug(state)

	if not active and state.Weight <= CLEANUP_WEIGHT then
		resetStateTransforms(state)
		if state.Tool and state.Tool.Parent then
			state.Tool:SetAttribute("FruitHoldPresentationRig", "")
			state.Tool:SetAttribute("FruitHoldPresentationJointCount", 0)
		end
		statesByCharacter[character] = nil
		logInfo("stop fruit=%s player=%s", tostring(state.FruitKey), player.Name)
	end
end

local function updateAll(dt)
	local config = getConfig()
	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		if character then
			updateState(player, character, dt, config)
		end
	end

	for character, state in pairs(statesByCharacter) do
		if typeof(character) ~= "Instance" or character.Parent == nil then
			resetStateTransforms(state)
			statesByCharacter[character] = nil
		end
	end
end

function FruitHoldPresentation.Start()
	if started then
		return FruitHoldPresentation
	end

	started = true
	local updateSignal
	updateSignal, updateSignalName = getUpdateSignal()
	renderConnection = updateSignal:Connect(updateAll)
	logInfo("started signal=%s", updateSignalName)
	if updateSignalName ~= "PreSimulation" then
		logWarn("using %s fallback; Animator may overwrite hold pose on some rigs", updateSignalName)
	end
	return FruitHoldPresentation
end

function FruitHoldPresentation.Stop()
	if not started then
		return
	end

	started = false
	if renderConnection then
		renderConnection:Disconnect()
		renderConnection = nil
	end

	for character, state in pairs(statesByCharacter) do
		resetStateTransforms(state)
		statesByCharacter[character] = nil
	end
end

return FruitHoldPresentation
