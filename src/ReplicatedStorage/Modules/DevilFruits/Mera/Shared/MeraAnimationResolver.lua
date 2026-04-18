local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MeraAssetCatalog = require(script.Parent:WaitForChild("MeraAssetCatalog"))
local AnimationResolver = require(
	ReplicatedStorage:WaitForChild("Modules"):WaitForChild("DevilFruits"):WaitForChild("Shared"):WaitForChild("AnimationResolver")
)

local MeraAnimationResolver = {}

local FLAME_DASH_CANDIDATES = { "Flame Dash", "FlameDash", "Dash" }
local FLAME_DASH_PREFERRED_DESCENDANT_CONTAINERS = { "AnimSaves", "Flame Dash" }
local REGISTRY_KEY_BY_MOVE = {
	FlameDash = "Mera.FlameDash",
	FireBurst = "Mera.FlameBurstR6",
}
local syntheticAnimationsById = {}

function MeraAnimationResolver.BuildAnimationPath(assetName)
	if typeof(assetName) == "string" and string.find(assetName, "%.") then
		return AnimationResolver.BuildRegistryPath(assetName)
	end

	return string.format("ReplicatedStorage/Assets/Animations/Mera/%s", tostring(assetName or ""))
end

function MeraAnimationResolver.IsPlayableAnimation(animation)
	if typeof(animation) ~= "Instance" or not animation:IsA("Animation") then
		return false
	end

	return tostring(animation.AnimationId or "") ~= ""
end

local function appendUniqueInstance(target, seen, instance)
	if typeof(instance) ~= "Instance" or seen[instance] then
		return false
	end

	seen[instance] = true
	target[#target + 1] = instance
	return true
end

local function getAnimationSearchRoots()
	local roots = {}
	local seen = {}

	local assetsFolder = ReplicatedStorage:FindFirstChild("Assets")
	local assetsAnimationsFolder = assetsFolder and assetsFolder:FindFirstChild("Animations")
	local assetsMeraFolder = assetsAnimationsFolder and assetsAnimationsFolder:FindFirstChild("Mera")
	local replicatedAnimationsFolder = ReplicatedStorage:FindFirstChild("Animations")
	local replicatedMeraFolder = replicatedAnimationsFolder and replicatedAnimationsFolder:FindFirstChild("Mera")

	appendUniqueInstance(roots, seen, assetsMeraFolder)
	appendUniqueInstance(roots, seen, replicatedMeraFolder)
	appendUniqueInstance(roots, seen, assetsAnimationsFolder)
	appendUniqueInstance(roots, seen, replicatedAnimationsFolder)

	return roots
end

local function getSyntheticAnimation(animationId, name)
	local resolvedId = tostring(animationId or "")
	if resolvedId == "" then
		return nil
	end

	local animation = syntheticAnimationsById[resolvedId]
	if animation and animation.Parent == nil then
		return animation
	end

	animation = Instance.new("Animation")
	animation.Name = tostring(name or resolvedId)
	animation.AnimationId = resolvedId
	syntheticAnimationsById[resolvedId] = animation
	return animation
end

local function getCandidateNames(moveName, configuredAssetName, defaultAssetName)
	if tostring(moveName) == "FlameDash" then
		return MeraAssetCatalog.BuildCandidateList(configuredAssetName or defaultAssetName, FLAME_DASH_CANDIDATES)
	end

	return MeraAssetCatalog.GetAnimationCandidates(moveName, configuredAssetName, defaultAssetName)
end

local function appendAnimationCandidate(candidates, seenAnimations, animation, containerPath, sourceLabel, supportsReleaseMarker)
	if not MeraAnimationResolver.IsPlayableAnimation(animation) then
		return
	end

	local seenKey = tostring(animation.AnimationId or "")
	if seenKey == "" then
		seenKey = animation
	end
	if seenAnimations[seenKey] then
		return
	end

	seenAnimations[seenKey] = true
	candidates[#candidates + 1] = {
		Animation = animation,
		Path = animation:GetFullName(),
		AnimationId = tostring(animation.AnimationId or ""),
		ContainerPath = tostring(containerPath or animation:GetFullName()),
		Source = tostring(sourceLabel or "candidate"),
		SupportsReleaseMarker = supportsReleaseMarker ~= false,
	}
end

local function appendRegistryCandidate(candidates, seenAnimations, moveName, animationKey)
	local registryKey = animationKey or REGISTRY_KEY_BY_MOVE[tostring(moveName)]
	if typeof(registryKey) ~= "string" or registryKey == "" then
		return
	end

	local candidate = AnimationResolver.BuildCandidate(registryKey, {
		Context = string.format("Mera.%s", tostring(moveName)),
		SupportsReleaseMarker = true,
	})
	if not candidate then
		return
	end

	local seenKey = tostring(candidate.AnimationId or "")
	if seenKey == "" or seenAnimations[seenKey] then
		return
	end

	seenAnimations[seenKey] = true
	candidates[#candidates + 1] = candidate
end

local function getPreferredDescendantContainers(moveName, containerName)
	if tostring(moveName) ~= "FlameDash" or tostring(containerName) ~= "Flame Dash" then
		return nil
	end

	return FLAME_DASH_PREFERRED_DESCENDANT_CONTAINERS
end

local function collectAnimationsFromContainer(container, moveName, containerName)
	if typeof(container) ~= "Instance" then
		return {}
	end

	if MeraAnimationResolver.IsPlayableAnimation(container) then
		return { container }
	end

	local orderedRoots = {}
	local seenRoots = {}

	local function appendRoot(root)
		appendUniqueInstance(orderedRoots, seenRoots, root)
	end

	for _, preferredName in ipairs(getPreferredDescendantContainers(moveName, containerName) or {}) do
		if container.Name == preferredName then
			appendRoot(container)
		end

		appendRoot(container:FindFirstChild(preferredName))
		for _, descendant in ipairs(container:GetDescendants()) do
			if descendant.Name == preferredName then
				appendRoot(descendant)
			end
		end
	end

	appendRoot(container)

	local animations = {}
	local seenAnimations = {}
	for _, searchRoot in ipairs(orderedRoots) do
		if MeraAnimationResolver.IsPlayableAnimation(searchRoot) then
			appendUniqueInstance(animations, seenAnimations, searchRoot)
		end

		for _, descendant in ipairs(searchRoot:GetDescendants()) do
			if MeraAnimationResolver.IsPlayableAnimation(descendant) then
				appendUniqueInstance(animations, seenAnimations, descendant)
			end
		end
	end

	return animations
end

local function collectRuntimeFallbackCandidates(moveName, candidates, seenAnimations)
	for _, descriptor in ipairs(MeraAssetCatalog.GetRuntimeAnimationFallbacks(moveName)) do
		if type(descriptor) == "table" and descriptor.Type == "animation_id" then
			local animation = getSyntheticAnimation(descriptor.AnimationId, descriptor.Name or moveName)
			if animation then
				appendAnimationCandidate(
					candidates,
					seenAnimations,
					animation,
					tostring(descriptor.Path or descriptor.AnimationId),
					descriptor.Source or "runtime_fallback",
					descriptor.SupportsReleaseMarker
				)
			end
		end
	end
end

local function collectNamedCandidates(root, moveName, candidateName, candidates, seenAnimations)
	if typeof(root) ~= "Instance" or typeof(candidateName) ~= "string" or candidateName == "" then
		return
	end

	local processedContainers = {}

	local function appendContainer(container, sourceLabel)
		if typeof(container) ~= "Instance" or processedContainers[container] then
			return
		end

		processedContainers[container] = true
		local containerPath = container:GetFullName()
		for _, animation in ipairs(collectAnimationsFromContainer(container, moveName, candidateName)) do
			appendAnimationCandidate(candidates, seenAnimations, animation, containerPath, sourceLabel, true)
		end
	end

	appendContainer(root:FindFirstChild(candidateName), "named_child")

	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant.Name == candidateName then
			appendContainer(descendant, "named_descendant")
		end
	end
end

local function collectKeywordCandidates(root, moveName, candidates, seenAnimations)
	if typeof(root) ~= "Instance" or tostring(moveName) ~= "FlameDash" then
		return
	end

	for _, descendant in ipairs(root:GetDescendants()) do
		if not MeraAnimationResolver.IsPlayableAnimation(descendant) then
			continue
		end

		local loweredName = string.lower(descendant.Name)
		if string.find(loweredName, "dash", 1, true)
			and (string.find(loweredName, "flame", 1, true) or string.find(loweredName, "mera", 1, true))
		then
			appendAnimationCandidate(
				candidates,
				seenAnimations,
				descendant,
				descendant.Parent and descendant.Parent:GetFullName() or descendant:GetFullName(),
				"keyword_match",
				false
			)
		end
	end
end

function MeraAnimationResolver.CollectAnimationCandidates(moveName, configuredAssetName, defaultAssetName, animationKey)
	local candidateNames = getCandidateNames(moveName, configuredAssetName, defaultAssetName)
	local candidates = {}
	local seenAnimations = {}

	appendRegistryCandidate(candidates, seenAnimations, moveName, animationKey)

	for _, root in ipairs(getAnimationSearchRoots()) do
		for _, candidateName in ipairs(candidateNames) do
			collectNamedCandidates(root, moveName, candidateName, candidates, seenAnimations)
		end

		collectKeywordCandidates(root, moveName, candidates, seenAnimations)
	end

	collectRuntimeFallbackCandidates(moveName, candidates, seenAnimations)

	return candidates, candidateNames
end

return MeraAnimationResolver
