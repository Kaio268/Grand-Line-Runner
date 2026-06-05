local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MessagingService = game:GetService("MessagingService")
local TextChatService = game:GetService("TextChatService")

local AdminConfig = require(script.Parent:WaitForChild("AdminConfig"))
local AdminStaffRoleStore = require(script.Parent:WaitForChild("AdminStaffRoleStore"))
local AdminAuditLog = require(script.Parent:WaitForChild("AdminAuditLog"))
local TesterRoleStore = require(script.Parent:WaitForChild("TesterRoleStore"))
local VIPTestOverrides = require(script.Parent:WaitForChild("VIPTestOverrides"))
local PopUpModule = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("PopUpModule"))

local AdminPermissions = {}

local OwnerRoot = {
	[5448954557] = true, -- YonkoKaio
}

local baseSuperAdmins = {
	[5448954557] = true, -- YonkoKaio
	[4843576528] = true, -- ChefChris
	[3412846835] = true,
	[4844244696] = true,
}

local SuperAdmins = {}
local baseConfiguredAdmins = {}
local baseConfiguredAdminIds = {}
local configuredAdmins = {}
local configuredAdminIds = {}
local baseConfiguredTesters = {}
local baseConfiguredTesterIds = {}
local configuredTesters = {}
local configuredTesterIds = {}
local staffRoleOverrides = {
	AdminsAdded = {},
	AdminsRemoved = {},
	SuperAdminsAdded = {},
	SuperAdminsRemoved = {},
	UpdatedAt = 0,
	UpdatedBy = 0,
	Available = false,
}
local testerRoleOverrides = {
	Added = {},
	Removed = {},
	UpdatedAt = 0,
	UpdatedBy = 0,
	Available = false,
}
local activePublicTesterTitleByUserId = {}
local ownerRootIds = {}
local superAdminIds = {}
local activeAdmins = {}
local userInfoCache = {}
local chatConnections = {}
local testerTitleConnections = {}
local textChatCommandConnection = nil
local vipTextChatCommandConnection = nil
local adminStateChanged = Instance.new("BindableEvent")
local staffRoleStateChanged = Instance.new("BindableEvent")
local testerStateChanged = Instance.new("BindableEvent")

local POPUP_STROKE = Color3.fromRGB(0, 0, 0)
local POPUP_INFO = Color3.fromRGB(105, 225, 255)
local POPUP_WARNING = Color3.fromRGB(255, 205, 90)
local POPUP_SUCCESS = Color3.fromRGB(105, 255, 172)
local POPUP_ERROR = Color3.fromRGB(255, 92, 92)
local POPUP_DURATION_SECONDS = 4
local POPUP_MESSAGE_LIMIT = 140
local ADMIN_COMMAND_FEEDBACK_EVENT_NAME = "AdminCommandFeedback"
local STAFF_ROLE_UPDATE_TOPIC = "AdminStaffRolesV1"
local TESTER_ROLE_UPDATE_TOPIC = "AdminTesterRolesV1"
local TESTER_STATUS_CHANGED_EVENT_NAME = "TesterStatusChanged"
local EQUIPPED_TITLE_ATTRIBUTE = "EquippedTitleId"

local function getOrCreateRemoteEvent(remoteName: string): RemoteEvent
	local remote = ReplicatedStorage:FindFirstChild(remoteName)
	if remote and not remote:IsA("RemoteEvent") then
		remote:Destroy()
		remote = nil
	end

	if not remote then
		remote = Instance.new("RemoteEvent")
		remote.Name = remoteName
		remote.Parent = ReplicatedStorage
	end

	return remote
end

local adminCommandFeedbackEvent = getOrCreateRemoteEvent(ADMIN_COMMAND_FEEDBACK_EVENT_NAME)
local testerStatusChangedEvent = getOrCreateRemoteEvent(TESTER_STATUS_CHANGED_EVENT_NAME)

local COMMAND_DISPLAY_NAMES = {
	admin = "Admin toggle",
	adminConsole = "Admin console",
	adminRoster = "Admin roster",
	announcement = "Announcement",
	boost = "Boost",
	bounty = "Bounty",
	beli = "Beli",
	chest = "Chest",
	clear = "Clear inventory",
	fruit = "Devil Fruit",
	giftreset = "Gift reset",
	gifts = "Gifts",
	give = "Resource grant",
	hitbox = "Ability and hazard hitboxes",
	invincible = "Admin invincibility",
	mainEvent = "Main event",
	money = "Beli",
	rebirth = "Rebirth",
	resetprogress = "Reset progress",
	restart = "Server restart",
	serverLuck = "Server luck",
	setspeed = "Speed",
	shipreset = "Ship reset",
	spawn = "Spawn",
	speed = "Speed",
	staffRole = "Staff role",
	testerRole = "Tester role",
	tutorial = "Tutorial reset",
	vip = "VIP test override",
	wipeplayer = "Wipe player",
}

local function getCommandDisplayName(commandName: string): string
	return COMMAND_DISPLAY_NAMES[commandName] or tostring(commandName)
end

local function formatFeedbackDetail(detail: string?): string
	local text = tostring(detail or ""):match("^%s*(.-)%s*$") or ""
	if text:sub(1, 5) == "text=" then
		return text:sub(6)
	end
	return text
end

local function truncateFeedbackText(text: string, limit: number): string
	if #text <= limit then
		return text
	end

	return text:sub(1, math.max(1, limit - 3)) .. "..."
end

local function getFeedbackPopupColor(status: string): Color3
	if status == "error" or status == "rejected" then
		return POPUP_ERROR
	elseif status == "warning" then
		return POPUP_WARNING
	end

	return POPUP_SUCCESS
end

local function sendCommandFeedback(player: Player?, status: string, commandName: string, source: string?, detail: string?)
	if player == nil or player.Parent ~= Players then
		return
	end

	local displayName = getCommandDisplayName(commandName)
	local detailText = formatFeedbackDetail(detail)
	local isAdmin, adminStatusReason = AdminPermissions.GetAdminStatus(player)
	local verb
	if status == "rejected" then
		verb = "rejected"
	elseif status == "error" then
		verb = "failed"
	elseif status == "warning" then
		verb = "needs attention"
	else
		verb = "confirmed"
	end
	local message
	if detailText ~= "" then
		message = string.format("%s %s: %s", displayName, verb, detailText)
	else
		message = string.format("%s %s.", displayName, verb)
	end

	adminCommandFeedbackEvent:FireClient(player, {
		Status = status,
		CommandName = commandName,
		DisplayName = displayName,
		Source = source or "unknown",
		Detail = detailText,
		IsAdmin = isAdmin,
		IsSuperAdmin = AdminPermissions.IsSuperAdmin(player),
		AdminStatusReason = adminStatusReason,
		Message = message,
		SentAt = os.time(),
	})

	if not (commandName == "vip" and status == "success") then
		PopUpModule:Server_SendPopUp(
			player,
			truncateFeedbackText(message, POPUP_MESSAGE_LIMIT),
			getFeedbackPopupColor(status),
			POPUP_STROKE,
			POPUP_DURATION_SECONDS,
			status == "error" or status == "rejected"
		)
	end
end

AdminPermissions.AdminStateChanged = adminStateChanged.Event
AdminPermissions.StaffRoleStateChanged = staffRoleStateChanged.Event
AdminPermissions.TesterStateChanged = testerStateChanged.Event

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
			baseConfiguredAdmins[numericUserId] = true
			table.insert(baseConfiguredAdminIds, numericUserId)
		elseif enabled == true then
			warn(string.format(
				"[AdminPermissions] Ignored admin config entry reason=invalid_user_id key=%s keyType=%s",
				tostring(userId),
				typeof(userId)
			))
		end
	end
end

if typeof(AdminConfig) == "table" and AdminConfig.Testers ~= nil then
	if typeof(AdminConfig.Testers) ~= "table" then
		warn(string.format(
			"[AdminPermissions] Tester config load failed reason=invalid_testers_table testersType=%s",
			typeof(AdminConfig.Testers)
		))
	else
		for userId, enabled in pairs(AdminConfig.Testers) do
			local numericUserId = tonumber(userId)
			if numericUserId and enabled == true then
				numericUserId = math.floor(numericUserId)
				baseConfiguredTesters[numericUserId] = true
				table.insert(baseConfiguredTesterIds, numericUserId)
			elseif enabled == true then
				warn(string.format(
					"[AdminPermissions] Ignored tester config entry reason=invalid_user_id key=%s keyType=%s",
					tostring(userId),
					typeof(userId)
				))
			end
		end
	end
end

for userId in pairs(OwnerRoot) do
	table.insert(ownerRootIds, userId)
end

for userId in pairs(baseSuperAdmins) do
	SuperAdmins[userId] = true
	table.insert(superAdminIds, userId)
end

for userId in pairs(baseConfiguredAdmins) do
	configuredAdmins[userId] = true
	table.insert(configuredAdminIds, userId)
end

table.sort(ownerRootIds)
table.sort(configuredAdminIds)
table.sort(baseConfiguredAdminIds)
table.sort(baseConfiguredTesterIds)
table.sort(superAdminIds)

local function getIdsText(ids)
	local parts = {}
	for _, userId in ipairs(ids) do
		parts[#parts + 1] = tostring(userId)
	end
	return table.concat(parts, ",")
end

local function getPublicTesterTitleId(): string
	if typeof(AdminConfig) ~= "table" then
		return "Tester"
	end

	local titleId = tostring(AdminConfig.PublicTesterTitleId or ""):match("^%s*(.-)%s*$") or ""
	if titleId == "" then
		return "Tester"
	end

	return titleId
end

local function normalizeTitleId(titleId): string
	if typeof(titleId) ~= "string" then
		return ""
	end

	return titleId:match("^%s*(.-)%s*$") or ""
end

local function readEquippedTitleId(player: Player?): string
	if player == nil then
		return ""
	end

	local attributeTitleId = normalizeTitleId(player:GetAttribute(EQUIPPED_TITLE_ATTRIBUTE))
	if attributeTitleId ~= "" then
		return attributeTitleId
	end

	local titlesFolder = player:FindFirstChild("Titles")
	local equippedValue = titlesFolder and titlesFolder:FindFirstChild("Equipped")
	if equippedValue and equippedValue:IsA("StringValue") then
		return normalizeTitleId(equippedValue.Value)
	end

	return ""
end

local function isPublicTesterTitleEnabled(): boolean
	return typeof(AdminConfig) == "table" and AdminConfig.EnablePublicTesterTitle == true
end

local function isTesterUserId(userId): boolean
	local numericUserId = math.floor(tonumber(userId) or 0)
	return numericUserId > 0 and configuredTesters[numericUserId] == true
end

local function emitTesterStateChanged(player: Player?, userId, source: string?)
	local numericUserId = math.floor(tonumber(userId) or (player and player.UserId) or 0)
	if numericUserId <= 0 then
		return
	end

	local isTester = isTesterUserId(numericUserId)
	local payload = {
		UserId = numericUserId,
		IsTester = isTester,
		Source = source or "unknown",
		SentAt = os.time(),
	}

	testerStateChanged:Fire(player, payload)
	if player and player.Parent == Players then
		testerStatusChangedEvent:FireClient(player, payload)
	end
end

local function emitTesterStateChangedForAll(source: string?)
	for _, player in ipairs(Players:GetPlayers()) do
		emitTesterStateChanged(player, player.UserId, source)
	end
end

local function updatePublicTesterTitleState(player: Player?, source: string?)
	if player == nil or player.Parent ~= Players then
		return
	end

	local userId = math.floor(tonumber(player.UserId) or 0)
	if userId <= 0 then
		return
	end

	local equippedTitleId = readEquippedTitleId(player)
	local active = isPublicTesterTitleEnabled()
		and equippedTitleId ~= ""
		and equippedTitleId == getPublicTesterTitleId()
	local previous = activePublicTesterTitleByUserId[userId] == true

	if active then
		activePublicTesterTitleByUserId[userId] = true
	else
		activePublicTesterTitleByUserId[userId] = nil
	end

	if previous ~= active then
		emitTesterStateChanged(player, userId, source or "tester_title_changed")
	end
end

local function addSortedUnique(ids, seen, userId)
	local numericUserId = math.floor(tonumber(userId) or 0)
	if numericUserId <= 0 or seen[numericUserId] == true then
		return
	end

	seen[numericUserId] = true
	table.insert(ids, numericUserId)
end

local function isOverrideRemoved(removed, userId): boolean
	return typeof(removed) == "table" and removed[tostring(userId)] == true
end

local function rebuildEffectiveStaffRoles()
	SuperAdmins = {}
	superAdminIds = {}
	configuredAdmins = {}
	configuredAdminIds = {}

	local seenSuperAdmins = {}
	local seenAdmins = {}
	local superAdminsAdded = if typeof(staffRoleOverrides.SuperAdminsAdded) == "table"
		then staffRoleOverrides.SuperAdminsAdded
		else {}
	local superAdminsRemoved = if typeof(staffRoleOverrides.SuperAdminsRemoved) == "table"
		then staffRoleOverrides.SuperAdminsRemoved
		else {}
	local adminsAdded = if typeof(staffRoleOverrides.AdminsAdded) == "table" then staffRoleOverrides.AdminsAdded else {}
	local adminsRemoved = if typeof(staffRoleOverrides.AdminsRemoved) == "table" then staffRoleOverrides.AdminsRemoved else {}

	for userId in pairs(OwnerRoot) do
		SuperAdmins[userId] = true
		addSortedUnique(superAdminIds, seenSuperAdmins, userId)
	end

	for userId in pairs(baseSuperAdmins) do
		if OwnerRoot[userId] == true or not isOverrideRemoved(superAdminsRemoved, userId) then
			SuperAdmins[userId] = true
			addSortedUnique(superAdminIds, seenSuperAdmins, userId)
		end
	end

	for userId, enabled in pairs(superAdminsAdded) do
		local numericUserId = tonumber(userId)
		if numericUserId and enabled == true then
			numericUserId = math.floor(numericUserId)
			if numericUserId > 0 and not isOverrideRemoved(superAdminsRemoved, numericUserId) then
				SuperAdmins[numericUserId] = true
				addSortedUnique(superAdminIds, seenSuperAdmins, numericUserId)
			end
		end
	end

	for userId in pairs(baseConfiguredAdmins) do
		if SuperAdmins[userId] ~= true and not isOverrideRemoved(adminsRemoved, userId) then
			configuredAdmins[userId] = true
			addSortedUnique(configuredAdminIds, seenAdmins, userId)
		end
	end

	for userId, enabled in pairs(adminsAdded) do
		local numericUserId = tonumber(userId)
		if numericUserId and enabled == true then
			numericUserId = math.floor(numericUserId)
			if numericUserId > 0
				and SuperAdmins[numericUserId] ~= true
				and not isOverrideRemoved(adminsRemoved, numericUserId) then
				configuredAdmins[numericUserId] = true
				addSortedUnique(configuredAdminIds, seenAdmins, numericUserId)
			end
		end
	end

	table.sort(superAdminIds)
	table.sort(configuredAdminIds)
end

local function applyStaffRoleOverrides(state)
	staffRoleOverrides = if typeof(state) == "table" then state else staffRoleOverrides
	rebuildEffectiveStaffRoles()
end

local function loadStaffRoleOverrides(keepCurrentOnFailure: boolean?)
	local state = AdminStaffRoleStore.Load()
	if state.Available == false and keepCurrentOnFailure == true and staffRoleOverrides.Available == true then
		warn("[AdminPermissions] Keeping existing staff role overrides after reload failure.")
		return false
	end

	applyStaffRoleOverrides(state)
	return state.Available == true
end

local function publishStaffRoleUpdate(actorUserId)
	task.spawn(function()
		pcall(function()
			MessagingService:PublishAsync(STAFF_ROLE_UPDATE_TOPIC, {
				UpdatedAt = os.time(),
				UpdatedBy = math.floor(tonumber(actorUserId) or 0),
			})
		end)
	end)
end

local function rebuildEffectiveTesters()
	configuredTesters = {}
	configuredTesterIds = {}

	local seen = {}
	local removed = if typeof(testerRoleOverrides.Removed) == "table" then testerRoleOverrides.Removed else {}
	local added = if typeof(testerRoleOverrides.Added) == "table" then testerRoleOverrides.Added else {}

	for userId in pairs(baseConfiguredTesters) do
		if removed[tostring(userId)] ~= true then
			configuredTesters[userId] = true
			addSortedUnique(configuredTesterIds, seen, userId)
		end
	end

	for userId, enabled in pairs(added) do
		local numericUserId = tonumber(userId)
		if numericUserId and enabled == true then
			numericUserId = math.floor(numericUserId)
			if removed[tostring(numericUserId)] ~= true then
				configuredTesters[numericUserId] = true
				addSortedUnique(configuredTesterIds, seen, numericUserId)
			end
		end
	end

	table.sort(configuredTesterIds)
end

local function applyTesterRoleOverrides(state)
	testerRoleOverrides = if typeof(state) == "table" then state else testerRoleOverrides
	rebuildEffectiveTesters()
end

local function loadTesterRoleOverrides(keepCurrentOnFailure: boolean?)
	local state = TesterRoleStore.Load()
	if state.Available == false and keepCurrentOnFailure == true and testerRoleOverrides.Available == true then
		warn("[AdminPermissions] Keeping existing tester role overrides after reload failure.")
		return false
	end

	applyTesterRoleOverrides(state)
	return state.Available == true
end

local function publishTesterRoleUpdate(actorUserId)
	task.spawn(function()
		pcall(function()
			MessagingService:PublishAsync(TESTER_ROLE_UPDATE_TOPIC, {
				UpdatedAt = os.time(),
				UpdatedBy = math.floor(tonumber(actorUserId) or 0),
			})
		end)
	end)
end

local function getTesterSource(userId: number): string
	local numericUserId = math.floor(tonumber(userId) or 0)
	local parts = {}
	local isStatic = baseConfiguredTesters[numericUserId] == true
	local isAdded = typeof(testerRoleOverrides.Added) == "table"
		and testerRoleOverrides.Added[tostring(numericUserId)] == true

	if isStatic then
		table.insert(parts, "Configured Tester")
	end
	if isAdded then
		table.insert(parts, "Persistent Tester")
	end

	return table.concat(parts, " + ")
end

local function getTesterManageBlockedReason(userId: number): string?
	local numericUserId = math.floor(tonumber(userId) or 0)
	if numericUserId <= 0 then
		return "invalid_user_id"
	end

	if SuperAdmins[numericUserId] == true then
		return "super_admin_locked"
	end

	if configuredAdmins[numericUserId] == true then
		return "admin_locked"
	end

	local onlinePlayer = Players:GetPlayerByUserId(numericUserId)
	if onlinePlayer and AdminPermissions.IsAdmin(onlinePlayer) then
		return "active_admin_locked"
	end

	return nil
end

loadStaffRoleOverrides(false)
loadTesterRoleOverrides(false)

local ROLE_LEVELS = {
	Normal = 0,
	Tester = 1,
	Admin = 2,
	SuperAdmin = 3,
	OwnerRoot = 4,
}

local ROLE_DISPLAY_NAMES = {
	Normal = "Player",
	Tester = "Tester",
	Admin = "Admin",
	SuperAdmin = "SuperAdmin",
	OwnerRoot = "OwnerRoot",
}

local function getUserIdFromSubject(subject): number?
	local numericUserId
	if typeof(subject) == "Instance" and subject:IsA("Player") then
		numericUserId = tonumber(subject.UserId)
	else
		numericUserId = tonumber(subject)
	end

	if numericUserId == nil then
		return nil
	end

	numericUserId = math.floor(numericUserId)
	if numericUserId <= 0 then
		return nil
	end

	return numericUserId
end

local function getRoleNameForUserId(userId): string
	local numericUserId = getUserIdFromSubject(userId)
	if numericUserId == nil then
		return "Normal"
	end

	if OwnerRoot[numericUserId] == true then
		return "OwnerRoot"
	end
	if SuperAdmins[numericUserId] == true then
		return "SuperAdmin"
	end
	if configuredAdmins[numericUserId] == true then
		return "Admin"
	end
	if isTesterUserId(numericUserId) then
		return "Tester"
	end

	return "Normal"
end

local function getRoleLevelForUserId(userId): number
	return ROLE_LEVELS[getRoleNameForUserId(userId)] or ROLE_LEVELS.Normal
end

local function getCachedUserInfo(userId: number, onlinePlayer: Player?)
	local numericUserId = math.floor(tonumber(userId) or 0)
	if onlinePlayer then
		local info = {
			Username = onlinePlayer.Name,
			DisplayName = onlinePlayer.DisplayName,
		}
		userInfoCache[numericUserId] = info
		return info
	end

	local cached = userInfoCache[numericUserId]
	if typeof(cached) == "table" then
		return cached
	end

	local fallbackName = "User " .. tostring(numericUserId)
	local resolved = {
		Username = fallbackName,
		DisplayName = fallbackName,
	}

	local userInfoOk, userInfos = pcall(function()
		return Players:GetUserInfosByUserIdsAsync({ numericUserId })
	end)
	if userInfoOk and typeof(userInfos) == "table" and typeof(userInfos[1]) == "table" then
		local userInfo = userInfos[1]
		local username = tostring(userInfo.Username or userInfo.Name or "")
		local displayName = tostring(userInfo.DisplayName or "")
		if username ~= "" then
			resolved.Username = username
			resolved.DisplayName = if displayName ~= "" then displayName else username
			userInfoCache[numericUserId] = resolved
			return resolved
		end
	end

	local nameOk, username = pcall(function()
		return Players:GetNameFromUserIdAsync(numericUserId)
	end)
	if nameOk and typeof(username) == "string" and username ~= "" then
		resolved.Username = username
		resolved.DisplayName = username
	end

	userInfoCache[numericUserId] = resolved
	return resolved
end

local function canManageRoleByUserId(actorUserId: number?, targetUserId: number?, roleName: string): (boolean, string?)
	local actorId = getUserIdFromSubject(actorUserId)
	local targetId = getUserIdFromSubject(targetUserId)
	if actorId == nil then
		return false, "invalid_actor"
	end
	if targetId == nil then
		return false, "invalid_target"
	end
	if actorId == targetId then
		return false, "cannot_modify_self"
	end
	if OwnerRoot[targetId] == true then
		return false, "owner_root_locked"
	end

	local normalizedRole = tostring(roleName or "")
	if normalizedRole == "SuperAdmin" then
		if OwnerRoot[actorId] ~= true then
			return false, "owner_root_required"
		end
		return true, nil
	end

	if normalizedRole == "Admin" or normalizedRole == "Tester" then
		if SuperAdmins[actorId] ~= true then
			return false, "super_admin_required"
		end
		if getRoleLevelForUserId(targetId) >= ROLE_LEVELS.SuperAdmin then
			return false, "target_role_locked"
		end
		return true, nil
	end

	return false, "invalid_role"
end

local function canModerateByUserId(actorUserId: number?, targetUserId: number?, actionName: string?): (boolean, string?)
	local actorId = getUserIdFromSubject(actorUserId)
	local targetId = getUserIdFromSubject(targetUserId)
	if actorId == nil then
		return false, "invalid_actor"
	end
	if targetId == nil then
		return false, "invalid_target"
	end
	if actorId == targetId then
		return false, "cannot_target_self"
	end
	if tostring(actionName or "") ~= "Kick" then
		return false, "unsupported_action"
	end
	if Players:GetPlayerByUserId(targetId) == nil then
		return false, "target_offline"
	end

	local actorLevel = getRoleLevelForUserId(actorId)
	local targetLevel = getRoleLevelForUserId(targetId)
	if actorLevel < ROLE_LEVELS.Admin then
		return false, "admin_required"
	end
	if actorLevel <= targetLevel then
		return false, "target_role_too_high"
	end

	local actorPlayer = Players:GetPlayerByUserId(actorId)
	if actorLevel == ROLE_LEVELS.Admin and not AdminPermissions.IsAdmin(actorPlayer) then
		return false, "active_admin_required"
	end

	return true, nil
end

local function addRoleCapabilities(entry, viewerUserId: number?)
	local userId = math.floor(tonumber(entry.UserId) or 0)
	local canGrantTester = canManageRoleByUserId(viewerUserId, userId, "Tester")
	local canGrantAdmin = canManageRoleByUserId(viewerUserId, userId, "Admin")
	local canGrantSuperAdmin = canManageRoleByUserId(viewerUserId, userId, "SuperAdmin")
	local canKick = canModerateByUserId(viewerUserId, userId, "Kick")

	entry.CanGrantTester = canGrantTester == true and entry.IsConfiguredTester ~= true
	entry.CanRemoveTester = canGrantTester == true and entry.IsConfiguredTester == true
	entry.CanAddTester = entry.CanGrantTester
	entry.CanGrantAdmin = canGrantAdmin == true and entry.IsConfiguredAdmin ~= true and entry.IsSuperAdmin ~= true
	entry.CanRemoveAdmin = canGrantAdmin == true and entry.IsConfiguredAdmin == true
	entry.CanGrantSuperAdmin = canGrantSuperAdmin == true and entry.IsSuperAdmin ~= true
	entry.CanRemoveSuperAdmin = canGrantSuperAdmin == true and entry.IsSuperAdmin == true and entry.IsOwnerRoot ~= true
	entry.CanKick = canKick == true
end

local function buildRosterEntry(userId: number, roleName: string, viewerUserId: number?)
	local numericUserId = math.floor(tonumber(userId) or 0)
	local onlinePlayer = Players:GetPlayerByUserId(numericUserId)
	local userInfo = getCachedUserInfo(numericUserId, onlinePlayer)
	local isActiveAdmin = false
	local adminStatusReason = "offline"
	local isConfiguredTesterRole = configuredTesters[numericUserId] == true
	local isTesterTitleActive = activePublicTesterTitleByUserId[numericUserId] == true
	local isTester = isConfiguredTesterRole
	local testerBlockReason = getTesterManageBlockedReason(numericUserId)

	if onlinePlayer then
		isActiveAdmin, adminStatusReason = AdminPermissions.GetAdminStatus(onlinePlayer)
	elseif SuperAdmins[numericUserId] == true then
		adminStatusReason = "super_admin_offline"
	elseif configuredAdmins[numericUserId] == true then
		adminStatusReason = "configured_admin_offline"
	end

	local roleNameForUser = getRoleNameForUserId(numericUserId)
	local entry = {
		UserId = numericUserId,
		Username = userInfo.Username,
		DisplayName = userInfo.DisplayName,
		Role = roleName,
		HighestRole = roleNameForUser,
		RoleLevel = getRoleLevelForUserId(numericUserId),
		RoleDisplayName = ROLE_DISPLAY_NAMES[roleNameForUser] or "Player",
		IsOwnerRoot = OwnerRoot[numericUserId] == true,
		IsSuperAdmin = SuperAdmins[numericUserId] == true,
		IsConfiguredAdmin = configuredAdmins[numericUserId] == true,
		IsBaseAdmin = baseConfiguredAdmins[numericUserId] == true,
		IsPersistedAdmin = typeof(staffRoleOverrides.AdminsAdded) == "table"
			and staffRoleOverrides.AdminsAdded[tostring(numericUserId)] == true,
		IsBaseSuperAdmin = baseSuperAdmins[numericUserId] == true,
		IsPersistedSuperAdmin = typeof(staffRoleOverrides.SuperAdminsAdded) == "table"
			and staffRoleOverrides.SuperAdminsAdded[tostring(numericUserId)] == true,
		IsTester = isTester,
		IsConfiguredTester = isConfiguredTesterRole,
		IsBaseTester = baseConfiguredTesters[numericUserId] == true,
		IsPersistedTester = typeof(testerRoleOverrides.Added) == "table"
			and testerRoleOverrides.Added[tostring(numericUserId)] == true,
		IsTesterTitleActive = isTesterTitleActive,
		TesterSource = getTesterSource(numericUserId),
		CanAddTester = testerBlockReason == nil and not isConfiguredTesterRole,
		CanRemoveTester = testerBlockReason == nil and isConfiguredTesterRole,
		TesterManageBlockedReason = testerBlockReason,
		IsOnline = onlinePlayer ~= nil,
		IsActiveAdmin = isActiveAdmin == true,
		AdminStatusReason = adminStatusReason,
	}

	addRoleCapabilities(entry, viewerUserId)
	return entry
end

local function buildRosterList(ids, roleName: string, viewerUserId: number?)
	local entries = {}
	for index, userId in ipairs(ids) do
		entries[index] = buildRosterEntry(userId, roleName, viewerUserId)
	end
	return entries
end

local function buildTesterRosterList(viewerUserId: number?)
	local ids = {}
	local seen = {}

	for _, userId in ipairs(configuredTesterIds) do
		addSortedUnique(ids, seen, userId)
	end

	table.sort(ids)
	return buildRosterList(ids, "Tester", viewerUserId)
end

local function buildAllPlayerRosterList(viewerUserId: number?)
	local entries = {}
	for _, onlinePlayer in ipairs(Players:GetPlayers()) do
		table.insert(entries, buildRosterEntry(onlinePlayer.UserId, "Player", viewerUserId))
	end

	table.sort(entries, function(left, right)
		local leftName = string.lower(tostring(left.Username or left.DisplayName or ""))
		local rightName = string.lower(tostring(right.Username or right.DisplayName or ""))
		if leftName == rightName then
			return tonumber(left.UserId) < tonumber(right.UserId)
		end
		return leftName < rightName
	end)

	return entries
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

local function resolveUserIdFromTarget(target): (number?, string?)
	local text = tostring(target or ""):gsub("\r", ""):gsub("\n", " ")
	text = text:match("^%s*(.-)%s*$") or ""
	if text == "" then
		return nil, "target_required"
	end

	local numericUserId = tonumber(text)
	if numericUserId ~= nil then
		numericUserId = math.floor(numericUserId)
		if numericUserId > 0 then
			return numericUserId, nil
		end

		return nil, "invalid_user_id"
	end

	text = text:gsub("^@", "")
	local lowered = string.lower(text)
	for _, onlinePlayer in ipairs(Players:GetPlayers()) do
		if string.lower(onlinePlayer.Name) == lowered or string.lower(onlinePlayer.DisplayName) == lowered then
			return onlinePlayer.UserId, nil
		end
	end

	local ok, userIdOrError = pcall(function()
		return Players:GetUserIdFromNameAsync(text)
	end)

	if ok and tonumber(userIdOrError) ~= nil then
		return math.floor(tonumber(userIdOrError)), nil
	end

	return nil, "target_unresolved"
end

local getDefaultAdminState
local setAdminInternal

local function isConfiguredAdmin(player: Player?): boolean
	local userId = getUserId(player)
	return userId ~= nil and configuredAdmins[userId] == true
end

local function canViewAdminConsole(player: Player?): boolean
	local userId = getUserId(player)
	if userId == nil then
		return false
	end

	if OwnerRoot[userId] == true or SuperAdmins[userId] == true then
		return true
	end

	return AdminPermissions.IsAdmin(player)
end

local function refreshOnlineAdminStateForUserId(userId: number, source: string?)
	local targetPlayer = Players:GetPlayerByUserId(math.floor(tonumber(userId) or 0))
	if not targetPlayer then
		return
	end

	local targetUserId = getUserId(targetPlayer)
	if targetUserId == nil then
		return
	end

	if getDefaultAdminState(targetPlayer) then
		if activeAdmins[targetUserId] ~= true then
			setAdminInternal(targetPlayer, true, source or "staff_role_changed")
		end
	elseif activeAdmins[targetUserId] == true then
		setAdminInternal(targetPlayer, false, source or "staff_role_changed")
	end
end

getDefaultAdminState = function(player: Player): boolean
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

setAdminInternal = function(player: Player, enabled: boolean, source: string?): (boolean, boolean)
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

local function handleAdminChatCommand(player: Player, message: string, source: string?): boolean
	local requestedState = parseAdminToggleCommand(message)
	if requestedState == nil then
		return false
	end

	source = source or "unknown"
	AdminPermissions.LogCommandAttempt(player, "admin", source, string.format("enabled=%s", tostring(requestedState)))
	if not AdminPermissions.IsSuperAdmin(player) then
		AdminPermissions.LogCommandRejected(player, "admin", source, "reason=not_super_admin")
		return false
	end

	local didSet = AdminPermissions.SetAdmin(player, requestedState)
	if didSet then
		AdminPermissions.LogCommandExecuted(player, "admin", source, string.format("enabled=%s", tostring(requestedState)))
	end
	return didSet
end

local function handleVipTestCommand(player: Player, message: string, source: string?): boolean
	local requestedAction = parseVipTestCommand(message)
	if requestedAction == nil then
		return false
	end

	source = source or "unknown"
	AdminPermissions.LogCommandAttempt(player, "vip", source, string.format("action=%s", requestedAction))
	if not AdminPermissions.IsSuperAdmin(player) then
		AdminPermissions.LogCommandRejected(player, "vip", source, "reason=not_super_admin")
		return false
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
	return true
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

	if testerTitleConnections[player] then
		testerTitleConnections[player]:Disconnect()
	end
	testerTitleConnections[player] = player:GetAttributeChangedSignal(EQUIPPED_TITLE_ATTRIBUTE):Connect(function()
		updatePublicTesterTitleState(player, "tester_title_changed")
	end)
	updatePublicTesterTitleState(player, "player_bound")

	AdminPermissions.LogPlayerResolved(player)
end

local function unbindPlayer(player: Player)
	local connection = chatConnections[player]
	if connection then
		connection:Disconnect()
		chatConnections[player] = nil
	end

	local testerTitleConnection = testerTitleConnections[player]
	if testerTitleConnection then
		testerTitleConnection:Disconnect()
		testerTitleConnections[player] = nil
	end

	local userId = getUserId(player)
	if userId ~= nil then
		activeAdmins[userId] = nil
		if activePublicTesterTitleByUserId[userId] == true then
			activePublicTesterTitleByUserId[userId] = nil
			emitTesterStateChanged(player, userId, "player_removing")
		end
	end
end

print(string.format(
	"[AdminPermissions] Admin config loaded adminCount=%d adminUserIds=%s superAdminCount=%d superAdminUserIds=%s",
	#configuredAdminIds,
	getIdsText(configuredAdminIds),
	#superAdminIds,
	getIdsText(superAdminIds)
))
print(string.format(
	"[AdminPermissions] Tester config loaded baseTesterCount=%d baseTesterUserIds=%s effectiveTesterCount=%d effectiveTesterUserIds=%s storeAvailable=%s",
	#baseConfiguredTesterIds,
	getIdsText(baseConfiguredTesterIds),
	#configuredTesterIds,
	getIdsText(configuredTesterIds),
	tostring(testerRoleOverrides.Available == true)
))

local function recordAdminAudit(player: Player?, actionName: string, targetUserId: number?, result: string, reason: string?)
	local actorUserId = getUserId(player) or 0
	local actorName = if player then (player.DisplayName or player.Name) else "Server"
	local numericTargetUserId = math.floor(tonumber(targetUserId) or 0)
	local targetName = ""
	if numericTargetUserId > 0 then
		local targetPlayer = Players:GetPlayerByUserId(numericTargetUserId)
		local targetInfo = getCachedUserInfo(numericTargetUserId, targetPlayer)
		targetName = targetInfo.DisplayName or targetInfo.Username or ("User " .. tostring(numericTargetUserId))
	end

	return AdminAuditLog.Record({
		ActorUserId = actorUserId,
		ActorName = actorName,
		Action = actionName,
		TargetUserId = numericTargetUserId,
		TargetName = targetName,
		Result = result,
		Reason = reason or "",
	})
end

function AdminPermissions.IsSuperAdmin(player: Player?): boolean
	local userId = getUserId(player)
	return userId ~= nil and SuperAdmins[userId] == true
end

function AdminPermissions.IsOwnerRoot(player: Player?): boolean
	local userId = getUserId(player)
	return userId ~= nil and OwnerRoot[userId] == true
end

function AdminPermissions.CanViewAdminConsole(player: Player?): boolean
	return canViewAdminConsole(player)
end

function AdminPermissions.GetRoleLevel(subject): number
	return getRoleLevelForUserId(getUserIdFromSubject(subject))
end

function AdminPermissions.GetRoleName(subject): string
	return getRoleNameForUserId(getUserIdFromSubject(subject))
end

function AdminPermissions.CanManageRole(actor: Player?, target, roleName: string): (boolean, string?)
	return canManageRoleByUserId(getUserId(actor), getUserIdFromSubject(target), roleName)
end

function AdminPermissions.CanModerate(actor: Player?, target, actionName: string?): (boolean, string?)
	return canModerateByUserId(getUserId(actor), getUserIdFromSubject(target), actionName)
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

function AdminPermissions.IsTester(player: Player?): boolean
	updatePublicTesterTitleState(player, "tester_status_check")
	local userId = getUserId(player)
	return userId ~= nil and isTesterUserId(userId)
end

function AdminPermissions.HasTesterRole(subject): boolean
	local userId = getUserIdFromSubject(subject)
	return userId ~= nil and isTesterUserId(userId)
end

function AdminPermissions.GetAdminRoster(requestingPlayer: Player?): table
	local viewerIsAdmin, viewerReason = AdminPermissions.GetAdminStatus(requestingPlayer)
	local viewerUserId = getUserId(requestingPlayer) or 0
	local viewerIsOwnerRoot = AdminPermissions.IsOwnerRoot(requestingPlayer)
	local viewerIsSuperAdmin = AdminPermissions.IsSuperAdmin(requestingPlayer)
	local viewerCanAccessConsole = canViewAdminConsole(requestingPlayer)
	local viewer = {
		UserId = requestingPlayer and requestingPlayer.UserId or 0,
		Username = requestingPlayer and requestingPlayer.Name or "",
		DisplayName = requestingPlayer and requestingPlayer.DisplayName or "",
		IsAdmin = viewerIsAdmin,
		IsOwnerRoot = viewerIsOwnerRoot,
		IsSuperAdmin = viewerIsSuperAdmin,
		CanViewAdminConsole = viewerCanAccessConsole,
		CanManageAdminRoles = viewerIsSuperAdmin,
		CanManageSuperAdmins = viewerIsOwnerRoot,
		CanModerate = viewerIsAdmin or viewerIsSuperAdmin or viewerIsOwnerRoot,
		AdminStatusReason = viewerReason,
		HighestRole = getRoleNameForUserId(viewerUserId),
		RoleLevel = getRoleLevelForUserId(viewerUserId),
	}

	if not viewerCanAccessConsole then
		return {
			Success = false,
			Message = "Admin access required.",
			GeneratedAt = os.time(),
			Viewer = viewer,
			OwnerRoots = {},
			SuperAdmins = {},
			Admins = {},
			AllPlayers = {},
			Testers = {},
			AuditLog = {},
		}
	end

	return {
		Success = true,
		GeneratedAt = os.time(),
		Viewer = viewer,
		OwnerRoots = buildRosterList(ownerRootIds, "OwnerRoot", viewerUserId),
		SuperAdmins = buildRosterList(superAdminIds, "SuperAdmin", viewerUserId),
		Admins = buildRosterList(configuredAdminIds, "Admin", viewerUserId),
		AllPlayers = buildAllPlayerRosterList(viewerUserId),
		Testers = buildTesterRosterList(viewerUserId),
		AuditLog = AdminAuditLog.GetRecent(60),
		StaffRoleStoreAvailable = staffRoleOverrides.Available == true,
		StaffRoleStoreUpdatedAt = math.floor(tonumber(staffRoleOverrides.UpdatedAt) or 0),
		StaffRoleStoreUpdatedBy = math.floor(tonumber(staffRoleOverrides.UpdatedBy) or 0),
		TesterRoleStoreAvailable = testerRoleOverrides.Available == true,
		TesterRoleStoreUpdatedAt = math.floor(tonumber(testerRoleOverrides.UpdatedAt) or 0),
		TesterRoleStoreUpdatedBy = math.floor(tonumber(testerRoleOverrides.UpdatedBy) or 0),
	}
end

function AdminPermissions.SetTesterRole(requestingPlayer: Player?, target, enabled: boolean, source: string?): table
	source = source or "AdminTesterRoleRequest"
	local action = if enabled == true then "add" else "remove"
	AdminPermissions.LogCommandAttempt(requestingPlayer, "testerRole", source, string.format(
		"action=%s target=%s",
		action,
		tostring(target)
	))

	if not AdminPermissions.IsSuperAdmin(requestingPlayer) then
		AdminPermissions.LogCommandRejected(requestingPlayer, "testerRole", source, "reason=not_super_admin")
		recordAdminAudit(requestingPlayer, if enabled == true then "SetTester" else "RemoveTester", nil, "rejected", "not_super_admin")
		return {
			Success = false,
			Message = "SuperAdmin access required.",
		}
	end

	local targetUserId, resolveReason = resolveUserIdFromTarget(target)
	if targetUserId == nil then
		AdminPermissions.LogCommandFailed(requestingPlayer, "testerRole", source, "reason=" .. tostring(resolveReason))
		recordAdminAudit(requestingPlayer, if enabled == true then "SetTester" else "RemoveTester", nil, "failed", tostring(resolveReason))
		return {
			Success = false,
			Message = "Could not resolve that tester target.",
		}
	end

	local canManageTester, blockedReason = canManageRoleByUserId(getUserId(requestingPlayer), targetUserId, "Tester")
	if not canManageTester then
		AdminPermissions.LogCommandRejected(
			requestingPlayer,
			"testerRole",
			source,
			string.format("reason=%s targetUserId=%d", blockedReason, targetUserId)
		)
		recordAdminAudit(requestingPlayer, if enabled == true then "SetTester" else "RemoveTester", targetUserId, "rejected", tostring(blockedReason))
		return {
			Success = false,
			Message = "Admins and SuperAdmins cannot be modified through tester management.",
			TargetUserId = targetUserId,
		}
	end

	local isTester = configuredTesters[targetUserId] == true
	if enabled == true and isTester then
		AdminPermissions.LogCommandExecuted(
			requestingPlayer,
			"testerRole",
			source,
			string.format("action=%s targetUserId=%d changed=false", action, targetUserId)
		)
		recordAdminAudit(requestingPlayer, "SetTester", targetUserId, "success", "already_tester")
		return {
			Success = true,
			Message = "That player is already a tester.",
			Changed = false,
			Entry = buildRosterEntry(targetUserId, "Tester"),
			Roster = AdminPermissions.GetAdminRoster(requestingPlayer),
		}
	elseif enabled ~= true and not isTester then
		AdminPermissions.LogCommandExecuted(
			requestingPlayer,
			"testerRole",
			source,
			string.format("action=%s targetUserId=%d changed=false", action, targetUserId)
		)
		recordAdminAudit(requestingPlayer, "RemoveTester", targetUserId, "success", "not_tester")
		return {
			Success = true,
			Message = "That player is not a configured or persistent tester.",
			Changed = false,
			Entry = buildRosterEntry(targetUserId, "Tester"),
			Roster = AdminPermissions.GetAdminRoster(requestingPlayer),
		}
	end

	local ok, state, errorMessage = TesterRoleStore.SetTester(targetUserId, enabled == true, getUserId(requestingPlayer) or 0)
	if not ok then
		AdminPermissions.LogCommandFailed(
			requestingPlayer,
			"testerRole",
			source,
			string.format("reason=store_write_failed targetUserId=%d error=%s", targetUserId, tostring(errorMessage))
		)
		recordAdminAudit(requestingPlayer, if enabled == true then "SetTester" else "RemoveTester", targetUserId, "failed", "store_write_failed")
		return {
			Success = false,
			Message = "Tester role storage failed. No role changed.",
			TargetUserId = targetUserId,
		}
	end

	applyTesterRoleOverrides(state)
	emitTesterStateChanged(Players:GetPlayerByUserId(targetUserId), targetUserId, "tester_role_changed")
	publishTesterRoleUpdate(getUserId(requestingPlayer) or 0)

	AdminPermissions.LogCommandExecuted(
		requestingPlayer,
		"testerRole",
		source,
		string.format("action=%s targetUserId=%d changed=true", action, targetUserId)
	)
	recordAdminAudit(requestingPlayer, if enabled == true then "SetTester" else "RemoveTester", targetUserId, "success", "changed=true")

	local message = if enabled == true then "Tester added." else "Tester removed."
	return {
		Success = true,
		Message = message,
		Changed = true,
		Entry = buildRosterEntry(targetUserId, "Tester"),
		Roster = AdminPermissions.GetAdminRoster(requestingPlayer),
	}
end

function AdminPermissions.SetStaffRole(requestingPlayer: Player?, target, roleName: string, enabled: boolean, source: string?, confirmed: boolean?): table
	source = source or "AdminConsoleActionRequest"
	roleName = tostring(roleName or "")
	enabled = enabled == true

	local auditAction = (enabled and "Set" or "Remove") .. roleName
	AdminPermissions.LogCommandAttempt(requestingPlayer, "staffRole", source, string.format(
		"role=%s enabled=%s target=%s confirmed=%s",
		roleName,
		tostring(enabled),
		tostring(target),
		tostring(confirmed == true)
	))

	if (roleName == "Admin" or roleName == "SuperAdmin") and confirmed ~= true then
		recordAdminAudit(requestingPlayer, auditAction, nil, "rejected", "confirmation_required")
		return {
			Success = false,
			Message = "Confirmation required before changing staff roles.",
		}
	end

	local targetUserId, resolveReason = resolveUserIdFromTarget(target)
	if targetUserId == nil then
		AdminPermissions.LogCommandFailed(requestingPlayer, "staffRole", source, "reason=" .. tostring(resolveReason))
		recordAdminAudit(requestingPlayer, auditAction, nil, "failed", tostring(resolveReason))
		return {
			Success = false,
			Message = "Could not resolve that staff role target.",
		}
	end

	local canManage, blockedReason = canManageRoleByUserId(getUserId(requestingPlayer), targetUserId, roleName)
	if not canManage then
		AdminPermissions.LogCommandRejected(
			requestingPlayer,
			"staffRole",
			source,
			string.format("reason=%s role=%s targetUserId=%d", tostring(blockedReason), roleName, targetUserId)
		)
		recordAdminAudit(requestingPlayer, auditAction, targetUserId, "rejected", tostring(blockedReason))
		return {
			Success = false,
			Message = "You do not have permission to change that role.",
			TargetUserId = targetUserId,
		}
	end

	local alreadyEnabled = if roleName == "SuperAdmin" then SuperAdmins[targetUserId] == true else configuredAdmins[targetUserId] == true
	if enabled == alreadyEnabled then
		AdminPermissions.LogCommandExecuted(
			requestingPlayer,
			"staffRole",
			source,
			string.format("role=%s enabled=%s targetUserId=%d changed=false", roleName, tostring(enabled), targetUserId)
		)
		recordAdminAudit(requestingPlayer, auditAction, targetUserId, "success", "changed=false")
		return {
			Success = true,
			Message = if enabled then "That role is already assigned." else "That role is not assigned.",
			Changed = false,
			Entry = buildRosterEntry(targetUserId, roleName, getUserId(requestingPlayer)),
			Roster = AdminPermissions.GetAdminRoster(requestingPlayer),
		}
	end

	local ok, state, errorMessage = AdminStaffRoleStore.SetRole(roleName, targetUserId, enabled, getUserId(requestingPlayer) or 0)
	if not ok then
		AdminPermissions.LogCommandFailed(
			requestingPlayer,
			"staffRole",
			source,
			string.format("reason=store_write_failed role=%s targetUserId=%d error=%s", roleName, targetUserId, tostring(errorMessage))
		)
		recordAdminAudit(requestingPlayer, auditAction, targetUserId, "failed", "store_write_failed")
		return {
			Success = false,
			Message = "Staff role storage failed. No role changed.",
			TargetUserId = targetUserId,
		}
	end

	applyStaffRoleOverrides(state)
	refreshOnlineAdminStateForUserId(targetUserId, "staff_role_changed")
	publishStaffRoleUpdate(getUserId(requestingPlayer) or 0)
	staffRoleStateChanged:Fire(requestingPlayer, {
		Source = "staff_role_changed",
		TargetUserId = targetUserId,
		Role = roleName,
		Enabled = enabled,
		SentAt = os.time(),
	})

	AdminPermissions.LogCommandExecuted(
		requestingPlayer,
		"staffRole",
		source,
		string.format("role=%s enabled=%s targetUserId=%d changed=true", roleName, tostring(enabled), targetUserId)
	)
	recordAdminAudit(requestingPlayer, auditAction, targetUserId, "success", "changed=true")

	return {
		Success = true,
		Message = string.format("%s %s.", roleName, if enabled then "added" else "removed"),
		Changed = true,
		Entry = buildRosterEntry(targetUserId, roleName, getUserId(requestingPlayer)),
		Roster = AdminPermissions.GetAdminRoster(requestingPlayer),
	}
end

function AdminPermissions.KickPlayer(requestingPlayer: Player?, target, reason, source: string?, confirmed: boolean?): table
	source = source or "AdminConsoleActionRequest"
	AdminPermissions.LogCommandAttempt(requestingPlayer, "adminConsole", source, string.format(
		"action=Kick target=%s confirmed=%s",
		tostring(target),
		tostring(confirmed == true)
	))

	if confirmed ~= true then
		recordAdminAudit(requestingPlayer, "Kick", nil, "rejected", "confirmation_required")
		return {
			Success = false,
			Message = "Confirmation required before kicking a player.",
		}
	end

	local targetUserId, resolveReason = resolveUserIdFromTarget(target)
	if targetUserId == nil then
		AdminPermissions.LogCommandFailed(requestingPlayer, "adminConsole", source, "reason=" .. tostring(resolveReason))
		recordAdminAudit(requestingPlayer, "Kick", nil, "failed", tostring(resolveReason))
		return {
			Success = false,
			Message = "Could not resolve that player.",
		}
	end

	local canKick, blockedReason = canModerateByUserId(getUserId(requestingPlayer), targetUserId, "Kick")
	if not canKick then
		AdminPermissions.LogCommandRejected(
			requestingPlayer,
			"adminConsole",
			source,
			string.format("reason=%s action=Kick targetUserId=%d", tostring(blockedReason), targetUserId)
		)
		recordAdminAudit(requestingPlayer, "Kick", targetUserId, "rejected", tostring(blockedReason))
		return {
			Success = false,
			Message = "You do not have permission to kick that player.",
			TargetUserId = targetUserId,
		}
	end

	local targetPlayer = Players:GetPlayerByUserId(targetUserId)
	if not targetPlayer then
		recordAdminAudit(requestingPlayer, "Kick", targetUserId, "failed", "target_offline")
		return {
			Success = false,
			Message = "That player is no longer in this server.",
			TargetUserId = targetUserId,
		}
	end

	local kickReason = tostring(reason or ""):gsub("\r", ""):gsub("\n", " ")
	kickReason = kickReason:match("^%s*(.-)%s*$") or ""
	if kickReason == "" then
		kickReason = "Removed from the server by an admin."
	end
	kickReason = kickReason:sub(1, 180)

	local kickOk, kickError = pcall(function()
		targetPlayer:Kick(kickReason)
	end)
	if not kickOk then
		AdminPermissions.LogCommandFailed(
			requestingPlayer,
			"adminConsole",
			source,
			string.format("reason=kick_failed targetUserId=%d error=%s", targetUserId, tostring(kickError))
		)
		recordAdminAudit(requestingPlayer, "Kick", targetUserId, "failed", "kick_failed")
		return {
			Success = false,
			Message = "Kick failed.",
			TargetUserId = targetUserId,
		}
	end

	AdminPermissions.LogCommandExecuted(
		requestingPlayer,
		"adminConsole",
		source,
		string.format("action=Kick targetUserId=%d reason=%s", targetUserId, kickReason)
	)
	recordAdminAudit(requestingPlayer, "Kick", targetUserId, "success", kickReason)

	return {
		Success = true,
		Message = "Player kicked.",
		Changed = true,
		TargetUserId = targetUserId,
		Roster = AdminPermissions.GetAdminRoster(requestingPlayer),
	}
end

function AdminPermissions.ApplyAdminConsoleAction(requestingPlayer: Player?, payload): table
	if not canViewAdminConsole(requestingPlayer) then
		AdminPermissions.LogCommandRejected(requestingPlayer, "adminConsole", "AdminConsoleActionRequest", "reason=not_admin")
		recordAdminAudit(requestingPlayer, "AdminConsole", nil, "rejected", "not_admin")
		return {
			Success = false,
			Message = "Admin access required.",
		}
	end

	if typeof(payload) ~= "table" then
		recordAdminAudit(requestingPlayer, "AdminConsole", nil, "rejected", "invalid_payload")
		return {
			Success = false,
			Message = "Invalid admin console action.",
		}
	end

	local actionName = tostring(payload.Action or "")
	local target = payload.TargetUserId or payload.Target or payload.TargetText
	local confirmed = payload.Confirmed == true

	if actionName == "SetTester" or actionName == "AddTester" then
		return AdminPermissions.SetTesterRole(requestingPlayer, target, true, "AdminConsoleActionRequest")
	elseif actionName == "RemoveTester" then
		if not confirmed then
			recordAdminAudit(requestingPlayer, "RemoveTester", nil, "rejected", "confirmation_required")
			return {
				Success = false,
				Message = "Confirmation required before removing a role.",
			}
		end
		return AdminPermissions.SetTesterRole(requestingPlayer, target, false, "AdminConsoleActionRequest")
	elseif actionName == "SetAdmin" or actionName == "AddAdmin" then
		return AdminPermissions.SetStaffRole(requestingPlayer, target, "Admin", true, "AdminConsoleActionRequest", confirmed)
	elseif actionName == "RemoveAdmin" then
		return AdminPermissions.SetStaffRole(requestingPlayer, target, "Admin", false, "AdminConsoleActionRequest", confirmed)
	elseif actionName == "SetSuperAdmin" or actionName == "AddSuperAdmin" then
		return AdminPermissions.SetStaffRole(requestingPlayer, target, "SuperAdmin", true, "AdminConsoleActionRequest", confirmed)
	elseif actionName == "RemoveSuperAdmin" then
		return AdminPermissions.SetStaffRole(requestingPlayer, target, "SuperAdmin", false, "AdminConsoleActionRequest", confirmed)
	elseif actionName == "Kick" then
		return AdminPermissions.KickPlayer(requestingPlayer, target, payload.Reason, "AdminConsoleActionRequest", confirmed)
	end

	recordAdminAudit(requestingPlayer, "AdminConsole", nil, "rejected", "unsupported_action")
	return {
		Success = false,
		Message = "Unsupported admin console action.",
	}
end

function AdminPermissions.HandleAdminCommand(player: Player, message: string, source: string?)
	return handleAdminChatCommand(player, message, source or "AdminPermissions.HandleAdminCommand")
end

function AdminPermissions.HandleVipTestCommand(player: Player, message: string, source: string?)
	return handleVipTestCommand(player, message, source or "AdminPermissions.HandleVipTestCommand")
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
		sendCommandFeedback(player, "rejected", commandName, source, detail or reason)
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

function AdminPermissions.LogCommandFailed(player: Player?, commandName: string, source: string?, detail: string?)
	local isAdmin, reason = AdminPermissions.GetAdminStatus(player)
	if player then
		warn(string.format(
			"[AdminPermissions] Admin command failed command=%s source=%s player=%s displayName=%s userId=%d isSuperAdmin=%s isAdmin=%s reason=%s%s",
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
		sendCommandFeedback(player, "error", commandName, source, detail or reason)
	else
		warn(string.format(
			"[AdminPermissions] Admin command failed command=%s source=%s player=nil isAdmin=false reason=%s%s",
			tostring(commandName),
			tostring(source or "unknown"),
			reason,
			detail and (" " .. detail) or ""
		))
	end
end

function AdminPermissions.LogCommandWarning(player: Player?, commandName: string, source: string?, detail: string?)
	local isAdmin, reason = AdminPermissions.GetAdminStatus(player)
	if player then
		warn(string.format(
			"[AdminPermissions] Admin command warning command=%s source=%s player=%s displayName=%s userId=%d isSuperAdmin=%s isAdmin=%s reason=%s%s",
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
		sendCommandFeedback(player, "warning", commandName, source, detail or reason)
	else
		warn(string.format(
			"[AdminPermissions] Admin command warning command=%s source=%s player=nil isAdmin=false reason=%s%s",
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
	sendCommandFeedback(player, "success", commandName, source, detail)
end

pcall(function()
	MessagingService:SubscribeAsync(STAFF_ROLE_UPDATE_TOPIC, function()
		loadStaffRoleOverrides(true)
		for _, player in ipairs(Players:GetPlayers()) do
			refreshOnlineAdminStateForUserId(player.UserId, "staff_role_reload")
		end
		staffRoleStateChanged:Fire(nil, {
			Source = "staff_role_reload",
			SentAt = os.time(),
		})
	end)
end)

pcall(function()
	MessagingService:SubscribeAsync(TESTER_ROLE_UPDATE_TOPIC, function()
		loadTesterRoleOverrides(true)
		emitTesterStateChangedForAll("tester_role_reload")
	end)
end)

for _, player in ipairs(Players:GetPlayers()) do
	bindPlayer(player)
end

setupAdminTextChatCommand()
Players.PlayerAdded:Connect(bindPlayer)
Players.PlayerRemoving:Connect(unbindPlayer)

return AdminPermissions
