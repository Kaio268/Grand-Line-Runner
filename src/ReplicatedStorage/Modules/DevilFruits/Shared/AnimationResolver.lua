local ReplicatedStorage = game:GetService("ReplicatedStorage")
local KeyframeSequenceProvider = game:GetService("KeyframeSequenceProvider")
local RunService = game:GetService("RunService")

local DiagnosticLogLimiter = require(script.Parent.Parent:WaitForChild("DiagnosticLogLimiter"))
local AnimationRegistry = require(script.Parent:WaitForChild("AnimationRegistry"))

local AnimationResolver = {}

local DEBUG_INFO = RunService:IsStudio()
local INFO_COOLDOWN = 0.2
local WARN_COOLDOWN = 5
local ATTRIBUTE_RIG_NAMES = {
	"EatAnimationRig",
	"RigAnimationVariant",
	"RigVariant",
	"RigTypeName",
	"RigName",
	"CurrentModelAsset",
}

local syntheticAnimationsById = {}
local registeredKeyframeSequencesByPath = {}
local EMBEDDED_LIVE_ANIMATION_ID_KEYS = {
	"LiveAnimationId",
	"PublishedAnimationId",
	"AnimationId",
}

local function shouldLogInfo()
	return DEBUG_INFO or ReplicatedStorage:GetAttribute("DebugAnimationRegistry") == true
end

local function logInfo(message, ...)
	if not shouldLogInfo() then
		return
	end

	if not DiagnosticLogLimiter.ShouldEmit("AnimationResolver:INFO", DiagnosticLogLimiter.BuildKey(message, ...), INFO_COOLDOWN) then
		return
	end

	print(string.format("[ANIM REGISTRY] " .. message, ...))
end

local function logWarn(message, ...)
	if not DiagnosticLogLimiter.ShouldEmit("AnimationResolver:WARN", DiagnosticLogLimiter.BuildKey(message, ...), WARN_COOLDOWN) then
		return
	end

	warn(string.format("[ANIM REGISTRY][WARN] " .. message, ...))
end

local function normalizePath(logicalPath)
	if typeof(logicalPath) == "table" then
		local segments = {}
		for _, segment in ipairs(logicalPath) do
			if typeof(segment) == "string" and segment ~= "" then
				segments[#segments + 1] = segment
			end
		end
		return segments
	end

	if typeof(logicalPath) ~= "string" or logicalPath == "" then
		return {}
	end

	local segments = {}
	for segment in string.gmatch(logicalPath, "[^%.]+") do
		if segment ~= "" then
			segments[#segments + 1] = segment
		end
	end
	return segments
end

local function formatPath(logicalPath)
	local segments = normalizePath(logicalPath)
	if #segments == 0 then
		return "<invalid>"
	end

	return table.concat(segments, ".")
end

local function getRegistryNode(logicalPath)
	local segments = normalizePath(logicalPath)
	if #segments == 0 then
		return nil, "invalid_key", "<invalid>"
	end

	local node = AnimationRegistry
	for _, segment in ipairs(segments) do
		if type(node) ~= "table" then
			return nil, "invalid_parent", table.concat(segments, ".")
		end

		node = node[segment]
		if node == nil then
			return nil, "missing_key", table.concat(segments, ".")
		end
	end

	return node, nil, table.concat(segments, ".")
end

local function normalizeVariant(value)
	if typeof(value) ~= "string" or value == "" then
		return nil
	end

	local upper = string.upper(value)
	if upper == "R6" then
		return "R6"
	end
	if upper == "R6G" then
		return "R6G"
	end
	if upper == "DEFAULT" or upper == "R15" then
		return "Default"
	end

	return value
end

local function validateAnimationId(animationId, logicalKey)
	if typeof(animationId) ~= "string" or animationId == "" then
		logWarn("missing AnimationId key=%s", tostring(logicalKey))
		return nil
	end

	if not string.match(animationId, "^rbxassetid://%d+$") then
		logWarn("invalid AnimationId key=%s id=%s", tostring(logicalKey), tostring(animationId))
		return nil
	end

	return animationId
end

local function getSyntheticAnimation(animationId, logicalKey, variant)
	local animation = syntheticAnimationsById[animationId]
	if animation and animation.Parent == nil then
		return animation
	end

	animation = Instance.new("Animation")
	animation.Name = string.gsub(string.format("%s%s", tostring(logicalKey), variant and ("." .. variant) or ""), "%.", "_")
	animation.AnimationId = animationId
	syntheticAnimationsById[animationId] = animation
	return animation
end

local logResolvedAnimation

local function buildDescriptor(logicalKey, variant, animationId, source, metadata)
	local path = variant and string.format("AnimationRegistry/%s.%s", logicalKey, variant)
		or string.format("AnimationRegistry/%s", logicalKey)
	local descriptor = {
		LogicalKey = logicalKey,
		Variant = variant,
		AnimationId = animationId,
		Path = path,
		Source = source or "registry",
	}

	if type(metadata) == "table" then
		for key, value in pairs(metadata) do
			descriptor[key] = value
		end
	end

	return descriptor
end

local function resolveDataModelPath(path)
	local segments = normalizePath(path)
	if #segments == 0 then
		return nil, "<invalid>"
	end

	local node
	local startIndex = 1
	if segments[1] == "game" then
		node = game
		startIndex = 2
	elseif segments[1] == "ReplicatedStorage" then
		node = ReplicatedStorage
		startIndex = 2
	else
		local serviceOk, service = pcall(function()
			return game:GetService(segments[1])
		end)
		if serviceOk and service then
			node = service
			startIndex = 2
		else
			node = ReplicatedStorage
		end
	end

	for index = startIndex, #segments do
		if typeof(node) ~= "Instance" then
			return nil, table.concat(segments, ".")
		end

		node = node:FindFirstChild(segments[index])
		if not node then
			return nil, table.concat(segments, ".")
		end
	end

	return node, table.concat(segments, ".")
end

local function resolveEmbeddedKeyframeSequence(logicalKey, node, selectedVariant, options)
	if type(node) ~= "table" or node.KeyframeSequencePath == nil then
		return nil, nil, false
	end

	if not RunService:IsStudio() then
		for _, key in ipairs(EMBEDDED_LIVE_ANIMATION_ID_KEYS) do
			local candidateAnimationId = node[key]
			if typeof(candidateAnimationId) == "string" and candidateAnimationId ~= "" then
				local animationId = validateAnimationId(candidateAnimationId, logicalKey)
				if animationId then
					logResolvedAnimation(logicalKey, animationId, selectedVariant, selectedVariant, options or {})
					return animationId, buildDescriptor(logicalKey, selectedVariant, animationId, "published_embedded_fallback", {
						KeyframeSequencePath = formatPath(node.KeyframeSequencePath),
						Length = node.Length,
						LiveAnimationIdField = key,
					}), true
				end
			end
		end

		logWarn(
			"embedded KeyframeSequence is Studio-only key=%s variant=%s path=%s context=%s; upload it and set LiveAnimationId",
			tostring(logicalKey),
			tostring(selectedVariant or "<none>"),
			formatPath(node.KeyframeSequencePath),
			tostring(options and options.Context or "unknown")
		)
		return nil, buildDescriptor(logicalKey, selectedVariant, nil, "embedded_keyframe_sequence_studio_only", {
			KeyframeSequencePath = formatPath(node.KeyframeSequencePath),
			Length = node.Length,
		}), true
	end

	local candidatePaths = { node.KeyframeSequencePath }
	if type(node.FallbackKeyframeSequencePaths) == "table" then
		for _, fallbackPath in ipairs(node.FallbackKeyframeSequencePaths) do
			candidatePaths[#candidatePaths + 1] = fallbackPath
		end
	end

	local sequence
	local formattedPath
	local attemptedPaths = {}
	for _, candidatePath in ipairs(candidatePaths) do
		local candidateSequence, candidateFormattedPath = resolveDataModelPath(candidatePath)
		attemptedPaths[#attemptedPaths + 1] = candidateFormattedPath
		if candidateSequence and candidateSequence:IsA("KeyframeSequence") then
			sequence = candidateSequence
			formattedPath = candidateFormattedPath
			break
		end
	end

	if not sequence or not sequence:IsA("KeyframeSequence") then
		formattedPath = table.concat(attemptedPaths, ", ")
		logWarn(
			"missing embedded KeyframeSequence key=%s variant=%s path=%s context=%s",
			tostring(logicalKey),
			tostring(selectedVariant or "<none>"),
			tostring(formattedPath),
			tostring(options and options.Context or "unknown")
		)
		return nil, buildDescriptor(logicalKey, selectedVariant, nil, "missing_embedded_keyframe_sequence", {
			KeyframeSequencePath = formattedPath,
			KeyframeSequencePaths = attemptedPaths,
			Length = node.Length,
		}), true
	end

	local cacheKey = formattedPath
	local animationId = registeredKeyframeSequencesByPath[cacheKey]
	if not animationId then
		local ok, result = pcall(function()
			return KeyframeSequenceProvider:RegisterKeyframeSequence(sequence)
		end)
		if not ok or typeof(result) ~= "string" or result == "" then
			logWarn(
				"embedded KeyframeSequence register failed key=%s variant=%s path=%s detail=%s",
				tostring(logicalKey),
				tostring(selectedVariant or "<none>"),
				tostring(formattedPath),
				tostring(result)
			)
			return nil, buildDescriptor(logicalKey, selectedVariant, nil, "embedded_keyframe_sequence_register_failed", {
				KeyframeSequencePath = formattedPath,
				Length = node.Length,
			}), true
		end

		animationId = result
		registeredKeyframeSequencesByPath[cacheKey] = animationId
	end

	logResolvedAnimation(logicalKey, animationId, selectedVariant, selectedVariant, options or {})
	return animationId, buildDescriptor(logicalKey, selectedVariant, animationId, "embedded_keyframe_sequence", {
		KeyframeSequencePath = formattedPath,
		KeyframeSequencePaths = attemptedPaths,
		Length = node.Length,
	}), true
end

function logResolvedAnimation(logicalKey, animationId, selectedVariant, requestedVariant, options)
	options = type(options) == "table" and options or {}
	logInfo(
		"resolved context=%s key=%s requestedVariant=%s selectedVariant=%s id=%s",
		tostring(options.Context or "unknown"),
		tostring(logicalKey),
		tostring(requestedVariant or "<none>"),
		tostring(selectedVariant or "<none>"),
		tostring(animationId)
	)
end

function AnimationResolver.ResolveRigVariant(player, character, humanoid, options)
	options = type(options) == "table" and options or {}

	local targets = { character, humanoid, player }
	for _, target in ipairs(targets) do
		if typeof(target) ~= "Instance" then
			continue
		end

		for _, attributeName in ipairs(ATTRIBUTE_RIG_NAMES) do
			local variant = normalizeVariant(target:GetAttribute(attributeName))
			if variant then
				if variant == "R6G" and options.R6GAsDefault == true then
					return "Default"
				end
				return variant
			end
		end
	end

	if humanoid and humanoid.RigType == Enum.HumanoidRigType.R6 then
		return "R6"
	end

	return normalizeVariant(options.DefaultVariant) or "Default"
end

function AnimationResolver.ResolveAssetId(logicalPath, options)
	options = type(options) == "table" and options or {}

	local node, detail, logicalKey = getRegistryNode(logicalPath)
	if not node then
		logWarn("missing registry key key=%s detail=%s context=%s", tostring(logicalKey), tostring(detail), tostring(options.Context or "unknown"))
		return nil, buildDescriptor(logicalKey, nil, nil, "missing_registry_key")
	end

	if typeof(node) == "string" then
		local animationId = validateAnimationId(node, logicalKey)
		if animationId then
			logResolvedAnimation(logicalKey, animationId, nil, nil, options)
		end
		return animationId, buildDescriptor(logicalKey, nil, animationId, "registry")
	end

	if type(node) ~= "table" then
		logWarn("invalid registry node key=%s type=%s", tostring(logicalKey), typeof(node))
		return nil, buildDescriptor(logicalKey, nil, nil, "invalid_registry_node")
	end

	local embeddedAnimationId, embeddedDescriptor, isEmbeddedNode = resolveEmbeddedKeyframeSequence(
		logicalKey,
		node,
		nil,
		options
	)
	if isEmbeddedNode then
		return embeddedAnimationId, embeddedDescriptor
	end

	local variant = normalizeVariant(options.Variant)
	local fallbackVariant = normalizeVariant(options.FallbackVariant) or "Default"
	local animationId
	local selectedVariant

	if variant and typeof(node[variant]) == "string" then
		animationId = node[variant]
		selectedVariant = variant
	elseif variant and type(node[variant]) == "table" then
		local variantAnimationId, variantDescriptor, isEmbeddedVariant = resolveEmbeddedKeyframeSequence(
			logicalKey,
			node[variant],
			variant,
			options
		)
		if isEmbeddedVariant then
			return variantAnimationId, variantDescriptor
		end

		logWarn("invalid registry variant key=%s variant=%s type=%s", tostring(logicalKey), tostring(variant), typeof(node[variant]))
	elseif variant and node[variant] ~= nil then
		logWarn("invalid registry variant key=%s variant=%s type=%s", tostring(logicalKey), tostring(variant), typeof(node[variant]))
	elseif variant then
		logWarn("missing registry variant key=%s variant=%s context=%s", tostring(logicalKey), tostring(variant), tostring(options.Context or "unknown"))
	end

	if not animationId and fallbackVariant and typeof(node[fallbackVariant]) == "string" then
		animationId = node[fallbackVariant]
		selectedVariant = fallbackVariant
	elseif not animationId and fallbackVariant and type(node[fallbackVariant]) == "table" then
		local fallbackAnimationId, fallbackDescriptor, isEmbeddedFallback = resolveEmbeddedKeyframeSequence(
			logicalKey,
			node[fallbackVariant],
			fallbackVariant,
			options
		)
		if isEmbeddedFallback then
			return fallbackAnimationId, fallbackDescriptor
		end
	end

	if not animationId and typeof(node.Default) == "string" then
		animationId = node.Default
		selectedVariant = "Default"
	elseif not animationId and type(node.Default) == "table" then
		local defaultAnimationId, defaultDescriptor, isEmbeddedDefault = resolveEmbeddedKeyframeSequence(
			logicalKey,
			node.Default,
			"Default",
			options
		)
		if isEmbeddedDefault then
			return defaultAnimationId, defaultDescriptor
		end
	end

	if not animationId then
		logWarn("missing registry AnimationId key=%s variant=%s fallback=%s", tostring(logicalKey), tostring(variant), tostring(fallbackVariant))
		return nil, buildDescriptor(logicalKey, variant, nil, "missing_registry_animation_id")
	end

	animationId = validateAnimationId(animationId, logicalKey)
	if animationId then
		logResolvedAnimation(logicalKey, animationId, selectedVariant, variant, options)
	end
	return animationId, buildDescriptor(logicalKey, selectedVariant, animationId, "registry")
end

function AnimationResolver.GetAssetId(logicalPath, options)
	local animationId = AnimationResolver.ResolveAssetId(logicalPath, options)
	return animationId
end

function AnimationResolver.GetAnimation(logicalPath, options)
	local animationId, descriptor = AnimationResolver.ResolveAssetId(logicalPath, options)
	if not animationId then
		return nil, descriptor
	end

	return getSyntheticAnimation(animationId, descriptor.LogicalKey, descriptor.Variant), descriptor
end

function AnimationResolver.GetRigAwareAnimation(logicalPath, player, character, humanoid, options)
	options = type(options) == "table" and options or {}
	local variant = options.Variant or AnimationResolver.ResolveRigVariant(player, character, humanoid, options)
	local animation, descriptor = AnimationResolver.GetAnimation(logicalPath, {
		Variant = variant,
		FallbackVariant = options.FallbackVariant or "Default",
		Context = options.Context,
	})
	return animation, descriptor
end

function AnimationResolver.BuildCandidate(logicalPath, options)
	local animation, descriptor = AnimationResolver.GetAnimation(logicalPath, options)
	if not animation then
		return nil, descriptor
	end

	return {
		Animation = animation,
		Path = descriptor.Path,
		AnimationId = descriptor.AnimationId,
		ContainerPath = descriptor.Path,
		Source = descriptor.Source,
		SupportsReleaseMarker = options and options.SupportsReleaseMarker ~= false,
		LogicalKey = descriptor.LogicalKey,
		Variant = descriptor.Variant,
	}, descriptor
end

function AnimationResolver.BuildRegistryPath(logicalPath, options)
	local logicalKey = formatPath(logicalPath)
	local variant = normalizeVariant(options and options.Variant)
	if variant then
		return string.format("AnimationRegistry/%s.%s", logicalKey, variant)
	end

	return string.format("AnimationRegistry/%s", logicalKey)
end

return AnimationResolver
