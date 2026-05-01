local Players = game:GetService("Players")

local AdminConfig = require(script.Parent:WaitForChild("AdminConfig"))

local AdminPermissions = {}

local admins = {}
local adminIds = {}

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
			admins[numericUserId] = true
			table.insert(adminIds, numericUserId)
		elseif enabled == true then
			warn(string.format(
				"[AdminPermissions] Ignored admin config entry reason=invalid_user_id key=%s keyType=%s",
				tostring(userId),
				typeof(userId)
			))
		end
	end
end

table.sort(adminIds)

local function getAdminIdsText()
	local parts = {}
	for _, userId in ipairs(adminIds) do
		table.insert(parts, tostring(userId))
	end
	return table.concat(parts, ",")
end

print(string.format(
	"[AdminPermissions] Admin config loaded adminCount=%d adminUserIds=%s",
	#adminIds,
	getAdminIdsText()
))

function AdminPermissions.GetAdminStatus(player: Player?): (boolean, string)
	if player == nil then
		return false, "missing_player"
	end

	local numericUserId = tonumber(player.UserId)
	if numericUserId == nil then
		return false, "missing_user_id"
	end

	numericUserId = math.floor(numericUserId)
	if admins[numericUserId] == true then
		return true, "user_id_listed_in_admin_config"
	end

	return false, "user_id_not_listed_in_admin_config"
end

function AdminPermissions.IsAdmin(player: Player?): boolean
	local isAdmin = AdminPermissions.GetAdminStatus(player)
	return isAdmin == true
end

function AdminPermissions.LogPlayerResolved(player: Player)
	local isAdmin, reason = AdminPermissions.GetAdminStatus(player)
	print(string.format(
		"[AdminPermissions] Player joined name=%s displayName=%s userId=%d isAdmin=%s reason=%s configuredAdminUserIds=%s",
		player.Name,
		player.DisplayName,
		player.UserId,
		tostring(isAdmin),
		reason,
		getAdminIdsText()
	))
end

function AdminPermissions.LogAdminStatusRequest(player: Player?, source: string?)
	local isAdmin, reason = AdminPermissions.GetAdminStatus(player)
	if player then
		print(string.format(
			"[AdminPermissions] Admin status requested source=%s player=%s displayName=%s userId=%d isAdmin=%s reason=%s",
			tostring(source or "unknown"),
			player.Name,
			player.DisplayName,
			player.UserId,
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
			"[AdminPermissions] Admin command attempted command=%s source=%s player=%s displayName=%s userId=%d isAdmin=%s reason=%s%s",
			tostring(commandName),
			tostring(source or "unknown"),
			player.Name,
			player.DisplayName,
			player.UserId,
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
			"[AdminPermissions] Rejected admin command command=%s source=%s player=%s displayName=%s userId=%d isAdmin=false reason=%s%s",
			tostring(commandName),
			tostring(source or "unknown"),
			player.Name,
			player.DisplayName,
			player.UserId,
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
		"[AdminPermissions] Admin command executed command=%s source=%s player=%s displayName=%s userId=%d isAdmin=%s reason=%s%s",
		tostring(commandName),
		tostring(source or "unknown"),
		player.Name,
		player.DisplayName,
		player.UserId,
		tostring(isAdmin),
		reason,
		detail and (" " .. detail) or ""
	))
end

for _, player in ipairs(Players:GetPlayers()) do
	AdminPermissions.LogPlayerResolved(player)
end

Players.PlayerAdded:Connect(function(player)
	AdminPermissions.LogPlayerResolved(player)
end)

return AdminPermissions
