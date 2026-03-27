local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local AffectableRegistry = {}

local DEBUG = RunService:IsStudio()
local EPSILON = 1e-4
local entitiesById = {}
local entitiesByRoot = setmetatable({}, { __mode = "k" })
local playerEntitiesByPlayer = setmetatable({}, { __mode = "k" })
local playerConnectionsByPlayer = setmetatable({}, { __mode = "k" })
local started = false
local entitySequence = 0
local DEFAULT_PLAYER_VOLUME_PADDING = Vector3.new(0.5, 0.5, 0.5)

AffectableRegistry.EntityType = {
	Player = "Player",
	Npc = "NPC",
	Hazard = "Hazard",
	Destructible = "Destructible",
	Obstacle = "Obstacle",
}

AffectableRegistry.VolumeType = {
	Box = "Box",
	Sphere = "Sphere",
}

local function formatVector3(value)
	if typeof(value) ~= "Vector3" then
		return tostring(value)
	end

	return string.format("(%.2f, %.2f, %.2f)", value.X, value.Y, value.Z)
end

local function formatInstance(instance)
	if typeof(instance) ~= "Instance" then
		return tostring(instance)
	end

	return instance:GetFullName()
end

local function logMessage(tag, message, ...)
	if not DEBUG then
		return
	end

	print(string.format("[AFFECT][%s] " .. message, tag, ...))
end

local function logQuery(options, tag, message, ...)
	if type(options) ~= "table" or options.DebugEnabled ~= true then
		return
	end

	print(string.format("[AFFECT][%s] " .. message, tag, ...))
end

local function nextEntityId(prefix)
	entitySequence += 1
	return string.format("%s:%d", prefix, entitySequence)
end

local function matchesAllowedValues(value, allowedValues)
	if type(allowedValues) ~= "table" then
		return true
	end

	if allowedValues[value] == true then
		return true
	end

	for _, allowedValue in ipairs(allowedValues) do
		if allowedValue == value then
			return true
		end
	end

	return false
end

local function addPaddingVector(target, value)
	if typeof(value) == "Vector3" then
		return target + Vector3.new(
			math.max(0, value.X),
			math.max(0, value.Y),
			math.max(0, value.Z)
		)
	end

	local scalar = math.max(0, tonumber(value) or 0)
	return target + Vector3.new(scalar, scalar, scalar)
end

local function normalizePadding(volume, options)
	local padding = Vector3.zero
	if type(options) == "table" then
		padding = addPaddingVector(padding, options.VolumePadding)
	end

	if type(volume) == "table" then
		padding = addPaddingVector(padding, volume.Padding)
	end

	return padding
end

local function getPaddingScalar(padding)
	if typeof(padding) == "Vector3" then
		return math.max(padding.X, padding.Y, padding.Z)
	end

	return math.max(0, tonumber(padding) or 0)
end

local function getEntityMetadata(entity)
	return type(entity) == "table" and type(entity.Metadata) == "table" and entity.Metadata or {}
end

local function isEntityActive(entity)
	if type(entity) ~= "table" then
		return false
	end

	local state = entity.IsActive
	if type(state) == "function" then
		local ok, isActive = pcall(state, entity)
		return ok and isActive == true
	end

	if state ~= nil then
		return state == true
	end

	return typeof(entity.RootInstance) == "Instance" and entity.RootInstance.Parent ~= nil
end

local function canEntityMatch(entity, options)
	if not isEntityActive(entity) then
		return false, "inactive"
	end

	if not matchesAllowedValues(entity.EntityType, type(options) == "table" and options.AllowedEntityTypes or nil) then
		return false, "filtered_type"
	end

	local metadata = getEntityMetadata(entity)
	if entity.EntityType == AffectableRegistry.EntityType.Player and options and options.AttackerPlayer ~= nil then
		if metadata.Player == options.AttackerPlayer then
			return false, "self_hit"
		end
	end

	if entity.EntityType == AffectableRegistry.EntityType.Hazard then
		if options and options.RequireCanFreeze == true and metadata.CanFreeze ~= true then
			return false, "not_freezable"
		end

		if not matchesAllowedValues(metadata.HazardClass, options and options.AllowedHazardClasses or nil) then
			return false, "disallowed_hazard_class"
		end

		if not matchesAllowedValues(metadata.HazardType, options and options.AllowedHazardTypes or nil) then
			return false, "disallowed_hazard_type"
		end
	end

	local matcher = entity.CanBeAffectedBy
	if type(matcher) == "function" then
		local ok, canMatch, reason = pcall(matcher, entity, options)
		if not ok then
			return false, "matcher_error"
		end

		if canMatch == false then
			return false, tostring(reason or "matcher_rejected")
		end
	end

	return true, "ok"
end

local function getVolumesForEntity(entity, options)
	if type(entity) ~= "table" then
		return {}
	end

	local provider = entity.GetVolumes
	local volumes
	if type(provider) == "function" then
		local ok, providedVolumes = pcall(provider, entity, options)
		if ok and type(providedVolumes) == "table" then
			volumes = providedVolumes
		else
			volumes = {}
		end
	elseif type(entity.Volumes) == "table" then
		volumes = entity.Volumes
	else
		volumes = {}
	end

	return volumes
end

local function getEntityCenter(entity)
	local metadata = getEntityMetadata(entity)
	local position = metadata.Position
	if typeof(position) == "Vector3" then
		return position
	end

	local rootInstance = entity.RootInstance
	if typeof(rootInstance) ~= "Instance" or not rootInstance.Parent then
		return nil
	end

	if rootInstance:IsA("Model") then
		return rootInstance:GetPivot().Position
	end

	if rootInstance:IsA("BasePart") then
		return rootInstance.Position
	end

	return nil
end

local function resolveEntityData(entity, matchInfo, options)
	if type(entity) ~= "table" then
		return {}
	end

	local resolver = entity.ResolveData
	if type(resolver) ~= "function" then
		return {}
	end

	local ok, resolvedData = pcall(resolver, entity, matchInfo, options)
	if ok and type(resolvedData) == "table" then
		return resolvedData
	end

	return {}
end

local function buildQueryMatch(entity, volume, matchPosition, distance, matchInfo, options)
	matchInfo = type(matchInfo) == "table" and matchInfo or {}
	local resolvedData = resolveEntityData(entity, {
		MatchPosition = matchPosition,
		HitPosition = matchPosition,
		Distance = distance,
		Volume = volume,
		HitInstance = matchInfo.HitInstance,
		MatchedRoot = matchInfo.MatchedRoot,
		MatchSource = matchInfo.MatchSource,
	}, options)
	local hitInstance = typeof(resolvedData.HitInstance) == "Instance" and resolvedData.HitInstance
		or typeof(matchInfo.HitInstance) == "Instance" and matchInfo.HitInstance
		or entity.RootInstance

	return {
		Entity = entity,
		EntityId = entity.EntityId,
		EntityType = entity.EntityType,
		RootInstance = entity.RootInstance,
		Controller = entity.Controller,
		Metadata = getEntityMetadata(entity),
		VolumeType = volume.Type,
		VolumeLabel = volume.Label or volume.Type,
		Label = tostring(resolvedData.Label or entity.EntityId),
		MatchPosition = matchPosition,
		HitPosition = matchPosition,
		HitInstance = hitInstance,
		MatchSource = tostring(resolvedData.MatchSource or matchInfo.MatchSource or "volume"),
		ResolvedData = resolvedData,
		Distance = distance,
		EntityPosition = getEntityCenter(entity),
	}
end

local function getLocalSegmentIntersection(startPosition, endPosition, boxCFrame, boxSize, padding)
	local localStart = boxCFrame:PointToObjectSpace(startPosition)
	local localEnd = boxCFrame:PointToObjectSpace(endPosition)
	local delta = localEnd - localStart
	local paddingVector = typeof(padding) == "Vector3" and padding or Vector3.new(padding, padding, padding)
	local halfSize = (boxSize * 0.5) + paddingVector
	local tMin = 0
	local tMax = 1

	local function applyAxis(startValue, deltaValue, halfValue)
		if math.abs(deltaValue) <= EPSILON then
			return startValue >= -halfValue and startValue <= halfValue, 0, 1
		end

		local inverse = 1 / deltaValue
		local t1 = (-halfValue - startValue) * inverse
		local t2 = (halfValue - startValue) * inverse
		if t1 > t2 then
			t1, t2 = t2, t1
		end

		return true, t1, t2
	end

	for _, axis in ipairs({
		{ localStart.X, delta.X, halfSize.X },
		{ localStart.Y, delta.Y, halfSize.Y },
		{ localStart.Z, delta.Z, halfSize.Z },
	}) do
		local ok, axisMin, axisMax = applyAxis(axis[1], axis[2], axis[3])
		if not ok then
			return nil, nil
		end

		tMin = math.max(tMin, axisMin)
		tMax = math.min(tMax, axisMax)
		if tMin > tMax then
			return nil, nil
		end
	end

	local localHit = localStart + (delta * tMin)
	local worldHit = boxCFrame:PointToWorldSpace(localHit)
	local totalDistance = (endPosition - startPosition).Magnitude
	return worldHit, totalDistance * tMin
end

local function getSegmentSphereIntersection(startPosition, endPosition, centerPosition, radius)
	local segment = endPosition - startPosition
	local totalDistance = segment.Magnitude
	if totalDistance <= EPSILON then
		return nil, nil
	end

	local direction = segment / totalDistance
	local toCenter = centerPosition - startPosition
	local projected = math.clamp(toCenter:Dot(direction), 0, totalDistance)
	local closestPoint = startPosition + (direction * projected)
	local distanceToCenter = (closestPoint - centerPosition).Magnitude
	if distanceToCenter > radius then
		return nil, nil
	end

	local offset = math.sqrt(math.max((radius * radius) - (distanceToCenter * distanceToCenter), 0))
	local hitDistance = math.max(projected - offset, 0)
	return startPosition + (direction * hitDistance), hitDistance
end

local function getRadiusBoxIntersection(centerPosition, radius, boxCFrame, boxSize, padding)
	local localCenter = boxCFrame:PointToObjectSpace(centerPosition)
	local paddingVector = typeof(padding) == "Vector3" and padding or Vector3.new(padding, padding, padding)
	local halfSize = (boxSize * 0.5) + paddingVector
	local clampedLocal = Vector3.new(
		math.clamp(localCenter.X, -halfSize.X, halfSize.X),
		math.clamp(localCenter.Y, -halfSize.Y, halfSize.Y),
		math.clamp(localCenter.Z, -halfSize.Z, halfSize.Z)
	)
	local worldPoint = boxCFrame:PointToWorldSpace(clampedLocal)
	local distance = (worldPoint - centerPosition).Magnitude
	if distance > radius then
		return nil, nil
	end

	return worldPoint, distance
end

local function getRadiusSphereIntersection(centerPosition, radius, sphereCenter, sphereRadius)
	local delta = sphereCenter - centerPosition
	local distance = delta.Magnitude
	if distance > (radius + sphereRadius) then
		return nil, nil
	end

	if distance <= EPSILON then
		return sphereCenter, 0
	end

	local direction = delta / distance
	local point = sphereCenter - (direction * sphereRadius)
	return point, math.max(distance - sphereRadius, 0)
end

local function getBestSegmentMatch(entity, startPosition, endPosition, options)
	local bestMatch = nil

	for _, volume in ipairs(getVolumesForEntity(entity, options)) do
		local padding = normalizePadding(volume, options)
		local queryRadius = math.max(0, tonumber(options and options.QueryRadius) or 0)
		local matchPosition, distance

		if volume.Type == AffectableRegistry.VolumeType.Box
			and typeof(volume.CFrame) == "CFrame"
			and typeof(volume.Size) == "Vector3" then
			matchPosition, distance = getLocalSegmentIntersection(
				startPosition,
				endPosition,
				volume.CFrame,
				volume.Size,
				padding + Vector3.new(queryRadius, queryRadius, queryRadius)
			)
		elseif volume.Type == AffectableRegistry.VolumeType.Sphere
			and typeof(volume.Center) == "Vector3"
			and type(volume.Radius) == "number" then
			matchPosition, distance = getSegmentSphereIntersection(
				startPosition,
				endPosition,
				volume.Center,
				math.max(0, volume.Radius) + getPaddingScalar(padding) + queryRadius
			)
		end

		if matchPosition and distance and (bestMatch == nil or distance < bestMatch.Distance) then
			bestMatch = buildQueryMatch(entity, volume, matchPosition, distance, nil, options)
		end
	end

	return bestMatch
end

local function getBestRadiusMatch(entity, centerPosition, radius, options)
	local bestMatch = nil

	for _, volume in ipairs(getVolumesForEntity(entity, options)) do
		local padding = normalizePadding(volume, options)
		local matchPosition, distance

		if volume.Type == AffectableRegistry.VolumeType.Box
			and typeof(volume.CFrame) == "CFrame"
			and typeof(volume.Size) == "Vector3" then
			matchPosition, distance = getRadiusBoxIntersection(
				centerPosition,
				radius,
				volume.CFrame,
				volume.Size,
				padding
			)
		elseif volume.Type == AffectableRegistry.VolumeType.Sphere
			and typeof(volume.Center) == "Vector3"
			and type(volume.Radius) == "number" then
			matchPosition, distance = getRadiusSphereIntersection(
				centerPosition,
				radius,
				volume.Center,
				math.max(0, volume.Radius) + getPaddingScalar(padding)
			)
		end

		if matchPosition and distance and (bestMatch == nil or distance < bestMatch.Distance) then
			bestMatch = buildQueryMatch(entity, volume, matchPosition, distance, nil, options)
		end
	end

	return bestMatch
end

function AffectableRegistry.RegisterEntity(options)
	options = type(options) == "table" and options or {}

	local rootInstance = options.RootInstance
	if typeof(rootInstance) ~= "Instance" then
		return nil
	end

	local existingByRoot = entitiesByRoot[rootInstance]
	if existingByRoot then
		AffectableRegistry.UnregisterEntity(existingByRoot)
	end

	local entityId = typeof(options.EntityId) == "string" and options.EntityId ~= ""
			and options.EntityId
		or nextEntityId(string.lower(tostring(options.EntityType or "entity")))
	local existingById = entitiesById[entityId]
	if existingById then
		AffectableRegistry.UnregisterEntity(existingById)
	end

	local entity = {
		EntityId = entityId,
		EntityType = tostring(options.EntityType or "Unknown"),
		RootInstance = rootInstance,
		Controller = options.Controller,
		Metadata = type(options.Metadata) == "table" and options.Metadata or {},
		IsActive = options.IsActive,
		CanBeAffectedBy = options.CanBeAffectedBy,
		GetVolumes = options.GetVolumes,
		ResolveData = options.ResolveData,
		Volumes = options.Volumes,
		Player = options.Player,
	}

	entitiesById[entityId] = entity
	entitiesByRoot[rootInstance] = entity

	logMessage(
		"REGISTER",
		"entityId=%s entityType=%s root=%s",
		entity.EntityId,
		entity.EntityType,
		formatInstance(rootInstance)
	)

	return entity
end

function AffectableRegistry.UnregisterEntity(target)
	local entity = nil
	if type(target) == "table" then
		entity = target
	elseif typeof(target) == "Instance" then
		entity = entitiesByRoot[target]
	elseif typeof(target) == "string" then
		entity = entitiesById[target]
	end

	if type(entity) ~= "table" then
		return
	end

	entitiesById[entity.EntityId] = nil
	if typeof(entity.RootInstance) == "Instance" then
		entitiesByRoot[entity.RootInstance] = nil
	end

	logMessage(
		"UNREGISTER",
		"entityId=%s entityType=%s root=%s",
		tostring(entity.EntityId),
		tostring(entity.EntityType),
		formatInstance(entity.RootInstance)
	)
end

function AffectableRegistry.GetEntityByRoot(rootInstance)
	if typeof(rootInstance) ~= "Instance" then
		return nil
	end

	return entitiesByRoot[rootInstance]
end

function AffectableRegistry.GetEntityById(entityId)
	if typeof(entityId) ~= "string" then
		return nil
	end

	return entitiesById[entityId]
end

local function buildPlayerEntity(player, character)
	return {
		EntityId = string.format("player:%d", player.UserId),
		EntityType = AffectableRegistry.EntityType.Player,
		RootInstance = character,
		Player = player,
		Metadata = {
			Player = player,
		},
		IsActive = function(entity)
			local activeCharacter = entity.Player and entity.Player.Character
			if activeCharacter ~= entity.RootInstance or not activeCharacter or not activeCharacter.Parent then
				return false
			end

			local humanoid = activeCharacter:FindFirstChildOfClass("Humanoid")
			local rootPart = activeCharacter:FindFirstChild("HumanoidRootPart")
			return humanoid ~= nil and rootPart ~= nil and humanoid.Health > 0
		end,
		GetVolumes = function(entity)
			local activeCharacter = entity.Player and entity.Player.Character
			if activeCharacter ~= entity.RootInstance or not activeCharacter or not activeCharacter.Parent then
				return {}
			end

			local humanoid = activeCharacter:FindFirstChildOfClass("Humanoid")
			local rootPart = activeCharacter:FindFirstChild("HumanoidRootPart")
			if not humanoid or not rootPart or humanoid.Health <= 0 then
				return {}
			end

			local boxCFrame, boxSize = activeCharacter:GetBoundingBox()
			return {
				{
					Type = AffectableRegistry.VolumeType.Box,
					Label = "CharacterBounds",
					CFrame = boxCFrame,
					Size = boxSize,
					Padding = DEFAULT_PLAYER_VOLUME_PADDING,
				},
			}
		end,
		ResolveData = function(entity, match)
			local activeCharacter = entity.Player and entity.Player.Character
			if activeCharacter ~= entity.RootInstance or not activeCharacter or not activeCharacter.Parent then
				return {}
			end

			local humanoid = activeCharacter:FindFirstChildOfClass("Humanoid")
			local rootPart = activeCharacter:FindFirstChild("HumanoidRootPart")
			if not humanoid or not rootPart or humanoid.Health <= 0 then
				return {}
			end

			return {
				Label = entity.Player.Name,
				Player = entity.Player,
				Character = activeCharacter,
				Humanoid = humanoid,
				RootPart = rootPart,
				HitPosition = match and match.HitPosition or nil,
				MatchSource = match and match.MatchSource or "volume",
			}
		end,
	}
end

local function unregisterPlayerEntity(player)
	local entity = playerEntitiesByPlayer[player]
	if not entity then
		return
	end

	playerEntitiesByPlayer[player] = nil
	AffectableRegistry.UnregisterEntity(entity)
end

local function registerPlayerEntity(player)
	unregisterPlayerEntity(player)

	local character = player.Character
	if not character then
		return
	end

	playerEntitiesByPlayer[player] = AffectableRegistry.RegisterEntity(buildPlayerEntity(player, character))
end

local function disconnectPlayerConnections(player)
	local connections = playerConnectionsByPlayer[player]
	if type(connections) ~= "table" then
		return
	end

	for _, connection in ipairs(connections) do
		if connection then
			connection:Disconnect()
		end
	end

	playerConnectionsByPlayer[player] = nil
end

local function hookPlayer(player)
	disconnectPlayerConnections(player)

	local connections = {
		player.CharacterAdded:Connect(function()
			task.defer(registerPlayerEntity, player)
		end),
		player.CharacterRemoving:Connect(function(character)
			if typeof(character) == "Instance" then
				AffectableRegistry.UnregisterEntity(character)
			end
			playerEntitiesByPlayer[player] = nil
		end),
	}

	playerConnectionsByPlayer[player] = connections

	if player.Character then
		task.defer(registerPlayerEntity, player)
	end
end

function AffectableRegistry.Start()
	if started then
		return
	end

	started = true

	for _, player in ipairs(Players:GetPlayers()) do
		hookPlayer(player)
	end

	Players.PlayerAdded:Connect(function(player)
		hookPlayer(player)
	end)

	Players.PlayerRemoving:Connect(function(player)
		unregisterPlayerEntity(player)
		disconnectPlayerConnections(player)
	end)
end

local function collectMatches(queryKind, options, getMatch)
	AffectableRegistry.Start()

	local matches = {}
	local maxMatches = math.max(1, math.floor(tonumber(options.MaxMatches) or 16))

	for _, entity in pairs(entitiesById) do
		local allowed, reason = canEntityMatch(entity, options)
		if allowed then
			local match = getMatch(entity, options)
			if match then
				matches[#matches + 1] = match
				logQuery(
					options,
					"MATCH",
					"query=%s entityId=%s entityType=%s root=%s volume=%s distance=%.2f match=%s",
					queryKind,
					match.EntityId,
					match.EntityType,
					formatInstance(match.RootInstance),
					tostring(match.VolumeType),
					match.Distance or 0,
					formatVector3(match.MatchPosition)
				)
			end
		else
			logQuery(
				options,
				"MISS",
				"query=%s entityId=%s entityType=%s root=%s reason=%s",
				queryKind,
				tostring(entity.EntityId),
				tostring(entity.EntityType),
				formatInstance(entity.RootInstance),
				tostring(reason)
			)
		end
	end

	table.sort(matches, function(a, b)
		return (a.Distance or math.huge) < (b.Distance or math.huge)
	end)

	while #matches > maxMatches do
		table.remove(matches)
	end

	return matches
end

function AffectableRegistry.QuerySegment(options)
	options = type(options) == "table" and options or {}
	AffectableRegistry.Start()

	local startPosition = options.StartPosition
	local endPosition = options.EndPosition
	if typeof(startPosition) ~= "Vector3" or typeof(endPosition) ~= "Vector3" then
		return {}
	end

	logQuery(
		options,
		"QUERY",
		"query=Segment start=%s end=%s radius=%.2f",
		formatVector3(startPosition),
		formatVector3(endPosition),
		math.max(0, tonumber(options.QueryRadius) or 0)
	)

	local matches = collectMatches("Segment", options, function(entity, queryOptions)
		return getBestSegmentMatch(entity, startPosition, endPosition, queryOptions)
	end)

	if #matches == 0 then
		logQuery(
			options,
			"MISS",
			"query=Segment start=%s end=%s radius=%.2f resultCount=0",
			formatVector3(startPosition),
			formatVector3(endPosition),
			math.max(0, tonumber(options.QueryRadius) or 0)
		)
	end

	return matches
end

function AffectableRegistry.QueryRadius(options)
	options = type(options) == "table" and options or {}
	AffectableRegistry.Start()

	local centerPosition = options.CenterPosition
	local radius = math.max(0, tonumber(options.Radius) or 0)
	if typeof(centerPosition) ~= "Vector3" or radius <= 0 then
		return {}
	end

	logQuery(
		options,
		"QUERY",
		"query=Radius center=%s radius=%.2f",
		formatVector3(centerPosition),
		radius
	)

	local matches = collectMatches("Radius", options, function(entity, queryOptions)
		return getBestRadiusMatch(entity, centerPosition, radius, queryOptions)
	end)

	if #matches == 0 then
		logQuery(
			options,
			"MISS",
			"query=Radius center=%s radius=%.2f resultCount=0",
			formatVector3(centerPosition),
			radius
		)
	end

	return matches
end

local function findRegisteredEntity(instance)
	local current = instance
	while typeof(current) == "Instance" do
		local entity = entitiesByRoot[current]
		if entity then
			return entity, current == instance and "direct" or "ancestor", current
		end

		current = current.Parent
	end

	return nil, "not_registered", nil
end

function AffectableRegistry.GetEntityFromInstance(instance, options)
	options = type(options) == "table" and options or {}
	AffectableRegistry.Start()

	if typeof(instance) ~= "Instance" then
		return nil, "invalid_instance", nil
	end

	local entity, matchSource, matchedRoot = findRegisteredEntity(instance)
	if not entity then
		return nil, matchSource, nil
	end

	local info = {
		Entity = entity,
		EntityId = entity.EntityId,
		EntityType = entity.EntityType,
		RootInstance = entity.RootInstance,
		Controller = entity.Controller,
		Label = entity.EntityId,
		HitInstance = instance,
		MatchedRoot = matchedRoot,
		MatchSource = matchSource,
	}

	local resolvedData = resolveEntityData(entity, {
		HitInstance = instance,
		MatchedRoot = matchedRoot,
		MatchSource = matchSource,
		HitPosition = options.HitPosition,
	}, options)
	info.ResolvedData = resolvedData
	info.Label = tostring(resolvedData.Label or entity.EntityId)

	local allowed, reason = canEntityMatch(entity, options)
	if not allowed then
		return entity, reason, info
	end

	return entity, "ok", info
end

function AffectableRegistry.GetWorldQueryExclusions(options)
	options = type(options) == "table" and options or {}
	AffectableRegistry.Start()

	local exclusions = {}
	local seen = {}

	for _, entity in pairs(entitiesById) do
		local allowed = canEntityMatch(entity, options)
		if allowed then
			local rootInstance = entity.RootInstance
			if typeof(rootInstance) == "Instance" and rootInstance.Parent and not seen[rootInstance] then
				seen[rootInstance] = true
				exclusions[#exclusions + 1] = rootInstance
			end
		end
	end

	return exclusions
end

return AffectableRegistry
