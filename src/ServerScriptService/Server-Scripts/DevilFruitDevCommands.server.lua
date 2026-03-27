local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local TextChatService = game:GetService("TextChatService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DevilFruitService = require(ServerScriptService.Modules:WaitForChild("DevilFruitService"))
local DevilFruitInventoryService = require(ServerScriptService.Modules:WaitForChild("DevilFruitInventoryService"))
local BrainrotInstanceService = require(ServerScriptService.Modules:WaitForChild("BrainrotInstanceService"))
local BountyService = require(ServerScriptService.Modules:WaitForChild("GrandLineRushBountyService"))
local GrandLineRushChestToolService = require(ServerScriptService.Modules:WaitForChild("GrandLineRushChestToolService"))
local GrandLineRushVerticalSliceService = require(ServerScriptService.Modules:WaitForChild("GrandLineRushVerticalSliceService"))
local GrandLineRushCorridorRunController = require(ServerScriptService.Modules:WaitForChild("GrandLineRushCorridorRunController"))
local ShipResetService = require(ServerScriptService.Modules:WaitForChild("ShipResetService"))
local ShipRuntimeSignals = require(ServerScriptService.Modules:WaitForChild("ShipRuntimeSignals"))
local DataManager = require(ServerScriptService:WaitForChild("Data"):WaitForChild("DataManager"))
local ProfileTemplate = require(ServerScriptService:WaitForChild("Data"):WaitForChild("DataManager"):WaitForChild("ProfileTemplate"))
local DevilFruitConfig = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("DevilFruits"))
local GrandLineRushEconomy = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("GrandLineRushEconomy"))
local PlotUpgradeConfig = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("PlotUpgrade"))
local CurrencyUtil = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("CurrencyUtil"))

local ADMIN_USER_IDS = {
	1103783585,
	2442286217,
	780333260,
}

local RECENT_COMMAND_WINDOW = 0.4

local adminSet = {}
local recentCommands = {}
local fruitAliases = {}
local chestTierAliases = {}
local resourceAliases = {}

for _, userId in ipairs(ADMIN_USER_IDS) do
	adminSet[userId] = true
end

local function normalizeText(text)
	return tostring(text or ""):lower():match("^%s*(.-)%s*$") or ""
end

local function cloneValue(value)
	if typeof(value) ~= "table" then
		return value
	end

	local cloned = {}
	for key, nestedValue in pairs(value) do
		cloned[key] = cloneValue(nestedValue)
	end

	return cloned
end

local function normalizeResourceAlias(text)
	local normalized = normalizeText(text)
	normalized = normalized:gsub("[_%-%s]+", " ")
	return normalized
end

local function registerFruitAlias(alias, displayName)
	local normalizedAlias = normalizeText(alias)
	if normalizedAlias == "" then
		return
	end

	fruitAliases[normalizedAlias] = displayName
end

local function registerChestAlias(alias, tierName)
	local normalizedAlias = normalizeText(alias)
	if normalizedAlias == "" then
		return
	end

	chestTierAliases[normalizedAlias] = tierName
end

local function registerResourceAlias(alias, resourceData)
	local normalizedAlias = normalizeResourceAlias(alias)
	if normalizedAlias == "" or typeof(resourceData) ~= "table" then
		return
	end

	resourceAliases[normalizedAlias] = resourceData
	resourceAliases[normalizedAlias:gsub("%s+", "")] = resourceData
end

for _, fruit in ipairs(DevilFruitConfig.GetAllFruits()) do
	registerFruitAlias(fruit.FruitKey, fruit.DisplayName)
	registerFruitAlias(fruit.DisplayName, fruit.DisplayName)
	registerFruitAlias(fruit.Id, fruit.DisplayName)

	for _, alias in ipairs(fruit.Aliases or {}) do
		registerFruitAlias(alias, fruit.DisplayName)
	end
end

local function isAuthorized(player)
	if not player then
		return false
	end

	return RunService:IsStudio() or adminSet[player.UserId] == true
end

local function markRecentCommand(player, commandText)
	local now = os.clock()
	local key = string.format("%d:%s", player.UserId, commandText)
	local lastTime = recentCommands[key]

	recentCommands[key] = now

	if lastTime and (now - lastTime) < RECENT_COMMAND_WINDOW then
		return false
	end

	return true
end

local function invokeRuntimeCommand(bindable, action, player)
	local ok, result, extra = pcall(function()
		return bindable:Invoke(action, player)
	end)

	if not ok then
		return false, result
	end

	if result == false then
		return false, extra or "runtime_command_failed"
	end

	return true, extra
end

local function grantAllFruits(player)
	local grantedCount = 0
	local alreadyOwnedCount = 0
	local failedFruitNames = {}

	for _, fruit in ipairs(DevilFruitConfig.GetAllFruits()) do
		local quantity, quantityReason = DevilFruitInventoryService.GetFruitQuantity(player, fruit.FruitKey)
		if quantity == nil then
			table.insert(failedFruitNames, string.format("%s (%s)", fruit.DisplayName, tostring(quantityReason)))
			continue
		end

		if quantity >= 1 then
			alreadyOwnedCount += 1
			continue
		end

		local granted, reason = DevilFruitInventoryService.GrantFruit(player, fruit.FruitKey, 1)
		if granted then
			grantedCount += 1
		else
			table.insert(failedFruitNames, string.format("%s (%s)", fruit.DisplayName, tostring(reason)))
		end
	end

	if #failedFruitNames > 0 then
		warn(string.format(
			"[DevFruitDevCommands] %s used /fruit all (granted=%d, already_owned=%d, failed=%s)",
			player.Name,
			grantedCount,
			alreadyOwnedCount,
			table.concat(failedFruitNames, ", ")
		))
		return
	end

	print(string.format(
		"[DevFruitDevCommands] %s used /fruit all (granted=%d, already_owned=%d)",
		player.Name,
		grantedCount,
		alreadyOwnedCount
	))
end

local function processFruitCommand(player, argumentText)
	if not isAuthorized(player) then
		return
	end

	local normalizedArgument = normalizeText(argumentText)
	if normalizedArgument == "" then
		warn(string.format("[DevFruitDevCommands] %s used /fruit without an argument", player.Name))
		return
	end

	if normalizedArgument == "all" then
		grantAllFruits(player)
		return
	end

	local cooldownArgument = normalizedArgument:match("^nocd%s*(.*)$")
	if cooldownArgument ~= nil then
		local normalizedCooldownArgument = normalizeText(cooldownArgument)
		local nextState

		if normalizedCooldownArgument == "on" then
			nextState = true
		elseif normalizedCooldownArgument == "off" then
			nextState = false
		else
			warn(string.format("[DevFruitDevCommands] Invalid /fruit nocd argument '%s' from %s (expected 'on' or 'off')", normalizedCooldownArgument, player.Name))
			return
		end

		if DevilFruitService.SetCooldownBypass(player, nextState) then
			print(string.format("[DevFruitDevCommands] %s set Devil Fruit cooldown bypass to %s", player.Name, tostring(nextState)))
		end
		return
	end

	local directEquipArgument = normalizedArgument:match("^equip%s+(.+)$")
	if directEquipArgument then
		local directFruit = fruitAliases[normalizeText(directEquipArgument)]
		if directFruit == nil then
			warn(string.format("[DevFruitDevCommands] Unknown fruit alias '%s' from %s", directEquipArgument, player.Name))
			return
		end

		local ok, persisted = DevilFruitService.SetEquippedFruit(player, directFruit)
		if ok then
			print(string.format("[DevFruitDevCommands] %s directly equipped Devil Fruit %s (persisted=%s)", player.Name, directFruit, tostring(persisted)))
		end
		return
	end

	local targetFruit = fruitAliases[normalizedArgument]
	if normalizedArgument == "clear" or normalizedArgument == "none" or normalizedArgument == "remove" then
		local ok, persisted = DevilFruitService.SetEquippedFruit(player, "")
		if ok then
			print(string.format("[DevFruitDevCommands] %s cleared Devil Fruit (persisted=%s)", player.Name, tostring(persisted)))
		end
		return
	end

	if targetFruit == nil then
		warn(string.format("[DevFruitDevCommands] Unknown fruit alias '%s' from %s", normalizedArgument, player.Name))
		return
	end

	local granted, reason = DevilFruitInventoryService.GrantFruit(player, targetFruit, 1)
	if granted then
		print(string.format("[DevFruitDevCommands] %s granted Devil Fruit item %s", player.Name, targetFruit))
	else
		warn(string.format("[DevFruitDevCommands] Failed to grant %s to %s (%s)", targetFruit, player.Name, tostring(reason)))
	end
end

local function parseSignedAmount(text)
	local normalized = tostring(text or ""):match("^%s*(.-)%s*$") or ""
	if normalized == "" then
		return nil
	end

	normalized = normalized:gsub(",", "")
	return tonumber(normalized)
end

local function parseWholeAmount(text)
	local amount = parseSignedAmount(text)
	if typeof(amount) ~= "number" or amount ~= amount then
		return nil
	end

	if amount < 0 then
		return math.ceil(amount)
	end

	return math.floor(amount)
end

local function getDisplayedMoney(player)
	local moneyValue = CurrencyUtil.findPrimaryValueObject(player)
	if moneyValue then
		return moneyValue.Value
	end

	local storedMoney = DataManager:GetValue(player, CurrencyUtil.getPrimaryPath())
	return (typeof(storedMoney) == "number") and storedMoney or 0
end

local function getDisplayedRebirths(player)
	local leaderstats = player:FindFirstChild("leaderstats")
	if leaderstats then
		local rebirthsValue = leaderstats:FindFirstChild("Rebirths")
		if rebirthsValue and rebirthsValue:IsA("NumberValue") then
			return math.max(0, math.floor(tonumber(rebirthsValue.Value) or 0))
		end
	end

	local storedRebirths = DataManager:GetValue(player, "leaderstats.Rebirths")
	if typeof(storedRebirths) == "number" then
		return math.max(0, math.floor(storedRebirths))
	end

	return 0
end

local function getDisplayedBountyBreakdown(player)
	local breakdown = BountyService.GetBreakdown(player)
	return {
		Crew = math.max(0, math.floor(tonumber(breakdown.Crew) or 0)),
		LifetimeExtraction = math.max(0, math.floor(tonumber(breakdown.LifetimeExtraction) or 0)),
		Total = math.max(0, math.floor(tonumber(breakdown.Total) or 0)),
	}
end

local function processMoneyCommand(player, argumentText)
	if not isAuthorized(player) then
		return
	end

	local normalizedArgument = normalizeText(argumentText)
	if normalizedArgument == "" then
		warn(string.format("[DevFruitDevCommands] Invalid /money usage from %s. Use /money <delta>, /money set <amount>, or /money clear", player.Name))
		return
	end

	if normalizedArgument == "clear" or normalizedArgument == "reset" or normalizedArgument == "zero" then
		local previousMoney = getDisplayedMoney(player)
		local success = DataManager:SetValue(player, CurrencyUtil.getPrimaryPath(), 0)
		if success == false then
			warn(string.format("[DevFruitDevCommands] Failed to clear Doubloons for %s", player.Name))
			return
		end

		local newMoney = getDisplayedMoney(player)
		print(string.format(
			"[DevFruitDevCommands] %s cleared Doubloons (old balance=%d, new balance=%d)",
			player.Name,
			math.floor(previousMoney),
			math.floor(newMoney)
		))
		return
	end

	local setArgument = normalizedArgument:match("^set%s+(.+)$")
	if setArgument ~= nil then
		local targetAmount = parseWholeAmount(setArgument)
		if typeof(targetAmount) ~= "number" then
			warn(string.format("[DevFruitDevCommands] Invalid /money set amount '%s' from %s", tostring(setArgument), player.Name))
			return
		end

		local previousMoney = getDisplayedMoney(player)
		local success = DataManager:SetValue(player, CurrencyUtil.getPrimaryPath(), targetAmount)
		if success == false then
			warn(string.format("[DevFruitDevCommands] Failed to set Doubloons for %s", player.Name))
			return
		end

		local newMoney = getDisplayedMoney(player)
		print(string.format(
			"[DevFruitDevCommands] %s set Doubloons to %d (old balance=%d, new balance=%d)",
			player.Name,
			math.floor(targetAmount),
			math.floor(previousMoney),
			math.floor(newMoney)
		))
		return
	end

	local amount = parseWholeAmount(argumentText)
	if typeof(amount) ~= "number" or amount == 0 then
		warn(string.format("[DevFruitDevCommands] Invalid /money amount '%s' from %s", tostring(argumentText), player.Name))
		return
	end

	local previousMoney = getDisplayedMoney(player)
	local newMoney = DataManager:AdjustValue(player, CurrencyUtil.getPrimaryPath(), amount)
	if typeof(newMoney) ~= "number" then
		newMoney = getDisplayedMoney(player)
	end

	local appliedDelta = math.floor(newMoney - previousMoney)
	print(string.format(
		"[DevFruitDevCommands] %s adjusted Doubloons by %d (applied=%d, new balance=%d)",
		player.Name,
		math.floor(amount),
		appliedDelta,
		math.floor(newMoney)
	))
end

local function processRebirthCommand(player, argumentText)
	if not isAuthorized(player) then
		return
	end

	local normalizedArgument = normalizeText(argumentText)
	if normalizedArgument == "" then
		warn(string.format(
			"[DevFruitDevCommands] Invalid /rebirth usage from %s. Use /rebirth set <amount>, /rebirth add <amount>, or /rebirth reset",
			player.Name
		))
		return
	end

	if normalizedArgument == "clear" or normalizedArgument == "reset" or normalizedArgument == "zero" then
		local previousRebirths = getDisplayedRebirths(player)
		local success = DataManager:SetValue(player, "leaderstats.Rebirths", 0)
		if success == false then
			warn(string.format("[DevFruitDevCommands] Failed to reset Rebirths for %s", player.Name))
			return
		end

		local newRebirths = getDisplayedRebirths(player)
		print(string.format(
			"[DevFruitDevCommands] %s reset Rebirths (old=%d, new=%d)",
			player.Name,
			math.floor(previousRebirths),
			math.floor(newRebirths)
		))
		return
	end

	local setArgument = normalizedArgument:match("^set%s+(.+)$")
	if setArgument ~= nil then
		local targetAmount = parseWholeAmount(setArgument)
		if typeof(targetAmount) ~= "number" or targetAmount < 0 then
			warn(string.format("[DevFruitDevCommands] Invalid /rebirth set amount '%s' from %s", tostring(setArgument), player.Name))
			return
		end

		local previousRebirths = getDisplayedRebirths(player)
		local success = DataManager:SetValue(player, "leaderstats.Rebirths", targetAmount)
		if success == false then
			warn(string.format("[DevFruitDevCommands] Failed to set Rebirths for %s", player.Name))
			return
		end

		local newRebirths = getDisplayedRebirths(player)
		print(string.format(
			"[DevFruitDevCommands] %s set Rebirths to %d (old=%d, new=%d)",
			player.Name,
			math.floor(targetAmount),
			math.floor(previousRebirths),
			math.floor(newRebirths)
		))
		return
	end

	local addArgument = normalizedArgument:match("^add%s+(.+)$")
	if addArgument ~= nil then
		local amount = parseWholeAmount(addArgument)
		if typeof(amount) ~= "number" or amount < 0 then
			warn(string.format("[DevFruitDevCommands] Invalid /rebirth add amount '%s' from %s", tostring(addArgument), player.Name))
			return
		end

		local previousRebirths = getDisplayedRebirths(player)
		local newRebirths = DataManager:AdjustValue(player, "leaderstats.Rebirths", amount)
		if typeof(newRebirths) ~= "number" then
			newRebirths = getDisplayedRebirths(player)
		end

		print(string.format(
			"[DevFruitDevCommands] %s added %d Rebirths (old=%d, new=%d)",
			player.Name,
			math.floor(amount),
			math.floor(previousRebirths),
			math.floor(newRebirths)
		))
		return
	end

	warn(string.format(
		"[DevFruitDevCommands] Invalid /rebirth usage from %s. Use /rebirth set <amount>, /rebirth add <amount>, or /rebirth reset",
		player.Name
	))
end

local function processBountyCommand(player, argumentText)
	if not isAuthorized(player) then
		return
	end

	local normalizedArgument = normalizeText(argumentText)
	if normalizedArgument == "" then
		warn(string.format(
			"[DevFruitDevCommands] Invalid /bounty usage from %s. Use /bounty set <amount>, /bounty add <amount>, /bounty reset, or /bounty debug",
			player.Name
		))
		return
	end

	if normalizedArgument == "debug" or normalizedArgument == "info" or normalizedArgument == "status" then
		local breakdown = BountyService.RefreshPlayerBounty(player) or getDisplayedBountyBreakdown(player)
		GrandLineRushVerticalSliceService.Start()
		GrandLineRushVerticalSliceService.PushState(player)
		print(string.format(
			"[DevFruitDevCommands] %s bounty debug crew=%d extraction=%d total=%d",
			player.Name,
			math.floor(tonumber(breakdown.Crew) or 0),
			math.floor(tonumber(breakdown.LifetimeExtraction) or 0),
			math.floor(tonumber(breakdown.Total) or 0)
		))
		return
	end

	if normalizedArgument == "clear" or normalizedArgument == "reset" or normalizedArgument == "zero" then
		local previous = getDisplayedBountyBreakdown(player)
		local breakdown = BountyService.SetLifetimeExtractionBounty(player, 0)
		if breakdown == nil then
			warn(string.format("[DevFruitDevCommands] Failed to reset lifetime bounty for %s", player.Name))
			return
		end

		GrandLineRushVerticalSliceService.Start()
		GrandLineRushVerticalSliceService.PushState(player)
		print(string.format(
			"[DevFruitDevCommands] %s reset lifetime extraction bounty (old=%d, crew=%d, total=%d)",
			player.Name,
			math.floor(previous.LifetimeExtraction),
			math.floor(tonumber(breakdown.Crew) or 0),
			math.floor(tonumber(breakdown.Total) or 0)
		))
		return
	end

	local setArgument = normalizedArgument:match("^set%s+(.+)$")
	if setArgument ~= nil then
		local targetAmount = parseWholeAmount(setArgument)
		if typeof(targetAmount) ~= "number" or targetAmount < 0 then
			warn(string.format("[DevFruitDevCommands] Invalid /bounty set amount '%s' from %s", tostring(setArgument), player.Name))
			return
		end

		local previous = getDisplayedBountyBreakdown(player)
		local breakdown = BountyService.SetLifetimeExtractionBounty(player, targetAmount)
		if breakdown == nil then
			warn(string.format("[DevFruitDevCommands] Failed to set lifetime bounty for %s", player.Name))
			return
		end

		GrandLineRushVerticalSliceService.Start()
		GrandLineRushVerticalSliceService.PushState(player)
		print(string.format(
			"[DevFruitDevCommands] %s set lifetime extraction bounty to %d (old=%d, total=%d)",
			player.Name,
			math.floor(targetAmount),
			math.floor(previous.LifetimeExtraction),
			math.floor(tonumber(breakdown.Total) or 0)
		))
		return
	end

	local addArgument = normalizedArgument:match("^add%s+(.+)$")
	if addArgument ~= nil then
		local amount = parseWholeAmount(addArgument)
		if typeof(amount) ~= "number" or amount < 0 then
			warn(string.format("[DevFruitDevCommands] Invalid /bounty add amount '%s' from %s", tostring(addArgument), player.Name))
			return
		end

		local previous = getDisplayedBountyBreakdown(player)
		local breakdown, grantedAmount = BountyService.AddLifetimeExtractionBounty(player, amount)
		if breakdown == nil then
			warn(string.format("[DevFruitDevCommands] Failed to add lifetime bounty for %s", player.Name))
			return
		end

		GrandLineRushVerticalSliceService.Start()
		GrandLineRushVerticalSliceService.PushState(player)
		print(string.format(
			"[DevFruitDevCommands] %s added %d lifetime extraction bounty (old=%d, new=%d, total=%d)",
			player.Name,
			math.floor(grantedAmount or 0),
			math.floor(previous.LifetimeExtraction),
			math.floor(tonumber(breakdown.LifetimeExtraction) or 0),
			math.floor(tonumber(breakdown.Total) or 0)
		))
		return
	end

	warn(string.format(
		"[DevFruitDevCommands] Invalid /bounty usage from %s. Use /bounty set <amount>, /bounty add <amount>, /bounty reset, or /bounty debug",
		player.Name
	))
end

local function getTrackedResourceValue(player, resourceData)
	if typeof(resourceData) ~= "table" then
		return nil
	end

	if resourceData.Kind == "currency" then
		return getDisplayedMoney(player)
	end

	local value = DataManager:GetValue(player, tostring(resourceData.Path or ""))
	if typeof(value) == "number" then
		return value
	end

	return nil
end

local function processGiveCommand(player, argumentText)
	if not isAuthorized(player) then
		return
	end

	local trimmedArguments = tostring(argumentText or ""):match("^%s*(.-)%s*$") or ""
	if trimmedArguments == "" then
		warn(string.format("[DevFruitDevCommands] Invalid /give usage from %s. Use /give <resource> <amount>", player.Name))
		return
	end

	local resourceArgument, amountArgument = trimmedArguments:match("^(.-)%s+([^%s]+)$")
	if resourceArgument == nil or amountArgument == nil then
		warn(string.format("[DevFruitDevCommands] Invalid /give usage from %s. Use /give <resource> <amount>", player.Name))
		return
	end

	local resourceKey = normalizeResourceAlias(resourceArgument)
	local resourceData = resourceAliases[resourceKey] or resourceAliases[resourceKey:gsub("%s+", "")]
	if typeof(resourceData) ~= "table" then
		warn(string.format("[DevFruitDevCommands] Unknown /give resource '%s' from %s", tostring(resourceArgument), player.Name))
		return
	end

	local amount = parseWholeAmount(amountArgument)
	if typeof(amount) ~= "number" or amount <= 0 then
		warn(string.format("[DevFruitDevCommands] Invalid /give amount '%s' from %s", tostring(amountArgument), player.Name))
		return
	end

	local newValue
	if resourceData.Kind == "currency" then
		newValue = DataManager:AdjustValue(player, tostring(resourceData.Path), amount)
	else
		newValue = DataManager:AdjustValue(player, tostring(resourceData.Path), amount)
		if typeof(newValue) == "number" and typeof(resourceData.MirrorPath) == "string" and resourceData.MirrorPath ~= "" then
			DataManager:SetValue(player, resourceData.MirrorPath, newValue)
		end
	end

	if typeof(newValue) ~= "number" then
		newValue = getTrackedResourceValue(player, resourceData)
	end

	if typeof(newValue) ~= "number" then
		warn(string.format(
			"[DevFruitDevCommands] Failed /give %s %d for %s",
			tostring(resourceData.DisplayName or resourceArgument),
			amount,
			player.Name
		))
		return
	end

	GrandLineRushVerticalSliceService.Start()
	GrandLineRushVerticalSliceService.PushState(player)

	print(string.format(
		"[DevFruitDevCommands] %s granted %d %s via /give (new total=%d)",
		player.Name,
		math.floor(amount),
		tostring(resourceData.DisplayName or resourceArgument),
		math.floor(newValue)
	))
end

local function processShipResetCommand(player, argumentText)
	if not isAuthorized(player) then
		return
	end

	local normalizedArgument = normalizeText(argumentText)
	if normalizedArgument ~= "" and normalizedArgument ~= "me" and normalizedArgument ~= "self" then
		warn(string.format("[DevFruitDevCommands] Invalid /shipreset usage from %s. Use /shipreset", player.Name))
		return
	end

	local success, result = ShipResetService.ResetPlayerShip(player)
	if not success then
		warn(string.format("[DevFruitDevCommands] Failed /shipreset for %s (%s)", player.Name, tostring(result)))
		return
	end

	local starterSlots = typeof(result) == "table" and tonumber(result.StarterSlots) or 0
	local shipLevel = typeof(result) == "table" and tonumber(result.ShipLevel) or 0
	BountyService.RefreshPlayerBounty(player)
	print(string.format(
		"[DevFruitDevCommands] %s reset ship progression (ship level=%d, starter slots=%d)",
		player.Name,
		math.floor(shipLevel),
		math.floor(starterSlots)
	))
end

local function processClearCommand(player, argumentText)
	if not isAuthorized(player) then
		return
	end

	local normalizedArgument = normalizeText(argumentText)
	if normalizedArgument ~= "inv" and normalizedArgument ~= "inventory" then
		warn(string.format("[DevFruitDevCommands] Invalid /clear usage from %s. Use /clear inv", player.Name))
		return
	end

	local failures = {}
	local standCommand = ShipRuntimeSignals.GetStandCommandFunction()
	DevilFruitInventoryService.Start()
	local ok, reason = invokeRuntimeCommand(standCommand, "clear", player)
	if not ok then
		table.insert(failures, "runtime_clear:" .. tostring(reason))
	end

	local function setTemplatePath(path, templateValue)
		if DataManager:SetValue(player, path, cloneValue(templateValue)) == false then
			table.insert(failures, "set_" .. tostring(path))
		end
	end

	setTemplatePath("Inventory", ProfileTemplate.Inventory)
	setTemplatePath("UnopenedChests", ProfileTemplate.UnopenedChests)
	setTemplatePath("FoodInventory", ProfileTemplate.FoodInventory)
	setTemplatePath("CrewInventory", ProfileTemplate.CrewInventory)
	setTemplatePath("BrainrotInventory", ProfileTemplate.BrainrotInventory)
	setTemplatePath("Materials", ProfileTemplate.Materials)
	setTemplatePath("Chef", ProfileTemplate.Chef)
	setTemplatePath("Ship", ProfileTemplate.Ship)
	setTemplatePath("IncomeBrainrots", ProfileTemplate.IncomeBrainrots)
	setTemplatePath("StandsLevels", ProfileTemplate.StandsLevels)

		DevilFruitService.SetEquippedFruit(player, "")
		if DataManager:SetValue(player, "DevilFruit", cloneValue(ProfileTemplate.DevilFruit)) == false then
			table.insert(failures, "set_DevilFruit")
		end

	BrainrotInstanceService.SyncAvailableCounts(player)
	BountyService.RefreshPlayerBounty(player)

	ok, reason = invokeRuntimeCommand(standCommand, "refresh", player)
	if not ok then
		table.insert(failures, "runtime_refresh:" .. tostring(reason))
	end

	GrandLineRushChestToolService.Start()
	GrandLineRushChestToolService.SyncPlayer(player)
	GrandLineRushVerticalSliceService.Start()
	GrandLineRushVerticalSliceService.PushState(player)

	if #failures > 0 then
		warn(string.format(
			"[DevFruitDevCommands] Failed /clear inv for %s (%s)",
			player.Name,
			table.concat(failures, ", ")
		))
		return
	end

	print(string.format("[DevFruitDevCommands] %s cleared inventory via /clear inv", player.Name))
end

local function processSpawnCommand(player, argumentText)
	if not isAuthorized(player) then
		return
	end

	local targetName = normalizeText(argumentText)
	if targetName == "" then
		warn(string.format("[DevFruitDevCommands] %s used /spawn without an argument", player.Name))
		return
	end

	if targetName ~= "chest" and targetName ~= "crew" then
		warn(string.format("[DevFruitDevCommands] Invalid /spawn target '%s' from %s", tostring(argumentText), player.Name))
		return
	end

	if targetName == "chest" then
		GrandLineRushCorridorRunController.Start()
		local ok, result = GrandLineRushCorridorRunController.SpawnSharedChestInFrontOfPlayer(player)
		if ok then
			print(string.format("[DevFruitDevCommands] %s spawned shared chest reward via /spawn", player.Name))
		else
			warn(string.format(
				"[DevFruitDevCommands] Failed /spawn chest for %s (%s)",
				player.Name,
				tostring(result or "unknown")
			))
		end
		return
	end

	GrandLineRushVerticalSliceService.Start()

	local rewardType = "Crew"
	local depthBand = GrandLineRushEconomy.VerticalSlice.WorldRun.StartDepthBand or GrandLineRushEconomy.VerticalSlice.DefaultDepthBand
	local response = GrandLineRushVerticalSliceService.StartRun(player, rewardType, depthBand)
	if response and response.ok then
		print(string.format("[DevFruitDevCommands] %s spawned live %s reward via /spawn", player.Name, targetName))
	else
		warn(string.format(
			"[DevFruitDevCommands] Failed /spawn %s for %s (%s)",
			targetName,
			player.Name,
			tostring((response and response.error) or "unknown")
		))
	end
end

local primaryCurrencyConfig = CurrencyUtil.getConfig()
local doubloonResource = {
	Kind = "currency",
	Path = CurrencyUtil.getPrimaryPath(),
	DisplayName = tostring(primaryCurrencyConfig.DisplayName or primaryCurrencyConfig.Key or "Doubloons"),
}

registerResourceAlias("doubloons", doubloonResource)
registerResourceAlias("doubloon", doubloonResource)
registerResourceAlias("money", doubloonResource)
registerResourceAlias(primaryCurrencyConfig.Key, doubloonResource)
registerResourceAlias(primaryCurrencyConfig.DisplayName, doubloonResource)

for _, materialKey in ipairs(PlotUpgradeConfig.MaterialOrder or {}) do
	local displayName = tostring(PlotUpgradeConfig.MaterialDisplayNames[materialKey] or materialKey)
	local resourceData = {
		Kind = "material",
		Key = materialKey,
		Path = "Materials." .. tostring(materialKey),
		DisplayName = displayName,
		MirrorPath = if materialKey == "Timber"
			then "Materials.CommonShipMaterial"
			elseif materialKey == "Iron"
			then "Materials.RareShipMaterial"
			else nil,
	}

	registerResourceAlias(materialKey, resourceData)
	registerResourceAlias(displayName, resourceData)
end

registerResourceAlias("common ship material", resourceAliases["timber"])
registerResourceAlias("commonshipmaterial", resourceAliases["timber"])
registerResourceAlias("rare ship material", resourceAliases["iron"])
registerResourceAlias("rareshipmaterial", resourceAliases["iron"])

for foodKey, foodData in pairs(GrandLineRushEconomy.Food or {}) do
	local displayName = tostring((typeof(foodData) == "table" and foodData.DisplayName) or foodKey)
	local resourceData = {
		Kind = "food",
		Key = foodKey,
		Path = "FoodInventory." .. tostring(foodKey),
		DisplayName = displayName,
	}

	registerResourceAlias(foodKey, resourceData)
	registerResourceAlias(displayName, resourceData)
end

for tierName in pairs(GrandLineRushEconomy.Chests.Tiers or {}) do
	registerChestAlias(tierName, tierName)
end

registerChestAlias("wood", "Wooden")
registerChestAlias("wooden", "Wooden")
registerChestAlias("iron", "Iron")
registerChestAlias("gold", "Gold")
registerChestAlias("legend", "Legendary")
registerChestAlias("legendary", "Legendary")

local function processChestCommand(player, argumentText)
	if not isAuthorized(player) then
		return
	end

	local trimmedArguments = tostring(argumentText or ""):match("^%s*(.-)%s*$") or ""
	if trimmedArguments == "" then
		warn(string.format("[DevFruitDevCommands] %s used /chest without arguments", player.Name))
		return
	end

	local rarityArgument, amountArgument = trimmedArguments:match("^(%S+)%s*(.*)$")
	local chestTier = chestTierAliases[normalizeText(rarityArgument)]
	if chestTier == nil then
		warn(string.format("[DevFruitDevCommands] Invalid /chest rarity '%s' from %s", tostring(rarityArgument), player.Name))
		return
	end

	local amount = 1
	local normalizedAmount = tostring(amountArgument or ""):match("^%s*(.-)%s*$") or ""
	if normalizedAmount ~= "" then
		amount = tonumber(normalizedAmount)
	end

	if typeof(amount) ~= "number" or amount ~= amount or amount < 1 then
		warn(string.format("[DevFruitDevCommands] Invalid /chest amount '%s' from %s", tostring(amountArgument), player.Name))
		return
	end

	amount = math.floor(amount)
	GrandLineRushChestToolService.Start()
	GrandLineRushVerticalSliceService.Start()

	local response = GrandLineRushVerticalSliceService.GrantChest(
		player,
		chestTier,
		amount,
		GrandLineRushEconomy.VerticalSlice.DefaultDepthBand
	)

	if response and response.ok then
		print(string.format(
			"[DevFruitDevCommands] %s granted %d %s chest(s) via /chest",
			player.Name,
			amount,
			chestTier
		))
	else
		warn(string.format(
			"[DevFruitDevCommands] Failed /chest %s %s for %s (%s)",
			tostring(chestTier),
			tostring(amount),
			player.Name,
			tostring((response and response.error) or "unknown")
		))
	end
end

local function getCommandNameAndArguments(rawText)
	local normalizedText = normalizeText(rawText)
	local commandName, argumentText = normalizedText:match("^/%s*(%S+)%s*(.*)$")
	if not commandName then
		return nil, nil, normalizedText
	end

	return commandName, argumentText or "", normalizedText
end

local function handleChatCommand(player, rawText)
	if not player then
		return
	end

	local commandName, argumentText, normalizedText = getCommandNameAndArguments(rawText)
	if not commandName then
		return
	end

	if commandName ~= "fruit" and commandName ~= "money" and commandName ~= "rebirth" and commandName ~= "bounty" and commandName ~= "give" and commandName ~= "spawn" and commandName ~= "chest" and commandName ~= "shipreset" and commandName ~= "clear" then
		return
	end

	if not markRecentCommand(player, normalizedText) then
		return
	end

	if commandName == "fruit" then
		processFruitCommand(player, argumentText)
		return
	end

	if commandName == "rebirth" then
		processRebirthCommand(player, argumentText)
		return
	end

	if commandName == "bounty" then
		processBountyCommand(player, argumentText)
		return
	end

	if commandName == "spawn" then
		processSpawnCommand(player, argumentText)
		return
	end

	if commandName == "give" then
		processGiveCommand(player, argumentText)
		return
	end

	if commandName == "chest" then
		processChestCommand(player, argumentText)
		return
	end

	if commandName == "shipreset" then
		processShipResetCommand(player, argumentText)
		return
	end

	if commandName == "clear" then
		processClearCommand(player, argumentText)
		return
	end

	processMoneyCommand(player, argumentText)
end

local function hookPlayer(player)
	player.Chatted:Connect(function(message)
		handleChatCommand(player, message)
	end)
end

local function setupTextChatCommand()
	local commandsFolder = TextChatService:FindFirstChild("TextChatCommands") or TextChatService:WaitForChild("TextChatCommands", 10)
	if not commandsFolder then
		return
	end

	local command = commandsFolder:FindFirstChild("DevilFruitDevCommand")
	if command and not command:IsA("TextChatCommand") then
		command:Destroy()
		command = nil
	end

	if not command then
		command = Instance.new("TextChatCommand")
		command.Name = "DevilFruitDevCommand"
		command.PrimaryAlias = "/fruit"
		command.SecondaryAlias = "/fruit"
		command.AutocompleteVisible = false
		command.Parent = commandsFolder
	end

	command.Triggered:Connect(function(textSource, unfilteredText)
		local player = textSource and Players:GetPlayerByUserId(textSource.UserId)
		if not player then
			return
		end

		local normalizedText = normalizeText(unfilteredText)
		if normalizedText:sub(1, 6) == "/fruit" then
			handleChatCommand(player, normalizedText)
			return
		end

		local syntheticCommand = normalizedText ~= "" and ("/fruit " .. normalizedText) or "/fruit"
		handleChatCommand(player, syntheticCommand)
	end)

	local moneyCommand = commandsFolder:FindFirstChild("MoneyDevCommand")
	if moneyCommand and not moneyCommand:IsA("TextChatCommand") then
		moneyCommand:Destroy()
		moneyCommand = nil
	end

	if not moneyCommand then
		moneyCommand = Instance.new("TextChatCommand")
		moneyCommand.Name = "MoneyDevCommand"
		moneyCommand.PrimaryAlias = "/money"
		moneyCommand.SecondaryAlias = "/money"
		moneyCommand.AutocompleteVisible = false
		moneyCommand.Parent = commandsFolder
	end

	moneyCommand.Triggered:Connect(function(textSource, unfilteredText)
		local player = textSource and Players:GetPlayerByUserId(textSource.UserId)
		if not player then
			return
		end

		local normalizedText = normalizeText(unfilteredText)
		if normalizedText:sub(1, 6) == "/money" or normalizedText:sub(1, 7) == "/ money" then
			handleChatCommand(player, normalizedText)
			return
		end

		local syntheticCommand = normalizedText ~= "" and ("/money " .. normalizedText) or "/money"
		handleChatCommand(player, syntheticCommand)
	end)

	local rebirthCommand = commandsFolder:FindFirstChild("RebirthDevCommand")
	if rebirthCommand and not rebirthCommand:IsA("TextChatCommand") then
		rebirthCommand:Destroy()
		rebirthCommand = nil
	end

	if not rebirthCommand then
		rebirthCommand = Instance.new("TextChatCommand")
		rebirthCommand.Name = "RebirthDevCommand"
		rebirthCommand.PrimaryAlias = "/rebirth"
		rebirthCommand.SecondaryAlias = "/rebirth"
		rebirthCommand.AutocompleteVisible = false
		rebirthCommand.Parent = commandsFolder
	end

	rebirthCommand.Triggered:Connect(function(textSource, unfilteredText)
		local player = textSource and Players:GetPlayerByUserId(textSource.UserId)
		if not player then
			return
		end

		local normalizedText = normalizeText(unfilteredText)
		if normalizedText:sub(1, 8) == "/rebirth" or normalizedText:sub(1, 9) == "/ rebirth" then
			handleChatCommand(player, normalizedText)
			return
		end

		local syntheticCommand = normalizedText ~= "" and ("/rebirth " .. normalizedText) or "/rebirth"
		handleChatCommand(player, syntheticCommand)
	end)

	local bountyCommand = commandsFolder:FindFirstChild("BountyDevCommand")
	if bountyCommand and not bountyCommand:IsA("TextChatCommand") then
		bountyCommand:Destroy()
		bountyCommand = nil
	end

	if not bountyCommand then
		bountyCommand = Instance.new("TextChatCommand")
		bountyCommand.Name = "BountyDevCommand"
		bountyCommand.PrimaryAlias = "/bounty"
		bountyCommand.SecondaryAlias = "/bounty"
		bountyCommand.AutocompleteVisible = false
		bountyCommand.Parent = commandsFolder
	end

	bountyCommand.Triggered:Connect(function(textSource, unfilteredText)
		local player = textSource and Players:GetPlayerByUserId(textSource.UserId)
		if not player then
			return
		end

		local normalizedText = normalizeText(unfilteredText)
		if normalizedText:sub(1, 7) == "/bounty" or normalizedText:sub(1, 8) == "/ bounty" then
			handleChatCommand(player, normalizedText)
			return
		end

		local syntheticCommand = normalizedText ~= "" and ("/bounty " .. normalizedText) or "/bounty"
		handleChatCommand(player, syntheticCommand)
	end)

	local giveCommand = commandsFolder:FindFirstChild("GiveDevCommand")
	if giveCommand and not giveCommand:IsA("TextChatCommand") then
		giveCommand:Destroy()
		giveCommand = nil
	end

	if not giveCommand then
		giveCommand = Instance.new("TextChatCommand")
		giveCommand.Name = "GiveDevCommand"
		giveCommand.PrimaryAlias = "/give"
		giveCommand.SecondaryAlias = "/give"
		giveCommand.AutocompleteVisible = false
		giveCommand.Parent = commandsFolder
	end

	giveCommand.Triggered:Connect(function(textSource, unfilteredText)
		local player = textSource and Players:GetPlayerByUserId(textSource.UserId)
		if not player then
			return
		end

		local normalizedText = normalizeText(unfilteredText)
		if normalizedText:sub(1, 5) == "/give" or normalizedText:sub(1, 6) == "/ give" then
			handleChatCommand(player, normalizedText)
			return
		end

		local syntheticCommand = normalizedText ~= "" and ("/give " .. normalizedText) or "/give"
		handleChatCommand(player, syntheticCommand)
	end)

	local spawnCommand = commandsFolder:FindFirstChild("SpawnDevCommand")
	if spawnCommand and not spawnCommand:IsA("TextChatCommand") then
		spawnCommand:Destroy()
		spawnCommand = nil
	end

	if not spawnCommand then
		spawnCommand = Instance.new("TextChatCommand")
		spawnCommand.Name = "SpawnDevCommand"
		spawnCommand.PrimaryAlias = "/spawn"
		spawnCommand.SecondaryAlias = "/spawn"
		spawnCommand.AutocompleteVisible = false
		spawnCommand.Parent = commandsFolder
	end

	spawnCommand.Triggered:Connect(function(textSource, unfilteredText)
		local player = textSource and Players:GetPlayerByUserId(textSource.UserId)
		if not player then
			return
		end

		local normalizedText = normalizeText(unfilteredText)
		if normalizedText:sub(1, 6) == "/spawn" or normalizedText:sub(1, 7) == "/ spawn" then
			handleChatCommand(player, normalizedText)
			return
		end

		local syntheticCommand = normalizedText ~= "" and ("/spawn " .. normalizedText) or "/spawn"
		handleChatCommand(player, syntheticCommand)
	end)

	local chestCommand = commandsFolder:FindFirstChild("ChestDevCommand")
	if chestCommand and not chestCommand:IsA("TextChatCommand") then
		chestCommand:Destroy()
		chestCommand = nil
	end

	if not chestCommand then
		chestCommand = Instance.new("TextChatCommand")
		chestCommand.Name = "ChestDevCommand"
		chestCommand.PrimaryAlias = "/chest"
		chestCommand.SecondaryAlias = "/chest"
		chestCommand.AutocompleteVisible = false
		chestCommand.Parent = commandsFolder
	end

	chestCommand.Triggered:Connect(function(textSource, unfilteredText)
		local player = textSource and Players:GetPlayerByUserId(textSource.UserId)
		if not player then
			return
		end

		local normalizedText = normalizeText(unfilteredText)
		if normalizedText:sub(1, 6) == "/chest" or normalizedText:sub(1, 7) == "/ chest" then
			handleChatCommand(player, normalizedText)
			return
		end

		local syntheticCommand = normalizedText ~= "" and ("/chest " .. normalizedText) or "/chest"
		handleChatCommand(player, syntheticCommand)
	end)

	local shipResetCommand = commandsFolder:FindFirstChild("ShipResetDevCommand")
	if shipResetCommand and not shipResetCommand:IsA("TextChatCommand") then
		shipResetCommand:Destroy()
		shipResetCommand = nil
	end

	if not shipResetCommand then
		shipResetCommand = Instance.new("TextChatCommand")
		shipResetCommand.Name = "ShipResetDevCommand"
		shipResetCommand.PrimaryAlias = "/shipreset"
		shipResetCommand.SecondaryAlias = "/shipreset"
		shipResetCommand.AutocompleteVisible = false
		shipResetCommand.Parent = commandsFolder
	end

	shipResetCommand.Triggered:Connect(function(textSource, unfilteredText)
		local player = textSource and Players:GetPlayerByUserId(textSource.UserId)
		if not player then
			return
		end

		local normalizedText = normalizeText(unfilteredText)
		if normalizedText:sub(1, 10) == "/shipreset" or normalizedText:sub(1, 11) == "/ shipreset" then
			handleChatCommand(player, normalizedText)
			return
		end

		local syntheticCommand = normalizedText ~= "" and ("/shipreset " .. normalizedText) or "/shipreset"
		handleChatCommand(player, syntheticCommand)
	end)

	local clearCommand = commandsFolder:FindFirstChild("ClearDevCommand")
	if clearCommand and not clearCommand:IsA("TextChatCommand") then
		clearCommand:Destroy()
		clearCommand = nil
	end

	if not clearCommand then
		clearCommand = Instance.new("TextChatCommand")
		clearCommand.Name = "ClearDevCommand"
		clearCommand.PrimaryAlias = "/clear"
		clearCommand.SecondaryAlias = "/clear"
		clearCommand.AutocompleteVisible = false
		clearCommand.Parent = commandsFolder
	end

	clearCommand.Triggered:Connect(function(textSource, unfilteredText)
		local player = textSource and Players:GetPlayerByUserId(textSource.UserId)
		if not player then
			return
		end

		local normalizedText = normalizeText(unfilteredText)
		if normalizedText:sub(1, 6) == "/clear" or normalizedText:sub(1, 7) == "/ clear" then
			handleChatCommand(player, normalizedText)
			return
		end

		local syntheticCommand = normalizedText ~= "" and ("/clear " .. normalizedText) or "/clear"
		handleChatCommand(player, syntheticCommand)
	end)
end

for _, player in ipairs(Players:GetPlayers()) do
	hookPlayer(player)
end

Players.PlayerAdded:Connect(hookPlayer)
setupTextChatCommand()
