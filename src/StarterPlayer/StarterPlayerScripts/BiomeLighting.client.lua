local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local MapResolver = require(Modules:WaitForChild("MapResolver"))

local player = Players.LocalPlayer

local STAGE_FOLDER_PATTERN = "^Stage%s+(%d+)%s+Lighting$"
local BIOME_FOLDER_PATTERN = "^Biome%s+(%d+)$"
local UPDATE_INTERVAL = 0.12
local RAYCAST_START_HEIGHT = 12
local RAYCAST_DISTANCE = 220
local LOG_PREFIX = "[BIOME LIGHTING]"

local RUNTIME_ATTRIBUTE = "BiomeLightingRuntime"
local GLOBAL_ATTRIBUTE = "BiomeLightingGlobal"
local SOURCE_ATTRIBUTE = "BiomeLightingSource"
local SOURCE_STAGE_ATTRIBUTE = "BiomeLightingStage"
local ACTIVE_BIOME_ATTRIBUTE = "ActiveBiomeLightingBiome"
local ACTIVE_STAGE_ATTRIBUTE = "ActiveBiomeLightingStage"
local SUPPRESSED_FOLDER_NAME = "_BiomeLightingSuppressed"

local LIGHTING_VALUE_CLASSES = {
	BoolValue = true,
	Color3Value = true,
	IntValue = true,
	NumberValue = true,
	StringValue = true,
}

local EXCLUSIVE_LIGHTING_CLASSES = {
	Atmosphere = true,
	BloomEffect = true,
	BlurEffect = true,
	Clouds = true,
	ColorCorrectionEffect = true,
	DepthOfFieldEffect = true,
	Sky = true,
	SunRaysEffect = true,
}

local activeBiomeIndex = nil
local activeStageIndex = nil
local appliedPropertyNames = {}
local originalLightingProperties = {}
local warnedMissingStages = {}
local warnedMissingBiomes = false
local biomesRoot = nil
local biomeContainersByIndex = {}

local function getIndexFromName(name, pattern)
	local indexText = tostring(name):match(pattern)
	return indexText and tonumber(indexText) or nil
end

local function isStageLightingFolder(instance)
	return instance
		and instance:IsA("Folder")
		and getIndexFromName(instance.Name, STAGE_FOLDER_PATTERN) ~= nil
end

local function isLightingValueObject(instance)
	return instance and LIGHTING_VALUE_CLASSES[instance.ClassName] == true
end

local function isLightingObject(instance)
	return instance
		and (
			instance:IsA("PostEffect")
			or instance:IsA("Atmosphere")
			or instance:IsA("Sky")
			or instance:IsA("Clouds")
		)
end

local function isUiLightingObject(instance)
	local lowerName = string.lower(instance and instance.Name or "")
	return lowerName:find("ui", 1, true) ~= nil
end

local function isProtectedLightingChild(instance)
	if not instance or instance.Parent ~= Lighting then
		return true
	end

	if instance:GetAttribute(RUNTIME_ATTRIBUTE) == true or instance:GetAttribute(GLOBAL_ATTRIBUTE) == true then
		return true
	end

	if instance.Name == SUPPRESSED_FOLDER_NAME or isStageLightingFolder(instance) then
		return true
	end

	if instance:IsA("BlurEffect") and isUiLightingObject(instance) then
		return true
	end

	return false
end

local function lightingObjectsConflict(existing, source)
	if not isLightingObject(existing) or not isLightingObject(source) then
		return false
	end

	if existing.Name == source.Name then
		return true
	end

	return EXCLUSIVE_LIGHTING_CLASSES[source.ClassName] == true and existing.ClassName == source.ClassName
end

local function getSuppressedFolder()
	local existing = Lighting:FindFirstChild(SUPPRESSED_FOLDER_NAME)
	if existing and existing:IsA("Folder") then
		return existing
	end

	if existing then
		existing:Destroy()
	end

	local folder = Instance.new("Folder")
	folder.Name = SUPPRESSED_FOLDER_NAME
	folder:SetAttribute(RUNTIME_ATTRIBUTE, true)
	folder.Parent = Lighting
	return folder
end

local function restoreSuppressedLightingObjects()
	local folder = Lighting:FindFirstChild(SUPPRESSED_FOLDER_NAME)
	if not folder then
		return
	end

	for _, child in ipairs(folder:GetChildren()) do
		child.Parent = Lighting
	end
end

local function destroyRuntimeLightingObjects()
	for _, child in ipairs(Lighting:GetChildren()) do
		if child:GetAttribute(RUNTIME_ATTRIBUTE) == true and child.Name ~= SUPPRESSED_FOLDER_NAME then
			child:Destroy()
		end
	end
end

local function restoreLightingProperties()
	for propertyName in pairs(appliedPropertyNames) do
		local originalValue = originalLightingProperties[propertyName]
		if originalValue ~= nil then
			pcall(function()
				Lighting[propertyName] = originalValue
			end)
		end
	end

	table.clear(appliedPropertyNames)
end

local function clearActiveStageLighting()
	destroyRuntimeLightingObjects()
	restoreSuppressedLightingObjects()
	restoreLightingProperties()
	activeStageIndex = nil
	Lighting:SetAttribute(ACTIVE_STAGE_ATTRIBUTE, nil)
end

local function findStageFolder(stageIndex)
	local expectedName = string.format("Stage %d Lighting", stageIndex)
	local direct = Lighting:FindFirstChild(expectedName)
	if direct and direct:IsA("Folder") then
		return direct
	end

	for _, child in ipairs(Lighting:GetChildren()) do
		if isStageLightingFolder(child) and getIndexFromName(child.Name, STAGE_FOLDER_PATTERN) == stageIndex then
			return child
		end
	end

	return nil
end

local function collectStageLightingObjects(stageFolder)
	local objects = {}

	for _, descendant in ipairs(stageFolder:GetDescendants()) do
		if isLightingObject(descendant) then
			table.insert(objects, descendant)
		end
	end

	return objects
end

local function collectStageLightingProperties(stageFolder)
	local properties = {}

	for _, child in ipairs(stageFolder:GetChildren()) do
		if isLightingValueObject(child) then
			table.insert(properties, child)
		end
	end

	return properties
end

local function suppressConflictingLightingObjects(source)
	local suppressedFolder = nil

	for _, existing in ipairs(Lighting:GetChildren()) do
		if not isProtectedLightingChild(existing) and lightingObjectsConflict(existing, source) then
			suppressedFolder = suppressedFolder or getSuppressedFolder()
			existing.Parent = suppressedFolder
		end
	end
end

local function applyStageProperties(stageFolder)
	for _, valueObject in ipairs(collectStageLightingProperties(stageFolder)) do
		local propertyName = valueObject.Name
		if originalLightingProperties[propertyName] == nil then
			local ok, currentValue = pcall(function()
				return Lighting[propertyName]
			end)
			if ok then
				originalLightingProperties[propertyName] = currentValue
			end
		end

		local ok = pcall(function()
			Lighting[propertyName] = valueObject.Value
		end)
		if ok then
			appliedPropertyNames[propertyName] = true
		end
	end
end

local function applyStageObjects(stageFolder, stageIndex)
	local objects = collectStageLightingObjects(stageFolder)

	for _, source in ipairs(objects) do
		suppressConflictingLightingObjects(source)

		local clone = source:Clone()
		clone:SetAttribute(RUNTIME_ATTRIBUTE, true)
		clone:SetAttribute(SOURCE_STAGE_ATTRIBUTE, stageIndex)
		clone:SetAttribute(SOURCE_ATTRIBUTE, source:GetFullName())
		clone.Parent = Lighting
	end
end

local function applyStageLighting(stageIndex)
	if activeStageIndex == stageIndex then
		return
	end

	clearActiveStageLighting()

	local stageFolder = findStageFolder(stageIndex)
	if not stageFolder then
		if not warnedMissingStages[stageIndex] then
			warnedMissingStages[stageIndex] = true
			warn(string.format("%s Missing Lighting.%s.", LOG_PREFIX, string.format("Stage %d Lighting", stageIndex)))
		end
		return
	end

	applyStageProperties(stageFolder)
	applyStageObjects(stageFolder, stageIndex)

	activeStageIndex = stageIndex
	Lighting:SetAttribute(ACTIVE_STAGE_ATTRIBUTE, stageIndex)
end

local function setActiveBiome(biomeIndex)
	if activeBiomeIndex == biomeIndex then
		return
	end

	activeBiomeIndex = biomeIndex
	Lighting:SetAttribute(ACTIVE_BIOME_ATTRIBUTE, biomeIndex)

	if biomeIndex then
		applyStageLighting(biomeIndex)
	else
		clearActiveStageLighting()
	end
end

local function getLegacyBiomesRoot()
	local legacyMap = Workspace:FindFirstChild("LegacyMap")
	return legacyMap and legacyMap:FindFirstChild("Biomes") or nil
end

local function rebuildBiomeMap()
	local refs = MapResolver.GetRefs({
		context = "BiomeLighting",
	})

	biomesRoot = refs.Biomes or getLegacyBiomesRoot()
	table.clear(biomeContainersByIndex)

	if not biomesRoot then
		return false
	end

	for _, child in ipairs(biomesRoot:GetChildren()) do
		local biomeIndex = getIndexFromName(child.Name, BIOME_FOLDER_PATTERN)
		if biomeIndex then
			biomeContainersByIndex[biomeIndex] = child
		end
	end

	return next(biomeContainersByIndex) ~= nil
end

local function getTopLevelBiomeContainer(instance)
	local current = instance
	while current and current ~= biomesRoot do
		local parent = current.Parent
		if parent == biomesRoot then
			local biomeIndex = getIndexFromName(current.Name, BIOME_FOLDER_PATTERN)
			if biomeIndex then
				return current, biomeIndex
			end
			return nil, nil
		end

		current = parent
	end

	return nil, nil
end

local function getCharacterRoot()
	local character = player.Character
	return character and character:FindFirstChild("HumanoidRootPart") or nil
end

local function detectCurrentBiomeIndex()
	if not biomesRoot or not biomesRoot.Parent then
		if not rebuildBiomeMap() then
			return nil
		end
	end

	local rootPart = getCharacterRoot()
	if not rootPart then
		return nil
	end

	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Include
	raycastParams.FilterDescendantsInstances = { biomesRoot }
	raycastParams.IgnoreWater = true

	local origin = rootPart.Position + Vector3.new(0, RAYCAST_START_HEIGHT, 0)
	local result = Workspace:Raycast(origin, Vector3.new(0, -RAYCAST_DISTANCE, 0), raycastParams)
	if not result then
		return nil
	end

	local _, biomeIndex = getTopLevelBiomeContainer(result.Instance)
	return biomeIndex
end

local function startBiomeLightingLoop()
	local accumulated = UPDATE_INTERVAL

	RunService.Heartbeat:Connect(function(deltaTime)
		accumulated += deltaTime
		if accumulated < UPDATE_INTERVAL then
			return
		end

		accumulated = 0
		local biomeIndex = detectCurrentBiomeIndex()
		setActiveBiome(biomeIndex)
	end)
end

if not rebuildBiomeMap() and not warnedMissingBiomes then
	warnedMissingBiomes = true
	warn(string.format("%s Missing Workspace.LegacyMap.Biomes; lighting will wait for map refs.", LOG_PREFIX))
end

player.CharacterRemoving:Connect(function()
	setActiveBiome(nil)
end)

startBiomeLightingLoop()
