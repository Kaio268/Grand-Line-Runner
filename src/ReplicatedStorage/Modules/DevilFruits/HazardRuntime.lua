local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local HazardUtils = require(Modules:WaitForChild("DevilFruits"):WaitForChild("HazardUtils"))
local MapResolver = require(Modules:WaitForChild("MapResolver"))

local HazardRuntime = {}

local controllersByRoot = setmetatable({}, { __mode = "k" })
local overlapParamsByHazardsFolder = setmetatable({}, { __mode = "k" })

local MAX_SERVER_SEARCH_RADIUS = 32
local MAX_RADIUS_QUERY_PARTS = 128
local MAX_UNIQUE_HAZARDS = 16
local MAX_SEGMENT_SAMPLES = 96

local function getPivotPosition(instance)
	if not instance or not instance.Parent then
		return nil
	end

	if instance:IsA("Model") then
		return instance:GetPivot().Position
	end

	if instance:IsA("BasePart") then
		return instance.Position
	end

	return nil
end

local function getHazardOverlapParams(hazardsFolder)
	local overlapParams = overlapParamsByHazardsFolder[hazardsFolder]
	if overlapParams then
		return overlapParams
	end

	overlapParams = OverlapParams.new()
	overlapParams.FilterType = Enum.RaycastFilterType.Include
	overlapParams.FilterDescendantsInstances = { hazardsFolder }
	overlapParams.MaxParts = MAX_RADIUS_QUERY_PARTS
	overlapParamsByHazardsFolder[hazardsFolder] = overlapParams
	return overlapParams
end

local function getSharedHazardsFolder()
	if not RunService:IsServer() then
		return nil
	end

	local refs = MapResolver.GetRefs()
	local waveFolder = refs and refs.WaveFolder
	if not waveFolder or not waveFolder.Parent then
		return nil
	end

	local hazardsFolder = waveFolder:FindFirstChild("Hazards")
	if hazardsFolder and hazardsFolder:IsA("Folder") then
		return hazardsFolder
	end

	return nil
end

local function matchesStringSet(value, allowedValues)
	if type(allowedValues) ~= "table" then
		return true
	end

	local normalizedValue = string.lower(tostring(value or ""))
	return allowedValues[normalizedValue] == true
end

function HazardRuntime.Register(rootInstance, controller)
	if typeof(rootInstance) ~= "Instance" or type(controller) ~= "table" then
		return false
	end

	controllersByRoot[rootInstance] = controller
	return true
end

function HazardRuntime.Unregister(rootInstance)
	if typeof(rootInstance) ~= "Instance" then
		return
	end

	controllersByRoot[rootInstance] = nil
end

function HazardRuntime.GetController(instance)
	local current = instance

	while current and current ~= workspace do
		local controller = controllersByRoot[current]
		if controller then
			return current, controller
		end

		current = current.Parent
	end

	return nil, nil
end

function HazardRuntime.GetSharedHazardsFolder()
	return getSharedHazardsFolder()
end

function HazardRuntime.GetServerHazardContext(instance, options)
	if not RunService:IsServer() or typeof(instance) ~= "Instance" then
		return nil, {
			HitInstance = instance,
			Reason = "invalid_instance",
		}
	end

	options = type(options) == "table" and options or {}
	local diagnostics = {
		HitInstance = instance,
		Reason = "unknown",
	}

	local hazardsFolder = typeof(options.HazardsFolder) == "Instance" and options.HazardsFolder or getSharedHazardsFolder()
	if not hazardsFolder then
		diagnostics.Reason = "missing_hazards_folder"
		return nil, diagnostics
	end

	local hazardRoot, hazardClass, hazardType, canFreeze, freezeBehavior = HazardUtils.GetHazardInfo(instance)
	if not hazardRoot or not hazardRoot.Parent then
		diagnostics.Reason = "no_hazard_root"
		return nil, diagnostics
	end

	diagnostics.HazardRoot = hazardRoot
	diagnostics.MatchSource = instance == hazardRoot and "direct" or "ancestor"

	if not hazardRoot:IsDescendantOf(hazardsFolder) then
		diagnostics.Reason = "outside_hazards_folder"
		return nil, diagnostics
	end

	local controllerRoot, controller = HazardRuntime.GetController(hazardRoot)
	if controllerRoot ~= hazardRoot or type(controller) ~= "table" then
		diagnostics.ControllerRoot = controllerRoot
		diagnostics.Reason = "missing_controller"
		return nil, diagnostics
	end

	if controller.Destroyed == true then
		diagnostics.ControllerRoot = controllerRoot
		diagnostics.Reason = "destroyed_controller"
		return nil, diagnostics
	end

	if options.RequireCanFreeze == true and canFreeze ~= true then
		diagnostics.Reason = "not_freezable"
		return nil, diagnostics
	end

	if not matchesStringSet(hazardClass, options.AllowedClasses) then
		diagnostics.Reason = "disallowed_class"
		return nil, diagnostics
	end

	if not matchesStringSet(hazardType, options.AllowedTypes) then
		diagnostics.Reason = "disallowed_type"
		return nil, diagnostics
	end

	local position = getPivotPosition(hazardRoot)
	if position == nil then
		diagnostics.Reason = "missing_position"
		return nil, diagnostics
	end

	diagnostics.RootPosition = position

	local playerRootPosition = options.PlayerRootPosition
	if typeof(playerRootPosition) == "Vector3" then
		local maxPlayerDistance = math.max(0, tonumber(options.MaxPlayerDistance) or 0)
		if maxPlayerDistance > 0 and (position - playerRootPosition).Magnitude > maxPlayerDistance then
			local referencePosition = typeof(options.HitPosition) == "Vector3" and options.HitPosition or position
			diagnostics.DistanceReference = referencePosition == position and "root" or "hit"
			diagnostics.DistancePosition = referencePosition
			diagnostics.DistanceToPlayer = (referencePosition - playerRootPosition).Magnitude
			if diagnostics.DistanceToPlayer > maxPlayerDistance then
				diagnostics.Reason = "too_far_from_player"
				return nil, diagnostics
			end
		end
	end

	local context = {
		Root = hazardRoot,
		Controller = controller,
		HazardClass = hazardClass,
		HazardType = hazardType,
		CanFreeze = canFreeze == true,
		FreezeBehavior = freezeBehavior,
		Position = position,
		MatchSource = diagnostics.MatchSource,
		HitInstance = instance,
		HitPosition = typeof(options.HitPosition) == "Vector3" and options.HitPosition or nil,
	}
	diagnostics.Reason = "ok"
	return context, diagnostics
end

function HazardRuntime.FindHazardsInRadius(centerPosition, radius, options)
	if not RunService:IsServer() or typeof(centerPosition) ~= "Vector3" then
		return {}
	end

	local normalizedRadius = math.clamp(math.max(0, tonumber(radius) or 0), 0, MAX_SERVER_SEARCH_RADIUS)
	if normalizedRadius <= 0 then
		return {}
	end

	options = type(options) == "table" and options or {}
	local hazardsFolder = typeof(options.HazardsFolder) == "Instance" and options.HazardsFolder or getSharedHazardsFolder()
	if not hazardsFolder then
		return {}
	end

	-- Keep the overlap query bounded to the authoritative shared-hazard folder so
	-- invalid or spammed requests cannot fan out across unrelated workspace parts.
	local nearbyParts = Workspace:GetPartBoundsInRadius(
		centerPosition,
		normalizedRadius,
		getHazardOverlapParams(hazardsFolder)
	)

	local seenRoots = {}
	local hazards = {}
	local maxUniqueHazards = math.max(1, math.floor(tonumber(options.MaxUniqueHazards) or MAX_UNIQUE_HAZARDS))

	for _, part in ipairs(nearbyParts) do
		local context = HazardRuntime.GetServerHazardContext(part, {
			HazardsFolder = hazardsFolder,
			RequireCanFreeze = options.RequireCanFreeze,
			AllowedClasses = options.AllowedClasses,
			AllowedTypes = options.AllowedTypes,
			PlayerRootPosition = options.PlayerRootPosition,
			MaxPlayerDistance = options.MaxPlayerDistance,
			HitPosition = part.Position,
		})
		if context and not seenRoots[context.Root] then
			seenRoots[context.Root] = true
			context.DistanceToCenter = (context.Position - centerPosition).Magnitude
			hazards[#hazards + 1] = context
			if #hazards >= maxUniqueHazards then
				break
			end
		end
	end

	table.sort(hazards, function(a, b)
		return (a.DistanceToCenter or math.huge) < (b.DistanceToCenter or math.huge)
	end)

	return hazards
end

function HazardRuntime.FindNearestHazardAlongSegment(startPosition, endPosition, searchRadius, options)
	if not RunService:IsServer() or typeof(startPosition) ~= "Vector3" or typeof(endPosition) ~= "Vector3" then
		return nil, nil
	end

	local delta = endPosition - startPosition
	local distance = delta.Magnitude
	local normalizedRadius = math.clamp(math.max(0.1, tonumber(searchRadius) or 0.1), 0.1, MAX_SERVER_SEARCH_RADIUS)

	if distance <= 0.001 then
		local hazards = HazardRuntime.FindHazardsInRadius(startPosition, normalizedRadius, options)
		return hazards[1], startPosition
	end

	local sampleSpacing = math.max(normalizedRadius * 0.55, 0.5)
	local sampleCount = math.max(1, math.ceil(distance / sampleSpacing))
	sampleCount = math.min(sampleCount, math.max(1, math.floor(tonumber(options and options.MaxSamples) or MAX_SEGMENT_SAMPLES)))

	for sampleIndex = 0, sampleCount do
		local alpha = sampleIndex / sampleCount
		local samplePosition = startPosition:Lerp(endPosition, alpha)
		local hazards = HazardRuntime.FindHazardsInRadius(samplePosition, normalizedRadius, options)
		if hazards[1] then
			return hazards[1], samplePosition
		end
	end

	return nil, nil
end

function HazardRuntime.Freeze(instance, duration)
	local rootInstance, controller = HazardRuntime.GetController(instance)
	if not controller or typeof(controller.Freeze) ~= "function" then
		return false, rootInstance, controller
	end

	return controller:Freeze(duration) ~= false, rootInstance, controller
end

function HazardRuntime.Destroy(instance)
	local rootInstance, controller = HazardRuntime.GetController(instance)
	if not controller or typeof(controller.Destroy) ~= "function" then
		return false, rootInstance, controller
	end

	controller:Destroy()
	return true, rootInstance, controller
end

return HazardRuntime
