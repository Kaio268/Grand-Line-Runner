local CrewSpawnRuntime = {}
local started = false

function CrewSpawnRuntime.Start()
	if started then
		return
	end
	started = true

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local Configs = Modules:WaitForChild("Configs")
local MapResolver = require(Modules:WaitForChild("MapResolver"))
local CrewOverhead = require(Modules:WaitForChild("Crew"):WaitForChild("CrewOverhead"))
local CrewAuraVisuals = require(Modules:WaitForChild("Crew"):WaitForChild("CrewAuraVisuals"))
local CrewIdleAnimator = require(Modules:WaitForChild("Crew"):WaitForChild("CrewIdleAnimator"))
local CrewIncomeBalance = require(Modules:WaitForChild("Crew"):WaitForChild("CrewIncomeBalance"))
local ServerMods = Modules:WaitForChild("Server"):WaitForChild("Crew")

local SpawnerConfig = require(Configs:WaitForChild("CrewSpawnSettings"))
local SpawnPartsCfg = require(Configs:WaitForChild("SpawnParts"))
local BiomeAreas = require(Configs:WaitForChild("BiomeAreas"))
local CrewVariantsCfg = require(Configs:WaitForChild("CrewVariants"))
local Registry = require(ServerMods:WaitForChild("Registry"))
local Placement = require(ServerMods:WaitForChild("Placement"))
local Interaction = require(ServerMods:WaitForChild("Interaction"))

local entries, maxTier, globalMaxFoot = Registry.Build()
local STARTUP_TRACE = RunService:IsStudio() and game:GetAttribute("CrewSpawnDebugTrace") == true
local function resolvePlacementPartName()
	if type(SpawnPartsCfg.GetPlacementPartName) == "function" then
		return SpawnPartsCfg.GetPlacementPartName()
	end

	return "Platform"
end

local PLACEMENT_PART_NAME = resolvePlacementPartName()

if STARTUP_TRACE then
	print("[SPAWN TRACE] startup awaiting MapResolver refs required=MapRoot,HitBox hitBoxRequired=true")
end

local resolvedMapRefs = MapResolver.WaitForRefs(
	{ "MapRoot", "HitBox" },
	nil,
	{
		warn = true,
		context = "SpawnCrewMembers",
	}
)
local map = resolvedMapRefs.MapRoot
local legacySpawnFolder = resolvedMapRefs.SpawnFolder
local hitBox = resolvedMapRefs.HitBox
local biomesRoot = resolvedMapRefs.Biomes or (map and map:FindFirstChild("Biomes"))

if STARTUP_TRACE then
	print(string.format(
		"[SPAWN TRACE] startup refsReady hitBoxRequired=true hitBoxNil=%s spawnSetupContinues=%s map=%s biomesRoot=%s legacySpawnFolder=%s hitBox=%s",
		tostring(hitBox == nil),
		tostring(hitBox ~= nil),
		map and map:GetFullName() or "<nil>",
		biomesRoot and biomesRoot:GetFullName() or "<nil>",
		legacySpawnFolder and legacySpawnFolder:GetFullName() or "<nil>",
		hitBox and hitBox:GetFullName() or "<nil>"
	))
end

local ctx = Interaction.NewContext(map)
local AddCrewMember = require(script.Parent.Parent.Modules:WaitForChild("AddCrewMember"))
local CrewInstanceService = require(script.Parent.Parent.Modules:WaitForChild("CrewInstanceService"))
local CrewQuickSlotService = require(script.Parent.Parent.Modules:WaitForChild("CrewQuickSlotService"))
local DataManager = require(ServerScriptService:WaitForChild("Data"):WaitForChild("DataManager"))
local QuestSignals = require(ServerScriptService.Modules:WaitForChild("GrandLineRushQuestSignals"))
local SpikeRuntimeService = require(
	ServerScriptService:WaitForChild("Modules")
		:WaitForChild("Hazards")
		:WaitForChild("SpikeRuntimeService")
)
local TutorialConfig = require(Configs:WaitForChild("FirstTimeTutorial"))

local rng = Random.new()
local DEBUG_TRACE = RunService:IsStudio() and game:GetAttribute("CrewSpawnDebugTrace") == true
local loggedHitBoxTouchByPlayer = {}
local spawnWarnThrottleByKey = {}
local FIRST_TUTORIAL_BIOME_INDEX = 1
local BIOME_FOLDER_PATTERN = "^Biome%s*(%d+)$"
local TUTORIAL_CREW_MEMBER_ATTRIBUTE = "TutorialCrewMember"
local TUTORIAL_OWNER_ATTRIBUTE = "TutorialOwnerUserId"
local TUTORIAL_TOKEN_ATTRIBUTE = "TutorialToken"
local TUTORIAL_REWARD_NAME_ATTRIBUTE = "TutorialRewardName"
local CARRIED_MODEL_ATTRIBUTE = "CrewCarryHeld"
local CREW_MEMBER_ID_ATTRIBUTE = "CrewMemberId"
local CREW_MEMBER_DISPLAY_NAME_ATTRIBUTE = "CrewMemberDisplayName"
local CREW_MEMBER_IMAGE_ATTRIBUTE = "CrewMemberImage"
local CREW_MEMBER_LEGACY_ID_ATTRIBUTE = "CrewMemberLegacyId"
local OVERHEAD_ATTRIBUTES = CrewOverhead.Attribute
local TUTORIAL_GRANTED_PATH = tostring(
	(TutorialConfig.TutorialCrewMember and TutorialConfig.TutorialCrewMember.GrantedPath)
		or "HiddenLeaderstats.TutorialCrewMemberGranted"
)
local CREW_MEMBERS_WORLD_FOLDER_NAME = "CrewMembersWorld"
local CREW_MEMBERS_SPAWN_FOLDER_NAME = "CrewMembers"

local function formatVector3(value)
	if typeof(value) ~= "Vector3" then
		return tostring(value)
	end

	return string.format("(%.2f, %.2f, %.2f)", value.X, value.Y, value.Z)
end

local function formatInstancePath(instance)
	if not instance then
		return "<nil>"
	end

	return instance:GetFullName()
end

local function mapTrace(message, ...)
	if not DEBUG_TRACE then
		return
	end

	print(string.format("[MAP TRACE] " .. message, ...))
end

local function spawnTrace(message, ...)
	if not DEBUG_TRACE then
		return
	end

	print(string.format("[SPAWN TRACE] " .. message, ...))
end

local function spawnWarn(message, ...)
	if not DEBUG_TRACE then
		return
	end

	warn(string.format("[SPAWN WARN] " .. message, ...))
end

local function spawnWarnThrottled(key, message, ...)
	if not DEBUG_TRACE then
		return
	end

	local now = os.clock()
	local last = spawnWarnThrottleByKey[key]
	if last and (now - last) < 5 then
		return
	end

	spawnWarnThrottleByKey[key] = now
	warn(string.format("[SPAWN WARN] " .. message, ...))
end

local function spawnError(message, ...)
	if not DEBUG_TRACE then
		return
	end

	warn(string.format("[SPAWN ERROR] " .. message, ...))
end

local function trySpawnDormantSpikeForCrew(model, data)
	if not (model and data) then
		return
	end

	local ok, spawned, reason = pcall(function()
		return SpikeRuntimeService.TrySpawnDormantForCrew({
			CrewModel = model,
			SpawnPart = data.Part,
			BiomeIndex = data.BiomeIndex,
			PlacementRarity = data.PlacementRarity,
		})
	end)

	if not ok then
		spawnWarnThrottled(
			"dormant_spike_error_" .. formatInstancePath(model),
			"dormantSpike skipped reason=service_error crewMember=%s spawnPart=%s error=%s",
			formatInstancePath(model),
			formatInstancePath(data.Part),
			tostring(spawned)
		)
	elseif spawned then
		spawnTrace(
			"dormantSpike spawned crewMember=%s spawnPart=%s biomeIndex=%s placementRarity=%s",
			formatInstancePath(model),
			formatInstancePath(data.Part),
			tostring(data.BiomeIndex),
			tostring(data.PlacementRarity)
		)
	else
		spawnTrace(
			"dormantSpike skipped reason=%s crewMember=%s spawnPart=%s biomeIndex=%s placementRarity=%s",
			tostring(reason),
			formatInstancePath(model),
			formatInstancePath(data.Part),
			tostring(data.BiomeIndex),
			tostring(data.PlacementRarity)
		)
	end
end

local function destroyDormantSpikeForCrew(model, reason)
	if not model then
		return
	end

	local ok, destroyed, destroyReason = pcall(function()
		return SpikeRuntimeService.DestroyDormantForCrew(model, reason)
	end)
	if not ok then
		spawnWarnThrottled(
			"dormant_spike_destroy_error_" .. formatInstancePath(model),
			"dormantSpike destroy skipped reason=service_error crewMember=%s error=%s",
			formatInstancePath(model),
			tostring(destroyed)
		)
	elseif destroyed then
		spawnTrace(
			"dormantSpike destroyed crewMember=%s reason=%s",
			formatInstancePath(model),
			tostring(destroyReason)
		)
	end
end

local function zoneTrace(message, ...)
	if not DEBUG_TRACE then
		return
	end

	print(string.format("[ZONE TRACE] " .. message, ...))
end

local function runTrace(message, ...)
	if not DEBUG_TRACE then
		return
	end

	print(string.format("[RUN TRACE] " .. message, ...))
end

local function isTutorialCrewMemberModel(model)
	return model ~= nil and model:GetAttribute(TUTORIAL_CREW_MEMBER_ATTRIBUTE) == true
end

local function isTutorialCrewMemberInfo(info)
	return typeof(info) == "table" and info.TutorialCrewMember == true
end

local function isHeldCrewMemberModel(model, st)
	return (st and st.Held == true) or (model and model:GetAttribute(CARRIED_MODEL_ATTRIBUTE) == true)
end

local function getTutorialCrewMemberGranted(player)
	local granted, reason = DataManager:TryGetValue(player, TUTORIAL_GRANTED_PATH)
	return reason == nil and granted == true
end

local function setTutorialCrewMemberGranted(player, granted)
	return DataManager:TrySetValue(player, TUTORIAL_GRANTED_PATH, granted == true)
end

local function getTutorialRewardNameFromModel(model)
	if not model then
		return ""
	end

	local rewardName = tostring(model:GetAttribute(TUTORIAL_REWARD_NAME_ATTRIBUTE) or "")
	if rewardName ~= "" then
		return rewardName
	end

	return tostring(model.Name or "")
end

local function hasUsableTutorialRewardInstance(player, model)
	local rewardName = getTutorialRewardNameFromModel(model)
	if rewardName == "" then
		return false, nil
	end

	local hasReward, instanceId = CrewInstanceService.HasUsableTutorialReward(player, rewardName)
	return hasReward == true, instanceId
end

local ServerLuck = workspace:WaitForChild("ServerLuck")
local CurrentEvent = workspace:WaitForChild("CurrentEvent")

local RUSH_TRIM_SECONDS = 3
local RARITY_DISTANCE_WEIGHTS = SpawnerConfig.RarityDistanceWeights or {}
local SAME_TIER_WEIGHT = tonumber(RARITY_DISTANCE_WEIGHTS.SameTier) or 1
local ONE_TIER_BELOW_WEIGHT = tonumber(RARITY_DISTANCE_WEIGHTS.OneTierBelow) or 0.02
local ONE_TIER_ABOVE_WEIGHT = tonumber(RARITY_DISTANCE_WEIGHTS.OneTierAbove) or 0.01
local RECONCILE_INTERVAL = math.max(0.5, tonumber(SpawnerConfig.ReconcileInterval) or 2)

local RARITY_TIER = SpawnPartsCfg.RarityTier or {}
local COMMON_TIER = tonumber(RARITY_TIER.Common) or 1
local UNCOMMON_TIER = tonumber(RARITY_TIER.Uncommon) or 2
local RARE_TIER = tonumber(RARITY_TIER.Rare) or 3
local EPIC_TIER = tonumber(RARITY_TIER.Epic) or 4
local LEGENDARY_TIER = tonumber(RARITY_TIER.Legendary) or 5
local MYTHIC_TIER = tonumber(RARITY_TIER.Mythic) or tonumber(RARITY_TIER.Mythical) or 6
local GODLY_TIER = tonumber(RARITY_TIER.Godly) or 7
local SECRET_TIER = tonumber(RARITY_TIER.Secret) or 8

local PLACEMENT_RARITY_INTENDED_TIER = {
	Common = COMMON_TIER,
	Uncommon = UNCOMMON_TIER,
	Rare = RARE_TIER,
	Epic = EPIC_TIER,
	Legendary = LEGENDARY_TIER,
	Mythic = MYTHIC_TIER,
	Mythical = MYTHIC_TIER,
	Godly = GODLY_TIER,
	Secret = SECRET_TIER,
	Omega = SECRET_TIER,
}

-- Canonical nearby-rarity pools. Selection never falls back to SpawnParts.LuckMult caps.
local PLACEMENT_RARITY_ALLOWED_ENTRY_TIERS = {
	Common = {
		[COMMON_TIER] = true,
		[UNCOMMON_TIER] = true,
	},
	Uncommon = {
		[COMMON_TIER] = true,
		[UNCOMMON_TIER] = true,
		[RARE_TIER] = true,
	},
	Rare = {
		[UNCOMMON_TIER] = true,
		[RARE_TIER] = true,
		[EPIC_TIER] = true,
	},
	Epic = {
		[RARE_TIER] = true,
		[EPIC_TIER] = true,
		[LEGENDARY_TIER] = true,
	},
	Legendary = {
		[EPIC_TIER] = true,
		[LEGENDARY_TIER] = true,
		[MYTHIC_TIER] = true,
	},
	Mythic = {
		[LEGENDARY_TIER] = true,
		[MYTHIC_TIER] = true,
		[GODLY_TIER] = true,
	},
	Mythical = {
		[LEGENDARY_TIER] = true,
		[MYTHIC_TIER] = true,
		[GODLY_TIER] = true,
	},
	Godly = {
		[MYTHIC_TIER] = true,
		[GODLY_TIER] = true,
		[SECRET_TIER] = true,
	},
	Secret = {
		[GODLY_TIER] = true,
		[SECRET_TIER] = true,
	},
	Omega = {
		[GODLY_TIER] = true,
		[SECRET_TIER] = true,
	},
}

local EXPECTED_RARITY_DISTANCE_WEIGHTS = {
	SameTier = 1,
	OneTierBelow = 0.02,
	OneTierAbove = 0.01,
}

local EXPECTED_VARIANT_CHANCES = {
	Normal = 90,
	Golden = 8,
	Diamond = 2,
}

local EXPECTED_PLACEMENT_RARITY_ALLOWED_TIERS = {
	Common = { COMMON_TIER, UNCOMMON_TIER },
	Uncommon = { COMMON_TIER, UNCOMMON_TIER, RARE_TIER },
	Rare = { UNCOMMON_TIER, RARE_TIER, EPIC_TIER },
	Epic = { RARE_TIER, EPIC_TIER, LEGENDARY_TIER },
	Legendary = { EPIC_TIER, LEGENDARY_TIER, MYTHIC_TIER },
	Mythic = { LEGENDARY_TIER, MYTHIC_TIER, GODLY_TIER },
	Mythical = { LEGENDARY_TIER, MYTHIC_TIER, GODLY_TIER },
	Godly = { MYTHIC_TIER, GODLY_TIER, SECRET_TIER },
	Secret = { GODLY_TIER, SECRET_TIER },
	Omega = { GODLY_TIER, SECRET_TIER },
}

local SECRET_ALLOWED_PLACEMENT_RARITIES = {
	Godly = true,
	Secret = true,
	Omega = true,
}

local GODLY_ALLOWED_PLACEMENT_RARITIES = {
	Mythic = true,
	Mythical = true,
	Godly = true,
	Secret = true,
	Omega = true,
}

local function tierSetMatchesExpected(actualSet, expectedList)
	if not actualSet then
		return false
	end

	local expectedCount = 0
	local expectedSet = {}
	for _, tier in ipairs(expectedList or {}) do
		expectedSet[tier] = true
		expectedCount += 1
		if actualSet[tier] ~= true then
			return false
		end
	end

	local actualCount = 0
	for tier in pairs(actualSet) do
		actualCount += 1
		if expectedSet[tier] ~= true then
			return false
		end
	end

	return actualCount == expectedCount
end

local function joinTierList(tiers)
	local parts = {}
	for _, tier in ipairs(tiers or {}) do
		parts[#parts + 1] = tostring(tier)
	end
	return table.concat(parts, ",")
end

local ServerEvents = ReplicatedStorage:FindFirstChild("ServerEvents")
if not ServerEvents then
	ServerEvents = Instance.new("Folder")
	ServerEvents.Name = "ServerEvents"
	ServerEvents.Parent = ReplicatedStorage
end

local LikeGoalSpawnSecret = ServerEvents:FindFirstChild("LikeGoalSpawnSecret")
if not LikeGoalSpawnSecret then
	LikeGoalSpawnSecret = Instance.new("BindableEvent")
	LikeGoalSpawnSecret.Name = "LikeGoalSpawnSecret"
	LikeGoalSpawnSecret.Parent = ServerEvents
end

local function validateSpawnBalanceGuards()
	if not DEBUG_TRACE then
		return
	end

	local expectedWeights = EXPECTED_RARITY_DISTANCE_WEIGHTS
	if math.abs(SAME_TIER_WEIGHT - expectedWeights.SameTier) > 1e-9
		or math.abs(ONE_TIER_BELOW_WEIGHT - expectedWeights.OneTierBelow) > 1e-9
		or math.abs(ONE_TIER_ABOVE_WEIGHT - expectedWeights.OneTierAbove) > 1e-9
	then
		spawnWarnThrottled(
			"spawn_balance_distance_weights_changed",
			"spawnBalance warning=rarity_distance_weights_changed same=%s below=%s above=%s expectedSame=%s expectedBelow=%s expectedAbove=%s",
			tostring(SAME_TIER_WEIGHT),
			tostring(ONE_TIER_BELOW_WEIGHT),
			tostring(ONE_TIER_ABOVE_WEIGHT),
			tostring(expectedWeights.SameTier),
			tostring(expectedWeights.OneTierBelow),
			tostring(expectedWeights.OneTierAbove)
		)
	end

	for placementRarity, expectedTiers in pairs(EXPECTED_PLACEMENT_RARITY_ALLOWED_TIERS) do
		local actualSet = PLACEMENT_RARITY_ALLOWED_ENTRY_TIERS[placementRarity]
		if not tierSetMatchesExpected(actualSet, expectedTiers) then
			spawnWarnThrottled(
				"spawn_balance_placement_rarity_pool_changed_" .. tostring(placementRarity),
				"spawnBalance warning=placement_rarity_pool_changed placementRarity=%s expectedTiers=%s",
				tostring(placementRarity),
				joinTierList(expectedTiers)
			)
		end
	end

	local order = CrewVariantsCfg.Order or {}
	if order[1] ~= "Normal" or order[2] ~= "Golden" or order[3] ~= "Diamond" then
		spawnWarnThrottled(
			"spawn_balance_variant_order_changed",
			"spawnBalance warning=variant_order_changed order=%s,%s,%s expected=Normal,Golden,Diamond",
			tostring(order[1]),
			tostring(order[2]),
			tostring(order[3])
		)
	end

	local versions = CrewVariantsCfg.Versions or {}
	for variantName, expectedChance in pairs(EXPECTED_VARIANT_CHANCES) do
		local actualChance = tonumber((versions[variantName] or {}).Chance) or 0
		if math.abs(actualChance - expectedChance) > 1e-9 then
			spawnWarnThrottled(
				"spawn_balance_variant_chance_changed_" .. tostring(variantName),
				"spawnBalance warning=variant_chance_changed variant=%s chance=%s expected=%s",
				tostring(variantName),
				tostring(actualChance),
				tostring(expectedChance)
			)
		end
	end
end

validateSpawnBalanceGuards()

mapTrace(
	"SpawnCrewMembers requestedMap=%s activeMap=%s mapPath=%s biomesRoot=%s legacySpawnFolder=%s hitBox=%s hitBoxPos=%s",
	tostring(resolvedMapRefs.RequestedMapName),
	tostring(resolvedMapRefs.ActiveMapName),
	formatInstancePath(map),
	formatInstancePath(biomesRoot),
	formatInstancePath(legacySpawnFolder),
	formatInstancePath(hitBox),
	formatVector3(hitBox and hitBox.Position or nil)
)
zoneTrace(
	"crewHitBox activeMap=%s mapPath=%s boundary=%s boundaryPos=%s boundarySize=%s",
	tostring(resolvedMapRefs.ActiveMapName),
	formatInstancePath(map),
	formatInstancePath(hitBox),
	formatVector3(hitBox and hitBox.Position or nil),
	formatVector3(hitBox and hitBox.Size or nil)
)
spawnTrace(
	"startup map=%s biomesRoot=%s usingBiomePlatforms=%s legacySpawnFolder=%s placementPartName=%s crewMembersWorld=%s carried=%s dropped=%s",
	formatInstancePath(map),
	formatInstancePath(biomesRoot),
	tostring(biomesRoot ~= nil),
	formatInstancePath(legacySpawnFolder),
	PLACEMENT_PART_NAME,
	formatInstancePath(map:FindFirstChild(CREW_MEMBERS_WORLD_FOLDER_NAME)),
	formatInstancePath(ctx and ctx.CarriedFolder),
	formatInstancePath(ctx and ctx.DroppedFolder)
)

local function shallowCopy(t)
	return table.clone(t)
end

local function normalizeCrewAttribute(value)
	if typeof(value) == "string" and value ~= "" then
		return value
	end
	if value ~= nil and typeof(value) ~= "string" then
		return tostring(value)
	end
	return nil
end

local function stampCrewMemberAttributes(model, entry)
	if not model then
		return
	end

	local info = entry and entry.Info
	local crewMemberId = normalizeCrewAttribute(info and info.CrewMemberId)
		or normalizeCrewAttribute(info and info.DisplayName)
		or normalizeCrewAttribute(info and info.CrewMemberName)
	local displayName = normalizeCrewAttribute(info and (info.DisplayName or info.CrewMemberName or info.Name))
		or crewMemberId
	local image = normalizeCrewAttribute(info and info.Render)
	local legacyId = normalizeCrewAttribute(info and info.LegacyId)
		or normalizeCrewAttribute(entry and entry.Id)

	model:SetAttribute(CREW_MEMBER_ID_ATTRIBUTE, crewMemberId)
	model:SetAttribute(CREW_MEMBER_DISPLAY_NAME_ATTRIBUTE, displayName)
	model:SetAttribute(CREW_MEMBER_IMAGE_ATTRIBUTE, image)
	model:SetAttribute(CREW_MEMBER_LEGACY_ID_ATTRIBUTE, legacyId)
end

local function removeLegacyCrewHover(model)
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant.Name == "CrewMemberHover" and descendant:IsA("BillboardGui") then
			descendant:Destroy()
		end
	end
end

local function syncSpawnOverhead(model, entry, remaining, despawnSeconds)
	if not model then
		return
	end

	local info = entry and entry.Info or {}
	local displayName = normalizeCrewAttribute(info.DisplayName or info.CrewMemberName or info.Name)
		or normalizeCrewAttribute(entry and entry.Id)
		or "Crewmate"
	local rarity = normalizeCrewAttribute(info.Rarity or entry and entry.Rarity) or "Common"
	local variant = normalizeCrewAttribute(info.Variant or entry and entry.Variant) or "Normal"
	local minIncome, maxIncome = CrewIncomeBalance.GetRangeDisplayIncome(rarity, variant)
	local income = math.max(0, math.floor(((minIncome + maxIncome) / 2) + 0.5))
	local safeRemaining = math.max(0, tonumber(remaining) or 0)
	local safeDespawnSeconds = math.max(
		safeRemaining,
		tonumber(despawnSeconds)
			or tonumber(model:GetAttribute(OVERHEAD_ATTRIBUTES.DespawnSeconds))
			or tonumber(info.TimeLeft)
			or safeRemaining
	)

	model:SetAttribute(OVERHEAD_ATTRIBUTES.Kind, CrewOverhead.Kind.Spawned)
	model:SetAttribute(OVERHEAD_ATTRIBUTES.DisplayName, displayName)
	model:SetAttribute(OVERHEAD_ATTRIBUTES.Rarity, rarity)
	model:SetAttribute(OVERHEAD_ATTRIBUTES.Variant, variant)
	model:SetAttribute(OVERHEAD_ATTRIBUTES.IncomePerSecond, income)
	model:SetAttribute(OVERHEAD_ATTRIBUTES.ExpiresAt, workspace:GetServerTimeNow() + safeRemaining)
	model:SetAttribute(OVERHEAD_ATTRIBUTES.DespawnSeconds, safeDespawnSeconds)
	removeLegacyCrewHover(model)
	CollectionService:AddTag(model, CrewOverhead.Tag)
end

local function normalizeEventName(s)
	s = tostring(s or "")
	s = s:lower()
	s = s:gsub("%s+", "")
	s = s:gsub("_", "")
	return s
end

local function getForcedVariantKey()
	local ev = normalizeEventName(CurrentEvent.Value)
	if ev == "goldenrush" then
		return "Golden"
	end
	if ev == "diamondrush" or ev == "diamonddrush" then
		return "Diamond"
	end
	return nil
end

local function getPlayerPositions()
	local positions = {}
	for _, plr in ipairs(Players:GetPlayers()) do
		local ch = plr.Character
		if ch then
			local hrp = ch:FindFirstChild("HumanoidRootPart")
			if hrp then
				positions[#positions + 1] = hrp.Position
			end
		end
	end
	return positions
end

local function anyPlayerNearPart(spawnPart, positions, radius)
	local r2 = radius * radius
	local p = spawnPart.Position
	for i = 1, #positions do
		local d = positions[i] - p
		if d.X * d.X + d.Y * d.Y + d.Z * d.Z <= r2 then
			return true
		end
	end
	return false
end

local function getServerLuckMult()
	local v = tonumber(ServerLuck.Value) or 1
	if v < 1 then
		v = 1
	end
	return v
end

local function getIntendedTierForPlacementRarity(placementRarity)
	return tonumber(PLACEMENT_RARITY_INTENDED_TIER[tostring(placementRarity or "")])
		or tonumber(RARITY_TIER[tostring(placementRarity or "")])
		or COMMON_TIER
end

local function getAllowedEntryTiersForPlacementRarity(placementRarity)
	return PLACEMENT_RARITY_ALLOWED_ENTRY_TIERS[tostring(placementRarity or "")]
end

local function isEntryTierAllowedForPlacementRarity(placementRarity, entryTier)
	local placementRarityText = tostring(placementRarity or "")
	local entryTierNumber = tonumber(entryTier) or COMMON_TIER
	local allowedEntryTiers = PLACEMENT_RARITY_ALLOWED_ENTRY_TIERS[placementRarityText]
	if not allowedEntryTiers or allowedEntryTiers[entryTierNumber] ~= true then
		return false
	end

	if entryTierNumber == SECRET_TIER then
		return SECRET_ALLOWED_PLACEMENT_RARITIES[placementRarityText] == true
	elseif entryTierNumber == GODLY_TIER then
		return GODLY_ALLOWED_PLACEMENT_RARITIES[placementRarityText] == true
	end

	return true
end

local function validateChosenEntryForPlacementRarity(data, entry, context)
	if not data or not entry then
		return false
	end

	local placementRarity = tostring(data.PlacementRarity or data.Name or "")
	local entryTier = tonumber(entry.Tier) or COMMON_TIER
	if isEntryTierAllowedForPlacementRarity(placementRarity, entryTier) then
		return true
	end

	spawnWarnThrottled(
		"spawn_balance_out_of_band_choice_" .. formatInstancePath(data.Part),
		"spawnBalance blocked reason=out_of_band_rarity_choice context=%s spawnPart=%s placementRarity=%s entry=%s entryRarity=%s entryTier=%s",
		tostring(context),
		formatInstancePath(data.Part),
		placementRarity,
		tostring(entry.Id),
		tostring(entry.Rarity),
		tostring(entryTier)
	)
	return false
end

local function getRarityDistanceWeight(entryTier, intendedTier)
	local distance = (tonumber(entryTier) or COMMON_TIER) - (tonumber(intendedTier) or COMMON_TIER)
	if distance == 0 then
		return SAME_TIER_WEIGHT, distance
	elseif distance == -1 then
		return ONE_TIER_BELOW_WEIGHT, distance
	elseif distance == 1 then
		return ONE_TIER_ABOVE_WEIGHT, distance
	end

	return 0, distance
end

local function weightForEntry(entry, data, serverLuckMult)
	local base = tonumber(entry.Info and entry.Info.Chance) or 0
	if base <= 0 then
		return 0, "disabled_chance"
	end

	local entryTier = tonumber(entry.Tier) or COMMON_TIER
	if not isEntryTierAllowedForPlacementRarity(data and (data.PlacementRarity or data.Name), entryTier) then
		return 0, "rarity_distance"
	end

	local intendedTier = tonumber(data and data.IntendedTier) or tonumber(data and data.Tier) or COMMON_TIER
	local distanceWeight, distance = getRarityDistanceWeight(entryTier, intendedTier)
	if distanceWeight <= 0 then
		return 0, "distance_weight"
	end

	local weight = base * distanceWeight
	serverLuckMult = tonumber(serverLuckMult) or 1
	if serverLuckMult <= 1 or maxTier <= 1 then
		return weight, nil, distance, distanceWeight
	end

	if entryTier < LEGENDARY_TIER then
		return weight, nil, distance, distanceWeight
	end

	local partBias = math.clamp(intendedTier / maxTier, 0, 1)
	local denom = math.max(1, (maxTier - LEGENDARY_TIER))
	local highBias = math.clamp((entryTier - LEGENDARY_TIER) / denom, 0, 1)
	local exponent = math.clamp(partBias * (0.35 + 0.65 * highBias), 0, 1)

	return weight * math.exp(math.log(serverLuckMult) * exponent), nil, distance, distanceWeight
end

local function chooseForPart(data, serverLuckMult)
	local total = 0
	local eligible = {}
	local filteredByReason = {}

	for i = 1, #entries do
		local entry = entries[i]
		local w, reason, distance, distanceWeight = weightForEntry(entry, data, serverLuckMult)
		if w > 0 then
			total += w
			eligible[#eligible + 1] = {
				Entry = entry,
				Weight = w,
			}

			if DEBUG_TRACE then
				spawnTrace(
					"rarityEligibility allowed placementRarity=%s intendedTier=%s crewMember=%s entryRarity=%s entryTier=%s distance=%s distanceWeight=%.4f finalWeight=%.8f",
					tostring(data and (data.PlacementRarity or data.Name)),
					tostring(data and data.IntendedTier),
					tostring(entry.Id),
					tostring(entry.Rarity),
					tostring(entry.Tier),
					tostring(distance),
					tonumber(distanceWeight) or 0,
					w
				)
			end
		else
			filteredByReason[reason or "zero_weight"] = (filteredByReason[reason or "zero_weight"] or 0) + 1
		end
	end

	if #eligible == 0 then
		if DEBUG_TRACE then
			local parts = {}
			for reason, count in pairs(filteredByReason) do
				parts[#parts + 1] = string.format("%s=%s", tostring(reason), tostring(count))
			end
			table.sort(parts)
			spawnWarnThrottled(
				"spawn_no_nearby_rarity_entries_" .. formatInstancePath(data and data.Part),
				"chooseForPart skipped reason=no_nearby_rarity_entries spawnPart=%s placementRarity=%s intendedTier=%s filters=%s",
				formatInstancePath(data and data.Part),
				tostring(data and (data.PlacementRarity or data.Name)),
				tostring(data and data.IntendedTier),
				table.concat(parts, ", ")
			)
		end
		return nil
	end

	if total <= 0 then
		return eligible[rng:NextInteger(1, #eligible)].Entry
	end

	local pick = rng:NextNumber() * total
	local acc = 0

	for i = 1, #eligible do
		acc += eligible[i].Weight
		if pick <= acc then
			return eligible[i].Entry
		end
	end

	return eligible[#eligible].Entry
end

local function tryPlayIdle(model, entry)
	entry = if typeof(entry) == "table" then entry else {}
	local info = if typeof(entry.Info) == "table" then entry.Info else entry
	CrewIdleAnimator.Start(model, {
		CrewMemberId = entry.Id or entry.BaseId or info.CrewMemberId or info.Id or info.ModelName,
		Gender = info.Gender,
		Info = info,
		Source = "CrewSpawnRuntime",
	})
end

local function refreshVariantAura(model, entry)
	entry = if typeof(entry) == "table" then entry else {}
	local info = if typeof(entry.Info) == "table" then entry.Info else entry
	CrewAuraVisuals.Refresh(model, {
		CrewMemberId = entry.Id or entry.BaseId or info.CrewMemberId or info.Id or info.ModelName,
		Variant = entry.Variant or info.Variant,
		Info = info,
		Source = "CrewSpawnRuntime",
	})
end

local function restoreDroppedCrewMemberPresentation(model, st)
	if typeof(model) ~= "Instance" or not model:IsA("Model") or not model.Parent then
		return false, "invalid_model"
	end
	if typeof(st) ~= "table" or typeof(st.Entry) ~= "table" then
		return false, "missing_entry"
	end

	refreshVariantAura(model, st.Entry)
	tryPlayIdle(model, st.Entry)
	return true
end

Interaction.SetWorldPresentationAdapter({
	RestoreDroppedCrewMember = restoreDroppedCrewMemberPresentation,
})

local function getBiomeIndexFromName(name)
	local indexText = tostring(name or ""):match(BIOME_FOLDER_PATTERN)
	return indexText and tonumber(indexText) or nil
end

local function getSpawnPartBiomeIndex(spawnPart)
	if not spawnPart or not biomesRoot then
		return nil
	end

	local current = spawnPart
	while current and current ~= biomesRoot do
		local parent = current.Parent
		if parent == biomesRoot then
			return getBiomeIndexFromName(current.Name)
		end

		current = parent
	end

	return nil
end

local function isPlacementPart(spawnPart)
	local isPlacement = SpawnPartsCfg.IsPlacementPart
	if type(isPlacement) == "function" then
		return isPlacement(spawnPart)
	end

	return spawnPart and spawnPart:IsA("BasePart") and spawnPart.Name == PLACEMENT_PART_NAME
end

local function getPlacementRarityForPart(spawnPart, biomeIndex)
	local getRarity = SpawnPartsCfg.GetPlacementRarityForPart
	if type(getRarity) == "function" then
		return getRarity(spawnPart, biomeIndex, BiomeAreas)
	end

	return "Common"
end

local function getPlacementTierForPart(spawnPart, biomeIndex)
	local getTier = SpawnPartsCfg.GetPlacementTierForPart
	if type(getTier) == "function" then
		return getTier(spawnPart, biomeIndex, BiomeAreas)
	end

	return COMMON_TIER
end

local partDataList = {}
local partDataByPart = {}

local function setupSpawnPart(spawnPart)
	local ok, err = xpcall(function()
		if partDataByPart[spawnPart] then
			return
		end

		if not spawnPart:IsA("BasePart") then
			spawnWarnThrottled(
				"setup_non_part_" .. formatInstancePath(spawnPart),
				"setupSpawnPart skipped reason=not_basepart instance=%s class=%s",
				formatInstancePath(spawnPart),
				tostring(spawnPart.ClassName)
			)
			return
		end

		if not isPlacementPart(spawnPart) then
			spawnWarnThrottled(
				"setup_invalid_placement_part_" .. formatInstancePath(spawnPart),
				"setupSpawnPart skipped reason=invalid_placement_part part=%s name=%s expectedName=%s class=%s",
				formatInstancePath(spawnPart),
				tostring(spawnPart.Name),
				tostring(PLACEMENT_PART_NAME),
				tostring(spawnPart.ClassName)
			)
			return
		end

		local biomeIndex = getSpawnPartBiomeIndex(spawnPart)
		local placementRarity = getPlacementRarityForPart(spawnPart, biomeIndex)
		local partTier = tonumber(getPlacementTierForPart(spawnPart, biomeIndex)) or COMMON_TIER
		local intendedTier = getIntendedTierForPlacementRarity(placementRarity)
		local allowedEntryTiers = getAllowedEntryTiersForPlacementRarity(placementRarity)

		local container = spawnPart:FindFirstChild(CREW_MEMBERS_SPAWN_FOLDER_NAME)
		if not container then
			container = Instance.new("Folder")
			container.Name = CREW_MEMBERS_SPAWN_FOLDER_NAME
			container.Parent = spawnPart
		end

		local spacing = (math.max(4, globalMaxFoot) * 1.2)

		local data = {
			Part = spawnPart,
			Name = placementRarity,
			PlacementRarity = placementRarity,
			BiomeIndex = biomeIndex,
			Tier = partTier,
			IntendedTier = intendedTier,
			AllowedEntryTiers = allowedEntryTiers,
			Container = container,
			Spacing = spacing,
			SlotOccupied = {},
			SlotCooldown = {},
			SlotOffsets = {},
		}

		partDataByPart[spawnPart] = data
		partDataList[#partDataList + 1] = data

		spawnTrace(
			"setupSpawnPart part=%s placementRarity=%s rawTier=%s intendedTier=%s biomeIndex=%s pos=%s size=%s container=%s",
			formatInstancePath(spawnPart),
			tostring(placementRarity),
			tostring(partTier),
			tostring(intendedTier),
			tostring(biomeIndex),
			formatVector3(spawnPart.Position),
			formatVector3(spawnPart.Size),
			formatInstancePath(container)
		)
	end, debug.traceback)

	if not ok then
		spawnError(
			"setupSpawnPart failed instance=%s error=%s",
			formatInstancePath(spawnPart),
			tostring(err)
		)
	end
end

local function getBiomeScanRoot(biomeContainer)
	if not biomeContainer then
		return nil, nil
	end

	local innerBiome = biomeContainer:FindFirstChild(biomeContainer.Name)
	if innerBiome then
		return innerBiome, innerBiome
	end

	return biomeContainer, nil
end

local function processBiomeContainer(biomeContainer)
	local ok, err = xpcall(function()
		if not biomeContainer then
			return
		end

		local scanRoot, innerBiome = getBiomeScanRoot(biomeContainer)

		spawnTrace(
			"processBiome biome=%s scanRoot=%s innerBiome=%s",
			formatInstancePath(biomeContainer),
			formatInstancePath(scanRoot),
			formatInstancePath(innerBiome)
		)

		if scanRoot:IsA("BasePart") then
			setupSpawnPart(scanRoot)
		end

		for _, descendant in ipairs(scanRoot:GetDescendants()) do
			if descendant:IsA("BasePart") then
				setupSpawnPart(descendant)
			end
		end
	end, debug.traceback)

	if not ok then
		spawnError(
			"processBiome failed biome=%s error=%s",
			formatInstancePath(biomeContainer),
			tostring(err)
		)
	end
end

if not biomesRoot then
	spawnError(
		"spawnPlatformDiscovery failed reason=missing_biomes_root map=%s legacySpawnFolder=%s",
		formatInstancePath(map),
		formatInstancePath(legacySpawnFolder)
	)
else
	spawnTrace(
		"biomesRoot ready root=%s topLevelBiomeCount=%s",
		formatInstancePath(biomesRoot),
		tostring(#biomesRoot:GetChildren())
	)

	for _, biomeContainer in ipairs(biomesRoot:GetChildren()) do
		processBiomeContainer(biomeContainer)
	end

	biomesRoot.ChildAdded:Connect(function(child)
		task.defer(function()
			spawnTrace("biomesRoot childAdded biome=%s", formatInstancePath(child))
			processBiomeContainer(child)
		end)
	end)

	biomesRoot.DescendantAdded:Connect(function(descendant)
		task.defer(function()
			if descendant:IsA("BasePart") then
				setupSpawnPart(descendant)
			end
		end)
	end)
end

local active = {}
ctx.Active = active

local function releaseSpawnSlot(data, slotIndex, model, reason, cooldownSeconds)
	if not data or not slotIndex then
		return false
	end

	local current = data.SlotOccupied and data.SlotOccupied[slotIndex]
	local canRelease = model == nil or current == nil or current == model
	if not canRelease then
		spawnWarnThrottled(
			"slot_release_mismatch_" .. formatInstancePath(data.Part) .. "_" .. tostring(slotIndex),
			"releaseSpawnSlot skipped reason=model_mismatch spawnPart=%s slot=%s expected=%s current=%s cleanupReason=%s",
			formatInstancePath(data.Part),
			tostring(slotIndex),
			formatInstancePath(model),
			formatInstancePath(current),
			tostring(reason)
		)
		return false
	end

	local released = current ~= nil
	if data.SlotOccupied then
		data.SlotOccupied[slotIndex] = nil
	end
	if data.SlotOffsets then
		data.SlotOffsets[slotIndex] = nil
	end
	if data.SlotCooldown and tonumber(cooldownSeconds) and tonumber(cooldownSeconds) > 0 then
		data.SlotCooldown[slotIndex] = os.clock() + tonumber(cooldownSeconds)
	end

	if released then
		spawnTrace(
			"slotReleased spawnPart=%s slot=%s model=%s reason=%s",
			formatInstancePath(data.Part),
			tostring(slotIndex),
			formatInstancePath(current),
			tostring(reason)
		)
	end

	return released
end

local function releaseStateOriginSlot(st, model, reason, clearOrigin)
	if not st then
		return false
	end

	local released = releaseSpawnSlot(st.OriginData, st.SlotIndex, model, reason)
	if clearOrigin then
		st.OriginData = nil
		st.SlotIndex = nil
	end
	return released
end

local function disconnectActiveState(st)
	if st and st.AncestryConn then
		st.AncestryConn:Disconnect()
		st.AncestryConn = nil
	end
end

local function clearActiveState(model, st, reason)
	if st then
		disconnectActiveState(st)
		destroyDormantSpikeForCrew(model, reason)
		releaseStateOriginSlot(st, model, reason, false)
	end

	if model and active[model] == st then
		active[model] = nil
	end
end

local function ensureSpawnContainer(data)
	if not data or data.Disabled or not data.Part or not data.Part.Parent or not data.Part:IsA("BasePart") then
		return false
	end

	if data.Container and data.Container.Parent == data.Part then
		return true
	end

	local container = data.Part:FindFirstChild(CREW_MEMBERS_SPAWN_FOLDER_NAME)
	if not container then
		container = Instance.new("Folder")
		container.Name = CREW_MEMBERS_SPAWN_FOLDER_NAME
		container.Parent = data.Part
	end

	data.Container = container
	spawnTrace(
		"spawnContainerRebound spawnPart=%s container=%s",
		formatInstancePath(data.Part),
		formatInstancePath(container)
	)
	return true
end

local function cleanupInvalidSpawnData(data, reason)
	if not data or data.Disabled then
		return
	end

	data.Disabled = true
	if data.Part then
		partDataByPart[data.Part] = nil
	end

	for i = 1, SpawnerConfig.MaxPerPart do
		local model = data.SlotOccupied and data.SlotOccupied[i]
		if model then
			local st = active[model]
			if model.Parent and model.Parent ~= data.Container then
				if st then
					releaseStateOriginSlot(st, model, reason or "invalid_spawn_part_parented_away", true)
				else
					releaseSpawnSlot(data, i, model, reason or "invalid_spawn_part_parented_away")
				end
			elseif st then
				clearActiveState(model, st, reason or "invalid_spawn_part")
			else
				releaseSpawnSlot(data, i, model, reason or "invalid_spawn_part")
			end

			if model.Parent == data.Container and not isTutorialCrewMemberModel(model) and not isHeldCrewMemberModel(model, st) then
				pcall(function()
					model:Destroy()
				end)
			end
		end
		if data.SlotCooldown then
			data.SlotCooldown[i] = nil
		end
	end

	spawnWarnThrottled(
		"invalid_spawn_data_" .. formatInstancePath(data.Part),
		"spawnData disabled reason=%s spawnPart=%s container=%s",
		tostring(reason),
		formatInstancePath(data.Part),
		formatInstancePath(data.Container)
	)
end

local function reconcileSpawnData(data, reason)
	if not data or data.Disabled then
		return false
	end

	if not data.Part or not data.Part.Parent or not data.Part:IsA("BasePart") then
		cleanupInvalidSpawnData(data, reason or "invalid_spawn_part")
		return false
	end

	if not ensureSpawnContainer(data) then
		cleanupInvalidSpawnData(data, reason or "invalid_spawn_container")
		return false
	end

	local occupiedModels = {}
	for i = 1, SpawnerConfig.MaxPerPart do
		local model = data.SlotOccupied and data.SlotOccupied[i]
		if model then
			local st = active[model]
			if not model.Parent then
				if st then
					clearActiveState(model, st, "destroyed_slot_model")
				else
					releaseSpawnSlot(data, i, model, "destroyed_slot_model")
				end
			elseif model.Parent ~= data.Container then
				if st then
					releaseStateOriginSlot(st, model, "parented_away_from_spawn_folder", true)
				else
					releaseSpawnSlot(data, i, model, "parented_away_from_spawn_folder")
				end
			elseif st and (st.OriginData ~= data or st.SlotIndex ~= i) then
				releaseSpawnSlot(data, i, model, "active_origin_mismatch")
				spawnWarnThrottled(
					"slot_active_origin_mismatch_" .. formatInstancePath(data.Part) .. "_" .. tostring(i),
					"reconcileSpawnData cleared reason=active_origin_mismatch spawnPart=%s slot=%s model=%s activeOrigin=%s activeSlot=%s",
					formatInstancePath(data.Part),
					tostring(i),
					formatInstancePath(model),
					formatInstancePath(st.OriginData and st.OriginData.Part),
					tostring(st.SlotIndex)
				)
			else
				occupiedModels[model] = true
			end
		end
	end

	for _, child in ipairs(data.Container:GetChildren()) do
		if child:IsA("Model") and not occupiedModels[child] and not isTutorialCrewMemberModel(child) then
			local st = active[child]
			if st then
				clearActiveState(child, st, "orphaned_spawn_folder_model")
			end
			spawnWarnThrottled(
				"orphaned_spawn_model_" .. formatInstancePath(child),
				"reconcileSpawnData destroying reason=orphaned_spawn_folder_model spawnPart=%s model=%s",
				formatInstancePath(data.Part),
				formatInstancePath(child)
			)
			pcall(function()
				child:Destroy()
			end)
		end
	end

	return true
end

local function expireCrewMember(model, st)
	if active[model] ~= st then
		return
	end
	if isTutorialCrewMemberModel(model) then
		return
	end
	if isHeldCrewMemberModel(model, st) then
		return
	end

	clearActiveState(model, st, "expired")
	pcall(function()
		model:Destroy()
	end)
end

local function rushTrimExistingOnce()
	for model, st in pairs(active) do
		if model and model.Parent and not isHeldCrewMemberModel(model, st) and not isTutorialCrewMemberModel(model) then
			local newRemain = math.min(st.Remaining or 0, RUSH_TRIM_SECONDS)
			st.Remaining = newRemain
			st.LastUpdate = os.clock()
			st.LastShown = -1
			syncSpawnOverhead(model, st.Entry, newRemain)

			task.delay(RUSH_TRIM_SECONDS, function()
				expireCrewMember(model, st)
			end)
		end
	end
end

local lastForced = nil
local function onEventChanged()
	local forced = getForcedVariantKey()
	if forced and forced ~= lastForced then
		rushTrimExistingOnce()
	end
	lastForced = forced
end

CurrentEvent:GetPropertyChangedSignal("Value"):Connect(onEventChanged)
onEventChanged()

Players.PlayerRemoving:Connect(function(plr)
	Interaction.OnPlayerRemoving(ctx, plr, active)
end)

local hitDebounce = {}

hitBox.Touched:Connect(function(hit)
	if not hit or hit.Name ~= "HumanoidRootPart" then
		return
	end
	local char = hit.Parent
	if not char then
		return
	end
	local plr = Players:GetPlayerFromCharacter(char)
	if not plr then
		return
	end

	zoneTrace(
		"crewBoundaryTouched player=%s boundary=%s boundaryPos=%s activeMap=%s mapPath=%s",
		plr.Name,
		formatInstancePath(hitBox),
		formatVector3(hitBox.Position),
		tostring(resolvedMapRefs.ActiveMapName),
		formatInstancePath(map)
	)

	if not loggedHitBoxTouchByPlayer[plr.UserId] then
		loggedHitBoxTouchByPlayer[plr.UserId] = true
		spawnTrace(
			"hitBoxTouched player=%s hitBox=%s hitBoxPos=%s",
			plr.Name,
			formatInstancePath(hitBox),
			formatVector3(hitBox.Position)
		)
	end

	local now = os.clock()
	local last = hitDebounce[plr.UserId]
	if last and (now - last) < 0.35 then
		return
	end
	hitDebounce[plr.UserId] = now

	local heldModel = ctx.HeldByUserId[plr.UserId]
	local heldIsTutorial = isTutorialCrewMemberModel(heldModel)
	local heldTutorialFlagGranted = heldIsTutorial and getTutorialCrewMemberGranted(plr) or false
	local heldTutorialAlreadyGranted = false
	if heldTutorialFlagGranted then
		local hasUsableReward, rewardInstanceId = hasUsableTutorialRewardInstance(plr, heldModel)
		heldTutorialAlreadyGranted = hasUsableReward == true
		if not heldTutorialAlreadyGranted then
			runTrace(
				"crewTurnIn tutorial flag ignored player=%s reward=%s reason=no_usable_tutorial_reward_instance",
				plr.Name,
				getTutorialRewardNameFromModel(heldModel)
			)
		else
			runTrace(
				"crewTurnIn tutorial grant skipped player=%s reward=%s reason=usable_tutorial_reward_exists instanceId=%s",
				plr.Name,
				getTutorialRewardNameFromModel(heldModel),
				tostring(rewardInstanceId)
			)
		end
	end

	if heldIsTutorial then
		local ownerUserId = heldModel:GetAttribute(TUTORIAL_OWNER_ATTRIBUTE)
		if ownerUserId ~= plr.UserId then
			runTrace(
				"crewTurnIn blocked player=%s reason=tutorial_owner_mismatch owner=%s",
				plr.Name,
				tostring(ownerUserId)
			)
			return
		end
	end

	local heldCount = if typeof(Interaction.GetHeldCount) == "function" then Interaction.GetHeldCount(ctx, plr) else 1
	local heldGrants = {}
	if typeof(Interaction.PeekAllHeld) == "function" then
		for _, info in ipairs(Interaction.PeekAllHeld(ctx, plr, active)) do
			if info and info.Name then
				table.insert(heldGrants, {
					CrewMemberId = info.Name,
					Amount = 1,
				})
			end
		end
	end
	if Interaction.HasHeld(ctx, plr) and not heldTutorialAlreadyGranted and not heldIsTutorial then
		local canGain = if #heldGrants > 0 and typeof(CrewQuickSlotService.CanGainCrewMemberBatchOrNotify) == "function"
			then CrewQuickSlotService.CanGainCrewMemberBatchOrNotify(plr, heldGrants, "SpawnCrewMembers:TurnIn")
			else CrewQuickSlotService.CanGainOrNotify(plr, math.max(1, heldCount), "SpawnCrewMembers:TurnIn")
		if not canGain then
			runTrace(
				"crewTurnIn blocked player=%s boundary=%s activeMap=%s reason=quick_slots_full",
				plr.Name,
				formatInstancePath(hitBox),
				tostring(resolvedMapRefs.ActiveMapName)
			)
			return
		end
	end

	if heldIsTutorial and not heldTutorialAlreadyGranted then
		local flagged = setTutorialCrewMemberGranted(plr, true)
		if flagged ~= true then
			runTrace(
				"crewTurnIn blocked player=%s reason=tutorial_flag_save_failed",
				plr.Name
			)
			return
		end
	end

	local heldInfos = if typeof(Interaction.CollectAllHeld) == "function"
		then Interaction.CollectAllHeld(ctx, plr, active, {
			Reason = "CrewTurnIn",
		})
		else { Interaction.CollectHeld(ctx, plr, active, nil, {
			Reason = "CrewTurnIn",
		}) }
	local collectedAny = false
	for _, info in ipairs(heldInfos) do
		if not (info and info.Name) then
			continue
		end
		collectedAny = true
		local displayName = tostring(info.DisplayName or info.CrewMemberId or info.Name)
		runTrace(
			"crewTurnIn player=%s boundary=%s activeMap=%s reward=%s slotIndex=%s origin=%s action=AddCrewMember",
			plr.Name,
			formatInstancePath(hitBox),
			tostring(resolvedMapRefs.ActiveMapName),
			displayName,
			tostring(info.SlotIndex),
			tostring(info.OriginData ~= nil)
		)
		local added = true
		if not heldTutorialAlreadyGranted then
			added = AddCrewMember:AddCrewMember(plr, info.Name, 1, {
				TutorialReward = isTutorialCrewMemberInfo(info),
				TutorialToken = tostring(info.TutorialToken or ""),
			})
		end
		if not added then
			if isTutorialCrewMemberInfo(info) then
				setTutorialCrewMemberGranted(plr, false)
			end
			runTrace(
				"crewTurnIn blocked player=%s reward=%s reason=inventory_full_or_add_failed",
				plr.Name,
				tostring(info.Name)
			)
			return
		end
		QuestSignals.Record(plr, "ExtractCrew", 1, {
			Source = "SpawnCrewMembers",
			CrewName = displayName,
			ActiveMap = tostring(resolvedMapRefs.ActiveMapName or ""),
			TutorialCrewMember = isTutorialCrewMemberInfo(info),
			TutorialAlreadyGranted = heldTutorialAlreadyGranted,
			TutorialToken = tostring(info.TutorialToken or ""),
		})
		if info.OriginData and info.SlotIndex then
			releaseSpawnSlot(info.OriginData, info.SlotIndex, info.Model, "extracted", rng:NextNumber(4, 6))
		end
	end
	if not collectedAny then
		runTrace(
			"crewTurnInSkipped player=%s boundary=%s activeMap=%s reason=no_held_crew_member",
			plr.Name,
			formatInstancePath(hitBox),
			tostring(resolvedMapRefs.ActiveMapName)
		)
	end
end)

local function registerActive(model, entry, originData, slotIndex)
	stampCrewMemberAttributes(model, entry)

	local tl = tonumber(entry.Info.TimeLeft) or 0
	if tl <= 0 then
		tl = 30
	end

	local st = {
		Model = model,
		Entry = entry,
		Rarity = entry.Rarity,
		Remaining = tl,
		LastUpdate = os.clock(),
		LastShown = -1,
		Held = false,
		HolderUserId = nil,
		Prompt = nil,
		Weld = nil,
		OriginData = originData,
		SlotIndex = slotIndex,
		AncestryConn = nil,
	}

	active[model] = st
	st.AncestryConn = model.AncestryChanged:Connect(function(_, parent)
		if parent == nil then
			clearActiveState(model, st, "destroyed_or_removed")
			return
		end

		if st.OriginData and st.SlotIndex and st.OriginData.Container and parent ~= st.OriginData.Container then
			releaseStateOriginSlot(st, model, "parented_away_from_spawn_folder", true)
		end
	end)

	syncSpawnOverhead(model, entry, tl, tl)
	st.Prompt = Interaction.BindPrompt(ctx, model, st, Placement.EnsurePrimaryPart)

	return st
end

local function occupiedCount(data)
	local c = 0
	for i = 1, SpawnerConfig.MaxPerPart do
		if data.SlotOccupied[i] then
			c += 1
		end
	end
	return c
end

local function findFreeSlotRandom(data, now)
	local candidates = {}
	for i = 1, SpawnerConfig.MaxPerPart do
		if not data.SlotOccupied[i] then
			local cd = data.SlotCooldown[i]
			if not cd or cd <= now then
				candidates[#candidates + 1] = i
			end
		end
	end
	if #candidates == 0 then
		return nil
	end
	return candidates[rng:NextInteger(1, #candidates)]
end

local function isOffsetClear(data, offsetXZ)
	local dist = data.Spacing
	local dist2 = dist * dist
	for slotIndex, occupiedModel in pairs(data.SlotOccupied) do
		if occupiedModel then
			local occupiedOffset = data.SlotOffsets[slotIndex]
			if occupiedOffset then
				local dx = offsetXZ.X - occupiedOffset.X
				local dz = offsetXZ.Y - occupiedOffset.Y
				if (dx * dx + dz * dz) < dist2 then
					return false
				end
			end
		end
	end

	return true
end

local function pickRandomOffset(data, halfX, halfZ)
	for _ = 1, 80 do
		local x = rng:NextNumber(-halfX, halfX)
		local z = rng:NextNumber(-halfZ, halfZ)
		local offsetXZ = Vector2.new(x, z)
		if isOffsetClear(data, offsetXZ) then
			return offsetXZ
		end
	end
	return Vector2.new(rng:NextNumber(-halfX, halfX), rng:NextNumber(-halfZ, halfZ))
end

local function getFlatPartBasis(spawnPart)
	local lookVector = spawnPart.CFrame.LookVector
	local look = Vector3.new(lookVector.X, 0, lookVector.Z)
	if look.Magnitude < 1e-4 then
		look = Vector3.new(0, 0, -1)
	else
		look = look.Unit
	end

	local flatCFrame = CFrame.lookAt(spawnPart.Position, spawnPart.Position + look, Vector3.yAxis)
	return flatCFrame.RightVector, flatCFrame.LookVector
end

local function getClosestOffsetOnSpawnPart(spawnPart, worldPosition, halfX, halfZ)
	if not spawnPart or typeof(worldPosition) ~= "Vector3" then
		return nil, nil, math.huge
	end

	local right, look = getFlatPartBasis(spawnPart)
	local relative = worldPosition - spawnPart.Position
	local offsetXZ = Vector2.new(
		math.clamp(relative:Dot(right), -halfX, halfX),
		math.clamp(relative:Dot(look), -halfZ, halfZ)
	)
	local surfacePosition = spawnPart.Position + right * offsetXZ.X + look * offsetXZ.Y
	local delta = Vector3.new(surfacePosition.X - worldPosition.X, 0, surfacePosition.Z - worldPosition.Z)

	return offsetXZ, surfacePosition, delta.Magnitude
end

local function pickTutorialOffset(data, halfX, halfZ, options)
	local preferredPosition = options and options.PreferredPosition
	if typeof(preferredPosition) ~= "Vector3" then
		return nil, "missing_reference_position"
	end

	local targetOffset = getClosestOffsetOnSpawnPart(data.Part, preferredPosition, halfX, halfZ)
	if not targetOffset then
		return nil, "missing_reference_position"
	end
	if isOffsetClear(data, targetOffset) then
		return targetOffset
	end

	local spacing = math.max(2, tonumber(data.Spacing) or 2)
	for radiusStep = 1, 4 do
		local radius = spacing * radiusStep
		for angleIndex = 1, 12 do
			local angle = (math.pi * 2) * (angleIndex / 12)
			local offsetXZ = Vector2.new(
				math.clamp(targetOffset.X + math.cos(angle) * radius, -halfX, halfX),
				math.clamp(targetOffset.Y + math.sin(angle) * radius, -halfZ, halfZ)
			)
			if isOffsetClear(data, offsetXZ) then
				return offsetXZ
			end
		end
	end

	return nil, "no_clear_nearby_offset"
end

local function getTutorialSpawnPointDistance(data, referencePosition)
	if typeof(referencePosition) ~= "Vector3" or not data or not data.Part then
		return math.huge
	end

	local halfX = math.max(0, data.Part.Size.X * 0.45)
	local halfZ = math.max(0, data.Part.Size.Z * 0.45)
	local _, _, distance = getClosestOffsetOnSpawnPart(data.Part, referencePosition, halfX, halfZ)
	return distance
end

local function getTutorialSpawnDataCandidates(preferredPosition)
	local firstBiome = {}
	local indexedBiomes = {}
	local anyBiome = {}
	local allCandidates = {}

	for i = 1, #partDataList do
		local data = partDataList[i]
		if data and not data.Disabled and reconcileSpawnData(data, "tutorial_candidate") then
			allCandidates[#allCandidates + 1] = data
			local biomeIndex = getSpawnPartBiomeIndex(data.Part)
			if biomeIndex == FIRST_TUTORIAL_BIOME_INDEX then
				firstBiome[#firstBiome + 1] = data
			elseif biomeIndex then
				indexedBiomes[#indexedBiomes + 1] = {
					Index = biomeIndex,
					Data = data,
				}
			else
				anyBiome[#anyBiome + 1] = data
			end
		end
	end

	local hasPreferredPosition = typeof(preferredPosition) == "Vector3"
	local candidates = if hasPreferredPosition then allCandidates else firstBiome
	if not hasPreferredPosition and #candidates == 0 and #indexedBiomes > 0 then
		table.sort(indexedBiomes, function(a, b)
			if a.Index ~= b.Index then
				return a.Index < b.Index
			end

			return a.Data.Part:GetFullName() < b.Data.Part:GetFullName()
		end)

		local firstIndex = indexedBiomes[1].Index
		candidates = {}
		for _, entry in ipairs(indexedBiomes) do
			if entry.Index ~= firstIndex then
				break
			end

			candidates[#candidates + 1] = entry.Data
		end
	elseif not hasPreferredPosition and #candidates == 0 then
		candidates = anyBiome
	end

	local referencePosition = if hasPreferredPosition then preferredPosition else hitBox and hitBox.Position or nil
	table.sort(candidates, function(a, b)
		local aDistance = getTutorialSpawnPointDistance(a, referencePosition)
		local bDistance = getTutorialSpawnPointDistance(b, referencePosition)
		if math.abs(aDistance - bDistance) > 0.001 then
			return aDistance < bDistance
		end

		return a.Part:GetFullName() < b.Part:GetFullName()
	end)

	return candidates
end

local function reserveTutorialSlot(data)
	if not reconcileSpawnData(data, "tutorial_reserve_preflight") then
		return nil, "spawn_data_invalid"
	end

	local slotIndex = findFreeSlotRandom(data, os.clock())
	if slotIndex then
		return slotIndex, nil
	end

	slotIndex = SpawnerConfig.MaxPerPart + 1
	while data.SlotOccupied[slotIndex] do
		slotIndex += 1
	end

	return slotIndex, "tutorial_overflow_slot"
end

local function spawnTutorialCrewMemberOnData(data, options)
	local player = options.Player
	local sourceEntry = options.Entry
	local template = sourceEntry and sourceEntry.Template
	if not (player and template and template:IsA("Model")) then
		return nil, "Tutorial Crewmate template is not available."
	end

	local finalId = tostring((sourceEntry.Info and sourceEntry.Info.CrewMemberId) or sourceEntry.FinalId or sourceEntry.Id or template.Name)
	local info = if typeof(sourceEntry.Info) == "table" then shallowCopy(sourceEntry.Info) else {}
	local lifetime = math.max(60, tonumber(options.Lifetime) or tonumber(info.TimeLeft) or 900)
	info.TimeLeft = lifetime

	local entry = {
		Id = finalId,
		Info = info,
		Template = template,
		Rarity = tostring(sourceEntry.Rarity or info.Rarity or "Common"),
		Tier = tonumber(sourceEntry.Tier) or 1,
		Foot = tonumber(sourceEntry.Foot) or 0,
		BaseId = sourceEntry.BaseId,
		Variant = sourceEntry.Variant,
	}

	local clone = template:Clone()
	clone.Name = finalId
	clone:SetAttribute(TUTORIAL_CREW_MEMBER_ATTRIBUTE, true)
	clone:SetAttribute(TUTORIAL_OWNER_ATTRIBUTE, player.UserId)
	clone:SetAttribute(TUTORIAL_TOKEN_ATTRIBUTE, tostring(options.Token or ""))
	clone:SetAttribute(TUTORIAL_REWARD_NAME_ATTRIBUTE, tostring(options.RewardName or finalId))
	clone.Parent = data.Container

	Placement.EnsurePrimaryPart(clone)
	Placement.AnchorModel(clone)

	local scaleVal = Instance.new("NumberValue")
	scaleVal.Value = SpawnerConfig.InitialScale
	scaleVal.Parent = clone

	pcall(function()
		clone:ScaleTo(scaleVal.Value)
	end)

	local _, initSize = clone:GetBoundingBox()
	local s0 = math.max(0.001, scaleVal.Value)
	local finalSize = initSize / s0
	local effX = data.Part.Size.X * 0.9
	local effZ = data.Part.Size.Z * 0.9
	local halfX = math.max(0, (effX / 2) - (finalSize.X / 2))
	local halfZ = math.max(0, (effZ / 2) - (finalSize.Z / 2))
	local slotIndex, slotReason = reserveTutorialSlot(data)
	if not slotIndex then
		pcall(function()
			clone:Destroy()
		end)
		return nil, slotReason or "Tutorial spawn part is no longer valid."
	end
	local offsetXZ, offsetReason = pickTutorialOffset(data, halfX, halfZ, options)
	if not offsetXZ then
		pcall(function()
			clone:Destroy()
		end)
		return nil, offsetReason or "Tutorial spawn part could not fit the Crewmate."
	end
	local yaw = rng:NextNumber(0, math.pi * 2)

	data.SlotOffsets[slotIndex] = offsetXZ
	Placement.AlignModelOnPartUpright(clone, data.Part, offsetXZ, yaw)
	data.SlotOccupied[slotIndex] = clone

	spawnTrace(
		"tutorialSpawn placementRarity=%s crewMember=%s player=%s chosenSpawnPart=%s chosenSpawnPartPos=%s finalParent=%s finalPivot=%s offset=%s slotIndex=%s",
		tostring(data.PlacementRarity or data.Name),
		tostring(finalId),
		player.Name,
		formatInstancePath(data.Part),
		formatVector3(data.Part.Position),
		formatInstancePath(clone.Parent),
		formatVector3(clone:GetPivot().Position),
		formatVector3(Vector3.new(offsetXZ.X, 0, offsetXZ.Y)),
		tostring(slotIndex)
	)

	local conn
	conn = scaleVal.Changed:Connect(function(v)
		if not clone.Parent then
			if conn then
				conn:Disconnect()
			end
			releaseSpawnSlot(data, slotIndex, clone, "tutorial_clone_removed_during_spawn_tween")
			return
		end

		local s = tonumber(v)
		if s then
			pcall(function()
				clone:ScaleTo(s)
			end)
			Placement.AlignModelOnPartUpright(clone, data.Part, offsetXZ, yaw)
		end
	end)

	local tween = TweenService:Create(
		scaleVal,
		TweenInfo.new(SpawnerConfig.TweenTime, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Value = 1 }
	)

	tween:Play()
	tween.Completed:Connect(function()
		if conn then
			conn:Disconnect()
		end
		if scaleVal.Parent then
			scaleVal:Destroy()
		end
		if clone.Parent then
			Placement.AlignModelOnPartUpright(clone, data.Part, offsetXZ, yaw)
			refreshVariantAura(clone, entry)
			tryPlayIdle(clone, entry)
			local state = registerActive(clone, entry, data, slotIndex)
			state.IsTutorial = true
			state.TutorialOwnerUserId = player.UserId
			state.TutorialToken = tostring(options.Token or "")
			if state.Prompt then
				state.Prompt.ObjectText = "Tutorial Pickup"
			end
		else
			releaseSpawnSlot(data, slotIndex, clone, "tutorial_clone_missing_before_register")
			spawnWarnThrottled(
				"tutorial_spawn_completed_missing_clone_" .. tostring(finalId),
				"tutorialSpawn skipped reason=clone_missing_before_register spawnPart=%s crewMember=%s player=%s",
				formatInstancePath(data.Part),
				tostring(finalId),
				player.Name
			)
		end
	end)

	return clone, nil
end

local function spawnTutorialCrewMember(options)
	if typeof(options) ~= "table" then
		return nil, "Tutorial spawn request is invalid."
	end
	if typeof(options.PreferredPosition) ~= "Vector3" then
		return nil, "Tutorial spawn reference position is not available yet."
	end

	local candidates = getTutorialSpawnDataCandidates(options.PreferredPosition)
	if #candidates == 0 then
		return nil, "CrewMember spawns are still loading."
	end

	local checkedCount = 0
	local rejected = {}
	for _, data in ipairs(candidates) do
		local distance = getTutorialSpawnPointDistance(data, options.PreferredPosition)
		checkedCount += 1
		local ok, modelOrMessage, message = xpcall(function()
			return spawnTutorialCrewMemberOnData(data, options)
		end, debug.traceback)

		if ok and modelOrMessage then
			spawnTrace(
				"tutorialSpawn selected player=%s referenceSource=%s reference=%s spawnPart=%s distance=%.2f candidatesChecked=%d totalCandidates=%d rejectedCloser=%s",
				options.Player and options.Player.Name or "<nil>",
				tostring(options.PreferredPositionSource or "Unknown"),
				formatVector3(options.PreferredPosition),
				formatInstancePath(data.Part),
				distance,
				checkedCount,
				#candidates,
				if #rejected > 0 then table.concat(rejected, "; ") else "<none>"
			)
			return modelOrMessage, nil
		elseif not ok then
			rejected[#rejected + 1] = string.format("%s:exception", formatInstancePath(data and data.Part))
			spawnError(
				"tutorialSpawn failed spawnPart=%s error=%s",
				formatInstancePath(data and data.Part),
				tostring(modelOrMessage)
			)
		else
			rejected[#rejected + 1] = string.format("%s:%s", formatInstancePath(data and data.Part), tostring(message or "unknown"))
			spawnWarnThrottled(
				"tutorial_spawn_failed_" .. formatInstancePath(data and data.Part),
				"tutorialSpawn skipped spawnPart=%s reason=%s",
				formatInstancePath(data and data.Part),
				tostring(message or "unknown")
			)
		end
	end

	spawnTrace(
		"tutorialSpawn unavailable player=%s referenceSource=%s reference=%s totalCandidates=%d rejected=%s",
		options.Player and options.Player.Name or "<nil>",
		tostring(options.PreferredPositionSource or "Unknown"),
		formatVector3(options.PreferredPosition),
		#candidates,
		if #rejected > 0 then table.concat(rejected, "; ") else "<none>"
	)
	return nil, "No nearby tutorial Crewmate spawn point is available yet."
end

ctx.SpawnTutorialCrewMember = spawnTutorialCrewMember

local function getSamePlacementRarityPartPaths(placementRarity)
	local paths = {}

	for i = 1, #partDataList do
		local data = partDataList[i]
		if data and not data.Disabled and data.Part and (data.PlacementRarity or data.Name) == placementRarity then
			paths[#paths + 1] = formatInstancePath(data.Part)
		end
	end

	table.sort(paths)
	return paths
end

local function spawnOne(data)
	local ok, result = xpcall(function()
		if not reconcileSpawnData(data, "spawn_one_preflight") then
			return false
		end

		local now = os.clock()
		local occupied = occupiedCount(data)
		if occupied >= SpawnerConfig.MaxPerPart then
			spawnWarnThrottled(
				"spawn_skip_max_" .. formatInstancePath(data.Part),
				"spawnOne skipped reason=max_per_part spawnPart=%s occupied=%s max=%s",
				formatInstancePath(data.Part),
				tostring(occupied),
				tostring(SpawnerConfig.MaxPerPart)
			)
			return false
		end

		local freeIndex = findFreeSlotRandom(data, now)
		if not freeIndex then
			spawnWarnThrottled(
				"spawn_skip_no_slot_" .. formatInstancePath(data.Part),
				"spawnOne skipped reason=no_free_slot spawnPart=%s occupied=%s cooldowns_active=true",
				formatInstancePath(data.Part),
				tostring(occupied)
			)
			return false
		end

		local baseEntry = chooseForPart(data, getServerLuckMult())
		if not baseEntry then
			spawnWarnThrottled(
				"spawn_skip_no_entry_" .. formatInstancePath(data.Part),
				"spawnOne skipped reason=no_base_entry spawnPart=%s placementRarity=%s intendedTier=%s",
				formatInstancePath(data.Part),
				tostring(data.PlacementRarity or data.Name),
				tostring(data.IntendedTier)
			)
			return false
		end
		if not validateChosenEntryForPlacementRarity(data, baseEntry, "spawnOne") then
			return false
		end

		local forcedVariant = getForcedVariantKey()
		local variantKey = forcedVariant or Registry.RollVariant(rng)

		local template, usedVariant = Registry.GetTemplateWithFallback(baseEntry.Id, variantKey)
		if not template then
			spawnWarnThrottled(
				"spawn_skip_no_template_" .. tostring(baseEntry.Id) .. "_" .. tostring(variantKey),
				"spawnOne skipped reason=no_template spawnPart=%s rarity=%s crewMember=%s requestedVariant=%s",
				formatInstancePath(data.Part),
				tostring(baseEntry.Rarity),
				tostring(baseEntry.Id),
				tostring(variantKey)
			)
			return false
		end
		variantKey = usedVariant

		local finalId = Registry.MakeVariantId(baseEntry.Id, variantKey)
		local finalInfo = Registry.GetOrBuildVariantInfo(baseEntry.Id, variantKey)
		if not finalInfo then
			spawnWarnThrottled(
				"spawn_skip_no_info_" .. tostring(finalId),
				"spawnOne skipped reason=no_final_info spawnPart=%s rarity=%s crewMember=%s variant=%s",
				formatInstancePath(data.Part),
				tostring(baseEntry.Rarity),
				tostring(baseEntry.Id),
				tostring(variantKey)
			)
			return false
		end

		if forcedVariant then
			local copied = shallowCopy(finalInfo)
			copied.TimeLeft = baseEntry.Info.TimeLeft
			finalInfo = copied
		end

		local rarityLabel = tostring(baseEntry.Rarity or "Common")

		local entry = {
			Id = finalId,
			Info = finalInfo,
			Template = template,
			Rarity = rarityLabel,
			Tier = baseEntry.Tier,
			Foot = baseEntry.Foot,
			BaseId = baseEntry.Id,
			Variant = variantKey,
		}

		local clone = template:Clone()
		clone.Name = finalId
		clone.Parent = data.Container

		Placement.EnsurePrimaryPart(clone)
		Placement.AnchorModel(clone)

		local scaleVal = Instance.new("NumberValue")
		scaleVal.Value = SpawnerConfig.InitialScale
		scaleVal.Parent = clone

		pcall(function()
			clone:ScaleTo(scaleVal.Value)
		end)

		local _, initSize = clone:GetBoundingBox()
		local s0 = math.max(0.001, scaleVal.Value)
		local finalSize = initSize / s0

		local effX = data.Part.Size.X * 0.9
		local effZ = data.Part.Size.Z * 0.9
		local halfX = math.max(0, (effX / 2) - (finalSize.X / 2))
		local halfZ = math.max(0, (effZ / 2) - (finalSize.Z / 2))

		local offsetXZ = pickRandomOffset(data, halfX, halfZ)
		local yaw = rng:NextNumber(0, math.pi * 2)

		data.SlotOffsets[freeIndex] = offsetXZ
		Placement.AlignModelOnPartUpright(clone, data.Part, offsetXZ, yaw)
		data.SlotOccupied[freeIndex] = clone

		local pivotPosition = clone:GetPivot().Position
		local matchingCandidatePaths = getSamePlacementRarityPartPaths(data.PlacementRarity or data.Name)
		spawnTrace(
			"spawnOne placementRarity=%s chosenRarity=%s crewMember=%s variant=%s candidateCount=%s candidates=%s chosenSpawnPart=%s chosenSpawnPartPos=%s finalParent=%s finalPivot=%s offset=%s",
			tostring(data.PlacementRarity or data.Name),
			tostring(rarityLabel),
			tostring(baseEntry.Id),
			tostring(variantKey),
			tostring(#matchingCandidatePaths),
			table.concat(matchingCandidatePaths, " | "),
			formatInstancePath(data.Part),
			formatVector3(data.Part.Position),
			formatInstancePath(clone.Parent),
			formatVector3(pivotPosition),
			formatVector3(Vector3.new(offsetXZ.X, 0, offsetXZ.Y))
		)

		local conn
		conn = scaleVal.Changed:Connect(function(v)
			if not clone.Parent then
				if conn then
					conn:Disconnect()
				end
				releaseSpawnSlot(data, freeIndex, clone, "clone_removed_during_spawn_tween")
				return
			end
			local s = tonumber(v)
			if s then
				pcall(function()
					clone:ScaleTo(s)
				end)
				Placement.AlignModelOnPartUpright(clone, data.Part, offsetXZ, yaw)
			end
		end)

		local tween = TweenService:Create(
			scaleVal,
			TweenInfo.new(SpawnerConfig.TweenTime, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
			{ Value = 1 }
		)

		tween:Play()

		tween.Completed:Connect(function()
			if conn then
				conn:Disconnect()
			end
			if scaleVal.Parent then
				scaleVal:Destroy()
			end
			if clone.Parent then
				Placement.AlignModelOnPartUpright(clone, data.Part, offsetXZ, yaw)
				local settledPosition = clone:GetPivot().Position
				spawnTrace(
					"spawnOne completed rarity=%s crewMember=%s finalParent=%s finalPosition=%s",
					tostring(rarityLabel),
					tostring(clone.Name),
					formatInstancePath(clone.Parent),
					formatVector3(settledPosition)
				)
				refreshVariantAura(clone, entry)
				tryPlayIdle(clone, entry)
				registerActive(clone, entry, data, freeIndex)
				trySpawnDormantSpikeForCrew(clone, data)
			else
				releaseSpawnSlot(data, freeIndex, clone, "clone_missing_before_register")
				spawnWarnThrottled(
					"spawn_completed_missing_clone_" .. tostring(finalId),
					"spawnOne skipped reason=clone_missing_before_register spawnPart=%s crewMember=%s",
					formatInstancePath(data.Part),
					tostring(finalId)
				)
			end
		end)

		return true
	end, debug.traceback)

	if not ok then
		spawnError(
			"spawnOne failed spawnPart=%s error=%s",
			formatInstancePath(data and data.Part),
			tostring(result)
		)
		return false
	end

	return result
end

local function despawnAllInData(data)
	if not reconcileSpawnData(data, "despawn_all_preflight") then
		return
	end

	for i = 1, SpawnerConfig.MaxPerPart do
		local m = data.SlotOccupied[i]
		if m then
			local st = active[m]
			if isTutorialCrewMemberModel(m) then
				continue
			end
			if isHeldCrewMemberModel(m, st) then
				if st then
					releaseStateOriginSlot(st, m, "despawn_all_held_parented_away", true)
				else
					releaseSpawnSlot(data, i, m, "despawn_all_held_parented_away")
				end
				continue
			end

			if st then
				clearActiveState(m, st, "despawn_all")
			else
				releaseSpawnSlot(data, i, m, "despawn_all")
			end
			pcall(function()
				m:Destroy()
			end)
		end
	end
end

local function buildSecretPool()
	local pool = {}
	for i = 1, #entries do
		local e = entries[i]
		local r = tostring(e.Rarity or ""):lower()
		local id = tostring(e.Id or ""):lower()

		if r:find("secret") or id:find("secret") then
			pool[#pool + 1] = e
		end
	end
	return pool
end

local secretEntries = buildSecretPool()

local function pickRandomPartData()
	local candidates = {}
	for i = 1, #partDataList do
		local data = partDataList[i]
		if data
			and not data.Disabled
			and (data.PlacementRarity == "Secret" or data.PlacementRarity == "Omega")
			and reconcileSpawnData(data, "like_goal_secret_candidate")
		then
			candidates[#candidates + 1] = data
		end
	end

	if #candidates == 0 then
		return nil
	end
	return candidates[rng:NextInteger(1, #candidates)]
end

local function spawnRandomSecretIgnoreLimits()
	local data = pickRandomPartData()
	if not data or not data.Part or not data.Part.Parent then
		spawnWarn("likeGoal skipped reason=no_secret_spawn_parts")
		return
	end

	local freeIndex = findFreeSlotRandom(data, os.clock())
	if not freeIndex then
		spawnWarn("likeGoal skipped reason=no_free_secret_slot spawnPart=%s", formatInstancePath(data.Part))
		return
	end

	local baseEntry
	if #secretEntries > 0 then
		baseEntry = secretEntries[rng:NextInteger(1, #secretEntries)]
	else
		spawnWarn("likeGoal skipped reason=no_secret_entries")
		return
	end
	if not validateChosenEntryForPlacementRarity(data, baseEntry, "likeGoalSecret") then
		return
	end

	local variantKey = "Normal"

	local template, usedVariant = Registry.GetTemplateWithFallback(baseEntry.Id, variantKey)
	if not template then
		spawnWarn("likeGoal skipped reason=missing_template crewMember=%s", tostring(baseEntry.Id))
		return
	end
	variantKey = usedVariant or variantKey

	local finalId = Registry.MakeVariantId(baseEntry.Id, variantKey)
	local finalInfo = Registry.GetOrBuildVariantInfo(baseEntry.Id, variantKey) or baseEntry.Info
	if not finalInfo then
		spawnWarn(
			"likeGoal skipped reason=missing_variant_info crewMember=%s variant=%s",
			tostring(baseEntry.Id),
			tostring(variantKey)
		)
		return
	end

	local entry = {
		Id = finalId,
		Info = finalInfo,
		Template = template,
		Rarity = "Secret",
		Tier = baseEntry.Tier,
		Foot = baseEntry.Foot,
		BaseId = baseEntry.Id,
		Variant = variantKey,
	}

	local clone = template:Clone()
	clone.Name = finalId
	clone.Parent = data.Container

	Placement.EnsurePrimaryPart(clone)
	Placement.AnchorModel(clone)

	local _, modelSize = clone:GetBoundingBox()

	local effX = data.Part.Size.X * 0.9
	local effZ = data.Part.Size.Z * 0.9
	local halfX = math.max(0, (effX / 2) - (modelSize.X / 2))
	local halfZ = math.max(0, (effZ / 2) - (modelSize.Z / 2))

	local offsetXZ = Vector2.new(
		rng:NextNumber(-halfX, halfX),
		rng:NextNumber(-halfZ, halfZ)
	)

	local yaw = rng:NextNumber(0, math.pi * 2)

	Placement.AlignModelOnPartUpright(clone, data.Part, offsetXZ, yaw)
	data.SlotOffsets[freeIndex] = offsetXZ
	data.SlotOccupied[freeIndex] = clone
	refreshVariantAura(clone, entry)
	tryPlayIdle(clone, entry)
	registerActive(clone, entry, data, freeIndex)
	trySpawnDormantSpikeForCrew(clone, data)

	spawnTrace(
		"likeGoalSpawn rarity=%s crewMember=%s chosenSpawnPart=%s chosenSpawnPartPos=%s finalParent=%s finalPosition=%s",
		"Secret",
		tostring(finalId),
		formatInstancePath(data.Part),
		formatVector3(data.Part.Position),
		formatInstancePath(clone.Parent),
		formatVector3(clone:GetPivot().Position)
	)
end

local LIKEGOAL_COOLDOWN = 30
local pendingSecretSpawns = 0
local processingSecretQueue = false
local nextSecretAllowedAt = 0

local function processSecretQueue()
	if processingSecretQueue then
		return
	end

	processingSecretQueue = true
	task.spawn(function()
		while pendingSecretSpawns > 0 do
			local now = os.clock()
			if now < nextSecretAllowedAt then
				task.wait(nextSecretAllowedAt - now)
			end

			pendingSecretSpawns -= 1
			spawnRandomSecretIgnoreLimits()
			nextSecretAllowedAt = os.clock() + LIKEGOAL_COOLDOWN
		end

		processingSecretQueue = false
	end)
end

LikeGoalSpawnSecret.Event:Connect(function(_count)
	pendingSecretSpawns += 1
	processSecretQueue()
end)


local rrIndex = 0
local lastReconcileAt = 0
local SPAWN_LOOP_FRAME_BUDGET_SECONDS = 0.006

while true do
	local positions = getPlayerPositions()
	local now = os.clock()
	local sliceStartedAt = os.clock()
	local shouldReconcile = (now - lastReconcileAt) >= RECONCILE_INTERVAL
	if shouldReconcile then
		lastReconcileAt = now
		for i = 1, #partDataList do
			reconcileSpawnData(partDataList[i], "periodic_audit")
			if os.clock() - sliceStartedAt >= SPAWN_LOOP_FRAME_BUDGET_SECONDS then
				task.wait()
				sliceStartedAt = os.clock()
			end
		end
	end

	for model, st in pairs(active) do
		if not model.Parent then
			clearActiveState(model, st, "destroyed_or_removed")
		else
			if st.OriginData and st.SlotIndex and st.OriginData.Container and model.Parent ~= st.OriginData.Container then
				releaseStateOriginSlot(st, model, "parented_away_from_spawn_folder", true)
			end

			if isHeldCrewMemberModel(model, st) then
				st.LastUpdate = now
			else
				local dt = now - (st.LastUpdate or now)
				st.LastUpdate = now
				st.Remaining = (st.Remaining or 0) - dt

				local remainingInt = math.ceil(st.Remaining)
				if remainingInt < 0 then
					remainingInt = 0
				end

				if remainingInt ~= st.LastShown then
					st.LastShown = remainingInt
				end

				if st.Remaining <= 0 and not isTutorialCrewMemberModel(model) then
					clearActiveState(model, st, "expired")
					pcall(function()
						model:Destroy()
					end)
				end
			end
		end
		if os.clock() - sliceStartedAt >= SPAWN_LOOP_FRAME_BUDGET_SECONDS then
			task.wait()
			sliceStartedAt = os.clock()
		end
	end


	local ops = 0
	local n = #partDataList

	if n > 0 then
		for _ = 1, n do
			rrIndex += 1
			if rrIndex > n then
				rrIndex = 1
			end

			local data = partDataList[rrIndex]
			if data and not data.Disabled and reconcileSpawnData(data, "spawn_loop") then
				local near = anyPlayerNearPart(data.Part, positions, SpawnerConfig.PlayerSpawnRadius)
				if not near then
					if SpawnerConfig.DespawnWhenNoPlayers then
						despawnAllInData(data)
					end
				else
					local did = spawnOne(data)
					if did then
						ops += 1
						if ops >= SpawnerConfig.MaxSpawnOperationsPerTick then
							break
						end
					end
				end
			end
			if os.clock() - sliceStartedAt >= SPAWN_LOOP_FRAME_BUDGET_SECONDS then
				task.wait()
				sliceStartedAt = os.clock()
			end
		end
	end
 

  
	task.wait(SpawnerConfig.TickInterval)
end

end

return CrewSpawnRuntime
