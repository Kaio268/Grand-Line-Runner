local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")
local TextChatService = game:GetService("TextChatService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local engineWarn = warn
local activeCommandWarnings = nil

local function warn(...)
	engineWarn(...)

	if activeCommandWarnings == nil then
		return
	end

	local parts = {}
	for index = 1, select("#", ...) do
		parts[index] = tostring(select(index, ...))
	end
	activeCommandWarnings[#activeCommandWarnings + 1] = table.concat(parts, " ")
end

local function adminCommandFlowLog(message, ...)
	print("[AdminCommandFlow] " .. string.format(message, ...))
end

local function adminCommandFlowWarn(message, ...)
	warn("[AdminCommandFlow] " .. string.format(message, ...))
end

adminCommandFlowLog("DevilFruitDevCommands server script started")

local AdminPermissions = require(ServerScriptService.Modules:WaitForChild("AdminPermissions"))
local DevilFruitService = require(ServerScriptService.Modules:WaitForChild("DevilFruitService"))
local DevilFruitInventoryService = require(ServerScriptService.Modules:WaitForChild("DevilFruitInventoryService"))
local CrewInstanceService = require(ServerScriptService.Modules:WaitForChild("CrewInstanceService"))
local BountyService = require(ServerScriptService.Modules:WaitForChild("GrandLineRushBountyService"))
local GrandLineRushChestToolService = require(ServerScriptService.Modules:WaitForChild("GrandLineRushChestToolService"))
local GrandLineRushVerticalSliceService = require(ServerScriptService.Modules:WaitForChild("GrandLineRushVerticalSliceService"))
local GrandLineRushCorridorRunController = require(ServerScriptService.Modules:WaitForChild("GrandLineRushCorridorRunController"))
local ShipResetService = require(ServerScriptService.Modules:WaitForChild("ShipResetService"))
local ShipRuntimeSignals = require(ServerScriptService.Modules:WaitForChild("ShipRuntimeSignals"))
local TimeRewardsService = require(ServerScriptService.Modules:WaitForChild("Time_Rewards_Server"))
local FirstTimeTutorialService = require(ServerScriptService.Modules:WaitForChild("FirstTimeTutorialService"))
local CrewMemberCanonicalReadGate = require(ServerScriptService.Modules:WaitForChild("CrewMemberCanonicalReadGate"))
local CrewMigrationPlanner = require(ServerScriptService.Modules:WaitForChild("CrewMigrationPlanner"))
local CrewQuickSlotService = require(ServerScriptService.Modules:WaitForChild("CrewQuickSlotService"))
local AddCrewMember = require(ServerScriptService.Modules:WaitForChild("AddCrewMember"))
local DataManager = require(ServerScriptService:WaitForChild("Data"):WaitForChild("DataManager"))
local ProfileTemplate = require(ServerScriptService:WaitForChild("Data"):WaitForChild("DataManager"):WaitForChild("ProfileTemplate"))
local SpeedUpgradeLimits = require(ServerScriptService.Modules:WaitForChild("SpeedUpgradeLimits"))
local HazardRuntime = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("DevilFruits"):WaitForChild("HazardRuntime"))
local DevilFruitConfig = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("DevilFruits"))
local GrandLineRushEconomy = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("GrandLineRushEconomy"))
local PlotUpgradeConfig = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("PlotUpgrade"))
local CurrencyUtil = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("CurrencyUtil"))
local PopUpModule = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("PopUpModule"))

adminCommandFlowLog("DevilFruitDevCommands dependencies loaded")

local function getOrCreateRemoteEvent(name)
	local remote = ReplicatedStorage:FindFirstChild(name)
	if remote and not remote:IsA("RemoteEvent") then
		remote:Destroy()
		remote = nil
	end
	if not remote then
		remote = Instance.new("RemoteEvent")
		remote.Name = name
		remote.Parent = ReplicatedStorage
	end
	return remote
end

local adminCommandRequestEvent = getOrCreateRemoteEvent("AdminCommandRequest")

local RECENT_COMMAND_WINDOW = 0.4
local WIPE_CONFIRM_WINDOW = 20
local SPEED_STAT_PATH = "HiddenLeaderstats.Speed"
local DEFAULT_SPEED_STAT = tonumber(ProfileTemplate.HiddenLeaderstats.Speed) or 1
local HITBOX_VISUAL_ATTRIBUTE = "ShowAbilityHitboxes"
local HITBOX_POPUP_ON_COLOR = Color3.fromRGB(105, 225, 255)
local HITBOX_POPUP_OFF_COLOR = Color3.fromRGB(220, 220, 220)
local HITBOX_POPUP_ERROR_COLOR = Color3.fromRGB(255, 85, 85)
local HITBOX_POPUP_STROKE_COLOR = Color3.fromRGB(0, 0, 0)
local HAZARDS_DISABLED_TIMER_SECONDS = 10 * 365 * 24 * 60 * 60

local recentCommands = {}
local pendingWipeConfirmations = {}
local fruitAliases = {}
local chestTierAliases = {}
local resourceAliases = {}
local BOOST_COMMAND_DEFAULT_MINUTES = 5
local boostAliases = {
	["x2money"] = {
		BoostName = "x2Money",
		DisplayName = "x2 Money",
	},
	["money"] = {
		BoostName = "x2Money",
		DisplayName = "x2 Money",
	},
	["x2doubloons"] = {
		BoostName = "x2Money",
		DisplayName = "x2 Money",
	},
	["doubloons"] = {
		BoostName = "x2Money",
		DisplayName = "x2 Money",
	},
	["2xmoney"] = {
		BoostName = "x2Money",
		DisplayName = "x2 Money",
	},
	["x15walkspeed"] = {
		BoostName = "x15WalkSpeed",
		DisplayName = "x1.5 Walkspeed",
	},
	["speed"] = {
		BoostName = "x15WalkSpeed",
		DisplayName = "x1.5 Walkspeed",
	},
	["walkspeed"] = {
		BoostName = "x15WalkSpeed",
		DisplayName = "x1.5 Walkspeed",
	},
}

local ADMIN_COMMAND_NAMES = {
	fruit = true,
	money = true,
	hazard = true,
	hazards = true,
	hitbox = true,
	speed = true,
	setspeed = true,
	boost = true,
	rebirth = true,
	bounty = true,
	give = true,
	spawn = true,
	chest = true,
	shipreset = true,
	clear = true,
	tutorial = true,
	wipeplayer = true,
	resetprogress = true,
	gifts = true,
	giftreset = true,
	crewcanary = true,
	crewread = true,
}

local function normalizeText(text)
	return tostring(text or ""):lower():match("^%s*(.-)%s*$") or ""
end

local function trimText(text)
	return tostring(text or ""):match("^%s*(.-)%s*$") or ""
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

local function splitWipeArguments(argumentText)
	local trimmed = trimText(argumentText)
	if trimmed == "" then
		return "", false
	end

	local targetSpec, trailingToken = trimmed:match("^(.-)%s+(%S+)$")
	if targetSpec and normalizeText(trailingToken) == "confirm" then
		return trimText(targetSpec), true
	end

	return trimmed, false
end

local function resolveResetTarget(requestingPlayer, targetSpec)
	local normalizedTarget = normalizeText(targetSpec)
	if normalizedTarget == "" then
		return nil, nil, nil, "missing_target"
	end

	if normalizedTarget == "me" or normalizedTarget == "self" then
		return requestingPlayer.UserId, requestingPlayer.Name, requestingPlayer, nil
	end

	local numericUserId = tonumber(normalizedTarget)
	if typeof(numericUserId) == "number" and numericUserId > 0 and numericUserId % 1 == 0 then
		local onlinePlayer = Players:GetPlayerByUserId(numericUserId)
		local resolvedLabel = onlinePlayer and onlinePlayer.Name or tostring(math.floor(numericUserId))
		return math.floor(numericUserId), resolvedLabel, onlinePlayer, nil
	end

	local exactMatch = nil
	local prefixMatch = nil
	local ambiguousPrefix = false

	for _, candidate in ipairs(Players:GetPlayers()) do
		local candidateName = normalizeText(candidate.Name)
		local candidateDisplayName = normalizeText(candidate.DisplayName)
		if normalizedTarget == candidateName or normalizedTarget == candidateDisplayName then
			exactMatch = candidate
			break
		end

		local matchesPrefix = candidateName:sub(1, #normalizedTarget) == normalizedTarget
			or candidateDisplayName:sub(1, #normalizedTarget) == normalizedTarget
		if matchesPrefix then
			if prefixMatch and prefixMatch ~= candidate then
				ambiguousPrefix = true
			else
				prefixMatch = candidate
			end
		end
	end

	if exactMatch then
		return exactMatch.UserId, exactMatch.Name, exactMatch, nil
	end

	if prefixMatch and ambiguousPrefix ~= true then
		return prefixMatch.UserId, prefixMatch.Name, prefixMatch, nil
	end

	if ambiguousPrefix then
		return nil, nil, nil, "ambiguous_target"
	end

	local ok, resolvedUserId = pcall(function()
		return Players:GetUserIdFromNameAsync(targetSpec)
	end)
	if ok and typeof(resolvedUserId) == "number" and resolvedUserId > 0 then
		local onlinePlayer = Players:GetPlayerByUserId(resolvedUserId)
		local resolvedLabel = onlinePlayer and onlinePlayer.Name or trimText(targetSpec)
		return resolvedUserId, resolvedLabel, onlinePlayer, nil
	end

	return nil, nil, nil, "target_not_found"
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
	return AdminPermissions.IsAdmin(player)
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

	local response = GrandLineRushVerticalSliceService.GrantSpecificFruitReward(player, targetFruit, {
		Kind = "AdminFruitGrant",
		InventoryName = "Admin Fruit Reward",
		DisplayName = "Admin Fruit Reward",
		Source = "AdminCommand",
		DepthBand = GrandLineRushEconomy.VerticalSlice.DefaultDepthBand,
	})
	if response and response.ok then
		if typeof(response.openResult) == "table" then
			PopUpModule:Server_ShowChestOpenResult(player, response.openResult)
		end

		if response.openResult and response.openResult.WasDuplicate == true then
			print(string.format(
				"[DevFruitDevCommands] %s duplicate Devil Fruit %s converted via chest reward flow (%s)",
				player.Name,
				targetFruit,
				tostring(
					response.openResult.ConversionRewardDisplayName
						or ((response.openResult.GrantedChest or {}).displayName)
						or response.openResult.Message
						or "duplicate reward"
				)
			))
		else
			print(string.format("[DevFruitDevCommands] %s granted Devil Fruit reward %s via chest reward flow", player.Name, targetFruit))
		end
	else
		warn(string.format(
			"[DevFruitDevCommands] Failed to resolve admin fruit reward %s for %s (%s)",
			targetFruit,
			player.Name,
			tostring(response and (response.error or response.message) or "unknown_error")
		))
	end
end

local function sendHitboxPopup(player, text, color, isError)
	if player and player.Parent == Players then
		PopUpModule:Server_SendPopUp(
			player,
			text,
			color or HITBOX_POPUP_OFF_COLOR,
			HITBOX_POPUP_STROKE_COLOR,
			3,
			isError == true
		)
	end
end

local function processHitboxCommand(player, argumentText)
	if not isAuthorized(player) then
		return
	end

	local normalizedArgument = normalizeText(argumentText)
	local nextState

	if normalizedArgument == "" or normalizedArgument == "toggle" then
		nextState = player:GetAttribute(HITBOX_VISUAL_ATTRIBUTE) ~= true
	elseif normalizedArgument == "on" or normalizedArgument == "true" or normalizedArgument == "1" then
		nextState = true
	elseif normalizedArgument == "off" or normalizedArgument == "false" or normalizedArgument == "0" then
		nextState = false
	else
		warn(string.format(
			"[DevFruitDevCommands] Invalid /hitbox argument '%s' from %s (expected 'on' or 'off')",
			normalizedArgument,
			player.Name
		))
		sendHitboxPopup(player, "Usage: /hitbox on or /hitbox off", HITBOX_POPUP_ERROR_COLOR, true)
		return
	end

	player:SetAttribute(HITBOX_VISUAL_ATTRIBUTE, nextState)
	sendHitboxPopup(
		player,
		nextState and "Ability hitboxes: ON" or "Ability hitboxes: OFF",
		nextState and HITBOX_POPUP_ON_COLOR or HITBOX_POPUP_OFF_COLOR,
		false
	)

	print(string.format(
		"[DevFruitDevCommands] %s set client ability hitbox visuals to %s",
		player.Name,
		nextState and "on" or "off"
	))
end

local function parseHazardsEnabledArgument(argumentText)
	local normalizedArgument = normalizeText(argumentText)
	if normalizedArgument == "on"
		or normalizedArgument == "true"
		or normalizedArgument == "1"
		or normalizedArgument == "enable"
		or normalizedArgument == "enabled"
	then
		return true
	elseif normalizedArgument == "off"
		or normalizedArgument == "false"
		or normalizedArgument == "0"
		or normalizedArgument == "disable"
		or normalizedArgument == "disabled"
	then
		return false
	end

	return nil
end

local function getNoDisastersTimer()
	local timer = Workspace:FindFirstChild("NoDisastersTimer")
	if not timer then
		return nil, "missing_no_disasters_timer"
	end

	local ok, value = pcall(function()
		return timer.Value
	end)
	if not ok or typeof(value) ~= "number" then
		return nil, "invalid_no_disasters_timer"
	end

	return timer, nil
end

local function clearActiveSharedHazards()
	local hazardsFolder = HazardRuntime.GetSharedHazardsFolder()
	if not hazardsFolder then
		return 0, 0, "missing_hazards_folder"
	end

	local clearedCount = 0
	local failedCount = 0
	for _, hazardRoot in ipairs(hazardsFolder:GetChildren()) do
		local runtimeOk, runtimeDestroyed = pcall(function()
			return HazardRuntime.Destroy(hazardRoot)
		end)

		if runtimeOk and runtimeDestroyed == true then
			clearedCount += 1
		else
			local destroyOk = pcall(function()
				hazardRoot:Destroy()
			end)
			if destroyOk then
				clearedCount += 1
			else
				failedCount += 1
			end
		end
	end

	return clearedCount, failedCount, nil
end

local function processHazardsCommand(player, argumentText)
	if not isAuthorized(player) then
		return
	end

	local nextEnabled = parseHazardsEnabledArgument(argumentText)
	if nextEnabled == nil then
		local normalizedArgument = normalizeText(argumentText)
		warn(string.format(
			"[DevFruitDevCommands] Invalid /hazards argument '%s' from %s. Use /hazards true or /hazards false",
			normalizedArgument,
			player.Name
		))
		return
	end

	local timer, timerReason = getNoDisastersTimer()
	if not timer then
		warn(string.format(
			"[DevFruitDevCommands] Failed /hazards %s for %s (%s)",
			tostring(nextEnabled),
			player.Name,
			tostring(timerReason)
		))
		return false, tostring(timerReason)
	end

	local previousTimerValue = timer.Value
	local nextTimerValue = if nextEnabled then 0 else math.max(previousTimerValue, HAZARDS_DISABLED_TIMER_SECONDS)
	timer.Value = nextTimerValue

	local clearedCount = 0
	local failedCount = 0
	local clearReason = nil
	if not nextEnabled then
		clearedCount, failedCount, clearReason = clearActiveSharedHazards()
	end

	local detail = string.format(
		"hazards=%s oldTimer=%d newTimer=%d cleared=%d",
		nextEnabled and "on" or "off",
		math.floor(previousTimerValue),
		math.floor(nextTimerValue),
		clearedCount
	)

	if clearReason then
		detail ..= " clearReason=" .. tostring(clearReason)
	end

	if failedCount > 0 then
		detail ..= " failed=" .. tostring(failedCount)
		warn(string.format(
			"[DevFruitDevCommands] Failed to clear %d active hazard(s) for %s via /hazards %s",
			failedCount,
			player.Name,
			nextEnabled and "true" or "false"
		))
		return false, detail
	end

	print(string.format(
		"[DevFruitDevCommands] %s set hazards to %s via /hazards (old timer=%d, new timer=%d, cleared=%d%s)",
		player.Name,
		nextEnabled and "on" or "off",
		math.floor(previousTimerValue),
		math.floor(nextTimerValue),
		clearedCount,
		clearReason and (", " .. tostring(clearReason)) or ""
	))
	return true, detail
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

local function getDisplayedSpeed(player)
	local hidden = player:FindFirstChild("HiddenLeaderstats")
	if hidden then
		local speedValue = hidden:FindFirstChild("Speed")
		if speedValue and speedValue:IsA("NumberValue") then
			return tonumber(speedValue.Value) or DEFAULT_SPEED_STAT
		end
	end

	local storedSpeed = DataManager:GetValue(player, SPEED_STAT_PATH)
	if typeof(storedSpeed) == "number" then
		return storedSpeed
	end

	return DEFAULT_SPEED_STAT
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

local function parseSpeedAmount(text)
	local amount = parseSignedAmount(text)
	if typeof(amount) ~= "number" or amount ~= amount or amount == math.huge or amount == -math.huge or amount < 0 then
		return nil
	end

	return amount
end

local function processSpeedCommand(player, argumentText)
	if not isAuthorized(player) then
		return
	end

	local normalizedArgument = normalizeText(argumentText)
	if normalizedArgument == "" then
		warn(string.format("[DevFruitDevCommands] Invalid /speed usage from %s. Use /speed <amount>, /speed set <amount>, or /speed reset", player.Name))
		return
	end

	local targetSpeed
	if normalizedArgument == "clear" or normalizedArgument == "reset" or normalizedArgument == "default" then
		targetSpeed = DEFAULT_SPEED_STAT
	else
		local setArgument = normalizedArgument:match("^set%s+(.+)$")
		targetSpeed = parseSpeedAmount(setArgument or normalizedArgument)
	end

	if typeof(targetSpeed) ~= "number" then
		warn(string.format("[DevFruitDevCommands] Invalid /speed amount '%s' from %s", tostring(argumentText), player.Name))
		return
	end

	targetSpeed = SpeedUpgradeLimits.SanitizeSpeedValue(targetSpeed)

	local previousSpeed = getDisplayedSpeed(player)
	local success = DataManager:SetValue(player, SPEED_STAT_PATH, targetSpeed)
	if success == false then
		warn(string.format("[DevFruitDevCommands] Failed to set Speed for %s", player.Name))
		return
	end

	local newSpeed = getDisplayedSpeed(player)
	print(string.format(
		"[DevFruitDevCommands] %s set Speed to %s (old=%s, new=%s)",
		player.Name,
		tostring(targetSpeed),
		tostring(previousSpeed),
		tostring(newSpeed)
	))
end

local function processBoostCommand(player, argumentText)
	if not isAuthorized(player) then
		return
	end

	local trimmedArgument = trimText(argumentText)
	if trimmedArgument == "" then
		warn(string.format(
			"[DevFruitDevCommands] Invalid /boost usage from %s. Use /boost x2money [minutes].",
			player.Name
		))
		return
	end

	local boostToken, durationText = trimmedArgument:match("^(%S+)%s*(.*)$")
	local boostData = boostAliases[normalizeText(boostToken)]
	if boostData == nil then
		warn(string.format(
			"[DevFruitDevCommands] Invalid /boost type '%s' from %s. Use /boost x2money [minutes].",
			tostring(boostToken),
			player.Name
		))
		return
	end

	local durationMinutes = BOOST_COMMAND_DEFAULT_MINUTES
	local normalizedDurationText = trimText(durationText)
	if normalizedDurationText ~= "" then
		durationMinutes = parseWholeAmount(normalizedDurationText)
	end

	if typeof(durationMinutes) ~= "number" or durationMinutes < 1 then
		warn(string.format(
			"[DevFruitDevCommands] Invalid /boost duration '%s' from %s. Duration must be a whole number of minutes.",
			tostring(durationText),
			player.Name
		))
		return
	end

	durationMinutes = math.floor(durationMinutes)

	local _, timePath = DataManager:_resolveBoostPaths(player, boostData.BoostName)
	if not timePath then
		warn(string.format(
			"[DevFruitDevCommands] Failed /boost %s for %s because the boost timer path is missing.",
			tostring(boostData.BoostName),
			player.Name
		))
		return
	end

	local durationSeconds = durationMinutes * 60
	DataManager:StartBoost(player, boostData.BoostName, durationSeconds)

	print(string.format(
		"[DevFruitDevCommands] %s granted %s for %d minute(s) via /boost",
		player.Name,
		tostring(boostData.DisplayName),
		durationMinutes
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
	setTemplatePath("CrewMemberInventory", ProfileTemplate.CrewMemberInventory)
	setTemplatePath("CrewMemberQuickSlots", ProfileTemplate.CrewMemberQuickSlots)
	setTemplatePath("CrewMemberIncome", ProfileTemplate.CrewMemberIncome)
	setTemplatePath("Materials", ProfileTemplate.Materials)
	setTemplatePath("Chef", ProfileTemplate.Chef)
	setTemplatePath("Ship", ProfileTemplate.Ship)

	DevilFruitService.SetEquippedFruit(player, "")
	if DataManager:SetValue(player, "DevilFruit", cloneValue(ProfileTemplate.DevilFruit)) == false then
		table.insert(failures, "set_DevilFruit")
	end

	CrewInstanceService.SyncCrewAvailableCounts(player)
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

	CrewInstanceService.RefreshCrewMemberShadowAfterDestructiveLegacyReset(player, "admin_clear_inventory")
	CrewInstanceService.SyncCrewAvailableCounts(player)
	print(string.format("[DevFruitDevCommands] %s cleared inventory via /clear inv", player.Name))
end

local function processTutorialCommand(player, argumentText)
	if not isAuthorized(player) then
		return
	end

	local normalizedArgument = normalizeText(argumentText)
	if normalizedArgument ~= "reset" then
		warn(string.format("[DevFruitDevCommands] Invalid /tutorial usage from %s. Use /tutorial reset", player.Name))
		return
	end

	local result = FirstTimeTutorialService.ResetForTesting(player)
	if typeof(result) ~= "table" or result.Success ~= true then
		local detail = if typeof(result) == "table" then tostring(result.Detail or result.detail or "unknown_error") else "unknown_error"
		warn(string.format("[DevFruitDevCommands] Failed /tutorial reset for %s (%s)", player.Name, detail))
		return false, detail
	end

	local detail = tostring(result.Detail or "tutorial reset")
	print(string.format("[DevFruitDevCommands] %s reset tutorial test data via /tutorial reset (%s)", player.Name, detail))
	return true, detail
end

local CREW_CANARY_HELPER_STATUS_ITEMS = {
	"Frigo Camelo",
	"Lirili Larila",
	"Gangster Footera",
}

local CREW_CANARY_MODEL_PREVIEW_STATUS_ITEMS = {
	"Frigo Camelo",
	"Lirili Larila",
	"Gangster Footera",
}

local CREW_CANARY_FOOD_READ_AUTHORITY_ITEMS = {
	"Frigo Camelo",
	"Lirili Larila",
	"Gangster Footera",
}

local function getCrewCanaryStandStatusItems(player)
	local items = {}
	local seen = {}

	local function append(value)
		local item = tostring(value or "")
		if item == "" or seen[item] then
			return
		end
		seen[item] = true
		items[#items + 1] = item
	end

	for _, item in ipairs(CREW_CANARY_HELPER_STATUS_ITEMS) do
		append(item)
	end

	local crewMemberIncome = DataManager:GetValue(player, "CrewMemberIncome")
	if typeof(crewMemberIncome) == "table" then
		local standNames = {}
		for standName in pairs(crewMemberIncome) do
			standNames[#standNames + 1] = tostring(standName)
		end
		table.sort(standNames)

		for _, standName in ipairs(standNames) do
			local standData = crewMemberIncome[standName]
			if typeof(standData) == "table" then
				append(standData.LegacyStorageName)
				append(standData.CrewMemberName)
				append(standData.StorageName)
			end
		end
	end

	local incomeFolder = player:FindFirstChild("CrewMemberIncome")
	if incomeFolder then
		local standFolders = incomeFolder:GetChildren()
		table.sort(standFolders, function(a, b)
			return a.Name < b.Name
		end)
		for _, standFolder in ipairs(standFolders) do
			for _, valueName in ipairs({ "LegacyStorageName", "CrewMemberName", "StorageName" }) do
				local value = standFolder:FindFirstChild(valueName)
				if value and value:IsA("StringValue") then
					append(value.Value)
				end
			end
		end
	end

	return items
end

local function getCrewCanaryStandReadAuthorityStandNames(player)
	local standNames = {}
	local seen = {}

	local function append(standName)
		local value = tostring(standName or "")
		if value == "" or seen[value] == true then
			return
		end
		seen[value] = true
		standNames[#standNames + 1] = value
	end

	local crewMemberIncome = DataManager:GetValue(player, "CrewMemberIncome")
	if typeof(crewMemberIncome) == "table" then
		local sortedStandNames = {}
		for standName in pairs(crewMemberIncome) do
			sortedStandNames[#sortedStandNames + 1] = tostring(standName)
		end
		table.sort(sortedStandNames)

		for _, standName in ipairs(sortedStandNames) do
			local standData = crewMemberIncome[standName]
			local storageName = if typeof(standData) == "table"
				then tostring(standData.LegacyStorageName or standData.CrewMemberName or standData.StorageName or "")
				else ""
			if storageName ~= "" then
				append(standName)
			end
		end
	end

	local incomeFolder = player:FindFirstChild("CrewMemberIncome")
	if incomeFolder then
		local standFolders = incomeFolder:GetChildren()
		table.sort(standFolders, function(a, b)
			return a.Name < b.Name
		end)
		for _, standFolder in ipairs(standFolders) do
			local value = standFolder:FindFirstChild("LegacyStorageName")
				or standFolder:FindFirstChild("CrewMemberName")
				or standFolder:FindFirstChild("StorageName")
			if value and value:IsA("StringValue") and tostring(value.Value or "") ~= "" then
				append(standFolder.Name)
			end
		end
	end

	return standNames
end

local function getCrewCanaryCanonicalInventoryInstance(player, instanceId)
	local resolvedId, instanceData = CrewInstanceService.GetInstance(player, tostring(instanceId or ""))
	if typeof(instanceData) == "table" then
		return instanceData, resolvedId
	end

	return nil, nil
end

local function buildCrewCanaryFoodReadAuthorityContext(player, standName, label)
	local standData = DataManager:GetValue(player, "CrewMemberIncome." .. tostring(standName))
	if typeof(standData) ~= "table" then
		return nil
	end

	local storageName = tostring(standData.LegacyStorageName or standData.CrewMemberName or standData.StorageName or "")
	local instanceId = tostring(standData.CrewMemberInstanceId or standData.InstanceId or "")
	if storageName == "" then
		return nil
	end

	local instanceData = getCrewCanaryCanonicalInventoryInstance(player, instanceId)
	return {
		Label = tostring(label or standName),
		StandName = tostring(standName),
		LegacyIdentity = storageName,
		InstanceId = instanceId,
		StorageName = tostring((instanceData and instanceData.StorageName) or storageName),
		Level = if instanceData then tonumber(instanceData.Level) or 1 else nil,
		CurrentXP = if instanceData then tonumber(instanceData.CurrentXP) or 0 else nil,
	}
end

local function getCrewCanaryFoodReadAuthorityContexts(player)
	local contexts = {}
	local seenLabels = {}
	local occupiedByIdentity = {}
	local standNames = getCrewCanaryStandReadAuthorityStandNames(player)

	for _, standName in ipairs(standNames) do
		local standData = DataManager:GetValue(player, "CrewMemberIncome." .. tostring(standName))
		if typeof(standData) == "table" then
			local legacyIdentity = tostring(standData.LegacyStorageName or standData.CrewMemberName or standData.StorageName or "")
			if legacyIdentity ~= "" and occupiedByIdentity[legacyIdentity] == nil then
				occupiedByIdentity[legacyIdentity] = standName
			end
		end
	end

	local function append(context)
		if typeof(context) ~= "table" then
			return
		end
		local label = tostring(context.Label or context.StandName or context.LegacyIdentity or "")
		if label == "" or seenLabels[label] == true then
			return
		end
		seenLabels[label] = true
		contexts[#contexts + 1] = context
	end

	for _, item in ipairs(CREW_CANARY_FOOD_READ_AUTHORITY_ITEMS) do
		local standName = occupiedByIdentity[item]
		if standName ~= nil then
			append(buildCrewCanaryFoodReadAuthorityContext(player, standName, "sample:" .. tostring(item)))
		else
			append({
				Label = "sample:" .. tostring(item),
				LegacyIdentity = tostring(item),
				StorageName = tostring(item),
			})
		end
	end

	for _, standName in ipairs(standNames) do
		append(buildCrewCanaryFoodReadAuthorityContext(player, standName, "stand:" .. tostring(standName)))
	end

	return contexts
end

local function newCrewCanaryFallbackPolicyCounts()
	return {
		CanonicalSelected = 0,
		AllowedCompatibilityFallback = 0,
		AllowedBrookFallback = 0,
		UnknownFallback = 0,
	}
end

local function addCrewCanaryFallbackPolicyCount(counts, result)
	if typeof(counts) ~= "table" or typeof(result) ~= "table" then
		return
	end

	local category = tostring(result.FallbackPolicyCategory or "")
	if category == "canonicalSelected" or result.UsedCanonical == true then
		counts.CanonicalSelected += 1
	elseif category == "allowedCompatibilityFallback" then
		counts.AllowedCompatibilityFallback += 1
	elseif category == "allowedBrookFallback" then
		counts.AllowedBrookFallback += 1
	elseif result.FallbackPolicyKind == "unknown_unapproved_fallback" then
		counts.UnknownFallback += 1
	end
end

local function formatCrewCanaryFallbackPolicyCounts(counts)
	counts = if typeof(counts) == "table" then counts else newCrewCanaryFallbackPolicyCounts()
	return string.format(
		"canonicalSelected=%d allowedCompatibilityFallback=%d allowedBrookFallback=%d unknownFallback=%d",
		tonumber(counts.CanonicalSelected) or 0,
		tonumber(counts.AllowedCompatibilityFallback) or 0,
		tonumber(counts.AllowedBrookFallback) or 0,
		tonumber(counts.UnknownFallback) or 0
	)
end

local function summarizeCrewCanaryHelperRows(rows, flags)
	local canonicalCount = 0
	local totalCount = 0
	local fallbackReasons = {}
	local policyCounts = newCrewCanaryFallbackPolicyCounts()
	local safeRows = if typeof(rows) == "table" then rows else {}

	for _, row in ipairs(safeRows) do
		local results = row.Results
		if typeof(results) ~= "table" then
			continue
		end

		for _, result in pairs(results) do
			if typeof(result) ~= "table" then
				continue
			end

			totalCount += 1
			if result.UsedCanonical == true then
				canonicalCount += 1
			end
			addCrewCanaryFallbackPolicyCount(policyCounts, result)

			local reason = tostring(result.FallbackReason or "")
			if reason ~= "" and reason ~= "none" then
				fallbackReasons[reason] = true
			end
		end
	end

	local reasonList = {}
	for reason in pairs(fallbackReasons) do
		reasonList[#reasonList + 1] = reason
	end
	table.sort(reasonList)

	return string.format(
		"helperRows=%d canonicalValues=%d/%d fallbackReasons=%s %s canonicalRead=%s gameplayReads=%s modelPreviewReads=%s",
		#safeRows,
		canonicalCount,
		totalCount,
		if #reasonList > 0 then table.concat(reasonList, ",") else "none",
		formatCrewCanaryFallbackPolicyCounts(policyCounts),
		tostring(flags and flags.CrewMemberCanonicalReadEnabled),
		tostring(flags and flags.CrewMemberCanaryGameplayReadsEnabled),
		tostring(flags and flags.CrewMemberCanaryModelPreviewReadsEnabled)
	)
end

local function summarizeCrewCanaryStandStatusRows(rows, flags)
	local canonicalCount = 0
	local totalCount = 0
	local fallbackReasons = {}
	local policyCounts = newCrewCanaryFallbackPolicyCounts()
	local safeRows = if typeof(rows) == "table" then rows else {}

	for _, row in ipairs(safeRows) do
		local result = row.Result
		if typeof(result) ~= "table" then
			continue
		end

		totalCount += 1
		if result.UsedCanonical == true then
			canonicalCount += 1
		end
		addCrewCanaryFallbackPolicyCount(policyCounts, result)

		local reason = tostring(result.FallbackReason or "")
		if reason ~= "" and reason ~= "none" then
			fallbackReasons[reason] = true
		end
	end

	local reasonList = {}
	for reason in pairs(fallbackReasons) do
		reasonList[#reasonList + 1] = reason
	end
	table.sort(reasonList)

	return string.format(
		"standStatusRows=%d canonicalValues=%d/%d fallbackReasons=%s %s canonicalRead=%s gameplayReads=%s helperReads=%s standStatusHelperRead=%s incomeStatusHelperRead=%s incomeToastHelperRead=%s foodStatusHelperRead=%s",
		#safeRows,
		canonicalCount,
		totalCount,
		if #reasonList > 0 then table.concat(reasonList, ",") else "none",
		formatCrewCanaryFallbackPolicyCounts(policyCounts),
		tostring(flags and flags.CrewMemberCanonicalReadEnabled),
		tostring(flags and flags.CrewMemberCanaryGameplayReadsEnabled),
		tostring(flags and flags.CrewMemberCanaryGameplayHelperReadsEnabled),
		tostring(flags and flags.CrewMemberCanaryStandStatusHelperReadEnabled),
		tostring(flags and flags.CrewMemberCanaryIncomeStatusHelperReadEnabled),
		tostring(flags and flags.CrewMemberCanaryIncomeToastHelperReadEnabled),
		tostring(flags and flags.CrewMemberCanaryFoodStatusHelperReadEnabled)
	)
end

local function summarizeCrewCanaryStandReadAuthorityRows(rows, flags)
	local canonicalCount = 0
	local totalCount = 0
	local fallbackReasons = {}
	local policyCounts = newCrewCanaryFallbackPolicyCounts()
	local rowSummaries = {}
	local safeRows = if typeof(rows) == "table" then rows else {}

	for _, row in ipairs(safeRows) do
		local result = row.Result
		if typeof(result) ~= "table" then
			continue
		end

		totalCount += 1
		if result.UsedCanonical == true then
			canonicalCount += 1
		end
		addCrewCanaryFallbackPolicyCount(policyCounts, result)

		local reason = tostring(result.FallbackReason or "")
		if reason ~= "" and reason ~= "none" then
			fallbackReasons[reason] = true
		end
		if #rowSummaries < 10 then
			rowSummaries[#rowSummaries + 1] = string.format(
				"%s legacy=%s canonical=%s display=%s source=%s fallback=%s policy=%s",
				tostring(result.StandName or row.StandName or ""),
				tostring(result.LegacyIdentity or ""),
				tostring(result.CanonicalIdentity or ""),
				tostring(result.DisplayName or ""),
				tostring(result.Source or ""),
				tostring(result.FallbackReason or "none"),
				tostring(result.FallbackPolicyCategory or "")
			)
		end
	end

	local reasonList = {}
	for reason in pairs(fallbackReasons) do
		reasonList[#reasonList + 1] = reason
	end
	table.sort(reasonList)

	return string.format(
		"standStatusReadAuthorityRows=%d canonicalSelected=%d/%d fallbackReasons=%s %s readAuthority=%s standStatusReadAuthority=%s writeAuthority=%s profileMigrationDryRun=%s profileMigrationWrite=%s canonicalRead=%s gameplayReads=%s rows=[%s]",
		#safeRows,
		canonicalCount,
		totalCount,
		if #reasonList > 0 then table.concat(reasonList, ",") else "none",
		formatCrewCanaryFallbackPolicyCounts(policyCounts),
		tostring(flags and flags.CrewMemberCanaryReadAuthorityEnabled),
		tostring(flags and flags.CrewMemberCanaryStandStatusReadAuthorityEnabled),
		tostring(flags and flags.CrewMemberCanaryWriteAuthorityEnabled),
		tostring(flags and flags.CrewMemberCanaryProfileMigrationDryRunEnabled),
		tostring(flags and flags.CrewMemberCanaryProfileMigrationWriteEnabled),
		tostring(flags and flags.CrewMemberCanonicalReadEnabled),
		tostring(flags and flags.CrewMemberCanaryGameplayReadsEnabled),
		table.concat(rowSummaries, "; ")
	)
end

local function summarizeCrewCanaryIncomeReadAuthorityRows(rows, flags)
	local canonicalCount = 0
	local totalCount = 0
	local fallbackReasons = {}
	local policyCounts = newCrewCanaryFallbackPolicyCounts()
	local rowSummaries = {}
	local safeRows = if typeof(rows) == "table" then rows else {}

	for _, row in ipairs(safeRows) do
		local result = row.Result
		if typeof(result) ~= "table" then
			continue
		end

		totalCount += 1
		if result.UsedCanonical == true then
			canonicalCount += 1
		end
		addCrewCanaryFallbackPolicyCount(policyCounts, result)

		local reason = tostring(result.FallbackReason or "")
		if reason ~= "" and reason ~= "none" then
			fallbackReasons[reason] = true
		end
		if #rowSummaries < 10 then
			rowSummaries[#rowSummaries + 1] = string.format(
				"%s legacy=%s canonicalIncome=%s inventory=%s display=%s income=%s/%s source=%s fallback=%s policy=%s",
				tostring(result.StandName or row.StandName or ""),
				tostring(result.LegacyIdentity or ""),
				tostring(result.CanonicalIncomeIdentity or ""),
				tostring(result.CanonicalInventoryIdentity or ""),
				tostring(result.DisplayName or ""),
				tostring(result.LegacyIncomeToCollect or 0),
				tostring(result.CanonicalIncomeToCollect or 0),
				tostring(result.Source or ""),
				tostring(result.FallbackReason or "none"),
				tostring(result.FallbackPolicyCategory or "")
			)
		end
	end

	local reasonList = {}
	for reason in pairs(fallbackReasons) do
		reasonList[#reasonList + 1] = reason
	end
	table.sort(reasonList)

	return string.format(
		"incomeStatusReadAuthorityRows=%d canonicalSelected=%d/%d fallbackReasons=%s %s readAuthority=%s incomeStatusReadAuthority=%s standStatusReadAuthority=%s writeAuthority=%s profileMigrationDryRun=%s profileMigrationWrite=%s canonicalRead=%s gameplayReads=%s rows=[%s]",
		#safeRows,
		canonicalCount,
		totalCount,
		if #reasonList > 0 then table.concat(reasonList, ",") else "none",
		formatCrewCanaryFallbackPolicyCounts(policyCounts),
		tostring(flags and flags.CrewMemberCanaryReadAuthorityEnabled),
		tostring(flags and flags.CrewMemberCanaryIncomeStatusReadAuthorityEnabled),
		tostring(flags and flags.CrewMemberCanaryStandStatusReadAuthorityEnabled),
		tostring(flags and flags.CrewMemberCanaryWriteAuthorityEnabled),
		tostring(flags and flags.CrewMemberCanaryProfileMigrationDryRunEnabled),
		tostring(flags and flags.CrewMemberCanaryProfileMigrationWriteEnabled),
		tostring(flags and flags.CrewMemberCanonicalReadEnabled),
		tostring(flags and flags.CrewMemberCanaryGameplayReadsEnabled),
		table.concat(rowSummaries, "; ")
	)
end

local function summarizeCrewCanaryFoodReadAuthorityRows(rows, flags)
	local canonicalCount = 0
	local totalCount = 0
	local fallbackReasons = {}
	local rowSummaries = {}
	local safeRows = if typeof(rows) == "table" then rows else {}

	for _, row in ipairs(safeRows) do
		local result = row.Result
		if typeof(result) ~= "table" then
			continue
		end

		totalCount += 1
		if result.UsedCanonical == true then
			canonicalCount += 1
		end

		local reason = tostring(result.FallbackReason or "")
		if reason ~= "" and reason ~= "none" then
			fallbackReasons[reason] = true
		end
		if #rowSummaries < 12 then
			local label = if typeof(row.Context) == "table"
				then tostring(row.Context.Label or row.Context.StandName or row.Context.LegacyIdentity or "")
				else tostring(result.StandName or result.LegacyIdentity or "")
			rowSummaries[#rowSummaries + 1] = string.format(
				"%s stand=%s legacy=%s instance=%s storage=%s canonical=%s assignedStand=%s display=%s level=%s/%s xp=%s/%s source=%s fallback=%s",
				label,
				tostring(result.StandName or ""),
				tostring(result.LegacyIdentity or ""),
				tostring(result.LegacyInstanceId or ""),
				tostring(result.LegacyStorageName or ""),
				tostring(result.CanonicalIdentity or ""),
				tostring(result.CanonicalAssignedStand or ""),
				tostring(result.DisplayName or ""),
				tostring(result.Level or ""),
				tostring(result.CanonicalLevel or ""),
				tostring(result.CurrentXP or ""),
				tostring(result.CanonicalCurrentXP or ""),
				tostring(result.Source or ""),
				tostring(result.FallbackReason or "none")
			)
		end
	end

	local reasonList = {}
	for reason in pairs(fallbackReasons) do
		reasonList[#reasonList + 1] = reason
	end
	table.sort(reasonList)

	return string.format(
		"foodStatusReadAuthorityRows=%d canonicalSelected=%d/%d fallbackReasons=%s readAuthority=%s foodStatusReadAuthority=%s standStatusReadAuthority=%s incomeStatusReadAuthority=%s writeAuthority=%s profileMigrationDryRun=%s profileMigrationWrite=%s canonicalRead=%s gameplayReads=%s rows=[%s]",
		#safeRows,
		canonicalCount,
		totalCount,
		if #reasonList > 0 then table.concat(reasonList, ",") else "none",
		tostring(flags and flags.CrewMemberCanaryReadAuthorityEnabled),
		tostring(flags and flags.CrewMemberCanaryFoodStatusReadAuthorityEnabled),
		tostring(flags and flags.CrewMemberCanaryStandStatusReadAuthorityEnabled),
		tostring(flags and flags.CrewMemberCanaryIncomeStatusReadAuthorityEnabled),
		tostring(flags and flags.CrewMemberCanaryWriteAuthorityEnabled),
		tostring(flags and flags.CrewMemberCanaryProfileMigrationDryRunEnabled),
		tostring(flags and flags.CrewMemberCanaryProfileMigrationWriteEnabled),
		tostring(flags and flags.CrewMemberCanonicalReadEnabled),
		tostring(flags and flags.CrewMemberCanaryGameplayReadsEnabled),
		table.concat(rowSummaries, "; ")
	)
end

local function summarizeCrewCanaryIncomeStatusRows(rows, flags)
	local canonicalCount = 0
	local totalCount = 0
	local fallbackReasons = {}
	local policyCounts = newCrewCanaryFallbackPolicyCounts()
	local safeRows = if typeof(rows) == "table" then rows else {}

	for _, row in ipairs(safeRows) do
		local result = row.Result
		if typeof(result) ~= "table" then
			continue
		end

		totalCount += 1
		if result.UsedCanonical == true then
			canonicalCount += 1
		end
		addCrewCanaryFallbackPolicyCount(policyCounts, result)

		local reason = tostring(result.FallbackReason or "")
		if reason ~= "" and reason ~= "none" then
			fallbackReasons[reason] = true
		end
	end

	local reasonList = {}
	for reason in pairs(fallbackReasons) do
		reasonList[#reasonList + 1] = reason
	end
	table.sort(reasonList)

	return string.format(
		"incomeStatusRows=%d canonicalValues=%d/%d fallbackReasons=%s %s canonicalRead=%s gameplayReads=%s helperReads=%s incomeStatusHelperRead=%s incomeToastHelperRead=%s standStatusHelperRead=%s foodStatusHelperRead=%s",
		#safeRows,
		canonicalCount,
		totalCount,
		if #reasonList > 0 then table.concat(reasonList, ",") else "none",
		formatCrewCanaryFallbackPolicyCounts(policyCounts),
		tostring(flags and flags.CrewMemberCanonicalReadEnabled),
		tostring(flags and flags.CrewMemberCanaryGameplayReadsEnabled),
		tostring(flags and flags.CrewMemberCanaryGameplayHelperReadsEnabled),
		tostring(flags and flags.CrewMemberCanaryIncomeStatusHelperReadEnabled),
		tostring(flags and flags.CrewMemberCanaryIncomeToastHelperReadEnabled),
		tostring(flags and flags.CrewMemberCanaryStandStatusHelperReadEnabled),
		tostring(flags and flags.CrewMemberCanaryFoodStatusHelperReadEnabled)
	)
end

local function summarizeCrewCanaryIncomeToastRows(rows, flags)
	local canonicalCount = 0
	local totalCount = 0
	local fallbackReasons = {}
	local safeRows = if typeof(rows) == "table" then rows else {}

	for _, row in ipairs(safeRows) do
		local result = row.Result
		if typeof(result) ~= "table" then
			continue
		end

		totalCount += 1
		if result.UsedCanonical == true then
			canonicalCount += 1
		end

		local reason = tostring(result.FallbackReason or "")
		if reason ~= "" and reason ~= "none" then
			fallbackReasons[reason] = true
		end
	end

	local reasonList = {}
	for reason in pairs(fallbackReasons) do
		reasonList[#reasonList + 1] = reason
	end
	table.sort(reasonList)

	return string.format(
		"incomeToastRows=%d canonicalValues=%d/%d fallbackReasons=%s canonicalRead=%s gameplayReads=%s helperReads=%s incomeToastHelperRead=%s incomeStatusHelperRead=%s standStatusHelperRead=%s foodStatusHelperRead=%s",
		#safeRows,
		canonicalCount,
		totalCount,
		if #reasonList > 0 then table.concat(reasonList, ",") else "none",
		tostring(flags and flags.CrewMemberCanonicalReadEnabled),
		tostring(flags and flags.CrewMemberCanaryGameplayReadsEnabled),
		tostring(flags and flags.CrewMemberCanaryGameplayHelperReadsEnabled),
		tostring(flags and flags.CrewMemberCanaryIncomeToastHelperReadEnabled),
		tostring(flags and flags.CrewMemberCanaryIncomeStatusHelperReadEnabled),
		tostring(flags and flags.CrewMemberCanaryStandStatusHelperReadEnabled),
		tostring(flags and flags.CrewMemberCanaryFoodStatusHelperReadEnabled)
	)
end

local function summarizeCrewCanaryFoodStatusRows(rows, flags)
	local canonicalCount = 0
	local totalCount = 0
	local fallbackReasons = {}
	local safeRows = if typeof(rows) == "table" then rows else {}

	for _, row in ipairs(safeRows) do
		local result = row.Result
		if typeof(result) ~= "table" then
			continue
		end

		totalCount += 1
		if result.UsedCanonical == true then
			canonicalCount += 1
		end

		local reason = tostring(result.FallbackReason or "")
		if reason ~= "" and reason ~= "none" then
			fallbackReasons[reason] = true
		end
	end

	local reasonList = {}
	for reason in pairs(fallbackReasons) do
		reasonList[#reasonList + 1] = reason
	end
	table.sort(reasonList)

	return string.format(
		"foodStatusRows=%d canonicalValues=%d/%d fallbackReasons=%s canonicalRead=%s gameplayReads=%s helperReads=%s foodStatusHelperRead=%s standStatusHelperRead=%s incomeStatusHelperRead=%s incomeToastHelperRead=%s",
		#safeRows,
		canonicalCount,
		totalCount,
		if #reasonList > 0 then table.concat(reasonList, ",") else "none",
		tostring(flags and flags.CrewMemberCanonicalReadEnabled),
		tostring(flags and flags.CrewMemberCanaryGameplayReadsEnabled),
		tostring(flags and flags.CrewMemberCanaryGameplayHelperReadsEnabled),
		tostring(flags and flags.CrewMemberCanaryFoodStatusHelperReadEnabled),
		tostring(flags and flags.CrewMemberCanaryStandStatusHelperReadEnabled),
		tostring(flags and flags.CrewMemberCanaryIncomeStatusHelperReadEnabled),
		tostring(flags and flags.CrewMemberCanaryIncomeToastHelperReadEnabled)
	)
end

local function summarizeCrewCanaryModelPreviewRows(rows, flags)
	local canonicalCount = 0
	local totalCount = 0
	local fallbackReasons = {}
	local safeRows = if typeof(rows) == "table" then rows else {}

	for _, row in ipairs(safeRows) do
		local descriptor = row.Descriptor
		if typeof(descriptor) ~= "table" then
			continue
		end

		totalCount += 1
		if descriptor.UsedCanonical == true then
			canonicalCount += 1
		end

		local reason = tostring(descriptor.FallbackReason or "")
		if reason ~= "" and reason ~= "none" then
			fallbackReasons[reason] = true
		end
	end

	local reasonList = {}
	for reason in pairs(fallbackReasons) do
		reasonList[#reasonList + 1] = reason
	end
	table.sort(reasonList)

	return string.format(
		"modelPreviewRows=%d canonicalModels=%d/%d fallbackReasons=%s canonicalRead=%s gameplayReads=%s modelPreviewReads=%s adminModelPreviewRead=%s indexModelPreviewRead=%s inventoryModelPreviewRead=%s",
		#safeRows,
		canonicalCount,
		totalCount,
		if #reasonList > 0 then table.concat(reasonList, ",") else "none",
		tostring(flags and flags.CrewMemberCanonicalReadEnabled),
		tostring(flags and flags.CrewMemberCanaryGameplayReadsEnabled),
		tostring(flags and flags.CrewMemberCanaryModelPreviewReadsEnabled),
		tostring(flags and flags.CrewMemberCanaryAdminModelPreviewReadEnabled),
		tostring(flags and flags.CrewMemberCanaryIndexModelPreviewReadEnabled),
		tostring(flags and flags.CrewMemberCanaryInventoryModelPreviewReadEnabled)
	)
end

local function summarizeCrewMigrationCategories(categoryCounts)
	local parts = {}
	for category, count in pairs(if typeof(categoryCounts) == "table" then categoryCounts else {}) do
		parts[#parts + 1] = tostring(category) .. "=" .. tostring(count)
	end
	table.sort(parts)
	return if #parts > 0 then table.concat(parts, ",") else "none"
end

local function getCrewMigrationCategoryCount(report, category)
	local counts = if typeof(report) == "table" then report.MismatchCountsByCategory else nil
	return if typeof(counts) == "table" then tonumber(counts[tostring(category or "")]) or 0 else 0
end

local function summarizeCrewMigrationFlags(flags)
	return string.format(
		"dryRun=%s saveLoadValidation=%s migrationKillSwitch=%s writeAuthority=%s quickSlotsWriteAuthority=%s productQuickSlotWriteAuthority=%s inventoryWriteAuthority=%s profileMigrationWrite=%s readAuthority=%s gameplayReads=%s canonicalRead=%s",
		tostring(flags and flags.CrewMemberCanaryProfileMigrationDryRunEnabled),
		tostring(flags and flags.CrewMemberCanarySaveLoadValidationEnabled),
		tostring(flags and flags.CrewMemberMigrationKillSwitchEnabled),
		tostring(flags and flags.CrewMemberCanaryWriteAuthorityEnabled),
		tostring(flags and flags.CrewMemberCanaryQuickSlotsWriteAuthorityEnabled),
		tostring(flags and flags.CrewMemberProductQuickSlotWriteAuthorityEnabled),
		tostring(flags and flags.CrewMemberInventoryWriteAuthorityEnabled),
		tostring(flags and flags.CrewMemberCanaryProfileMigrationWriteEnabled),
		tostring(flags and flags.CrewMemberCanaryReadAuthorityEnabled),
		tostring(flags and flags.CrewMemberCanaryGameplayReadsEnabled),
		tostring(flags and flags.CrewMemberCanonicalReadEnabled)
	)
end

local function isCrewMigrationDryRunSafe(flags)
	if flags.CrewMemberCanaryProfileMigrationDryRunEnabled ~= true then
		return false, "profile_migration_dryrun_disabled"
	end
	if flags.CrewMemberCanaryProfileMigrationWriteEnabled == true then
		return false, "profile_migration_write_enabled"
	end
	if flags.CrewMemberCanaryWriteAuthorityEnabled == true then
		return false, "write_authority_enabled"
	end
	if flags.CrewMemberCanaryQuickSlotsWriteAuthorityEnabled == true then
		return false, "quick_slots_write_authority_enabled"
	end
	if flags.CrewMemberProductQuickSlotWriteAuthorityEnabled == true then
		return false, "product_quick_slot_write_authority_enabled"
	end
	if flags.CrewMemberInventoryWriteAuthorityEnabled == true then
		return false, "inventory_write_authority_enabled"
	end
	if flags.CrewMemberCanonicalReadEnabled == true then
		return false, "canonical_read_enabled"
	end
	if flags.CrewMemberCanaryGameplayReadsEnabled == true then
		return false, "gameplay_reads_enabled"
	end
	if flags.CrewMemberMigrationKillSwitchEnabled ~= true then
		return false, "migration_kill_switch_not_enabled"
	end
	return true, nil
end

local function summarizeCrewMigrationStatus(flags, snapshot)
	local metadata = if typeof(snapshot) == "table" then snapshot.Metadata else nil
	return string.format(
		"migrationStatus %s snapshot=%s snapshotUser=%s snapshotTool=%s",
		summarizeCrewMigrationFlags(flags),
		tostring(snapshot ~= nil),
		tostring(metadata and metadata.UserId or ""),
		tostring(metadata and metadata.ToolVersion or "")
	)
end

local function summarizeCrewMigrationSnapshot(snapshot, flags)
	local counts = if typeof(snapshot) == "table" then snapshot.Counts else {}
	local validation = if typeof(snapshot) == "table" and snapshot.Metadata then snapshot.Metadata.ValidationSummary else {}
	return string.format(
		"migrationSnapshot legacyInstances=%d canonicalInstances=%d legacyStands=%d canonicalIncomeRows=%d legacyIndex=%d canonicalIndex=%d validationClean=%s validationStale=%s %s",
		counts.LegacyInstances or 0,
		counts.LiveCanonicalInstances or 0,
		counts.LegacyStandRows or 0,
		counts.LiveCanonicalIncomeRows or 0,
		counts.LegacyIndexEntries or 0,
		counts.LiveCanonicalIndexEntries or 0,
		tostring(validation.IsClean),
		tostring(validation.IsStale),
		summarizeCrewMigrationFlags(flags)
	)
end

local function summarizeCrewMigrationReport(label, report, flags)
	local counts = if typeof(report) == "table" then report.Counts else {}
	return string.format(
		"%s legacyInstances=%d projectedInstances=%d liveCanonicalInstances=%d order=%d/%d/%d quickSlotKeys=%d/%d standAssignments=%d incomeRows=%d/%d/%d index=%d/%d/%d levelMismatch=%d xpMismatch=%d duplicates=%d unknown=%d compatibilityReview=%d brookReview=%d blocking=%d review=%d unclassified=%d categories=%s canProceed=%s %s",
		tostring(label or "migrationReport"),
		counts.LegacyInstances or 0,
		counts.ProjectedInstances or 0,
		counts.LiveCanonicalInstances or 0,
		counts.LegacyOrder or 0,
		counts.ProjectedOrder or 0,
		counts.LiveCanonicalOrder or 0,
		counts.LegacyQuickSlotKeys or 0,
		counts.CanonicalQuickSlotKeys or 0,
		counts.LegacyStandRows or 0,
		counts.LegacyStandRows or 0,
		counts.ProjectedIncomeRows or 0,
		counts.LiveCanonicalIncomeRows or 0,
		counts.LegacyIndexEntries or 0,
		counts.ProjectedIndexEntries or 0,
		counts.LiveCanonicalIndexEntries or 0,
		getCrewMigrationCategoryCount(report, "level_mismatch"),
		getCrewMigrationCategoryCount(report, "xp_mismatch"),
		getCrewMigrationCategoryCount(report, "duplicate_assignment"),
		getCrewMigrationCategoryCount(report, "unknown_id"),
		getCrewMigrationCategoryCount(report, "compatibility_only"),
		getCrewMigrationCategoryCount(report, "brook_fallback"),
		report and report.BlockingCount or 0,
		report and report.ReviewCount or 0,
		report and report.UnclassifiedCount or 0,
		summarizeCrewMigrationCategories(report and report.MismatchCountsByCategory),
		tostring(report and report.CanProceed == true),
		summarizeCrewMigrationFlags(flags)
	)
end

local function summarizeCrewMigrationCompatibilityReview(report, flags)
	local counts = if typeof(report) == "table" then report.Counts else {}
	return string.format(
		"compatibilityReview compatibilityOnly=%d allowedCompatibility=%d undecidedCompatibility=%d brookFallback=%d allowedBrook=%d undecidedBrook=%d liveAssigned=%d inventoryOnly=%d indexOnly=%d metadataOnly=%d statuses=%s %s",
		tonumber(counts.CompatibilityOnly) or 0,
		tonumber(counts.AllowedCompatibility) or 0,
		tonumber(counts.UndecidedCompatibility) or 0,
		tonumber(counts.BrookFallback) or 0,
		tonumber(counts.AllowedBrook) or 0,
		tonumber(counts.UndecidedBrook) or 0,
		tonumber(counts.LiveAssigned) or 0,
		tonumber(counts.InventoryOnly) or 0,
		tonumber(counts.IndexOnly) or 0,
		tonumber(counts.MetadataOnly) or 0,
		summarizeCrewMigrationCategories(counts.StatusCategories),
		summarizeCrewMigrationFlags(flags)
	)
end

local function summarizeCrewMigrationSaveLoadReport(report, flags)
	return string.format(
		"migrationSaveLoad passed=%s blocking=%d review=%d unclassified=%d noGo=%s categories=%s %s",
		tostring(report and report.Passed == true),
		report and report.BlockingCount or 0,
		report and report.ReviewCount or 0,
		report and report.UnclassifiedCount or 0,
		if report and typeof(report.NoGoReasons) == "table" and #report.NoGoReasons > 0
			then table.concat(report.NoGoReasons, ",")
			else "none",
		summarizeCrewMigrationCategories(report and report.MismatchCountsByCategory),
		summarizeCrewMigrationFlags(flags)
	)
end

local function summarizeCrewMigrationAuditReport(label, auditReport, flags)
	local report = if typeof(auditReport) == "table" then auditReport.Report or auditReport else nil
	return string.format(
		"%s legacyInstances=%d projectedInstances=%d liveCanonicalInstances=%d order=%d/%d/%d quickSlotKeys=%d/%d standAssignments=%d incomeRows=%d/%d/%d index=%d/%d/%d levelMismatch=%d xpMismatch=%d duplicates=%d unknown=%d blocking=%d unclassified=%d compatibilityReview=%d brookReview=%d canProceed=%s canSave=%s hash=%s auditKey=%s store=%s noGo=%s %s",
		tostring(label or "migrationAudit"),
		report and report.LegacyInstances or 0,
		report and report.ProjectedInstances or 0,
		report and report.LiveCanonicalInstances or 0,
		report and report.LegacyOrder or 0,
		report and report.ProjectedOrder or 0,
		report and report.LiveCanonicalOrder or 0,
		report and report.LegacyQuickSlotKeys or 0,
		report and report.CanonicalQuickSlotKeys or 0,
		report and report.StandAssignments or 0,
		report and report.LegacyIncomeRows or 0,
		report and report.ProjectedIncomeRows or 0,
		report and report.LiveCanonicalIncomeRows or 0,
		report and report.LegacyIndexEntries or 0,
		report and report.ProjectedIndexEntries or 0,
		report and report.LiveCanonicalIndexEntries or 0,
		report and report.LevelMismatchCount or 0,
		report and report.XPMismatchCount or 0,
		report and report.DuplicateAssignmentCount or 0,
		report and report.UnknownIdCount or 0,
		report and report.BlockingCount or 0,
		report and report.UnclassifiedCount or 0,
		report and report.CompatibilityReviewCount or 0,
		report and report.BrookReviewCount or 0,
		tostring(report and report.CanProceed == true),
		tostring(auditReport and auditReport.CanSave == true),
		tostring(report and report.ReportHash or ""),
		tostring(auditReport and auditReport.Key or ""),
		tostring(CrewMigrationPlanner.AuditDataStoreName or ""),
		if auditReport and typeof(auditReport.NoGoReasons) == "table" and #auditReport.NoGoReasons > 0
			then table.concat(auditReport.NoGoReasons, ",")
			else "none",
		summarizeCrewMigrationFlags(flags)
	)
end

local function summarizeCrewMigrationAuditStoreResult(label, result)
	return string.format(
		"%s ok=%s missing=%s store=%s auditKey=%s reason=%s",
		tostring(label or "migrationAuditStore"),
		tostring(result and result.Ok == true),
		tostring(result and result.Missing == true),
		tostring(result and result.StoreName or CrewMigrationPlanner.AuditDataStoreName or ""),
		tostring(result and result.Key or ""),
		tostring(result and result.Reason or "none")
	)
end

local function summarizeCrewMigrationAuditComparison(comparison)
	return string.format(
		"migrationAuditCompare passed=%s mismatches=%d noGo=%s",
		tostring(comparison and comparison.Passed == true),
		comparison and typeof(comparison.Mismatches) == "table" and #comparison.Mismatches or 0,
		if comparison and typeof(comparison.NoGoReasons) == "table" and #comparison.NoGoReasons > 0
			then table.concat(comparison.NoGoReasons, ",")
			else "none"
	)
end

local function summarizeCrewMigrationWritePreviewRoots(diff)
	local parts = {}
	for _, rootDiff in ipairs(diff and diff.RootDiffs or {}) do
		parts[#parts + 1] = string.format(
			"%s:%s:+%d/-%d/~%d",
			tostring(rootDiff.Root),
			tostring(rootDiff.WouldChange),
			rootDiff.KeysAdded or 0,
			rootDiff.KeysRemoved or 0,
			rootDiff.KeysUpdated or 0
		)
	end
	return if #parts > 0 then table.concat(parts, ";") else "none"
end

local function summarizeCrewMigrationWritePreviewReport(label, previewReport, flags)
	local report = if typeof(previewReport) == "table" then previewReport.Report or previewReport else nil
	local diff = if typeof(previewReport) == "table" then previewReport.Diff else nil
	return string.format(
		"%s canWritePreview=%s canWriteMigration=%s noop=%s canonicalAlreadyMatchesProjection=%s rootsChanged=%d keysAdded=%d keysRemoved=%d keysUpdated=%d projectionHash=%s stable=%s rollbackHash=%s blocking=%d unclassified=%d duplicates=%d unknown=%d compatibilityReview=%d brookReview=%d roots=%s auditKey=%s store=%s noGo=%s %s",
		tostring(label or "migrationWritePreview"),
		tostring(report and report.CanWritePreview == true),
		tostring(report and report.CanWriteMigration == true),
		tostring(report and report.WouldBeNoOp == true),
		tostring(report and report.CanonicalAlreadyMatchesProjection == true),
		report and report.RootsChanged or 0,
		report and report.KeysAdded or 0,
		report and report.KeysRemoved or 0,
		report and report.KeysUpdated or 0,
		tostring(report and report.ProjectionHash or ""),
		tostring(report and report.ProjectionHashStable == true),
		tostring(report and report.RollbackSnapshotHash or ""),
		report and report.BlockingCount or 0,
		report and report.UnclassifiedCount or 0,
		report and report.DuplicateAssignmentCount or 0,
		report and report.UnknownIdCount or 0,
		report and report.CompatibilityReviewCount or 0,
		report and report.BrookReviewCount or 0,
		summarizeCrewMigrationWritePreviewRoots(diff),
		tostring(previewReport and previewReport.Key or ""),
		tostring(CrewMigrationPlanner.AuditDataStoreName or ""),
		if previewReport and typeof(previewReport.NoGoReasons) == "table" and #previewReport.NoGoReasons > 0
			then table.concat(previewReport.NoGoReasons, ",")
			else "none",
		summarizeCrewMigrationFlags(flags)
	)
end

local function summarizeCrewMigrationRootWrites(writes)
	local parts = {}
	for _, write in ipairs(writes or {}) do
		parts[#parts + 1] = string.format(
			"%s:%s",
			tostring(write.Root or write.Path or ""),
			tostring(write.Ok == true)
		)
	end
	return if #parts > 0 then table.concat(parts, ";") else "none"
end

local function summarizeCrewMigrationSampledWriteResult(result, flags)
	local postCompare = result and result.PostCompare
	return string.format(
		"migrationWriteSampled passed=%s writes=%d roots=%s postBlocking=%d postUnclassified=%d postCanProceed=%s noGo=%s %s",
		tostring(result and result.Passed == true),
		result and typeof(result.Writes) == "table" and #result.Writes or 0,
		summarizeCrewMigrationRootWrites(result and result.Writes),
		postCompare and postCompare.BlockingCount or 0,
		postCompare and postCompare.UnclassifiedCount or 0,
		tostring(postCompare and postCompare.CanProceed == true),
		if result and typeof(result.NoGoReasons) == "table" and #result.NoGoReasons > 0
			then table.concat(result.NoGoReasons, ",")
			else "none",
		summarizeCrewMigrationFlags(flags)
	)
end

local function summarizeCrewMigrationRollbackStatus(status)
	local snapshot = status and status.RollbackSnapshot
	local metadata = snapshot and snapshot.Metadata
	return string.format(
		"migrationRollbackStatus ok=%s missing=%s kind=%s store=%s auditKey=%s snapshotUser=%s snapshotPlace=%s snapshotGame=%s snapshotTool=%s reason=%s",
		tostring(status and status.Ok == true),
		tostring(status and status.Missing == true),
		tostring(status and status.RollbackKind or ""),
		tostring(status and status.StoreName or CrewMigrationPlanner.AuditDataStoreName or ""),
		tostring(status and status.Key or ""),
		tostring(metadata and metadata.UserId or ""),
		tostring(metadata and metadata.PlaceId or ""),
		tostring(metadata and metadata.GameId or ""),
		tostring(metadata and metadata.ToolVersion or ""),
		tostring(status and status.Reason or "none")
	)
end

local function summarizeCrewMigrationRollbackResult(result, flags)
	local postCompare = result and result.PostCompare
	return string.format(
		"migrationRollbackLatest passed=%s writes=%d roots=%s postBlocking=%d postUnclassified=%d postCanProceed=%s noGo=%s %s",
		tostring(result and result.Passed == true),
		result and typeof(result.Writes) == "table" and #result.Writes or 0,
		summarizeCrewMigrationRootWrites(result and result.Writes),
		postCompare and postCompare.BlockingCount or 0,
		postCompare and postCompare.UnclassifiedCount or 0,
		tostring(postCompare and postCompare.CanProceed == true),
		if result and typeof(result.NoGoReasons) == "table" and #result.NoGoReasons > 0
			then table.concat(result.NoGoReasons, ",")
			else "none",
		summarizeCrewMigrationFlags(flags)
	)
end

local function summarizeQuickSlotsWriteAuthorityStatus(status, flags)
	local canonical = status and status.Canonical
	return string.format(
		"quickSlotsWriteAuthority status canonical=%s/%s config=%s..%s inBounds=%s %s",
		tostring(canonical and canonical.UnlockedSlots),
		tostring(canonical and canonical.MaxSlots),
		tostring(status and status.ConfigMinSlots),
		tostring(status and status.ConfigMaxSlots),
		tostring(status and status.CanonicalInBounds == true),
		summarizeCrewMigrationFlags(flags)
	)
end

local function summarizeQuickSlotsWriteAuthorityResult(result, flags)
	local postCompare = result and result.PostCompare
	local postStatus = result and result.PostStatus
	local canonical = postStatus and postStatus.Canonical
	return string.format(
		"quickSlotsWriteAuthoritySet passed=%s canonicalSource=%s legacyDualWriteMatched=%s writes=%d new=%s/%s postBlocking=%d postUnclassified=%d postCanProceed=%s noGo=%s %s",
		tostring(result and result.Passed == true),
		tostring(result and result.CanonicalBecameMutationSource == true),
		tostring(result and result.LegacyDualWriteMatched == true),
		result and typeof(result.Writes) == "table" and #result.Writes or 0,
		tostring(canonical and canonical.UnlockedSlots),
		tostring(canonical and canonical.MaxSlots),
		postCompare and postCompare.BlockingCount or 0,
		postCompare and postCompare.UnclassifiedCount or 0,
		tostring(postCompare and postCompare.CanProceed == true),
		if result and typeof(result.NoGoReasons) == "table" and #result.NoGoReasons > 0
			then table.concat(result.NoGoReasons, ",")
			else "none",
		summarizeCrewMigrationFlags(flags)
	)
end

local function summarizeInventoryAuthorityStatus(status, flags)
	local canonical = status and status.Canonical
	return string.format(
		"inventoryAuthority status canonicalInstances=%s canonicalNext=%s blocking=%d unclassified=%d issues=%s %s",
		tostring(canonical and canonical.InstanceCount or 0),
		tostring(canonical and canonical.NextInstanceId),
		tonumber(status and status.BlockingCount) or 0,
		tonumber(status and status.UnclassifiedCount) or 0,
		if status and typeof(status.Issues) == "table" and #status.Issues > 0
			then table.concat(status.Issues, ",")
			else "none",
		summarizeCrewMigrationFlags(flags)
	)
end

local function summarizeProductQuickSlotsCanaryResult(result, flags)
	local initial = result and result.InitialStatus
	local preReceipt = result and result.PreReceiptStatus
	local postReceipt = result and result.PostReceiptStatus
	local postDuplicate = result and result.PostDuplicateStatus
	local postReceiptCompare = result and result.PostReceiptCompare
	local postDuplicateCompare = result and result.PostDuplicateCompare
	return string.format(
		"productQuickSlotsCanary passed=%s receipt=%s productId=%s initial=%s/%s preReceipt=%s/%s postReceipt=%s/%s postDuplicate=%s/%s firstDecision=%s secondDecision=%s receiptGrantCount=%d purchaseCached=%s postBlocking=%d postUnclassified=%d duplicateBlocking=%d duplicateUnclassified=%d noGo=%s %s",
		tostring(result and result.Passed == true),
		tostring(result and result.ReceiptId or ""),
		tostring(result and result.ProductId or ""),
		tostring(initial and initial.Canonical and initial.Canonical.UnlockedSlots),
		tostring(initial and initial.Canonical and initial.Canonical.MaxSlots),
		tostring(preReceipt and preReceipt.Canonical and preReceipt.Canonical.UnlockedSlots),
		tostring(preReceipt and preReceipt.Canonical and preReceipt.Canonical.MaxSlots),
		tostring(postReceipt and postReceipt.Canonical and postReceipt.Canonical.UnlockedSlots),
		tostring(postReceipt and postReceipt.Canonical and postReceipt.Canonical.MaxSlots),
		tostring(postDuplicate and postDuplicate.Canonical and postDuplicate.Canonical.UnlockedSlots),
		tostring(postDuplicate and postDuplicate.Canonical and postDuplicate.Canonical.MaxSlots),
		tostring(result and result.FirstReceiptDecision),
		tostring(result and result.SecondReceiptDecision),
		tonumber(result and result.ReceiptGrantCount) or 0,
		tostring(result and result.PurchaseCached == true),
		postReceiptCompare and postReceiptCompare.BlockingCount or 0,
		postReceiptCompare and postReceiptCompare.UnclassifiedCount or 0,
		postDuplicateCompare and postDuplicateCompare.BlockingCount or 0,
		postDuplicateCompare and postDuplicateCompare.UnclassifiedCount or 0,
		if result and typeof(result.NoGoReasons) == "table" and #result.NoGoReasons > 0
			then table.concat(result.NoGoReasons, ",")
			else "none",
		summarizeCrewMigrationFlags(flags)
	)
end

local function summarizeProductQuickSlotsReceiptStatus(result, flags)
	return string.format(
		"productQuickSlotsReceiptStatus passed=%s receipt=%s productId=%s profileCached=%s lastSavedCached=%s auditReceiptMatches=%s auditPhase=%s tokenUsed=%s globalFlagAtReceipt=%s rootWrites=%d rootsMatch=%s blocking=%d unclassified=%d noGo=%s %s",
		tostring(result and result.Passed == true),
		tostring(result and result.ReceiptId or ""),
		tostring(result and result.ProductId or ""),
		tostring(result and result.ProfilePurchaseCached == true),
		tostring(result and result.LastSavedPurchaseCached == true),
		tostring(result and result.AuditReceiptMatches == true),
		tostring(result and result.AuditPhase or ""),
		tostring(result and result.AuditTokenUsed == true),
		tostring(result and result.AuditGlobalFlagAtReceipt == true),
		tonumber(result and result.AuditRootWriteCount) or 0,
		tostring(result and result.Status and result.Status.RootsMatch == true),
		result and result.Compare and result.Compare.BlockingCount or 0,
		result and result.Compare and result.Compare.UnclassifiedCount or 0,
		if result and typeof(result.NoGoReasons) == "table" and #result.NoGoReasons > 0
			then table.concat(result.NoGoReasons, ",")
			else "none",
		summarizeCrewMigrationFlags(flags)
	)
end

local function ensureCrewMigrationAuditSession(player)
	local flags = CrewMemberCanonicalReadGate.GetFlags()
	if flags.CrewMemberCanaryProfileMigrationDryRunEnabled ~= true then
		local ok, reason, state = CrewMemberCanonicalReadGate.SetProfileMigrationDryRunSessionOverride(true)
		if ok ~= true then
			return nil, tostring(reason or "migration_dryrun_enable_failed")
		end
		flags = state and state.Flags or CrewMemberCanonicalReadGate.GetFlags()
		print(string.format(
			"[DevFruitDevCommands] %s enabled CrewMember migration dry-run diagnostics for audit %s",
			player.Name,
			summarizeCrewMigrationFlags(flags)
		))
	end

	local safe, safetyReason = isCrewMigrationDryRunSafe(flags)
	if safe ~= true then
		return nil, tostring(safetyReason)
	end

	return flags, nil
end

local function processCrewCanaryCommand(player, argumentText)
	if not isAuthorized(player) then
		return
	end

	local normalizedArgument = normalizeText(argumentText)
	local legacyMode = normalizedArgument:match("^legacy%s*(.*)$")
	local helperMode = normalizedArgument:match("^helpers%s+(.+)$")
	local gameplayHelpersMode = normalizedArgument:match("^gameplayhelpers%s+(.+)$")
	local modelPreviewMode = normalizedArgument:match("^modelpreviews%s+(.+)$")
	local readAuthorityMode = normalizedArgument:match("^readauthority%s*(.*)$")
	local migrationMode = normalizedArgument:match("^migration%s*(.*)$")
	local writeAuthorityMode = normalizedArgument:match("^writeauthority%s*(.*)$")
	local inventoryAuthorityMode = normalizedArgument:match("^inventoryauthority%s*(.*)$")
	local rawInventoryAuthorityMode = trimText(argumentText):match("^[Ii][Nn][Vv][Ee][Nn][Tt][Oo][Rr][Yy][Aa][Uu][Tt][Hh][Oo][Rr][Ii][Tt][Yy]%s*(.*)$")
	local productMode = normalizedArgument:match("^product%s*(.*)$")
	local migrationAuditMode = if migrationMode then migrationMode:match("^audit%s*(.*)$") else nil
	local migrationWritePreviewMode = if migrationMode then migrationMode:match("^writepreview%s*(.*)$") else nil
	local migrationWriteMode = if migrationMode then migrationMode:match("^write%s+(.+)$") else nil
	local migrationRollbackMode = if migrationMode then migrationMode:match("^rollback%s*(.*)$") else nil
	local standStatusMode = normalizedArgument:match("^standstatus%s*(.*)$")
	local incomeStatusMode = normalizedArgument:match("^incomestatus%s*(.*)$")
	local standIncomeStatusMode = normalizedArgument:match("^standincomestatus%s*(.*)$")
	local incomeToastMode = normalizedArgument:match("^incometoast%s*(.*)$")
	local foodStatusMode = normalizedArgument:match("^foodstatus%s*(.*)$")
	local standReadAuthorityMode = if readAuthorityMode then readAuthorityMode:match("^standstatus%s*(.*)$") else nil
	local incomeReadAuthorityMode = if readAuthorityMode then readAuthorityMode:match("^incomestatus%s*(.*)$") else nil
	local foodReadAuthorityMode = if readAuthorityMode then readAuthorityMode:match("^foodstatus%s*(.*)$") else nil
	local quickSlotsWriteAuthorityMode = if writeAuthorityMode then writeAuthorityMode:match("^quickslots%s*(.*)$") else nil
	local productQuickSlotsMode = if productMode then productMode:match("^quickslots%s*(.*)$") else nil
	local productQuickSlotsReceiptId = if productQuickSlotsMode
		then productQuickSlotsMode:match("^receipt%s+(.+)$")
			or productQuickSlotsMode:match("^cache%s+(.+)$")
		else nil
	local indexModelPreviewMode = if modelPreviewMode then modelPreviewMode:match("^index%s*(.*)$") else nil
	local inventoryModelPreviewMode = if modelPreviewMode then modelPreviewMode:match("^inventory%s*(.*)$") else nil
	if standReadAuthorityMode == "" then
		standReadAuthorityMode = "status"
	end
	if incomeReadAuthorityMode == "" then
		incomeReadAuthorityMode = "status"
	end
	if foodReadAuthorityMode == "" then
		foodReadAuthorityMode = "status"
	end
	if readAuthorityMode == "" then
		readAuthorityMode = "status"
	end
	if migrationMode == "" then
		migrationMode = "status"
	end
	if writeAuthorityMode == "" then
		writeAuthorityMode = "status"
	end
	if inventoryAuthorityMode == "" then
		inventoryAuthorityMode = "status"
	end
	if rawInventoryAuthorityMode == "" then
		rawInventoryAuthorityMode = "status"
	end
	if productMode == "" then
		productMode = "status"
	end
	if legacyMode == "" then
		legacyMode = "status"
	end
	if migrationAuditMode == "" then
		migrationAuditMode = "status"
	end
	if migrationWritePreviewMode == "" then
		migrationWritePreviewMode = "run"
	end
	if migrationRollbackMode == "" then
		migrationRollbackMode = "status"
	end
	if standStatusMode == "" then
		standStatusMode = "status"
	end
	if incomeStatusMode == "" then
		incomeStatusMode = "status"
	end
	if standIncomeStatusMode == "" then
		standIncomeStatusMode = "status"
	end
	if incomeToastMode == "" then
		incomeToastMode = "status"
	end
	if foodStatusMode == "" then
		foodStatusMode = "status"
	end
	if quickSlotsWriteAuthorityMode == "" then
		quickSlotsWriteAuthorityMode = "status"
	end
	if productQuickSlotsMode == "" then
		productQuickSlotsMode = "status"
	end
	if indexModelPreviewMode == "" then
		indexModelPreviewMode = "status"
	end
	if inventoryModelPreviewMode == "" then
		inventoryModelPreviewMode = "status"
	end
	if normalizedArgument ~= ""
		and normalizedArgument ~= "status"
		and normalizedArgument ~= "debug"
		and normalizedArgument ~= "helpers"
		and normalizedArgument ~= "gameplayhelpers"
		and normalizedArgument ~= "modelpreviews"
		and normalizedArgument ~= "readauthority"
		and normalizedArgument ~= "migration"
		and normalizedArgument ~= "writeauthority"
		and normalizedArgument ~= "inventoryauthority"
		and normalizedArgument ~= "product"
		and normalizedArgument ~= "legacy"
		and normalizedArgument ~= "standstatus"
		and normalizedArgument ~= "incomestatus"
		and normalizedArgument ~= "standincomestatus"
		and normalizedArgument ~= "incometoast"
		and normalizedArgument ~= "foodstatus"
		and helperMode == nil
		and gameplayHelpersMode == nil
		and modelPreviewMode == nil
		and readAuthorityMode == nil
		and migrationMode == nil
		and writeAuthorityMode == nil
		and inventoryAuthorityMode == nil
		and productMode == nil
		and legacyMode == nil
		and standStatusMode == nil
		and incomeStatusMode == nil
		and standIncomeStatusMode == nil
		and incomeToastMode == nil
		and foodStatusMode == nil
	then
		warn(string.format(
			"[DevFruitDevCommands] Invalid /crewcanary usage from %s. Use /crewcanary status, /crewcanary writeauthority quickslots status|on|off|set <count>, /crewcanary inventoryauthority status|on|off|grant <crew> [count]|remove <crew>|reconcile, /crewcanary product quickslots status|on|off|canary|delayed, /crewcanary helpers, /crewcanary helpers on|off|stale, /crewcanary gameplayhelpers on|off, /crewcanary standincomestatus on|off|stale, /crewcanary standstatus on|off|stale, /crewcanary incomestatus on|off|stale, /crewcanary incometoast on|off|stale, /crewcanary foodstatus, /crewcanary foodstatus on, /crewcanary foodstatus off, /crewcanary foodstatus stale, /crewcanary modelpreviews, /crewcanary modelpreviews on|off|stale, /crewcanary modelpreviews index on|off|stale, or /crewcanary modelpreviews inventory on|off|stale",
			player.Name
		))
		return false, "invalid_usage"
	end

	if legacyMode ~= nil then
		warn(string.format(
			"[DevFruitDevCommands] Retired /crewcanary legacy from %s argument='%s' reason=canonical_only",
			player.Name,
			tostring(legacyMode)
		))
		return false, "legacy_canary_retired"
	end

	if migrationMode ~= nil then
		warn(string.format(
			"[DevFruitDevCommands] Retired /crewcanary migration from %s argument='%s' reason=canonical_only",
			player.Name,
			tostring(migrationMode)
		))
		return false, "migration_tooling_retired"
	end

	if readAuthorityMode ~= nil then
		warn(string.format(
			"[DevFruitDevCommands] Retired /crewcanary readauthority from %s argument='%s' reason=legacy_roots_wiped",
			player.Name,
			tostring(readAuthorityMode)
		))
		return false, "read_authority_canary_retired"
	end

	if inventoryAuthorityMode ~= nil then
		local grantArgument = if rawInventoryAuthorityMode ~= nil
			then rawInventoryAuthorityMode:match("^[Gg][Rr][Aa][Nn][Tt]%s+(.+)$")
			else nil
		local removeArgument = if rawInventoryAuthorityMode ~= nil
			then rawInventoryAuthorityMode:match("^[Rr][Ee][Mm][Oo][Vv][Ee]%s+(.+)$")
			else nil
		if inventoryAuthorityMode ~= "status"
			and inventoryAuthorityMode ~= "on"
			and inventoryAuthorityMode ~= "enable"
			and inventoryAuthorityMode ~= "true"
			and inventoryAuthorityMode ~= "off"
			and inventoryAuthorityMode ~= "disable"
			and inventoryAuthorityMode ~= "false"
			and inventoryAuthorityMode ~= "reconcile"
			and grantArgument == nil
			and removeArgument == nil
		then
			warn(string.format(
				"[DevFruitDevCommands] Invalid /crewcanary inventoryauthority argument '%s' from %s. Use status, on, off, grant <crew> [count], remove <crew>, or reconcile",
				tostring(inventoryAuthorityMode),
				player.Name
			))
			return false, "invalid_inventory_authority_argument"
		end

		if inventoryAuthorityMode == "status" then
			local flags = CrewMemberCanonicalReadGate.GetFlags()
			local status = CrewInstanceService.BuildInventoryAuthorityStatus(player)
			CrewInstanceService.PrintInventoryAuthorityStatus(status)
			return true,
				"CrewMember inventory authority status printed to server output. "
					.. summarizeInventoryAuthorityStatus(status, flags)
		end

		if not AdminPermissions.IsSuperAdmin(player) then
			warn(string.format(
				"[DevFruitDevCommands] Rejected /crewcanary inventoryauthority %s from %s reason=not_super_admin",
				tostring(inventoryAuthorityMode),
				player.Name
			))
			return false, "not_super_admin"
		end

		if inventoryAuthorityMode == "on"
			or inventoryAuthorityMode == "enable"
			or inventoryAuthorityMode == "true"
		then
			local ok, reason, state = CrewMemberCanonicalReadGate.SetInventoryWriteAuthoritySessionOverride(true)
			if ok ~= true then
				warn(string.format(
					"[DevFruitDevCommands] Failed /crewcanary inventoryauthority on for %s reason=%s",
					player.Name,
					tostring(reason or "unknown_error")
				))
				return false, tostring(reason or "unknown_error")
			end

			local flags = state and state.Flags or CrewMemberCanonicalReadGate.GetFlags()
			local status = CrewInstanceService.BuildInventoryAuthorityStatus(player)
			CrewInstanceService.PrintInventoryAuthorityStatus(status)
			CrewMemberCanonicalReadGate.PrintStatus(player)
			return true,
				"CrewMember inventory write authority enabled for this staging server session. "
					.. summarizeInventoryAuthorityStatus(status, flags)
		end

		if inventoryAuthorityMode == "off"
			or inventoryAuthorityMode == "disable"
			or inventoryAuthorityMode == "false"
		then
			local ok, reason, state = CrewMemberCanonicalReadGate.SetInventoryWriteAuthoritySessionOverride(false)
			if ok ~= true then
				warn(string.format(
					"[DevFruitDevCommands] Failed /crewcanary inventoryauthority off for %s reason=%s",
					player.Name,
					tostring(reason or "unknown_error")
				))
				return false, tostring(reason or "unknown_error")
			end

			local flags = state and state.Flags or CrewMemberCanonicalReadGate.GetFlags()
			local status = CrewInstanceService.BuildInventoryAuthorityStatus(player)
			CrewInstanceService.PrintInventoryAuthorityStatus(status)
			CrewMemberCanonicalReadGate.PrintStatus(player)
			return true,
				"CrewMember inventory write authority disabled for this server session. "
					.. summarizeInventoryAuthorityStatus(status, flags)
		end

		if inventoryAuthorityMode == "reconcile" then
			local ok, reason, status = CrewInstanceService.ReconcileLegacyInventoryMirrorFromCrew(player, {})
			local flags = CrewMemberCanonicalReadGate.GetFlags()
			local finalStatus = status or CrewInstanceService.BuildInventoryAuthorityStatus(player)
			CrewInstanceService.PrintInventoryAuthorityStatus(finalStatus)
			if ok ~= true then
				return false,
					"CrewMember inventory authority reconciliation failed: "
						.. tostring(reason or "unknown_error")
						.. " "
						.. summarizeInventoryAuthorityStatus(finalStatus, flags)
			end
			return true,
				"CrewMember inventory authority reconciliation passed. "
					.. summarizeInventoryAuthorityStatus(finalStatus, flags)
		end

		if grantArgument ~= nil then
			local storageName = tostring(grantArgument or ""):match("^%s*(.-)%s*$") or ""
			local count = 1
			local parsedName, parsedCount = storageName:match("^(.-)%s+(%d+)$")
			if parsedName ~= nil and tostring(parsedName):match("%S") ~= nil then
				storageName = tostring(parsedName):match("^%s*(.-)%s*$") or storageName
				count = tonumber(parsedCount) or 1
			end
			local flags = CrewMemberCanonicalReadGate.GetFlags()
			if flags.CrewMemberInventoryWriteAuthorityEnabled ~= true then
				return false, "inventory_write_authority_disabled"
			end
			local ok = AddCrewMember:AddCrewMember(player, storageName, count, {
				_QuickSlotCapacityReserved = true,
			})
			local status = CrewInstanceService.BuildInventoryAuthorityStatus(player)
			CrewInstanceService.PrintInventoryAuthorityStatus(status)
			if ok ~= true or status.Passed ~= true then
				return false,
					"CrewMember inventory authority grant failed. "
						.. summarizeInventoryAuthorityStatus(status, flags)
			end
			return true,
				"CrewMember inventory authority grant passed. "
					.. summarizeInventoryAuthorityStatus(status, flags)
		end

		if removeArgument ~= nil then
			local storageName = tostring(removeArgument or ""):match("^%s*(.-)%s*$") or ""
			local flags = CrewMemberCanonicalReadGate.GetFlags()
			if flags.CrewMemberInventoryWriteAuthorityEnabled ~= true then
				return false, "inventory_write_authority_disabled"
			end
			local instanceId, _, reason = CrewInstanceService.RemoveAvailableInstance(player, storageName)
			local status = CrewInstanceService.BuildInventoryAuthorityStatus(player)
			CrewInstanceService.PrintInventoryAuthorityStatus(status)
			if instanceId == nil or status.Passed ~= true then
				return false,
					"CrewMember inventory authority remove failed reason="
						.. tostring(reason or "instance_unavailable")
						.. " "
						.. summarizeInventoryAuthorityStatus(status, flags)
			end
			return true,
				"CrewMember inventory authority remove passed instanceId="
					.. tostring(instanceId)
					.. " "
					.. summarizeInventoryAuthorityStatus(status, flags)
		end
	end

	if productMode ~= nil then
		if productQuickSlotsMode == nil then
			if productMode ~= "status" then
				warn(string.format(
					"[DevFruitDevCommands] Invalid /crewcanary product argument '%s' from %s. Use quickslots status|on|off|canary|delayed",
					tostring(productMode),
					player.Name
				))
				return false, "invalid_product_argument"
			end

			local flags = CrewMemberCanonicalReadGate.GetFlags()
			local status = CrewMigrationPlanner.BuildQuickSlotsWriteAuthorityStatus(player, {
				Flags = flags,
			})
			CrewMigrationPlanner.PrintQuickSlotsWriteAuthorityStatus(status)
			return true,
				"CrewMember product quick-slot status printed to server output. "
					.. summarizeQuickSlotsWriteAuthorityStatus(status, flags)
		end

		if productQuickSlotsMode ~= "status"
			and productQuickSlotsMode ~= "on"
			and productQuickSlotsMode ~= "enable"
			and productQuickSlotsMode ~= "true"
			and productQuickSlotsMode ~= "off"
			and productQuickSlotsMode ~= "disable"
			and productQuickSlotsMode ~= "false"
			and productQuickSlotsMode ~= "canary"
			and productQuickSlotsMode ~= "simulate"
			and productQuickSlotsMode ~= "delayed"
			and productQuickSlotsReceiptId == nil
	then
		warn(string.format(
			"[DevFruitDevCommands] Invalid /crewcanary product quickslots argument '%s' from %s. Use status, on, off, canary, or delayed",
				tostring(productQuickSlotsMode),
				player.Name
			))
			return false, "invalid_product_quickslots_argument"
		end

		if productQuickSlotsMode == "status" then
			local flags = CrewMemberCanonicalReadGate.GetFlags()
			local status = CrewMigrationPlanner.BuildQuickSlotsWriteAuthorityStatus(player, {
				Flags = flags,
			})
			CrewMigrationPlanner.PrintQuickSlotsWriteAuthorityStatus(status)
			return true,
				"CrewMember product quick-slot status printed to server output. "
					.. summarizeQuickSlotsWriteAuthorityStatus(status, flags)
		end

		if not AdminPermissions.IsSuperAdmin(player) then
			warn(string.format(
				"[DevFruitDevCommands] Rejected /crewcanary product quickslots %s from %s reason=not_super_admin",
				tostring(productQuickSlotsMode),
				player.Name
			))
			return false, "not_super_admin"
		end

		if productQuickSlotsReceiptId ~= nil then
			local receiptId = tostring(productQuickSlotsReceiptId or ""):match("^%s*(.-)%s*$") or ""
			local ok, receiptResult = pcall(function()
				return CrewQuickSlotService.BuildProductQuickSlotReceiptStatus(player, receiptId, {})
			end)
			local flags = CrewMemberCanonicalReadGate.GetFlags()
			if ok ~= true then
				warn(string.format(
					"[DevFruitDevCommands] Failed /crewcanary product quickslots receipt for %s receipt=%s error=%s %s",
					player.Name,
					tostring(receiptId),
					tostring(receiptResult),
					summarizeCrewMigrationFlags(flags)
				))
				return false, "product_quickslots_receipt_status_error:" .. tostring(receiptResult)
			end

			print("[CrewQuickSlots] " .. tostring(receiptResult and receiptResult.Summary or "productQuickSlotsReceiptStatus unavailable"))
			if receiptResult and receiptResult.Status then
				CrewMigrationPlanner.PrintQuickSlotsWriteAuthorityStatus(receiptResult.Status)
			end
			CrewMemberCanonicalReadGate.PrintStatus(player)
			if receiptResult.Passed ~= true then
				return false,
					"CrewMember product quick-slot receipt status failed. "
						.. summarizeProductQuickSlotsReceiptStatus(receiptResult, flags)
			end
			return true,
				"CrewMember product quick-slot receipt status passed. "
					.. summarizeProductQuickSlotsReceiptStatus(receiptResult, flags)
		end

		if productQuickSlotsMode == "on"
			or productQuickSlotsMode == "enable"
			or productQuickSlotsMode == "true"
		then
			local ok, reason, state = CrewMemberCanonicalReadGate.SetProductQuickSlotWriteAuthoritySessionOverride(true)
			if ok ~= true then
				warn(string.format(
					"[DevFruitDevCommands] Failed /crewcanary product quickslots on for %s reason=%s",
					player.Name,
					tostring(reason or "unknown_error")
				))
				return false, tostring(reason or "unknown_error")
			end

			local flags = state and state.Flags or CrewMemberCanonicalReadGate.GetFlags()
			local status = CrewMigrationPlanner.BuildQuickSlotsWriteAuthorityStatus(player, {
				Flags = flags,
			})
			CrewMigrationPlanner.PrintQuickSlotsWriteAuthorityStatus(status)
			print(string.format(
				"[DevFruitDevCommands] %s enabled CrewMember product quick-slot write authority %s",
				player.Name,
				summarizeQuickSlotsWriteAuthorityStatus(status, flags)
			))
			CrewMemberCanonicalReadGate.PrintStatus(player)
			return true,
				"CrewMember product quick-slot write authority enabled for this staging server session. "
					.. summarizeQuickSlotsWriteAuthorityStatus(status, flags)
		end

		if productQuickSlotsMode == "off"
			or productQuickSlotsMode == "disable"
			or productQuickSlotsMode == "false"
		then
			local ok, reason, state = CrewMemberCanonicalReadGate.SetProductQuickSlotWriteAuthoritySessionOverride(false)
			if ok ~= true then
				warn(string.format(
					"[DevFruitDevCommands] Failed /crewcanary product quickslots off for %s reason=%s",
					player.Name,
					tostring(reason or "unknown_error")
				))
				return false, tostring(reason or "unknown_error")
			end

			local flags = state and state.Flags or CrewMemberCanonicalReadGate.GetFlags()
			local status = CrewMigrationPlanner.BuildQuickSlotsWriteAuthorityStatus(player, {
				Flags = flags,
			})
			CrewMigrationPlanner.PrintQuickSlotsWriteAuthorityStatus(status)
			CrewMemberCanonicalReadGate.PrintStatus(player)
			return true,
				"CrewMember product quick-slot write authority disabled for this server session. "
					.. summarizeQuickSlotsWriteAuthorityStatus(status, flags)
		end

		if productQuickSlotsMode == "delayed" then
			local openOk, openReason, openState = CrewMemberCanonicalReadGate.SetProductQuickSlotWriteAuthoritySessionOverride(true)
			if openOk ~= true then
				return false, "product_quick_slot_delayed_open_failed:" .. tostring(openReason or "unknown_error")
			end
			local openFlags = openState and openState.Flags or CrewMemberCanonicalReadGate.GetFlags()
			local openStatus = CrewMigrationPlanner.BuildQuickSlotsWriteAuthorityStatus(player, {
				Flags = openFlags,
			})
			local token, tokenReason = CrewQuickSlotService.CreateProductQuickSlotAuthorityToken(player, {
				Source = "synthetic_delayed_receipt",
				IntendedTargetUnlockedSlots = openStatus.Canonical and math.min(
					(openStatus.Canonical.UnlockedSlots or 0) + 1,
					openStatus.Canonical.MaxSlots or 0
				),
				IntendedTargetMaxSlots = openStatus.Canonical and openStatus.Canonical.MaxSlots,
			})
			local closeOk, closeReason, closeState = CrewMemberCanonicalReadGate.SetProductQuickSlotWriteAuthoritySessionOverride(false)
			if closeOk ~= true then
				warn(string.format(
					"[DevFruitDevCommands] Failed to close delayed product quick-slot authority window for %s reason=%s",
					player.Name,
					tostring(closeReason or "unknown_error")
				))
			end
			if token == nil then
				return false, "product_quick_slot_delayed_token_failed:" .. tostring(tokenReason or "unknown_error")
			end
			local ok, canaryResult = pcall(function()
				return CrewQuickSlotService.RunDelayedProductQuickSlotAuthorityCanary(player, {
					Token = token,
				})
			end)
			local finalCloseOk, finalCloseReason, finalCloseState = CrewMemberCanonicalReadGate.SetProductQuickSlotWriteAuthoritySessionOverride(false)
			local closedFlags = finalCloseState and finalCloseState.Flags or closeState and closeState.Flags or CrewMemberCanonicalReadGate.GetFlags()
			if finalCloseOk ~= true then
				warn(string.format(
					"[DevFruitDevCommands] Failed final delayed product quick-slot authority close for %s reason=%s",
					player.Name,
					tostring(finalCloseReason or "unknown_error")
				))
			end
			if ok ~= true then
				return false, "product_quickslots_delayed_canary_error:" .. tostring(canaryResult)
			end

			print("[CrewQuickSlots] " .. tostring(canaryResult and canaryResult.Summary or "delayedProductQuickSlotsCanary unavailable"))
			local status = CrewMigrationPlanner.BuildQuickSlotsWriteAuthorityStatus(player, {
				Flags = closedFlags,
			})
			CrewMigrationPlanner.PrintQuickSlotsWriteAuthorityStatus(status)
			CrewMemberCanonicalReadGate.PrintStatus(player)
			if canaryResult.Passed ~= true then
				return false,
					"CrewMember delayed product quick-slot canary failed. "
						.. tostring(canaryResult.Summary or "")
						.. " "
						.. summarizeCrewMigrationFlags(closedFlags)
			end
			return true,
				"CrewMember delayed product quick-slot canary passed. "
					.. tostring(canaryResult.Summary or "")
					.. " "
					.. summarizeCrewMigrationFlags(closedFlags)
		end

		local flags = CrewMemberCanonicalReadGate.GetFlags()
		if flags.CrewMemberProductQuickSlotWriteAuthorityEnabled ~= true then
			return false, "product_quick_slot_write_authority_disabled"
		end
		local ok, canaryResult = pcall(function()
			return CrewQuickSlotService.RunProductQuickSlotAuthorityCanary(player, {
				Flags = flags,
			})
		end)
		local closeOk, closeReason, closeState = CrewMemberCanonicalReadGate.SetProductQuickSlotWriteAuthoritySessionOverride(false)
		local closedFlags = closeState and closeState.Flags or CrewMemberCanonicalReadGate.GetFlags()
		if closeOk ~= true then
			warn(string.format(
				"[DevFruitDevCommands] Failed to close CrewMember product quick-slot write-authority window for %s reason=%s",
				player.Name,
				tostring(closeReason or "unknown_error")
			))
		end
		if ok ~= true then
			warn(string.format(
				"[DevFruitDevCommands] Failed /crewcanary product quickslots canary for %s error=%s %s",
				player.Name,
				tostring(canaryResult),
				summarizeCrewMigrationFlags(closedFlags)
			))
			return false, "product_quickslots_canary_error:" .. tostring(canaryResult)
		end

		print("[CrewQuickSlots] " .. tostring(canaryResult and canaryResult.Summary or "productQuickSlotsCanary unavailable"))
		local status = CrewMigrationPlanner.BuildQuickSlotsWriteAuthorityStatus(player, {
			Flags = closedFlags,
		})
		CrewMigrationPlanner.PrintQuickSlotsWriteAuthorityStatus(status)
		CrewMemberCanonicalReadGate.PrintStatus(player)
		if canaryResult.Passed ~= true then
			return false,
				"CrewMember product quick-slot canary failed. "
					.. summarizeProductQuickSlotsCanaryResult(canaryResult, closedFlags)
		end
		return true,
			"CrewMember product quick-slot canary passed. "
				.. summarizeProductQuickSlotsCanaryResult(canaryResult, closedFlags)
	end

	if writeAuthorityMode ~= nil then
		if quickSlotsWriteAuthorityMode == nil then
			if writeAuthorityMode ~= "status" then
				warn(string.format(
					"[DevFruitDevCommands] Invalid /crewcanary writeauthority argument '%s' from %s. Use quickslots status|on|off|set <count>",
					tostring(writeAuthorityMode),
					player.Name
				))
				return false, "invalid_write_authority_argument"
			end

			local flags = CrewMemberCanonicalReadGate.GetFlags()
			local status = CrewMigrationPlanner.BuildQuickSlotsWriteAuthorityStatus(player, {
				Flags = flags,
			})
			CrewMigrationPlanner.PrintQuickSlotsWriteAuthorityStatus(status)
			return true,
				"CrewMember write-authority status printed to server output. "
					.. summarizeQuickSlotsWriteAuthorityStatus(status, flags)
		end

		local setCountText = quickSlotsWriteAuthorityMode:match("^set%s+(.+)$")
		if quickSlotsWriteAuthorityMode ~= "status"
			and quickSlotsWriteAuthorityMode ~= "on"
			and quickSlotsWriteAuthorityMode ~= "enable"
			and quickSlotsWriteAuthorityMode ~= "true"
			and quickSlotsWriteAuthorityMode ~= "off"
			and quickSlotsWriteAuthorityMode ~= "disable"
			and quickSlotsWriteAuthorityMode ~= "false"
			and setCountText == nil
		then
			warn(string.format(
				"[DevFruitDevCommands] Invalid /crewcanary writeauthority quickslots argument '%s' from %s. Use status, on, off, or set <count>",
				tostring(quickSlotsWriteAuthorityMode),
				player.Name
			))
			return false, "invalid_quickslots_write_authority_argument"
		end

		if quickSlotsWriteAuthorityMode == "status" then
			local flags = CrewMemberCanonicalReadGate.GetFlags()
			local status = CrewMigrationPlanner.BuildQuickSlotsWriteAuthorityStatus(player, {
				Flags = flags,
			})
			CrewMigrationPlanner.PrintQuickSlotsWriteAuthorityStatus(status)
			return true,
				"CrewMember quick-slot write-authority status printed to server output. "
					.. summarizeQuickSlotsWriteAuthorityStatus(status, flags)
		end

		if not AdminPermissions.IsSuperAdmin(player) then
			warn(string.format(
				"[DevFruitDevCommands] Rejected /crewcanary writeauthority quickslots %s from %s reason=not_super_admin",
				tostring(quickSlotsWriteAuthorityMode),
				player.Name
			))
			return false, "not_super_admin"
		end

		if quickSlotsWriteAuthorityMode == "on"
			or quickSlotsWriteAuthorityMode == "enable"
			or quickSlotsWriteAuthorityMode == "true"
		then
			local ok, reason, state = CrewMemberCanonicalReadGate.SetQuickSlotsWriteAuthoritySessionOverride(true)
			if ok ~= true then
				warn(string.format(
					"[DevFruitDevCommands] Failed /crewcanary writeauthority quickslots on for %s reason=%s",
					player.Name,
					tostring(reason or "unknown_error")
				))
				return false, tostring(reason or "unknown_error")
			end

			local flags = state and state.Flags or CrewMemberCanonicalReadGate.GetFlags()
			local status = CrewMigrationPlanner.BuildQuickSlotsWriteAuthorityStatus(player, {
				Flags = flags,
			})
			CrewMigrationPlanner.PrintQuickSlotsWriteAuthorityStatus(status)
			print(string.format(
				"[DevFruitDevCommands] %s enabled CrewMember quick-slot write authority %s",
				player.Name,
				summarizeQuickSlotsWriteAuthorityStatus(status, flags)
			))
			CrewMemberCanonicalReadGate.PrintStatus(player)
			return true,
				"CrewMember quick-slot write authority enabled for this staging server session. "
					.. summarizeQuickSlotsWriteAuthorityStatus(status, flags)
		end

		if quickSlotsWriteAuthorityMode == "off"
			or quickSlotsWriteAuthorityMode == "disable"
			or quickSlotsWriteAuthorityMode == "false"
		then
			local ok, reason, state = CrewMemberCanonicalReadGate.SetQuickSlotsWriteAuthoritySessionOverride(false)
			if ok ~= true then
				warn(string.format(
					"[DevFruitDevCommands] Failed /crewcanary writeauthority quickslots off for %s reason=%s",
					player.Name,
					tostring(reason or "unknown_error")
				))
				return false, tostring(reason or "unknown_error")
			end

			local flags = state and state.Flags or CrewMemberCanonicalReadGate.GetFlags()
			local status = CrewMigrationPlanner.BuildQuickSlotsWriteAuthorityStatus(player, {
				Flags = flags,
			})
			CrewMigrationPlanner.PrintQuickSlotsWriteAuthorityStatus(status)
			print(string.format(
				"[DevFruitDevCommands] %s disabled CrewMember quick-slot write authority %s",
				player.Name,
				summarizeQuickSlotsWriteAuthorityStatus(status, flags)
			))
			CrewMemberCanonicalReadGate.PrintStatus(player)
			return true,
				"CrewMember quick-slot write authority disabled for this server session. "
					.. summarizeQuickSlotsWriteAuthorityStatus(status, flags)
		end

		local requestedCount = tonumber(setCountText)
		if requestedCount == nil then
			return false, "invalid_quickslot_count"
		end

		local flags = CrewMemberCanonicalReadGate.GetFlags()
		local validationStatus = CrewMemberCanonicalReadGate.PrintStatus(player)
		local ok, result = pcall(function()
			return CrewMigrationPlanner.ExecuteQuickSlotsWriteAuthoritySet(player, requestedCount, {
				ValidationStatus = validationStatus,
				Flags = flags,
			})
		end)
		local closeOk, closeReason, closeState = CrewMemberCanonicalReadGate.SetQuickSlotsWriteAuthoritySessionOverride(false)
		local closedFlags = closeState and closeState.Flags or CrewMemberCanonicalReadGate.GetFlags()
		if closeOk ~= true then
			warn(string.format(
				"[DevFruitDevCommands] Failed to close CrewMember quick-slot write-authority window for %s reason=%s",
				player.Name,
				tostring(closeReason or "unknown_error")
			))
		end
		if ok ~= true then
			warn(string.format(
				"[DevFruitDevCommands] Failed /crewcanary writeauthority quickslots set for %s error=%s %s",
				player.Name,
				tostring(result),
				summarizeCrewMigrationFlags(closedFlags)
			))
			return false, "quickslots_write_authority_error:" .. tostring(result)
		end

		CrewMigrationPlanner.PrintQuickSlotsWriteAuthorityResult(result)
		if result.Passed ~= true then
			return false,
				"CrewMember quick-slot write-authority set failed validation. "
					.. summarizeQuickSlotsWriteAuthorityResult(result, closedFlags)
		end
		return true,
			"CrewMember quick-slot write-authority set passed. "
				.. summarizeQuickSlotsWriteAuthorityResult(result, closedFlags)
	end

	if migrationMode == "on" or migrationMode == "enable" or migrationMode == "true" then
		if not AdminPermissions.IsSuperAdmin(player) then
			warn(string.format(
				"[DevFruitDevCommands] Rejected /crewcanary migration on from %s reason=not_super_admin",
				player.Name
			))
			return false, "not_super_admin"
		end

		local ok, reason, state = CrewMemberCanonicalReadGate.SetProfileMigrationDryRunSessionOverride(true)
		if ok ~= true then
			warn(string.format(
				"[DevFruitDevCommands] Failed /crewcanary migration on for %s reason=%s",
				player.Name,
				tostring(reason or "unknown_error")
			))
			return false, tostring(reason or "unknown_error")
		end

		local flags = state and state.Flags or CrewMemberCanonicalReadGate.GetFlags()
		print(string.format(
			"[DevFruitDevCommands] %s enabled CrewMember migration dry-run diagnostics %s",
			player.Name,
			summarizeCrewMigrationFlags(flags)
		))
		CrewMemberCanonicalReadGate.PrintStatus(player)
		return true,
			"CrewMember migration dry-run diagnostics enabled for this staging server session. "
				.. summarizeCrewMigrationStatus(flags, CrewMigrationPlanner.GetDiagnosticSnapshot(player))
	end

	if migrationMode == "off" or migrationMode == "disable" or migrationMode == "false" then
		if not AdminPermissions.IsSuperAdmin(player) then
			warn(string.format(
				"[DevFruitDevCommands] Rejected /crewcanary migration off from %s reason=not_super_admin",
				player.Name
			))
			return false, "not_super_admin"
		end

		local ok, reason, state = CrewMemberCanonicalReadGate.SetProfileMigrationDryRunSessionOverride(false)
		if ok ~= true then
			warn(string.format(
				"[DevFruitDevCommands] Failed /crewcanary migration off for %s reason=%s",
				player.Name,
				tostring(reason or "unknown_error")
			))
			return false, tostring(reason or "unknown_error")
		end

		local flags = state and state.Flags or CrewMemberCanonicalReadGate.GetFlags()
		print(string.format(
			"[DevFruitDevCommands] %s disabled CrewMember migration dry-run diagnostics %s",
			player.Name,
			summarizeCrewMigrationFlags(flags)
		))
		CrewMemberCanonicalReadGate.PrintStatus(player)
		return true,
			"CrewMember migration dry-run diagnostics disabled for this server session. "
				.. summarizeCrewMigrationStatus(flags, CrewMigrationPlanner.GetDiagnosticSnapshot(player))
	end

	if migrationMode == "clear" then
		if not AdminPermissions.IsSuperAdmin(player) then
			warn(string.format(
				"[DevFruitDevCommands] Rejected /crewcanary migration clear from %s reason=not_super_admin",
				player.Name
			))
			return false, "not_super_admin"
		end

		local cleared = CrewMigrationPlanner.ClearDiagnosticSnapshot(player)
		local flags = CrewMemberCanonicalReadGate.GetFlags()
		print(string.format(
			"[DevFruitDevCommands] %s cleared CrewMember migration diagnostic snapshot cleared=%s %s",
			player.Name,
			tostring(cleared),
			summarizeCrewMigrationFlags(flags)
		))
		return true,
			"CrewMember migration diagnostic snapshot cleared. "
				.. summarizeCrewMigrationStatus(flags, CrewMigrationPlanner.GetDiagnosticSnapshot(player))
	end

	if migrationAuditMode ~= nil then
		if migrationAuditMode ~= "status"
			and migrationAuditMode ~= "before"
			and migrationAuditMode ~= "after"
			and migrationAuditMode ~= "clear"
		then
			warn(string.format(
				"[DevFruitDevCommands] Invalid /crewcanary migration audit argument '%s' from %s. Use status, before, after, or clear",
				tostring(migrationAuditMode),
				player.Name
			))
			return false, "invalid_migration_audit_argument"
		end

		if migrationAuditMode == "status" then
			local flags = CrewMemberCanonicalReadGate.GetFlags()
			local loadResult = CrewMigrationPlanner.LoadMigrationAudit(player)
			print(string.format(
				"[DevFruitDevCommands] %s requested CrewMember migration audit status %s %s",
				player.Name,
				summarizeCrewMigrationFlags(flags),
				summarizeCrewMigrationAuditStoreResult("auditStatus", loadResult)
			))
			if loadResult.Ok ~= true then
				return false,
					"CrewMember migration audit status could not read audit DataStore. "
						.. summarizeCrewMigrationAuditStoreResult("auditStatus", loadResult)
			end
			return true,
				"CrewMember migration audit status printed to server output. "
					.. summarizeCrewMigrationAuditStoreResult("auditStatus", loadResult)
		end

		if not AdminPermissions.IsSuperAdmin(player) then
			warn(string.format(
				"[DevFruitDevCommands] Rejected /crewcanary migration audit %s from %s reason=not_super_admin",
				tostring(migrationAuditMode),
				player.Name
			))
			return false, "not_super_admin"
		end

		if migrationAuditMode == "clear" then
			local clearResult = CrewMigrationPlanner.ClearMigrationAudit(player)
			print(string.format(
				"[DevFruitDevCommands] %s cleared CrewMember migration audit report %s",
				player.Name,
				summarizeCrewMigrationAuditStoreResult("auditClear", clearResult)
			))
			if clearResult.Ok ~= true then
				return false,
					"CrewMember migration audit clear failed. "
						.. summarizeCrewMigrationAuditStoreResult("auditClear", clearResult)
			end
			return true,
				"CrewMember migration audit report cleared. "
					.. summarizeCrewMigrationAuditStoreResult("auditClear", clearResult)
		end

		local flags, safetyReason = ensureCrewMigrationAuditSession(player)
		if flags == nil then
			warn(string.format(
				"[DevFruitDevCommands] Rejected /crewcanary migration audit %s from %s reason=%s",
				tostring(migrationAuditMode),
				player.Name,
				tostring(safetyReason)
			))
			return false, tostring(safetyReason)
		end

		local validationStatus = CrewMemberCanonicalReadGate.PrintStatus(player)
		local compareReport = CrewMigrationPlanner.BuildMigrationCompareReport(player, {
			Snapshot = CrewMigrationPlanner.GetDiagnosticSnapshot(player),
			ValidationStatus = validationStatus,
		})
		CrewMigrationPlanner.PrintMigrationCompareReport(compareReport)
		local auditReport = CrewMigrationPlanner.BuildMigrationAuditReport(player, migrationAuditMode, {
			ValidationStatus = validationStatus,
			CompareReport = compareReport,
			Flags = flags,
		})
		CrewMigrationPlanner.PrintMigrationAuditReport(migrationAuditMode, auditReport)
		if auditReport.CanSave ~= true then
			warn(string.format(
				"[DevFruitDevCommands] Rejected /crewcanary migration audit %s from %s reason=audit_no_go noGo=%s %s",
				tostring(migrationAuditMode),
				player.Name,
				if typeof(auditReport.NoGoReasons) == "table" and #auditReport.NoGoReasons > 0
					then table.concat(auditReport.NoGoReasons, ",")
					else "none",
				summarizeCrewMigrationFlags(flags)
			))
			return false,
				"CrewMember migration audit blocked by no-go condition. "
					.. summarizeCrewMigrationAuditReport("migrationAudit", auditReport, flags)
		end

		if migrationAuditMode == "before" then
			local saveResult = CrewMigrationPlanner.SaveMigrationAuditBefore(player, auditReport)
			print(string.format(
				"[DevFruitDevCommands] %s saved CrewMember migration audit before %s %s",
				player.Name,
				summarizeCrewMigrationAuditReport("migrationAuditBefore", auditReport, flags),
				summarizeCrewMigrationAuditStoreResult("auditSave", saveResult)
			))
			if saveResult.Ok ~= true then
				return false,
					"CrewMember migration audit before generated, but audit DataStore save failed. "
						.. summarizeCrewMigrationAuditStoreResult("auditSave", saveResult)
			end
			return true,
				"CrewMember migration audit before saved. "
					.. summarizeCrewMigrationAuditReport("migrationAuditBefore", auditReport, flags)
		end

		if migrationAuditMode == "after" then
			local loadResult = CrewMigrationPlanner.LoadMigrationAudit(player)
			if loadResult.Ok ~= true or loadResult.Missing == true then
				warn(string.format(
					"[DevFruitDevCommands] Rejected /crewcanary migration audit after from %s reason=before_audit_unavailable %s",
					player.Name,
					summarizeCrewMigrationAuditStoreResult("auditLoad", loadResult)
				))
				return false,
					"CrewMember migration audit after could not load a before report. "
						.. summarizeCrewMigrationAuditStoreResult("auditLoad", loadResult)
			end

			local comparison = CrewMigrationPlanner.CompareMigrationAuditReports(loadResult.Record.Before, auditReport.Report)
			CrewMigrationPlanner.PrintMigrationAuditComparison(comparison)
			local saveResult = CrewMigrationPlanner.SaveMigrationAuditAfter(
				player,
				loadResult.Record,
				auditReport,
				comparison
			)
			print(string.format(
				"[DevFruitDevCommands] %s completed CrewMember migration audit after %s %s %s",
				player.Name,
				summarizeCrewMigrationAuditReport("migrationAuditAfter", auditReport, flags),
				summarizeCrewMigrationAuditComparison(comparison),
				summarizeCrewMigrationAuditStoreResult("auditSaveAfter", saveResult)
			))
			if comparison.Passed ~= true then
				return false,
					"CrewMember migration audit after failed. "
						.. summarizeCrewMigrationAuditComparison(comparison)
			end
			if saveResult.Ok ~= true then
				return false,
					"CrewMember migration audit after passed, but audit DataStore result save failed. "
						.. summarizeCrewMigrationAuditStoreResult("auditSaveAfter", saveResult)
			end
			return true,
				"CrewMember migration audit after passed. "
					.. summarizeCrewMigrationAuditComparison(comparison)
		end
	end

	if migrationWritePreviewMode ~= nil then
		if migrationWritePreviewMode ~= "run"
			and migrationWritePreviewMode ~= "status"
			and migrationWritePreviewMode ~= "clear"
			and migrationWritePreviewMode ~= "export"
		then
			warn(string.format(
				"[DevFruitDevCommands] Invalid /crewcanary migration writepreview argument '%s' from %s. Use writepreview, writepreview status, writepreview clear, or writepreview export",
				tostring(migrationWritePreviewMode),
				player.Name
			))
			return false, "invalid_migration_writepreview_argument"
		end

		if migrationWritePreviewMode == "status" or migrationWritePreviewMode == "export" then
			local flags = CrewMemberCanonicalReadGate.GetFlags()
			local loadResult = CrewMigrationPlanner.LoadMigrationWritePreview(player)
			local previewReport = {
				StoreName = loadResult.StoreName,
				Key = loadResult.Key,
				Report = loadResult.WritePreview,
				Diff = loadResult.WritePreviewDiff,
			}
			print(string.format(
				"[DevFruitDevCommands] %s requested CrewMember migration writepreview %s %s %s",
				player.Name,
				tostring(migrationWritePreviewMode),
				summarizeCrewMigrationAuditStoreResult("writePreviewStatus", loadResult),
				summarizeCrewMigrationWritePreviewReport("migrationWritePreviewStatus", previewReport, flags)
			))
			if loadResult.Ok ~= true then
				return false,
					"CrewMember migration writepreview status could not read audit DataStore. "
						.. summarizeCrewMigrationAuditStoreResult("writePreviewStatus", loadResult)
			end
			if loadResult.Missing == true then
				return true,
					"CrewMember migration writepreview status has no stored preview. "
						.. summarizeCrewMigrationAuditStoreResult("writePreviewStatus", loadResult)
			end
			return true,
				"CrewMember migration writepreview status printed to server output. "
					.. summarizeCrewMigrationWritePreviewReport("migrationWritePreviewStatus", previewReport, flags)
		end

		if not AdminPermissions.IsSuperAdmin(player) then
			warn(string.format(
				"[DevFruitDevCommands] Rejected /crewcanary migration writepreview %s from %s reason=not_super_admin",
				tostring(migrationWritePreviewMode),
				player.Name
			))
			return false, "not_super_admin"
		end

		if migrationWritePreviewMode == "clear" then
			local clearedMemory = CrewMigrationPlanner.ClearMigrationWritePreview(player)
			local clearResult = CrewMigrationPlanner.ClearMigrationWritePreviewAudit(player)
			print(string.format(
				"[DevFruitDevCommands] %s cleared CrewMember migration writepreview memoryCleared=%s %s",
				player.Name,
				tostring(clearedMemory),
				summarizeCrewMigrationAuditStoreResult("writePreviewClear", clearResult)
			))
			if clearResult.Ok ~= true then
				return false,
					"CrewMember migration writepreview clear failed. "
						.. summarizeCrewMigrationAuditStoreResult("writePreviewClear", clearResult)
			end
			return true,
				"CrewMember migration writepreview cleared. "
					.. summarizeCrewMigrationAuditStoreResult("writePreviewClear", clearResult)
		end

		local flags = CrewMemberCanonicalReadGate.GetFlags()
		local safe, safetyReason = isCrewMigrationDryRunSafe(flags)
		if safe ~= true then
			warn(string.format(
				"[DevFruitDevCommands] Rejected /crewcanary migration writepreview from %s reason=%s %s",
				player.Name,
				tostring(safetyReason),
				summarizeCrewMigrationFlags(flags)
			))
			return false, tostring(safetyReason)
		end

		local validationStatus = CrewMemberCanonicalReadGate.PrintStatus(player)
		local compareReport = CrewMigrationPlanner.BuildMigrationCompareReport(player, {
			Snapshot = CrewMigrationPlanner.GetDiagnosticSnapshot(player),
			ValidationStatus = validationStatus,
		})
		CrewMigrationPlanner.PrintMigrationCompareReport(compareReport)
		local previewReport = CrewMigrationPlanner.BuildMigrationWritePreviewReport(player, {
			ValidationStatus = validationStatus,
			CompareReport = compareReport,
			Flags = flags,
		})
		CrewMigrationPlanner.PrintMigrationWritePreviewReport(previewReport)
		if previewReport.CanWritePreview ~= true then
			warn(string.format(
				"[DevFruitDevCommands] Rejected /crewcanary migration writepreview from %s reason=writepreview_no_go noGo=%s %s",
				player.Name,
				if typeof(previewReport.NoGoReasons) == "table" and #previewReport.NoGoReasons > 0
					then table.concat(previewReport.NoGoReasons, ",")
					else "none",
				summarizeCrewMigrationFlags(flags)
			))
			return false,
				"CrewMember migration writepreview blocked by no-go condition. "
					.. summarizeCrewMigrationWritePreviewReport("migrationWritePreview", previewReport, flags)
		end

		local saveResult = CrewMigrationPlanner.SaveMigrationWritePreview(player, previewReport)
		if saveResult.Ok ~= true then
			warn(string.format(
				"[DevFruitDevCommands] Failed /crewcanary migration writepreview save for %s reason=%s",
				player.Name,
				tostring(saveResult.Reason or "unknown_error")
			))
			return false,
				"CrewMember migration writepreview generated, but rollback/audit snapshot save failed. "
					.. summarizeCrewMigrationAuditStoreResult("writePreviewSave", saveResult)
		end
		CrewMigrationPlanner.StoreMigrationWritePreview(player, previewReport)
		print(string.format(
			"[DevFruitDevCommands] %s saved CrewMember migration writepreview %s %s",
			player.Name,
			summarizeCrewMigrationWritePreviewReport("migrationWritePreview", previewReport, flags),
			summarizeCrewMigrationAuditStoreResult("writePreviewSave", saveResult)
		))
		return true,
			"CrewMember migration writepreview saved. "
				.. summarizeCrewMigrationWritePreviewReport("migrationWritePreview", previewReport, flags)
	end

	if migrationWriteMode ~= nil then
		if migrationWriteMode ~= "sampled" then
			warn(string.format(
				"[DevFruitDevCommands] Invalid /crewcanary migration write argument '%s' from %s. Use write sampled",
				tostring(migrationWriteMode),
				player.Name
			))
			return false, "invalid_migration_write_argument"
		end
		if not AdminPermissions.IsSuperAdmin(player) then
			warn(string.format(
				"[DevFruitDevCommands] Rejected /crewcanary migration write sampled from %s reason=not_super_admin",
				player.Name
			))
			return false, "not_super_admin"
		end

		local flags = CrewMemberCanonicalReadGate.GetFlags()
		local safe, safetyReason = isCrewMigrationDryRunSafe(flags)
		if safe ~= true then
			warn(string.format(
				"[DevFruitDevCommands] Rejected /crewcanary migration write sampled from %s reason=%s %s",
				player.Name,
				tostring(safetyReason),
				summarizeCrewMigrationFlags(flags)
			))
			return false, tostring(safetyReason)
		end

		local validationStatus = CrewMemberCanonicalReadGate.PrintStatus(player)
		local previewReport, compareReport = CrewMigrationPlanner.BuildSampledMigrationWritePreview(player, {
			Snapshot = CrewMigrationPlanner.GetDiagnosticSnapshot(player),
			ValidationStatus = validationStatus,
			Flags = flags,
		})
		CrewMigrationPlanner.PrintMigrationCompareReport(compareReport)
		CrewMigrationPlanner.PrintMigrationWritePreviewReport(previewReport)
		if previewReport.CanWritePreview ~= true then
			warn(string.format(
				"[DevFruitDevCommands] Rejected /crewcanary migration write sampled from %s reason=writepreview_no_go noGo=%s %s",
				player.Name,
				if typeof(previewReport.NoGoReasons) == "table" and #previewReport.NoGoReasons > 0
					then table.concat(previewReport.NoGoReasons, ",")
					else "none",
				summarizeCrewMigrationFlags(flags)
			))
			return false,
				"CrewMember sampled migration write blocked by preview no-go. "
					.. summarizeCrewMigrationWritePreviewReport("migrationWritePreview", previewReport, flags)
		end

		local saveResult, loadResult = CrewMigrationPlanner.SaveAndVerifySampledMigrationRollback(player, previewReport)
		if saveResult.Ok ~= true then
			warn(string.format(
				"[DevFruitDevCommands] Rejected /crewcanary migration write sampled from %s reason=rollback_snapshot_store_failed %s",
				player.Name,
				summarizeCrewMigrationAuditStoreResult("sampledWriteRollbackSave", saveResult)
			))
			return false,
				"CrewMember sampled migration write blocked because rollback snapshot could not be stored/read. "
					.. summarizeCrewMigrationAuditStoreResult("sampledWriteRollbackSave", saveResult)
		end
		print(string.format(
			"[DevFruitDevCommands] %s verified CrewMember sampled migration rollback snapshot %s %s",
			player.Name,
			summarizeCrewMigrationAuditStoreResult("sampledWriteRollbackSave", saveResult),
			summarizeCrewMigrationAuditStoreResult("sampledWriteRollbackLoad", loadResult)
		))

		local openOk, openReason, openState = CrewMemberCanonicalReadGate.SetProfileMigrationWriteSampledSessionOverride(true)
		if openOk ~= true then
			warn(string.format(
				"[DevFruitDevCommands] Rejected /crewcanary migration write sampled from %s reason=%s",
				player.Name,
				tostring(openReason or "write_window_open_failed")
			))
			return false, tostring(openReason or "write_window_open_failed")
		end

		local writeFlags = openState and openState.Flags or CrewMemberCanonicalReadGate.GetFlags()
		local ok, writeResult = pcall(function()
			return CrewMigrationPlanner.ExecuteSampledMigrationWrite(player, previewReport, {
				ValidationStatus = validationStatus,
				Flags = writeFlags,
			})
		end)
		local closeOk, closeReason, closeState = CrewMemberCanonicalReadGate.SetProfileMigrationDryRunSessionOverride(true)
		local closedFlags = closeState and closeState.Flags or CrewMemberCanonicalReadGate.GetFlags()
		if closeOk ~= true then
			warn(string.format(
				"[DevFruitDevCommands] Failed to close CrewMember sampled migration write window for %s reason=%s",
				player.Name,
				tostring(closeReason or "unknown_error")
			))
		end
		if ok ~= true then
			warn(string.format(
				"[DevFruitDevCommands] Failed /crewcanary migration write sampled for %s error=%s %s",
				player.Name,
				tostring(writeResult),
				summarizeCrewMigrationFlags(closedFlags)
			))
			return false, "sampled_write_error:" .. tostring(writeResult)
		end

		CrewMigrationPlanner.PrintSampledMigrationWriteReport(writeResult)
		if writeResult.Passed ~= true then
			return false,
				"CrewMember sampled migration write failed validation. "
					.. summarizeCrewMigrationSampledWriteResult(writeResult, closedFlags)
		end
		return true,
			"CrewMember sampled migration write passed. "
				.. summarizeCrewMigrationSampledWriteResult(writeResult, closedFlags)
	end

	if migrationRollbackMode ~= nil then
		if migrationRollbackMode ~= "status" and migrationRollbackMode ~= "latest" then
			warn(string.format(
				"[DevFruitDevCommands] Invalid /crewcanary migration rollback argument '%s' from %s. Use rollback status or rollback latest",
				tostring(migrationRollbackMode),
				player.Name
			))
			return false, "invalid_migration_rollback_argument"
		end

		if migrationRollbackMode == "status" then
			local status = CrewMigrationPlanner.LoadMigrationRollbackStatus(player)
			print(string.format(
				"[DevFruitDevCommands] %s requested CrewMember migration rollback status %s",
				player.Name,
				summarizeCrewMigrationRollbackStatus(status)
			))
			if status.Ok ~= true then
				return false,
					"CrewMember migration rollback status could not read audit DataStore. "
						.. summarizeCrewMigrationRollbackStatus(status)
			end
			return true,
				"CrewMember migration rollback status printed to server output. "
					.. summarizeCrewMigrationRollbackStatus(status)
		end

		if not AdminPermissions.IsSuperAdmin(player) then
			warn(string.format(
				"[DevFruitDevCommands] Rejected /crewcanary migration rollback latest from %s reason=not_super_admin",
				player.Name
			))
			return false, "not_super_admin"
		end

		local flags = CrewMemberCanonicalReadGate.GetFlags()
		local safe, safetyReason = isCrewMigrationDryRunSafe(flags)
		if safe ~= true then
			warn(string.format(
				"[DevFruitDevCommands] Rejected /crewcanary migration rollback latest from %s reason=%s %s",
				player.Name,
				tostring(safetyReason),
				summarizeCrewMigrationFlags(flags)
			))
			return false, tostring(safetyReason)
		end

		local validationStatus = CrewMemberCanonicalReadGate.PrintStatus(player)
		local rollbackResult = CrewMigrationPlanner.ExecuteMigrationRollbackLatest(player, {
			ValidationStatus = validationStatus,
			Flags = flags,
		})
		CrewMigrationPlanner.PrintMigrationRollbackReport(rollbackResult)
		local closeDryRun = rollbackResult
			and rollbackResult.LoadResult
			and rollbackResult.LoadResult.RollbackKind == "quick_slots_write_authority"
		local closeOk, closeReason, closeState = CrewMemberCanonicalReadGate.SetProfileMigrationDryRunSessionOverride(not closeDryRun)
		local closedFlags = closeState and closeState.Flags or CrewMemberCanonicalReadGate.GetFlags()
		if closeOk ~= true then
			warn(string.format(
				"[DevFruitDevCommands] Failed to set CrewMember migration dry-run state after rollback for %s reason=%s",
				player.Name,
				tostring(closeReason or "unknown_error")
			))
		end
		if rollbackResult.Passed ~= true then
			return false,
				"CrewMember migration rollback latest failed. "
					.. summarizeCrewMigrationRollbackResult(rollbackResult, closedFlags)
		end
		return true,
			"CrewMember migration rollback latest passed. "
				.. summarizeCrewMigrationRollbackResult(rollbackResult, closedFlags)
	end

	if migrationMode ~= nil
		and migrationMode ~= "status"
		and migrationMode ~= "snapshot"
		and migrationMode ~= "dryrun"
		and migrationMode ~= "compare"
		and migrationMode ~= "review"
		and migrationMode ~= "cleanupcompat"
		and migrationMode ~= "saveload"
		and migrationAuditMode == nil
		and migrationWritePreviewMode == nil
		and migrationWriteMode == nil
		and migrationRollbackMode == nil
	then
		warn(string.format(
			"[DevFruitDevCommands] Invalid /crewcanary migration argument '%s' from %s. Use status, on, off, snapshot, dryrun, compare, review, cleanupcompat, saveload, clear, audit status, audit before, audit after, audit clear, writepreview, writepreview status, writepreview clear, writepreview export, write sampled, rollback status, or rollback latest",
			tostring(migrationMode),
			player.Name
		))
		return false, "invalid_migration_argument"
	end

	if migrationMode == "status" then
		local flags = CrewMemberCanonicalReadGate.GetFlags()
		CrewMemberCanonicalReadGate.PrintStatus(player)
		return true,
			"CrewMember migration diagnostics status printed to server output. "
				.. summarizeCrewMigrationStatus(flags, CrewMigrationPlanner.GetDiagnosticSnapshot(player))
	end

	if migrationMode == "cleanupcompat" then
		if not AdminPermissions.IsSuperAdmin(player) then
			warn(string.format(
				"[DevFruitDevCommands] Rejected /crewcanary migration cleanupcompat from %s reason=not_super_admin",
				player.Name
			))
			return false, "not_super_admin"
		end

		local validationStatus = CrewMemberCanonicalReadGate.PrintStatus(player)
		local plan = CrewMigrationPlanner.BuildCompatibilityCleanupPlan(player)
		CrewMigrationPlanner.PrintCompatibilityCleanupPlan(plan)
		local result = CrewMigrationPlanner.ExecuteCompatibilityCleanup(player, {
			ValidationStatus = validationStatus,
		})
		CrewMigrationPlanner.PrintCompatibilityCleanupResult(result)
		if result.PostReview then
			CrewMigrationPlanner.PrintCompatibilityReviewReport(result.PostReview)
		end
		if result.PostCompare then
			CrewMigrationPlanner.PrintMigrationCompareReport(result.PostCompare)
		end
		if result.Passed ~= true then
			return false,
				"CrewMember compatibility cleanup failed validation. "
					.. tostring(result.Summary or "compatibilityCleanup unavailable")
		end
		return true,
			"CrewMember compatibility cleanup completed. "
				.. tostring(result.Summary or "compatibilityCleanup unavailable")
	end

	if migrationMode ~= nil then
		local flags = CrewMemberCanonicalReadGate.GetFlags()
		local safe, safetyReason = isCrewMigrationDryRunSafe(flags)
		if safe ~= true then
			warn(string.format(
				"[DevFruitDevCommands] Rejected /crewcanary migration %s from %s reason=%s %s",
				tostring(migrationMode),
				player.Name,
				tostring(safetyReason),
				summarizeCrewMigrationFlags(flags)
			))
			return false, tostring(safetyReason)
		end

		if migrationMode == "saveload" and flags.CrewMemberCanarySaveLoadValidationEnabled ~= true then
			warn(string.format(
				"[DevFruitDevCommands] Rejected /crewcanary migration saveload from %s reason=saveload_validation_disabled",
				player.Name
			))
			return false, "saveload_validation_disabled"
		end

		local validationStatus = CrewMemberCanonicalReadGate.PrintStatus(player)
		local options = {
			ValidationStatus = validationStatus,
		}

		if migrationMode == "snapshot" then
			local snapshot = CrewMigrationPlanner.BuildMigrationSnapshot(player, options)
			CrewMigrationPlanner.StoreDiagnosticSnapshot(player, snapshot)
			CrewMigrationPlanner.PrintMigrationSnapshotReport(snapshot)
			return true,
				"CrewMember migration snapshot captured in memory. "
					.. summarizeCrewMigrationSnapshot(snapshot, flags)
		end

		if migrationMode == "dryrun" then
			local report = CrewMigrationPlanner.BuildMigrationDryRunReport(player, options)
			CrewMigrationPlanner.PrintMigrationDryRunReport(report)
			return true,
				"CrewMember migration dry-run printed to server output. "
					.. summarizeCrewMigrationReport("migrationDryRun", report, flags)
		end

		if migrationMode == "compare" then
			local report = CrewMigrationPlanner.BuildMigrationCompareReport(player, {
				Snapshot = CrewMigrationPlanner.GetDiagnosticSnapshot(player),
				ValidationStatus = validationStatus,
			})
			CrewMigrationPlanner.PrintMigrationCompareReport(report)
			return true,
				"CrewMember migration compare printed to server output. "
					.. summarizeCrewMigrationReport("migrationCompare", report, flags)
		end

		if migrationMode == "review" then
			local report = CrewMigrationPlanner.BuildCompatibilityReviewReport(player)
			CrewMigrationPlanner.PrintCompatibilityReviewReport(report)
			return true,
				"CrewMember migration compatibility review printed to server output. "
					.. summarizeCrewMigrationCompatibilityReview(report, flags)
		end

		if migrationMode == "saveload" then
			local report = CrewMigrationPlanner.BuildMigrationSaveLoadReport(
				player,
				CrewMigrationPlanner.GetDiagnosticSnapshot(player),
				options
			)
			CrewMigrationPlanner.PrintMigrationSaveLoadReport(report)
			return true,
				"CrewMember migration save/load validation printed to server output. "
					.. summarizeCrewMigrationSaveLoadReport(report, flags)
		end
	end

	if readAuthorityMode == "on" or readAuthorityMode == "enable" or readAuthorityMode == "true" then
		if not AdminPermissions.IsSuperAdmin(player) then
			warn(string.format(
				"[DevFruitDevCommands] Rejected /crewcanary readauthority on from %s reason=not_super_admin",
				player.Name
			))
			return false, "not_super_admin"
		end

		local ok, reason, state = CrewMemberCanonicalReadGate.SetCombinedReadAuthoritySessionOverride(true)
		if ok ~= true then
			warn(string.format(
				"[DevFruitDevCommands] Failed /crewcanary readauthority on for %s reason=%s",
				player.Name,
				tostring(reason or "unknown_error")
			))
			return false, tostring(reason or "unknown_error")
		end

		local flags = state and state.Flags or CrewMemberCanonicalReadGate.GetFlags()
		print(string.format(
			"[DevFruitDevCommands] %s enabled CrewMember combined read-authority canaries readAuthority=%s standStatusReadAuthority=%s incomeStatusReadAuthority=%s foodStatusReadAuthority=%s writeAuthority=%s profileMigrationDryRun=%s profileMigrationWrite=%s gameplayReads=%s canonicalRead=%s",
			player.Name,
			tostring(flags.CrewMemberCanaryReadAuthorityEnabled),
			tostring(flags.CrewMemberCanaryStandStatusReadAuthorityEnabled),
			tostring(flags.CrewMemberCanaryIncomeStatusReadAuthorityEnabled),
			tostring(flags.CrewMemberCanaryFoodStatusReadAuthorityEnabled),
			tostring(flags.CrewMemberCanaryWriteAuthorityEnabled),
			tostring(flags.CrewMemberCanaryProfileMigrationDryRunEnabled),
			tostring(flags.CrewMemberCanaryProfileMigrationWriteEnabled),
			tostring(flags.CrewMemberCanaryGameplayReadsEnabled),
			tostring(flags.CrewMemberCanonicalReadEnabled)
		))
		CrewMemberCanonicalReadGate.PrintStatus(player)
		local standRows = CrewMemberCanonicalReadGate.PrintStandStatusReadAuthorityStatus(
			player,
			getCrewCanaryStandReadAuthorityStandNames(player),
			{
				Player = player,
			}
		)
		local incomeRows = CrewMemberCanonicalReadGate.PrintIncomeStatusReadAuthorityStatus(
			player,
			getCrewCanaryStandReadAuthorityStandNames(player),
			{
				Player = player,
			}
		)
		local foodRows = CrewMemberCanonicalReadGate.PrintFoodStatusReadAuthorityStatus(
			player,
			getCrewCanaryFoodReadAuthorityContexts(player),
			{
				Player = player,
			}
		)
		local detail = "CrewMember combined read-authority canaries enabled for this staging server session. "
			.. summarizeCrewCanaryStandReadAuthorityRows(standRows, flags)
			.. " "
			.. summarizeCrewCanaryIncomeReadAuthorityRows(incomeRows, flags)
			.. " "
			.. summarizeCrewCanaryFoodReadAuthorityRows(foodRows, flags)
		return true, detail
	end

	if readAuthorityMode == "off" or readAuthorityMode == "disable" or readAuthorityMode == "false" then
		if not AdminPermissions.IsSuperAdmin(player) then
			warn(string.format(
				"[DevFruitDevCommands] Rejected /crewcanary readauthority off from %s reason=not_super_admin",
				player.Name
			))
			return false, "not_super_admin"
		end

		local ok, reason, state = CrewMemberCanonicalReadGate.SetCombinedReadAuthoritySessionOverride(false)
		if ok ~= true then
			warn(string.format(
				"[DevFruitDevCommands] Failed /crewcanary readauthority off for %s reason=%s",
				player.Name,
				tostring(reason or "unknown_error")
			))
			return false, tostring(reason or "unknown_error")
		end

		local flags = state and state.Flags or CrewMemberCanonicalReadGate.GetFlags()
		print(string.format(
			"[DevFruitDevCommands] %s disabled CrewMember combined read-authority canaries readAuthority=%s standStatusReadAuthority=%s incomeStatusReadAuthority=%s foodStatusReadAuthority=%s writeAuthority=%s profileMigrationDryRun=%s profileMigrationWrite=%s gameplayReads=%s canonicalRead=%s",
			player.Name,
			tostring(flags.CrewMemberCanaryReadAuthorityEnabled),
			tostring(flags.CrewMemberCanaryStandStatusReadAuthorityEnabled),
			tostring(flags.CrewMemberCanaryIncomeStatusReadAuthorityEnabled),
			tostring(flags.CrewMemberCanaryFoodStatusReadAuthorityEnabled),
			tostring(flags.CrewMemberCanaryWriteAuthorityEnabled),
			tostring(flags.CrewMemberCanaryProfileMigrationDryRunEnabled),
			tostring(flags.CrewMemberCanaryProfileMigrationWriteEnabled),
			tostring(flags.CrewMemberCanaryGameplayReadsEnabled),
			tostring(flags.CrewMemberCanonicalReadEnabled)
		))
		CrewMemberCanonicalReadGate.PrintStatus(player)
		return true, string.format(
			"CrewMember combined read-authority canaries disabled for this server session. readAuthority=%s standStatusReadAuthority=%s incomeStatusReadAuthority=%s foodStatusReadAuthority=%s writeAuthority=%s profileMigrationDryRun=%s profileMigrationWrite=%s gameplayReads=%s canonicalRead=%s",
			tostring(flags.CrewMemberCanaryReadAuthorityEnabled),
			tostring(flags.CrewMemberCanaryStandStatusReadAuthorityEnabled),
			tostring(flags.CrewMemberCanaryIncomeStatusReadAuthorityEnabled),
			tostring(flags.CrewMemberCanaryFoodStatusReadAuthorityEnabled),
			tostring(flags.CrewMemberCanaryWriteAuthorityEnabled),
			tostring(flags.CrewMemberCanaryProfileMigrationDryRunEnabled),
			tostring(flags.CrewMemberCanaryProfileMigrationWriteEnabled),
			tostring(flags.CrewMemberCanaryGameplayReadsEnabled),
			tostring(flags.CrewMemberCanonicalReadEnabled)
		)
	end

	if standReadAuthorityMode == "on" or standReadAuthorityMode == "enable" or standReadAuthorityMode == "true" then
		if not AdminPermissions.IsSuperAdmin(player) then
			warn(string.format(
				"[DevFruitDevCommands] Rejected /crewcanary readauthority standstatus on from %s reason=not_super_admin",
				player.Name
			))
			return false, "not_super_admin"
		end

		local ok, reason, state = CrewMemberCanonicalReadGate.SetStandStatusReadAuthoritySessionOverride(true)
		if ok ~= true then
			warn(string.format(
				"[DevFruitDevCommands] Failed /crewcanary readauthority standstatus on for %s reason=%s",
				player.Name,
				tostring(reason or "unknown_error")
			))
			return false, tostring(reason or "unknown_error")
		end

		local flags = state and state.Flags or CrewMemberCanonicalReadGate.GetFlags()
		print(string.format(
			"[DevFruitDevCommands] %s enabled CrewMember stand status read-authority canary readAuthority=%s standStatusReadAuthority=%s writeAuthority=%s profileMigrationDryRun=%s profileMigrationWrite=%s gameplayReads=%s canonicalRead=%s",
			player.Name,
			tostring(flags.CrewMemberCanaryReadAuthorityEnabled),
			tostring(flags.CrewMemberCanaryStandStatusReadAuthorityEnabled),
			tostring(flags.CrewMemberCanaryWriteAuthorityEnabled),
			tostring(flags.CrewMemberCanaryProfileMigrationDryRunEnabled),
			tostring(flags.CrewMemberCanaryProfileMigrationWriteEnabled),
			tostring(flags.CrewMemberCanaryGameplayReadsEnabled),
			tostring(flags.CrewMemberCanonicalReadEnabled)
		))
		CrewMemberCanonicalReadGate.PrintStatus(player)
		local rows = CrewMemberCanonicalReadGate.PrintStandStatusReadAuthorityStatus(
			player,
			getCrewCanaryStandReadAuthorityStandNames(player),
			{
				Player = player,
			}
		)
		local detail = "CrewMember stand status read-authority canary enabled for this staging server session. "
			.. summarizeCrewCanaryStandReadAuthorityRows(rows, flags)
		return true, detail
	end

	if standReadAuthorityMode == "off" or standReadAuthorityMode == "disable" or standReadAuthorityMode == "false" then
		if not AdminPermissions.IsSuperAdmin(player) then
			warn(string.format(
				"[DevFruitDevCommands] Rejected /crewcanary readauthority standstatus off from %s reason=not_super_admin",
				player.Name
			))
			return false, "not_super_admin"
		end

		local ok, reason, state = CrewMemberCanonicalReadGate.SetStandStatusReadAuthoritySessionOverride(false)
		if ok ~= true then
			warn(string.format(
				"[DevFruitDevCommands] Failed /crewcanary readauthority standstatus off for %s reason=%s",
				player.Name,
				tostring(reason or "unknown_error")
			))
			return false, tostring(reason or "unknown_error")
		end

		local flags = state and state.Flags or CrewMemberCanonicalReadGate.GetFlags()
		print(string.format(
			"[DevFruitDevCommands] %s disabled CrewMember stand status read-authority canary readAuthority=%s standStatusReadAuthority=%s writeAuthority=%s profileMigrationDryRun=%s profileMigrationWrite=%s gameplayReads=%s canonicalRead=%s",
			player.Name,
			tostring(flags.CrewMemberCanaryReadAuthorityEnabled),
			tostring(flags.CrewMemberCanaryStandStatusReadAuthorityEnabled),
			tostring(flags.CrewMemberCanaryWriteAuthorityEnabled),
			tostring(flags.CrewMemberCanaryProfileMigrationDryRunEnabled),
			tostring(flags.CrewMemberCanaryProfileMigrationWriteEnabled),
			tostring(flags.CrewMemberCanaryGameplayReadsEnabled),
			tostring(flags.CrewMemberCanonicalReadEnabled)
		))
		CrewMemberCanonicalReadGate.PrintStatus(player)
		return true, string.format(
			"CrewMember stand status read-authority canary disabled for this server session. readAuthority=%s standStatusReadAuthority=%s writeAuthority=%s profileMigrationDryRun=%s profileMigrationWrite=%s gameplayReads=%s canonicalRead=%s",
			tostring(flags.CrewMemberCanaryReadAuthorityEnabled),
			tostring(flags.CrewMemberCanaryStandStatusReadAuthorityEnabled),
			tostring(flags.CrewMemberCanaryWriteAuthorityEnabled),
			tostring(flags.CrewMemberCanaryProfileMigrationDryRunEnabled),
			tostring(flags.CrewMemberCanaryProfileMigrationWriteEnabled),
			tostring(flags.CrewMemberCanaryGameplayReadsEnabled),
			tostring(flags.CrewMemberCanonicalReadEnabled)
		)
	end

	if standReadAuthorityMode ~= nil
		and standReadAuthorityMode ~= "status"
		and standReadAuthorityMode ~= "stale"
		and standReadAuthorityMode ~= "fallback"
	then
		warn(string.format(
			"[DevFruitDevCommands] Invalid /crewcanary readauthority standstatus argument '%s' from %s. Use on, off, or stale",
			tostring(standReadAuthorityMode),
			player.Name
		))
		return false, "invalid_readauthority_standstatus_argument"
	end

	if incomeReadAuthorityMode == "on" or incomeReadAuthorityMode == "enable" or incomeReadAuthorityMode == "true" then
		if not AdminPermissions.IsSuperAdmin(player) then
			warn(string.format(
				"[DevFruitDevCommands] Rejected /crewcanary readauthority incomestatus on from %s reason=not_super_admin",
				player.Name
			))
			return false, "not_super_admin"
		end

		local ok, reason, state = CrewMemberCanonicalReadGate.SetIncomeStatusReadAuthoritySessionOverride(true)
		if ok ~= true then
			warn(string.format(
				"[DevFruitDevCommands] Failed /crewcanary readauthority incomestatus on for %s reason=%s",
				player.Name,
				tostring(reason or "unknown_error")
			))
			return false, tostring(reason or "unknown_error")
		end

		local flags = state and state.Flags or CrewMemberCanonicalReadGate.GetFlags()
		print(string.format(
			"[DevFruitDevCommands] %s enabled CrewMember income status read-authority canary readAuthority=%s incomeStatusReadAuthority=%s standStatusReadAuthority=%s writeAuthority=%s profileMigrationDryRun=%s profileMigrationWrite=%s gameplayReads=%s canonicalRead=%s",
			player.Name,
			tostring(flags.CrewMemberCanaryReadAuthorityEnabled),
			tostring(flags.CrewMemberCanaryIncomeStatusReadAuthorityEnabled),
			tostring(flags.CrewMemberCanaryStandStatusReadAuthorityEnabled),
			tostring(flags.CrewMemberCanaryWriteAuthorityEnabled),
			tostring(flags.CrewMemberCanaryProfileMigrationDryRunEnabled),
			tostring(flags.CrewMemberCanaryProfileMigrationWriteEnabled),
			tostring(flags.CrewMemberCanaryGameplayReadsEnabled),
			tostring(flags.CrewMemberCanonicalReadEnabled)
		))
		CrewMemberCanonicalReadGate.PrintStatus(player)
		local rows = CrewMemberCanonicalReadGate.PrintIncomeStatusReadAuthorityStatus(
			player,
			getCrewCanaryStandReadAuthorityStandNames(player),
			{
				Player = player,
			}
		)
		local detail = "CrewMember income status read-authority canary enabled for this staging server session. "
			.. summarizeCrewCanaryIncomeReadAuthorityRows(rows, flags)
		return true, detail
	end

	if incomeReadAuthorityMode == "off" or incomeReadAuthorityMode == "disable" or incomeReadAuthorityMode == "false" then
		if not AdminPermissions.IsSuperAdmin(player) then
			warn(string.format(
				"[DevFruitDevCommands] Rejected /crewcanary readauthority incomestatus off from %s reason=not_super_admin",
				player.Name
			))
			return false, "not_super_admin"
		end

		local ok, reason, state = CrewMemberCanonicalReadGate.SetIncomeStatusReadAuthoritySessionOverride(false)
		if ok ~= true then
			warn(string.format(
				"[DevFruitDevCommands] Failed /crewcanary readauthority incomestatus off for %s reason=%s",
				player.Name,
				tostring(reason or "unknown_error")
			))
			return false, tostring(reason or "unknown_error")
		end

		local flags = state and state.Flags or CrewMemberCanonicalReadGate.GetFlags()
		print(string.format(
			"[DevFruitDevCommands] %s disabled CrewMember income status read-authority canary readAuthority=%s incomeStatusReadAuthority=%s standStatusReadAuthority=%s writeAuthority=%s profileMigrationDryRun=%s profileMigrationWrite=%s gameplayReads=%s canonicalRead=%s",
			player.Name,
			tostring(flags.CrewMemberCanaryReadAuthorityEnabled),
			tostring(flags.CrewMemberCanaryIncomeStatusReadAuthorityEnabled),
			tostring(flags.CrewMemberCanaryStandStatusReadAuthorityEnabled),
			tostring(flags.CrewMemberCanaryWriteAuthorityEnabled),
			tostring(flags.CrewMemberCanaryProfileMigrationDryRunEnabled),
			tostring(flags.CrewMemberCanaryProfileMigrationWriteEnabled),
			tostring(flags.CrewMemberCanaryGameplayReadsEnabled),
			tostring(flags.CrewMemberCanonicalReadEnabled)
		))
		CrewMemberCanonicalReadGate.PrintStatus(player)
		return true, string.format(
			"CrewMember income status read-authority canary disabled for this server session. readAuthority=%s incomeStatusReadAuthority=%s standStatusReadAuthority=%s writeAuthority=%s profileMigrationDryRun=%s profileMigrationWrite=%s gameplayReads=%s canonicalRead=%s",
			tostring(flags.CrewMemberCanaryReadAuthorityEnabled),
			tostring(flags.CrewMemberCanaryIncomeStatusReadAuthorityEnabled),
			tostring(flags.CrewMemberCanaryStandStatusReadAuthorityEnabled),
			tostring(flags.CrewMemberCanaryWriteAuthorityEnabled),
			tostring(flags.CrewMemberCanaryProfileMigrationDryRunEnabled),
			tostring(flags.CrewMemberCanaryProfileMigrationWriteEnabled),
			tostring(flags.CrewMemberCanaryGameplayReadsEnabled),
			tostring(flags.CrewMemberCanonicalReadEnabled)
		)
	end

	if incomeReadAuthorityMode ~= nil
		and incomeReadAuthorityMode ~= "status"
		and incomeReadAuthorityMode ~= "stale"
		and incomeReadAuthorityMode ~= "fallback"
	then
		warn(string.format(
			"[DevFruitDevCommands] Invalid /crewcanary readauthority incomestatus argument '%s' from %s. Use on, off, or stale",
			tostring(incomeReadAuthorityMode),
			player.Name
		))
		return false, "invalid_readauthority_incomestatus_argument"
	end

	if foodReadAuthorityMode == "on" or foodReadAuthorityMode == "enable" or foodReadAuthorityMode == "true" then
		if not AdminPermissions.IsSuperAdmin(player) then
			warn(string.format(
				"[DevFruitDevCommands] Rejected /crewcanary readauthority foodstatus on from %s reason=not_super_admin",
				player.Name
			))
			return false, "not_super_admin"
		end

		local ok, reason, state = CrewMemberCanonicalReadGate.SetFoodStatusReadAuthoritySessionOverride(true)
		if ok ~= true then
			warn(string.format(
				"[DevFruitDevCommands] Failed /crewcanary readauthority foodstatus on for %s reason=%s",
				player.Name,
				tostring(reason or "unknown_error")
			))
			return false, tostring(reason or "unknown_error")
		end

		local flags = state and state.Flags or CrewMemberCanonicalReadGate.GetFlags()
		print(string.format(
			"[DevFruitDevCommands] %s enabled CrewMember food status read-authority canary readAuthority=%s foodStatusReadAuthority=%s standStatusReadAuthority=%s incomeStatusReadAuthority=%s writeAuthority=%s profileMigrationDryRun=%s profileMigrationWrite=%s gameplayReads=%s canonicalRead=%s",
			player.Name,
			tostring(flags.CrewMemberCanaryReadAuthorityEnabled),
			tostring(flags.CrewMemberCanaryFoodStatusReadAuthorityEnabled),
			tostring(flags.CrewMemberCanaryStandStatusReadAuthorityEnabled),
			tostring(flags.CrewMemberCanaryIncomeStatusReadAuthorityEnabled),
			tostring(flags.CrewMemberCanaryWriteAuthorityEnabled),
			tostring(flags.CrewMemberCanaryProfileMigrationDryRunEnabled),
			tostring(flags.CrewMemberCanaryProfileMigrationWriteEnabled),
			tostring(flags.CrewMemberCanaryGameplayReadsEnabled),
			tostring(flags.CrewMemberCanonicalReadEnabled)
		))
		CrewMemberCanonicalReadGate.PrintStatus(player)
		local rows = CrewMemberCanonicalReadGate.PrintFoodStatusReadAuthorityStatus(
			player,
			getCrewCanaryFoodReadAuthorityContexts(player),
			{
				Player = player,
			}
		)
		local detail = "CrewMember food status read-authority canary enabled for this staging server session. "
			.. summarizeCrewCanaryFoodReadAuthorityRows(rows, flags)
		return true, detail
	end

	if foodReadAuthorityMode == "off" or foodReadAuthorityMode == "disable" or foodReadAuthorityMode == "false" then
		if not AdminPermissions.IsSuperAdmin(player) then
			warn(string.format(
				"[DevFruitDevCommands] Rejected /crewcanary readauthority foodstatus off from %s reason=not_super_admin",
				player.Name
			))
			return false, "not_super_admin"
		end

		local ok, reason, state = CrewMemberCanonicalReadGate.SetFoodStatusReadAuthoritySessionOverride(false)
		if ok ~= true then
			warn(string.format(
				"[DevFruitDevCommands] Failed /crewcanary readauthority foodstatus off for %s reason=%s",
				player.Name,
				tostring(reason or "unknown_error")
			))
			return false, tostring(reason or "unknown_error")
		end

		local flags = state and state.Flags or CrewMemberCanonicalReadGate.GetFlags()
		print(string.format(
			"[DevFruitDevCommands] %s disabled CrewMember food status read-authority canary readAuthority=%s foodStatusReadAuthority=%s standStatusReadAuthority=%s incomeStatusReadAuthority=%s writeAuthority=%s profileMigrationDryRun=%s profileMigrationWrite=%s gameplayReads=%s canonicalRead=%s",
			player.Name,
			tostring(flags.CrewMemberCanaryReadAuthorityEnabled),
			tostring(flags.CrewMemberCanaryFoodStatusReadAuthorityEnabled),
			tostring(flags.CrewMemberCanaryStandStatusReadAuthorityEnabled),
			tostring(flags.CrewMemberCanaryIncomeStatusReadAuthorityEnabled),
			tostring(flags.CrewMemberCanaryWriteAuthorityEnabled),
			tostring(flags.CrewMemberCanaryProfileMigrationDryRunEnabled),
			tostring(flags.CrewMemberCanaryProfileMigrationWriteEnabled),
			tostring(flags.CrewMemberCanaryGameplayReadsEnabled),
			tostring(flags.CrewMemberCanonicalReadEnabled)
		))
		CrewMemberCanonicalReadGate.PrintStatus(player)
		return true, string.format(
			"CrewMember food status read-authority canary disabled for this server session. readAuthority=%s foodStatusReadAuthority=%s standStatusReadAuthority=%s incomeStatusReadAuthority=%s writeAuthority=%s profileMigrationDryRun=%s profileMigrationWrite=%s gameplayReads=%s canonicalRead=%s",
			tostring(flags.CrewMemberCanaryReadAuthorityEnabled),
			tostring(flags.CrewMemberCanaryFoodStatusReadAuthorityEnabled),
			tostring(flags.CrewMemberCanaryStandStatusReadAuthorityEnabled),
			tostring(flags.CrewMemberCanaryIncomeStatusReadAuthorityEnabled),
			tostring(flags.CrewMemberCanaryWriteAuthorityEnabled),
			tostring(flags.CrewMemberCanaryProfileMigrationDryRunEnabled),
			tostring(flags.CrewMemberCanaryProfileMigrationWriteEnabled),
			tostring(flags.CrewMemberCanaryGameplayReadsEnabled),
			tostring(flags.CrewMemberCanonicalReadEnabled)
		)
	end

	if foodReadAuthorityMode ~= nil
		and foodReadAuthorityMode ~= "status"
		and foodReadAuthorityMode ~= "stale"
		and foodReadAuthorityMode ~= "fallback"
	then
		warn(string.format(
			"[DevFruitDevCommands] Invalid /crewcanary readauthority foodstatus argument '%s' from %s. Use on, off, or stale",
			tostring(foodReadAuthorityMode),
			player.Name
		))
		return false, "invalid_readauthority_foodstatus_argument"
	end

	if readAuthorityMode ~= nil
		and standReadAuthorityMode == nil
		and incomeReadAuthorityMode == nil
		and foodReadAuthorityMode == nil
	then
		warn(string.format(
			"[DevFruitDevCommands] Invalid /crewcanary readauthority argument '%s' from %s. Use on, off, standstatus, incomestatus, or foodstatus on, off, or stale",
			tostring(readAuthorityMode),
			player.Name
		))
		return false, "invalid_readauthority_argument"
	end

	if gameplayHelpersMode == "on" or gameplayHelpersMode == "enable" or gameplayHelpersMode == "true" then
		if not AdminPermissions.IsSuperAdmin(player) then
			warn(string.format(
				"[DevFruitDevCommands] Rejected /crewcanary gameplayhelpers on from %s reason=not_super_admin",
				player.Name
			))
			return false, "not_super_admin"
		end

		local ok, reason, state = CrewMemberCanonicalReadGate.SetAllGameplayHelperReadSessionOverride(true)
		if ok ~= true then
			warn(string.format(
				"[DevFruitDevCommands] Failed /crewcanary gameplayhelpers on for %s reason=%s",
				player.Name,
				tostring(reason or "unknown_error")
			))
			return false, tostring(reason or "unknown_error")
		end

		local flags = state and state.Flags or CrewMemberCanonicalReadGate.GetFlags()
		print(string.format(
			"[DevFruitDevCommands] %s enabled all CrewMember gameplay helper read session overrides helperReads=%s standStatusHelperRead=%s incomeStatusHelperRead=%s incomeToastHelperRead=%s foodStatusHelperRead=%s gameplayReads=%s canonicalRead=%s",
			player.Name,
			tostring(flags.CrewMemberCanaryGameplayHelperReadsEnabled),
			tostring(flags.CrewMemberCanaryStandStatusHelperReadEnabled),
			tostring(flags.CrewMemberCanaryIncomeStatusHelperReadEnabled),
			tostring(flags.CrewMemberCanaryIncomeToastHelperReadEnabled),
			tostring(flags.CrewMemberCanaryFoodStatusHelperReadEnabled),
			tostring(flags.CrewMemberCanaryGameplayReadsEnabled),
			tostring(flags.CrewMemberCanonicalReadEnabled)
		))
		CrewMemberCanonicalReadGate.PrintStatus(player)
		return true, string.format(
			"CrewMember gameplay helper reads enabled for this staging server session. helperReads=%s standStatusHelperRead=%s incomeStatusHelperRead=%s incomeToastHelperRead=%s foodStatusHelperRead=%s gameplayReads=%s canonicalRead=%s",
			tostring(flags.CrewMemberCanaryGameplayHelperReadsEnabled),
			tostring(flags.CrewMemberCanaryStandStatusHelperReadEnabled),
			tostring(flags.CrewMemberCanaryIncomeStatusHelperReadEnabled),
			tostring(flags.CrewMemberCanaryIncomeToastHelperReadEnabled),
			tostring(flags.CrewMemberCanaryFoodStatusHelperReadEnabled),
			tostring(flags.CrewMemberCanaryGameplayReadsEnabled),
			tostring(flags.CrewMemberCanonicalReadEnabled)
		)
	end

	if gameplayHelpersMode == "off" or gameplayHelpersMode == "disable" or gameplayHelpersMode == "false" then
		if not AdminPermissions.IsSuperAdmin(player) then
			warn(string.format(
				"[DevFruitDevCommands] Rejected /crewcanary gameplayhelpers off from %s reason=not_super_admin",
				player.Name
			))
			return false, "not_super_admin"
		end

		local ok, reason, state = CrewMemberCanonicalReadGate.SetAllGameplayHelperReadSessionOverride(false)
		if ok ~= true then
			warn(string.format(
				"[DevFruitDevCommands] Failed /crewcanary gameplayhelpers off for %s reason=%s",
				player.Name,
				tostring(reason or "unknown_error")
			))
			return false, tostring(reason or "unknown_error")
		end

		local flags = state and state.Flags or CrewMemberCanonicalReadGate.GetFlags()
		print(string.format(
			"[DevFruitDevCommands] %s disabled all CrewMember gameplay helper read session overrides helperReads=%s standStatusHelperRead=%s incomeStatusHelperRead=%s incomeToastHelperRead=%s foodStatusHelperRead=%s gameplayReads=%s canonicalRead=%s",
			player.Name,
			tostring(flags.CrewMemberCanaryGameplayHelperReadsEnabled),
			tostring(flags.CrewMemberCanaryStandStatusHelperReadEnabled),
			tostring(flags.CrewMemberCanaryIncomeStatusHelperReadEnabled),
			tostring(flags.CrewMemberCanaryIncomeToastHelperReadEnabled),
			tostring(flags.CrewMemberCanaryFoodStatusHelperReadEnabled),
			tostring(flags.CrewMemberCanaryGameplayReadsEnabled),
			tostring(flags.CrewMemberCanonicalReadEnabled)
		))
		CrewMemberCanonicalReadGate.PrintStatus(player)
		return true, string.format(
			"CrewMember gameplay helper reads disabled for this server session. helperReads=%s standStatusHelperRead=%s incomeStatusHelperRead=%s incomeToastHelperRead=%s foodStatusHelperRead=%s gameplayReads=%s canonicalRead=%s",
			tostring(flags.CrewMemberCanaryGameplayHelperReadsEnabled),
			tostring(flags.CrewMemberCanaryStandStatusHelperReadEnabled),
			tostring(flags.CrewMemberCanaryIncomeStatusHelperReadEnabled),
			tostring(flags.CrewMemberCanaryIncomeToastHelperReadEnabled),
			tostring(flags.CrewMemberCanaryFoodStatusHelperReadEnabled),
			tostring(flags.CrewMemberCanaryGameplayReadsEnabled),
			tostring(flags.CrewMemberCanonicalReadEnabled)
		)
	end

	if gameplayHelpersMode ~= nil then
		warn(string.format(
			"[DevFruitDevCommands] Invalid /crewcanary gameplayhelpers argument '%s' from %s. Use on or off",
			tostring(gameplayHelpersMode),
			player.Name
		))
		return false, "invalid_gameplayhelpers_argument"
	end

	if standStatusMode == "on" or standStatusMode == "enable" or standStatusMode == "true" then
		if not AdminPermissions.IsSuperAdmin(player) then
			warn(string.format(
				"[DevFruitDevCommands] Rejected /crewcanary standstatus on from %s reason=not_super_admin",
				player.Name
			))
			return false, "not_super_admin"
		end

		local ok, reason, state = CrewMemberCanonicalReadGate.SetStandStatusHelperReadSessionOverride(true)
		if ok ~= true then
			warn(string.format(
				"[DevFruitDevCommands] Failed /crewcanary standstatus on for %s reason=%s",
				player.Name,
				tostring(reason or "unknown_error")
			))
			return false, tostring(reason or "unknown_error")
		end

		local flags = state and state.Flags or CrewMemberCanonicalReadGate.GetFlags()
		print(string.format(
			"[DevFruitDevCommands] %s enabled CrewMember stand status helper read session override helperReads=%s standStatusHelperRead=%s incomeStatusHelperRead=%s foodStatusHelperRead=%s gameplayReads=%s canonicalRead=%s",
			player.Name,
			tostring(flags.CrewMemberCanaryGameplayHelperReadsEnabled),
			tostring(flags.CrewMemberCanaryStandStatusHelperReadEnabled),
			tostring(flags.CrewMemberCanaryIncomeStatusHelperReadEnabled),
			tostring(flags.CrewMemberCanaryFoodStatusHelperReadEnabled),
			tostring(flags.CrewMemberCanaryGameplayReadsEnabled),
			tostring(flags.CrewMemberCanonicalReadEnabled)
		))
		CrewMemberCanonicalReadGate.PrintStatus(player)
		local helperRows = CrewMemberCanonicalReadGate.PrintStandStatusHelperStatus(
			player,
			getCrewCanaryStandStatusItems(player),
			{
				Player = player,
			}
		)
		local detail = "CrewMember stand status helper reads enabled for this staging server session. "
			.. summarizeCrewCanaryStandStatusRows(helperRows, flags)
		return true, detail
	end

	if standStatusMode == "off" or standStatusMode == "disable" or standStatusMode == "false" then
		if not AdminPermissions.IsSuperAdmin(player) then
			warn(string.format(
				"[DevFruitDevCommands] Rejected /crewcanary standstatus off from %s reason=not_super_admin",
				player.Name
			))
			return false, "not_super_admin"
		end

		local ok, reason, state = CrewMemberCanonicalReadGate.SetStandStatusHelperReadSessionOverride(false)
		if ok ~= true then
			warn(string.format(
				"[DevFruitDevCommands] Failed /crewcanary standstatus off for %s reason=%s",
				player.Name,
				tostring(reason or "unknown_error")
			))
			return false, tostring(reason or "unknown_error")
		end

		local flags = state and state.Flags or CrewMemberCanonicalReadGate.GetFlags()
		print(string.format(
			"[DevFruitDevCommands] %s disabled CrewMember stand status helper read session override helperReads=%s standStatusHelperRead=%s incomeStatusHelperRead=%s foodStatusHelperRead=%s gameplayReads=%s canonicalRead=%s",
			player.Name,
			tostring(flags.CrewMemberCanaryGameplayHelperReadsEnabled),
			tostring(flags.CrewMemberCanaryStandStatusHelperReadEnabled),
			tostring(flags.CrewMemberCanaryIncomeStatusHelperReadEnabled),
			tostring(flags.CrewMemberCanaryFoodStatusHelperReadEnabled),
			tostring(flags.CrewMemberCanaryGameplayReadsEnabled),
			tostring(flags.CrewMemberCanonicalReadEnabled)
		))
		CrewMemberCanonicalReadGate.PrintStatus(player)
		return true, "CrewMember stand status helper reads disabled for this server session."
	end

	if standStatusMode ~= nil
		and standStatusMode ~= "status"
		and standStatusMode ~= "stale"
		and standStatusMode ~= "fallback"
	then
		warn(string.format(
			"[DevFruitDevCommands] Invalid /crewcanary standstatus argument '%s' from %s. Use on, off, or stale",
			tostring(standStatusMode),
			player.Name
		))
		return false, "invalid_standstatus_argument"
	end

	if incomeStatusMode == "on" or incomeStatusMode == "enable" or incomeStatusMode == "true" then
		if not AdminPermissions.IsSuperAdmin(player) then
			warn(string.format(
				"[DevFruitDevCommands] Rejected /crewcanary incomestatus on from %s reason=not_super_admin",
				player.Name
			))
			return false, "not_super_admin"
		end

		local ok, reason, state = CrewMemberCanonicalReadGate.SetIncomeStatusHelperReadSessionOverride(true)
		if ok ~= true then
			warn(string.format(
				"[DevFruitDevCommands] Failed /crewcanary incomestatus on for %s reason=%s",
				player.Name,
				tostring(reason or "unknown_error")
			))
			return false, tostring(reason or "unknown_error")
		end

		local flags = state and state.Flags or CrewMemberCanonicalReadGate.GetFlags()
		print(string.format(
			"[DevFruitDevCommands] %s enabled CrewMember income status helper read session override helperReads=%s incomeStatusHelperRead=%s incomeToastHelperRead=%s standStatusHelperRead=%s foodStatusHelperRead=%s gameplayReads=%s canonicalRead=%s",
			player.Name,
			tostring(flags.CrewMemberCanaryGameplayHelperReadsEnabled),
			tostring(flags.CrewMemberCanaryIncomeStatusHelperReadEnabled),
			tostring(flags.CrewMemberCanaryIncomeToastHelperReadEnabled),
			tostring(flags.CrewMemberCanaryStandStatusHelperReadEnabled),
			tostring(flags.CrewMemberCanaryFoodStatusHelperReadEnabled),
			tostring(flags.CrewMemberCanaryGameplayReadsEnabled),
			tostring(flags.CrewMemberCanonicalReadEnabled)
		))
		CrewMemberCanonicalReadGate.PrintStatus(player)
		local helperRows = CrewMemberCanonicalReadGate.PrintIncomeStatusHelperStatus(
			player,
			getCrewCanaryStandStatusItems(player),
			{
				Player = player,
			}
		)
		local detail = "CrewMember income status helper reads enabled for this staging server session. "
			.. summarizeCrewCanaryIncomeStatusRows(helperRows, flags)
		return true, detail
	end

	if incomeStatusMode == "off" or incomeStatusMode == "disable" or incomeStatusMode == "false" then
		if not AdminPermissions.IsSuperAdmin(player) then
			warn(string.format(
				"[DevFruitDevCommands] Rejected /crewcanary incomestatus off from %s reason=not_super_admin",
				player.Name
			))
			return false, "not_super_admin"
		end

		local ok, reason, state = CrewMemberCanonicalReadGate.SetIncomeStatusHelperReadSessionOverride(false)
		if ok ~= true then
			warn(string.format(
				"[DevFruitDevCommands] Failed /crewcanary incomestatus off for %s reason=%s",
				player.Name,
				tostring(reason or "unknown_error")
			))
			return false, tostring(reason or "unknown_error")
		end

		local flags = state and state.Flags or CrewMemberCanonicalReadGate.GetFlags()
		print(string.format(
			"[DevFruitDevCommands] %s disabled CrewMember income status helper read session override helperReads=%s incomeStatusHelperRead=%s incomeToastHelperRead=%s standStatusHelperRead=%s foodStatusHelperRead=%s gameplayReads=%s canonicalRead=%s",
			player.Name,
			tostring(flags.CrewMemberCanaryGameplayHelperReadsEnabled),
			tostring(flags.CrewMemberCanaryIncomeStatusHelperReadEnabled),
			tostring(flags.CrewMemberCanaryIncomeToastHelperReadEnabled),
			tostring(flags.CrewMemberCanaryStandStatusHelperReadEnabled),
			tostring(flags.CrewMemberCanaryFoodStatusHelperReadEnabled),
			tostring(flags.CrewMemberCanaryGameplayReadsEnabled),
			tostring(flags.CrewMemberCanonicalReadEnabled)
		))
		CrewMemberCanonicalReadGate.PrintStatus(player)
		return true, "CrewMember income status helper reads disabled for this server session."
	end

	if incomeStatusMode ~= nil
		and incomeStatusMode ~= "status"
		and incomeStatusMode ~= "stale"
		and incomeStatusMode ~= "fallback"
	then
		warn(string.format(
			"[DevFruitDevCommands] Invalid /crewcanary incomestatus argument '%s' from %s. Use on, off, or stale",
			tostring(incomeStatusMode),
			player.Name
		))
		return false, "invalid_incomestatus_argument"
	end

	if standIncomeStatusMode == "on" or standIncomeStatusMode == "enable" or standIncomeStatusMode == "true" then
		if not AdminPermissions.IsSuperAdmin(player) then
			warn(string.format(
				"[DevFruitDevCommands] Rejected /crewcanary standincomestatus on from %s reason=not_super_admin",
				player.Name
			))
			return false, "not_super_admin"
		end

		local ok, reason, state = CrewMemberCanonicalReadGate.SetStandIncomeStatusHelperReadSessionOverride(true)
		if ok ~= true then
			warn(string.format(
				"[DevFruitDevCommands] Failed /crewcanary standincomestatus on for %s reason=%s",
				player.Name,
				tostring(reason or "unknown_error")
			))
			return false, tostring(reason or "unknown_error")
		end

		local flags = state and state.Flags or CrewMemberCanonicalReadGate.GetFlags()
		print(string.format(
			"[DevFruitDevCommands] %s enabled CrewMember stand+income status helper read session override helperReads=%s standStatusHelperRead=%s incomeStatusHelperRead=%s incomeToastHelperRead=%s foodStatusHelperRead=%s gameplayReads=%s canonicalRead=%s profileMigrationWrite=%s",
			player.Name,
			tostring(flags.CrewMemberCanaryGameplayHelperReadsEnabled),
			tostring(flags.CrewMemberCanaryStandStatusHelperReadEnabled),
			tostring(flags.CrewMemberCanaryIncomeStatusHelperReadEnabled),
			tostring(flags.CrewMemberCanaryIncomeToastHelperReadEnabled),
			tostring(flags.CrewMemberCanaryFoodStatusHelperReadEnabled),
			tostring(flags.CrewMemberCanaryGameplayReadsEnabled),
			tostring(flags.CrewMemberCanonicalReadEnabled),
			tostring(flags.CrewMemberCanaryProfileMigrationWriteEnabled)
		))
		CrewMemberCanonicalReadGate.PrintStatus(player)
		local standRows = CrewMemberCanonicalReadGate.PrintStandStatusHelperStatus(player, getCrewCanaryStandStatusItems(player), {
			Player = player,
		})
		local incomeRows = CrewMemberCanonicalReadGate.PrintIncomeStatusHelperStatus(player, getCrewCanaryStandStatusItems(player), {
			Player = player,
		})
		local detail = "CrewMember stand+income status helper reads enabled for this staging server session. "
			.. summarizeCrewCanaryStandStatusRows(standRows, flags)
			.. " "
			.. summarizeCrewCanaryIncomeStatusRows(incomeRows, flags)
		return true, detail
	end

	if standIncomeStatusMode == "off" or standIncomeStatusMode == "disable" or standIncomeStatusMode == "false" then
		if not AdminPermissions.IsSuperAdmin(player) then
			warn(string.format(
				"[DevFruitDevCommands] Rejected /crewcanary standincomestatus off from %s reason=not_super_admin",
				player.Name
			))
			return false, "not_super_admin"
		end

		local ok, reason, state = CrewMemberCanonicalReadGate.SetStandIncomeStatusHelperReadSessionOverride(false)
		if ok ~= true then
			warn(string.format(
				"[DevFruitDevCommands] Failed /crewcanary standincomestatus off for %s reason=%s",
				player.Name,
				tostring(reason or "unknown_error")
			))
			return false, tostring(reason or "unknown_error")
		end

		local flags = state and state.Flags or CrewMemberCanonicalReadGate.GetFlags()
		print(string.format(
			"[DevFruitDevCommands] %s disabled CrewMember stand+income status helper read session override helperReads=%s standStatusHelperRead=%s incomeStatusHelperRead=%s incomeToastHelperRead=%s foodStatusHelperRead=%s gameplayReads=%s canonicalRead=%s profileMigrationWrite=%s",
			player.Name,
			tostring(flags.CrewMemberCanaryGameplayHelperReadsEnabled),
			tostring(flags.CrewMemberCanaryStandStatusHelperReadEnabled),
			tostring(flags.CrewMemberCanaryIncomeStatusHelperReadEnabled),
			tostring(flags.CrewMemberCanaryIncomeToastHelperReadEnabled),
			tostring(flags.CrewMemberCanaryFoodStatusHelperReadEnabled),
			tostring(flags.CrewMemberCanaryGameplayReadsEnabled),
			tostring(flags.CrewMemberCanonicalReadEnabled),
			tostring(flags.CrewMemberCanaryProfileMigrationWriteEnabled)
		))
		CrewMemberCanonicalReadGate.PrintStatus(player)
		return true, "CrewMember stand+income status helper reads disabled for this server session."
	end

	if standIncomeStatusMode ~= nil
		and standIncomeStatusMode ~= "status"
		and standIncomeStatusMode ~= "stale"
		and standIncomeStatusMode ~= "fallback"
	then
		warn(string.format(
			"[DevFruitDevCommands] Invalid /crewcanary standincomestatus argument '%s' from %s. Use on, off, or stale",
			tostring(standIncomeStatusMode),
			player.Name
		))
		return false, "invalid_standincomestatus_argument"
	end

	if incomeToastMode == "on" or incomeToastMode == "enable" or incomeToastMode == "true" then
		if not AdminPermissions.IsSuperAdmin(player) then
			warn(string.format(
				"[DevFruitDevCommands] Rejected /crewcanary incometoast on from %s reason=not_super_admin",
				player.Name
			))
			return false, "not_super_admin"
		end

		local ok, reason, state = CrewMemberCanonicalReadGate.SetIncomeToastHelperReadSessionOverride(true)
		if ok ~= true then
			warn(string.format(
				"[DevFruitDevCommands] Failed /crewcanary incometoast on for %s reason=%s",
				player.Name,
				tostring(reason or "unknown_error")
			))
			return false, tostring(reason or "unknown_error")
		end

		local flags = state and state.Flags or CrewMemberCanonicalReadGate.GetFlags()
		print(string.format(
			"[DevFruitDevCommands] %s enabled CrewMember income toast helper read session override helperReads=%s incomeToastHelperRead=%s incomeStatusHelperRead=%s standStatusHelperRead=%s foodStatusHelperRead=%s gameplayReads=%s canonicalRead=%s",
			player.Name,
			tostring(flags.CrewMemberCanaryGameplayHelperReadsEnabled),
			tostring(flags.CrewMemberCanaryIncomeToastHelperReadEnabled),
			tostring(flags.CrewMemberCanaryIncomeStatusHelperReadEnabled),
			tostring(flags.CrewMemberCanaryStandStatusHelperReadEnabled),
			tostring(flags.CrewMemberCanaryFoodStatusHelperReadEnabled),
			tostring(flags.CrewMemberCanaryGameplayReadsEnabled),
			tostring(flags.CrewMemberCanonicalReadEnabled)
		))
		CrewMemberCanonicalReadGate.PrintStatus(player)
		local helperRows = CrewMemberCanonicalReadGate.PrintIncomeToastHelperStatus(
			player,
			getCrewCanaryStandStatusItems(player),
			{
				Player = player,
			}
		)
		local detail = "CrewMember income toast helper reads enabled for this staging server session. "
			.. summarizeCrewCanaryIncomeToastRows(helperRows, flags)
		return true, detail
	end

	if incomeToastMode == "off" or incomeToastMode == "disable" or incomeToastMode == "false" then
		if not AdminPermissions.IsSuperAdmin(player) then
			warn(string.format(
				"[DevFruitDevCommands] Rejected /crewcanary incometoast off from %s reason=not_super_admin",
				player.Name
			))
			return false, "not_super_admin"
		end

		local ok, reason, state = CrewMemberCanonicalReadGate.SetIncomeToastHelperReadSessionOverride(false)
		if ok ~= true then
			warn(string.format(
				"[DevFruitDevCommands] Failed /crewcanary incometoast off for %s reason=%s",
				player.Name,
				tostring(reason or "unknown_error")
			))
			return false, tostring(reason or "unknown_error")
		end

		local flags = state and state.Flags or CrewMemberCanonicalReadGate.GetFlags()
		print(string.format(
			"[DevFruitDevCommands] %s disabled CrewMember income toast helper read session override helperReads=%s incomeToastHelperRead=%s incomeStatusHelperRead=%s standStatusHelperRead=%s foodStatusHelperRead=%s gameplayReads=%s canonicalRead=%s",
			player.Name,
			tostring(flags.CrewMemberCanaryGameplayHelperReadsEnabled),
			tostring(flags.CrewMemberCanaryIncomeToastHelperReadEnabled),
			tostring(flags.CrewMemberCanaryIncomeStatusHelperReadEnabled),
			tostring(flags.CrewMemberCanaryStandStatusHelperReadEnabled),
			tostring(flags.CrewMemberCanaryFoodStatusHelperReadEnabled),
			tostring(flags.CrewMemberCanaryGameplayReadsEnabled),
			tostring(flags.CrewMemberCanonicalReadEnabled)
		))
		CrewMemberCanonicalReadGate.PrintStatus(player)
		return true, "CrewMember income toast helper reads disabled for this server session."
	end

	if incomeToastMode ~= nil
		and incomeToastMode ~= "status"
		and incomeToastMode ~= "stale"
		and incomeToastMode ~= "fallback"
	then
		warn(string.format(
			"[DevFruitDevCommands] Invalid /crewcanary incometoast argument '%s' from %s. Use on, off, or stale",
			tostring(incomeToastMode),
			player.Name
		))
		return false, "invalid_incometoast_argument"
	end

	if foodStatusMode == "on" or foodStatusMode == "enable" or foodStatusMode == "true" then
		if not AdminPermissions.IsSuperAdmin(player) then
			warn(string.format(
				"[DevFruitDevCommands] Rejected /crewcanary foodstatus on from %s reason=not_super_admin",
				player.Name
			))
			return false, "not_super_admin"
		end

		local ok, reason, state = CrewMemberCanonicalReadGate.SetFoodStatusHelperReadSessionOverride(true)
		if ok ~= true then
			warn(string.format(
				"[DevFruitDevCommands] Failed /crewcanary foodstatus on for %s reason=%s",
				player.Name,
				tostring(reason or "unknown_error")
			))
			return false, tostring(reason or "unknown_error")
		end

		local flags = state and state.Flags or CrewMemberCanonicalReadGate.GetFlags()
		print(string.format(
			"[DevFruitDevCommands] %s enabled CrewMember food status helper read session override helperReads=%s foodStatusHelperRead=%s standStatusHelperRead=%s incomeStatusHelperRead=%s incomeToastHelperRead=%s gameplayReads=%s canonicalRead=%s",
			player.Name,
			tostring(flags.CrewMemberCanaryGameplayHelperReadsEnabled),
			tostring(flags.CrewMemberCanaryFoodStatusHelperReadEnabled),
			tostring(flags.CrewMemberCanaryStandStatusHelperReadEnabled),
			tostring(flags.CrewMemberCanaryIncomeStatusHelperReadEnabled),
			tostring(flags.CrewMemberCanaryIncomeToastHelperReadEnabled),
			tostring(flags.CrewMemberCanaryGameplayReadsEnabled),
			tostring(flags.CrewMemberCanonicalReadEnabled)
		))
		CrewMemberCanonicalReadGate.PrintStatus(player)
		local helperRows = CrewMemberCanonicalReadGate.PrintFoodStatusHelperStatus(
			player,
			getCrewCanaryStandStatusItems(player),
			{
				Player = player,
			}
		)
		local detail = "CrewMember food status helper reads enabled for this staging server session. "
			.. summarizeCrewCanaryFoodStatusRows(helperRows, flags)
		return true, detail
	end

	if foodStatusMode == "off" or foodStatusMode == "disable" or foodStatusMode == "false" then
		if not AdminPermissions.IsSuperAdmin(player) then
			warn(string.format(
				"[DevFruitDevCommands] Rejected /crewcanary foodstatus off from %s reason=not_super_admin",
				player.Name
			))
			return false, "not_super_admin"
		end

		local ok, reason, state = CrewMemberCanonicalReadGate.SetFoodStatusHelperReadSessionOverride(false)
		if ok ~= true then
			warn(string.format(
				"[DevFruitDevCommands] Failed /crewcanary foodstatus off for %s reason=%s",
				player.Name,
				tostring(reason or "unknown_error")
			))
			return false, tostring(reason or "unknown_error")
		end

		local flags = state and state.Flags or CrewMemberCanonicalReadGate.GetFlags()
		print(string.format(
			"[DevFruitDevCommands] %s disabled CrewMember food status helper read session override helperReads=%s foodStatusHelperRead=%s standStatusHelperRead=%s incomeStatusHelperRead=%s incomeToastHelperRead=%s gameplayReads=%s canonicalRead=%s",
			player.Name,
			tostring(flags.CrewMemberCanaryGameplayHelperReadsEnabled),
			tostring(flags.CrewMemberCanaryFoodStatusHelperReadEnabled),
			tostring(flags.CrewMemberCanaryStandStatusHelperReadEnabled),
			tostring(flags.CrewMemberCanaryIncomeStatusHelperReadEnabled),
			tostring(flags.CrewMemberCanaryIncomeToastHelperReadEnabled),
			tostring(flags.CrewMemberCanaryGameplayReadsEnabled),
			tostring(flags.CrewMemberCanonicalReadEnabled)
		))
		CrewMemberCanonicalReadGate.PrintStatus(player)
		return true, "CrewMember food status helper reads disabled for this server session."
	end

	if foodStatusMode ~= nil
		and foodStatusMode ~= "status"
		and foodStatusMode ~= "stale"
		and foodStatusMode ~= "fallback"
	then
		warn(string.format(
			"[DevFruitDevCommands] Invalid /crewcanary foodstatus argument '%s' from %s. Use on, off, or stale",
			tostring(foodStatusMode),
			player.Name
		))
		return false, "invalid_foodstatus_argument"
	end

	if indexModelPreviewMode == "on" or indexModelPreviewMode == "enable" or indexModelPreviewMode == "true" then
		if not AdminPermissions.IsSuperAdmin(player) then
			warn(string.format(
				"[DevFruitDevCommands] Rejected /crewcanary modelpreviews index on from %s reason=not_super_admin",
				player.Name
			))
			return false, "not_super_admin"
		end

		local ok, reason, state = CrewMemberCanonicalReadGate.SetIndexModelPreviewReadSessionOverride(true)
		if ok ~= true then
			warn(string.format(
				"[DevFruitDevCommands] Failed /crewcanary modelpreviews index on for %s reason=%s",
				player.Name,
				tostring(reason or "unknown_error")
			))
			return false, tostring(reason or "unknown_error")
		end

		local flags = state and state.Flags or CrewMemberCanonicalReadGate.GetFlags()
		print(string.format(
			"[DevFruitDevCommands] %s enabled CrewMember index model-preview read session override modelPreviewReads=%s adminModelPreviewRead=%s indexModelPreviewRead=%s inventoryModelPreviewRead=%s gameplayReads=%s canonicalRead=%s",
			player.Name,
			tostring(flags.CrewMemberCanaryModelPreviewReadsEnabled),
			tostring(flags.CrewMemberCanaryAdminModelPreviewReadEnabled),
			tostring(flags.CrewMemberCanaryIndexModelPreviewReadEnabled),
			tostring(flags.CrewMemberCanaryInventoryModelPreviewReadEnabled),
			tostring(flags.CrewMemberCanaryGameplayReadsEnabled),
			tostring(flags.CrewMemberCanonicalReadEnabled)
		))
		CrewMemberCanonicalReadGate.PrintStatus(player)
		local previewRows = CrewMemberCanonicalReadGate.PrintIndexModelPreviewStatus(
			player,
			CREW_CANARY_MODEL_PREVIEW_STATUS_ITEMS,
			{
				Player = player,
			}
		)
		local detail = "CrewMember index model-preview reads enabled for this staging server session. "
			.. summarizeCrewCanaryModelPreviewRows(previewRows, flags)
		return true, detail
	end

	if indexModelPreviewMode == "off" or indexModelPreviewMode == "disable" or indexModelPreviewMode == "false" then
		if not AdminPermissions.IsSuperAdmin(player) then
			warn(string.format(
				"[DevFruitDevCommands] Rejected /crewcanary modelpreviews index off from %s reason=not_super_admin",
				player.Name
			))
			return false, "not_super_admin"
		end

		local ok, reason, state = CrewMemberCanonicalReadGate.SetIndexModelPreviewReadSessionOverride(false)
		if ok ~= true then
			warn(string.format(
				"[DevFruitDevCommands] Failed /crewcanary modelpreviews index off for %s reason=%s",
				player.Name,
				tostring(reason or "unknown_error")
			))
			return false, tostring(reason or "unknown_error")
		end

		local flags = state and state.Flags or CrewMemberCanonicalReadGate.GetFlags()
		print(string.format(
			"[DevFruitDevCommands] %s disabled CrewMember index model-preview read session override modelPreviewReads=%s adminModelPreviewRead=%s indexModelPreviewRead=%s inventoryModelPreviewRead=%s gameplayReads=%s canonicalRead=%s",
			player.Name,
			tostring(flags.CrewMemberCanaryModelPreviewReadsEnabled),
			tostring(flags.CrewMemberCanaryAdminModelPreviewReadEnabled),
			tostring(flags.CrewMemberCanaryIndexModelPreviewReadEnabled),
			tostring(flags.CrewMemberCanaryInventoryModelPreviewReadEnabled),
			tostring(flags.CrewMemberCanaryGameplayReadsEnabled),
			tostring(flags.CrewMemberCanonicalReadEnabled)
		))
		CrewMemberCanonicalReadGate.PrintStatus(player)
		return true, "CrewMember index model-preview reads disabled for this server session."
	end

	if indexModelPreviewMode ~= nil
		and indexModelPreviewMode ~= "status"
		and indexModelPreviewMode ~= "stale"
		and indexModelPreviewMode ~= "fallback"
	then
		warn(string.format(
			"[DevFruitDevCommands] Invalid /crewcanary modelpreviews index argument '%s' from %s. Use on, off, or stale",
			tostring(indexModelPreviewMode),
			player.Name
		))
		return false, "invalid_index_modelpreviews_argument"
	end

	if inventoryModelPreviewMode == "on" or inventoryModelPreviewMode == "enable" or inventoryModelPreviewMode == "true" then
		if not AdminPermissions.IsSuperAdmin(player) then
			warn(string.format(
				"[DevFruitDevCommands] Rejected /crewcanary modelpreviews inventory on from %s reason=not_super_admin",
				player.Name
			))
			return false, "not_super_admin"
		end

		local ok, reason, state = CrewMemberCanonicalReadGate.SetInventoryModelPreviewReadSessionOverride(true)
		if ok ~= true then
			warn(string.format(
				"[DevFruitDevCommands] Failed /crewcanary modelpreviews inventory on for %s reason=%s",
				player.Name,
				tostring(reason or "unknown_error")
			))
			return false, tostring(reason or "unknown_error")
		end

		local flags = state and state.Flags or CrewMemberCanonicalReadGate.GetFlags()
		print(string.format(
			"[DevFruitDevCommands] %s enabled CrewMember inventory model-preview read session override modelPreviewReads=%s adminModelPreviewRead=%s indexModelPreviewRead=%s inventoryModelPreviewRead=%s gameplayReads=%s canonicalRead=%s",
			player.Name,
			tostring(flags.CrewMemberCanaryModelPreviewReadsEnabled),
			tostring(flags.CrewMemberCanaryAdminModelPreviewReadEnabled),
			tostring(flags.CrewMemberCanaryIndexModelPreviewReadEnabled),
			tostring(flags.CrewMemberCanaryInventoryModelPreviewReadEnabled),
			tostring(flags.CrewMemberCanaryGameplayReadsEnabled),
			tostring(flags.CrewMemberCanonicalReadEnabled)
		))
		CrewMemberCanonicalReadGate.PrintStatus(player)
		local previewRows = CrewMemberCanonicalReadGate.PrintInventoryModelPreviewStatus(
			player,
			CREW_CANARY_MODEL_PREVIEW_STATUS_ITEMS,
			{
				Player = player,
			}
		)
		local detail = "CrewMember inventory model-preview reads enabled for this staging server session. "
			.. summarizeCrewCanaryModelPreviewRows(previewRows, flags)
		return true, detail
	end

	if inventoryModelPreviewMode == "off" or inventoryModelPreviewMode == "disable" or inventoryModelPreviewMode == "false" then
		if not AdminPermissions.IsSuperAdmin(player) then
			warn(string.format(
				"[DevFruitDevCommands] Rejected /crewcanary modelpreviews inventory off from %s reason=not_super_admin",
				player.Name
			))
			return false, "not_super_admin"
		end

		local ok, reason, state = CrewMemberCanonicalReadGate.SetInventoryModelPreviewReadSessionOverride(false)
		if ok ~= true then
			warn(string.format(
				"[DevFruitDevCommands] Failed /crewcanary modelpreviews inventory off for %s reason=%s",
				player.Name,
				tostring(reason or "unknown_error")
			))
			return false, tostring(reason or "unknown_error")
		end

		local flags = state and state.Flags or CrewMemberCanonicalReadGate.GetFlags()
		print(string.format(
			"[DevFruitDevCommands] %s disabled CrewMember inventory model-preview read session override modelPreviewReads=%s adminModelPreviewRead=%s indexModelPreviewRead=%s inventoryModelPreviewRead=%s gameplayReads=%s canonicalRead=%s",
			player.Name,
			tostring(flags.CrewMemberCanaryModelPreviewReadsEnabled),
			tostring(flags.CrewMemberCanaryAdminModelPreviewReadEnabled),
			tostring(flags.CrewMemberCanaryIndexModelPreviewReadEnabled),
			tostring(flags.CrewMemberCanaryInventoryModelPreviewReadEnabled),
			tostring(flags.CrewMemberCanaryGameplayReadsEnabled),
			tostring(flags.CrewMemberCanonicalReadEnabled)
		))
		CrewMemberCanonicalReadGate.PrintStatus(player)
		return true, "CrewMember inventory model-preview reads disabled for this server session."
	end

	if inventoryModelPreviewMode ~= nil
		and inventoryModelPreviewMode ~= "status"
		and inventoryModelPreviewMode ~= "stale"
		and inventoryModelPreviewMode ~= "fallback"
	then
		warn(string.format(
			"[DevFruitDevCommands] Invalid /crewcanary modelpreviews inventory argument '%s' from %s. Use on, off, or stale",
			tostring(inventoryModelPreviewMode),
			player.Name
		))
		return false, "invalid_inventory_modelpreviews_argument"
	end

	if modelPreviewMode == "on" or modelPreviewMode == "enable" or modelPreviewMode == "true" then
		if not AdminPermissions.IsSuperAdmin(player) then
			warn(string.format(
				"[DevFruitDevCommands] Rejected /crewcanary modelpreviews on from %s reason=not_super_admin",
				player.Name
			))
			return false, "not_super_admin"
		end

		local ok, reason, state = CrewMemberCanonicalReadGate.SetAdminModelPreviewReadSessionOverride(true)
		if ok ~= true then
			warn(string.format(
				"[DevFruitDevCommands] Failed /crewcanary modelpreviews on for %s reason=%s",
				player.Name,
				tostring(reason or "unknown_error")
			))
			return false, tostring(reason or "unknown_error")
		end

		local flags = state and state.Flags or CrewMemberCanonicalReadGate.GetFlags()
		print(string.format(
			"[DevFruitDevCommands] %s enabled CrewMember admin model-preview read session override modelPreviewReads=%s adminModelPreviewRead=%s indexModelPreviewRead=%s inventoryModelPreviewRead=%s gameplayReads=%s canonicalRead=%s",
			player.Name,
			tostring(flags.CrewMemberCanaryModelPreviewReadsEnabled),
			tostring(flags.CrewMemberCanaryAdminModelPreviewReadEnabled),
			tostring(flags.CrewMemberCanaryIndexModelPreviewReadEnabled),
			tostring(flags.CrewMemberCanaryInventoryModelPreviewReadEnabled),
			tostring(flags.CrewMemberCanaryGameplayReadsEnabled),
			tostring(flags.CrewMemberCanonicalReadEnabled)
		))
		CrewMemberCanonicalReadGate.PrintStatus(player)
		local previewRows = CrewMemberCanonicalReadGate.PrintAdminModelPreviewStatus(
			player,
			CREW_CANARY_MODEL_PREVIEW_STATUS_ITEMS,
			{
				Player = player,
			}
		)
		local detail = "CrewMember admin model-preview reads enabled for this staging server session. "
			.. summarizeCrewCanaryModelPreviewRows(previewRows, flags)
		return true, detail
	end

	if modelPreviewMode == "off" or modelPreviewMode == "disable" or modelPreviewMode == "false" then
		if not AdminPermissions.IsSuperAdmin(player) then
			warn(string.format(
				"[DevFruitDevCommands] Rejected /crewcanary modelpreviews off from %s reason=not_super_admin",
				player.Name
			))
			return false, "not_super_admin"
		end

		local ok, reason, state = CrewMemberCanonicalReadGate.SetAdminModelPreviewReadSessionOverride(false)
		if ok ~= true then
			warn(string.format(
				"[DevFruitDevCommands] Failed /crewcanary modelpreviews off for %s reason=%s",
				player.Name,
				tostring(reason or "unknown_error")
			))
			return false, tostring(reason or "unknown_error")
		end

		local flags = state and state.Flags or CrewMemberCanonicalReadGate.GetFlags()
		print(string.format(
			"[DevFruitDevCommands] %s disabled CrewMember admin model-preview read session override modelPreviewReads=%s adminModelPreviewRead=%s indexModelPreviewRead=%s inventoryModelPreviewRead=%s gameplayReads=%s canonicalRead=%s",
			player.Name,
			tostring(flags.CrewMemberCanaryModelPreviewReadsEnabled),
			tostring(flags.CrewMemberCanaryAdminModelPreviewReadEnabled),
			tostring(flags.CrewMemberCanaryIndexModelPreviewReadEnabled),
			tostring(flags.CrewMemberCanaryInventoryModelPreviewReadEnabled),
			tostring(flags.CrewMemberCanaryGameplayReadsEnabled),
			tostring(flags.CrewMemberCanonicalReadEnabled)
		))
		CrewMemberCanonicalReadGate.PrintStatus(player)
		return true, "CrewMember admin model-preview reads disabled for this server session."
	end

	if modelPreviewMode ~= nil
		and indexModelPreviewMode == nil
		and inventoryModelPreviewMode == nil
		and modelPreviewMode ~= "stale"
		and modelPreviewMode ~= "fallback"
	then
		warn(string.format(
			"[DevFruitDevCommands] Invalid /crewcanary modelpreviews argument '%s' from %s. Use on, off, or stale",
			tostring(modelPreviewMode),
			player.Name
		))
		return false, "invalid_modelpreviews_argument"
	end

	if helperMode == "on" or helperMode == "enable" or helperMode == "true" then
		if not AdminPermissions.IsSuperAdmin(player) then
			warn(string.format(
				"[DevFruitDevCommands] Rejected /crewcanary helpers on from %s reason=not_super_admin",
				player.Name
			))
			return false, "not_super_admin"
		end

		local ok, reason, state = CrewMemberCanonicalReadGate.SetMetadataHelperReadSessionOverride(true)
		if ok ~= true then
			warn(string.format(
				"[DevFruitDevCommands] Failed /crewcanary helpers on for %s reason=%s",
				player.Name,
				tostring(reason or "unknown_error")
			))
			return false, tostring(reason or "unknown_error")
		end

		local flags = state and state.Flags or CrewMemberCanonicalReadGate.GetFlags()
		print(string.format(
			"[DevFruitDevCommands] %s enabled CrewMember metadata helper read session override helperReads=%s metadataHelperReads=%s modelPreviewReads=%s gameplayReads=%s canonicalRead=%s",
			player.Name,
			tostring(flags.CrewMemberCanaryGameplayHelperReadsEnabled),
			tostring(flags.CrewMemberCanaryMetadataHelperReadsEnabled),
			tostring(flags.CrewMemberCanaryModelPreviewReadsEnabled),
			tostring(flags.CrewMemberCanaryGameplayReadsEnabled),
			tostring(flags.CrewMemberCanonicalReadEnabled)
		))
		CrewMemberCanonicalReadGate.PrintStatus(player)
		local helperRows = CrewMemberCanonicalReadGate.PrintMetadataHelperStatus(player, CREW_CANARY_HELPER_STATUS_ITEMS, {
			Player = player,
		})
		local detail = "CrewMember metadata helper reads enabled for this staging server session. "
			.. summarizeCrewCanaryHelperRows(helperRows, flags)
		return true, detail
	end

	if helperMode == "off" or helperMode == "disable" or helperMode == "false" then
		if not AdminPermissions.IsSuperAdmin(player) then
			warn(string.format(
				"[DevFruitDevCommands] Rejected /crewcanary helpers off from %s reason=not_super_admin",
				player.Name
			))
			return false, "not_super_admin"
		end

		local ok, reason, state = CrewMemberCanonicalReadGate.SetMetadataHelperReadSessionOverride(false)
		if ok ~= true then
			warn(string.format(
				"[DevFruitDevCommands] Failed /crewcanary helpers off for %s reason=%s",
				player.Name,
				tostring(reason or "unknown_error")
			))
			return false, tostring(reason or "unknown_error")
		end

		local flags = state and state.Flags or CrewMemberCanonicalReadGate.GetFlags()
		print(string.format(
			"[DevFruitDevCommands] %s disabled CrewMember metadata helper read session override helperReads=%s metadataHelperReads=%s modelPreviewReads=%s gameplayReads=%s canonicalRead=%s",
			player.Name,
			tostring(flags.CrewMemberCanaryGameplayHelperReadsEnabled),
			tostring(flags.CrewMemberCanaryMetadataHelperReadsEnabled),
			tostring(flags.CrewMemberCanaryModelPreviewReadsEnabled),
			tostring(flags.CrewMemberCanaryGameplayReadsEnabled),
			tostring(flags.CrewMemberCanonicalReadEnabled)
		))
		CrewMemberCanonicalReadGate.PrintStatus(player)
		return true, "CrewMember metadata helper reads disabled for this server session."
	end

	if helperMode ~= nil and helperMode ~= "stale" and helperMode ~= "fallback" then
		warn(string.format(
			"[DevFruitDevCommands] Invalid /crewcanary helpers argument '%s' from %s. Use on, off, or stale",
			tostring(helperMode),
			player.Name
		))
		return false, "invalid_helpers_argument"
	end

	CrewMemberCanonicalReadGate.PrintStatus(player)
	if standReadAuthorityMode == "status"
		or standReadAuthorityMode == "stale"
		or standReadAuthorityMode == "fallback"
	then
		local rows = CrewMemberCanonicalReadGate.PrintStandStatusReadAuthorityStatus(
			player,
			getCrewCanaryStandReadAuthorityStandNames(player),
			{
				Player = player,
				MaxValidationAgeSeconds = if standReadAuthorityMode == "stale"
						or standReadAuthorityMode == "fallback"
					then 0.001
					else nil,
			}
		)
		local flags = CrewMemberCanonicalReadGate.GetFlags()
		return true,
			"CrewMember canary status printed to server output. "
				.. summarizeCrewCanaryStandReadAuthorityRows(rows, flags)
	end
	if incomeReadAuthorityMode == "status"
		or incomeReadAuthorityMode == "stale"
		or incomeReadAuthorityMode == "fallback"
	then
		local rows = CrewMemberCanonicalReadGate.PrintIncomeStatusReadAuthorityStatus(
			player,
			getCrewCanaryStandReadAuthorityStandNames(player),
			{
				Player = player,
				MaxValidationAgeSeconds = if incomeReadAuthorityMode == "stale"
						or incomeReadAuthorityMode == "fallback"
					then 0.001
					else nil,
			}
		)
		local flags = CrewMemberCanonicalReadGate.GetFlags()
		return true,
			"CrewMember canary status printed to server output. "
				.. summarizeCrewCanaryIncomeReadAuthorityRows(rows, flags)
	end
	if foodReadAuthorityMode == "status"
		or foodReadAuthorityMode == "stale"
		or foodReadAuthorityMode == "fallback"
	then
		local rows = CrewMemberCanonicalReadGate.PrintFoodStatusReadAuthorityStatus(
			player,
			getCrewCanaryFoodReadAuthorityContexts(player),
			{
				Player = player,
				MaxValidationAgeSeconds = if foodReadAuthorityMode == "stale"
						or foodReadAuthorityMode == "fallback"
					then 0.001
					else nil,
			}
		)
		local flags = CrewMemberCanonicalReadGate.GetFlags()
		return true,
			"CrewMember canary status printed to server output. "
				.. summarizeCrewCanaryFoodReadAuthorityRows(rows, flags)
	end
	if normalizedArgument == "standstatus" or standStatusMode == "stale" or standStatusMode == "fallback" then
		local helperRows = CrewMemberCanonicalReadGate.PrintStandStatusHelperStatus(
			player,
			getCrewCanaryStandStatusItems(player),
			{
				Player = player,
				MaxValidationAgeSeconds = if standStatusMode == "stale" or standStatusMode == "fallback" then 0.001 else nil,
			}
		)
		local flags = CrewMemberCanonicalReadGate.GetFlags()
		return true,
			"CrewMember canary status printed to server output. "
				.. summarizeCrewCanaryStandStatusRows(helperRows, flags)
	end
	if normalizedArgument == "incomestatus" or incomeStatusMode == "stale" or incomeStatusMode == "fallback" then
		local helperRows = CrewMemberCanonicalReadGate.PrintIncomeStatusHelperStatus(
			player,
			getCrewCanaryStandStatusItems(player),
			{
				Player = player,
				MaxValidationAgeSeconds = if incomeStatusMode == "stale" or incomeStatusMode == "fallback"
					then 0.001
					else nil,
			}
		)
		local flags = CrewMemberCanonicalReadGate.GetFlags()
		return true,
			"CrewMember canary status printed to server output. "
				.. summarizeCrewCanaryIncomeStatusRows(helperRows, flags)
	end
	if normalizedArgument == "incometoast" or incomeToastMode == "stale" or incomeToastMode == "fallback" then
		local helperRows = CrewMemberCanonicalReadGate.PrintIncomeToastHelperStatus(
			player,
			getCrewCanaryStandStatusItems(player),
			{
				Player = player,
				MaxValidationAgeSeconds = if incomeToastMode == "stale" or incomeToastMode == "fallback"
					then 0.001
					else nil,
			}
		)
		local flags = CrewMemberCanonicalReadGate.GetFlags()
		return true,
			"CrewMember canary status printed to server output. "
				.. summarizeCrewCanaryIncomeToastRows(helperRows, flags)
	end
	if normalizedArgument == "foodstatus" or foodStatusMode == "stale" or foodStatusMode == "fallback" then
		local helperRows = CrewMemberCanonicalReadGate.PrintFoodStatusHelperStatus(
			player,
			getCrewCanaryStandStatusItems(player),
			{
				Player = player,
				MaxValidationAgeSeconds = if foodStatusMode == "stale" or foodStatusMode == "fallback"
					then 0.001
					else nil,
			}
		)
		local flags = CrewMemberCanonicalReadGate.GetFlags()
		return true,
			"CrewMember canary status printed to server output. "
				.. summarizeCrewCanaryFoodStatusRows(helperRows, flags)
	end
	if normalizedArgument == "helpers" or helperMode == "stale" or helperMode == "fallback" then
		local helperRows = CrewMemberCanonicalReadGate.PrintMetadataHelperStatus(player, CREW_CANARY_HELPER_STATUS_ITEMS, {
			Player = player,
			MaxValidationAgeSeconds = if helperMode == "stale" or helperMode == "fallback" then 0.001 else nil,
		})
		local flags = CrewMemberCanonicalReadGate.GetFlags()
		return true, "CrewMember canary status printed to server output. " .. summarizeCrewCanaryHelperRows(helperRows, flags)
	end
	if normalizedArgument == "modelpreviews" or modelPreviewMode == "stale" or modelPreviewMode == "fallback" then
		local previewRows = CrewMemberCanonicalReadGate.PrintAdminModelPreviewStatus(
			player,
			CREW_CANARY_MODEL_PREVIEW_STATUS_ITEMS,
			{
				Player = player,
				MaxValidationAgeSeconds = if modelPreviewMode == "stale" or modelPreviewMode == "fallback" then 0.001 else nil,
			}
		)
		local flags = CrewMemberCanonicalReadGate.GetFlags()
		return true,
			"CrewMember canary status printed to server output. "
				.. summarizeCrewCanaryModelPreviewRows(previewRows, flags)
	end
	if indexModelPreviewMode == "status" or indexModelPreviewMode == "stale" or indexModelPreviewMode == "fallback" then
		local previewRows = CrewMemberCanonicalReadGate.PrintIndexModelPreviewStatus(
			player,
			CREW_CANARY_MODEL_PREVIEW_STATUS_ITEMS,
			{
				Player = player,
				MaxValidationAgeSeconds = if indexModelPreviewMode == "stale" or indexModelPreviewMode == "fallback"
					then 0.001
					else nil,
			}
		)
		local flags = CrewMemberCanonicalReadGate.GetFlags()
		return true,
			"CrewMember canary status printed to server output. "
				.. summarizeCrewCanaryModelPreviewRows(previewRows, flags)
	end
	if inventoryModelPreviewMode == "status"
		or inventoryModelPreviewMode == "stale"
		or inventoryModelPreviewMode == "fallback"
	then
		local previewRows = CrewMemberCanonicalReadGate.PrintInventoryModelPreviewStatus(
			player,
			CREW_CANARY_MODEL_PREVIEW_STATUS_ITEMS,
			{
				Player = player,
				MaxValidationAgeSeconds = if inventoryModelPreviewMode == "stale"
						or inventoryModelPreviewMode == "fallback"
					then 0.001
					else nil,
			}
		)
		local flags = CrewMemberCanonicalReadGate.GetFlags()
		return true,
			"CrewMember canary status printed to server output. "
				.. summarizeCrewCanaryModelPreviewRows(previewRows, flags)
	end
	return true, "CrewMember canary status printed to server output."
end

local function processWipePlayerCommand(player, argumentText, commandName)
	if not isAuthorized(player) then
		return
	end

	local targetSpec, wantsConfirm = splitWipeArguments(argumentText)
	if targetSpec == "" then
		warn(string.format(
			"[DevFruitDevCommands] Invalid /%s usage from %s. Use /%s <playerName|userId> and then /%s <playerName|userId> confirm",
			tostring(commandName),
			player.Name,
			tostring(commandName),
			tostring(commandName)
		))
		return
	end

	local targetUserId, targetLabel, targetPlayer, resolveReason = resolveResetTarget(player, targetSpec)
	if targetUserId == nil then
		if resolveReason == "ambiguous_target" then
			warn(string.format(
				"[DevFruitDevCommands] Ambiguous /%s target '%s' from %s. Use an exact player name or userId.",
				tostring(commandName),
				tostring(targetSpec),
				player.Name
			))
			return
		end

		warn(string.format(
			"[DevFruitDevCommands] Unknown /%s target '%s' from %s",
			tostring(commandName),
			tostring(targetSpec),
			player.Name
		))
		return
	end

	local now = os.clock()
	local existingConfirmation = pendingWipeConfirmations[player.UserId]
	if existingConfirmation and now > existingConfirmation.expiresAt then
		pendingWipeConfirmations[player.UserId] = nil
		existingConfirmation = nil
	end

	if wantsConfirm ~= true then
		pendingWipeConfirmations[player.UserId] = {
			targetUserId = targetUserId,
			targetLabel = targetLabel,
			targetSpec = targetSpec,
			expiresAt = now + WIPE_CONFIRM_WINDOW,
		}

		warn(string.format(
			"[DevFruitDevCommands] Confirmation required. Re-run /%s %s confirm within %d seconds to permanently wipe %s (userId=%d).",
			tostring(commandName),
			tostring(targetSpec),
			WIPE_CONFIRM_WINDOW,
			tostring(targetLabel),
			targetUserId
		))
		return
	end

	if existingConfirmation == nil or existingConfirmation.targetUserId ~= targetUserId then
		warn(string.format(
			"[DevFruitDevCommands] No matching pending wipe confirmation for %s. Run /%s %s first, then confirm.",
			player.Name,
			tostring(commandName),
			tostring(targetSpec)
		))
		return
	end

	pendingWipeConfirmations[player.UserId] = nil

	print(string.format(
		"[DevFruitDevCommands] %s confirmed /%s for %s (userId=%d, online=%s)",
		player.Name,
		tostring(commandName),
		tostring(targetLabel),
		targetUserId,
		tostring(targetPlayer ~= nil)
	))

	local success, reason = DataManager:HardResetData(targetUserId)
	if success ~= true then
		warn(string.format(
			"[DevFruitDevCommands] Failed /%s for %s (userId=%d, reason=%s)",
			tostring(commandName),
			tostring(targetLabel),
			targetUserId,
			tostring(reason)
		))
		return
	end

	print(string.format(
		"[DevFruitDevCommands] %s wiped persistent profile data for %s (userId=%d, online=%s)",
		player.Name,
		tostring(targetLabel),
		targetUserId,
		tostring(targetPlayer ~= nil)
	))
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
registerChestAlias("legend", "Gold")
registerChestAlias("legendary", "Gold")

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

local function processGiftResetCommand(player, argumentText, commandName)
	if not isAuthorized(player) then
		return
	end

	local normalizedCommand = normalizeText(commandName)
	local trimmedArgument = trimText(argumentText)
	local normalizedArgument = normalizeText(argumentText)
	local targetSpec = "me"

	if normalizedCommand == "gifts" then
		if normalizedArgument == "" or normalizedArgument == "reset" or normalizedArgument == "clear" then
			targetSpec = "me"
		else
			local action, rest = trimmedArgument:match("^(%S+)%s*(.*)$")
			local normalizedAction = normalizeText(action)
			if normalizedAction ~= "reset" and normalizedAction ~= "clear" then
				warn(string.format(
					"[DevFruitDevCommands] Invalid /gifts usage from %s. Use /gifts reset [playerName].",
					player.Name
				))
				return
			end

			local parsedTarget = trimText(rest)
			targetSpec = parsedTarget ~= "" and parsedTarget or "me"
		end
	else
		targetSpec = trimmedArgument ~= "" and trimmedArgument or "me"
	end

	local targetUserId, targetLabel, targetPlayer, resolveReason = resolveResetTarget(player, targetSpec)
	if targetUserId == nil then
		if resolveReason == "ambiguous_target" then
			warn(string.format(
				"[DevFruitDevCommands] Ambiguous /%s target '%s' from %s. Use an exact player name or userId.",
				tostring(commandName),
				tostring(targetSpec),
				player.Name
			))
			return
		end

		warn(string.format(
			"[DevFruitDevCommands] Unknown /%s target '%s' from %s",
			tostring(commandName),
			tostring(targetSpec),
			player.Name
		))
		return
	end

	if targetPlayer == nil then
		warn(string.format(
			"[DevFruitDevCommands] /%s currently supports online players only. %s (userId=%d) is not in the server.",
			tostring(commandName),
			tostring(targetLabel),
			targetUserId
		))
		return
	end

	local ok, reason = TimeRewardsService.ResetClaims(targetPlayer)
	if not ok then
		warn(string.format(
			"[DevFruitDevCommands] Failed /%s for %s (%s)",
			tostring(commandName),
			targetPlayer.Name,
			tostring(reason)
		))
		return
	end

	print(string.format(
		"[DevFruitDevCommands] %s reset Gifts claims for %s via /%s",
		player.Name,
		targetPlayer.Name,
		tostring(commandName)
	))
end

local function getCommandNameAndArguments(rawText)
	local normalizedText = normalizeText(rawText)
	local commandName, argumentText = normalizedText:match("^/%s*(%S+)%s*(.*)$")
	if not commandName then
		return nil, nil, normalizedText
	end

	return commandName, argumentText or "", normalizedText
end

local function cleanFeedbackText(text)
	local value = trimText(tostring(text or ""))
	value = value:gsub("^%[DevFruitDevCommands%]%s*", "")
	value = value:gsub("^%[AdminCommandFlow%]%s*", "")
	return value
end

local function getWarningFeedbackStatus(warningText)
	if string.find(warningText, "Confirmation required", 1, true) then
		return "warning"
	end

	return "error"
end

local function executeAdminCommandHandler(player, commandName, source, normalizedText, handler)
	local defaultDetail = string.format("text=%s", normalizedText)
	local warnings = {}
	local previousWarnings = activeCommandWarnings
	activeCommandWarnings = warnings

	local ok, success, detail, status = pcall(handler)
	activeCommandWarnings = previousWarnings

	if not ok then
		AdminPermissions.LogCommandFailed(player, commandName, source, "error=" .. tostring(success))
		return
	end

	if typeof(success) == "table" then
		local result = success
		success = result.Success
		if success == nil then
			success = result.success
		end
		detail = result.Detail or result.detail or detail
		status = result.Status or result.status or status
	end

	local feedbackDetail = cleanFeedbackText(detail or defaultDetail)
	local commandOutcome = if success == true
		then "success"
		elseif success == false
		then "failed"
		elseif status == "warning" or success == "warning"
		then "warning"
		elseif status == "error" or status == "failed"
		then "failed"
		elseif status == "success"
		then "success"
		else nil

	if commandOutcome == "success" then
		AdminPermissions.LogCommandExecuted(player, commandName, source, feedbackDetail)
		return
	elseif commandOutcome == "failed" then
		AdminPermissions.LogCommandFailed(player, commandName, source, feedbackDetail)
		return
	elseif commandOutcome == "warning" then
		AdminPermissions.LogCommandWarning(player, commandName, source, feedbackDetail)
		return
	end

	if #warnings > 0 then
		local warningText = cleanFeedbackText(warnings[#warnings])
		if getWarningFeedbackStatus(warningText) == "warning" then
			AdminPermissions.LogCommandWarning(player, commandName, source, warningText)
		else
			AdminPermissions.LogCommandFailed(player, commandName, source, warningText)
		end
		return
	end

	AdminPermissions.LogCommandExecuted(player, commandName, source, feedbackDetail)
end

local function handleChatCommand(player, rawText, source)
	source = source or "chat"
	if not player then
		adminCommandFlowWarn("ignored command attempt source=%s reason=missing_player text=%s", tostring(source), tostring(rawText))
		return
	end

	local commandName, argumentText, normalizedText = getCommandNameAndArguments(rawText)
	if not commandName then
		if normalizedText:sub(1, 1) == "/" then
			adminCommandFlowLog(
				"ignored slash text source=%s player=%s userId=%d reason=no_command text=%s",
				tostring(source),
				player.Name,
				player.UserId,
				normalizedText
			)
		end
		return
	end

	if not ADMIN_COMMAND_NAMES[commandName] then
		adminCommandFlowLog(
			"ignored slash command source=%s player=%s userId=%d command=%s reason=not_admin_command text=%s",
			tostring(source),
			player.Name,
			player.UserId,
			commandName,
			normalizedText
		)
		return
	end

	AdminPermissions.LogCommandAttempt(player, commandName, source, string.format("text=%s", normalizedText))

	if not isAuthorized(player) then
		AdminPermissions.LogCommandRejected(player, commandName, source)
		return
	end

	if not markRecentCommand(player, normalizedText) then
		adminCommandFlowLog(
			"ignored duplicate admin command source=%s player=%s userId=%d command=%s text=%s",
			tostring(source),
			player.Name,
			player.UserId,
			commandName,
			normalizedText
		)
		return
	end

	adminCommandFlowLog(
		"accepted admin command source=%s player=%s userId=%d command=%s args=%s",
		tostring(source),
		player.Name,
		player.UserId,
		commandName,
		argumentText
	)

	if commandName == "fruit" then
		executeAdminCommandHandler(player, commandName, source, normalizedText, function()
			return processFruitCommand(player, argumentText)
		end)
		return
	end

	if commandName == "hitbox" then
		executeAdminCommandHandler(player, commandName, source, normalizedText, function()
			return processHitboxCommand(player, argumentText)
		end)
		return
	end

	if commandName == "hazards" or commandName == "hazard" then
		executeAdminCommandHandler(player, commandName, source, normalizedText, function()
			return processHazardsCommand(player, argumentText)
		end)
		return
	end

	if commandName == "boost" then
		executeAdminCommandHandler(player, commandName, source, normalizedText, function()
			return processBoostCommand(player, argumentText)
		end)
		return
	end

	if commandName == "speed" or commandName == "setspeed" then
		executeAdminCommandHandler(player, commandName, source, normalizedText, function()
			return processSpeedCommand(player, argumentText)
		end)
		return
	end

	if commandName == "rebirth" then
		executeAdminCommandHandler(player, commandName, source, normalizedText, function()
			return processRebirthCommand(player, argumentText)
		end)
		return
	end

	if commandName == "bounty" then
		executeAdminCommandHandler(player, commandName, source, normalizedText, function()
			return processBountyCommand(player, argumentText)
		end)
		return
	end

	if commandName == "spawn" then
		executeAdminCommandHandler(player, commandName, source, normalizedText, function()
			return processSpawnCommand(player, argumentText)
		end)
		return
	end

	if commandName == "give" then
		executeAdminCommandHandler(player, commandName, source, normalizedText, function()
			return processGiveCommand(player, argumentText)
		end)
		return
	end

	if commandName == "chest" then
		executeAdminCommandHandler(player, commandName, source, normalizedText, function()
			return processChestCommand(player, argumentText)
		end)
		return
	end

	if commandName == "shipreset" then
		executeAdminCommandHandler(player, commandName, source, normalizedText, function()
			return processShipResetCommand(player, argumentText)
		end)
		return
	end

	if commandName == "clear" then
		executeAdminCommandHandler(player, commandName, source, normalizedText, function()
			return processClearCommand(player, argumentText)
		end)
		return
	end

	if commandName == "tutorial" then
		executeAdminCommandHandler(player, commandName, source, normalizedText, function()
			return processTutorialCommand(player, argumentText)
		end)
		return
	end

	if commandName == "gifts" or commandName == "giftreset" then
		executeAdminCommandHandler(player, commandName, source, normalizedText, function()
			return processGiftResetCommand(player, argumentText, commandName)
		end)
		return
	end

	if commandName == "crewcanary" or commandName == "crewread" then
		executeAdminCommandHandler(player, commandName, source, normalizedText, function()
			return processCrewCanaryCommand(player, argumentText)
		end)
		return
	end

	if commandName == "wipeplayer" or commandName == "resetprogress" then
		executeAdminCommandHandler(player, commandName, source, normalizedText, function()
			return processWipePlayerCommand(player, argumentText, commandName)
		end)
		return
	end

	executeAdminCommandHandler(player, commandName, source, normalizedText, function()
		return processMoneyCommand(player, argumentText)
	end)
end

-- Admin panel execution stays server-authoritative by reusing the exact same
-- parser, permission checks, duplicate guard, and command handlers as chat.
adminCommandRequestEvent.OnServerEvent:Connect(function(player, rawText)
	if type(rawText) ~= "string" then
		AdminPermissions.LogCommandRejected(player, "adminPanelCommand", "AdminPanelRemote", "reason=invalid_payload")
		return
	end

	local commandText = rawText:gsub("\r", ""):gsub("\n", " ")
	commandText = commandText:match("^%s*(.-)%s*$") or ""
	if commandText == "" then
		return
	end
	commandText = commandText:sub(1, 240)
	if commandText:sub(1, 1) ~= "/" then
		commandText = "/" .. commandText
	end

	local commandName = getCommandNameAndArguments(commandText)
	if commandName == "admin" then
		AdminPermissions.HandleAdminCommand(player, commandText, "AdminPanelRemote")
		return
	end
	if commandName == "vip" then
		AdminPermissions.HandleVipTestCommand(player, commandText, "AdminPanelRemote")
		return
	end

	handleChatCommand(player, commandText, "AdminPanelRemote")
end)

local function hookPlayer(player)
	adminCommandFlowLog("hooking Player.Chatted player=%s userId=%d", player.Name, player.UserId)
	player.Chatted:Connect(function(message)
		adminCommandFlowLog("Player.Chatted fired player=%s userId=%d text=%s", player.Name, player.UserId, tostring(message))
		handleChatCommand(player, message, "Player.Chatted")
	end)
end

local function setupTextChatCommand()
	adminCommandFlowLog("setupTextChatCommand begin chatVersion=%s", tostring(TextChatService.ChatVersion))
	local commandsFolder = TextChatService:FindFirstChild("TextChatCommands") or TextChatService:WaitForChild("TextChatCommands", 10)
	if not commandsFolder then
		adminCommandFlowWarn("setupTextChatCommand failed reason=TextChatCommands_missing")
		return
	end
	adminCommandFlowLog("setupTextChatCommand found folder=%s children=%d", commandsFolder:GetFullName(), #commandsFolder:GetChildren())

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
			adminCommandFlowWarn("TextChatCommand triggered command=DevilFruitDevCommand reason=player_not_found textSourceUserId=%s text=%s", tostring(textSource and textSource.UserId), tostring(unfilteredText))
			return
		end

		local normalizedText = normalizeText(unfilteredText)
		if normalizedText:sub(1, 6) == "/fruit" then
			handleChatCommand(player, normalizedText, "TextChatCommand:DevilFruitDevCommand")
			return
		end

		local syntheticCommand = normalizedText ~= "" and ("/fruit " .. normalizedText) or "/fruit"
		handleChatCommand(player, syntheticCommand, "TextChatCommand:DevilFruitDevCommand")
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
			adminCommandFlowWarn("TextChatCommand triggered command=MoneyDevCommand reason=player_not_found textSourceUserId=%s text=%s", tostring(textSource and textSource.UserId), tostring(unfilteredText))
			return
		end

		local normalizedText = normalizeText(unfilteredText)
		if normalizedText:sub(1, 6) == "/money" or normalizedText:sub(1, 7) == "/ money" then
			handleChatCommand(player, normalizedText, "TextChatCommand:MoneyDevCommand")
			return
		end

		local syntheticCommand = normalizedText ~= "" and ("/money " .. normalizedText) or "/money"
		handleChatCommand(player, syntheticCommand, "TextChatCommand:MoneyDevCommand")
	end)

	local speedCommand = commandsFolder:FindFirstChild("SpeedDevCommand")
	if speedCommand and not speedCommand:IsA("TextChatCommand") then
		speedCommand:Destroy()
		speedCommand = nil
	end

	if not speedCommand then
		speedCommand = Instance.new("TextChatCommand")
		speedCommand.Name = "SpeedDevCommand"
		speedCommand.PrimaryAlias = "/speed"
		speedCommand.SecondaryAlias = "/setspeed"
		speedCommand.AutocompleteVisible = false
		speedCommand.Parent = commandsFolder
	end

	speedCommand.Triggered:Connect(function(textSource, unfilteredText)
		local player = textSource and Players:GetPlayerByUserId(textSource.UserId)
		if not player then
			adminCommandFlowWarn("TextChatCommand triggered command=SpeedDevCommand reason=player_not_found textSourceUserId=%s text=%s", tostring(textSource and textSource.UserId), tostring(unfilteredText))
			return
		end

		local normalizedText = normalizeText(unfilteredText)
		if normalizedText:sub(1, 6) == "/speed" or normalizedText:sub(1, 7) == "/ speed" or normalizedText:sub(1, 9) == "/setspeed" or normalizedText:sub(1, 10) == "/ setspeed" then
			handleChatCommand(player, normalizedText, "TextChatCommand:SpeedDevCommand")
			return
		end

		local syntheticCommand = normalizedText ~= "" and ("/speed " .. normalizedText) or "/speed"
		handleChatCommand(player, syntheticCommand, "TextChatCommand:SpeedDevCommand")
	end)

	local boostCommand = commandsFolder:FindFirstChild("BoostDevCommand")
	if boostCommand and not boostCommand:IsA("TextChatCommand") then
		boostCommand:Destroy()
		boostCommand = nil
	end

	if not boostCommand then
		boostCommand = Instance.new("TextChatCommand")
		boostCommand.Name = "BoostDevCommand"
		boostCommand.PrimaryAlias = "/boost"
		boostCommand.SecondaryAlias = "/boost"
		boostCommand.AutocompleteVisible = false
		boostCommand.Parent = commandsFolder
	end

	boostCommand.Triggered:Connect(function(textSource, unfilteredText)
		local player = textSource and Players:GetPlayerByUserId(textSource.UserId)
		if not player then
			adminCommandFlowWarn("TextChatCommand triggered command=BoostDevCommand reason=player_not_found textSourceUserId=%s text=%s", tostring(textSource and textSource.UserId), tostring(unfilteredText))
			return
		end

		local normalizedText = normalizeText(unfilteredText)
		if normalizedText:sub(1, 6) == "/boost" or normalizedText:sub(1, 7) == "/ boost" then
			handleChatCommand(player, normalizedText, "TextChatCommand:BoostDevCommand")
			return
		end

		local syntheticCommand = normalizedText ~= "" and ("/boost " .. normalizedText) or "/boost"
		handleChatCommand(player, syntheticCommand, "TextChatCommand:BoostDevCommand")
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
			adminCommandFlowWarn("TextChatCommand triggered command=RebirthDevCommand reason=player_not_found textSourceUserId=%s text=%s", tostring(textSource and textSource.UserId), tostring(unfilteredText))
			return
		end

		local normalizedText = normalizeText(unfilteredText)
		if normalizedText:sub(1, 8) == "/rebirth" or normalizedText:sub(1, 9) == "/ rebirth" then
			handleChatCommand(player, normalizedText, "TextChatCommand:RebirthDevCommand")
			return
		end

		local syntheticCommand = normalizedText ~= "" and ("/rebirth " .. normalizedText) or "/rebirth"
		handleChatCommand(player, syntheticCommand, "TextChatCommand:RebirthDevCommand")
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
			adminCommandFlowWarn("TextChatCommand triggered command=BountyDevCommand reason=player_not_found textSourceUserId=%s text=%s", tostring(textSource and textSource.UserId), tostring(unfilteredText))
			return
		end

		local normalizedText = normalizeText(unfilteredText)
		if normalizedText:sub(1, 7) == "/bounty" or normalizedText:sub(1, 8) == "/ bounty" then
			handleChatCommand(player, normalizedText, "TextChatCommand:BountyDevCommand")
			return
		end

		local syntheticCommand = normalizedText ~= "" and ("/bounty " .. normalizedText) or "/bounty"
		handleChatCommand(player, syntheticCommand, "TextChatCommand:BountyDevCommand")
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
			adminCommandFlowWarn("TextChatCommand triggered command=GiveDevCommand reason=player_not_found textSourceUserId=%s text=%s", tostring(textSource and textSource.UserId), tostring(unfilteredText))
			return
		end

		local normalizedText = normalizeText(unfilteredText)
		if normalizedText:sub(1, 5) == "/give" or normalizedText:sub(1, 6) == "/ give" then
			handleChatCommand(player, normalizedText, "TextChatCommand:GiveDevCommand")
			return
		end

		local syntheticCommand = normalizedText ~= "" and ("/give " .. normalizedText) or "/give"
		handleChatCommand(player, syntheticCommand, "TextChatCommand:GiveDevCommand")
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
			adminCommandFlowWarn("TextChatCommand triggered command=SpawnDevCommand reason=player_not_found textSourceUserId=%s text=%s", tostring(textSource and textSource.UserId), tostring(unfilteredText))
			return
		end

		local normalizedText = normalizeText(unfilteredText)
		if normalizedText:sub(1, 6) == "/spawn" or normalizedText:sub(1, 7) == "/ spawn" then
			handleChatCommand(player, normalizedText, "TextChatCommand:SpawnDevCommand")
			return
		end

		local syntheticCommand = normalizedText ~= "" and ("/spawn " .. normalizedText) or "/spawn"
		handleChatCommand(player, syntheticCommand, "TextChatCommand:SpawnDevCommand")
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
			adminCommandFlowWarn("TextChatCommand triggered command=ChestDevCommand reason=player_not_found textSourceUserId=%s text=%s", tostring(textSource and textSource.UserId), tostring(unfilteredText))
			return
		end

		local normalizedText = normalizeText(unfilteredText)
		if normalizedText:sub(1, 6) == "/chest" or normalizedText:sub(1, 7) == "/ chest" then
			handleChatCommand(player, normalizedText, "TextChatCommand:ChestDevCommand")
			return
		end

		local syntheticCommand = normalizedText ~= "" and ("/chest " .. normalizedText) or "/chest"
		handleChatCommand(player, syntheticCommand, "TextChatCommand:ChestDevCommand")
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
			adminCommandFlowWarn("TextChatCommand triggered command=ShipResetDevCommand reason=player_not_found textSourceUserId=%s text=%s", tostring(textSource and textSource.UserId), tostring(unfilteredText))
			return
		end

		local normalizedText = normalizeText(unfilteredText)
		if normalizedText:sub(1, 10) == "/shipreset" or normalizedText:sub(1, 11) == "/ shipreset" then
			handleChatCommand(player, normalizedText, "TextChatCommand:ShipResetDevCommand")
			return
		end

		local syntheticCommand = normalizedText ~= "" and ("/shipreset " .. normalizedText) or "/shipreset"
		handleChatCommand(player, syntheticCommand, "TextChatCommand:ShipResetDevCommand")
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
			adminCommandFlowWarn("TextChatCommand triggered command=ClearDevCommand reason=player_not_found textSourceUserId=%s text=%s", tostring(textSource and textSource.UserId), tostring(unfilteredText))
			return
		end

		local normalizedText = normalizeText(unfilteredText)
		if normalizedText:sub(1, 6) == "/clear" or normalizedText:sub(1, 7) == "/ clear" then
			handleChatCommand(player, normalizedText, "TextChatCommand:ClearDevCommand")
			return
		end

		local syntheticCommand = normalizedText ~= "" and ("/clear " .. normalizedText) or "/clear"
		handleChatCommand(player, syntheticCommand, "TextChatCommand:ClearDevCommand")
	end)

	local tutorialCommand = commandsFolder:FindFirstChild("TutorialDevCommand")
	if tutorialCommand and not tutorialCommand:IsA("TextChatCommand") then
		tutorialCommand:Destroy()
		tutorialCommand = nil
	end

	if not tutorialCommand then
		tutorialCommand = Instance.new("TextChatCommand")
		tutorialCommand.Name = "TutorialDevCommand"
		tutorialCommand.PrimaryAlias = "/tutorial"
		tutorialCommand.SecondaryAlias = "/tutorial"
		tutorialCommand.AutocompleteVisible = false
		tutorialCommand.Parent = commandsFolder
	end

	tutorialCommand.Triggered:Connect(function(textSource, unfilteredText)
		local player = textSource and Players:GetPlayerByUserId(textSource.UserId)
		if not player then
			adminCommandFlowWarn("TextChatCommand triggered command=TutorialDevCommand reason=player_not_found textSourceUserId=%s text=%s", tostring(textSource and textSource.UserId), tostring(unfilteredText))
			return
		end

		local normalizedText = normalizeText(unfilteredText)
		if normalizedText:sub(1, 9) == "/tutorial" or normalizedText:sub(1, 10) == "/ tutorial" then
			handleChatCommand(player, normalizedText, "TextChatCommand:TutorialDevCommand")
			return
		end

		local syntheticCommand = normalizedText ~= "" and ("/tutorial " .. normalizedText) or "/tutorial"
		handleChatCommand(player, syntheticCommand, "TextChatCommand:TutorialDevCommand")
	end)

	local giftsCommand = commandsFolder:FindFirstChild("GiftsDevCommand")
	if giftsCommand and not giftsCommand:IsA("TextChatCommand") then
		giftsCommand:Destroy()
		giftsCommand = nil
	end

	if not giftsCommand then
		giftsCommand = Instance.new("TextChatCommand")
		giftsCommand.Name = "GiftsDevCommand"
		giftsCommand.PrimaryAlias = "/gifts"
		giftsCommand.SecondaryAlias = "/giftreset"
		giftsCommand.AutocompleteVisible = false
		giftsCommand.Parent = commandsFolder
	end

	giftsCommand.Triggered:Connect(function(textSource, unfilteredText)
		local player = textSource and Players:GetPlayerByUserId(textSource.UserId)
		if not player then
			adminCommandFlowWarn("TextChatCommand triggered command=GiftsDevCommand reason=player_not_found textSourceUserId=%s text=%s", tostring(textSource and textSource.UserId), tostring(unfilteredText))
			return
		end

		local normalizedText = normalizeText(unfilteredText)
		if normalizedText:sub(1, 6) == "/gifts" or normalizedText:sub(1, 10) == "/giftreset" then
			handleChatCommand(player, normalizedText, "TextChatCommand:GiftsDevCommand")
			return
		end

		local syntheticCommand = normalizedText ~= "" and ("/gifts " .. normalizedText) or "/gifts"
		handleChatCommand(player, syntheticCommand, "TextChatCommand:GiftsDevCommand")
	end)

	local wipeCommand = commandsFolder:FindFirstChild("WipePlayerDevCommand")
	if wipeCommand and not wipeCommand:IsA("TextChatCommand") then
		wipeCommand:Destroy()
		wipeCommand = nil
	end

	if not wipeCommand then
		wipeCommand = Instance.new("TextChatCommand")
		wipeCommand.Name = "WipePlayerDevCommand"
		wipeCommand.PrimaryAlias = "/wipeplayer"
		wipeCommand.SecondaryAlias = "/resetprogress"
		wipeCommand.AutocompleteVisible = false
		wipeCommand.Parent = commandsFolder
	end

	wipeCommand.Triggered:Connect(function(textSource, unfilteredText)
		local player = textSource and Players:GetPlayerByUserId(textSource.UserId)
		if not player then
			adminCommandFlowWarn("TextChatCommand triggered command=WipePlayerDevCommand reason=player_not_found textSourceUserId=%s text=%s", tostring(textSource and textSource.UserId), tostring(unfilteredText))
			return
		end

		local normalizedText = normalizeText(unfilteredText)
		if normalizedText:sub(1, 11) == "/wipeplayer" or normalizedText:sub(1, 14) == "/resetprogress" then
			handleChatCommand(player, normalizedText, "TextChatCommand:WipePlayerDevCommand")
			return
		end

		local syntheticCommand = normalizedText ~= "" and ("/wipeplayer " .. normalizedText) or "/wipeplayer"
		handleChatCommand(player, syntheticCommand, "TextChatCommand:WipePlayerDevCommand")
	end)

	local hitboxCommand = commandsFolder:FindFirstChild("HitboxDevCommand")
	if hitboxCommand and not hitboxCommand:IsA("TextChatCommand") then
		hitboxCommand:Destroy()
		hitboxCommand = nil
	end

	if not hitboxCommand then
		hitboxCommand = Instance.new("TextChatCommand")
		hitboxCommand.Name = "HitboxDevCommand"
		hitboxCommand.PrimaryAlias = "/hitbox"
		hitboxCommand.SecondaryAlias = "/hitbox"
		hitboxCommand.AutocompleteVisible = false
		hitboxCommand.Parent = commandsFolder
	end

	hitboxCommand.Triggered:Connect(function(textSource, unfilteredText)
		local player = textSource and Players:GetPlayerByUserId(textSource.UserId)
		if not player then
			adminCommandFlowWarn("TextChatCommand triggered command=HitboxDevCommand reason=player_not_found textSourceUserId=%s text=%s", tostring(textSource and textSource.UserId), tostring(unfilteredText))
			return
		end

		local normalizedText = normalizeText(unfilteredText)
		if normalizedText:sub(1, 7) == "/hitbox" or normalizedText:sub(1, 8) == "/ hitbox" then
			handleChatCommand(player, normalizedText, "TextChatCommand:HitboxDevCommand")
			return
		end

		local syntheticCommand = normalizedText ~= "" and ("/hitbox " .. normalizedText) or "/hitbox"
		handleChatCommand(player, syntheticCommand, "TextChatCommand:HitboxDevCommand")
	end)

	local hazardsCommand = commandsFolder:FindFirstChild("HazardsDevCommand")
	if hazardsCommand and not hazardsCommand:IsA("TextChatCommand") then
		hazardsCommand:Destroy()
		hazardsCommand = nil
	end

	if not hazardsCommand then
		hazardsCommand = Instance.new("TextChatCommand")
		hazardsCommand.Name = "HazardsDevCommand"
		hazardsCommand.PrimaryAlias = "/hazards"
		hazardsCommand.SecondaryAlias = "/hazard"
		hazardsCommand.AutocompleteVisible = false
		hazardsCommand.Parent = commandsFolder
	end

	hazardsCommand.Triggered:Connect(function(textSource, unfilteredText)
		local player = textSource and Players:GetPlayerByUserId(textSource.UserId)
		if not player then
			adminCommandFlowWarn("TextChatCommand triggered command=HazardsDevCommand reason=player_not_found textSourceUserId=%s text=%s", tostring(textSource and textSource.UserId), tostring(unfilteredText))
			return
		end

		local normalizedText = normalizeText(unfilteredText)
		if normalizedText:sub(1, 8) == "/hazards" or normalizedText:sub(1, 9) == "/ hazards" or normalizedText:sub(1, 7) == "/hazard" or normalizedText:sub(1, 8) == "/ hazard" then
			handleChatCommand(player, normalizedText, "TextChatCommand:HazardsDevCommand")
			return
		end

		local syntheticCommand = normalizedText ~= "" and ("/hazards " .. normalizedText) or "/hazards"
		handleChatCommand(player, syntheticCommand, "TextChatCommand:HazardsDevCommand")
	end)

	adminCommandFlowLog("setupTextChatCommand complete registeredAdminTextChatCommands=16")
end

for _, player in ipairs(Players:GetPlayers()) do
	hookPlayer(player)
end

Players.PlayerAdded:Connect(hookPlayer)
adminCommandFlowLog("PlayerAdded listener connected for admin chat commands")
setupTextChatCommand()
