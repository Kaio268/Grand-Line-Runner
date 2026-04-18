local ReplicatedStorage = game:GetService("ReplicatedStorage")
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

local function buildDescriptor(logicalKey, variant, animationId, source)
	local path = variant and string.format("AnimationRegistry/%s.%s", logicalKey, variant)
		or string.format("AnimationRegistry/%s", logicalKey)
	return {
		LogicalKey = logicalKey,
		Variant = variant,
		AnimationId = animationId,
		Path = path,
		Source = source or "registry",
	}
end

local function logResolvedAnimation(logicalKey, animationId, selectedVariant, requestedVariant, options)
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

	local variant = normalizeVariant(options.Variant)
	local fallbackVariant = normalizeVariant(options.FallbackVariant) or "Default"
	local animationId
	local selectedVariant

	if variant and typeof(node[variant]) == "string" then
		animationId = node[variant]
		selectedVariant = variant
	elseif variant and node[variant] ~= nil then
		logWarn("invalid registry variant key=%s variant=%s type=%s", tostring(logicalKey), tostring(variant), typeof(node[variant]))
	elseif variant then
		logWarn("missing registry variant key=%s variant=%s context=%s", tostring(logicalKey), tostring(variant), tostring(options.Context or "unknown"))
	end

	if not animationId and fallbackVariant and typeof(node[fallbackVariant]) == "string" then
		animationId = node[fallbackVariant]
		selectedVariant = fallbackVariant
	end

	if not animationId and typeof(node.Default) == "string" then
		animationId = node.Default
		selectedVariant = "Default"
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
