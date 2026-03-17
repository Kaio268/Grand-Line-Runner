local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local TextChatService = game:GetService("TextChatService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DevilFruitService = require(ServerScriptService.Modules:WaitForChild("DevilFruitService"))
local DevilFruitInventoryService = require(ServerScriptService.Modules:WaitForChild("DevilFruitInventoryService"))
local GrandLineRushChestToolService = require(ServerScriptService.Modules:WaitForChild("GrandLineRushChestToolService"))
local GrandLineRushVerticalSliceService = require(ServerScriptService.Modules:WaitForChild("GrandLineRushVerticalSliceService"))
local GrandLineRushCorridorRunController = require(ServerScriptService.Modules:WaitForChild("GrandLineRushCorridorRunController"))
local DataManager = require(ServerScriptService:WaitForChild("Data"):WaitForChild("DataManager"))
local DevilFruitConfig = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("DevilFruits"))
local GrandLineRushEconomy = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("GrandLineRushEconomy"))
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

for _, userId in ipairs(ADMIN_USER_IDS) do
	adminSet[userId] = true
end

local function normalizeText(text)
	return tostring(text or ""):lower():match("^%s*(.-)%s*$") or ""
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

local function getDisplayedMoney(player)
	local moneyValue = CurrencyUtil.findPrimaryValueObject(player)
	if moneyValue then
		return moneyValue.Value
	end

	local storedMoney = DataManager:GetValue(player, CurrencyUtil.getPrimaryPath())
	return (typeof(storedMoney) == "number") and storedMoney or 0
end

local function processMoneyCommand(player, argumentText)
	if not isAuthorized(player) then
		return
	end

	local amount = parseSignedAmount(argumentText)
	if typeof(amount) ~= "number" or amount == 0 or amount ~= amount then
		warn(string.format("[DevFruitDevCommands] Invalid /money amount '%s' from %s", tostring(argumentText), player.Name))
		return
	end

	if amount < 0 then
		amount = math.ceil(amount)
	else
		amount = math.floor(amount)
	end

	local newMoney = DataManager:AdjustValue(player, CurrencyUtil.getPrimaryPath(), amount)
	if typeof(newMoney) ~= "number" then
		newMoney = getDisplayedMoney(player)
	end

	print(string.format(
		"[DevFruitDevCommands] %s adjusted Doubloons by %d (new balance=%d)",
		player.Name,
		math.floor(amount),
		math.floor(newMoney)
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

	if commandName ~= "fruit" and commandName ~= "money" and commandName ~= "spawn" and commandName ~= "chest" then
		return
	end

	if not markRecentCommand(player, normalizedText) then
		return
	end

	if commandName == "fruit" then
		processFruitCommand(player, argumentText)
		return
	end

	if commandName == "spawn" then
		processSpawnCommand(player, argumentText)
		return
	end

	if commandName == "chest" then
		processChestCommand(player, argumentText)
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
end

for _, player in ipairs(Players:GetPlayers()) do
	hookPlayer(player)
end

Players.PlayerAdded:Connect(hookPlayer)
setupTextChatCommand()
