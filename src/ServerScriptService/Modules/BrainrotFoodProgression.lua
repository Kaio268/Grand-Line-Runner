local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local DataManager = require(ServerScriptService:WaitForChild("Data"):WaitForChild("DataManager"))
local BrainrotInstanceService = require(ServerScriptService:WaitForChild("Modules"):WaitForChild("BrainrotInstanceService"))
local Economy = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("GrandLineRushEconomy"))
local BrainrotsCfg = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("Brainrots"))
local VariantCfg = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("BrainrotVariants"))

local Module = {}

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

local function getVariantPrefix(variantKey)
	local variant = (VariantCfg.Versions or {})[variantKey]
	return tostring(variant and variant.Prefix or (variantKey and variantKey ~= "Normal" and (variantKey .. " ") or ""))
end

local function resolveInventoryStorageName(player, savedName)
	if typeof(savedName) ~= "string" or savedName == "" then
		return nil
	end

	if DataManager:GetValue(player, "Inventory." .. savedName .. ".Level") ~= nil
		or DataManager:GetValue(player, "Inventory." .. savedName .. ".Quantity") ~= nil then
		return savedName
	end

	local inventory = player:FindFirstChild("Inventory")
	if not inventory then
		return savedName
	end

	for _, child in ipairs(inventory:GetChildren()) do
		if child:IsA("Folder") then
			local baseValue = child:FindFirstChild("BaseName")
			local variantValue = child:FindFirstChild("Variant")
			local baseName = baseValue and baseValue:IsA("StringValue") and baseValue.Value or nil
			local variantKey = variantValue and variantValue:IsA("StringValue") and variantValue.Value or "Normal"
			if typeof(baseName) == "string" and baseName ~= "" then
				if getVariantPrefix(variantKey) .. baseName == savedName then
					return child.Name
				end
			end
		end
	end

	return savedName
end

local function ensureInventoryFolder(player, storageName)
	local inventory = player:FindFirstChild("Inventory")
	if not inventory then
		inventory = Instance.new("Folder")
		inventory.Name = "Inventory"
		inventory.Parent = player
	end

	local entry = inventory:FindFirstChild(storageName)
	if not entry then
		entry = Instance.new("Folder")
		entry.Name = storageName
		entry.Parent = inventory
	end

	return entry
end

local function ensureNumberValue(parent, name, value)
	local numberValue = parent:FindFirstChild(name)
	if not numberValue or not numberValue:IsA("NumberValue") then
		if numberValue then
			numberValue:Destroy()
		end
		numberValue = Instance.new("NumberValue")
		numberValue.Name = name
		numberValue.Parent = parent
	end
	numberValue.Value = tonumber(value) or 0
	return numberValue
end

local function ensureInventoryProgressValues(player, storageName, level, currentXP)
	local entry = ensureInventoryFolder(player, storageName)
	ensureNumberValue(entry, "Level", math.max(1, tonumber(level) or 1))
	ensureNumberValue(entry, "CurrentXP", math.max(0, tonumber(currentXP) or 0))
end

local function getStoredRarity(player, storageName)
	local stored = DataManager:GetValue(player, "Inventory." .. storageName .. ".Rarity")
	if typeof(stored) == "string" and stored ~= "" then
		return normalizeRarity(stored)
	end

	local info = BrainrotsCfg[storageName]
	if type(info) == "table" then
		return normalizeRarity(info.Rarity)
	end

	local inventory = player:FindFirstChild("Inventory")
	local entry = inventory and inventory:FindFirstChild(storageName)
	local baseValue = entry and entry:FindFirstChild("BaseName")
	local baseName = baseValue and baseValue:IsA("StringValue") and baseValue.Value or nil
	local baseInfo = baseName and BrainrotsCfg[baseName] or nil
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
	local instanceId, instanceData = BrainrotInstanceService.ResolveProgressTarget(player, brainrotName)
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
		local updated = BrainrotInstanceService.UpdateProgress(player, instanceId, level, currentXP)
		if updated then
			instanceData = updated
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

	BrainrotInstanceService.UpdateProgress(player, progress.InstanceId, plan.LevelAfter, plan.CurrentXPAfter)

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

function Module.ApplyAutoFeedStep(player, brainrotName, expectedFoodKey)
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

	DataManager:AddValue(player, "FoodInventory." .. stepPreview.FoodKey, -stepPreview.AmountUsed)
	foodInventory[stepPreview.FoodKey] = math.max(0, math.floor(tonumber(foodInventory[stepPreview.FoodKey]) or 0) - stepPreview.AmountUsed)

	local levelAfter, currentXPAfter = normalizeProgress(
		progress.Rarity,
		progress.Level,
		math.max(0, progress.CurrentXP) + stepPreview.XPGained
	)

	BrainrotInstanceService.UpdateProgress(player, progress.InstanceId, levelAfter, currentXPAfter)

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
