local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local AffectableRegistry = require(ServerScriptService:WaitForChild("Modules"):WaitForChild("AffectableRegistry"))
local HazardRuntime = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("DevilFruits"):WaitForChild("HazardRuntime"))

local HitResolver = {}

local DEBUG = RunService:IsStudio()
local DEFAULT_MAX_IGNORED_HITS = 12
local DEFAULT_CLASSIFICATION_ORDER = { "Player", "Hazard", "Ignore", "Block" }
local DEFAULT_DIRECT_CLASSIFICATION_ORDER = { "Player", "NPC", "Hazard", "Ignore", "Block" }
local DEFAULT_IGNORE_HELPER_NAMES = {
	HitBox = true,
	ExtractionZone = true,
	RunHub = true,
	DecreaseSpeed = true,
}
local DEFAULT_IGNORE_ATTRIBUTE_NAMES = {
	"IgnoreProjectiles",
	"ProjectileIgnore",
}

local spherecastFallbackLogged = false

HitResolver.ResultKind = {
	Player = "Player",
	Npc = "NPC",
	Hazard = "Hazard",
	Destructible = "Destructible",
	Obstacle = "Obstacle",
	Ignore = "Ignore",
	Block = "Block",
	Fail = "Fail",
	NoHit = "NoHit",
}

HitResolver.Reasons = {
	Ok = "ok",
	NoHit = "no_hit",
	InvalidInstance = "invalid_instance",
	MissingHitInstance = "missing_hit_instance",
	NoCharacterModel = "no_character_model",
	NoPlayerCharacter = "no_player_character",
	PlayerCharacter = "player_character",
	SelfHit = "self_hit",
	MissingHumanoid = "missing_humanoid",
	DeadTarget = "dead_target",
	MissingRoot = "missing_root",
	MissingHazardsFolder = "missing_hazards_folder",
	NoHazardRoot = "no_hazard_root",
	OutsideHazardsFolder = "outside_hazards_folder",
	NotRegisteredHazard = "not_registered_hazard",
	DestroyedHazardController = "destroyed_hazard_controller",
	NotFreezable = "not_freezable",
	DisallowedHazardClass = "disallowed_hazard_class",
	DisallowedHazardType = "disallowed_hazard_type",
	MissingHazardPosition = "missing_hazard_position",
	TooFarFromPlayer = "too_far_from_player",
	ConfiguredIgnore = "configured_ignore",
	HelperIgnore = "helper_ignore",
	NonCollidable = "non_collidable",
	WorldGeometry = "world_geometry",
	Terrain = "terrain",
	NoAffectableMatch = "no_affectable_match",
	NotAffectable = "not_affectable",
	IgnoredLimit = "ignored_limit",
	MissingClassification = "missing_classification",
	UnknownClassifier = "unknown_classifier",
}

HitResolver.DEFAULT_MAX_IGNORED_HITS = DEFAULT_MAX_IGNORED_HITS
HitResolver.DEFAULT_CLASSIFICATION_ORDER = table.clone(DEFAULT_CLASSIFICATION_ORDER)
HitResolver.DEFAULT_DIRECT_CLASSIFICATION_ORDER = table.clone(DEFAULT_DIRECT_CLASSIFICATION_ORDER)
HitResolver.DEFAULT_IGNORE_HELPER_NAMES = table.clone(DEFAULT_IGNORE_HELPER_NAMES)

local HAZARD_REASON_MAP = {
	invalid_instance = HitResolver.Reasons.InvalidInstance,
	missing_hazards_folder = HitResolver.Reasons.MissingHazardsFolder,
	no_hazard_root = HitResolver.Reasons.NoHazardRoot,
	outside_hazards_folder = HitResolver.Reasons.OutsideHazardsFolder,
	missing_controller = HitResolver.Reasons.NotRegisteredHazard,
	destroyed_controller = HitResolver.Reasons.DestroyedHazardController,
	not_freezable = HitResolver.Reasons.NotFreezable,
	disallowed_class = HitResolver.Reasons.DisallowedHazardClass,
	disallowed_type = HitResolver.Reasons.DisallowedHazardType,
	missing_position = HitResolver.Reasons.MissingHazardPosition,
	too_far_from_player = HitResolver.Reasons.TooFarFromPlayer,
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

local function formatInstanceClass(instance)
	if typeof(instance) ~= "Instance" then
		return tostring(instance)
	end

	return instance.ClassName
end

local function hasTruthyAttribute(instance, attributeName)
	if typeof(instance) ~= "Instance" then
		return false
	end

	local value = instance:GetAttribute(attributeName)
	if value == true then
		return true
	end

	if typeof(value) == "string" then
		local lowered = string.lower(value)
		return lowered == "true" or lowered == "1" or lowered == "yes"
	end

	return false
end

local function getOrderLabel(order)
	if type(order) ~= "table" or #order == 0 then
		return table.concat(DEFAULT_CLASSIFICATION_ORDER, ">")
	end

	return table.concat(order, ">")
end

local function getDebugEnabled(options)
	if type(options) ~= "table" then
		return DEBUG
	end

	if options.DebugEnabled == nil then
		return DEBUG
	end

	return options.DebugEnabled == true
end

local function getTracePrefix(options)
	if type(options) == "table" and typeof(options.TracePrefix) == "string" and options.TracePrefix ~= "" then
		return options.TracePrefix
	end

	return "HIT"
end

local function logMessage(options, tag, message, ...)
	if not getDebugEnabled(options) then
		return
	end

	print(string.format("[%s][%s] " .. message, getTracePrefix(options), tag, ...))
end

local function logError(options, message, ...)
	if not getDebugEnabled(options) then
		return
	end

	warn(string.format("[%s][ERROR] " .. message, getTracePrefix(options), ...))
end

local function getPlayerMatchSource(hitPart, targetCharacter, targetRootPart)
	if hitPart == targetRootPart then
		return "root"
	end

	if hitPart == targetCharacter then
		return "direct"
	end

	return "ancestor"
end

local function normalizeHazardReason(reason)
	return HAZARD_REASON_MAP[tostring(reason)] or tostring(reason)
end

local function getResultType(kind)
	if kind == HitResolver.ResultKind.Player
		or kind == HitResolver.ResultKind.Npc
		or kind == HitResolver.ResultKind.Hazard
		or kind == HitResolver.ResultKind.Destructible
		or kind == HitResolver.ResultKind.Obstacle
	then
		return kind
	end

	return "Unknown"
end

local function getResultModel(result)
	if type(result) ~= "table" then
		return nil
	end

	if typeof(result.Model) == "Instance" then
		return result.Model
	end

	if typeof(result.Character) == "Instance" then
		return result.Character
	end

	if type(result.Hazard) == "table" and typeof(result.Hazard.Root) == "Instance" then
		return result.Hazard.Root
	end

	if typeof(result.Instance) == "Instance" then
		return result.Instance
	end

	if typeof(result.HitInstance) == "Instance" then
		return result.HitInstance:FindFirstAncestorOfClass("Model") or result.HitInstance
	end

	return nil
end

local function annotateResult(result)
	if type(result) ~= "table" then
		return result
	end

	result.Type = result.Type or getResultType(result.Kind)
	result.Model = result.Model or getResultModel(result)

	return result
end

local function getResolutionId(options)
	if type(options) ~= "table" then
		return "unknown"
	end

	local queryId = options.QueryId or options.ProjectileId
	if queryId == nil then
		return "unknown"
	end

	return tostring(queryId)
end

local function getAllowedEntityTypes(options)
	if type(options) ~= "table" then
		return nil
	end

	if type(options.AllowedEntityTypes) == "table" then
		return options.AllowedEntityTypes
	end

	local allowedEntityTypes = {}
	if options.IncludePlayers ~= false then
		allowedEntityTypes[AffectableRegistry.EntityType.Player] = true
	end
	if options.IncludeNpcs == true then
		allowedEntityTypes[AffectableRegistry.EntityType.Npc] = true
	end
	if options.IncludeHazards == true then
		allowedEntityTypes[AffectableRegistry.EntityType.Hazard] = true
	end
	if options.IncludeDestructibles == true then
		allowedEntityTypes[AffectableRegistry.EntityType.Destructible] = true
	end
	if options.IncludeObstacles == true then
		allowedEntityTypes[AffectableRegistry.EntityType.Obstacle] = true
	end

	return next(allowedEntityTypes) and allowedEntityTypes or nil
end

local function mapEntityTypeToResultKind(entityType)
	if entityType == AffectableRegistry.EntityType.Player then
		return HitResolver.ResultKind.Player
	end

	if entityType == AffectableRegistry.EntityType.Npc then
		return HitResolver.ResultKind.Npc
	end

	if entityType == AffectableRegistry.EntityType.Hazard then
		return HitResolver.ResultKind.Hazard
	end

	if entityType == AffectableRegistry.EntityType.Destructible then
		return HitResolver.ResultKind.Destructible
	end

	if entityType == AffectableRegistry.EntityType.Obstacle then
		return HitResolver.ResultKind.Obstacle
	end

	return nil
end

local function createEntityHitResult(match)
	if type(match) ~= "table" then
		return nil
	end

	local resultKind = mapEntityTypeToResultKind(match.EntityType)
	if not resultKind then
		return nil
	end

	local resolvedData = type(match.ResolvedData) == "table" and match.ResolvedData or {}
	local rootInstance = typeof(match.RootInstance) == "Instance" and match.RootInstance or nil
	local hitInstance = typeof(match.HitInstance) == "Instance" and match.HitInstance or rootInstance
	local baseResult = {
		Kind = resultKind,
		Reason = HitResolver.Reasons.Ok,
		Label = tostring(resolvedData.Label or match.Label or match.EntityId),
		MatchSource = tostring(resolvedData.MatchSource or match.MatchSource or "volume"),
		EntityId = match.EntityId,
		EntityType = match.EntityType,
		VolumeType = match.VolumeType,
		HitPosition = match.HitPosition or match.MatchPosition,
		HitInstance = hitInstance,
		HitClass = formatInstanceClass(hitInstance),
		Distance = match.Distance,
		AffectableEntity = match.Entity,
	}

	if resultKind == HitResolver.ResultKind.Player then
		baseResult.Player = resolvedData.Player
		baseResult.Character = resolvedData.Character or rootInstance
		baseResult.Humanoid = resolvedData.Humanoid
		baseResult.RootPart = resolvedData.RootPart
	elseif resultKind == HitResolver.ResultKind.Npc then
		baseResult.Character = resolvedData.Character or rootInstance
		baseResult.Humanoid = resolvedData.Humanoid
		baseResult.RootPart = resolvedData.RootPart
	elseif resultKind == HitResolver.ResultKind.Hazard then
		baseResult.Hazard = {
			Root = resolvedData.Root or rootInstance,
			Controller = resolvedData.Controller or (match.Entity and match.Entity.Controller) or nil,
			HazardClass = resolvedData.HazardClass,
			HazardType = resolvedData.HazardType,
			CanFreeze = resolvedData.CanFreeze == true,
			FreezeBehavior = resolvedData.FreezeBehavior,
			Position = resolvedData.Position,
			HitPosition = match.HitPosition,
			MatchSource = baseResult.MatchSource,
		}
	elseif resultKind == HitResolver.ResultKind.Destructible or resultKind == HitResolver.ResultKind.Obstacle then
		baseResult.Instance = rootInstance
	end

	return annotateResult(baseResult)
end

local function getMergedIgnoreHelperNames(options)
	local merged = table.clone(DEFAULT_IGNORE_HELPER_NAMES)
	local custom = type(options) == "table" and options.IgnoreHelperNames or nil
	if type(custom) == "table" then
		for key, value in pairs(custom) do
			merged[key] = value
		end
	end

	return merged
end

local function getIgnoreAttributeNames(options)
	local names = {}
	for _, attributeName in ipairs(DEFAULT_IGNORE_ATTRIBUTE_NAMES) do
		names[#names + 1] = attributeName
	end

	local custom = type(options) == "table" and options.IgnoreAttributeNames or nil
	if type(custom) == "table" then
		for _, attributeName in ipairs(custom) do
			if typeof(attributeName) == "string" and attributeName ~= "" then
				names[#names + 1] = attributeName
			end
		end
	end

	return names
end

local function buildRaycastParams(excludeInstances, ignoredInstances)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.IgnoreWater = true

	local filterDescendantsInstances = {}
	local function appendInstances(source)
		if typeof(source) ~= "table" then
			return
		end

		for _, instance in ipairs(source) do
			if typeof(instance) == "Instance" then
				filterDescendantsInstances[#filterDescendantsInstances + 1] = instance
			end
		end
	end

	appendInstances(excludeInstances)
	appendInstances(ignoredInstances)

	params.FilterDescendantsInstances = filterDescendantsInstances
	return params
end

local function castStep(origin, displacement, radius, params, options)
	if displacement.Magnitude <= 0.001 then
		return nil
	end

	local ok, result = pcall(function()
		return Workspace:Spherecast(origin, radius, displacement, params)
	end)
	if ok then
		return result
	end

	if not spherecastFallbackLogged then
		spherecastFallbackLogged = true
		logError(options, "spherecast unavailable, falling back to raycast detail=%s", tostring(result))
	end

	return Workspace:Raycast(origin, displacement, params)
end

local function getProjectedBodyPlayer(character)
	if not character or character:GetAttribute("HoroProjectionBody") ~= true then
		return nil
	end

	local ownerUserId = tonumber(character:GetAttribute("HoroProjectionOwnerUserId") or character:GetAttribute("OwnerUserId"))
	if not ownerUserId then
		return nil
	end

	local player = Players:GetPlayerByUserId(ownerUserId)
	if not player or player:GetAttribute("HoroProjectionActive") ~= true then
		return nil
	end

	local projectionId = character:GetAttribute("ProjectionId")
	if typeof(projectionId) == "string"
		and projectionId ~= ""
		and player:GetAttribute("HoroProjectionId") ~= projectionId
	then
		return nil
	end

	return player
end

local function resolvePlayer(options, hitPart)
	local diagnostics = {
		HitInstance = hitPart,
		Reason = HitResolver.Reasons.InvalidInstance,
	}

	if typeof(hitPart) ~= "Instance" then
		return nil, diagnostics
	end

	local targetCharacter = hitPart:FindFirstAncestorOfClass("Model")
	diagnostics.TargetCharacter = targetCharacter
	if not targetCharacter then
		diagnostics.Reason = HitResolver.Reasons.NoCharacterModel
		return nil, diagnostics
	end

	local targetPlayer = Players:GetPlayerFromCharacter(targetCharacter)
	local projectedBodyPlayer = nil
	if not targetPlayer then
		projectedBodyPlayer = getProjectedBodyPlayer(targetCharacter)
		targetPlayer = projectedBodyPlayer
	end
	diagnostics.TargetPlayer = targetPlayer
	if not targetPlayer then
		diagnostics.Reason = HitResolver.Reasons.NoPlayerCharacter
		return nil, diagnostics
	end
	diagnostics.ProjectedBody = projectedBodyPlayer ~= nil

	diagnostics.MatchSource = getPlayerMatchSource(hitPart, targetCharacter, nil)
	if targetPlayer == options.AttackerPlayer then
		diagnostics.Reason = HitResolver.Reasons.SelfHit
		return nil, diagnostics
	end

	local targetHumanoid = targetCharacter:FindFirstChildOfClass("Humanoid")
	local targetRootPart = targetCharacter:FindFirstChild("HumanoidRootPart")
	diagnostics.TargetHumanoid = targetHumanoid
	diagnostics.TargetRoot = targetRootPart
	diagnostics.MatchSource = getPlayerMatchSource(hitPart, targetCharacter, targetRootPart)

	if not targetHumanoid then
		diagnostics.Reason = HitResolver.Reasons.MissingHumanoid
		return nil, diagnostics
	end

	if targetHumanoid.Health <= 0 then
		diagnostics.Reason = HitResolver.Reasons.DeadTarget
		return nil, diagnostics
	end

	if not targetRootPart then
		diagnostics.Reason = HitResolver.Reasons.MissingRoot
		return nil, diagnostics
	end

	diagnostics.Reason = HitResolver.Reasons.Ok
	return {
		Kind = HitResolver.ResultKind.Player,
		Reason = HitResolver.Reasons.Ok,
		Label = targetPlayer.Name,
		MatchSource = diagnostics.MatchSource,
		Player = targetPlayer,
		Character = targetCharacter,
		Humanoid = targetHumanoid,
		RootPart = targetRootPart,
		HitInstance = hitPart,
		HitClass = formatInstanceClass(hitPart),
	}, diagnostics
end

local function resolveNpc(options, hitPart)
	local diagnostics = {
		HitInstance = hitPart,
		Reason = HitResolver.Reasons.InvalidInstance,
	}

	if typeof(hitPart) ~= "Instance" then
		return nil, diagnostics
	end

	local targetCharacter = hitPart:FindFirstAncestorOfClass("Model")
	diagnostics.TargetCharacter = targetCharacter
	if not targetCharacter then
		diagnostics.Reason = HitResolver.Reasons.NoCharacterModel
		return nil, diagnostics
	end

	local targetPlayer = Players:GetPlayerFromCharacter(targetCharacter)
	local projectedBodyPlayer = getProjectedBodyPlayer(targetCharacter)
	diagnostics.TargetPlayer = targetPlayer
	if targetPlayer or projectedBodyPlayer then
		diagnostics.Reason = HitResolver.Reasons.PlayerCharacter
		diagnostics.MatchSource = getPlayerMatchSource(hitPart, targetCharacter, nil)
		return nil, diagnostics
	end

	local targetHumanoid = targetCharacter:FindFirstChildOfClass("Humanoid")
	local targetRootPart = targetCharacter:FindFirstChild("HumanoidRootPart")
	diagnostics.TargetHumanoid = targetHumanoid
	diagnostics.TargetRoot = targetRootPart
	diagnostics.MatchSource = getPlayerMatchSource(hitPart, targetCharacter, targetRootPart)

	if not targetHumanoid then
		diagnostics.Reason = HitResolver.Reasons.MissingHumanoid
		return nil, diagnostics
	end

	if targetHumanoid.Health <= 0 then
		diagnostics.Reason = HitResolver.Reasons.DeadTarget
		return nil, diagnostics
	end

	if not targetRootPart then
		diagnostics.Reason = HitResolver.Reasons.MissingRoot
		return nil, diagnostics
	end

	diagnostics.Reason = HitResolver.Reasons.Ok
	return {
		Kind = HitResolver.ResultKind.Npc,
		Reason = HitResolver.Reasons.Ok,
		Label = targetCharacter.Name,
		MatchSource = diagnostics.MatchSource,
		Character = targetCharacter,
		Humanoid = targetHumanoid,
		RootPart = targetRootPart,
		HitInstance = hitPart,
		HitClass = formatInstanceClass(hitPart),
	}, diagnostics
end

local function resolveHazard(options, castResult)
	local hitPart = castResult and castResult.Instance
	local diagnostics = {
		HitInstance = hitPart,
		Reason = HitResolver.Reasons.InvalidInstance,
	}

	if typeof(hitPart) ~= "Instance" then
		return nil, diagnostics
	end

	local playerRootPosition = options.PlayerRootPosition
	if typeof(playerRootPosition) ~= "Vector3" then
		playerRootPosition = options.OriginPosition
	end

	local hazardContext, runtimeDiagnostics = HazardRuntime.GetServerHazardContext(hitPart, {
		HazardsFolder = options.HazardsFolder,
		RequireCanFreeze = options.RequireCanFreeze ~= false,
		AllowedClasses = options.AllowedHazardClasses,
		AllowedTypes = options.AllowedHazardTypes,
		PlayerRootPosition = playerRootPosition,
		MaxPlayerDistance = tonumber(options.MaxPlayerDistance) or 0,
		HitPosition = castResult and castResult.Position or nil,
	})

	if type(runtimeDiagnostics) == "table" then
		for key, value in pairs(runtimeDiagnostics) do
			diagnostics[key] = value
		end
	end

	if not hazardContext then
		diagnostics.Reason = normalizeHazardReason(diagnostics.Reason)
		return nil, diagnostics
	end

	diagnostics.Reason = HitResolver.Reasons.Ok
	return {
		Kind = HitResolver.ResultKind.Hazard,
		Reason = HitResolver.Reasons.Ok,
		Label = formatInstance(hazardContext.Root),
		MatchSource = hazardContext.MatchSource,
		Hazard = hazardContext,
		HitInstance = hitPart,
		HitClass = formatInstanceClass(hitPart),
	}, diagnostics
end

local function resolveIgnore(options, hitPart)
	if typeof(hitPart) ~= "Instance" then
		return nil
	end

	if hitPart == Workspace.Terrain then
		return nil
	end

	local ignoreHelperNames = getMergedIgnoreHelperNames(options)
	local ignoreAttributeNames = getIgnoreAttributeNames(options)

	local current = hitPart
	while current and current ~= Workspace do
		for _, attributeName in ipairs(ignoreAttributeNames) do
			if hasTruthyAttribute(current, attributeName) then
				return {
					Kind = HitResolver.ResultKind.Ignore,
					Reason = HitResolver.Reasons.ConfiguredIgnore,
					ReasonDetail = attributeName,
					Label = formatInstance(current),
					Instance = current,
					HitInstance = hitPart,
					HitClass = formatInstanceClass(hitPart),
					MatchSource = current == hitPart and "direct" or "ancestor",
				}
			end
		end

		if ignoreHelperNames[current.Name] then
			return {
				Kind = HitResolver.ResultKind.Ignore,
				Reason = HitResolver.Reasons.HelperIgnore,
				ReasonDetail = current.Name,
				Label = formatInstance(current),
				Instance = current,
				HitInstance = hitPart,
				HitClass = formatInstanceClass(hitPart),
				MatchSource = current == hitPart and "direct" or "ancestor",
			}
		end

		current = current.Parent
	end

	if options.IgnoreNonCollidable ~= false and hitPart:IsA("BasePart") and hitPart.CanCollide ~= true then
		return {
			Kind = HitResolver.ResultKind.Ignore,
			Reason = HitResolver.Reasons.NonCollidable,
			Label = formatInstance(hitPart),
			Instance = hitPart,
			HitInstance = hitPart,
			HitClass = formatInstanceClass(hitPart),
			MatchSource = "direct",
		}
	end

	return nil
end

local function resolveBlock(castResult)
	local hitPart = castResult and castResult.Instance
	if typeof(hitPart) ~= "Instance" then
		return {
			Kind = HitResolver.ResultKind.Fail,
			Reason = HitResolver.Reasons.MissingHitInstance,
			Label = "<missing_hit_instance>",
			HitInstance = nil,
			HitClass = nil,
		}
	end

	local reason = hitPart == Workspace.Terrain and HitResolver.Reasons.Terrain or HitResolver.Reasons.WorldGeometry
	return {
		Kind = HitResolver.ResultKind.Block,
		Reason = reason,
		Label = formatInstance(hitPart),
		Instance = hitPart,
		HitInstance = hitPart,
		HitClass = formatInstanceClass(hitPart),
		MatchSource = "direct",
	}
end

local function createFailResult(castResult, reason, label)
	local hitPart = castResult and castResult.Instance
	return annotateResult({
		Kind = HitResolver.ResultKind.Fail,
		Reason = reason,
		Label = label or tostring(reason),
		HitInstance = hitPart,
		HitClass = formatInstanceClass(hitPart),
		HitPosition = castResult and castResult.Position or nil,
	})
end

function HitResolver.ClassifyCastResult(options)
	options = type(options) == "table" and options or {}

	local castResult = options.CastResult
	local hitPart = castResult and castResult.Instance
	local hitPosition = castResult and castResult.Position or nil
	local classificationOrder = type(options.ClassificationOrder) == "table" and options.ClassificationOrder or DEFAULT_CLASSIFICATION_ORDER

	if typeof(hitPart) ~= "Instance" then
		local failResult = createFailResult(castResult, HitResolver.Reasons.MissingHitInstance, "<missing_hit_instance>")
		logMessage(
			options,
			"FAIL",
			"projectileId=%s order=%s reason=%s position=%s",
			tostring(options.ProjectileId),
			getOrderLabel(classificationOrder),
			failResult.Reason,
			formatVector3(hitPosition)
		)
		return failResult
	end

	logMessage(
		options,
		"INPUT",
		"projectileId=%s order=%s hit=%s class=%s position=%s",
		tostring(options.ProjectileId),
		getOrderLabel(classificationOrder),
		formatInstance(hitPart),
		formatInstanceClass(hitPart),
		formatVector3(hitPosition)
	)

	local diagnostics = {}

	for _, classifierName in ipairs(classificationOrder) do
		if classifierName == HitResolver.ResultKind.Player then
			local playerHit, playerDiagnostics = resolvePlayer(options, hitPart)
			diagnostics.Player = playerDiagnostics
			if playerHit then
				playerHit.HitPosition = hitPosition
				playerHit.Diagnostics = diagnostics
				annotateResult(playerHit)
				logMessage(
					options,
					"PLAYER",
					"projectileId=%s hit=%s class=%s player=%s character=%s match=%s final=Player",
					tostring(options.ProjectileId),
					formatInstance(hitPart),
					formatInstanceClass(hitPart),
					playerHit.Player.Name,
					formatInstance(playerHit.Character),
					tostring(playerHit.MatchSource or "unknown")
				)
				return playerHit
			end

			if playerDiagnostics and playerDiagnostics.TargetCharacter then
				logMessage(
					options,
					"PLAYER",
					"projectileId=%s hit=%s class=%s character=%s player=%s match=%s final=NoPlayer reason=%s",
					tostring(options.ProjectileId),
					formatInstance(hitPart),
					formatInstanceClass(hitPart),
					formatInstance(playerDiagnostics.TargetCharacter),
					tostring(playerDiagnostics.TargetPlayer and playerDiagnostics.TargetPlayer.Name or nil),
					tostring(playerDiagnostics.MatchSource or "unknown"),
					tostring(playerDiagnostics.Reason)
				)
			end
		elseif classifierName == HitResolver.ResultKind.Npc then
			local npcHit, npcDiagnostics = resolveNpc(options, hitPart)
			diagnostics.Npc = npcDiagnostics
			if npcHit then
				npcHit.HitPosition = hitPosition
				npcHit.Diagnostics = diagnostics
				annotateResult(npcHit)
				logMessage(
					options,
					"PLAYER",
					"projectileId=%s hit=%s class=%s npc=%s match=%s final=NPC",
					tostring(options.ProjectileId),
					formatInstance(hitPart),
					formatInstanceClass(hitPart),
					formatInstance(npcHit.Character),
					tostring(npcHit.MatchSource or "unknown")
				)
				return npcHit
			end

			if npcDiagnostics and npcDiagnostics.TargetCharacter then
				logMessage(
					options,
					"PLAYER",
					"projectileId=%s hit=%s class=%s npc=%s match=%s final=NoNPC reason=%s",
					tostring(options.ProjectileId),
					formatInstance(hitPart),
					formatInstanceClass(hitPart),
					formatInstance(npcDiagnostics.TargetCharacter),
					tostring(npcDiagnostics.MatchSource or "unknown"),
					tostring(npcDiagnostics.Reason)
				)
			end
		elseif classifierName == HitResolver.ResultKind.Hazard then
			local hazardHit, hazardDiagnostics = resolveHazard(options, castResult)
			diagnostics.Hazard = hazardDiagnostics
			if hazardHit then
				hazardHit.HitPosition = hitPosition
				hazardHit.Diagnostics = diagnostics
				annotateResult(hazardHit)
				logMessage(
					options,
					"HAZARD",
					"projectileId=%s hit=%s class=%s hazardRoot=%s match=%s final=Hazard",
					tostring(options.ProjectileId),
					formatInstance(hitPart),
					formatInstanceClass(hitPart),
					formatInstance(hazardHit.Hazard.Root),
					tostring(hazardHit.MatchSource or "unknown")
				)
				return hazardHit
			end

			if hazardDiagnostics and (hazardDiagnostics.HazardRoot or hazardDiagnostics.Reason ~= HitResolver.Reasons.NoHazardRoot) then
				logMessage(
					options,
					"HAZARD",
					"projectileId=%s hit=%s class=%s hazardRoot=%s match=%s final=NoHazard reason=%s",
					tostring(options.ProjectileId),
					formatInstance(hitPart),
					formatInstanceClass(hitPart),
					formatInstance(hazardDiagnostics.HazardRoot),
					tostring(hazardDiagnostics.MatchSource or "unknown"),
					tostring(hazardDiagnostics.Reason)
				)
			end
		elseif classifierName == HitResolver.ResultKind.Ignore then
			local ignoredHit = resolveIgnore(options, hitPart)
			if ignoredHit then
				ignoredHit.HitPosition = hitPosition
				ignoredHit.Diagnostics = diagnostics
				annotateResult(ignoredHit)
				logMessage(
					options,
					"IGNORE",
					"projectileId=%s hit=%s class=%s final=Ignore reason=%s detail=%s match=%s",
					tostring(options.ProjectileId),
					formatInstance(hitPart),
					formatInstanceClass(hitPart),
					tostring(ignoredHit.Reason),
					tostring(ignoredHit.ReasonDetail),
					tostring(ignoredHit.MatchSource or "unknown")
				)
				return ignoredHit
			end
		elseif classifierName == HitResolver.ResultKind.Block then
			local blockHit = resolveBlock(castResult)
			blockHit.HitPosition = hitPosition
			blockHit.Diagnostics = diagnostics
			annotateResult(blockHit)
			logMessage(
				options,
				"BLOCK",
				"projectileId=%s hit=%s class=%s hazardRoot=%s hazardReason=%s final=Block reason=%s",
				tostring(options.ProjectileId),
				formatInstance(hitPart),
				formatInstanceClass(hitPart),
				formatInstance(diagnostics.Hazard and diagnostics.Hazard.HazardRoot or nil),
				tostring(diagnostics.Hazard and diagnostics.Hazard.Reason or "none"),
				tostring(blockHit.Reason)
			)
			return blockHit
		else
			local failResult = createFailResult(castResult, HitResolver.Reasons.UnknownClassifier, classifierName)
			logMessage(
				options,
				"FAIL",
				"projectileId=%s order=%s reason=%s classifier=%s",
				tostring(options.ProjectileId),
				getOrderLabel(classificationOrder),
				failResult.Reason,
				tostring(classifierName)
			)
			return failResult
		end
	end

	local failResult = createFailResult(castResult, HitResolver.Reasons.MissingClassification, "missing_classification")
	annotateResult(failResult)
	logMessage(
		options,
		"FAIL",
		"projectileId=%s order=%s reason=%s position=%s",
		tostring(options.ProjectileId),
		getOrderLabel(classificationOrder),
		failResult.Reason,
		formatVector3(hitPosition)
	)
	return failResult
end

function HitResolver.ClassifyHitInstance(options)
	options = type(options) == "table" and options or {}

	local classificationOrder = type(options.ClassificationOrder) == "table"
			and options.ClassificationOrder
		or DEFAULT_DIRECT_CLASSIFICATION_ORDER

	return HitResolver.ClassifyCastResult({
		ProjectileId = options.ProjectileId,
		CastResult = {
			Instance = options.HitInstance,
			Position = options.HitPosition,
		},
		AttackerPlayer = options.AttackerPlayer,
		OriginPosition = options.OriginPosition,
		PlayerRootPosition = options.PlayerRootPosition,
		MaxPlayerDistance = options.MaxPlayerDistance,
		HazardsFolder = options.HazardsFolder,
		RequireCanFreeze = options.RequireCanFreeze,
		AllowedHazardClasses = options.AllowedHazardClasses,
		AllowedHazardTypes = options.AllowedHazardTypes,
		ClassificationOrder = classificationOrder,
		IgnoreHelperNames = options.IgnoreHelperNames,
		IgnoreAttributeNames = options.IgnoreAttributeNames,
		IgnoreNonCollidable = options.IgnoreNonCollidable,
		DebugEnabled = options.DebugEnabled,
		TracePrefix = options.TracePrefix,
	})
end

HitResolver.ResolveHitInstance = HitResolver.ClassifyHitInstance

local function createCastResultFromHit(hit)
	return {
		Instance = hit and hit.HitInstance or nil,
		Position = hit and hit.HitPosition or nil,
	}
end

local function getMatchDistance(startPosition, hitPosition)
	if typeof(startPosition) ~= "Vector3" or typeof(hitPosition) ~= "Vector3" then
		return math.huge
	end

	return (hitPosition - startPosition).Magnitude
end

local function getAffectableQueryOptions(options, extra)
	local queryOptions = {
		AttackerPlayer = options.AttackerPlayer,
		AllowedEntityTypes = getAllowedEntityTypes(options),
		AffectType = options.AffectType,
		RequireCanFreeze = options.RequireCanFreeze,
		AllowedHazardClasses = options.AllowedHazardClasses,
		AllowedHazardTypes = options.AllowedHazardTypes,
	}

	if type(extra) == "table" then
		for key, value in pairs(extra) do
			queryOptions[key] = value
		end
	end

	return queryOptions
end

local function getSegmentMaxMatches(options)
	return math.max(1, math.floor(tonumber(options.MaxMatches) or 1))
end

local function createBlockHitResult(castResult)
	local blockHit = resolveBlock(castResult)
	blockHit.HitPosition = castResult and castResult.Position or nil
	return annotateResult(blockHit)
end

local addIgnoredInstance

local function resolveWorldSegmentBlock(options, startPosition, displacement)
	local maxIgnoredHits = math.max(1, math.floor(tonumber(options.MaxIgnoredHits) or DEFAULT_MAX_IGNORED_HITS))
	local affectableQueryOptions = getAffectableQueryOptions(options)

	for attempt = 1, maxIgnoredHits do
		local params = buildRaycastParams(options.ExcludeInstances, options.IgnoredInstances)
		local castResult = castStep(startPosition, displacement, tonumber(options.QueryRadius) or 0, params, options)
		if not castResult then
			return nil, nil, nil
		end

		local hitInstance = castResult.Instance
		local hitPosition = castResult.Position
		local entity, entityReason, entityInfo = AffectableRegistry.GetEntityFromInstance(hitInstance, {
			AttackerPlayer = affectableQueryOptions.AttackerPlayer,
			AllowedEntityTypes = affectableQueryOptions.AllowedEntityTypes,
			AffectType = affectableQueryOptions.AffectType,
			RequireCanFreeze = affectableQueryOptions.RequireCanFreeze,
			AllowedHazardClasses = affectableQueryOptions.AllowedHazardClasses,
			AllowedHazardTypes = affectableQueryOptions.AllowedHazardTypes,
			HitPosition = hitPosition,
		})

		if entity and entityReason == "ok" then
			local ignoredInstance = entityInfo and (entityInfo.MatchedRoot or entityInfo.RootInstance) or hitInstance
			addIgnoredInstance(options, ignoredInstance)
			logMessage(
				options,
				"SEGMENT",
				"queryId=%s action=skip_affectable hit=%s entityId=%s entityType=%s match=%s reason=entity_volume_authority",
				getResolutionId(options),
				formatInstance(hitInstance),
				tostring(entityInfo and entityInfo.EntityId or nil),
				tostring(entityInfo and entityInfo.EntityType or nil),
				tostring(entityInfo and entityInfo.MatchSource or "unknown")
			)
			continue
		end

		if entity and entityReason ~= "ok" then
			logMessage(
				options,
				"SEGMENT",
				"queryId=%s action=affectable_rejected hit=%s entityId=%s entityType=%s reason=%s",
				getResolutionId(options),
				formatInstance(hitInstance),
				tostring(entityInfo and entityInfo.EntityId or nil),
				tostring(entityInfo and entityInfo.EntityType or nil),
				tostring(entityReason)
			)
		end

		local ignoredHit = resolveIgnore(options, hitInstance)
		if ignoredHit then
			addIgnoredInstance(options, ignoredHit.Instance or ignoredHit.HitInstance)
			logMessage(
				options,
				"SEGMENT",
				"queryId=%s action=skip_world hit=%s reason=%s detail=%s",
				getResolutionId(options),
				formatInstance(hitInstance),
				tostring(ignoredHit.Reason),
				tostring(ignoredHit.ReasonDetail)
			)
			continue
		end

		local blockHit = createBlockHitResult(castResult)
		logMessage(
			options,
			"SEGMENT",
			"queryId=%s action=block_candidate hit=%s reason=%s distance=%.2f",
			getResolutionId(options),
			tostring(blockHit.Label),
			tostring(blockHit.Reason),
			getMatchDistance(startPosition, blockHit.HitPosition)
		)
		return blockHit, castResult, nil
	end

	return nil, nil, createFailResult({
		Instance = nil,
		Position = startPosition + displacement,
	}, HitResolver.Reasons.IgnoredLimit, "ignored_limit")
end

function HitResolver.ResolveRadiusHits(options)
	options = type(options) == "table" and options or {}

	local centerPosition = options.CenterPosition
	local radius = math.max(0, tonumber(options.Radius) or 0)
	if typeof(centerPosition) ~= "Vector3" or radius <= 0 then
		logMessage(
			options,
			"FAIL",
			"queryId=%s mode=Radius reason=%s center=%s radius=%.2f",
			getResolutionId(options),
			HitResolver.Reasons.NoHit,
			formatVector3(centerPosition),
			radius
		)
		return {}
	end

	local results = {}
	local totalByKind = {}
	local allowedEntityTypes = getAllowedEntityTypes(options)

	logMessage(
		options,
		"RADIUS",
		"queryId=%s action=query center=%s radius=%.2f",
		getResolutionId(options),
		formatVector3(centerPosition),
		radius
	)

	local matches = AffectableRegistry.QueryRadius({
		QueryId = getResolutionId(options),
		CenterPosition = centerPosition,
		Radius = radius,
		MaxMatches = math.max(1, math.floor(tonumber(options.MaxMatches) or tonumber(options.MaxTargets) or 16)),
		AttackerPlayer = options.AttackerPlayer,
		AllowedEntityTypes = allowedEntityTypes,
		AffectType = options.AffectType,
		RequireCanFreeze = options.RequireCanFreeze,
		AllowedHazardClasses = options.AllowedHazardClasses,
		AllowedHazardTypes = options.AllowedHazardTypes,
		DebugEnabled = options.AffectDebugEnabled == true,
	})

	for _, match in ipairs(matches) do
		local hitResult = createEntityHitResult(match)
		if hitResult then
			results[#results + 1] = hitResult
			totalByKind[hitResult.Kind] = (totalByKind[hitResult.Kind] or 0) + 1
			logMessage(
				options,
				"RADIUS",
				"queryId=%s action=match kind=%s label=%s distance=%.2f volume=%s",
				getResolutionId(options),
				tostring(hitResult.Kind),
				tostring(hitResult.Label),
				tonumber(hitResult.Distance) or 0,
				tostring(hitResult.VolumeType)
			)
		end
	end

	table.sort(results, function(a, b)
		return (a.Distance or math.huge) < (b.Distance or math.huge)
	end)

	logMessage(
		options,
		"RADIUS",
		"queryId=%s action=resolve total=%d players=%d hazards=%d npcs=%d destructibles=%d obstacles=%d",
		getResolutionId(options),
		#results,
		totalByKind[HitResolver.ResultKind.Player] or 0,
		totalByKind[HitResolver.ResultKind.Hazard] or 0,
		totalByKind[HitResolver.ResultKind.Npc] or 0,
		totalByKind[HitResolver.ResultKind.Destructible] or 0,
		totalByKind[HitResolver.ResultKind.Obstacle] or 0
	)

	return results
end

function HitResolver.ResolveSegmentHit(options)
	options = type(options) == "table" and options or {}

	local startPosition = options.StartPosition or options.Origin
	local endPosition = options.EndPosition
	local displacement = options.Displacement
	if typeof(endPosition) ~= "Vector3" and typeof(startPosition) == "Vector3" and typeof(displacement) == "Vector3" then
		endPosition = startPosition + displacement
	end

	if typeof(startPosition) ~= "Vector3" or typeof(endPosition) ~= "Vector3" then
		return {
			Status = HitResolver.ResultKind.NoHit,
			Continue = true,
			Reason = HitResolver.Reasons.NoHit,
		}
	end

	displacement = endPosition - startPosition
	if displacement.Magnitude <= 0.001 then
		return {
			Status = HitResolver.ResultKind.NoHit,
			Continue = true,
			Reason = HitResolver.Reasons.NoHit,
		}
	end

	local allowedEntityTypes = getAllowedEntityTypes(options)
	logMessage(
		options,
		"SEGMENT",
		"queryId=%s action=query start=%s end=%s radius=%.2f",
		getResolutionId(options),
		formatVector3(startPosition),
		formatVector3(endPosition),
		math.max(0, tonumber(options.QueryRadius) or 0)
	)

	local entityMatches = AffectableRegistry.QuerySegment({
		QueryId = getResolutionId(options),
		StartPosition = startPosition,
		EndPosition = endPosition,
		QueryRadius = math.max(0, tonumber(options.QueryRadius) or 0),
		MaxMatches = getSegmentMaxMatches(options),
		AttackerPlayer = options.AttackerPlayer,
		AllowedEntityTypes = allowedEntityTypes,
		AffectType = options.AffectType,
		RequireCanFreeze = options.RequireCanFreeze,
		AllowedHazardClasses = options.AllowedHazardClasses,
		AllowedHazardTypes = options.AllowedHazardTypes,
		DebugEnabled = options.AffectDebugEnabled == true,
	})

	local entityHit = nil
	if #entityMatches > 0 then
		entityHit = createEntityHitResult(entityMatches[1])
		if entityHit then
			logMessage(
				options,
				"SEGMENT",
				"queryId=%s action=entity_candidate kind=%s label=%s distance=%.2f volume=%s",
				getResolutionId(options),
				tostring(entityHit.Kind),
				tostring(entityHit.Label),
				tonumber(entityHit.Distance) or 0,
				tostring(entityHit.VolumeType)
			)
		end
	end

	local worldBlockHit, worldCastResult, worldFailHit = resolveWorldSegmentBlock(options, startPosition, displacement)
	if worldFailHit then
		logMessage(
			options,
			"FAIL",
			"queryId=%s mode=Segment reason=%s start=%s end=%s",
			getResolutionId(options),
			tostring(worldFailHit.Reason),
			formatVector3(startPosition),
			formatVector3(endPosition)
		)
		return {
			Status = HitResolver.ResultKind.Fail,
			Continue = false,
			Reason = worldFailHit.Reason,
			CastResult = createCastResultFromHit(worldFailHit),
			Hit = worldFailHit,
		}
	end

	local entityDistance = entityHit and getMatchDistance(startPosition, entityHit.HitPosition) or math.huge
	local worldDistance = worldBlockHit and getMatchDistance(startPosition, worldBlockHit.HitPosition) or math.huge

	if entityHit and entityDistance <= worldDistance then
		logMessage(
			options,
			"RESOLVE",
			"queryId=%s mode=Segment final=%s reason=%s label=%s distance=%.2f",
			getResolutionId(options),
			tostring(entityHit.Kind),
			tostring(entityHit.Reason),
			tostring(entityHit.Label),
			entityDistance
		)
		return {
			Status = "Hit",
			Continue = false,
			Reason = entityHit.Reason,
			CastResult = createCastResultFromHit(entityHit),
			Hit = entityHit,
			MatchDistance = entityDistance,
		}
	end

	if worldBlockHit then
		logMessage(
			options,
			"RESOLVE",
			"queryId=%s mode=Segment final=%s reason=%s label=%s distance=%.2f",
			getResolutionId(options),
			tostring(worldBlockHit.Kind),
			tostring(worldBlockHit.Reason),
			tostring(worldBlockHit.Label),
			worldDistance
		)
		return {
			Status = "Hit",
			Continue = false,
			Reason = worldBlockHit.Reason,
			CastResult = worldCastResult or createCastResultFromHit(worldBlockHit),
			Hit = worldBlockHit,
			MatchDistance = worldDistance,
		}
	end

	logMessage(
		options,
		"RESOLVE",
		"queryId=%s mode=Segment final=NoHit reason=%s",
		getResolutionId(options),
		HitResolver.Reasons.NoHit
	)
	return {
		Status = HitResolver.ResultKind.NoHit,
		Continue = true,
		Reason = HitResolver.Reasons.NoHit,
	}
end

addIgnoredInstance = function(options, instance)
	if typeof(instance) ~= "Instance" then
		return false
	end

	options.IgnoredLookup = type(options.IgnoredLookup) == "table" and options.IgnoredLookup or {}
	options.IgnoredInstances = type(options.IgnoredInstances) == "table" and options.IgnoredInstances or {}
	if options.IgnoredLookup[instance] then
		return false
	end

	options.IgnoredLookup[instance] = true
	options.IgnoredInstances[#options.IgnoredInstances + 1] = instance
	return true
end

function HitResolver.ResolveCastStep(options)
	options = type(options) == "table" and options or {}

	local origin = options.Origin
	local displacement = options.Displacement
	if typeof(origin) ~= "Vector3" or typeof(displacement) ~= "Vector3" or displacement.Magnitude <= 0.001 then
		return {
			Status = HitResolver.ResultKind.NoHit,
			Continue = true,
			Reason = HitResolver.Reasons.NoHit,
		}
	end

	local maxIgnoredHits = math.max(1, math.floor(tonumber(options.MaxIgnoredHits) or DEFAULT_MAX_IGNORED_HITS))

	for attempt = 1, maxIgnoredHits do
		local params = buildRaycastParams(options.ExcludeInstances, options.IgnoredInstances)
		local castResult = castStep(origin, displacement, tonumber(options.Radius) or 0, params, options)
		if not castResult then
			return {
				Status = HitResolver.ResultKind.NoHit,
				Continue = true,
				Reason = HitResolver.Reasons.NoHit,
			}
		end

		local hit = HitResolver.ClassifyCastResult({
			ProjectileId = options.ProjectileId,
			CastResult = castResult,
			AttackerPlayer = options.AttackerPlayer,
			OriginPosition = options.OriginPosition,
			PlayerRootPosition = options.PlayerRootPosition,
			MaxPlayerDistance = options.MaxPlayerDistance,
			HazardsFolder = options.HazardsFolder,
			RequireCanFreeze = options.RequireCanFreeze,
			AllowedHazardClasses = options.AllowedHazardClasses,
			AllowedHazardTypes = options.AllowedHazardTypes,
			ClassificationOrder = options.ClassificationOrder,
			IgnoreHelperNames = options.IgnoreHelperNames,
			IgnoreAttributeNames = options.IgnoreAttributeNames,
			IgnoreNonCollidable = options.IgnoreNonCollidable,
			DebugEnabled = options.DebugEnabled,
			TracePrefix = options.TracePrefix,
		})

		if not hit then
			logMessage(
				options,
				"FAIL",
				"projectileId=%s final=Fail reason=%s",
				tostring(options.ProjectileId),
				HitResolver.Reasons.MissingClassification
			)
			return {
				Status = HitResolver.ResultKind.Fail,
				Continue = false,
				Reason = HitResolver.Reasons.MissingClassification,
				Hit = createFailResult(castResult, HitResolver.Reasons.MissingClassification, "missing_classification"),
			}
		end

		if hit.Kind == HitResolver.ResultKind.Ignore then
			addIgnoredInstance(options, hit.Instance or hit.HitInstance)
			logMessage(
				options,
				"RESOLVE",
				"projectileId=%s final=Ignore continue=true reason=%s hit=%s",
				tostring(options.ProjectileId),
				tostring(hit.Reason),
				tostring(hit.Label)
			)
		else
			local isFail = hit.Kind == HitResolver.ResultKind.Fail
			local finalTag = isFail and "FAIL" or "RESOLVE"
			logMessage(
				options,
				finalTag,
				"projectileId=%s final=%s continue=false reason=%s hit=%s",
				tostring(options.ProjectileId),
				tostring(hit.Kind),
				tostring(hit.Reason),
				tostring(hit.Label)
			)
			return {
				Status = isFail and HitResolver.ResultKind.Fail or "Hit",
				Continue = false,
				Reason = hit.Reason,
				CastResult = castResult,
				Hit = hit,
			}
		end
	end

	logMessage(
		options,
		"FAIL",
		"projectileId=%s final=Fail reason=%s ignoredHits=%d origin=%s displacement=%s",
		tostring(options.ProjectileId),
		HitResolver.Reasons.IgnoredLimit,
		maxIgnoredHits,
		formatVector3(origin),
		formatVector3(displacement)
	)
	return {
		Status = HitResolver.ResultKind.Fail,
		Continue = false,
		Reason = HitResolver.Reasons.IgnoredLimit,
		Detail = maxIgnoredHits,
		Hit = {
			Kind = HitResolver.ResultKind.Fail,
			Reason = HitResolver.Reasons.IgnoredLimit,
			Label = "ignored_limit",
		},
	}
end

return HitResolver
