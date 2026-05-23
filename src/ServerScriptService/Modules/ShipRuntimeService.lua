local Players = game:GetService("Players")
Players.CharacterAutoLoads = false

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local DataManager = require(ServerScriptService:WaitForChild("Data"):WaitForChild("DataManager"))
local CrewSlotAssignmentReconciler = require(ServerScriptService.Modules:WaitForChild("CrewSlotAssignmentReconciler"))
local ShipSlotInteractionService = require(ServerScriptService.Modules:WaitForChild("ShipSlotInteractionService"))
local ShipRuntimeSignals = require(ServerScriptService.Modules:WaitForChild("ShipRuntimeSignals"))
local ShipSlotService = require(ServerScriptService.Modules:WaitForChild("ShipSlotService"))
local ShipVisuals = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("ShipVisuals"))
local PlotUpgradeConfig = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("PlotUpgrade"))

local ShipRuntimeService = {}

local PLOT_UPGRADE_STAT_NAME = tostring(PlotUpgradeConfig.InternalStatName or "PlotUpgrade")
local PLOT_UPGRADE_PATH = "HiddenLeaderstats." .. PLOT_UPGRADE_STAT_NAME
local REBIRTH_STAT_NAME = "Rebirths"
local DATA_READY_TIMEOUT_SECONDS = 20
local UPGRADE_VALUE_TIMEOUT_SECONDS = 20
local CHARACTER_SPAWN_TIMEOUT_SECONDS = 10
local RESET_REFRESH_WAIT_TIMEOUT_SECONDS = 8
local SHIP_SPAWN_RETRY_COUNT = 12
local SHIP_SPAWN_RETRY_DELAY_SECONDS = 0.4
local SHIP_READY_RETRY_COUNT = 6
local SHIP_READY_RETRY_DELAY_SECONDS = 0.75
local RUNTIME_SPAWN_LOCATION_ATTRIBUTE = "ShipRuntimeSpawnLocation"

local runtimeStateByPlayer = {}
local pendingRefreshAfterResetByPlayer = setmetatable({}, { __mode = "k" })
local warnedKeys = {}
local started = false

local ATTR = ShipVisuals.Attributes
local RUNTIME_POINTS = ShipVisuals.RuntimePoints or {}
local RUNTIME_POINTS_FOLDER_NAME = tostring(RUNTIME_POINTS.FolderName or "ShipRuntimePoints")
local WORLD_UP = Vector3.new(0, 1, 0)

local function getRuntimeSpawnLocationName()
	local spawnConfig = RUNTIME_POINTS.Spawn or {}
	return tostring(spawnConfig.Name or "ShipSpawnPoint")
end

local function warnOnce(key, message, ...)
	if warnedKeys[key] then
		return
	end

	warnedKeys[key] = true
	warn(string.format(message, ...))
end

local function formatPlayer(player)
	if not player then
		return "<nil>"
	end

	return string.format("%s(%d)", player.Name, player.UserId)
end

local function namesMatchIgnoringCase(left, right)
	return tostring(left or ""):lower() == tostring(right or ""):lower()
end

local function getRuntimeState(player)
	local state = runtimeStateByPlayer[player]
	if not state then
		state = {
			characterConnections = {},
			connections = {},
			position = nil,
			positionIndex = nil,
			respawnRequestId = 0,
			ship = nil,
		}
		runtimeStateByPlayer[player] = state
	end

	return state
end

local function disconnectConnections(connections)
	if typeof(connections) ~= "table" then
		return
	end

	for _, connection in ipairs(connections) do
		if connection and connection.Connected then
			connection:Disconnect()
		end
	end

	table.clear(connections)
end

local function isRuntimeShipSpawnLocation(instance)
	return typeof(instance) == "Instance"
		and instance:IsA("SpawnLocation")
		and instance:GetAttribute(RUNTIME_SPAWN_LOCATION_ATTRIBUTE) == true
end

local function clearPlayerRespawnLocation(player, expectedAncestor)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return
	end

	local respawnLocation = player.RespawnLocation
	if not isRuntimeShipSpawnLocation(respawnLocation) then
		return
	end

	if expectedAncestor and respawnLocation.Parent and not respawnLocation:IsDescendantOf(expectedAncestor) then
		return
	end

	player.RespawnLocation = nil
end

local function makeRefreshFailure(reason, details)
	local safeReason = tostring(reason or "unknown_error")
	local payload = if typeof(details) == "table" then table.clone(details) else {}
	payload.Reason = safeReason
	return false, safeReason, payload
end

local function cloneRefreshOptions(options)
	local clone = {}
	if typeof(options) == "table" then
		for key, value in pairs(options) do
			clone[key] = value
		end
	end
	clone.AllowDuringReset = nil
	return clone
end

local function mergeRefreshOptions(current, incoming)
	current = if typeof(current) == "table" then current else {}
	incoming = if typeof(incoming) == "table" then incoming else {}

	for key, value in pairs(incoming) do
		if key == "ForceReplace" or key == "TeleportAfterReplace" then
			if value == true then
				current[key] = true
			elseif current[key] == nil then
				current[key] = value
			end
		elseif key ~= "AllowDuringReset" then
			current[key] = value
		end
	end

	if current.Reason == nil then
		current.Reason = "queued_after_reset"
	end

	return current
end

local function disconnectPlayerState(player)
	local state = runtimeStateByPlayer[player]
	if not state then
		return
	end

	disconnectConnections(state.characterConnections)
	disconnectConnections(state.connections)
end

local function getAssetFolder()
	local current = ReplicatedStorage

	for _, segment in ipairs(ShipVisuals.AssetPath or {}) do
		current = current and current:FindFirstChild(segment)
		if not current then
			warnOnce(
				"missing_asset_path",
				"[ShipRuntimeService] Missing ship asset folder %s; active ships will not spawn.",
				ShipVisuals.GetAssetPathLabel()
			)
			return nil
		end
	end

	return current
end

local function resolveWorkspacePath(pathSegments)
	local current = Workspace

	for _, segment in ipairs(pathSegments or {}) do
		current = current and current:FindFirstChild(segment)
		if not current then
			return nil
		end
	end

	return current
end

local function getShipSystem()
	local shipSystem = resolveWorkspacePath(ShipVisuals.ShipSystemPath)
	if not shipSystem then
		warnOnce(
			"missing_ship_system",
			"[ShipRuntimeService] Missing Workspace.%s; active ships will not spawn.",
			table.concat(ShipVisuals.ShipSystemPath or {}, ".")
		)
	end

	return shipSystem
end

local function getShipSystemFolders()
	local shipSystem = getShipSystem()
	if not shipSystem then
		return nil, nil, nil
	end

	local activeShips = shipSystem:FindFirstChild(ShipVisuals.ActiveShipsName)
	if not activeShips then
		warnOnce(
			"missing_active_ships",
			"[ShipRuntimeService] Missing %s.%s; active ships will not spawn.",
			shipSystem:GetFullName(),
			ShipVisuals.ActiveShipsName
		)
		return shipSystem, nil, nil
	end

	local positions = shipSystem:FindFirstChild(ShipVisuals.ShipPositionsName)
	if not positions then
		warnOnce(
			"missing_ship_positions",
			"[ShipRuntimeService] Missing %s.%s; active ships will not spawn.",
			shipSystem:GetFullName(),
			ShipVisuals.ShipPositionsName
		)
		return shipSystem, activeShips, nil
	end

	return shipSystem, activeShips, positions
end

local function getSortedShipPositions()
	local _, _, positionsFolder = getShipSystemFolders()
	if not positionsFolder then
		return {}
	end

	local positions = {}

	for _, child in ipairs(positionsFolder:GetChildren()) do
		if child.Name == ShipVisuals.ShipPositionName and child:IsA("BasePart") then
			positions[#positions + 1] = child
		end
	end

	table.sort(positions, function(left, right)
		local leftPosition = left.Position
		local rightPosition = right.Position

		if leftPosition.X ~= rightPosition.X then
			return leftPosition.X < rightPosition.X
		end

		if leftPosition.Z ~= rightPosition.Z then
			return leftPosition.Z < rightPosition.Z
		end

		return leftPosition.Y < rightPosition.Y
	end)

	if #positions == 0 then
		warnOnce(
			"no_ship_positions",
			"[ShipRuntimeService] No BasePart named %s found under ShipPositions.",
			ShipVisuals.ShipPositionName
		)
	end

	return positions
end

local function getActiveShipsFolder()
	local _, activeShips = getShipSystemFolders()
	return activeShips
end

local function getActiveShipsForPlayer(player)
	local activeShips = getActiveShipsFolder()
	if not activeShips then
		return {}
	end

	local ships = {}

	for _, child in ipairs(activeShips:GetChildren()) do
		if child:IsA("Model") and child:GetAttribute(ATTR.OwnerUserId) == player.UserId then
			ships[#ships + 1] = child
		end
	end

	return ships
end

local function getRuntimeName(player)
	return string.format("%s_%d", tostring(ShipVisuals.RuntimeModelName or "ActiveShip"), player.UserId)
end

local function getPositionIndexForInstance(positions, position)
	if not position then
		return nil
	end

	for index, candidate in ipairs(positions) do
		if candidate == position then
			return index
		end
	end

	return nil
end

local function getOccupiedPositionIndexes(playerToIgnore)
	local occupied = {}
	local positions = getSortedShipPositions()
	local activeShips = getActiveShipsFolder()

	if activeShips then
		for _, child in ipairs(activeShips:GetChildren()) do
			local ownerUserId = child:GetAttribute(ATTR.OwnerUserId)
			if ownerUserId and (not playerToIgnore or ownerUserId ~= playerToIgnore.UserId) then
				local positionIndex = tonumber(child:GetAttribute(ATTR.PositionIndex))
				if positionIndex then
					occupied[positionIndex] = true
				end
			end
		end
	end

	for player, state in pairs(runtimeStateByPlayer) do
		if player ~= playerToIgnore then
			local positionIndex = state.positionIndex or getPositionIndexForInstance(positions, state.position)
			if positionIndex then
				occupied[positionIndex] = true
			end
		end
	end

	return occupied, positions
end

local function assignPosition(player)
	local state = getRuntimeState(player)
	local occupied, positions = getOccupiedPositionIndexes(player)

	if state.position and state.position.Parent then
		local stateIndex = state.positionIndex or getPositionIndexForInstance(positions, state.position)
		if stateIndex and not occupied[stateIndex] then
			state.positionIndex = stateIndex
			return state.position, stateIndex
		end
	end

	local activeShip = ShipRuntimeService.GetActiveShip(player)
	local activeShipPositionIndex = activeShip and tonumber(activeShip:GetAttribute(ATTR.PositionIndex))
	if activeShipPositionIndex and positions[activeShipPositionIndex] then
		state.position = positions[activeShipPositionIndex]
		state.positionIndex = activeShipPositionIndex
		return state.position, state.positionIndex
	end

	for index, position in ipairs(positions) do
		if not occupied[index] then
			state.position = position
			state.positionIndex = index
			return position, index
		end
	end

	warnOnce(
		"no_free_position_" .. tostring(player.UserId),
		"[ShipRuntimeService] No free ShipPositions.Pos available for %s.",
		formatPlayer(player)
	)

	return nil, nil
end

local function resolveSourceModel(upgradeLevel)
	local assetFolder = getAssetFolder()
	if not assetFolder then
		return nil, nil
	end

	local missingVisual

	for _, visual in ipairs(ShipVisuals.GetFallbackVisualsForUpgradeLevel(upgradeLevel)) do
		local model = assetFolder:FindFirstChild(visual.ModelName)
		if model and model:IsA("Model") then
			if missingVisual then
				warnOnce(
					"ship_fallback_" .. tostring(upgradeLevel),
					"[ShipRuntimeService] Missing %s for PlotUpgrade %s; falling back to %s.",
					missingVisual.ModelName,
					tostring(upgradeLevel),
					visual.ModelName
				)
			end

			return model, visual
		end

		missingVisual = missingVisual or visual
		warnOnce(
			"missing_ship_model_" .. tostring(visual.ModelName),
			"[ShipRuntimeService] Missing ship model %s.%s.",
			ShipVisuals.GetAssetPathLabel(),
			visual.ModelName
		)
	end

	return nil, nil
end

local function partHasInteraction(part)
	return ShipSlotService.IsInteractionPart(part)
end

local function isNamedWalkableCollisionFolder(instance)
	local normalizedName = ShipSlotService.NormalizeInstanceName(instance and instance.Name or "")

	for _, folderName in ipairs(ShipVisuals.WalkableCollisionFolderNames or {}) do
		if normalizedName == ShipSlotService.NormalizeInstanceName(folderName) then
			return true
		end
	end

	return false
end

local function isUnderWalkableCollisionFolder(instance)
	local current = instance and instance.Parent

	while current do
		if isNamedWalkableCollisionFolder(current) then
			return true
		end

		current = current.Parent
	end

	return false
end

local function isNamedNoCollisionFolder(instance)
	local normalizedName = ShipSlotService.NormalizeInstanceName(instance and instance.Name or "")

	for _, folderName in ipairs(ShipVisuals.NoCollisionFolderNames or {}) do
		if normalizedName == ShipSlotService.NormalizeInstanceName(folderName) then
			return true
		end
	end

	return false
end

local function isUnderNoCollisionFolder(instance)
	local current = instance and instance.Parent

	while current do
		if isNamedNoCollisionFolder(current) then
			return true
		end

		current = current.Parent
	end

	return false
end

local function isWalkableCollisionPart(part)
	local safetyAttributes = ShipVisuals.RuntimeSafetyAttributes or {}

	return part:GetAttribute(safetyAttributes.PreserveCollision) == true
		or part:GetAttribute(safetyAttributes.WalkableCollision) == true
		or isUnderWalkableCollisionFolder(part)
end

local function isForcedNoCollisionPart(part)
	local safetyAttributes = ShipVisuals.RuntimeSafetyAttributes or {}

	return part:GetAttribute(safetyAttributes.ForceNoCollision) == true or isUnderNoCollisionFolder(part)
end

local function sanitizeRuntimeClone(model)
	local preservePhysics = model:GetAttribute(ShipVisuals.RuntimeSafetyAttributes.PreservePhysics) == true
	local allowScripts = model:GetAttribute(ShipVisuals.RuntimeSafetyAttributes.AllowScripts) == true
	local walkableCollisionParts = 0
	local runtimeCollidableParts = 0

	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") then
			local interactive = partHasInteraction(descendant)
			local walkableCollision = isWalkableCollisionPart(descendant)
			local forcedNoCollision = isForcedNoCollisionPart(descendant)

			if not preservePhysics then
				descendant.Anchored = true
			end

			if forcedNoCollision then
				descendant.CanCollide = false
			elseif walkableCollision then
				walkableCollisionParts += 1
				descendant.CanCollide = true
				descendant.CanTouch = descendant:GetAttribute(ShipVisuals.RuntimeSafetyAttributes.PreserveTouch) == true
				descendant.CanQuery = true
			end

			if not walkableCollision and descendant:GetAttribute(ShipVisuals.RuntimeSafetyAttributes.PreserveTouch) ~= true and not interactive then
				descendant.CanTouch = false
			end

			if not walkableCollision and descendant:GetAttribute(ShipVisuals.RuntimeSafetyAttributes.PreserveQuery) ~= true and not interactive then
				descendant.CanQuery = false
			end

			if descendant.CanCollide then
				runtimeCollidableParts += 1
			end
		elseif not allowScripts and (descendant:IsA("Script") or descendant:IsA("LocalScript")) then
			descendant.Disabled = true
		end
	end

	model:SetAttribute("ShipWalkableCollisionParts", walkableCollisionParts)
	model:SetAttribute("ShipRuntimeCollidableParts", runtimeCollidableParts)
	return runtimeCollidableParts
end

local function warnIfMissingWalkableCollision(model, visual)
	local count = tonumber(model:GetAttribute("ShipRuntimeCollidableParts")) or 0
	if count > 0 then
		return
	end

	warnOnce(
		"missing_walkable_collision_" .. tostring(visual and visual.ModelName or model.Name),
		"[ShipRuntimeService] %s has no collidable parts after runtime sanitization. Players may fall through unless the ship asset keeps authored collision or adds ShipCollision/WalkableCollision parts.",
		tostring(visual and visual.ModelName or model.Name)
	)
end

local function applyRuntimeAttributes(model, player, visual, upgradeLevel, positionIndex, position)
	model:SetAttribute(ATTR.IsActiveShip, true)
	model:SetAttribute(ATTR.OwnerUserId, player.UserId)
	model:SetAttribute(ATTR.OwnerName, player.Name)
	model:SetAttribute(ATTR.ActiveModelName, visual.ModelName)
	model:SetAttribute(ATTR.ActiveTier, visual.Tier)
	model:SetAttribute(ATTR.ActiveUpgradeLevel, upgradeLevel)
	model:SetAttribute(ATTR.SourceModelName, visual.ModelName)
	model:SetAttribute(ATTR.SourceTier, visual.Tier)
	model:SetAttribute(ATTR.PositionIndex, positionIndex)
	model:SetAttribute(ATTR.NormalCrewSlots, visual.NormalCrewSlots)
	model:SetAttribute(ATTR.AssetNormalSlotCapacity, visual.AssetNormalSlotCapacity)

	if position then
		model:SetAttribute(ATTR.PositionName, position.Name)
	end
end

local function getRuntimePointsFolder(activeShip)
	local folder = activeShip:FindFirstChild(RUNTIME_POINTS_FOLDER_NAME)
	if folder and not folder:IsA("Folder") then
		folder:Destroy()
		folder = nil
	end

	if not folder then
		folder = Instance.new("Folder")
		folder.Name = RUNTIME_POINTS_FOLDER_NAME
		folder.Parent = activeShip
	end

	return folder
end

local function getInstanceCFrame(instance)
	if not instance then
		return nil
	end

	if instance:IsA("BasePart") then
		return instance.CFrame
	end

	if instance:IsA("Attachment") then
		return instance.WorldCFrame
	end

	if instance:IsA("Model") then
		return instance:GetPivot()
	end

	return nil
end

local function isRuntimePointDescendant(activeShip, instance)
	local folder = activeShip and activeShip:FindFirstChild(RUNTIME_POINTS_FOLDER_NAME)
	return folder ~= nil and instance ~= nil and instance:IsDescendantOf(folder)
end

local function findMarkerByName(activeShip, markerName)
	if not activeShip then
		return nil
	end

	markerName = tostring(markerName or "")
	if markerName == "" then
		return nil
	end

	local directMarker = activeShip:FindFirstChild(markerName, true)
	if directMarker
		and not isRuntimePointDescendant(activeShip, directMarker)
		and getInstanceCFrame(directMarker) ~= nil
	then
		return directMarker
	end

	for _, descendant in ipairs(activeShip:GetDescendants()) do
		if descendant.Name == markerName
			and not isRuntimePointDescendant(activeShip, descendant)
			and getInstanceCFrame(descendant) ~= nil
		then
			return descendant
		end
	end

	for _, descendant in ipairs(activeShip:GetDescendants()) do
		if namesMatchIgnoringCase(descendant.Name, markerName)
			and not isRuntimePointDescendant(activeShip, descendant)
			and getInstanceCFrame(descendant) ~= nil
		then
			return descendant
		end
	end

	return nil
end

local function findMarkerCFrame(activeShip, markerNames)
	for _, markerName in ipairs(markerNames or {}) do
		markerName = tostring(markerName)
		local marker = findMarkerByName(activeShip, markerName)
		local markerCFrame = getInstanceCFrame(marker)
		if markerCFrame then
			return markerCFrame, marker, marker.Name
		end
	end

	return nil, nil
end

local function getConfigVector3(value, fallback)
	return if typeof(value) == "Vector3" then value else fallback
end

local function horizontalUnit(vector, fallback)
	local horizontal = Vector3.new(vector.X, 0, vector.Z)
	if horizontal.Magnitude > 0.001 then
		return horizontal.Unit
	end

	return fallback
end

local function getFallbackFacingVector(boxCFrame, position, fallbackConfig)
	local fallback = fallbackConfig or {}
	local mode = tostring(fallback.Facing or "Outward")
	local forward = horizontalUnit(boxCFrame.LookVector, Vector3.new(0, 0, -1))
	local right = horizontalUnit(boxCFrame.RightVector, Vector3.new(1, 0, 0))

	if mode == "Forward" then
		return forward
	elseif mode == "Backward" then
		return -forward
	elseif mode == "Right" then
		return right
	elseif mode == "Left" then
		return -right
	end

	return horizontalUnit(position - boxCFrame.Position, forward)
end

local function applyPointFacingCorrection(cframe, pointConfig, usedMarker)
	local degrees = tonumber(pointConfig.FacingCorrectionDegrees) or 0
	if usedMarker and pointConfig.MarkerFacingCorrectionDegrees ~= nil then
		degrees = tonumber(pointConfig.MarkerFacingCorrectionDegrees) or 0
	elseif not usedMarker and pointConfig.FallbackFacingCorrectionDegrees ~= nil then
		degrees = tonumber(pointConfig.FallbackFacingCorrectionDegrees) or 0
	end

	if degrees ~= 0 then
		cframe *= CFrame.Angles(0, math.rad(degrees), 0)
	end

	local rotationOffset = if usedMarker then pointConfig.MarkerRotationOffset else pointConfig.FallbackRotationOffset
	if typeof(rotationOffset) == "CFrame" then
		cframe *= rotationOffset
	end

	return cframe
end

local function getBoundingBoxFallbackCFrame(activeShip, pointConfig)
	local fallback = pointConfig.Fallback
	if typeof(fallback) ~= "table" then
		return activeShip:GetPivot() * (pointConfig.Offset or CFrame.new())
	end

	local boxCFrame, boxSize = activeShip:GetBoundingBox()
	local positionScale = getConfigVector3(fallback.PositionScale, Vector3.new(0, 0.5, 0))
	local localOffset = getConfigVector3(fallback.LocalOffset, Vector3.new())
	local worldOffset = getConfigVector3(fallback.WorldOffset, Vector3.new())
	local scaledOffset = Vector3.new(
		boxSize.X * positionScale.X,
		boxSize.Y * positionScale.Y,
		boxSize.Z * positionScale.Z
	)
	local position = boxCFrame:PointToWorldSpace(scaledOffset + localOffset) + worldOffset
	local facing = getFallbackFacingVector(boxCFrame, position, fallback)

	return CFrame.lookAt(position, position + facing, WORLD_UP)
end

local function warnForRuntimePointMarker(activeShip, pointKey, pointConfig, markerName)
	local preferredMarkerName = tostring(pointConfig.PreferredMarkerName or "")
	if preferredMarkerName == "" or markerName == preferredMarkerName or namesMatchIgnoringCase(markerName, preferredMarkerName) then
		return
	end

	local shipName = tostring(activeShip:GetAttribute(ATTR.ActiveModelName) or activeShip.Name)
	local pointName = tostring(pointConfig.Name or pointKey)
	local fallbackLabel = if markerName and markerName ~= "" then markerName else "bounding-box fallback"

	warnOnce(
		string.format("missing_runtime_marker_%s_%s", shipName, tostring(pointKey)),
		"[ShipRuntimeService] %s is missing preferred marker %s for %s; using %s. Add a dedicated invisible marker for precise placement.",
		shipName,
		preferredMarkerName,
		pointName,
		fallbackLabel
	)
end

local function warnForMissingRequiredRuntimePointMarker(activeShip, pointKey, pointConfig)
	local shipName = tostring(activeShip:GetAttribute(ATTR.ActiveModelName) or activeShip.Name)
	local pointName = tostring(pointConfig.Name or pointKey)
	local markerLabel = tostring(pointConfig.PreferredMarkerName or pointKey)

	warnOnce(
		string.format("missing_required_runtime_marker_%s_%s", shipName, tostring(pointKey)),
		"[ShipRuntimeService] %s has no valid %s marker for %s; player spawning is blocked until the asset provides one.",
		shipName,
		markerLabel,
		pointName
	)
end

local function applyMarkerPointOffset(cframe, pointConfig)
	local markerWorldOffset = pointConfig.MarkerWorldOffset
	if typeof(markerWorldOffset) == "Vector3" then
		cframe = cframe + markerWorldOffset
	end

	local markerOffset = pointConfig.MarkerOffset
	if typeof(markerOffset) == "CFrame" then
		cframe *= markerOffset
	end

	return cframe
end

local function resolveRuntimePoint(activeShip, pointKey, pointConfig)
	local markerCFrame, marker, markerName = findMarkerCFrame(activeShip, pointConfig.MarkerNames)
	if markerCFrame then
		warnForRuntimePointMarker(activeShip, pointKey, pointConfig, markerName)
		local cframe = applyMarkerPointOffset(markerCFrame, pointConfig)
		return marker, applyPointFacingCorrection(cframe, pointConfig, true)
	end

	warnForRuntimePointMarker(activeShip, pointKey, pointConfig, nil)
	return nil, applyPointFacingCorrection(getBoundingBoxFallbackCFrame(activeShip, pointConfig), pointConfig, false)
end

local function resolveRequiredRuntimePoint(activeShip, pointKey, pointConfig)
	local markerCFrame, marker, markerName = findMarkerCFrame(activeShip, pointConfig.MarkerNames)
	if not markerCFrame then
		warnForMissingRequiredRuntimePointMarker(activeShip, pointKey, pointConfig)
		return nil, nil, "missing_ship_spawn_marker", {
			ActiveShip = activeShip,
			PointKey = pointKey,
		}
	end

	warnForRuntimePointMarker(activeShip, pointKey, pointConfig, markerName)
	local cframe = applyMarkerPointOffset(markerCFrame, pointConfig)
	return marker, applyPointFacingCorrection(cframe, pointConfig, true)
end

local function resolveRuntimePointCFrame(activeShip, pointKey, pointConfig)
	local _, cframe = resolveRuntimePoint(activeShip, pointKey, pointConfig)
	return cframe
end

local function ensureRuntimePart(parent, name, cframe, size)
	local part = parent:FindFirstChild(name)
	if part and not part:IsA("BasePart") then
		part:Destroy()
		part = nil
	end

	if not part then
		part = Instance.new("Part")
		part.Name = name
		part.Parent = parent
	end

	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Transparency = 1
	part.Size = size or Vector3.new(2, 2, 2)
	part.CFrame = cframe

	return part
end

local function ensureRuntimeSpawnLocation(parent, name, cframe, size)
	local spawnLocation = parent:FindFirstChild(name)
	if spawnLocation and not spawnLocation:IsA("SpawnLocation") then
		spawnLocation:Destroy()
		spawnLocation = nil
	end

	if not spawnLocation then
		spawnLocation = Instance.new("SpawnLocation")
		spawnLocation.Name = name
		spawnLocation.Parent = parent
	end

	spawnLocation:SetAttribute(RUNTIME_SPAWN_LOCATION_ATTRIBUTE, true)
	spawnLocation.Anchored = true
	spawnLocation.CanCollide = false
	spawnLocation.CanQuery = false
	spawnLocation.CanTouch = false
	spawnLocation.CastShadow = false
	spawnLocation.Transparency = 1
	spawnLocation.Size = size or Vector3.new(4, 1, 4)
	spawnLocation.CFrame = cframe
	spawnLocation.AllowTeamChangeOnTouch = false
	spawnLocation.Duration = 0
	spawnLocation.Enabled = true
	spawnLocation.Neutral = true

	return spawnLocation
end

local function getRuntimeSpawnLocation(activeShip)
	local folder = activeShip and activeShip:FindFirstChild(RUNTIME_POINTS_FOLDER_NAME)
	local spawnLocation = folder and folder:FindFirstChild(getRuntimeSpawnLocationName())
	if isRuntimeShipSpawnLocation(spawnLocation)
		and spawnLocation:IsDescendantOf(activeShip)
	then
		return spawnLocation
	end

	return nil
end

local function getShipOwnerDisplayText(player)
	local ownerName = player and tostring(player.Name or "") or ""
	if ownerName == "" then
		ownerName = "Player"
	end

	return ownerName .. "'s"
end

local function ensurePlayerDisplayCard(parent, player, options)
	options = options or {}

	local frame = parent:FindFirstChild("PlayerDisplay")
	if frame and not frame:IsA("Frame") then
		frame:Destroy()
		frame = nil
	end

	if not frame then
		frame = Instance.new("Frame")
		frame.Name = "PlayerDisplay"
		frame.Parent = parent
	end

	frame.BackgroundColor3 = Color3.fromRGB(18, 18, 18)
	frame.BackgroundTransparency = 0.2
	frame.BorderSizePixel = 0
	frame.Position = options.Position or UDim2.fromScale(0, 0)
	frame.Size = options.Size or UDim2.fromScale(1, 1)
	frame.Visible = if options.Visible ~= nil then options.Visible else true

	local playerName = frame:FindFirstChild("PlayerName")
	if playerName and not playerName:IsA("TextLabel") then
		playerName:Destroy()
		playerName = nil
	end

	if not playerName then
		playerName = Instance.new("TextLabel")
		playerName.Name = "PlayerName"
		playerName.Parent = frame
	end

	playerName.BackgroundTransparency = 1
	playerName.Position = UDim2.fromScale(0.3, 0.12)
	playerName.Size = UDim2.fromScale(0.66, 0.76)
	playerName.Font = Enum.Font.GothamBold
	playerName.TextColor3 = Color3.fromRGB(255, 255, 255)
	playerName.TextScaled = true
	playerName.TextStrokeTransparency = 0.45
	playerName.Text = getShipOwnerDisplayText(player)

	local playerIcon = frame:FindFirstChild("PlayerIcon")
	if playerIcon and not playerIcon:IsA("ImageLabel") then
		playerIcon:Destroy()
		playerIcon = nil
	end

	if not playerIcon then
		playerIcon = Instance.new("ImageLabel")
		playerIcon.Name = "PlayerIcon"
		playerIcon.Parent = frame
	end

	playerIcon.BackgroundTransparency = 1
	playerIcon.Position = UDim2.fromScale(0.04, 0.16)
	playerIcon.Size = UDim2.fromScale(0.22, 0.68)
	playerIcon.Image = "rbxthumb://type=AvatarHeadShot&id=" .. player.UserId .. "&w=150&h=150"

	return frame
end

local function ensureHomeIndicator(homePart, player)
	local billboard = homePart:FindFirstChild("BillboardGui")
	if billboard and not billboard:IsA("BillboardGui") then
		billboard:Destroy()
		billboard = nil
	end

	if not billboard then
		billboard = Instance.new("BillboardGui")
		billboard.Name = "BillboardGui"
		billboard.AlwaysOnTop = true
		billboard.MaxDistance = 250
		billboard.StudsOffsetWorldSpace = Vector3.new(0, 0, 0)
		billboard.Parent = homePart
	end
	billboard.Size = UDim2.fromOffset(190, 76)

	local imageLabel = billboard:FindFirstChild("ImageLabel")
	if imageLabel then
		imageLabel:Destroy()
	end

	ensurePlayerDisplayCard(billboard, player, {
		Visible = false,
	})
end

local function ensureGroupRewardPoint(folder, activeShip)
	local config = RUNTIME_POINTS.GroupReward or {}
	local modelName = tostring(config.Name or "GroupReward")
	local model = folder:FindFirstChild(modelName)
	if model and not model:IsA("Model") then
		model:Destroy()
		model = nil
	end

	if not model then
		model = Instance.new("Model")
		model.Name = modelName
		model.Parent = folder
	end

	local hitboxName = tostring(config.HitboxName or "Hitbox")
	local hitbox = ensureRuntimePart(
		model,
		hitboxName,
		resolveRuntimePointCFrame(activeShip, "GroupReward", config),
		config.Size or Vector3.new(6, 6, 6)
	)

	local prompt = hitbox:FindFirstChildOfClass("ProximityPrompt")
	if not prompt then
		prompt = Instance.new("ProximityPrompt")
		prompt.Name = "ProximityPrompt"
		prompt.Parent = hitbox
	end

	prompt.ActionText = "Claim"
	prompt.ObjectText = "Group Reward"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt.Enabled = true

	model.PrimaryPart = hitbox
	return model, hitbox
end

local function removeRuntimeOwnerSign(folder)
	local signConfig = RUNTIME_POINTS.OwnerSign or {}
	local signName = tostring(signConfig.Name or "ShipOwnerSign")
	local signPart = folder:FindFirstChild(signName)
	if signPart then
		signPart:Destroy()
	end
end

local function ensureRuntimePoints(player, activeShip)
	local folder = getRuntimePointsFolder(activeShip)

	local spawnConfig = RUNTIME_POINTS.Spawn or {}
	local _, spawnCFrame, spawnReason, spawnDetails = resolveRequiredRuntimePoint(activeShip, "Spawn", spawnConfig)
	if not spawnCFrame then
		clearPlayerRespawnLocation(player, activeShip)
		return nil, spawnReason or "missing_ship_spawn_marker", spawnDetails
	end

	local spawnPart = ensureRuntimeSpawnLocation(
		folder,
		getRuntimeSpawnLocationName(),
		spawnCFrame,
		spawnConfig.Size or Vector3.new(4, 1, 4)
	)
	if not isRuntimeShipSpawnLocation(spawnPart) then
		clearPlayerRespawnLocation(player, activeShip)
		return nil, "invalid_runtime_spawn_location", {
			ActiveShip = activeShip,
			SpawnLocation = spawnPart,
		}
	end

	player.RespawnLocation = spawnPart

	ensureGroupRewardPoint(folder, activeShip)

	local homeConfig = RUNTIME_POINTS.Home or {}
	local homePart = ensureRuntimePart(
		folder,
		tostring(homeConfig.Name or "HOME"),
		resolveRuntimePointCFrame(activeShip, "Home", homeConfig),
		homeConfig.Size or Vector3.new(2, 2, 2)
	)
	ensureHomeIndicator(homePart, player)

	removeRuntimeOwnerSign(folder)

	return {
		Spawn = spawnPart,
		Home = homePart,
	}
end

local function getUpgradeValueObject(player)
	local hiddenLeaderstats = player:FindFirstChild("HiddenLeaderstats")
	if not hiddenLeaderstats then
		return nil
	end

	local valueObject = hiddenLeaderstats:FindFirstChild(PLOT_UPGRADE_STAT_NAME)
	if valueObject and valueObject:IsA("ValueBase") then
		return valueObject
	end

	return nil
end

local function getRebirthValueObject(player)
	local leaderstats = player:FindFirstChild("leaderstats")
	if not leaderstats then
		return nil
	end

	local valueObject = leaderstats:FindFirstChild(REBIRTH_STAT_NAME)
	if valueObject and valueObject:IsA("ValueBase") then
		return valueObject
	end

	return nil
end

local function getUpgradeLevel(player)
	local valueObject = getUpgradeValueObject(player)
	if valueObject then
		return PlotUpgradeConfig.ClampLevel(valueObject.Value)
	end

	local storedUpgrade = DataManager:GetValue(player, PLOT_UPGRADE_PATH)
	return PlotUpgradeConfig.ClampLevel(storedUpgrade)
end

local function runStandRefresh(player)
	local standCommand = ShipRuntimeSignals.GetStandCommandFunction()
	if not standCommand or not standCommand:IsA("BindableFunction") then
		return false, "stand_refresh_missing", {
			Reason = "stand_refresh_missing",
		}
	end

	local ok, result, reason = xpcall(function()
		return standCommand:Invoke("refresh", player)
	end, debug.traceback)

	if not ok then
		return false, "stand_refresh_failed", {
			Reason = "stand_refresh_failed",
			Error = tostring(result),
		}
	end

	if result == false then
		return false, tostring(reason or "stand_refresh_failed"), {
			Reason = tostring(reason or "stand_refresh_failed"),
		}
	end

	return true, reason or result
end

local function invokeStandRefresh(player)
	local ok, reason, details = runStandRefresh(player)
	if ok then
		return true, reason
	end

	task.delay(0.25, function()
		if player.Parent ~= Players then
			return
		end

		local retryOk, retryReason, retryDetails = runStandRefresh(player)
		if retryOk then
			return
		end

		local detailText = if typeof(retryDetails) == "table" and retryDetails.Error
			then tostring(retryDetails.Error)
			else tostring(retryReason)
		warn(("[ShipRuntimeService] Failed to refresh crew slots for %s after ship refresh: %s"):format(
			formatPlayer(player),
			detailText
		))
	end)

	return false, reason, details
end

local function refreshSlotInteractions(player, activeShip, upgradeLevel)
	local ok, err = xpcall(function()
		ShipSlotInteractionService.RefreshPlayerShip(player, activeShip, {
			UpgradeLevel = upgradeLevel,
		})
	end, debug.traceback)

	if ok then
		return true
	end

	return false, tostring(err)
end

local function queueRefreshAfterReset(player, options)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return false, "invalid_player"
	end

	if not CrewSlotAssignmentReconciler.IsResetInProgress(player) then
		return false, "reset_not_in_progress"
	end

	local queued = pendingRefreshAfterResetByPlayer[player]
	if queued then
		queued.Options = mergeRefreshOptions(queued.Options, cloneRefreshOptions(options))
		return true, "already_queued"
	end

	queued = {
		Options = mergeRefreshOptions({}, cloneRefreshOptions(options)),
	}
	pendingRefreshAfterResetByPlayer[player] = queued

	task.spawn(function()
		local resetComplete, resetReason = CrewSlotAssignmentReconciler.WaitForResetToComplete(
			player,
			RESET_REFRESH_WAIT_TIMEOUT_SECONDS
		)
		if pendingRefreshAfterResetByPlayer[player] ~= queued then
			return
		end
		pendingRefreshAfterResetByPlayer[player] = nil

		if player.Parent ~= Players then
			return
		end

		if not resetComplete then
			warn(("[ShipRuntimeService] Queued ship refresh for %s did not run because reset did not finish: %s"):format(
				formatPlayer(player),
				tostring(resetReason)
			))
			return
		end

		task.defer(function()
			if player.Parent ~= Players then
				return
			end

			local ok, result, detail = ShipRuntimeService.RefreshPlayerShip(player, queued.Options)
			if ok then
				return
			end

			warn(("[ShipRuntimeService] Queued ship refresh failed for %s after reset completed: %s"):format(
				formatPlayer(player),
				tostring(result or (detail and detail.Reason) or "unknown_error")
			))
		end)
	end)

	return true, "queued"
end

local function destroyShips(ships)
	for _, ship in ipairs(ships) do
		if ship and ship.Parent then
			ship:Destroy()
		end
	end
end

local function shouldTeleportAfterShipReplacement(options, currentShip, currentTier, currentModelName, visual, currentPositionIndex, positionIndex)
	if options.TeleportAfterReplace == false then
		return false
	end

	if options.TeleportAfterReplace == true then
		return true
	end

	if options.ForceReplace == true then
		return true
	end

	if not currentShip then
		return false
	end

	if currentTier ~= visual.Tier or currentModelName ~= visual.ModelName then
		return true
	end

	return currentPositionIndex ~= positionIndex
end

local function shouldRetryShipTeleport(reason)
	return reason == "active_ship_not_found"
		or reason == "reset_in_progress"
		or reason == "spawn_cframe_not_found"
		or reason == "missing_humanoid_root_part"
		or reason == "missing_humanoid"
end

local function teleportPlayerToShipSpawnWithRetrySync(player, character, context)
	local lastReason = nil
	local lastDetails = nil

	for attempt = 1, SHIP_SPAWN_RETRY_COUNT do
		if player.Parent ~= Players or character.Parent == nil or player.Character ~= character then
			return false, "character_unavailable"
		end

		if CrewSlotAssignmentReconciler.IsResetInProgress(player) then
			CrewSlotAssignmentReconciler.WaitForResetToComplete(player, RESET_REFRESH_WAIT_TIMEOUT_SECONDS)
		end

		local ok, reason, details = ShipRuntimeService.TeleportPlayerToShip(player, character, context)
		if ok or reason == "horo_projection" then
			return true, reason, details
		end
		if reason == "dead" then
			return false, reason, details
		end

		lastReason = reason
		lastDetails = details
		if not shouldRetryShipTeleport(reason) or attempt >= SHIP_SPAWN_RETRY_COUNT then
			break
		end

		task.wait(SHIP_SPAWN_RETRY_DELAY_SECONDS * attempt)
	end

	return false, lastReason, lastDetails
end

local function warnShipTeleportFailure(player, reason, warnKeyPrefix)
	warnOnce(
		string.format("%s_%d_%s", tostring(warnKeyPrefix or "ship_spawn_failed"), player.UserId, tostring(reason)),
		"[ShipRuntimeService] Could not move %s to their active ship spawn after retries: %s.",
		formatPlayer(player),
		tostring(reason)
	)
end

local function teleportPlayerToShipSpawnWithRetry(player, character, context, warnKeyPrefix)
	task.spawn(function()
		local ok, reason = teleportPlayerToShipSpawnWithRetrySync(player, character, context)
		if not ok and reason ~= "dead" and reason ~= "character_unavailable" then
			warnShipTeleportFailure(player, reason, warnKeyPrefix)
		end
	end)
end

local function teleportPlayerToShipSpawnDeferred(player, context)
	task.defer(function()
		if player.Parent ~= Players then
			return
		end

		local character = player.Character
		if not character or character.Parent == nil then
			return
		end

		teleportPlayerToShipSpawnWithRetry(player, character, context, "replacement_spawn_failed")
	end)
end

function ShipRuntimeService.IsActiveShip(instance)
	return typeof(instance) == "Instance" and instance:GetAttribute(ATTR.IsActiveShip) == true
end

function ShipRuntimeService.GetActiveShip(player)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return nil
	end

	local state = runtimeStateByPlayer[player]
	if state and state.ship and state.ship.Parent and ShipRuntimeService.IsActiveShip(state.ship) then
		return state.ship
	end

	local ships = getActiveShipsForPlayer(player)
	local activeShip = ships[1]

	if state then
		state.ship = activeShip
	end

	return activeShip
end

function ShipRuntimeService.GetAssignedPosition(player)
	local state = runtimeStateByPlayer[player]
	return state and state.position or nil
end

function ShipRuntimeService.GetPlayerSpawnCFrame(player)
	local activeShip = ShipRuntimeService.GetActiveShip(player)
	if not activeShip then
		return nil
	end

	local runtimeSpawnLocation = getRuntimeSpawnLocation(activeShip)
	if runtimeSpawnLocation then
		return runtimeSpawnLocation.CFrame
	end

	local runtimePoints = ensureRuntimePoints(player, activeShip)
	if not runtimePoints or not runtimePoints.Spawn then
		return nil
	end

	return runtimePoints.Spawn.CFrame
end

function ShipRuntimeService.TeleportPlayerToShip(player, targetCharacter, context)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return false, "invalid_player"
	end

	local character = targetCharacter or player.Character
	if not character then
		return false, "missing_character"
	end

	if character:GetAttribute("HoroProjectionSkipPlotSpawn") == true then
		return false, "horo_projection"
	end

	local activeShip = ShipRuntimeService.GetActiveShip(player)
	if not activeShip then
		local refreshed, result, details = ShipRuntimeService.RefreshPlayerShip(player)
		if refreshed == true and typeof(result) == "Instance" then
			activeShip = result
		elseif result == "reset_in_progress" then
			return false, result, details
		end
	end

	if not activeShip then
		return false, "active_ship_not_found"
	end

	local targetCFrame = ShipRuntimeService.GetPlayerSpawnCFrame(player)
	if not targetCFrame then
		return false, "spawn_cframe_not_found"
	end

	local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
		or character:WaitForChild("HumanoidRootPart", CHARACTER_SPAWN_TIMEOUT_SECONDS)
	if not humanoidRootPart then
		return false, "missing_humanoid_root_part"
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
		or character:WaitForChild("Humanoid", CHARACTER_SPAWN_TIMEOUT_SECONDS)
	if not humanoid then
		return false, "missing_humanoid"
	end

	if humanoid.Health <= 0 then
		return false, "dead"
	end

	character:PivotTo(targetCFrame)
	return true, context or "ship_spawn"
end

function ShipRuntimeService.ClearPlayerShip(player, options)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return false, "invalid_player"
	end

	options = options or {}

	ShipSlotInteractionService.CleanupPlayer(player)

	local ships = getActiveShipsForPlayer(player)
	for _, ship in ipairs(ships) do
		clearPlayerRespawnLocation(player, ship)
	end
	destroyShips(ships)

	local state = runtimeStateByPlayer[player]
	if state then
		state.ship = nil

		if options.ReleasePosition ~= false then
			state.position = nil
			state.positionIndex = nil
		end
	end

	return true
end

function ShipRuntimeService.QueueRefreshAfterReset(player, options)
	return queueRefreshAfterReset(player, options)
end

function ShipRuntimeService.RefreshPlayerShip(player, options)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return makeRefreshFailure("invalid_player")
	end

	options = options or {}
	if CrewSlotAssignmentReconciler.IsResetInProgress(player) and options.AllowDuringReset ~= true then
		local queued, queueReason = queueRefreshAfterReset(player, options)
		return makeRefreshFailure("reset_in_progress", {
			Retryable = true,
			Queued = queued,
			QueueReason = queueReason,
		})
	end
	pendingRefreshAfterResetByPlayer[player] = nil

	if DataManager.WaitUntilReady and not DataManager:WaitUntilReady(player, DATA_READY_TIMEOUT_SECONDS) then
		warnOnce(
			"data_not_ready_" .. tostring(player.UserId),
			"[ShipRuntimeService] Player data was not ready for %s; skipping active ship refresh.",
			formatPlayer(player)
		)
		return makeRefreshFailure("data_not_ready")
	end

	local upgradeLevel = getUpgradeLevel(player)
	local sourceModel, visual = resolveSourceModel(upgradeLevel)
	if not sourceModel or not visual then
		return makeRefreshFailure("missing_ship_template", {
			UpgradeLevel = upgradeLevel,
		})
	end

	local position, positionIndex = assignPosition(player)
	if not position then
		return makeRefreshFailure("missing_ship_position")
	end

	local activeShips = getActiveShipsFolder()
	if not activeShips then
		return makeRefreshFailure("missing_active_ships")
	end

	local existingShips = getActiveShipsForPlayer(player)
	local currentShip = existingShips[1]
	local currentTier = currentShip and tonumber(currentShip:GetAttribute(ATTR.ActiveTier))
	local currentModelName = currentShip and tostring(currentShip:GetAttribute(ATTR.ActiveModelName) or "")
	local currentPositionIndex = currentShip and tonumber(currentShip:GetAttribute(ATTR.PositionIndex))
	local teleportAfterReplace = shouldTeleportAfterShipReplacement(
		options,
		currentShip,
		currentTier,
		currentModelName,
		visual,
		currentPositionIndex,
		positionIndex
	)
	local isCorrectShip = currentShip
		and currentTier == visual.Tier
		and currentModelName == visual.ModelName
		and currentPositionIndex == positionIndex

	if isCorrectShip and not options.ForceReplace then
		local duplicateShips = {}
		for index = 2, #existingShips do
			duplicateShips[#duplicateShips + 1] = existingShips[index]
		end
		destroyShips(duplicateShips)

		currentShip.Name = getRuntimeName(player)
		applyRuntimeAttributes(currentShip, player, visual, upgradeLevel, positionIndex, position)
		warnIfMissingWalkableCollision(currentShip, visual)

		local state = getRuntimeState(player)
		state.ship = currentShip
		state.position = position
		state.positionIndex = positionIndex

		local runtimePoints, runtimePointReason, runtimePointDetails = ensureRuntimePoints(player, currentShip)
		if not runtimePoints then
			return makeRefreshFailure(runtimePointReason or "ship_spawn_not_ready", runtimePointDetails)
		end

		local slotRefreshOk, slotRefreshError = refreshSlotInteractions(player, currentShip, upgradeLevel)
		if not slotRefreshOk then
			return makeRefreshFailure("slot_interaction_refresh_failed", {
				Error = slotRefreshError,
			})
		end
		invokeStandRefresh(player)

		return true, currentShip
	end

	ShipSlotInteractionService.CleanupPlayer(player)

	local cloneOk, cloneOrError = xpcall(function()
		return sourceModel:Clone()
	end, debug.traceback)
	if not cloneOk or typeof(cloneOrError) ~= "Instance" or not cloneOrError:IsA("Model") then
		return makeRefreshFailure("clone_failed", {
			UpgradeLevel = upgradeLevel,
			SourceModel = sourceModel:GetFullName(),
			Error = tostring(cloneOrError),
		})
	end

	local clone = cloneOrError
	clone.Name = getRuntimeName(player)
	sanitizeRuntimeClone(clone)
	applyRuntimeAttributes(clone, player, visual, upgradeLevel, positionIndex, position)
	warnIfMissingWalkableCollision(clone, visual)
	clone:PivotTo(position.CFrame)
	clone.Parent = activeShips

	local runtimePoints, runtimePointReason, runtimePointDetails = ensureRuntimePoints(player, clone)
	if not runtimePoints then
		clone:Destroy()
		return makeRefreshFailure(runtimePointReason or "ship_spawn_not_ready", runtimePointDetails)
	end

	destroyShips(existingShips)

	local state = getRuntimeState(player)
	state.ship = clone
	state.position = position
	state.positionIndex = positionIndex

	local slotRefreshOk, slotRefreshError = refreshSlotInteractions(player, clone, upgradeLevel)
	if not slotRefreshOk then
		return makeRefreshFailure("slot_interaction_refresh_failed", {
			Error = slotRefreshError,
		})
	end
	invokeStandRefresh(player)

	if teleportAfterReplace then
		teleportPlayerToShipSpawnDeferred(player, "ship_replacement")
	end

	return true, clone
end

local function characterNeedsLoad(player)
	local character = player.Character
	if not character or character.Parent == nil then
		return true
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	return humanoid ~= nil and humanoid.Health <= 0
end

local function ensureActiveShipSpawnReady(player, activeShip)
	if not activeShip or not activeShip.Parent or not ShipRuntimeService.IsActiveShip(activeShip) then
		return false, "active_ship_not_found"
	end

	local runtimePoints, runtimePointReason, runtimePointDetails = ensureRuntimePoints(player, activeShip)
	if not runtimePoints or not runtimePoints.Spawn then
		return false, runtimePointReason or "ship_spawn_not_ready", runtimePointDetails
	end

	local spawnLocation = runtimePoints.Spawn
	if not isRuntimeShipSpawnLocation(spawnLocation) or not spawnLocation:IsDescendantOf(activeShip) then
		clearPlayerRespawnLocation(player, activeShip)
		return false, "invalid_runtime_spawn_location", {
			ActiveShip = activeShip,
			SpawnLocation = spawnLocation,
		}
	end

	player.RespawnLocation = spawnLocation
	return true, activeShip, {
		ActiveShip = activeShip,
		SpawnLocation = spawnLocation,
		SpawnCFrame = spawnLocation.CFrame,
	}
end

local function ensureShipReadyForCharacterLoad(player, reason)
	local activeShip = ShipRuntimeService.GetActiveShip(player)
	if activeShip then
		local spawnReady, spawnResult, spawnDetails = ensureActiveShipSpawnReady(player, activeShip)
		if spawnReady then
			return true, spawnResult, spawnDetails
		end
	end

	local refreshed, result, details = ShipRuntimeService.RefreshPlayerShip(player, {
		Reason = reason or "character_load",
	})
	if refreshed == true then
		local spawnReady, spawnResult, spawnDetails = ensureActiveShipSpawnReady(player, result)
		if spawnReady then
			return true, spawnResult, spawnDetails
		end

		return false, spawnResult, spawnDetails
	end

	if result == "reset_in_progress" then
		CrewSlotAssignmentReconciler.WaitForResetToComplete(player, RESET_REFRESH_WAIT_TIMEOUT_SECONDS)
		refreshed, result, details = ShipRuntimeService.RefreshPlayerShip(player, {
			Reason = tostring(reason or "character_load") .. "_after_reset",
		})
		if refreshed == true then
			local spawnReady, spawnResult, spawnDetails = ensureActiveShipSpawnReady(player, result)
			if spawnReady then
				return true, spawnResult, spawnDetails
			end

			return false, spawnResult, spawnDetails
		end
	end

	return false, result, details
end

local function shouldRetryShipReadyFailure(reason)
	return reason ~= "invalid_player" and reason ~= "player_left"
end

local function waitForShipSpawnReady(player, reason, options)
	local retryCount = math.max(1, math.floor(tonumber(options.ReadyRetryCount) or SHIP_READY_RETRY_COUNT))
	local retryDelay = math.max(0.05, tonumber(options.ReadyRetryDelay) or SHIP_READY_RETRY_DELAY_SECONDS)
	local lastReason = nil
	local lastDetails = nil
	local warnedDelay = false

	for attempt = 1, retryCount do
		if player.Parent ~= Players then
			return false, "player_left"
		end

		if CrewSlotAssignmentReconciler.IsResetInProgress(player) then
			CrewSlotAssignmentReconciler.WaitForResetToComplete(player, RESET_REFRESH_WAIT_TIMEOUT_SECONDS)
		end

		local shipReady, result, details = ensureShipReadyForCharacterLoad(player, reason)
		if shipReady then
			return true, result, details
		end

		lastReason = result
		lastDetails = details
		if not warnedDelay then
			warnedDelay = true
			warnOnce(
				"respawn_delayed_" .. tostring(player.UserId) .. "_" .. tostring(reason) .. "_" .. tostring(result),
				"[ShipRuntimeService] Respawn for %s is delayed because their ship spawn is not ready: %s.",
				formatPlayer(player),
				tostring(result or (details and details.Reason) or "unknown_error")
			)
		end

		if not shouldRetryShipReadyFailure(result) or attempt >= retryCount then
			break
		end

		task.wait(retryDelay * attempt)
	end

	return false, lastReason, lastDetails
end

local function isLatestRespawnRequest(player, requestId)
	local state = runtimeStateByPlayer[player]
	return state ~= nil and state.respawnRequestId == requestId
end

local function respawnPlayerAtShipSync(player, reason, options, requestId)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return false, "invalid_player"
	end

	options = if typeof(options) == "table" then options else {}
	local respawnReason = tostring(reason or options.Reason or "ship_respawn")
	local shipReady, result, details = waitForShipSpawnReady(player, respawnReason, options)
	if requestId and not isLatestRespawnRequest(player, requestId) then
		return false, "superseded"
	end

	if not shipReady then
		warnOnce(
			"respawn_without_ship_blocked_"
				.. tostring(player.UserId)
				.. "_"
				.. tostring(respawnReason)
				.. "_"
				.. tostring(result),
			"[ShipRuntimeService] Blocked respawn for %s because no ready ship spawn was available after controlled retries: %s.",
			formatPlayer(player),
			tostring(result or (details and details.Reason) or "unknown_error")
		)
		return false, result or "ship_spawn_not_ready", details
	end

	local character = player.Character
	if character and character.Parent and not characterNeedsLoad(player) then
		local moved, moveReason, moveDetails = teleportPlayerToShipSpawnWithRetrySync(player, character, respawnReason)
		if requestId and not isLatestRespawnRequest(player, requestId) then
			return false, "superseded"
		end

		if moved then
			return true, moveReason or "teleported", moveDetails
		end

		if moveReason == "character_unavailable" and player.Character ~= character then
			return false, moveReason, moveDetails
		elseif moveReason ~= "dead" and moveReason ~= "character_unavailable" then
			warnShipTeleportFailure(player, moveReason, "character_load_spawn_failed")
			return false, moveReason, moveDetails
		end
	end

	local ok, loadError = pcall(function()
		player:LoadCharacter()
	end)
	if not ok then
		warnOnce(
			"load_character_failed_" .. tostring(player.UserId),
			"[ShipRuntimeService] Failed to load character for %s: %s.",
			formatPlayer(player),
			tostring(loadError)
		)
		return false, "load_character_failed"
	end

	return true, "loaded"
end

function ShipRuntimeService.RespawnPlayerAtShip(player, reason, options)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return false, "invalid_player"
	end

	options = if typeof(options) == "table" then options else {}
	local state = getRuntimeState(player)
	state.respawnRequestId = (tonumber(state.respawnRequestId) or 0) + 1
	local requestId = state.respawnRequestId

	if options.Async == false then
		return respawnPlayerAtShipSync(player, reason, options, requestId)
	end

	task.spawn(function()
		respawnPlayerAtShipSync(player, reason, options, requestId)
	end)

	return true, "queued"
end

local function loadPlayerCharacterAtShipSpawn(player, reason)
	return ShipRuntimeService.RespawnPlayerAtShip(player, reason)
end

local function waitForUpgradeValue(player, timeoutSeconds)
	local deadline = os.clock() + (timeoutSeconds or UPGRADE_VALUE_TIMEOUT_SECONDS)

	repeat
		local valueObject = getUpgradeValueObject(player)
		if valueObject then
			return valueObject
		end

		task.wait(0.2)
	until player.Parent ~= Players or os.clock() >= deadline

	return nil
end

local function waitForRebirthValue(player, timeoutSeconds)
	local deadline = os.clock() + (timeoutSeconds or UPGRADE_VALUE_TIMEOUT_SECONDS)

	repeat
		local valueObject = getRebirthValueObject(player)
		if valueObject then
			return valueObject
		end

		task.wait(0.2)
	until player.Parent ~= Players or os.clock() >= deadline

	return nil
end

local function watchPlayerUpgrade(player)
	task.spawn(function()
		local valueObject = waitForUpgradeValue(player, UPGRADE_VALUE_TIMEOUT_SECONDS)
		if player.Parent ~= Players then
			return
		end

		local state = getRuntimeState(player)

		if valueObject then
			state.connections[#state.connections + 1] = valueObject.Changed:Connect(function()
				if CrewSlotAssignmentReconciler.IsResetInProgress(player) then
					queueRefreshAfterReset(player, {
						Reason = "plot_upgrade_changed_during_reset",
					})
					return
				end

				ShipRuntimeService.RefreshPlayerShip(player)
			end)
		else
			warnOnce(
				"missing_upgrade_value_" .. tostring(player.UserId),
				"[ShipRuntimeService] Could not find HiddenLeaderstats.%s for %s; using saved data fallback only.",
				PLOT_UPGRADE_STAT_NAME,
				formatPlayer(player)
			)
		end

		local rebirthValueObject = waitForRebirthValue(player, 5)
		if player.Parent ~= Players then
			return
		end

		if rebirthValueObject then
			state.connections[#state.connections + 1] = rebirthValueObject.Changed:Connect(function()
				if CrewSlotAssignmentReconciler.IsResetInProgress(player) then
					queueRefreshAfterReset(player, {
						Reason = "rebirth_changed_during_reset",
						ForceReplace = true,
					})
					return
				end

				ShipRuntimeService.RefreshPlayerShip(player)
			end)
		end

	end)
end

local function bindCharacterRespawn(player, character)
	local state = getRuntimeState(player)
	disconnectConnections(state.characterConnections)

	task.spawn(function()
		if player.Parent ~= Players or character.Parent == nil then
			return
		end

		local humanoid = character:FindFirstChildOfClass("Humanoid")
			or character:WaitForChild("Humanoid", CHARACTER_SPAWN_TIMEOUT_SECONDS)
		if not humanoid or player.Character ~= character then
			return
		end

		state.characterConnections[#state.characterConnections + 1] = humanoid.Died:Connect(function()
			task.delay(Players.RespawnTime, function()
				if player.Parent ~= Players then
					return
				end

				loadPlayerCharacterAtShipSpawn(player, "death_respawn")
			end)
		end)
	end)
end

local function attachCharacterSpawnHandler(player)
	local state = getRuntimeState(player)
	if state.spawnConnection and state.spawnConnection.Connected then
		return
	end

	local function handleCharacter(character)
		bindCharacterRespawn(player, character)

		task.defer(function()
			if player.Parent ~= Players or character.Parent == nil then
				return
			end

			ShipRuntimeService.RespawnPlayerAtShip(player, "character_spawn")
		end)
	end

	state.spawnConnection = player.CharacterAdded:Connect(handleCharacter)
	state.connections[#state.connections + 1] = state.spawnConnection

	if player.Character then
		handleCharacter(player.Character)
	end
end

function ShipRuntimeService.Start()
	if started then
		return
	end
	started = true
	Players.CharacterAutoLoads = false

	Players.PlayerAdded:Connect(function(player)
		attachCharacterSpawnHandler(player)
		watchPlayerUpgrade(player)
		loadPlayerCharacterAtShipSpawn(player, "initial_join")
	end)

	Players.PlayerRemoving:Connect(function(player)
		pendingRefreshAfterResetByPlayer[player] = nil
		clearPlayerRespawnLocation(player)
		ShipRuntimeService.ClearPlayerShip(player)
		disconnectPlayerState(player)
		runtimeStateByPlayer[player] = nil
	end)

	for _, player in ipairs(Players:GetPlayers()) do
		attachCharacterSpawnHandler(player)
		watchPlayerUpgrade(player)
		loadPlayerCharacterAtShipSpawn(player, "initial_join")
	end
end

return ShipRuntimeService
