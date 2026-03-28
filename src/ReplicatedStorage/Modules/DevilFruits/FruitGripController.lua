local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DevilFruitConfig = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("DevilFruits"))
local DiagnosticLogLimiter = require(script.Parent:WaitForChild("DiagnosticLogLimiter"))

local FruitGripController = {}

local DEBUG_LOGS = RunService:IsStudio()
local WARN_COOLDOWN = 3
local DEFAULT_PROFILE = {
	AssetGripBias = Vector3.new(0.72, -0.12, 0.18),
	AssetGripOffset = Vector3.new(),
	RuntimeGrip = CFrame.new(),
	Contexts = {},
}
local MODEL_VARIANT_ATTRIBUTE_PATTERNS = {
	"FruitGripModelVariant",
	"FruitModelVariant",
	"%sGripModelVariant",
	"%sModelVariant",
}
local contextStackByTool = setmetatable({}, { __mode = "k" })
local lastGripSignatureByTool = setmetatable({}, { __mode = "k" })

local function logInfo(message, ...)
	if not DEBUG_LOGS then
		return
	end

	print(string.format("[FRUIT GRIP] " .. message, ...))
end

local function logWarn(message, ...)
	if not DiagnosticLogLimiter.ShouldEmit("FruitGripController:WARN", DiagnosticLogLimiter.BuildKey(message, ...), WARN_COOLDOWN) then
		return
	end

	warn(string.format("[FRUIT GRIP][WARN] " .. message, ...))
end

local function shallowCopy(source)
	local clone = {}
	for key, value in pairs(source or {}) do
		clone[key] = value
	end
	return clone
end

local function mergeOptions(base, extra)
	local merged = shallowCopy(base)
	for key, value in pairs(extra or {}) do
		merged[key] = value
	end
	return merged
end

local function formatVector3(value)
	if typeof(value) ~= "Vector3" then
		return tostring(value)
	end

	return string.format("(%.2f, %.2f, %.2f)", value.X, value.Y, value.Z)
end

local function formatCFrame(value)
	if typeof(value) ~= "CFrame" then
		return tostring(value)
	end

	local x, y, z = value:ToOrientation()
	return string.format(
		"pos=%s rot=(%.1f, %.1f, %.1f)",
		formatVector3(value.Position),
		math.deg(x),
		math.deg(y),
		math.deg(z)
	)
end

local function resolveFruit(fruitIdentifier, tool)
	local identifier = fruitIdentifier
	if identifier == nil and tool and tool:IsA("Tool") then
		identifier = tool:GetAttribute("FruitKey")
	end

	if typeof(identifier) ~= "string" or identifier == "" then
		return nil
	end

	return DevilFruitConfig.GetFruit(identifier)
end

local function normalizeContextName(value)
	if typeof(value) ~= "string" or value == "" then
		return nil
	end

	return value
end

local function normalizeModelVariant(value)
	if typeof(value) ~= "string" or value == "" then
		return nil
	end

	return value
end

local function resolveModelVariantFromInstance(instance, fruitKey)
	if not instance then
		return nil
	end

	for _, pattern in ipairs(MODEL_VARIANT_ATTRIBUTE_PATTERNS) do
		local attributeName = string.find(pattern, "%s", 1, true) and string.format(pattern, fruitKey) or pattern
		local value = normalizeModelVariant(instance:GetAttribute(attributeName))
		if value then
			return value, attributeName
		end
	end

	local currentModelAsset = normalizeModelVariant(instance:GetAttribute("CurrentModelAsset"))
	if currentModelAsset then
		return currentModelAsset, "CurrentModelAsset"
	end

	return nil
end

local function getActiveContextName(tool, options)
	local explicitContext = normalizeContextName(options and options.ContextName)
	if explicitContext then
		return explicitContext
	end

	local stack = tool and contextStackByTool[tool] or nil
	if stack and #stack > 0 then
		return stack[#stack].ContextName
	end

	return nil
end

local function mergeProfile(target, overrideProfile, sourceLabel)
	if type(overrideProfile) ~= "table" then
		return
	end

	if typeof(overrideProfile.AssetGripBias) == "Vector3" then
		target.AssetGripBias = overrideProfile.AssetGripBias
	end

	if typeof(overrideProfile.AssetGripOffset) == "Vector3" then
		target.AssetGripOffset = overrideProfile.AssetGripOffset
	end

	if typeof(overrideProfile.RuntimeGrip) == "CFrame" then
		target.RuntimeGrip = overrideProfile.RuntimeGrip
	end

	if sourceLabel then
		target.Sources[#target.Sources + 1] = sourceLabel
	end
end

function FruitGripController.ResolveProfile(fruitIdentifier, options)
	options = options or {}
	local tool = options.Tool
	local fruit = resolveFruit(fruitIdentifier, tool)
	if not fruit then
		return nil
	end

	local player = options.Player
	local character = options.Character or (player and player.Character) or nil
	local modelVariant = normalizeModelVariant(options.ModelVariant)
	local variantSource = modelVariant and "explicit" or nil

	if not modelVariant then
		local variantValue, source = resolveModelVariantFromInstance(tool, fruit.FruitKey)
		modelVariant, variantSource = variantValue, source
	end

	if not modelVariant then
		local variantValue, source = resolveModelVariantFromInstance(character, fruit.FruitKey)
		modelVariant, variantSource = variantValue, source
	end

	if not modelVariant then
		local variantValue, source = resolveModelVariantFromInstance(player, fruit.FruitKey)
		modelVariant, variantSource = variantValue, source
	end

	local contextName = getActiveContextName(tool, options)
	local profile = {
		Fruit = fruit,
		ModelVariant = modelVariant,
		ModelVariantSource = variantSource,
		ContextName = contextName,
		AssetGripBias = DEFAULT_PROFILE.AssetGripBias,
		AssetGripOffset = DEFAULT_PROFILE.AssetGripOffset,
		RuntimeGrip = DEFAULT_PROFILE.RuntimeGrip,
		Sources = { "default" },
	}

	local globalGripDefaults = type(DevilFruitConfig.GripDefaults) == "table" and DevilFruitConfig.GripDefaults or nil
	if globalGripDefaults then
		mergeProfile(profile, globalGripDefaults, "global_default")
	end

	local globalModelProfile = modelVariant and globalGripDefaults and type(globalGripDefaults.Models) == "table"
		and globalGripDefaults.Models[modelVariant]
		or nil
	if globalModelProfile then
		mergeProfile(profile, globalModelProfile, "global_model:" .. tostring(modelVariant))
	end

	mergeProfile(profile, {
		AssetGripBias = fruit.ToolGripBias,
		AssetGripOffset = fruit.ToolGripOffset,
	}, "fruit_legacy")

	local defaultContextProfile = contextName and type(DEFAULT_PROFILE.Contexts) == "table" and DEFAULT_PROFILE.Contexts[contextName] or nil
	if defaultContextProfile then
		mergeProfile(profile, defaultContextProfile, "default_context:" .. tostring(contextName))
	end

	local globalContextProfile = contextName and globalGripDefaults and type(globalGripDefaults.Contexts) == "table" and globalGripDefaults.Contexts[contextName] or nil
	if globalContextProfile then
		mergeProfile(profile, globalContextProfile, "global_context:" .. tostring(contextName))
	end

	local gripProfiles = type(fruit.GripProfiles) == "table" and fruit.GripProfiles or nil
	if gripProfiles then
		mergeProfile(profile, gripProfiles.Default, "fruit_default")

		local modelProfile = modelVariant and type(gripProfiles.Models) == "table" and gripProfiles.Models[modelVariant] or nil
		if modelProfile then
			mergeProfile(profile, modelProfile, "model:" .. tostring(modelVariant))
		end

		local contextProfile = contextName and type(gripProfiles.Contexts) == "table" and gripProfiles.Contexts[contextName] or nil
		if contextProfile then
			mergeProfile(profile, contextProfile, "context:" .. tostring(contextName))
		end

		if globalModelProfile and contextName and type(globalModelProfile.Contexts) == "table" then
			mergeProfile(profile, globalModelProfile.Contexts[contextName], "global_model_context:" .. tostring(modelVariant) .. ":" .. tostring(contextName))
		end

		if modelProfile and contextName and type(modelProfile.Contexts) == "table" then
			mergeProfile(profile, modelProfile.Contexts[contextName], "model_context:" .. tostring(modelVariant) .. ":" .. tostring(contextName))
		end
	end

	return profile
end

function FruitGripController.GetBuildGripSettings(fruitIdentifier, options)
	local profile = FruitGripController.ResolveProfile(fruitIdentifier, options)
	if not profile then
		return {
			AssetGripBias = DEFAULT_PROFILE.AssetGripBias,
			AssetGripOffset = DEFAULT_PROFILE.AssetGripOffset,
			RuntimeGrip = DEFAULT_PROFILE.RuntimeGrip,
			Sources = { "default_fallback" },
		}
	end

	return profile
end

function FruitGripController.ApplyToolGrip(tool, fruitIdentifier, options)
	options = options or {}
	if not tool or not tool:IsA("Tool") then
		logWarn("apply skipped invalid tool")
		return false
	end

	local profile = FruitGripController.ResolveProfile(fruitIdentifier, mergeOptions(options, { Tool = tool }))
	if not profile then
		logWarn("apply skipped unknown fruit=%s", tostring(fruitIdentifier))
		return false
	end

	tool.Grip = profile.RuntimeGrip
	tool:SetAttribute("FruitGripResolvedContext", profile.ContextName or "")
	tool:SetAttribute("FruitGripResolvedModelVariant", profile.ModelVariant or "")

	local signature = table.concat({
		tostring(profile.Fruit.FruitKey),
		tostring(profile.ModelVariant or "default"),
		tostring(profile.ContextName or "default"),
		formatCFrame(profile.RuntimeGrip),
		table.concat(profile.Sources, " -> "),
	}, "|")
	if lastGripSignatureByTool[tool] ~= signature then
		lastGripSignatureByTool[tool] = signature
		logInfo(
			"selected fruit=%s model=%s context=%s finalRuntimeGrip=%s sources=%s",
			profile.Fruit.FruitKey,
			tostring(profile.ModelVariant or "default"),
			tostring(profile.ContextName or "default"),
			formatCFrame(profile.RuntimeGrip),
			table.concat(profile.Sources, " -> ")
		)
	end
	return true
end

function FruitGripController.PushContext(tool, fruitIdentifier, contextName, options)
	if not tool or not tool:IsA("Tool") then
		return false
	end

	local normalizedContext = normalizeContextName(contextName)
	if not normalizedContext then
		return false
	end

	local stack = contextStackByTool[tool]
	if not stack then
		stack = {}
		contextStackByTool[tool] = stack
	end

	stack[#stack + 1] = {
		ContextName = normalizedContext,
		Options = shallowCopy(options or {}),
	}

	logInfo(
		"context push fruit=%s context=%s depth=%d",
		tostring(fruitIdentifier or tool:GetAttribute("FruitKey") or "?"),
		normalizedContext,
		#stack
	)

	FruitGripController.ApplyToolGrip(tool, fruitIdentifier, mergeOptions(options, {
		Tool = tool,
		ContextName = normalizedContext,
	}))
	return true
end

function FruitGripController.PopContext(tool, fruitIdentifier, contextName, options)
	if not tool or not tool:IsA("Tool") then
		return false
	end

	local stack = contextStackByTool[tool]
	if not stack or #stack == 0 then
		return FruitGripController.ApplyToolGrip(tool, fruitIdentifier, mergeOptions(options, { Tool = tool }))
	end

	local normalizedContext = normalizeContextName(contextName)
	local removeIndex = #stack
	if normalizedContext then
		for index = #stack, 1, -1 do
			if stack[index].ContextName == normalizedContext then
				removeIndex = index
				break
			end
		end
	end

	local removedEntry = table.remove(stack, removeIndex)
	if #stack == 0 then
		contextStackByTool[tool] = nil
	end

	logInfo(
		"restore fruit=%s removedContext=%s remainingDepth=%d",
		tostring(fruitIdentifier or tool:GetAttribute("FruitKey") or "?"),
		tostring(removedEntry and removedEntry.ContextName or normalizedContext or "default"),
		stack and #stack or 0
	)

	FruitGripController.ApplyToolGrip(tool, fruitIdentifier, mergeOptions(options, { Tool = tool }))
	return true
end

return FruitGripController
