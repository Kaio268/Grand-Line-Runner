local Config = {
	AssetRootName = "ReplicatedStorage",
	AssetPath = { "Assets", "Ships" },
	RuntimeModelName = "ActiveShip",
	MaxLevel = 8,
	CaptainSlotName = "Captain's Spot",
	ShipCrewPlacementRotationOffsetDegrees = 0,

	ShipSystemPath = { "Map", "Main Map", "ShipSystem" },
	ActiveShipsName = "ActiveShips",
	ShipPositionsName = "ShipPositions",
	ShipPositionName = "Pos",

	Attributes = {
		ActiveModelName = "ActiveShipModelName",
		ActiveTier = "ActiveShipTier",
		ActiveUpgradeLevel = "ActiveShipUpgradeLevel",
		InteractionKind = "ShipInteractionKind",
		InteractionSlotKey = "ShipInteractionSlotKey",
		IsActiveShip = "ShipRuntimeActive",
		OwnerName = "OwnerName",
		OwnerOnlyInteraction = "ShipOwnerOnlyInteraction",
		OwnerUserId = "OwnerUserId",
		PositionIndex = "ShipPositionIndex",
		PositionName = "ShipPositionName",
		SourceModelName = "ShipVisualModelName",
		SourceTier = "ShipVisualTier",
		NormalCrewSlots = "ActiveShipNormalCrewSlots",
		AssetNormalSlotCapacity = "ActiveShipAssetNormalSlotCapacity",
	},

	InteractionKinds = {
		CaptainSlot = "CaptainSlot",
		ClaimPad = "ClaimPad",
		CrewSlot = "CrewSlot",
		GroupReward = "GroupReward",
		SlotWorldUi = "SlotWorldUi",
	},

	RuntimeSafetyAttributes = {
		PreserveCollision = "ShipVisualPreserveCollision",
		WalkableCollision = "ShipWalkableCollision",
		ForceNoCollision = "ShipForceNoCollision",
		PreserveTouch = "ShipVisualPreserveTouch",
		PreserveQuery = "ShipVisualPreserveQuery",
		PreservePhysics = "ShipVisualPreservePhysics",
		AllowScripts = "ShipVisualAllowScripts",
	},

	WalkableCollisionFolderNames = {
		"ShipCollision",
		"WalkableCollision",
	},

	NoCollisionFolderNames = {
		"NoCollision",
		"DecorativeNoCollision",
	},

	SailName = {
		Enabled = true,
		FolderName = "ShipSailCustomization",
		AnchorName = "ShipSailIdentityAnchor",
		SurfaceGuiName = "ShipSailIdentitySurfaceGui",
		RuntimeAttribute = "ShipSailIdentityRuntime",
		EnabledAttribute = "SailIdentityEnabled",
		OwnerUserIdAttribute = "ShipSailIdentityOwnerUserId",
		OwnerNameAttribute = "ShipSailIdentityOwnerName",
		DisplayTextAttribute = "ShipSailIdentityDisplayText",
		OwnerDisplayTextAttribute = "OwnerDisplayText",
		ConfigKeyAttribute = "ShipSailIdentityConfigKey",
		FailureReasonAttribute = "ShipSailIdentityFailureReason",
		CanvasSize = Vector2.new(512, 192),
		PixelsPerStud = 50,
		SurfaceFace = Enum.NormalId.Back,
		LightInfluence = 0.15,
		MaxDistance = 250,
		Side = "Back",
		SurfaceOffset = 0.12,
		AnchorDepth = 0.05,
		MaxDisplayNameLength = 24,

		DisplayNameAttributes = {
			"ShipDisplayName",
			"CrewDisplayName",
			"CustomShipName",
			"CustomCrewName",
		},

		Models = {
			["Lvl 1 Ship"] = {
				Enabled = true,
				FlagPath = { "Ship Mesh", "Flags" },
				AnchorSize = Vector3.new(22, 6.5, 0.05),
			},

			["Lvl 2 Ship"] = {
				Enabled = true,
				FlagPath = { "Ship Mesh", "Flags" },
				AnchorSize = Vector3.new(28, 7.5, 0.05),
			},

			["Lvl 3 Ship"] = {
				Enabled = true,
				FlagPath = { "Ship Mesh", "Flags" },
				AnchorSize = Vector3.new(30, 9.5, 0.05),
			},

			["Lvl 4 Ship"] = {
				Enabled = true,
				FlagPath = { "Ship Mesh", "Flags" },
				AnchorSize = Vector3.new(42, 13, 0.05),
			},

			["Lvl 5 Ship"] = {
				Enabled = true,
				FlagPath = { "Ship Mesh", "Flags" },
				AnchorSize = Vector3.new(48, 16, 0.05),
			},
		},
	},

	RuntimePoints = {
		FolderName = "ShipRuntimePoints",
		Spawn = {
			Name = "ShipSpawnPoint",
			PreferredMarkerName = "Spawn",
			MarkerNames = { "Spawn", "spawn", "ShipSpawn", "SpawnPoint", "PlayerSpawn", "Ship Spawn", "SpawnLocation", "Captain's Spot" },
			MarkerWorldOffset = Vector3.new(0, 4, 0),
			Fallback = {
				PositionScale = Vector3.new(0, 0.5, 0),
				WorldOffset = Vector3.new(0, 8, 0),
				Facing = "Forward",
			},
			Size = Vector3.new(4, 1, 4),
		},
		Upgrade = {
			Name = "ShipUpgradePoint",
			PreferredMarkerName = "ShipUpgradePoint",
			MarkerNames = { "ShipUpgradePoint", "UpgradePoint", "Upgrade" },
			PromptWorldOffset = Vector3.new(0, 3, 0),
			PromptLocalOffset = Vector3.new(0, 0, 0),
			PromptWorldSize = Vector3.new(4.8, 2.7, 0.2),
			PromptWorldScale = 2,
			PromptCanvasSize = Vector2.new(720, 430),
			PromptMaxDistance = 46,
			PromptAlwaysOnTop = false,
			PromptInputCanQuery = true,
			PromptLightInfluence = 0.15,
			PromptYawOffsetDegrees = 0,
			Fallback = {
				PositionScale = Vector3.new(0.62, -0.2, -0.18),
				WorldOffset = Vector3.new(0, 5, 0),
				Facing = "Outward",
			},
		},
		GroupReward = {
			Name = "GroupReward",
			HitboxName = "Hitbox",
			PreferredMarkerName = "GroupRewardPoint",
			MarkerNames = { "GroupRewardPoint", "GroupReward" },
			Fallback = {
				PositionScale = Vector3.new(-0.62, -0.2, -0.18),
				WorldOffset = Vector3.new(0, 4, 0),
				Facing = "Outward",
			},
			Size = Vector3.new(6, 6, 6),
		},
		Home = {
			Name = "HOME",
			PreferredMarkerName = "HomeIndicatorPoint",
			MarkerNames = { "HomeIndicatorPoint", "HomePoint", "HOME", "Home" },
			Fallback = {
				PositionScale = Vector3.new(0, 0.58, 0),
				WorldOffset = Vector3.new(0, 4, 0),
				Facing = "Forward",
			},
			Size = Vector3.new(2, 2, 2),
		},
		OwnerSign = {
			Name = "ShipOwnerSign",
			PreferredMarkerName = "ShipOwnerSign",
			MarkerNames = { "ShipOwnerSign", "OwnerSign", "Sign", "PlayerDisplay" },
			Fallback = {
				PositionScale = Vector3.new(0, -0.16, -0.62),
				WorldOffset = Vector3.new(0, 6, 0),
				Facing = "Outward",
			},
			SurfaceFace = Enum.NormalId.Front,
			FacingCorrectionDegrees = 0,
			Size = Vector3.new(8, 4, 1),
		},
	},

	ShipModels = {
		["Lvl 1 Ship"] = {
			Tier = 1,
			NormalSlotCapacity = 6,
		},
		["Lvl 2 Ship"] = {
			Tier = 2,
			NormalSlotCapacity = 8,
		},
		["Lvl 3 Ship"] = {
			Tier = 3,
			NormalSlotCapacity = 12,
		},
		["Lvl 4 Ship"] = {
			Tier = 4,
			NormalSlotCapacity = 24,
		},
		["Lvl 5 Ship"] = {
			Tier = 5,
			NormalSlotCapacity = 24,
		},
	},

	UpgradeLevels = {
		[0] = {
			ModelName = "Lvl 1 Ship",
			NormalCrewSlots = 4,
			CaptainSlotUnlocked = false,
			CaptainState = "inactive",
			CaptainBonusPercent = 0,
			UpgradeRewardLabel = "Lvl 1 Ship with 4 normal crew slots",
		},
		[1] = {
			ModelName = "Lvl 1 Ship",
			NormalCrewSlots = 6,
			CaptainSlotUnlocked = false,
			CaptainState = "inactive",
			CaptainBonusPercent = 0,
			UpgradeRewardLabel = "Lvl 1 Ship expands to 6 normal crew slots",
		},
		[2] = {
			ModelName = "Lvl 2 Ship",
			NormalCrewSlots = 8,
			CaptainSlotUnlocked = false,
			CaptainState = "inactive",
			CaptainBonusPercent = 0,
			UpgradeRewardLabel = "Lvl 2 Ship unlocks 8 normal crew slots",
		},
		[3] = {
			ModelName = "Lvl 2 Ship",
			NormalCrewSlots = 8,
			CaptainSlotUnlocked = true,
			CaptainState = "unlocked",
			CaptainBonusPercent = 5,
			CaptainBonusLabel = "Captain's Spot +5%",
			UpgradeRewardLabel = "Captain's Spot unlocked: Captain earns +5%",
		},
		[4] = {
			ModelName = "Lvl 3 Ship",
			NormalCrewSlots = 12,
			CaptainSlotUnlocked = true,
			CaptainState = "unlocked",
			CaptainBonusPercent = 8,
			CaptainBonusLabel = "Captain's Spot +8%",
			UpgradeRewardLabel = "Lvl 3 Ship unlocks 12 normal crew slots and Captain earns +8%",
		},
		[5] = {
			ModelName = "Lvl 3 Ship",
			NormalCrewSlots = 12,
			CaptainSlotUnlocked = true,
			CaptainState = "upgraded",
			CaptainBonusPercent = 12,
			CaptainBonusLabel = "Captain's Spot +12%",
			UpgradeRewardLabel = "Captain Slot bonus upgraded to +12%",
		},
		[6] = {
			ModelName = "Lvl 4 Ship",
			NormalCrewSlots = 16,
			CaptainSlotUnlocked = true,
			CaptainState = "upgraded",
			CaptainBonusPercent = 16,
			CaptainBonusLabel = "Captain's Spot +16%",
			UpgradeRewardLabel = "Lvl 4 Ship unlocks 16 normal crew slots and Captain earns +16%",
		},
		[7] = {
			ModelName = "Lvl 4 Ship",
			NormalCrewSlots = 24,
			CaptainSlotUnlocked = true,
			CaptainState = "upgraded",
			CaptainBonusPercent = 20,
			CaptainBonusLabel = "Captain's Spot +20%",
			UpgradeRewardLabel = "Lvl 4 Ship expands to 24 normal crew slots and Captain earns +20%",
		},
		[8] = {
			ModelName = "Lvl 5 Ship",
			NormalCrewSlots = 24,
			CaptainSlotUnlocked = true,
			CaptainState = "maxed",
			CaptainBonusPercent = 25,
			CaptainBonusLabel = "Captain's Spot +25%",
			UpgradeRewardLabel = "Lvl 5 Ship reaches max Captain Slot bonus at +25%",
		},
	},
}

local function normalizeUpgradeLevel(level)
	return math.clamp(math.floor(tonumber(level) or 0), 0, Config.MaxLevel)
end

local function cloneUpgradeEntry(entry)
	if typeof(entry) ~= "table" then
		return nil
	end

	return table.clone(entry)
end

local function getModelConfig(modelName)
	local config = Config.ShipModels[tostring(modelName or "")]
	if typeof(config) ~= "table" then
		return nil
	end

	return config
end

local function getEntryForUpgradeLevel(level)
	local upgradeLevel = normalizeUpgradeLevel(level)
	local entry = Config.UpgradeLevels[upgradeLevel]

	if typeof(entry) == "table" then
		return entry, upgradeLevel
	end

	for candidate = upgradeLevel, 0, -1 do
		entry = Config.UpgradeLevels[candidate]
		if typeof(entry) == "table" then
			return entry, candidate
		end
	end

	return Config.UpgradeLevels[0], 0
end

local function getBandRangeForEntry(level, entry)
	local minLevel = level
	local maxLevel = level

	for candidate = level - 1, 0, -1 do
		local candidateEntry = Config.UpgradeLevels[candidate]
		if
			typeof(candidateEntry) == "table"
			and candidateEntry.ModelName == entry.ModelName
		then
			minLevel = candidate
		else
			break
		end
	end

	for candidate = level + 1, Config.MaxLevel do
		local candidateEntry = Config.UpgradeLevels[candidate]
		if
			typeof(candidateEntry) == "table"
			and candidateEntry.ModelName == entry.ModelName
		then
			maxLevel = candidate
		else
			break
		end
	end

	return minLevel, maxLevel
end

local function visualFromEntry(level, entry)
	if typeof(entry) ~= "table" then
		return nil
	end

	local modelName = tostring(entry.ModelName or "")
	local modelConfig = getModelConfig(modelName) or {}
	local minLevel, maxLevel = getBandRangeForEntry(level, entry)
	local normalCrewSlots = math.max(0, math.floor(tonumber(entry.NormalCrewSlots) or 0))

	return {
		Tier = math.max(1, math.floor(tonumber(modelConfig.Tier) or 1)),
		ModelName = modelName,
		MinUpgradeLevel = minLevel,
		MaxUpgradeLevel = maxLevel,
		NormalCrewSlots = normalCrewSlots,
		MaxCrewSlots = normalCrewSlots,
		AssetNormalSlotCapacity = math.max(0, math.floor(tonumber(modelConfig.NormalSlotCapacity) or normalCrewSlots)),
		CaptainSlotUnlocked = entry.CaptainSlotUnlocked == true,
		CaptainState = tostring(entry.CaptainState or "inactive"),
		CaptainBonusPercent = math.max(0, tonumber(entry.CaptainBonusPercent) or 0),
		CaptainBonusLabel = tostring(entry.CaptainBonusLabel or ""),
		UpgradeRewardLabel = tostring(entry.UpgradeRewardLabel or ""),
		UpgradeLevel = level,
	}
end

function Config.GetUpgradeLevelInfo(level)
	local entry, upgradeLevel = getEntryForUpgradeLevel(level)
	local result = cloneUpgradeEntry(entry)
	if not result then
		return nil
	end

	local modelConfig = getModelConfig(result.ModelName) or {}
	result.Level = upgradeLevel
	result.Tier = math.max(1, math.floor(tonumber(modelConfig.Tier) or 1))
	result.AssetNormalSlotCapacity = math.max(
		0,
		math.floor(tonumber(modelConfig.NormalSlotCapacity) or tonumber(result.NormalCrewSlots) or 0)
	)
	result.NormalCrewSlots = math.max(0, math.floor(tonumber(result.NormalCrewSlots) or 0))
	result.CaptainSlotUnlocked = result.CaptainSlotUnlocked == true
	result.CaptainState = tostring(result.CaptainState or "inactive")
	result.CaptainBonusPercent = math.max(0, tonumber(result.CaptainBonusPercent) or 0)
	result.CaptainBonusLabel = tostring(result.CaptainBonusLabel or "")

	return result
end

function Config.GetVisualBandForUpgradeLevel(level)
	local entry, upgradeLevel = getEntryForUpgradeLevel(level)
	return visualFromEntry(upgradeLevel, entry), upgradeLevel
end

function Config.GetVisualForUpgradeLevel(level)
	local visual = Config.GetVisualBandForUpgradeLevel(level)
	return visual
end

function Config.GetModelNameForUpgradeLevel(level)
	local visual = Config.GetVisualForUpgradeLevel(level)
	return visual and visual.ModelName or nil
end

function Config.GetTierForUpgradeLevel(level)
	local visual = Config.GetVisualForUpgradeLevel(level)
	return visual and visual.Tier or nil
end

function Config.GetMaxCrewSlotsForUpgradeLevel(level)
	return Config.GetNormalCrewSlotsForUpgradeLevel(level)
end

function Config.GetNormalCrewSlotsForUpgradeLevel(level)
	local info = Config.GetUpgradeLevelInfo(level)
	return info and info.NormalCrewSlots or 0
end

function Config.GetAssetNormalSlotCapacityForUpgradeLevel(level)
	local info = Config.GetUpgradeLevelInfo(level)
	return info and info.AssetNormalSlotCapacity or 0
end

function Config.GetNormalCrewSlotsByLevel()
	local result = {}

	for level = 0, Config.MaxLevel do
		result[level] = Config.GetNormalCrewSlotsForUpgradeLevel(level)
	end

	return result
end

function Config.GetCaptainSlotInfoForUpgradeLevel(level)
	local info = Config.GetUpgradeLevelInfo(level)
	local bonusPercent = info and info.CaptainBonusPercent or 0
	local unlocked = info and info.CaptainSlotUnlocked == true or false

	return {
		SlotName = Config.CaptainSlotName,
		Unlocked = unlocked,
		State = info and info.CaptainState or "inactive",
		BonusPercent = bonusPercent,
		BonusMultiplier = 1 + (bonusPercent / 100),
		BonusLabel = info and info.CaptainBonusLabel or "",
	}
end

function Config.GetFallbackVisualsForUpgradeLevel(level)
	local visuals = {}
	local seenModels = {}
	local upgradeLevel = normalizeUpgradeLevel(level)

	for candidate = upgradeLevel, 0, -1 do
		local visual = Config.GetVisualForUpgradeLevel(candidate)
		if visual and visual.ModelName ~= "" and not seenModels[visual.ModelName] then
			seenModels[visual.ModelName] = true
			visuals[#visuals + 1] = visual
		end
	end

	return visuals
end

function Config.GetAssetPathLabel()
	local segments = table.clone(Config.AssetPath or {})
	table.insert(segments, 1, Config.AssetRootName)
	return table.concat(segments, ".")
end

return Config
