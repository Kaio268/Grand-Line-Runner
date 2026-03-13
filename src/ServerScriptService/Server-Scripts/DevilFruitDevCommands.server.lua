local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local TextChatService = game:GetService("TextChatService")

local DevilFruitService = require(ServerScriptService.Modules:WaitForChild("DevilFruitService"))
local DevilFruitInventoryService = require(ServerScriptService.Modules:WaitForChild("DevilFruitInventoryService"))
local DataManager = require(ServerScriptService:WaitForChild("Data"):WaitForChild("DataManager"))

local ADMIN_USER_IDS = {
	1103783585,
	2442286217,
	780333260,
}

local FRUIT_ALIASES = {
	mera = "Mera Mera no Mi",
	hie = "Hie Hie no Mi",
}

local RECENT_COMMAND_WINDOW = 0.4

local adminSet = {}
local recentCommands = {}

for _, userId in ipairs(ADMIN_USER_IDS) do
	adminSet[userId] = true
end

local function normalizeText(text)
	return tostring(text or ""):lower():match("^%s*(.-)%s*$") or ""
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

local function processFruitCommand(player, argumentText)
	if not isAuthorized(player) then
		return
	end

	local normalizedArgument = normalizeText(argumentText)
	if normalizedArgument == "" then
		warn(string.format("[DevFruitDevCommands] %s used /fruit without an argument", player.Name))
		return
	end

	local directEquipArgument = normalizedArgument:match("^equip%s+(.+)$")
	if directEquipArgument then
		local directFruit = FRUIT_ALIASES[normalizeText(directEquipArgument)]
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

	local targetFruit = FRUIT_ALIASES[normalizedArgument]
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
	local leaderstats = player:FindFirstChild("leaderstats")
	local moneyValue = leaderstats and leaderstats:FindFirstChild("Money")
	if moneyValue and moneyValue:IsA("NumberValue") then
		return moneyValue.Value
	end

	local storedMoney = DataManager:GetValue(player, "leaderstats.Money")
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

	local newMoney = DataManager:AdjustValue(player, "leaderstats.Money", amount)
	if typeof(newMoney) ~= "number" then
		newMoney = getDisplayedMoney(player)
	end

	print(string.format(
		"[DevFruitDevCommands] %s adjusted Money by %d (new balance=%d)",
		player.Name,
		math.floor(amount),
		math.floor(newMoney)
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

local function handleChatCommand(player, rawText)
	if not player then
		return
	end

	local commandName, argumentText, normalizedText = getCommandNameAndArguments(rawText)
	if not commandName then
		return
	end

	if commandName ~= "fruit" and commandName ~= "money" then
		return
	end

	if not markRecentCommand(player, normalizedText) then
		return
	end

	if commandName == "fruit" then
		processFruitCommand(player, argumentText)
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
end

for _, player in ipairs(Players:GetPlayers()) do
	hookPlayer(player)
end

Players.PlayerAdded:Connect(hookPlayer)
setupTextChatCommand()
