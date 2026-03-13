local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local TextChatService = game:GetService("TextChatService")

local DevilFruitService = require(ServerScriptService.Modules:WaitForChild("DevilFruitService"))
local DevilFruitInventoryService = require(ServerScriptService.Modules:WaitForChild("DevilFruitInventoryService"))

local ADMIN_USER_IDS = {
	1103783585,
	2442286217,
	780333260,
}

local FRUIT_ALIASES = {
	mera = "Mera Mera no Mi",
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

local function handleChatCommand(player, rawText)
	if not player then
		return
	end

	local normalizedText = normalizeText(rawText)
	local argumentText = normalizedText:match("^/fruit%s+(.+)$")
	if argumentText == nil then
		if normalizedText == "/fruit" then
			argumentText = ""
		else
			return
		end
	end

	if not markRecentCommand(player, normalizedText) then
		return
	end

	processFruitCommand(player, argumentText)
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
end

for _, player in ipairs(Players:GetPlayers()) do
	hookPlayer(player)
end

Players.PlayerAdded:Connect(hookPlayer)
setupTextChatCommand()
