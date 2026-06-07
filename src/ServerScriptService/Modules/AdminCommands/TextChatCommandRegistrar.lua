local TextChatCommandRegistrar = {}

local COMMANDS = {
	{
		Name = "DevilFruitDevCommand",
		PrimaryAlias = "/fruit",
		SecondaryAlias = "/fruit",
		Prefixes = { "/fruit" },
	},
	{
		Name = "MoneyDevCommand",
		PrimaryAlias = "/beli",
		SecondaryAlias = "/money",
		Prefixes = { "/beli", "/ beli", "/money", "/ money" },
	},
	{
		Name = "SpeedDevCommand",
		PrimaryAlias = "/speed",
		SecondaryAlias = "/setspeed",
		Prefixes = { "/speed", "/ speed", "/setspeed", "/ setspeed" },
	},
	{
		Name = "BoostDevCommand",
		PrimaryAlias = "/boost",
		SecondaryAlias = "/boost",
		Prefixes = { "/boost", "/ boost" },
	},
	{
		Name = "RebirthDevCommand",
		PrimaryAlias = "/rebirth",
		SecondaryAlias = "/rebirth",
		Prefixes = { "/rebirth", "/ rebirth" },
	},
	{
		Name = "BountyDevCommand",
		PrimaryAlias = "/bounty",
		SecondaryAlias = "/bounty",
		Prefixes = { "/bounty", "/ bounty" },
	},
	{
		Name = "GiveDevCommand",
		PrimaryAlias = "/give",
		SecondaryAlias = "/give",
		Prefixes = { "/give", "/ give" },
	},
	{
		Name = "SpawnDevCommand",
		PrimaryAlias = "/spawn",
		SecondaryAlias = "/spawn",
		Prefixes = { "/spawn", "/ spawn" },
	},
	{
		Name = "ChestDevCommand",
		PrimaryAlias = "/chest",
		SecondaryAlias = "/chest",
		Prefixes = { "/chest", "/ chest" },
	},
	{
		Name = "ShipResetDevCommand",
		PrimaryAlias = "/shipreset",
		SecondaryAlias = "/shipreset",
		Prefixes = { "/shipreset", "/ shipreset" },
	},
	{
		Name = "ClearDevCommand",
		PrimaryAlias = "/clear",
		SecondaryAlias = "/clear",
		Prefixes = { "/clear", "/ clear" },
	},
	{
		Name = "TutorialDevCommand",
		PrimaryAlias = "/tutorial",
		SecondaryAlias = "/tutorial",
		Prefixes = { "/tutorial", "/ tutorial" },
	},
	{
		Name = "GiftsDevCommand",
		PrimaryAlias = "/gifts",
		SecondaryAlias = "/giftreset",
		Prefixes = { "/gifts", "/giftreset" },
	},
	{
		Name = "WipePlayerDevCommand",
		PrimaryAlias = "/wipeplayer",
		SecondaryAlias = "/resetprogress",
		Prefixes = { "/wipeplayer", "/resetprogress" },
	},
	{
		Name = "HitboxDevCommand",
		PrimaryAlias = "/hitbox",
		SecondaryAlias = "/hitbox",
		Prefixes = { "/hitbox", "/ hitbox" },
	},
	{
		Name = "InvincibleDevCommand",
		PrimaryAlias = "/invincible",
		SecondaryAlias = "/invincible",
		Prefixes = { "/invincible", "/ invincible" },
	},
	{
		Name = "HazardsDevCommand",
		PrimaryAlias = "/hazards",
		SecondaryAlias = "/hazard",
		Prefixes = { "/hazards", "/ hazards", "/hazard", "/ hazard" },
	},
	{
		Name = "ChestRushDevCommand",
		PrimaryAlias = "/chestrush",
		SecondaryAlias = "/chestrush",
		Prefixes = { "/chestrush", "/ chestrush" },
	},
	{
		Name = "RestartDevCommand",
		PrimaryAlias = "/restart",
		SecondaryAlias = "/restart",
		Prefixes = { "/restart", "/ restart" },
	},
}

local function startsWithAnyPrefix(text, prefixes)
	for _, prefix in ipairs(prefixes) do
		if text:sub(1, #prefix) == prefix then
			return true
		end
	end

	return false
end

local function ensureCommand(commandsFolder, commandSpec)
	local command = commandsFolder:FindFirstChild(commandSpec.Name)
	if command and not command:IsA("TextChatCommand") then
		command:Destroy()
		command = nil
	end

	if not command then
		command = Instance.new("TextChatCommand")
		command.Name = commandSpec.Name
		command.Parent = commandsFolder
	end

	command.PrimaryAlias = commandSpec.PrimaryAlias
	command.SecondaryAlias = commandSpec.SecondaryAlias
	command.AutocompleteVisible = false

	return command
end

function TextChatCommandRegistrar.Setup(options)
	local textChatService = options.TextChatService
	local players = options.Players
	local normalizeText = options.NormalizeText
	local handleChatCommand = options.HandleChatCommand
	local log = options.Log
	local warnFlow = options.Warn

	log("setupTextChatCommand begin chatVersion=%s", tostring(textChatService.ChatVersion))

	local commandsFolder = textChatService:FindFirstChild("TextChatCommands")
		or textChatService:WaitForChild("TextChatCommands", 10)
	if not commandsFolder then
		warnFlow("setupTextChatCommand failed reason=TextChatCommands_missing")
		return
	end

	log("setupTextChatCommand found folder=%s children=%d", commandsFolder:GetFullName(), #commandsFolder:GetChildren())

	for _, commandSpec in ipairs(COMMANDS) do
		local command = ensureCommand(commandsFolder, commandSpec)
		command.Triggered:Connect(function(textSource, unfilteredText)
			local player = textSource and players:GetPlayerByUserId(textSource.UserId)
			if not player then
				warnFlow(
					"TextChatCommand triggered command=%s reason=player_not_found textSourceUserId=%s text=%s",
					commandSpec.Name,
					tostring(textSource and textSource.UserId),
					tostring(unfilteredText)
				)
				return
			end

			local normalizedText = normalizeText(unfilteredText)
			local source = "TextChatCommand:" .. commandSpec.Name
			if startsWithAnyPrefix(normalizedText, commandSpec.Prefixes) then
				handleChatCommand(player, normalizedText, source)
				return
			end

			local syntheticCommand = if normalizedText ~= ""
				then commandSpec.PrimaryAlias .. " " .. normalizedText
				else commandSpec.PrimaryAlias
			handleChatCommand(player, syntheticCommand, source)
		end)
	end

	log("setupTextChatCommand complete registeredAdminTextChatCommands=%d", #COMMANDS)
end

return TextChatCommandRegistrar
