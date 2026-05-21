local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local StudioAssetResolver = {}

local roots = {
	ReplicatedStorage = ReplicatedStorage,
	Workspace = Workspace,
}

if RunService:IsServer() then
	roots.ServerStorage = game:GetService("ServerStorage")
end

local definitions = {
	SpikeTraps = {
		ClassNames = { "Folder" },
		Paths = {
			{ "ReplicatedStorage", "Assets", "Hazards", "SpikeTraps" },
			{ "ReplicatedStorage", "Assets", "Hazards", "Spike Traps" },
			{ "ReplicatedStorage", "Assets", "SpikeTraps" },
			{ "ReplicatedStorage", "Assets", "Spike Traps" },
			{ "ReplicatedStorage", "SpikeTraps" },
			{ "ReplicatedStorage", "Spike Traps" },
			{ "Workspace", "SpikeTraps" },
			{ "Workspace", "Spike Traps" },
			{ "ServerStorage", "SpikeTraps" },
			{ "ServerStorage", "Spike Traps" },
		},
		RecursiveRoots = {
			{ "ReplicatedStorage", "Assets", "Hazards" },
			{ "ReplicatedStorage", "Assets" },
			{ "ReplicatedStorage" },
			{ "Workspace" },
			{ "ServerStorage" },
		},
		RecursiveNames = { "SpikeTraps", "Spike Traps", "SpikeTrapsFolder" },
	},
	Puddles = {
		ClassNames = { "Folder" },
		Paths = {
			{ "ReplicatedStorage", "Assets", "Hazards", "Puddles" },
			{ "ReplicatedStorage", "Assets", "Puddles" },
			{ "ReplicatedStorage", "Puddles" },
			{ "Workspace", "Puddles" },
			{ "ServerStorage", "Puddles" },
		},
		RecursiveRoots = {
			{ "ReplicatedStorage", "Assets", "Hazards" },
			{ "ReplicatedStorage", "Assets" },
			{ "ReplicatedStorage" },
			{ "Workspace" },
			{ "ServerStorage" },
		},
		RecursiveNames = { "Puddles", "PUDDLES", "Puddle", "puddles" },
	},
	Waves = {
		ClassNames = { "Folder" },
		Paths = {
			{ "ReplicatedStorage", "Assets", "Hazards", "Waves" },
			{ "ReplicatedStorage", "Waves" },
		},
		RecursiveRoots = {
			{ "ReplicatedStorage", "Assets", "Hazards" },
			{ "ReplicatedStorage", "Assets" },
			{ "ReplicatedStorage" },
		},
		RecursiveNames = { "Waves" },
	},
	CannonVfx = {
		ClassNames = { "Folder", "Model", "BasePart", "Attachment" },
		Paths = {
			{ "ReplicatedStorage", "Assets", "Hazards", "CannonVFX" },
			{ "ReplicatedStorage", "Assets", "Hazards", "cannonVFX" },
			{ "ReplicatedStorage", "Assets", "Hazards", "CannonballVFX" },
			{ "ReplicatedStorage", "Assets", "Hazards", "canonballVFX" },
			{ "ReplicatedStorage", "Assets", "cannonVFX" },
			{ "ReplicatedStorage", "Assets", "cannonVFX", "canonballVFX" },
			{ "ReplicatedStorage", "Assets", "cannonVFX", "canonballVFX (1)" },
			{ "ReplicatedStorage", "Assets", "VFX", "canonball_vfx" },
			{ "ReplicatedStorage", "Assets", "VFX", "canonball_vfx", "canonballVFX" },
		},
		RecursiveRoots = {
			{ "ReplicatedStorage", "Assets", "Hazards" },
			{ "ReplicatedStorage", "Assets" },
		},
		RecursiveNames = {
			"CannonVFX",
			"cannonVFX",
			"CannonballVFX",
			"Cannonball VFX",
			"canonballVFX",
			"canonballVFX (1)",
			"canonball_vfx",
		},
		RecursiveKeywords = { "cannon", "canon" },
	},
}

local cache = {}
local missingCache = {}
local warned = {}

local function pathToString(path)
	return table.concat(path, ".")
end

local function getPath(path)
	local current = roots[path[1]]
	if not current then
		return nil
	end

	for index = 2, #path do
		current = current:FindFirstChild(path[index])
		if not current then
			return nil
		end
	end

	return current
end

local function waitForPath(path, timeout)
	local current = roots[path[1]]
	if not current then
		return nil
	end

	local deadline = os.clock() + math.max(0, tonumber(timeout) or 0)
	for index = 2, #path do
		local child = current:FindFirstChild(path[index])
		if child then
			current = child
		else
			local remaining = deadline - os.clock()
			if remaining <= 0 then
				return nil
			end

			child = current:WaitForChild(path[index], remaining)
			if not child then
				return nil
			end

			current = child
		end
	end

	return current
end

local function classMatches(instance, classNames)
	if not instance then
		return false
	end

	if typeof(classNames) ~= "table" or #classNames == 0 then
		return true
	end

	for _, className in ipairs(classNames) do
		if instance:IsA(className) then
			return true
		end
	end

	return false
end

local function getNameSet(names)
	local nameSet = {}
	for _, name in ipairs(names or {}) do
		nameSet[tostring(name)] = true
	end
	return nameSet
end

local function getKeywordList(keywords)
	local keywordList = {}
	for _, keyword in ipairs(keywords or {}) do
		local normalized = string.lower(tostring(keyword or ""))
		if normalized ~= "" then
			keywordList[#keywordList + 1] = normalized
		end
	end
	return keywordList
end

local function nameMatches(instanceName, nameSet, keywordList)
	if nameSet[instanceName] == true then
		return true
	end

	local lowerName = string.lower(instanceName)
	for _, keyword in ipairs(keywordList) do
		if string.find(lowerName, keyword, 1, true) then
			return true
		end
	end

	return false
end

local function findRecursive(definition)
	local nameSet = getNameSet(definition.RecursiveNames)
	local keywordList = getKeywordList(definition.RecursiveKeywords)
	if next(nameSet) == nil and #keywordList == 0 then
		return nil
	end

	for _, rootPath in ipairs(definition.RecursiveRoots or {}) do
		local root = getPath(rootPath)
		if root and classMatches(root, definition.ClassNames) and nameMatches(root.Name, nameSet, keywordList) then
			return root
		end

		if root then
			for _, descendant in ipairs(root:GetDescendants()) do
				if classMatches(descendant, definition.ClassNames) and nameMatches(descendant.Name, nameSet, keywordList) then
					return descendant
				end
			end
		end
	end

	return nil
end

local function getTriedPaths(definition)
	local paths = {}
	for _, path in ipairs(definition.Paths or {}) do
		paths[#paths + 1] = pathToString(path)
	end

	for _, path in ipairs(definition.RecursiveRoots or {}) do
		paths[#paths + 1] = pathToString(path) .. "/*"
	end

	return table.concat(paths, ", ")
end

local function warnMissing(assetId, definition, options)
	options = if typeof(options) == "table" then options else {}
	if options.WarnIfMissing == false then
		return
	end

	local context = tostring(options.Context or "unknown")
	local warningKey = tostring(assetId) .. ":" .. context
	if warned[warningKey] == true then
		return
	end
	warned[warningKey] = true

	local requiredLabel = if options.Required == true then "required" else "optional"
	warn(string.format(
		"[StudioAssetResolver] Missing %s Studio asset '%s' for %s. Tried: %s",
		requiredLabel,
		tostring(assetId),
		context,
		getTriedPaths(definition)
	))
end

function StudioAssetResolver.ResolveAsset(assetId, options)
	assetId = tostring(assetId or "")
	local definition = definitions[assetId]
	if not definition then
		error(string.format("[StudioAssetResolver] Unknown asset id '%s'.", assetId), 2)
	end
	options = if typeof(options) == "table" then options else {}
	local cacheMissing = options.CacheMissing ~= false

	local cached = cache[assetId]
	if cached and cached.Parent then
		return cached
	elseif cached then
		cache[assetId] = nil
	end

	if cacheMissing and missingCache[assetId] == true then
		warnMissing(assetId, definition, options)
		return nil
	end

	for _, path in ipairs(definition.Paths or {}) do
		local instance = getPath(path)
		if classMatches(instance, definition.ClassNames) then
			cache[assetId] = instance
			return instance
		end
	end

	local recursiveMatch = findRecursive(definition)
	if recursiveMatch then
		cache[assetId] = recursiveMatch
		return recursiveMatch
	end

	if cacheMissing then
		missingCache[assetId] = true
	end
	warnMissing(assetId, definition, options)
	return nil
end

function StudioAssetResolver.WaitForAsset(assetId, timeout, options)
	assetId = tostring(assetId or "")
	local definition = definitions[assetId]
	if not definition then
		error(string.format("[StudioAssetResolver] Unknown asset id '%s'.", assetId), 2)
	end
	options = if typeof(options) == "table" then options else {}

	local canonicalPath = definition.Paths and definition.Paths[1]
	if canonicalPath then
		local instance = waitForPath(canonicalPath, timeout)
		if classMatches(instance, definition.ClassNames) then
			cache[assetId] = instance
			missingCache[assetId] = nil
			return instance
		end
	end

	options.CacheMissing = false
	return StudioAssetResolver.ResolveAsset(assetId, options)
end

function StudioAssetResolver.ValidateRequiredAssets(assetIds, context)
	for _, assetId in ipairs(assetIds or {}) do
		StudioAssetResolver.ResolveAsset(assetId, {
			Context = context,
			Required = true,
		})
	end
end

function StudioAssetResolver.ClearCache(assetId)
	if assetId == nil then
		table.clear(cache)
		table.clear(missingCache)
		return
	end

	assetId = tostring(assetId)
	cache[assetId] = nil
	missingCache[assetId] = nil
end

return StudioAssetResolver
