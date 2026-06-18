local ShipVisuals = require(script.Parent:WaitForChild("ShipVisuals"))
local Economy = require(script.Parent:WaitForChild("GrandLineRushEconomy"))

local Config = {
	DisplayName = "Ship Upgrade",
	InternalStatName = "PlotUpgrade",
	MaxLevel = ShipVisuals.MaxLevel or 8,
	CaptainSlotName = ShipVisuals.CaptainSlotName,

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

	UsableStandCountByLevel = ShipVisuals.GetNormalCrewSlotsByLevel(),

	LevelUnlockDescriptions = {
		[1] = "Lvl 1 Ship expands to 6 normal crew slots",
		[2] = "Lvl 2 Ship unlocks 8 normal crew slots",
		[3] = "Captain's Spot unlocked (Captain earns +5%)",
		[4] = "Lvl 3 Ship unlocks 12 normal crew slots and Captain earns +8%",
		[5] = "Captain Slot bonus upgraded to +12%",
		[6] = "Lvl 4 Ship unlocks 16 normal crew slots and Captain earns +16%",
		[7] = "Lvl 4 Ship expands to 26 normal crew slots and Captain earns +20%",
		[8] = "Lvl 5 Ship unlocks 38 normal crew slots and reaches max Captain Slot bonus (+25%)",
	},

	RequirementsByLevel = {
		[0] = {
			Beli = 1_000,
			Materials = {
				Timber = 25,
			},
		},
		[1] = {
			Beli = 3_000,
			Materials = {
				Timber = 50,
			},
		},
		[2] = {
			Beli = 7_500,
			Materials = {
				Timber = 90,
				Iron = 10,
			},
		},
		[3] = {
			Beli = 15_000,
			Materials = {
				Timber = 140,
				Iron = 25,
			},
		},
		[4] = {
			Beli = 35_000,
			Materials = {
				Timber = 220,
				Iron = 50,
				AncientTimber = 3,
			},
		},
		[5] = {
			Beli = 75_000,
			Materials = {
				Timber = 320,
				Iron = 90,
				AncientTimber = 6,
			},
		},
		[6] = {
			Beli = 150_000,
			Materials = {
				Timber = 450,
				Iron = 140,
				AncientTimber = 10,
			},
		},
		[7] = {
			Beli = 225_000,
			Materials = {
				Timber = 600,
				Iron = 220,
				AncientTimber = 14,
			},
		},
	},

	RebirthRequirementsByLevel = {
		[1] = 0,
		[2] = 0,
		[3] = 0,
		[4] = 0,
		[5] = 1,
		[6] = 3,
		[7] = 6,
		[8] = 10,
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

	local requirement = Config.RequirementsByLevel[clamped]
	if typeof(requirement) ~= "table" then
		return nil
	end

	local materials = table.clone(typeof(requirement.Materials) == "table" and requirement.Materials or {})
	for materialKey, amount in pairs(materials) do
		materials[materialKey] = Economy.ScaleAmount(amount)
	end

	return {
		Beli = Economy.ScaleAmount(math.max(0, math.floor(tonumber(requirement.Beli or requirement.Doubloons) or 0))),
		Materials = materials,
		Rebirths = Config.GetRequiredRebirthsForLevel(clamped + 1),
		TargetLevel = clamped + 1,
	}
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

function Config.GetRequiredRebirthsForLevel(level)
	local clamped = Config.ClampLevel(level)
	if clamped <= 0 then
		return 0
	end

	return math.max(0, math.floor(tonumber(Config.RebirthRequirementsByLevel[clamped]) or 0))
end

function Config.HasRequiredRebirthsForLevel(level, rebirths)
	local required = Config.GetRequiredRebirthsForLevel(level)
	local currentRebirths = math.max(0, math.floor(tonumber(rebirths) or 0))
	return currentRebirths >= required
end

function Config.GetEffectiveLevel(level, rebirths)
	local clamped = Config.ClampLevel(level)
	while clamped > 0 and not Config.HasRequiredRebirthsForLevel(clamped, rebirths) do
		clamped -= 1
	end

	return clamped
end

function Config.GetUsableStandCount(level, rebirths)
	local clamped = Config.GetEffectiveLevel(level, rebirths)
	return ShipVisuals.GetNormalCrewSlotsForUpgradeLevel(clamped)
end

local function normalizeStandNumber(standName)
	local standNumber = tonumber(tostring(standName or ""))
	if not standNumber then
		return nil
	end

	standNumber = math.floor(standNumber)
	return if standNumber >= 1 then standNumber else nil
end

function Config.IsStandVisible(level, standName, rebirths)
	local standNumber = normalizeStandNumber(standName)
	if not standNumber then
		return false
	end

	local effectiveLevel = Config.GetEffectiveLevel(level, rebirths)
	return standNumber <= ShipVisuals.GetAssetNormalSlotCapacityForUpgradeLevel(effectiveLevel)
end

function Config.IsStandUsable(level, standName, rebirths)
	local standNumber = normalizeStandNumber(standName)
	if not standNumber then
		return false
	end

	return Config.IsStandVisible(level, standName, rebirths) and standNumber <= Config.GetUsableStandCount(level, rebirths)
end

function Config.GetStandUnlockLevel(standName)
	for level = 0, Config.MaxLevel do
		if Config.IsStandUsable(level, standName, math.huge) then
			return level
		end
	end

	return nil
end

function Config.GetLockedSlotDescription(level, standName, rebirths)
	if not Config.IsStandVisible(level, standName, rebirths) or Config.IsStandUsable(level, standName, rebirths) then
		return nil
	end

	local unlockLevel = Config.GetStandUnlockLevel(standName)
	if unlockLevel ~= nil then
		local requiredRebirths = Config.GetRequiredRebirthsForLevel(unlockLevel)
		local currentRebirths = math.max(0, math.floor(tonumber(rebirths) or 0))
		if currentRebirths < requiredRebirths then
			return string.format("Requires %d rebirth%s", requiredRebirths, requiredRebirths == 1 and "" or "s")
		end

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
	local description = Config.LevelUnlockDescriptions[clamped] or ("Unlock level " .. tostring(clamped))
	local requiredRebirths = Config.GetRequiredRebirthsForLevel(clamped)
	if requiredRebirths > 0 then
		return string.format(
			"%s (Requires %d rebirth%s)",
			description,
			requiredRebirths,
			requiredRebirths == 1 and "" or "s"
		)
	end

	return description
end

function Config.GetCaptainSlotInfo(level, rebirths)
	local effectiveLevel = Config.GetEffectiveLevel(level, rebirths)
	return ShipVisuals.GetCaptainSlotInfoForUpgradeLevel(effectiveLevel)
end

function Config.IsCaptainSlotUnlocked(level, rebirths)
	local info = Config.GetCaptainSlotInfo(level, rebirths)
	return info and info.Unlocked == true
end

function Config.GetCaptainBonusPercent(level, rebirths)
	local info = Config.GetCaptainSlotInfo(level, rebirths)
	return info and info.BonusPercent or 0
end

function Config.GetCaptainBonusMultiplier(level, rebirths)
	local percent = Config.GetCaptainBonusPercent(level, rebirths)
	return 1 + (math.max(0, tonumber(percent) or 0) / 100)
end

return Config
