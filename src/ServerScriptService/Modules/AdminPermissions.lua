local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextChatService = game:GetService("TextChatService")

local AdminConfig = require(script.Parent:WaitForChild("AdminConfig"))
local VIPTestOverrides = require(script.Parent:WaitForChild("VIPTestOverrides"))
local PopUpModule = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("PopUpModule"))

local AdminPermissions = {}

local SuperAdmins = {
	[5448954557] = true, -- YonkoKaio
	[4843576528] = true, -- ChefChris
}

local configuredAdmins = {}
local configuredAdminIds = {}
local superAdminIds = {}
local activeAdmins = {}
local chatConnections = {}
local textChatCommandConnection = nil
local vipTextChatCommandConnection = nil
local adminStateChanged = Instance.new("BindableEvent")

local POPUP_STROKE = Color3.fromRGB(0, 0, 0)
local POPUP_INFO = Color3.fromRGB(105, 225, 255)
local POPUP_WARNING = Color3.fromRGB(255, 205, 90)

AdminPermissions.AdminStateChanged = adminStateChanged.Event

if typeof(AdminConfig) ~= "table" then
	warn(string.format(
		"[AdminPermissions] Admin config load failed reason=invalid_config_type configType=%s",
		typeof(AdminConfig)
	))
elseif typeof(AdminConfig.Admins) ~= "table" then
	warn(string.format(
		"[AdminPermissions] Admin config load failed reason=missing_admins_table adminsType=%s",
		typeof(AdminConfig.Admins)
	))
else
	for userId, enabled in pairs(AdminConfig.Admins) do
		local numericUserId = tonumber(userId)
		if numericUserId and enabled == true then
			numericUserId = math.floor(numericUserId)
			configuredAdmins[numericUserId] = true
			table.insert(configuredAdminIds, numericUserId)
		elseif enabled == true then
			warn(string.format(
				"[AdminPermissions] Ignored admin config entry reason=invalid_user_id key=%s keyType=%s",
				tostring(userId),
				typeof(userId)
			))
		end
	end
end

for userId in pairs(SuperAdmins) do
	table.insert(superAdminIds, userId)
end

table.sort(configuredAdminIds)
table.sort(superAdminIds)

local function getIdsText(ids)
	local parts = {}
	for _, userId in ipairs(ids) do
		parts[#parts + 1] = tostring(userId)
	end
	return table.concat(parts, ",")
end

local function getUserId(player: Player?): number?
	if player == nil then
		return nil
	end

	local numericUserId = tonumber(player.UserId)
	if numericUserId == nil then
		return nil
	end

	return math.floor(numericUserId)
end

local function isConfiguredAdmin(player: Player?): boolean
	local userId = getUserId(player)
	return userId ~= nil and configuredAdmins[userId] == true
end

local function getDefaultAdminState(player: Player): boolean
	return AdminPermissions.IsSuperAdmin(player) or isConfiguredAdmin(player)
end

local function getVipValue(player: Player?): boolean
	if player == nil then
		return false
	end

	local passes = player:FindFirstChild("Passes")
	local vip = passes and passes:FindFirstChild("VIP")
	return vip ~= nil and vip:IsA("BoolValue") and vip.Value == true
end

local function sendVipTestMessage(player: Player, message: string, isWarning: boolean?)
	local color = if isWarning == true then POPUP_WARNING else POPUP_INFO
	PopUpModule:Server_SendPopUp(player, message, color, POPUP_STROKE, 4, false)
end

local function setAdminInternal(player: Player, enabled: boolean, source: string?): (boolean, boolean)
	local userId = getUserId(player)
	if userId == nil then
		return false, false
	end

	enabled = enabled == true
	local previous = activeAdmins[userId] == true
	activeAdmins[userId] = enabled
	local changed = previous ~= enabled

	adminStateChanged:Fire(player, enabled, source or "unknown", changed)

	return true, changed
end

local function parseAdminToggleCommand(message: string): boolean?
	local normalized = tostring(message or ""):match("^%s*(.-)%s*$")
	normalized = string.lower(normalized or "")

	if normalized == "/admin true" then
		return true
	elseif normalized == "/admin false" then
		return false
	end

	return nil
end

local function parseVipTestCommand(message: string): string?
	local normalized = tostring(message or ""):match("^%s*(.-)%s*$")
	normalized = string.lower(normalized or "")

	if normalized == "/vip true" then
		return "true"
	elseif normalized == "/vip false" then
		return "false"
	elseif normalized == "/vip state" then
		return "state"
	end

	return nil
end

local function handleAdminChatCommand(player: Player, message: string, source: string?)
	local requestedState = parseAdminToggleCommand(message)
	if requestedState == nil then
		return
	end

	source = source or "unknown"
	AdminPermissions.LogCommandAttempt(player, "admin", source, string.format("enabled=%s", tostring(requestedState)))
	if not AdminPermissions.IsSuperAdmin(player) then
		AdminPermissions.LogCommandRejected(player, "admin", source, "reason=not_super_admin")
		return
	end

	AdminPermissions.SetAdmin(player, requestedState)
	AdminPermissions.LogCommandExecuted(player, "admin", source, string.format("enabled=%s", tostring(requestedState)))
end

local function handleVipTestCommand(player: Player, message: string, source: string?)
	local requestedAction = parseVipTestCommand(message)
	if requestedAction == nil then
		return
	end

	source = source or "unknown"
	AdminPermissions.LogCommandAttempt(player, "vip", source, string.format("action=%s", requestedAction))
	if not AdminPermissions.IsSuperAdmin(player) then
		AdminPermissions.LogCommandRejected(player, "vip", source, "reason=not_super_admin")
		return
	end

	if requestedAction == "true" then
		VIPTestOverrides.SetOverride(player, true)
		sendVipTestMessage(player, "VIP TEST OVERRIDE: ON. You are testing as VIP.")
	elseif requestedAction == "false" then
		VIPTestOverrides.SetOverride(player, false)
		sendVipTestMessage(player, "VIP TEST OVERRIDE: OFF. You are testing as non-VIP.", true)
	else
		local override = VIPTestOverrides.GetOverride(player)
		local effectiveVip, sourceName = VIPTestOverrides.GetEffectiveVip(player)
		local realVip = VIPTestOverrides.GetRealVip(player)
		local overrideText = if override == nil then "CLEARED" elseif override == true then "ON" else "OFF"
		sendVipTestMessage(
			player,
			string.format(
				"VIP TEST OVERRIDE: STATE %s. Effective VIP: %s. Real VIP: %s. Source: %s.",
				overrideText,
				tostring(effectiveVip),
				tostring(realVip),
				sourceName
			)
		)
	end

	local effectiveVip, sourceName = VIPTestOverrides.GetEffectiveVip(player)
	print(string.format(
		"[VIP TEST] %s action=%s override=%s realVIP=%s effectiveVIP=%s source=%s",
		player.Name,
		requestedAction,
		tostring(VIPTestOverrides.GetOverride(player)),
		tostring(VIPTestOverrides.GetRealVip(player)),
		tostring(effectiveVip),
		sourceName
	))
	AdminPermissions.LogCommandExecuted(player, "vip", source, string.format("action=%s", requestedAction))
end

local function bindAdminTextChatCommand()
	local command = TextChatService:FindFirstChild("AdminToggleCommand")
	if command and not command:IsA("TextChatCommand") then
		command:Destroy()
		command = nil
	end

	if not command then
		command = Instance.new("TextChatCommand")
		command.Name = "AdminToggleCommand"
		command.PrimaryAlias = "/admin"
		command.SecondaryAlias = ""
		command.AutocompleteVisible = false
		command.Parent = TextChatService
	end

	if textChatCommandConnection then
		textChatCommandConnection:Disconnect()
	end

	textChatCommandConnection = command.Triggered:Connect(function(textSource, unfilteredText)
		local player = textSource and Players:GetPlayerByUserId(textSource.UserId)
		if not player then
			warn(string.format(
				"[AdminPermissions] Admin TextChatCommand ignored reason=player_not_found textSourceUserId=%s",
				tostring(textSource and textSource.UserId)
			))
			return
		end

		local normalizedText = tostring(unfilteredText or ""):lower():match("^%s*(.-)%s*$") or ""
		if normalizedText:sub(1, 6) == "/admin" or normalizedText:sub(1, 7) == "/ admin" then
			handleAdminChatCommand(player, normalizedText, "TextChatCommand:AdminToggleCommand")
			return
		end

		local syntheticCommand = normalizedText ~= "" and ("/admin " .. normalizedText) or "/admin"
		handleAdminChatCommand(player, syntheticCommand, "TextChatCommand:AdminToggleCommand")
	end)
end

local function bindVipTextChatCommand()
	local command = TextChatService:FindFirstChild("VipTestCommand")
	if command and not command:IsA("TextChatCommand") then
		command:Destroy()
		command = nil
	end

	if not command then
		command = Instance.new("TextChatCommand")
		command.Name = "VipTestCommand"
		command.PrimaryAlias = "/vip"
		command.SecondaryAlias = ""
		command.AutocompleteVisible = false
		command.Parent = TextChatService
	end

	if vipTextChatCommandConnection then
		vipTextChatCommandConnection:Disconnect()
	end

	vipTextChatCommandConnection = command.Triggered:Connect(function(textSource, unfilteredText)
		local player = textSource and Players:GetPlayerByUserId(textSource.UserId)
		if not player then
			warn(string.format(
				"[AdminPermissions] VIP TextChatCommand ignored reason=player_not_found textSourceUserId=%s",
				tostring(textSource and textSource.UserId)
			))
			return
		end

		local normalizedText = tostring(unfilteredText or ""):lower():match("^%s*(.-)%s*$") or ""
		if normalizedText:sub(1, 4) == "/vip" or normalizedText:sub(1, 5) == "/ vip" then
			handleVipTestCommand(player, normalizedText, "TextChatCommand:VipTestCommand")
			return
		end

		local syntheticCommand = normalizedText ~= "" and ("/vip " .. normalizedText) or "/vip"
		handleVipTestCommand(player, syntheticCommand, "TextChatCommand:VipTestCommand")
	end)
end

local function setupAdminTextChatCommand()
	bindAdminTextChatCommand()
	bindVipTextChatCommand()
	print("[AdminPermissions] Registered /admin TextChatCommand under TextChatService")
	print("[AdminPermissions] Registered /vip TextChatCommand under TextChatService")
end

local function bindPlayer(player: Player)
	local userId = getUserId(player)
	if userId ~= nil then
		activeAdmins[userId] = getDefaultAdminState(player)
	end

	if chatConnections[player] then
		chatConnections[player]:Disconnect()
	end
	chatConnections[player] = player.Chatted:Connect(function(message)
		handleAdminChatCommand(player, message, "Player.Chatted")
		handleVipTestCommand(player, message, "Player.Chatted")
	end)

	AdminPermissions.LogPlayerResolved(player)
end

local function unbindPlayer(player: Player)
	local connection = chatConnections[player]
	if connection then
		connection:Disconnect()
		chatConnections[player] = nil
	end

	local userId = getUserId(player)
	if userId ~= nil then
		activeAdmins[userId] = nil
	end
end

print(string.format(
	"[AdminPermissions] Admin config loaded adminCount=%d adminUserIds=%s superAdminCount=%d superAdminUserIds=%s",
	#configuredAdminIds,
	getIdsText(configuredAdminIds),
	#superAdminIds,
	getIdsText(superAdminIds)
))

function AdminPermissions.IsSuperAdmin(player: Player?): boolean
	local userId = getUserId(player)
	return userId ~= nil and SuperAdmins[userId] == true
end

function AdminPermissions.SetAdmin(player: Player, enabled: boolean): boolean
	if not AdminPermissions.IsSuperAdmin(player) then
		return false
	end

	local didSet, changed = setAdminInternal(player, enabled == true, "SetAdmin")
	if didSet then
		print(string.format("[ADMIN] %s set admin = %s", player.Name, tostring(enabled == true)))
		local isAdmin = AdminPermissions.IsAdmin(player)
		local effectiveVip, sourceName = VIPTestOverrides.GetEffectiveVip(player)
		local realVip = getVipValue(player)
		print(string.format(
			"[ADMIN DEBUG] player=%s userId=%d isSuperAdmin=%s isAdmin=%s passesVIP=%s effectiveVIP=%s effectiveVIPSource=%s computedVIPBarrierBypass=%s changed=%s",
			player.Name,
			player.UserId,
			tostring(AdminPermissions.IsSuperAdmin(player)),
			tostring(isAdmin),
			tostring(realVip),
			tostring(effectiveVip),
			sourceName,
			tostring(isAdmin or effectiveVip),
			tostring(changed)
		))
	end
	return didSet
end

function AdminPermissions.GetAdminStatus(player: Player?): (boolean, string)
	if player == nil then
		return false, "missing_player"
	end

	local userId = getUserId(player)
	if userId == nil then
		return false, "missing_user_id"
	end

	if activeAdmins[userId] == true then
		return true, "active_admin_enabled"
	end

	if AdminPermissions.IsSuperAdmin(player) then
		return false, "super_admin_inactive"
	end

	if configuredAdmins[userId] == true then
		return false, "configured_admin_inactive"
	end

	return false, "user_id_not_active_admin"
end

function AdminPermissions.IsAdmin(player: Player?): boolean
	local isAdmin = AdminPermissions.GetAdminStatus(player)
	return isAdmin == true
end

function AdminPermissions.LogPlayerResolved(player: Player)
	local isAdmin, reason = AdminPermissions.GetAdminStatus(player)
	print(string.format(
		"[AdminPermissions] Player joined name=%s displayName=%s userId=%d isSuperAdmin=%s isAdmin=%s reason=%s configuredAdminUserIds=%s superAdminUserIds=%s",
		player.Name,
		player.DisplayName,
		player.UserId,
		tostring(AdminPermissions.IsSuperAdmin(player)),
		tostring(isAdmin),
		reason,
		getIdsText(configuredAdminIds),
		getIdsText(superAdminIds)
	))
end

function AdminPermissions.LogAdminStatusRequest(player: Player?, source: string?)
	local isAdmin, reason = AdminPermissions.GetAdminStatus(player)
	if player then
		print(string.format(
			"[AdminPermissions] Admin status requested source=%s player=%s displayName=%s userId=%d isSuperAdmin=%s isAdmin=%s reason=%s",
			tostring(source or "unknown"),
			player.Name,
			player.DisplayName,
			player.UserId,
			tostring(AdminPermissions.IsSuperAdmin(player)),
			tostring(isAdmin),
			reason
		))
	else
		warn(string.format(
			"[AdminPermissions] Admin status requested source=%s player=nil isAdmin=false reason=%s",
			tostring(source or "unknown"),
			reason
		))
	end
end

function AdminPermissions.LogCommandAttempt(player: Player?, commandName: string, source: string?, detail: string?)
	local isAdmin, reason = AdminPermissions.GetAdminStatus(player)
	if player then
		print(string.format(
			"[AdminPermissions] Admin command attempted command=%s source=%s player=%s displayName=%s userId=%d isSuperAdmin=%s isAdmin=%s reason=%s%s",
			tostring(commandName),
			tostring(source or "unknown"),
			player.Name,
			player.DisplayName,
			player.UserId,
			tostring(AdminPermissions.IsSuperAdmin(player)),
			tostring(isAdmin),
			reason,
			detail and (" " .. detail) or ""
		))
	else
		warn(string.format(
			"[AdminPermissions] Admin command attempted command=%s source=%s player=nil isAdmin=false reason=%s%s",
			tostring(commandName),
			tostring(source or "unknown"),
			reason,
			detail and (" " .. detail) or ""
		))
	end
end

function AdminPermissions.LogCommandRejected(player: Player?, commandName: string, source: string?, detail: string?)
	local _, reason = AdminPermissions.GetAdminStatus(player)
	if player then
		warn(string.format(
			"[AdminPermissions] Rejected admin command command=%s source=%s player=%s displayName=%s userId=%d isSuperAdmin=%s isAdmin=false reason=%s%s",
			tostring(commandName),
			tostring(source or "unknown"),
			player.Name,
			player.DisplayName,
			player.UserId,
			tostring(AdminPermissions.IsSuperAdmin(player)),
			reason,
			detail and (" " .. detail) or ""
		))
	else
		warn(string.format(
			"[AdminPermissions] Rejected admin command command=%s source=%s player=nil isAdmin=false reason=%s%s",
			tostring(commandName),
			tostring(source or "unknown"),
			reason,
			detail and (" " .. detail) or ""
		))
	end
end

function AdminPermissions.LogCommandExecuted(player: Player, commandName: string, source: string?, detail: string?)
	local isAdmin, reason = AdminPermissions.GetAdminStatus(player)
	print(string.format(
		"[AdminPermissions] Admin command executed command=%s source=%s player=%s displayName=%s userId=%d isSuperAdmin=%s isAdmin=%s reason=%s%s",
		tostring(commandName),
		tostring(source or "unknown"),
		player.Name,
		player.DisplayName,
		player.UserId,
		tostring(AdminPermissions.IsSuperAdmin(player)),
		tostring(isAdmin),
		reason,
		detail and (" " .. detail) or ""
	))
end

for _, player in ipairs(Players:GetPlayers()) do
	bindPlayer(player)
end

setupAdminTextChatCommand()
Players.PlayerAdded:Connect(bindPlayer)
Players.PlayerRemoving:Connect(unbindPlayer)

return AdminPermissions
