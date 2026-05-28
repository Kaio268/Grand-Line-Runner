local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MessagingService = game:GetService("MessagingService")
local TextChatService = game:GetService("TextChatService")

local AdminConfig = require(script.Parent:WaitForChild("AdminConfig"))
local TesterRoleStore = require(script.Parent:WaitForChild("TesterRoleStore"))
local VIPTestOverrides = require(script.Parent:WaitForChild("VIPTestOverrides"))
local PopUpModule = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("PopUpModule"))

local AdminPermissions = {}

local SuperAdmins = {
	[5448954557] = true, -- YonkoKaio
	[4843576528] = true, -- ChefChris
	[3412846835] = true,
	[4844244696] = true,
}

local configuredAdmins = {}
local configuredAdminIds = {}
local baseConfiguredTesters = {}
local baseConfiguredTesterIds = {}
local configuredTesters = {}
local configuredTesterIds = {}
local testerRoleOverrides = {
	Added = {},
	Removed = {},
	UpdatedAt = 0,
	UpdatedBy = 0,
	Available = false,
}
local activePublicTesterTitleByUserId = {}
local superAdminIds = {}
local activeAdmins = {}
local userInfoCache = {}
local chatConnections = {}
local testerTitleConnections = {}
local textChatCommandConnection = nil
local vipTextChatCommandConnection = nil
local adminStateChanged = Instance.new("BindableEvent")
local testerStateChanged = Instance.new("BindableEvent")

local POPUP_STROKE = Color3.fromRGB(0, 0, 0)
local POPUP_INFO = Color3.fromRGB(105, 225, 255)
local POPUP_WARNING = Color3.fromRGB(255, 205, 90)
local POPUP_SUCCESS = Color3.fromRGB(105, 255, 172)
local POPUP_ERROR = Color3.fromRGB(255, 92, 92)
local POPUP_DURATION_SECONDS = 4
local POPUP_MESSAGE_LIMIT = 140
local ADMIN_COMMAND_FEEDBACK_EVENT_NAME = "AdminCommandFeedback"
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
	serverLuck = "Server luck",
	setspeed = "Speed",
	shipreset = "Ship reset",
	spawn = "Spawn",
	speed = "Speed",
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

for userId in pairs(SuperAdmins) do
	table.insert(superAdminIds, userId)
end

table.sort(configuredAdminIds)
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
	return numericUserId > 0
		and (configuredTesters[numericUserId] == true or activePublicTesterTitleByUserId[numericUserId] == true)
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
	local isTitleActive = activePublicTesterTitleByUserId[numericUserId] == true

	if isStatic then
		table.insert(parts, "Configured Tester")
	end
	if isAdded then
		table.insert(parts, "Persistent Tester")
	end
	if isTitleActive then
		table.insert(parts, "Tester Title Active")
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

loadTesterRoleOverrides(false)

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

local function buildRosterEntry(userId: number, roleName: string)
	local numericUserId = math.floor(tonumber(userId) or 0)
	local onlinePlayer = Players:GetPlayerByUserId(numericUserId)
	local userInfo = getCachedUserInfo(numericUserId, onlinePlayer)
	local isActiveAdmin = false
	local adminStatusReason = "offline"
	local isConfiguredTesterRole = configuredTesters[numericUserId] == true
	local isTesterTitleActive = activePublicTesterTitleByUserId[numericUserId] == true
	local isTester = isConfiguredTesterRole or isTesterTitleActive
	local testerBlockReason = getTesterManageBlockedReason(numericUserId)

	if onlinePlayer then
		isActiveAdmin, adminStatusReason = AdminPermissions.GetAdminStatus(onlinePlayer)
	elseif SuperAdmins[numericUserId] == true then
		adminStatusReason = "super_admin_offline"
	elseif configuredAdmins[numericUserId] == true then
		adminStatusReason = "configured_admin_offline"
	end

	return {
		UserId = numericUserId,
		Username = userInfo.Username,
		DisplayName = userInfo.DisplayName,
		Role = roleName,
		IsSuperAdmin = SuperAdmins[numericUserId] == true,
		IsConfiguredAdmin = configuredAdmins[numericUserId] == true,
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
end

local function buildRosterList(ids, roleName: string)
	local entries = {}
	for index, userId in ipairs(ids) do
		entries[index] = buildRosterEntry(userId, roleName)
	end
	return entries
end

local function buildTesterRosterList()
	local ids = {}
	local seen = {}

	for _, userId in ipairs(configuredTesterIds) do
		addSortedUnique(ids, seen, userId)
	end

	for userId, active in pairs(activePublicTesterTitleByUserId) do
		if active == true then
			addSortedUnique(ids, seen, userId)
		end
	end

	table.sort(ids)
	return buildRosterList(ids, "Tester")
end

local function buildAllPlayerRosterList()
	local entries = {}
	for _, onlinePlayer in ipairs(Players:GetPlayers()) do
		table.insert(entries, buildRosterEntry(onlinePlayer.UserId, "Player"))
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

function AdminPermissions.IsTester(player: Player?): boolean
	updatePublicTesterTitleState(player, "tester_status_check")
	local userId = getUserId(player)
	return userId ~= nil and isTesterUserId(userId)
end

function AdminPermissions.GetAdminRoster(requestingPlayer: Player?): table
	local viewerIsAdmin, viewerReason = AdminPermissions.GetAdminStatus(requestingPlayer)
	local viewer = {
		UserId = requestingPlayer and requestingPlayer.UserId or 0,
		Username = requestingPlayer and requestingPlayer.Name or "",
		DisplayName = requestingPlayer and requestingPlayer.DisplayName or "",
		IsAdmin = viewerIsAdmin,
		IsSuperAdmin = AdminPermissions.IsSuperAdmin(requestingPlayer),
		AdminStatusReason = viewerReason,
	}

	if not viewerIsAdmin then
		return {
			Success = false,
			Message = "Admin access required.",
			GeneratedAt = os.time(),
			Viewer = viewer,
			SuperAdmins = {},
			Admins = {},
			AllPlayers = {},
			Testers = {},
		}
	end

	return {
		Success = true,
		GeneratedAt = os.time(),
		Viewer = viewer,
		SuperAdmins = buildRosterList(superAdminIds, "SuperAdmin"),
		Admins = buildRosterList(configuredAdminIds, "Admin"),
		AllPlayers = buildAllPlayerRosterList(),
		Testers = buildTesterRosterList(),
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
		return {
			Success = false,
			Message = "SuperAdmin access required.",
		}
	end

	local targetUserId, resolveReason = resolveUserIdFromTarget(target)
	if targetUserId == nil then
		AdminPermissions.LogCommandFailed(requestingPlayer, "testerRole", source, "reason=" .. tostring(resolveReason))
		return {
			Success = false,
			Message = "Could not resolve that tester target.",
		}
	end

	local blockedReason = getTesterManageBlockedReason(targetUserId)
	if blockedReason ~= nil then
		AdminPermissions.LogCommandRejected(
			requestingPlayer,
			"testerRole",
			source,
			string.format("reason=%s targetUserId=%d", blockedReason, targetUserId)
		)
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

	local message = if enabled == true then "Tester added." else "Tester removed."
	return {
		Success = true,
		Message = message,
		Changed = true,
		Entry = buildRosterEntry(targetUserId, "Tester"),
		Roster = AdminPermissions.GetAdminRoster(requestingPlayer),
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
