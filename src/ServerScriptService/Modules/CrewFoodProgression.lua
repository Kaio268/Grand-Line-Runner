local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

-- Crew progression now owns the old food/level behavior. The economy/config keys
-- still read Brainrots until the saved-data and balance migration is validated.
local dataManagerModule = nil
local function getDataManager()
	if dataManagerModule == nil then
		dataManagerModule = require(ServerScriptService:WaitForChild("Data"):WaitForChild("DataManager"))
	end
	return dataManagerModule
end
local DataManager = setmetatable({}, {
	__index = function(_, key)
		local value = getDataManager()[key]
		if typeof(value) == "function" then
			return function(_, ...)
				return value(getDataManager(), ...)
			end
		end
		return value
	end,
})
local CrewInstanceService = require(ServerScriptService:WaitForChild("Modules"):WaitForChild("CrewInstanceService"))
local CrewStandIncomeAuthority = require(ServerScriptService:WaitForChild("Modules"):WaitForChild("CrewStandIncomeAuthority"))
local Economy = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("GrandLineRushEconomy"))
local CrewCatalog = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Crew"):WaitForChild("CrewCatalog"))
local BrainrotsCfg = CrewCatalog.GetLegacyConfig()
local VariantCfg = CrewCatalog.GetVariantConfig()

local Module = {}
local CrewStorageModule = nil
local PROGRESSION_AUTHORITY_AUDIT_PATH = "CrewMemberProgressionAuthorityAudit"

local function getCrewStorage()
	if CrewStorageModule == nil then
		CrewStorageModule = require(ServerScriptService:WaitForChild("Modules"):WaitForChild("CrewStorage"))
	end
	return CrewStorageModule
end

local function cloneValue(value)
	if typeof(value) ~= "table" then
		return value
	end

	local copy = {}
	for key, child in pairs(value) do
		copy[key] = cloneValue(child)
	end
	return copy
end

local function isProgressionWriteAuthorityEnabled()
	local flags = getCrewStorage().GetShadowFlags()
	return flags.CrewMemberProgressionWriteAuthorityEnabled == true, flags
end

local function updateProgressionAuthorityAudit(player, updates)
	local audit = DataManager:GetValue(player, PROGRESSION_AUTHORITY_AUDIT_PATH)
	if typeof(audit) ~= "table" then
		audit = {}
	else
		audit = cloneValue(audit)
	end

	for key, value in pairs(if typeof(updates) == "table" then updates else {}) do
		if key ~= "ClearKeys" then
			audit[key] = value
		end
	end
	for _, key in ipairs(if typeof(updates) == "table" and typeof(updates.ClearKeys) == "table" then updates.ClearKeys else {}) do
		audit[tostring(key)] = nil
	end
	audit.UpdatedAt = os.time()
	DataManager:TrySetValue(player, PROGRESSION_AUTHORITY_AUDIT_PATH, audit)
	return audit
end

local function buildProgressionMutationSnapshot(player, sourcePath)
	return {
		Kind = "progression_write_authority",
		SourcePath = tostring(sourcePath or ""),
		PlayerUserId = player and player.UserId or 0,
		PlaceId = game.PlaceId,
		GameId = game.GameId,
		CreatedAt = os.time(),
		FoodInventory = cloneValue(DataManager:GetValue(player, "FoodInventory")),
		Inventory = cloneValue(DataManager:GetValue(player, "Inventory")),
		CrewMemberInventory = cloneValue(DataManager:GetValue(player, "CrewMemberInventory")),
		CrewMemberIncome = cloneValue(DataManager:GetValue(player, "CrewMemberIncome")),
		Audit = cloneValue(DataManager:GetValue(player, PROGRESSION_AUTHORITY_AUDIT_PATH)),
	}
end

local function restoreProgressionMutationSnapshot(player, snapshot, reason)
	if typeof(snapshot) ~= "table" then
		return false, "snapshot_missing"
	end
	if snapshot.Kind ~= "progression_write_authority" then
		return false, "snapshot_kind_mismatch"
	end
	if tonumber(snapshot.PlayerUserId) ~= (player and player.UserId or 0) then
		return false, "snapshot_user_mismatch"
	end
	if tonumber(snapshot.PlaceId) ~= game.PlaceId or tonumber(snapshot.GameId) ~= game.GameId then
		return false, "snapshot_environment_mismatch"
	end

	local writes = {}
	local function write(path, value)
		local ok, writeReason = DataManager:TrySetValue(player, path, cloneValue(value) or {})
		writes[path] = ok == true
		if ok ~= true then
			return false, tostring(writeReason or "")
		end
		return true, nil
	end

	local ok, writeReason = write("FoodInventory", snapshot.FoodInventory)
	if ok ~= true then
		return false, "food_inventory:" .. tostring(writeReason)
	end
	ok, writeReason = write("Inventory", snapshot.Inventory)
	if ok ~= true then
		return false, "inventory:" .. tostring(writeReason)
	end
	ok, writeReason = write("CrewMemberInventory", snapshot.CrewMemberInventory)
	if ok ~= true then
		return false, "crew_member_inventory:" .. tostring(writeReason)
	end
	ok, writeReason = write("CrewMemberIncome", snapshot.CrewMemberIncome)
	if ok ~= true then
		return false, "crew_member_income:" .. tostring(writeReason)
	end

	updateProgressionAuthorityAudit(player, {
		LastRollback = {
			Reason = tostring(reason or ""),
			Writes = writes,
			CompletedAt = os.time(),
		},
		LastRollbackSnapshot = snapshot,
	})
	return true, nil
end

local function refreshCrewMemberShadow(_player, _reason)
	-- Progression writes CrewMemberInventory/CrewMemberIncome directly now.
	-- Legacy projection remains available through explicit migration tools.
	return nil
end

function Module.RefreshProgressionShadow(player, reason)
	return refreshCrewMemberShadow(player, tostring(reason or "food_progression"))
end

local function syncAssignedStandLevel(player, instanceData, level)
	if typeof(instanceData) ~= "table" then
		return false
	end

	local assignedStand = tostring(instanceData.AssignedStand or "")
	if assignedStand == "" then
		return false
	end

	local safeLevel = math.max(1, math.floor(tonumber(level) or tonumber(instanceData.Level) or 1))
	return CrewStandIncomeAuthority.SetStandLevel(player, assignedStand, safeLevel, "food_progression_stand_level")
end

local function normalizeRarity(rawRarity)
	local rarity = tostring(rawRarity or "Common")
	if Economy.Brainrots.TotalXPMultiplierByRarity[rarity] then
		return rarity
	end
	return "Common"
end

local function getMaxLevel()
	return math.max(1, tonumber(Economy.Brainrots.MaxLevel) or 50)
end

local function getFoodPriority()
	return Economy.Brainrots.FoodAutoFeedPriority
end

local function getFoodDisplayName(foodKey)
	local config = Economy.Food[foodKey]
	return tostring(config and config.DisplayName or foodKey)
end

local function getFoodXP(foodKey)
	local config = Economy.Food[foodKey]
	return math.max(0, tonumber(config and config.XP) or 0)
end

local function getXPRequiredForLevel(rarity, level)
	if level >= getMaxLevel() then
		return 0
	end

	local multiplier = tonumber(Economy.Brainrots.TotalXPMultiplierByRarity[normalizeRarity(rarity)]) or 1
	for _, band in ipairs(Economy.Brainrots.BaseXPPerLevelBand) do
		if level >= band.MinLevel and level <= band.MaxLevel then
			return math.max(1, math.floor((tonumber(band.XPPerLevel) or 0) * multiplier + 0.5))
		end
	end

	return math.max(1, math.floor(40 * multiplier + 0.5))
end

local function getVariantAndBaseName(fullName)
	fullName = tostring(fullName or "")
	for _, variantKey in ipairs(VariantCfg.Order or {}) do
		if variantKey ~= "Normal" then
			local variant = (VariantCfg.Versions or {})[variantKey]
			local prefix = tostring(variant and variant.Prefix or (variantKey .. " "))
			if prefix ~= "" and fullName:sub(1, #prefix) == prefix then
				return variantKey, fullName:sub(#prefix + 1)
			end
		end
	end
	return "Normal", fullName
end

local function getStoredRarity(_player, storageName)
	local info = CrewCatalog.GetInfoById(storageName) or BrainrotsCfg[storageName]
	if type(info) == "table" then
		return normalizeRarity(info.Rarity)
	end

	local _, baseName = getVariantAndBaseName(storageName)
	local baseInfo = CrewCatalog.GetInfoById(baseName) or BrainrotsCfg[baseName]
	return normalizeRarity(baseInfo and baseInfo.Rarity or nil)
end

local function normalizeProgress(rarity, level, currentXP)
	local safeLevel = math.max(1, math.floor(tonumber(level) or 1))
	local safeXP = math.max(0, math.floor(tonumber(currentXP) or 0))
	local maxLevel = getMaxLevel()

	while safeLevel < maxLevel do
		local needed = getXPRequiredForLevel(rarity, safeLevel)
		if needed <= 0 or safeXP < needed then
			break
		end
		safeXP -= needed
		safeLevel += 1
	end

	if safeLevel >= maxLevel then
		safeLevel = maxLevel
		safeXP = 0
	end

	return safeLevel, safeXP
end

local function buildPreviewStep(plan)
	local firstStep = plan and plan.ConsumptionSteps and plan.ConsumptionSteps[1]
	if not firstStep then
		return nil
	end

	local nextStep = plan.ConsumptionSteps[2]
	return {
		FoodKey = tostring(firstStep.FoodKey),
		FoodDisplayName = getFoodDisplayName(firstStep.FoodKey),
		AmountUsed = math.max(0, math.floor(tonumber(firstStep.AmountUsed) or 0)),
		XPGained = math.max(0, math.floor(tonumber(firstStep.XPGained) or 0)),
		RemainingAfter = math.max(0, math.floor(tonumber(firstStep.RemainingAfter) or 0)),
		NextFoodKey = nextStep and tostring(nextStep.FoodKey) or nil,
		NextFoodDisplayName = nextStep and getFoodDisplayName(nextStep.FoodKey) or nil,
	}
end

function Module.GetFoodPriority()
	return getFoodPriority()
end

function Module.GetFoodDisplayName(foodKey)
	return getFoodDisplayName(foodKey)
end

function Module.GetFoodXP(foodKey)
	return getFoodXP(foodKey)
end

function Module.GetFoodPriorityDisplay()
	local names = {}
	for _, foodKey in ipairs(getFoodPriority()) do
		names[#names + 1] = getFoodDisplayName(foodKey)
	end
	return table.concat(names, " -> ")
end

function Module.GetXPRequiredForLevel(rarity, level)
	return getXPRequiredForLevel(rarity, level)
end

function Module.GetProgress(player, brainrotName)
	local instanceId, instanceData = CrewInstanceService.ResolveProgressTarget(player, brainrotName)
	if not instanceData then
		return nil
	end

	local storageName = tostring(instanceData.StorageName or "")
	local rarity = normalizeRarity(instanceData.Rarity or getStoredRarity(player, storageName))
	local rawLevel = tonumber(instanceData.Level) or 1
	local rawCurrentXP = tonumber(instanceData.CurrentXP) or 0
	local level = rawLevel
	local currentXP = rawCurrentXP

	level, currentXP = normalizeProgress(rarity, level, currentXP)

	if rawLevel ~= level or rawCurrentXP ~= currentXP or tostring(instanceData.Rarity or "") ~= rarity then
		local updated = CrewInstanceService.UpdateProgress(player, instanceId, level, currentXP)
		if updated then
			instanceData = updated
			syncAssignedStandLevel(player, instanceData, level)
			Module.RefreshProgressionShadow(player, "data_repair_progression")
		end
	end

	return {
		InstanceId = tostring(instanceId),
		StorageName = storageName,
		Rarity = rarity,
		Level = level,
		CurrentXP = currentXP,
		NextLevelXP = getXPRequiredForLevel(rarity, level),
		MaxLevel = getMaxLevel(),
	}
end

function Module.GetNextAutoFeedStep(player, brainrotName)
	local progress = Module.GetProgress(player, brainrotName)
	if not progress then
		return false, {
			Error = "missing_brainrot",
		}
	end

	if progress.Level >= progress.MaxLevel then
		return false, {
			Error = "brainrot_max_level",
			Progress = progress,
		}
	end

	local foodInventory = Module.GetFoodInventory(player)
	local plan = Module.BuildAutoFeedPlan(foodInventory, progress.Rarity, progress.Level, progress.CurrentXP)
	local stepPreview = buildPreviewStep(plan)
	if not stepPreview then
		return false, {
			Error = "not_enough_food",
			Progress = progress,
			Plan = plan,
		}
	end

	return true, {
		Progress = progress,
		Plan = plan,
		Step = stepPreview,
	}
end

function Module.GetFoodInventory(player)
	local inventory = DataManager:GetValue(player, "FoodInventory")
	if typeof(inventory) ~= "table" then
		inventory = {}
	end
	return inventory
end

function Module.GetTotalFoodCount(player)
	local total = 0
	local inventory = Module.GetFoodInventory(player)
	for foodKey in pairs(Economy.Food) do
		total += math.max(0, math.floor(tonumber(inventory[foodKey]) or 0))
	end
	return total
end

function Module.BuildAutoFeedPlan(foodInventory, rarity, level, currentXP)
	local maxLevel = getMaxLevel()
	local result = {
		FoodUsed = {},
		ConsumptionSteps = {},
		FoodsConsumed = 0,
		TotalXPConsumed = 0,
		LevelBefore = level,
		CurrentXPBefore = currentXP,
		LevelAfter = level,
		CurrentXPAfter = currentXP,
		LevelUps = 0,
		XPNeededBefore = math.max(0, getXPRequiredForLevel(rarity, level) - currentXP),
		ReachedMax = level >= maxLevel,
		StoppedForLackOfFood = false,
	}

	if result.ReachedMax then
		result.NextLevelXPAfter = 0
		return result
	end

	local remainingThreshold = result.XPNeededBefore
	for _, foodKey in ipairs(getFoodPriority()) do
		local available = math.max(0, math.floor(tonumber(foodInventory[foodKey]) or 0))
		local foodXP = getFoodXP(foodKey)
		local usedThisFood = 0
		while available > 0 and result.LevelAfter < maxLevel and remainingThreshold > 0 do
			available -= 1
			usedThisFood += 1
			result.FoodUsed[foodKey] = (result.FoodUsed[foodKey] or 0) + 1
			result.FoodsConsumed += 1
			result.TotalXPConsumed += foodXP
			remainingThreshold -= foodXP

			local pendingXP = foodXP
			while pendingXP > 0 and result.LevelAfter < maxLevel do
				local needed = getXPRequiredForLevel(rarity, result.LevelAfter)
				local remaining = math.max(0, needed - result.CurrentXPAfter)
				local applied = math.min(pendingXP, remaining)
				result.CurrentXPAfter += applied
				pendingXP -= applied

				if result.CurrentXPAfter >= needed then
					result.LevelAfter += 1
					result.LevelUps += 1
					result.CurrentXPAfter = 0
				end
			end

			if result.LevelAfter >= maxLevel then
				result.LevelAfter = maxLevel
				result.CurrentXPAfter = 0
				remainingThreshold = 0
				break
			end
		end

		if usedThisFood > 0 then
			table.insert(result.ConsumptionSteps, {
				FoodKey = foodKey,
				AmountUsed = usedThisFood,
				XPGained = usedThisFood * foodXP,
				RemainingAfter = available,
			})
		end
	end

	result.StoppedForLackOfFood = result.FoodsConsumed == 0 or remainingThreshold > 0
	result.ReachedMax = result.LevelAfter >= maxLevel
	result.NextLevelXPAfter = getXPRequiredForLevel(rarity, result.LevelAfter)
	return result
end

function Module.ApplyAutoFeed(player, brainrotName, options)
	options = typeof(options) == "table" and options or {}
	local progressionAuthorityEnabled = isProgressionWriteAuthorityEnabled()

	local progress = Module.GetProgress(player, brainrotName)
	if not progress then
		return false, {
			Error = "missing_brainrot",
		}
	end

	if progress.Level >= progress.MaxLevel then
		return false, {
			Error = "brainrot_max_level",
			Progress = progress,
		}
	end

	local foodInventory = Module.GetFoodInventory(player)
	local plan = Module.BuildAutoFeedPlan(foodInventory, progress.Rarity, progress.Level, progress.CurrentXP)
	if plan.FoodsConsumed <= 0 then
		return false, {
			Error = "not_enough_food",
			Progress = progress,
			Plan = plan,
		}
	end

	local snapshot = if progressionAuthorityEnabled then buildProgressionMutationSnapshot(player, "apply_auto_feed") else nil
	if progressionAuthorityEnabled then
		updateProgressionAuthorityAudit(player, {
			LastRollbackSnapshot = snapshot,
			LastMutation = {
				SourcePath = "apply_auto_feed",
				InstanceId = tostring(progress.InstanceId),
				FoodsConsumed = plan.FoodsConsumed,
				TotalXPConsumed = plan.TotalXPConsumed,
				StartedAt = os.time(),
			},
			LastFailClosedReason = nil,
		})
	end

	for stepIndex, stepData in ipairs(plan.ConsumptionSteps) do
		local foodKey = stepData.FoodKey
		local amountUsed = tonumber(stepData.AmountUsed) or 0
		if amountUsed > 0 then
			DataManager:AddValue(player, "FoodInventory." .. foodKey, -amountUsed)
			foodInventory[foodKey] = math.max(0, math.floor(tonumber(foodInventory[foodKey]) or 0) - amountUsed)
			if typeof(options.OnConsumptionStep) == "function" then
				options.OnConsumptionStep({
					FoodKey = foodKey,
					AmountUsed = amountUsed,
					XPGained = tonumber(stepData.XPGained) or 0,
					RemainingAfter = math.max(0, math.floor(tonumber(foodInventory[foodKey]) or 0)),
				}, stepIndex, plan)
			end
		end
	end

	local updated = CrewInstanceService.UpdateProgress(player, progress.InstanceId, plan.LevelAfter, plan.CurrentXPAfter)
	if not updated then
		if progressionAuthorityEnabled then
			local restoreOk, restoreReason = restoreProgressionMutationSnapshot(player, snapshot, "apply_auto_feed_progression_write_failed")
			updateProgressionAuthorityAudit(player, {
				LastFailClosedReason = "progression_write_failed",
				LastRollbackRestoreOk = restoreOk,
				LastRollbackRestoreReason = restoreReason,
			})
		end
		return false, {
			Error = "progression_write_failed",
			Progress = progress,
			Plan = plan,
		}
	end
	if updated then
		syncAssignedStandLevel(player, updated, plan.LevelAfter)
		if options.DeferShadowRefresh ~= true then
			refreshCrewMemberShadow(player, "food_progression")
		end
	end
	if progressionAuthorityEnabled then
		updateProgressionAuthorityAudit(player, {
			LastMutation = {
				SourcePath = "apply_auto_feed",
				InstanceId = tostring(progress.InstanceId),
				FoodsConsumed = plan.FoodsConsumed,
				TotalXPConsumed = plan.TotalXPConsumed,
				LevelAfter = plan.LevelAfter,
				CurrentXPAfter = plan.CurrentXPAfter,
				CompletedAt = os.time(),
			},
			ClearKeys = {
				"LastFailClosedReason",
				"LastFailClosedIssues",
				"LastRollbackRestoreOk",
				"LastRollbackRestoreReason",
			},
		})
	end

	plan.Progress = {
		InstanceId = tostring(progress.InstanceId),
		StorageName = progress.StorageName,
		Rarity = progress.Rarity,
		Level = plan.LevelAfter,
		CurrentXP = plan.CurrentXPAfter,
		NextLevelXP = plan.NextLevelXPAfter,
		MaxLevel = progress.MaxLevel,
	}

	return true, plan
end

function Module.ApplyAutoFeedStep(player, brainrotName, expectedFoodKey, options)
	options = typeof(options) == "table" and options or {}
	local progressionAuthorityEnabled = isProgressionWriteAuthorityEnabled()
	local progress = Module.GetProgress(player, brainrotName)
	if not progress then
		return false, {
			Error = "missing_brainrot",
		}
	end

	if progress.Level >= progress.MaxLevel then
		return false, {
			Error = "brainrot_max_level",
			Progress = progress,
		}
	end

	local foodInventory = Module.GetFoodInventory(player)
	local plan = Module.BuildAutoFeedPlan(foodInventory, progress.Rarity, progress.Level, progress.CurrentXP)
	local stepPreview = buildPreviewStep(plan)
	if not stepPreview then
		return false, {
			Error = "not_enough_food",
			Progress = progress,
			Plan = plan,
		}
	end

	if expectedFoodKey and tostring(stepPreview.FoodKey) ~= tostring(expectedFoodKey) then
		return false, {
			Error = "step_changed",
			Progress = progress,
			Plan = plan,
			Step = stepPreview,
		}
	end

	local snapshot = if progressionAuthorityEnabled then buildProgressionMutationSnapshot(player, "apply_auto_feed_step") else nil
	if progressionAuthorityEnabled then
		updateProgressionAuthorityAudit(player, {
			LastRollbackSnapshot = snapshot,
			LastMutation = {
				SourcePath = "apply_auto_feed_step",
				InstanceId = tostring(progress.InstanceId),
				FoodKey = tostring(stepPreview.FoodKey),
				AmountUsed = tonumber(stepPreview.AmountUsed) or 0,
				XPGained = tonumber(stepPreview.XPGained) or 0,
				StartedAt = os.time(),
			},
			LastFailClosedReason = nil,
		})
	end

	DataManager:AddValue(player, "FoodInventory." .. stepPreview.FoodKey, -stepPreview.AmountUsed)
	foodInventory[stepPreview.FoodKey] = math.max(0, math.floor(tonumber(foodInventory[stepPreview.FoodKey]) or 0) - stepPreview.AmountUsed)

	local levelAfter, currentXPAfter = normalizeProgress(
		progress.Rarity,
		progress.Level,
		math.max(0, progress.CurrentXP) + stepPreview.XPGained
	)

	local updated = CrewInstanceService.UpdateProgress(player, progress.InstanceId, levelAfter, currentXPAfter)
	if not updated then
		if progressionAuthorityEnabled then
			local restoreOk, restoreReason = restoreProgressionMutationSnapshot(player, snapshot, "apply_auto_feed_step_progression_write_failed")
			updateProgressionAuthorityAudit(player, {
				LastFailClosedReason = "progression_write_failed",
				LastRollbackRestoreOk = restoreOk,
				LastRollbackRestoreReason = restoreReason,
			})
		end
		return false, {
			Error = "progression_write_failed",
			Progress = progress,
			Step = stepPreview,
		}
	end
	if updated then
		syncAssignedStandLevel(player, updated, levelAfter)
		if options.DeferShadowRefresh ~= true then
			refreshCrewMemberShadow(player, "food_progression")
		end
	end
	if progressionAuthorityEnabled then
		updateProgressionAuthorityAudit(player, {
			LastMutation = {
				SourcePath = "apply_auto_feed_step",
				InstanceId = tostring(progress.InstanceId),
				FoodKey = tostring(stepPreview.FoodKey),
				AmountUsed = tonumber(stepPreview.AmountUsed) or 0,
				XPGained = tonumber(stepPreview.XPGained) or 0,
				LevelAfter = levelAfter,
				CurrentXPAfter = currentXPAfter,
				CompletedAt = os.time(),
			},
			ClearKeys = {
				"LastFailClosedReason",
				"LastFailClosedIssues",
				"LastRollbackRestoreOk",
				"LastRollbackRestoreReason",
			},
		})
	end

	return true, {
		AppliedStep = stepPreview,
		LevelUps = math.max(0, levelAfter - progress.Level),
		Progress = {
			InstanceId = tostring(progress.InstanceId),
			StorageName = progress.StorageName,
			Rarity = progress.Rarity,
			Level = levelAfter,
			CurrentXP = currentXPAfter,
			NextLevelXP = getXPRequiredForLevel(progress.Rarity, levelAfter),
			MaxLevel = progress.MaxLevel,
		},
	}
end

return Module
