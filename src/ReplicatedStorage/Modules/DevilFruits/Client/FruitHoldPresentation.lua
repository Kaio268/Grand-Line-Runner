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
local R6G_RUNTIME_PROOF_INTERVAL = 0.75
local CLEANUP_WEIGHT = 0.01
local DEFAULT_FADE_SPEED = 14
local REFERENCE_FRUIT_KEY = "Mera"
local BLEND_MODE_ADDITIVE = "Additive"
local BLEND_MODE_REPLACE = "Replace"
local JOINT_MODE_STATIC = "Static"
local JOINT_MODE_ARM_TARGET = "ArmTarget"
local MODEL_VARIANT_R6G = "R6G"
local MODEL_VARIANT_ATTRIBUTE_NAMES = {
	"FruitHoldModelVariant",
	"FruitGripModelVariant",
	"FruitModelVariant",
	"EatAnimationRig",
	"CurrentModelAsset",
}
local EAT_ANIMATION_ACTIVE_ATTRIBUTE = "FruitEatAnimationActive"
local R6G_R6_MOTOR_ALIASES = {
	["Right Shoulder"] = "RightShoulder",
}
local R6G_ARM_TARGET_STATIC_PRESENTATION_JOINTS = {
	["Right Elbow"] = true,
	RightElbow = true,
	["Right Wrist"] = true,
	RightWrist = true,
}

local statesByCharacter = setmetatable({}, { __mode = "k" })
local assetReferenceByRigKey = {}
local visibleOrientationReferenceByFruitKey = {}
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

local function logR6GProof(message, ...)
	if not shouldDebug() then
		return
	end

	local ok, formatted = pcall(string.format, "[R6G HOLD PROOF] " .. tostring(message), ...)
	print(ok and formatted or ("[R6G HOLD PROOF] " .. tostring(message)))
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

local function debugInstancePath(instance)
	if typeof(instance) == "Instance" then
		return instance:GetFullName()
	end

	return "<nil>"
end

local function getSortedMapKeys(map)
	local keys = {}
	if type(map) ~= "table" then
		return keys
	end

	for key in pairs(map) do
		keys[#keys + 1] = tostring(key)
	end
	table.sort(keys)
	return keys
end

local function formatConfigJointEntries(jointConfig)
	local entries = {}
	for _, key in ipairs(getSortedMapKeys(jointConfig)) do
		entries[#entries + 1] = string.format("%s=%s", key, formatCFrame(jointConfig[key]))
	end

	if #entries == 0 then
		return "<none>"
	end

	return table.concat(entries, " | ")
end

local function findConfigJoint(jointConfig, ...)
	if type(jointConfig) ~= "table" then
		return nil
	end

	for index = 1, select("#", ...) do
		local key = select(index, ...)
		local value = jointConfig[key]
		if typeof(value) == "CFrame" then
			return key, value
		end
	end

	return nil
end

local function formatResolvedJointEntries(entries)
	local parts = {}
	for _, entry in ipairs(entries or {}) do
		parts[#parts + 1] = string.format(
			"%s->%s requested=%s final=%s blend=%s hybridStatic=%s target=%s motor=%s",
			tostring(entry.ConfigName),
			tostring(entry.MotorName),
			tostring(entry.RequestedMode),
			tostring(entry.Mode),
			tostring(entry.BlendMode),
			tostring(entry.HybridStatic == true),
			formatCFrame(entry.TargetTransform),
			debugInstancePath(entry.Motor)
		)
	end

	if #parts == 0 then
		return "<none>"
	end

	return table.concat(parts, " | ")
end

local function formatProofNames(entries)
	local parts = {}
	for _, entry in ipairs(entries or {}) do
		parts[#parts + 1] = tostring(entry)
	end

	if #parts == 0 then
		return "<none>"
	end

	return table.concat(parts, ",")
end

local function formatJointCFrame(joint, propertyName)
	local ok, value = pcall(function()
		return joint[propertyName]
	end)

	if ok and typeof(value) == "CFrame" then
		return formatCFrame(value)
	end

	return "<unavailable>"
end

local function getGripPart(character)
	if typeof(character) ~= "Instance" then
		return nil
	end

	return character:FindFirstChild("RightHand")
		or character:FindFirstChild("RightLowerArm")
		or character:FindFirstChild("Right Arm")
end

local function logR6GLiveGripState(source, tool, character)
	if not shouldDebug() or not (tool and tool:IsA("Tool")) then
		return
	end

	local handle = tool:FindFirstChild("Handle")
	local gripPart = getGripPart(character)
	local attachment = gripPart and (gripPart:FindFirstChild("RightGripAttachment") or gripPart:FindFirstChild("RightGrip")) or nil
	local attachmentIsAttachment = attachment and attachment:IsA("Attachment")
	print(string.format(
		"[R6G FRUIT WELD][CLIENT] %s tool=%s parent=%s handle=%s gripPart=%s attachmentExists=%s attachment=%s attachmentClass=%s attachmentCFrame=%s toolGrip=%s manualMode=%s",
		tostring(source),
		tool.Name,
		debugInstancePath(tool.Parent),
		debugInstancePath(handle),
		debugInstancePath(gripPart),
		tostring(attachmentIsAttachment == true),
		attachment and attachment.Name or "",
		attachment and attachment.ClassName or "",
		attachmentIsAttachment and formatCFrame(attachment.CFrame) or "<none>",
		formatCFrame(tool.Grip),
		tostring(tool:GetAttribute("FruitManualGripC0Mode") or "")
	))

	local foundJoint = false
	if typeof(character) == "Instance" then
		for _, descendant in ipairs(character:GetDescendants()) do
			if descendant:IsA("JointInstance") and (descendant.Name == "RightGrip" or descendant.Name == "ManualGrip") then
				foundJoint = true
				print(string.format(
					"[R6G FRUIT WELD][CLIENT] %s joint name=%s class=%s parent=%s part0=%s part1=%s connectedToHandle=%s C0=%s C1=%s",
					tostring(source),
					descendant.Name,
					descendant.ClassName,
					debugInstancePath(descendant.Parent),
					debugInstancePath(descendant.Part0),
					debugInstancePath(descendant.Part1),
					tostring(handle ~= nil and (descendant.Part0 == handle or descendant.Part1 == handle)),
					formatJointCFrame(descendant, "C0"),
					formatJointCFrame(descendant, "C1")
				))
			end
		end
	end

	if not foundJoint then
		print(string.format("[R6G FRUIT WELD][CLIENT] %s joint name=<none>", tostring(source)))
	end
end

local function scheduleR6GLiveGripDebug(state)
	if not state or state.RigKey ~= MODEL_VARIANT_R6G then
		return
	end

	logR6GLiveGripState("client.start", state.Tool, state.Character)
	task.delay(0.25, function()
		if statesByCharacter[state.Character] == state then
			logR6GLiveGripState("client.delay0.25", state.Tool, state.Character)
		end
	end)
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

local function normalizeModelVariant(value)
	if typeof(value) ~= "string" or value == "" then
		return nil
	end

	if string.upper(value) == MODEL_VARIANT_R6G then
		return MODEL_VARIANT_R6G
	end

	return value
end

local function getModelVariant(player, character, humanoid)
	local targets = { character, humanoid, player }
	for _, target in ipairs(targets) do
		if typeof(target) == "Instance" then
			for _, attributeName in ipairs(MODEL_VARIANT_ATTRIBUTE_NAMES) do
				local variant = normalizeModelVariant(target:GetAttribute(attributeName))
				if variant then
					return variant, string.format("%s.%s", debugInstancePath(target), attributeName)
				end
			end
		end
	end

	return nil
end

local function getRigKey(player, character, humanoid)
	local modelVariant, modelVariantSource = getModelVariant(player, character, humanoid)
	if modelVariant == MODEL_VARIANT_R6G then
		return MODEL_VARIANT_R6G, modelVariant, modelVariantSource
	end

	if humanoid and humanoid.RigType == Enum.HumanoidRigType.R6 then
		return "R6", modelVariant, modelVariantSource
	end

	return "R15", modelVariant, modelVariantSource
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

local function getRigPresentationConfig(config, rigKey)
	local rigConfig = type(config[rigKey]) == "table" and config[rigKey] or nil
	if rigKey ~= MODEL_VARIANT_R6G then
		return rigConfig, rigConfig and rigKey or "<missing>"
	end

	local r6Config = type(config.R6) == "table" and config.R6 or nil
	if rigConfig then
		return rigConfig, "R6G"
	end
	if r6Config then
		return r6Config, "R6_fallback"
	end

	return nil, "<missing>"
end

local function collectJoints(player, character, humanoid, config)
	local rigKey, modelVariant, modelVariantSource = getRigKey(player, character, humanoid)
	local rigConfig, rigConfigSource = getRigPresentationConfig(config, rigKey)
	local jointConfig = rigConfig and type(rigConfig.Joints) == "table" and rigConfig.Joints or nil
	local blendMode = normalizeBlendMode(rigConfig and rigConfig.BlendMode or config.BlendMode)
	local jointMode = normalizeJointMode(rigConfig and rigConfig.Mode or config.Mode)
	local joints = {}
	local _, rightShoulderConfig = findConfigJoint(jointConfig, "RightShoulder", "Right Shoulder")
	local _, rightElbowConfig = findConfigJoint(jointConfig, "RightElbow", "Right Elbow")
	local _, rightWristConfig = findConfigJoint(jointConfig, "RightWrist", "Right Wrist")
	local presentationDebug = {
		RigKey = rigKey,
		ModelVariant = modelVariant,
		ModelVariantSource = modelVariantSource,
		ConfigSource = rigConfigSource,
		RawMode = rigConfig and rigConfig.Mode or config.Mode,
		ResolvedMode = jointMode,
		RawBlendMode = rigConfig and rigConfig.BlendMode or config.BlendMode,
		ResolvedBlendMode = blendMode,
		HandTargetLocal = rigConfig and rigConfig.HandTargetLocal,
		ConfigJointStack = formatConfigJointEntries(jointConfig),
		ConfigHasRightShoulder = rightShoulderConfig ~= nil,
		ConfigHasRightElbow = rightElbowConfig ~= nil,
		ConfigHasRightWrist = rightWristConfig ~= nil,
		ResolvedEntries = {},
		MissingEntries = {},
		SkippedEntries = {},
	}

	for motorName, targetTransform in pairs(jointConfig or {}) do
		if typeof(targetTransform) ~= "CFrame" then
			presentationDebug.SkippedEntries[#presentationDebug.SkippedEntries + 1] =
				string.format("%s:non_cframe:%s", tostring(motorName), typeof(targetTransform))
			continue
		end
		local presentationMode = jointMode
		local hybridStatic = false
		if rigKey == MODEL_VARIANT_R6G
			and jointMode == JOINT_MODE_ARM_TARGET
			and R6G_ARM_TARGET_STATIC_PRESENTATION_JOINTS[motorName] then
			presentationMode = JOINT_MODE_STATIC
			hybridStatic = true
		end

		local resolvedMotorName = rigKey == MODEL_VARIANT_R6G and R6G_R6_MOTOR_ALIASES[motorName] or nil
		local motor = findMotor(character, resolvedMotorName or motorName)
		if motor then
			local jointEntry = {
				BlendMode = blendMode,
				ConfigName = tostring(motorName),
				HybridStatic = hybridStatic,
				Mode = presentationMode,
				MotorName = motor.Name,
				RigConfig = rigConfig,
				RequestedMode = jointMode,
				Motor = motor,
				TargetTransform = targetTransform,
			}
			joints[#joints + 1] = jointEntry
			presentationDebug.ResolvedEntries[#presentationDebug.ResolvedEntries + 1] = jointEntry
		else
			presentationDebug.MissingEntries[#presentationDebug.MissingEntries + 1] =
				string.format("%s->%s", tostring(motorName), tostring(resolvedMotorName or motorName))
			logWarn("missing hold joint character=%s rig=%s motor=%s", character.Name, rigKey, tostring(motorName))
		end
	end

	return joints, rigKey, presentationDebug
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

	local boundsMin = Vector3.new(math.huge, math.huge, math.huge)
	local boundsMax = Vector3.new(-math.huge, -math.huge, -math.huge)
	local foundPart = false
	for _, descendant in ipairs(tool:GetDescendants()) do
		if descendant:IsA("BasePart") and descendant.Transparency < 0.98 then
			local halfSize = descendant.Size * 0.5
			for xSign = -1, 1, 2 do
				for ySign = -1, 1, 2 do
					for zSign = -1, 1, 2 do
						local corner = descendant.CFrame:PointToWorldSpace(Vector3.new(
							halfSize.X * xSign,
							halfSize.Y * ySign,
							halfSize.Z * zSign
						))
						boundsMin = Vector3.new(
							math.min(boundsMin.X, corner.X),
							math.min(boundsMin.Y, corner.Y),
							math.min(boundsMin.Z, corner.Z)
						)
						boundsMax = Vector3.new(
							math.max(boundsMax.X, corner.X),
							math.max(boundsMax.Y, corner.Y),
							math.max(boundsMax.Z, corner.Z)
						)
						foundPart = true
					end
				end
			end
		end
	end

	if foundPart then
		return (boundsMin + boundsMax) * 0.5
	end

	local handle = tool:FindFirstChild("Handle")
	if handle and handle:IsA("BasePart") then
		return handle.Position
	end

	return nil
end

local function getVisibleFruitParts(tool)
	local parts = {}
	if typeof(tool) ~= "Instance" then
		return parts
	end

	for _, descendant in ipairs(tool:GetDescendants()) do
		if descendant:IsA("BasePart") and descendant.Transparency < 0.98 then
			table.insert(parts, descendant)
		end
	end

	return parts
end

local function getPrimaryVisibleFruitPart(parts)
	local primaryPart = nil
	local primaryVolume = -math.huge
	for _, part in ipairs(parts) do
		local size = part.Size
		local volume = size.X * size.Y * size.Z
		if volume > primaryVolume then
			primaryPart = part
			primaryVolume = volume
		end
	end

	return primaryPart
end

local function getVisibleFruitHandleBounds(handle, parts)
	local boundsMin = Vector3.new(math.huge, math.huge, math.huge)
	local boundsMax = Vector3.new(-math.huge, -math.huge, -math.huge)
	local foundPart = false

	for _, part in ipairs(parts) do
		local halfSize = part.Size * 0.5
		for xSign = -1, 1, 2 do
			for ySign = -1, 1, 2 do
				for zSign = -1, 1, 2 do
					local worldCorner = part.CFrame:PointToWorldSpace(Vector3.new(
						halfSize.X * xSign,
						halfSize.Y * ySign,
						halfSize.Z * zSign
					))
					local localCorner = handle.CFrame:PointToObjectSpace(worldCorner)
					boundsMin = Vector3.new(
						math.min(boundsMin.X, localCorner.X),
						math.min(boundsMin.Y, localCorner.Y),
						math.min(boundsMin.Z, localCorner.Z)
					)
					boundsMax = Vector3.new(
						math.max(boundsMax.X, localCorner.X),
						math.max(boundsMax.Y, localCorner.Y),
						math.max(boundsMax.Z, localCorner.Z)
					)
					foundPart = true
				end
			end
		end
	end

	if foundPart then
		return (boundsMin + boundsMax) * 0.5, (boundsMax - boundsMin) * 0.5
	end

	return nil
end

local function getToolHandle(tool)
	local handle = tool and tool:FindFirstChild("Handle")
	if handle and handle:IsA("BasePart") then
		return handle
	end

	return nil
end

local function getVisibleOrientationReferenceDelta(fruitKey, rigKey, handleToPrimary, handleToCenter, handleExtents)
	local referenceKey = typeof(fruitKey) == "string" and fruitKey or tostring(fruitKey or "")
	local reference = visibleOrientationReferenceByFruitKey[referenceKey]
	if rigKey ~= MODEL_VARIANT_R6G then
		visibleOrientationReferenceByFruitKey[referenceKey] = {
			HandleToPrimary = handleToPrimary,
			HandleToCenter = handleToCenter,
			HandleExtents = handleExtents,
			RigKey = rigKey,
		}

		return "stored-default", CFrame.new(), Vector3.new(), Vector3.new(), rigKey, referenceKey
	end

	if not reference then
		return "missing-default", nil, nil, nil, nil, referenceKey
	end

	return "ready",
		reference.HandleToPrimary:ToObjectSpace(handleToPrimary),
		handleToCenter - reference.HandleToCenter,
		handleExtents - reference.HandleExtents,
		reference.RigKey,
		referenceKey
end

local function getFruitCompareLabel(referenceState, rigKey)
	if referenceState == "stored-default" then
		return "[FRUIT COMPARE][DEFAULT_REF]"
	end

	if rigKey == MODEL_VARIANT_R6G and referenceState == "ready" then
		return "[FRUIT COMPARE][R6G_COMPARE]"
	end

	return nil
end

local function getVisibleDifferenceState(referenceState, handleToPrimaryDelta, handleToCenterDelta, handleExtentsDelta)
	if referenceState == "stored-default" then
		return "reference"
	end

	if referenceState ~= "ready"
		or typeof(handleToPrimaryDelta) ~= "CFrame"
		or typeof(handleToCenterDelta) ~= "Vector3"
		or typeof(handleExtentsDelta) ~= "Vector3" then
		return "unknown"
	end

	local x, y, z = handleToPrimaryDelta:ToOrientation()
	local maxRotationDelta = math.max(math.abs(math.deg(x)), math.abs(math.deg(y)), math.abs(math.deg(z)))
	local differs = handleToPrimaryDelta.Position.Magnitude > 0.01
		or handleToCenterDelta.Magnitude > 0.01
		or handleExtentsDelta.Magnitude > 0.01
		or maxRotationDelta > 1

	return tostring(differs)
end

local function logVisibleFruitOrientation(source, state)
	if not shouldDebug() or not state or not state.Tool then
		return
	end

	local handle = getToolHandle(state.Tool)
	if not handle then
		print(string.format(
			"[FRUIT VISIBLE] %s fruit=%s player=%s rig=%s reason=missing_handle",
			tostring(source),
			tostring(state.FruitKey),
			state.Player and state.Player.Name or "?",
			tostring(state.RigKey)
		))
		return
	end

	local visibleParts = getVisibleFruitParts(state.Tool)
	local primaryPart = getPrimaryVisibleFruitPart(visibleParts)
	local handleToCenter, handleExtents = getVisibleFruitHandleBounds(handle, visibleParts)
	if not primaryPart or typeof(handleToCenter) ~= "Vector3" or typeof(handleExtents) ~= "Vector3" then
		print(string.format(
			"[FRUIT VISIBLE] %s fruit=%s player=%s rig=%s reason=missing_visible_geometry visibleParts=%d handle=%s handleCFrame=%s",
			tostring(source),
			tostring(state.FruitKey),
			state.Player and state.Player.Name or "?",
			tostring(state.RigKey),
			#visibleParts,
			debugInstancePath(handle),
			formatCFrame(handle.CFrame)
		))
		return
	end

	local handleToPrimary = handle.CFrame:ToObjectSpace(primaryPart.CFrame)
	local centerWorld = handle.CFrame:PointToWorldSpace(handleToCenter)
	local referenceState, handleToPrimaryDelta, handleToCenterDelta, handleExtentsDelta, referenceRigKey, referenceKey = getVisibleOrientationReferenceDelta(
		state.FruitKey,
		state.RigKey,
		handleToPrimary,
		handleToCenter,
		handleExtents
	)

	print(string.format(
		"[FRUIT VISIBLE] %s fruit=%s player=%s rig=%s visibleParts=%d primary=%s primarySize=%s handle=%s handleCFrame=%s primaryCFrame=%s handleToPrimary=%s centerWorld=%s handleToCenter=%s handleExtents=%s compareKey=%s compareRef=%s referenceRig=%s deltaHandleToPrimary=%s deltaHandleToCenter=%s deltaHandleExtents=%s toolGrip=%s manualMode=%s",
		tostring(source),
		tostring(state.FruitKey),
		state.Player and state.Player.Name or "?",
		tostring(state.RigKey),
		#visibleParts,
		debugInstancePath(primaryPart),
		formatVector3(primaryPart.Size),
		debugInstancePath(handle),
		formatCFrame(handle.CFrame),
		formatCFrame(primaryPart.CFrame),
		formatCFrame(handleToPrimary),
		formatVector3(centerWorld),
		formatVector3(handleToCenter),
		formatVector3(handleExtents),
		tostring(referenceKey or "<missing>"),
		referenceState,
		tostring(referenceRigKey or ""),
		handleToPrimaryDelta and formatCFrame(handleToPrimaryDelta) or "<equip default first>",
		handleToCenterDelta and formatVector3(handleToCenterDelta) or "<equip default first>",
		handleExtentsDelta and formatVector3(handleExtentsDelta) or "<equip default first>",
		formatCFrame(state.Tool.Grip),
		tostring(state.Tool:GetAttribute("FruitManualGripC0Mode") or "")
	))

	local compareLabel = getFruitCompareLabel(referenceState, state.RigKey)
	local manualMode = tostring(state.Tool:GetAttribute("FruitManualGripC0Mode") or "")
	if compareLabel then
		print(string.format(
			"%s source=%s fruit=%s rig=%s compareKey=%s compareRef=%s handleToPrimary=%s handleToCenter=%s handleExtents=%s toolGrip=%s manualMode=%s",
			compareLabel,
			tostring(source),
			tostring(state.FruitKey),
			tostring(state.RigKey),
			tostring(referenceKey or "<missing>"),
			referenceState,
			formatCFrame(handleToPrimary),
			formatVector3(handleToCenter),
			formatVector3(handleExtents),
			formatCFrame(state.Tool.Grip),
			manualMode
		))
	end

	if compareLabel or state.RigKey == MODEL_VARIANT_R6G then
		print(string.format(
			"[FRUIT COMPARE][SUMMARY] source=%s fruit=%s defaultRig=%s currentRig=%s compareKey=%s compareRef=%s handleToPrimary=%s handleToCenter=%s handleExtents=%s visibleDiffers=%s toolGrip=%s manualMode=%s",
			tostring(source),
			tostring(state.FruitKey),
			tostring(referenceRigKey or "<missing>"),
			tostring(state.RigKey),
			tostring(referenceKey or "<missing>"),
			referenceState,
			formatCFrame(handleToPrimary),
			formatVector3(handleToCenter),
			formatVector3(handleExtents),
			getVisibleDifferenceState(referenceState, handleToPrimaryDelta, handleToCenterDelta, handleExtentsDelta),
			formatCFrame(state.Tool.Grip),
			manualMode
		))
	end
end

local function scheduleVisibleFruitOrientationDebug(state)
	if not state then
		return
	end

	logVisibleFruitOrientation("client.start", state)
	task.delay(0.25, function()
		if statesByCharacter[state.Character] == state then
			logVisibleFruitOrientation("client.delay0.25", state)
		end
	end)
end

local function getAssetReferenceDelta(rigKey, fruitKey, handleLocal, handleLocalCFrame, fruitCenterLocal, fruitMinusHandLocal, fruitMinusHandleLocal, assetMinusHandleLocal)
	local reference = assetReferenceByRigKey[rigKey]
	if fruitKey == REFERENCE_FRUIT_KEY then
		assetReferenceByRigKey[rigKey] = {
			HandleLocal = handleLocal,
			HandleLocalCFrame = handleLocalCFrame,
			FruitCenterLocal = fruitCenterLocal,
			FruitMinusHandLocal = fruitMinusHandLocal,
			FruitMinusHandleLocal = fruitMinusHandleLocal,
			AssetMinusHandleLocal = assetMinusHandleLocal,
		}

		return "stored", Vector3.new(), CFrame.new(), Vector3.new(), Vector3.new(), Vector3.new(), Vector3.new()
	end

	if not reference then
		return "missing", nil, nil, nil, nil, nil, nil
	end

	return "ready",
		handleLocal - reference.HandleLocal,
		reference.HandleLocalCFrame:ToObjectSpace(handleLocalCFrame),
		fruitCenterLocal - reference.FruitCenterLocal,
		fruitMinusHandLocal - reference.FruitMinusHandLocal,
		fruitMinusHandleLocal - reference.FruitMinusHandleLocal,
		assetMinusHandleLocal - reference.AssetMinusHandleLocal
end

local function getPresentationHandWorld(state)
	if typeof(state.LastSolvedHandWorld) == "Vector3" then
		return state.LastSolvedHandWorld
	end

	if not state or state.RigKey ~= MODEL_VARIANT_R6G then
		return nil
	end

	local gripPart = getGripPart(state.Character)
	if not (gripPart and gripPart:IsA("BasePart")) then
		return nil
	end

	local attachment = gripPart:FindFirstChild("RightGripAttachment")
		or gripPart:FindFirstChild("RightGrip")
	if attachment and attachment:IsA("Attachment") then
		return attachment.WorldCFrame.Position
	end

	return gripPart.Position
end

local function emitPoseDebug(state)
	if not shouldDebug() then
		return
	end

	if not state or (state.RigKey ~= "R6" and state.RigKey ~= MODEL_VARIANT_R6G) then
		return
	end

	local handWorld = getPresentationHandWorld(state)
	if typeof(handWorld) ~= "Vector3" then
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

	local handle = getToolHandle(state.Tool)
	if not handle then
		return
	end

	local handLocal = torso.CFrame:PointToObjectSpace(handWorld)
	local desiredHandLocal = typeof(state.LastDesiredHandWorld) == "Vector3"
		and torso.CFrame:PointToObjectSpace(state.LastDesiredHandWorld)
		or handLocal
	local solvedMinusDesiredLocal = handLocal - desiredHandLocal
	local handleLocal = torso.CFrame:PointToObjectSpace(handle.Position)
	local handleLocalCFrame = torso.CFrame:ToObjectSpace(handle.CFrame)
	local fruitCenterLocal = torso.CFrame:PointToObjectSpace(fruitCenter)
	local fruitMinusHandLocal = torso.CFrame:VectorToObjectSpace(fruitCenter - handWorld)
	local fruitMinusHandleLocal = torso.CFrame:VectorToObjectSpace(fruitCenter - handle.Position)
	local assetMinusHandleLocal = handle.CFrame:PointToObjectSpace(fruitCenter)
	local referenceState, handleDelta, handleCFrameDelta, fruitCenterDelta, fruitMinusHandDelta, fruitMinusHandleDelta, assetMinusHandleDelta = getAssetReferenceDelta(
		state.RigKey,
		state.FruitKey,
		handleLocal,
		handleLocalCFrame,
		fruitCenterLocal,
		fruitMinusHandLocal,
		fruitMinusHandleLocal,
		assetMinusHandleLocal
	)

	if state.Tool and state.Tool.Parent then
		state.Tool:SetAttribute("FruitHoldSolvedHandLocal", handLocal)
		state.Tool:SetAttribute("FruitHoldDesiredHandLocal", desiredHandLocal)
		state.Tool:SetAttribute("FruitHoldSolvedMinusDesiredLocal", solvedMinusDesiredLocal)
		state.Tool:SetAttribute("FruitHoldHandleLocal", handleLocal)
		state.Tool:SetAttribute("FruitHoldHandleLocalCFrame", handleLocalCFrame)
		state.Tool:SetAttribute("FruitHoldCenterLocal", fruitCenterLocal)
		state.Tool:SetAttribute("FruitHoldCenterMinusHandLocal", fruitMinusHandLocal)
		state.Tool:SetAttribute("FruitHoldCenterMinusHandleLocal", fruitMinusHandleLocal)
		state.Tool:SetAttribute("FruitHoldAssetCenterMinusHandleLocal", assetMinusHandleLocal)
		state.Tool:SetAttribute("FruitHoldMeraReferenceState", referenceState)
		if handleDelta then
			state.Tool:SetAttribute("FruitHoldMeraDeltaHandleLocal", handleDelta)
		end
		if handleCFrameDelta then
			state.Tool:SetAttribute("FruitHoldMeraDeltaHandleLocalCFrame", handleCFrameDelta)
		end
		if fruitCenterDelta then
			state.Tool:SetAttribute("FruitHoldMeraDeltaCenterLocal", fruitCenterDelta)
		end
		if fruitMinusHandDelta then
			state.Tool:SetAttribute("FruitHoldMeraDeltaMinusHandLocal", fruitMinusHandDelta)
		end
		if fruitMinusHandleDelta then
			state.Tool:SetAttribute("FruitHoldMeraDeltaMinusHandleLocal", fruitMinusHandleDelta)
		end
		if assetMinusHandleDelta then
			state.Tool:SetAttribute("FruitHoldMeraDeltaAssetMinusHandleLocal", assetMinusHandleDelta)
		end
	end

	logInfo(
		"asset fruit=%s player=%s rig=%s reference=%s handTarget=%s desiredHandLocal=%s handLocal=%s solvedMinusDesired=%s handleLocal=%s handleCFrame=%s fruitCenterLocal=%s fruitMinusHand=%s fruitMinusHandle=%s assetMinusHandle=%s deltaHandle=%s deltaHandleCFrame=%s deltaCenter=%s deltaMinusHand=%s deltaMinusHandle=%s deltaAssetMinusHandle=%s grip=%s",
		tostring(state.FruitKey),
		state.Player and state.Player.Name or "?",
		tostring(state.RigKey),
		referenceState,
		formatVector3(state.LastArmTargetLocal),
		formatVector3(desiredHandLocal),
		formatVector3(handLocal),
		formatVector3(solvedMinusDesiredLocal),
		formatVector3(handleLocal),
		formatCFrame(handleLocalCFrame),
		formatVector3(fruitCenterLocal),
		formatVector3(fruitMinusHandLocal),
		formatVector3(fruitMinusHandleLocal),
		formatVector3(assetMinusHandleLocal),
		handleDelta and formatVector3(handleDelta) or "<equip Mera first>",
		handleCFrameDelta and formatCFrame(handleCFrameDelta) or "<equip Mera first>",
		fruitCenterDelta and formatVector3(fruitCenterDelta) or "<equip Mera first>",
		fruitMinusHandDelta and formatVector3(fruitMinusHandDelta) or "<equip Mera first>",
		fruitMinusHandleDelta and formatVector3(fruitMinusHandleDelta) or "<equip Mera first>",
		assetMinusHandleDelta and formatVector3(assetMinusHandleDelta) or "<equip Mera first>",
		formatCFrame(state.Tool and state.Tool.Grip)
	)
end

local function getArmTargetTransform(state, joint)
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
	local reachScale = tonumber(rigConfig.ArmTargetReachScale) or 1
	local reachOffset = tonumber(rigConfig.ArmTargetReachOffset) or 0
	local reachDistance = math.max(0.05, armLength * reachScale + reachOffset)
	local armTargetOffsetLocal = rigConfig.ArmTargetOffsetLocal
	local armTargetOffsetWorld = typeof(armTargetOffsetLocal) == "Vector3"
		and part0.CFrame:VectorToWorldSpace(armTargetOffsetLocal)
		or Vector3.zero
	local shoulderToHand = safeUnit(desiredHandWorld - shoulderWorld, -part0.CFrame.LookVector)
	local solvedHandWorld = shoulderWorld + shoulderToHand * reachDistance + armTargetOffsetWorld
	local armCenterWorld = shoulderWorld + shoulderToHand * (reachDistance * 0.5) + armTargetOffsetWorld
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
	state.LastDesiredHandWorld = desiredHandWorld
	state.LastArmTargetLocal = handTargetLocal
	return motor.C0:Inverse() * part0.CFrame:ToObjectSpace(targetArmCFrame) * motor.C1, true
end

local function getJointTargetTransform(state, joint)
	if joint.Mode == JOINT_MODE_ARM_TARGET then
		return getArmTargetTransform(state, joint)
	end

	return joint.TargetTransform, true
end

local function hasResolvedJoint(entries, motorName)
	for _, entry in ipairs(entries or {}) do
		if entry.MotorName == motorName then
			return true
		end
	end

	return false
end

local function formatAppliedJointEntries(entries)
	local parts = {}
	for _, entry in ipairs(entries or {}) do
		parts[#parts + 1] = string.format(
			"%s/%s requested=%s final=%s blend=%s solved=%s weight=%.2f resolved=%s applied=%s motorNow=%s",
			tostring(entry.ConfigName),
			tostring(entry.MotorName),
			tostring(entry.RequestedMode),
			tostring(entry.Mode),
			tostring(entry.BlendMode),
			tostring(entry.Solved),
			tonumber(entry.Weight) or 0,
			formatCFrame(entry.ResolvedTransform),
			formatCFrame(entry.AppliedTransform),
			formatCFrame(entry.MotorTransform)
		)
	end

	if #parts == 0 then
		return "<none>"
	end

	return table.concat(parts, " | ")
end

local function logR6GResolvedPresentation(state, source)
	if not state or state.RigKey ~= MODEL_VARIANT_R6G then
		return
	end

	local debugState = state.PresentationDebug
	if type(debugState) ~= "table" then
		logR6GProof(
			"resolved source=%s fruit=%s player=%s rig=%s reason=missing_debug_state",
			tostring(source),
			tostring(state.FruitKey),
			state.Player and state.Player.Name or "?",
			tostring(state.RigKey)
		)
		return
	end

	local finalStack = formatResolvedJointEntries(debugState.ResolvedEntries)
	local hasRightElbow = hasResolvedJoint(debugState.ResolvedEntries, "RightElbow")
	if state.Tool and state.Tool.Parent then
		state.Tool:SetAttribute("FruitHoldR6GModelVariantSource", tostring(debugState.ModelVariantSource or ""))
		state.Tool:SetAttribute("FruitHoldR6GConfigSource", tostring(debugState.ConfigSource or ""))
		state.Tool:SetAttribute("FruitHoldR6GConfigMode", tostring(debugState.ResolvedMode or ""))
		state.Tool:SetAttribute("FruitHoldR6GConfigBlendMode", tostring(debugState.ResolvedBlendMode or ""))
		state.Tool:SetAttribute("FruitHoldR6GConfigJointStack", tostring(debugState.ConfigJointStack or ""))
		state.Tool:SetAttribute("FruitHoldR6GConfigHasRightElbow", debugState.ConfigHasRightElbow == true)
		state.Tool:SetAttribute("FruitHoldR6GFinalHasRightElbow", hasRightElbow)
		state.Tool:SetAttribute("FruitHoldR6GFinalJointStack", finalStack)
		state.Tool:SetAttribute("FruitHoldR6GMissingJoints", formatProofNames(debugState.MissingEntries))
		state.Tool:SetAttribute("FruitHoldR6GSkippedJoints", formatProofNames(debugState.SkippedEntries))
	end

	logR6GProof(
		"resolved source=%s fruit=%s player=%s rig=%s modelVariant=%s modelSource=%s configSource=%s merged=false rawMode=%s resolvedMode=%s rawBlend=%s resolvedBlend=%s handTarget=%s configHasRightShoulder=%s configHasRightElbow=%s configHasRightWrist=%s finalHasRightElbow=%s configJoints=%s finalStack=%s missing=%s skipped=%s",
		tostring(source),
		tostring(state.FruitKey),
		state.Player and state.Player.Name or "?",
		tostring(state.RigKey),
		tostring(debugState.ModelVariant or ""),
		tostring(debugState.ModelVariantSource or ""),
		tostring(debugState.ConfigSource or ""),
		tostring(debugState.RawMode or ""),
		tostring(debugState.ResolvedMode or ""),
		tostring(debugState.RawBlendMode or ""),
		tostring(debugState.ResolvedBlendMode or ""),
		formatVector3(debugState.HandTargetLocal),
		tostring(debugState.ConfigHasRightShoulder == true),
		tostring(debugState.ConfigHasRightElbow == true),
		tostring(debugState.ConfigHasRightWrist == true),
		tostring(hasRightElbow),
		tostring(debugState.ConfigJointStack or ""),
		finalStack,
		formatProofNames(debugState.MissingEntries),
		formatProofNames(debugState.SkippedEntries)
	)
end

local function scheduleR6GResolvedPresentationDebug(state)
	if not state or state.RigKey ~= MODEL_VARIANT_R6G then
		return
	end

	logR6GResolvedPresentation(state, "client.start")
	task.delay(0.25, function()
		if statesByCharacter[state.Character] == state then
			logR6GResolvedPresentation(state, "client.delay0.25")
		end
	end)
end

local function emitR6GAppliedJointProof(state, active)
	if not shouldDebug() or not state or state.RigKey ~= MODEL_VARIANT_R6G then
		return
	end

	local now = os.clock()
	if state.LastR6GProofAt and (now - state.LastR6GProofAt) < R6G_RUNTIME_PROOF_INTERVAL then
		return
	end
	state.LastR6GProofAt = now

	local entries = state.LastAppliedJointEntries or {}
	local appliedStack = formatAppliedJointEntries(entries)
	local hasRightElbow = false
	for _, entry in ipairs(entries) do
		if entry.MotorName == "RightElbow" then
			hasRightElbow = true
			break
		end
	end

	if state.Tool and state.Tool.Parent then
		state.Tool:SetAttribute("FruitHoldR6GAppliedHasRightElbow", hasRightElbow)
		state.Tool:SetAttribute("FruitHoldR6GAppliedJointStack", appliedStack)
	end

	logR6GProof(
		"applied source=%s fruit=%s player=%s active=%s weight=%.2f hasRightElbow=%s jointCount=%d stack=%s",
		updateSignalName,
		tostring(state.FruitKey),
		state.Player and state.Player.Name or "?",
		tostring(active),
		tonumber(state.Weight) or 0,
		tostring(hasRightElbow),
		#entries,
		appliedStack
	)

	task.spawn(function()
		RunService.RenderStepped:Wait()
		if statesByCharacter[state.Character] ~= state then
			return
		end

		local postEntries = {}
		for _, entry in ipairs(entries) do
			local motor = entry.Motor
			if typeof(motor) == "Instance" and motor.Parent then
				postEntries[#postEntries + 1] = string.format(
					"%s/%s sameAsApplied=%s expected=%s current=%s",
					tostring(entry.ConfigName),
					tostring(entry.MotorName),
					tostring(motor.Transform == entry.AppliedTransform),
					formatCFrame(entry.AppliedTransform),
					formatCFrame(motor.Transform)
				)
			else
				postEntries[#postEntries + 1] = string.format(
					"%s/%s missing_motor_after_apply",
					tostring(entry.ConfigName),
					tostring(entry.MotorName)
				)
			end
		end

		logR6GProof(
			"postRender source=RenderStepped fruit=%s player=%s stack=%s",
			tostring(state.FruitKey),
			state.Player and state.Player.Name or "?",
			#postEntries > 0 and table.concat(postEntries, " | ") or "<none>"
		)
	end)
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

	local joints, rigKey, presentationDebug = collectJoints(player, character, humanoid, config)
	local state = {
		Player = player,
		Character = character,
		Tool = tool,
		FruitKey = fruitKey,
		Humanoid = humanoid,
		RigKey = rigKey,
		Joints = joints,
		PresentationDebug = presentationDebug,
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

	scheduleR6GLiveGripDebug(state)
	scheduleR6GResolvedPresentationDebug(state)
	scheduleVisibleFruitOrientationDebug(state)
	return state
end

local function shouldSuppressForContext(tool, config)
	if tool and tool:GetAttribute(EAT_ANIMATION_ACTIVE_ATTRIBUTE) == true then
		return true
	end

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
	local suppressed = shouldSuppressForContext(state.Tool, config)
	local active = tool ~= nil
		and state.Tool == tool
		and state.Humanoid
		and state.Humanoid.Parent == character
		and state.Humanoid.Health > 0
		and config.Enabled ~= false
		and not suppressed

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

	if suppressed then
		if state.Weight > CLEANUP_WEIGHT then
			resetStateTransforms(state)
		end
		state.Weight = 0
		state.LastAppliedJointEntries = nil
		return
	end

	local fadeSpeed = math.max(0.1, tonumber(config.FadeSpeed) or DEFAULT_FADE_SPEED)
	local alpha = 1 - math.exp(-fadeSpeed * math.max(0, dt))
	local targetWeight = active and 1 or 0
	state.Weight += (targetWeight - state.Weight) * alpha

	local appliedJointEntries = state.RigKey == MODEL_VARIANT_R6G and {} or nil
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
			if appliedJointEntries then
				appliedJointEntries[#appliedJointEntries + 1] = {
					BlendMode = joint.BlendMode,
					ConfigName = joint.ConfigName,
					Mode = joint.Mode,
					Motor = motor,
					MotorName = motor.Name,
					MotorTransform = motor.Transform,
					RequestedMode = joint.RequestedMode,
					ResolvedTransform = resolvedTransform,
					AppliedTransform = targetTransform,
					Solved = solved,
					Weight = state.Weight,
				}
			end
		end
	end
	if appliedJointEntries then
		state.LastAppliedJointEntries = appliedJointEntries
		emitR6GAppliedJointProof(state, active)
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
