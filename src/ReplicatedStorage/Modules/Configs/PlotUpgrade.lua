local Config = {
	DisplayName = "Ship Upgrade",
	InternalStatName = "PlotUpgrade",
	MaxLevel = 7,

	MaterialOrder = {
		"Timber",
		"Iron",
		"AncientTimber",
	},

	MaterialDisplayNames = {
		Timber = "Timber",
		Iron = "Iron",
		AncientTimber = "Ancient Timber",
	},

	FloorUnlockLevels = {
		Floor1 = 0,
		Floor2 = 4,
		Floor3 = 6,
	},

	StandFloorRanges = {
		Floor1 = { 1, 8 },
		Floor2 = { 9, 16 },
		Floor3 = { 17, 24 },
	},

	UsableStandCountByLevel = {
		[0] = 4,
		[1] = 6,
		[2] = 8,
		[3] = 8,
		[4] = 16,
		[5] = 16,
		[6] = 24,
		[7] = 24,
	},

	LevelUnlockDescriptions = {
		[1] = "Floor 1 now has 6/8 usable slots",
		[2] = "Floor 1 now has 8/8 usable slots",
		[3] = "Captain Slot unlocked on Floor 1 Slot 1 (+25%)",
		[4] = "Floor 2 unlocked with all 8 slots usable",
		[5] = "First Mate Slot unlocked on Floor 2 Slot 1 (+20%)",
		[6] = "Floor 3 unlocked with all 8 slots usable",
		[7] = "Final special slot unlocked on Floor 3 Slot 1 (+15%)",
	},

	RequirementsByLevel = {
		[0] = {
			Doubloons = 1_000,
			Materials = {
				Timber = 25,
			},
		},
		[1] = {
			Doubloons = 3_000,
			Materials = {
				Timber = 50,
			},
		},
		[2] = {
			Doubloons = 7_500,
			Materials = {
				Timber = 90,
				Iron = 10,
			},
		},
		[3] = {
			Doubloons = 15_000,
			Materials = {
				Timber = 140,
				Iron = 25,
			},
		},
		[4] = {
			Doubloons = 35_000,
			Materials = {
				Timber = 220,
				Iron = 50,
				AncientTimber = 3,
			},
		},
		[5] = {
			Doubloons = 75_000,
			Materials = {
				Timber = 320,
				Iron = 90,
				AncientTimber = 6,
			},
		},
		[6] = {
			Doubloons = 150_000,
			Materials = {
				Timber = 450,
				Iron = 140,
				AncientTimber = 10,
			},
		},
	},

	SlotBonuses = {
		["1"] = {
			Label = "Captain Slot",
			UnlockLevel = 3,
			Multiplier = 1.25,
			Floor = 1,
			Slot = 1,
		},
		["9"] = {
			Label = "First Mate Slot",
			UnlockLevel = 5,
			Multiplier = 1.20,
			Floor = 2,
			Slot = 1,
		},
		["17"] = {
			Label = "Final Slot",
			UnlockLevel = 7,
			Multiplier = 1.15,
			Floor = 3,
			Slot = 1,
		},
	},
}

function Config.ClampLevel(level)
	local numericLevel = math.floor(tonumber(level) or 0)
	return math.clamp(numericLevel, 0, Config.MaxLevel)
end

function Config.IsMaxLevel(level)
	return Config.ClampLevel(level) >= Config.MaxLevel
end

function Config.GetNextLevel(level)
	local clamped = Config.ClampLevel(level)
	if clamped >= Config.MaxLevel then
		return nil
	end

	return clamped + 1
end

function Config.GetRequirementForLevel(level)
	local clamped = Config.ClampLevel(level)
	if clamped >= Config.MaxLevel then
		return nil
	end

	return Config.RequirementsByLevel[clamped]
end

function Config.GetMaterialCost(requirement, materialKey)
	if typeof(requirement) ~= "table" then
		return 0
	end

	local materials = requirement.Materials
	if typeof(materials) ~= "table" then
		return 0
	end

	return math.max(0, math.floor(tonumber(materials[materialKey]) or 0))
end

function Config.GetUsableStandCount(level)
	local clamped = Config.ClampLevel(level)
	return Config.UsableStandCountByLevel[clamped] or 0
end

function Config.IsFloorUnlocked(level, floorName)
	local unlockLevel = Config.FloorUnlockLevels[tostring(floorName)] or math.huge
	return Config.ClampLevel(level) >= unlockLevel
end

function Config.GetStandFloorName(standName)
	local standNumber = tonumber(tostring(standName or ""))
	if not standNumber then
		return nil
	end

	for floorName, range in pairs(Config.StandFloorRanges) do
		local startStand = tonumber(range[1]) or 0
		local endStand = tonumber(range[2]) or -1
		if standNumber >= startStand and standNumber <= endStand then
			return floorName
		end
	end

	return nil
end

function Config.IsStandVisible(level, standName)
	local floorName = Config.GetStandFloorName(standName)
	if floorName == nil then
		return false
	end

	return Config.IsFloorUnlocked(level, floorName)
end

function Config.IsStandUsable(level, standName)
	local standNumber = tonumber(tostring(standName or ""))
	if not standNumber then
		return false
	end

	return Config.IsStandVisible(level, standName) and standNumber <= Config.GetUsableStandCount(level)
end

function Config.GetStandUnlockLevel(standName)
	for level = 0, Config.MaxLevel do
		if Config.IsStandUsable(level, standName) then
			return level
		end
	end

	return nil
end

function Config.GetLockedSlotDescription(level, standName)
	if not Config.IsStandVisible(level, standName) or Config.IsStandUsable(level, standName) then
		return nil
	end

	local unlockLevel = Config.GetStandUnlockLevel(standName)
	if unlockLevel ~= nil then
		return string.format("Unlock at Lv %d", unlockLevel)
	end

	return "Locked"
end

function Config.GetNextUnlockDescription(level)
	local nextLevel = Config.GetNextLevel(level)
	if nextLevel == nil then
		return "Ship fully upgraded"
	end

	return Config.GetLevelUnlockDescription(nextLevel)
end

function Config.GetLevelUnlockDescription(level)
	local clamped = Config.ClampLevel(level)
	return Config.LevelUnlockDescriptions[clamped] or ("Unlock level " .. tostring(clamped))
end

function Config.GetSlotBonusInfo(level, standName)
	local entry = Config.SlotBonuses[tostring(standName)]
	if typeof(entry) ~= "table" then
		return nil
	end

	if Config.ClampLevel(level) < tonumber(entry.UnlockLevel or Config.MaxLevel) then
		return nil
	end

	return entry
end

function Config.GetSlotBonusMultiplier(level, standName)
	local info = Config.GetSlotBonusInfo(level, standName)
	if info then
		return tonumber(info.Multiplier) or 1
	end

	return 1
end

return Config
