local Players = game:GetService("Players")
local PhysicsService = game:GetService("PhysicsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local MapResolver = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("MapResolver"))
local GamepassesConfig = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("Gamepasses"))
local PopUpModule = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("PopUpModule"))
local AdminPermissions = require(ServerScriptService:WaitForChild("Modules"):WaitForChild("AdminPermissions"))
local VIPTestOverrides = require(ServerScriptService:WaitForChild("Modules"):WaitForChild("VIPTestOverrides"))

local VIPBarrierService = {}

local PLAYER_GROUP = "Players"
local VIP_PLAYER_GROUP = "VIPPlayers"
local VIP_BARRIER_GROUP = "VIPBarriers"
local VIP_GAMEPASS_ID = assert(tonumber(GamepassesConfig.VIP and GamepassesConfig.VIP.ID), "VIP gamepass ID is not configured")
local FEEDBACK_COOLDOWN_SECONDS = 8
local POPUP_COLOR = Color3.fromRGB(255, 86, 86)
local POPUP_STROKE = Color3.fromRGB(0, 0, 0)
local DEBUG_LOGS = RunService:IsStudio()

local started = false
local playerStates = {}
local playerAddedConnection = nil
local playerRemovingConnection = nil
local activeMapConnection = nil
local adminStateConnection = nil
local vipOverrideConnection = nil
local barrierFolder = nil
local barrierFolderConnections = {}
local barrierTouchedConnections = setmetatable({}, { __mode = "k" })
local lastFeedbackAtByPlayer = {}

local function debugLog(message, ...)
	if not DEBUG_LOGS then
		return
	end

	print(string.format("[VIPBarrierDebug] " .. message, ...))
end

local function disconnectAll(connections)
	for _, connection in ipairs(connections) do
		connection:Disconnect()
	end
	table.clear(connections)
end

local function getCollisionMatrixValue(groupA, groupB)
	local ok, result = pcall(function()
		return PhysicsService:CollisionGroupsAreCollidable(groupA, groupB)
	end)
	if ok then
		return tostring(result)
	end
	return "error:" .. tostring(result)
end

local function debugCollisionMatrix(context)
	debugLog(
		"collisionMatrix context=%s PlayersVsVIPBarriers=%s expected=true VIPPlayersVsVIPBarriers=%s expected=false PlayersVsVIPPlayers=%s expected=false",
		tostring(context),
		getCollisionMatrixValue(PLAYER_GROUP, VIP_BARRIER_GROUP),
		getCollisionMatrixValue(VIP_PLAYER_GROUP, VIP_BARRIER_GROUP),
		getCollisionMatrixValue(PLAYER_GROUP, VIP_PLAYER_GROUP)
	)
end

local function registerCollisionGroup(groupName)
	pcall(function()
		PhysicsService:RegisterCollisionGroup(groupName)
	end)
end

local function setCollidable(groupA, groupB, isCollidable)
	local ok, err = pcall(function()
		PhysicsService:CollisionGroupSetCollidable(groupA, groupB, isCollidable)
	end)
	if not ok then
		warn(string.format(
			"[VIPBarrierService] Failed to set collision matrix %s vs %s = %s (%s)",
			groupA,
			groupB,
			tostring(isCollidable),
			tostring(err)
		))
	end
end

local function setupCollisionGroups()
	registerCollisionGroup(PLAYER_GROUP)
	registerCollisionGroup(VIP_PLAYER_GROUP)
	registerCollisionGroup(VIP_BARRIER_GROUP)

	setCollidable(PLAYER_GROUP, PLAYER_GROUP, false)
	setCollidable(VIP_PLAYER_GROUP, VIP_PLAYER_GROUP, false)
	setCollidable(PLAYER_GROUP, VIP_PLAYER_GROUP, false)
	setCollidable(PLAYER_GROUP, VIP_BARRIER_GROUP, true)
	setCollidable(VIP_PLAYER_GROUP, VIP_BARRIER_GROUP, false)

	debugCollisionMatrix("setupCollisionGroups")
end

local function hasVipValue(player)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return false
	end

	local passes = player:FindFirstChild("Passes")
	local vip = passes and passes:FindFirstChild("VIP")
	return vip ~= nil and vip:IsA("BoolValue") and vip.Value == true
end

local function hasVipAccess(player)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return false
	end

	if AdminPermissions.IsAdmin(player) then
		return true
	end

	local effectiveVip = VIPTestOverrides.GetEffectiveVip(player)
	return effectiveVip == true
end

local function getCharacterCollisionGroupSummary(player)
	local character = player.Character
	if not character then
		return "<no character>"
	end

	local counts = {}
	for _, descendant in ipairs(character:GetDescendants()) do
		if descendant:IsA("BasePart") then
			local groupName = descendant.CollisionGroup
			counts[groupName] = (counts[groupName] or 0) + 1
		end
	end

	local parts = {}
	for groupName, count in pairs(counts) do
		parts[#parts + 1] = string.format("%s=%d", groupName, count)
	end
	table.sort(parts)

	if #parts == 0 then
		return "<no BaseParts>"
	end

	return table.concat(parts, ",")
end

local function debugPlayerAccess(player, context, appliedGroup)
	local effectiveVip, effectiveVipSource = VIPTestOverrides.GetEffectiveVip(player)
	local vipOverride = VIPTestOverrides.GetOverride(player)
	debugLog(
		"playerState context=%s player=%s userId=%d isSuperAdmin=%s isAdmin=%s passesVIP=%s vipOverride=%s effectiveVIP=%s effectiveVIPSource=%s computedBypass=%s appliedGroup=%s characterGroups=%s",
		tostring(context),
		player.Name,
		player.UserId,
		tostring(AdminPermissions.IsSuperAdmin(player)),
		tostring(AdminPermissions.IsAdmin(player)),
		tostring(hasVipValue(player)),
		tostring(vipOverride),
		tostring(effectiveVip),
		effectiveVipSource,
		tostring(hasVipAccess(player)),
		tostring(appliedGroup or "<none>"),
		getCharacterCollisionGroupSummary(player)
	)
end

local function getPlayerCollisionGroup(player)
	return if hasVipAccess(player) then VIP_PLAYER_GROUP else PLAYER_GROUP
end

local function setPartCollisionGroup(part, groupName)
	if part:IsA("BasePart") then
		part.CollisionGroup = groupName
	end
end

local function applyCharacterCollisionGroup(player)
	local character = player.Character
	if not character then
		return
	end

	local groupName = getPlayerCollisionGroup(player)
	for _, descendant in ipairs(character:GetDescendants()) do
		setPartCollisionGroup(descendant, groupName)
	end
	debugPlayerAccess(player, "applyCharacterCollisionGroup", groupName)
end

local function getPlayerFromHit(hit)
	if typeof(hit) ~= "Instance" then
		return nil
	end

	local character = hit:FindFirstAncestorOfClass("Model")
	if not character then
		return nil
	end

	return Players:GetPlayerFromCharacter(character)
end

local function sendVipRequiredFeedback(player)
	if hasVipAccess(player) then
		return
	end

	local now = os.clock()
	local lastFeedbackAt = lastFeedbackAtByPlayer[player]
	if lastFeedbackAt and now - lastFeedbackAt < FEEDBACK_COOLDOWN_SECONDS then
		return
	end
	lastFeedbackAtByPlayer[player] = now

	PopUpModule:Server_SendPopUp(player, "VIP Required", POPUP_COLOR, POPUP_STROKE, 3, true)
	if VIP_GAMEPASS_ID and VIP_GAMEPASS_ID > 0 then
		PopUpModule:Server_PromptGamepass(player, VIP_GAMEPASS_ID)
	end
end

local function configureBarrierPart(part)
	if not part:IsA("BasePart") then
		return
	end

	part.CollisionGroup = VIP_BARRIER_GROUP
	part.CanCollide = true

	if not barrierTouchedConnections[part] then
		barrierTouchedConnections[part] = part.Touched:Connect(function(hit)
			local player = getPlayerFromHit(hit)
			if player then
				sendVipRequiredFeedback(player)
			end
		end)
	end
end

local function configureBarrierDescendant(instance)
	if instance:IsA("BasePart") then
		configureBarrierPart(instance)
	end
end

local function debugBarrierFolder(folder, context)
	if not DEBUG_LOGS then
		return
	end

	if not folder then
		debugLog("barrierFolder context=%s folder=<nil>", tostring(context))
		return
	end

	local partCount = 0
	local wrongGroupCount = 0
	local nonCollideCount = 0
	for _, descendant in ipairs(folder:GetDescendants()) do
		if descendant:IsA("BasePart") then
			partCount += 1
			if descendant.CollisionGroup ~= VIP_BARRIER_GROUP then
				wrongGroupCount += 1
			end
			if descendant.CanCollide ~= true then
				nonCollideCount += 1
			end
		end
	end

	debugLog(
		"barrierFolder context=%s path=%s baseParts=%d wrongGroup=%d nonCollide=%d",
		tostring(context),
		folder:GetFullName(),
		partCount,
		wrongGroupCount,
		nonCollideCount
	)
end

local function bindBarrierFolder(folder)
	if barrierFolder == folder then
		return
	end

	disconnectAll(barrierFolderConnections)
	barrierFolder = folder

	if not barrierFolder then
		return
	end

	for _, descendant in ipairs(barrierFolder:GetDescendants()) do
		configureBarrierDescendant(descendant)
	end
	debugBarrierFolder(barrierFolder, "bindBarrierFolder")

	table.insert(barrierFolderConnections, barrierFolder.DescendantAdded:Connect(configureBarrierDescendant))
end

local function resolveAndBindBarrierFolder()
	local refs = MapResolver.WaitForRefs({ "VipBarriers" }, nil, {
		warn = true,
		context = "VIPBarrierService",
	})
	bindBarrierFolder(refs.VipBarriers)
end

local function bindPassesFolder(player, state)
	disconnectAll(state.passConnections)

	local passes = player:FindFirstChild("Passes")
	if not passes then
		applyCharacterCollisionGroup(player)
		return
	end

	local vip = passes:FindFirstChild("VIP")
	if vip and vip:IsA("BoolValue") then
		table.insert(state.passConnections, vip:GetPropertyChangedSignal("Value"):Connect(function()
			applyCharacterCollisionGroup(player)
		end))
	end

	table.insert(state.passConnections, passes.ChildAdded:Connect(function(child)
		if child.Name == "VIP" then
			bindPassesFolder(player, state)
		end
	end))
	table.insert(state.passConnections, passes.ChildRemoved:Connect(function(child)
		if child.Name == "VIP" then
			bindPassesFolder(player, state)
		end
	end))

	applyCharacterCollisionGroup(player)
end

local function bindCharacter(player, state, character)
	disconnectAll(state.characterConnections)

	if not character then
		return
	end

	table.insert(state.characterConnections, character.DescendantAdded:Connect(function(descendant)
		setPartCollisionGroup(descendant, getPlayerCollisionGroup(player))
	end))

	applyCharacterCollisionGroup(player)
end

local function watchPlayer(player)
	if playerStates[player] then
		return
	end

	local state = {
		rootConnections = {},
		passConnections = {},
		characterConnections = {},
	}
	playerStates[player] = state

	table.insert(state.rootConnections, player.CharacterAdded:Connect(function(character)
		bindCharacter(player, state, character)
	end))
	table.insert(state.rootConnections, player.ChildAdded:Connect(function(child)
		if child.Name == "Passes" then
			bindPassesFolder(player, state)
		end
	end))
	table.insert(state.rootConnections, player.ChildRemoved:Connect(function(child)
		if child.Name == "Passes" then
			bindPassesFolder(player, state)
		end
	end))

	bindPassesFolder(player, state)
	bindCharacter(player, state, player.Character)
end

local function unwatchPlayer(player)
	local state = playerStates[player]
	if not state then
		return
	end

	disconnectAll(state.rootConnections)
	disconnectAll(state.passConnections)
	disconnectAll(state.characterConnections)
	playerStates[player] = nil
	lastFeedbackAtByPlayer[player] = nil
end

function VIPBarrierService.HasVipAccess(player)
	return hasVipAccess(player)
end

function VIPBarrierService.GetPlayerCollisionGroup(player)
	return getPlayerCollisionGroup(player)
end

function VIPBarrierService.ApplyCharacter(player)
	applyCharacterCollisionGroup(player)
end

function VIPBarrierService.Start()
	if started then
		return
	end
	started = true

	setupCollisionGroups()

	playerAddedConnection = Players.PlayerAdded:Connect(watchPlayer)
	playerRemovingConnection = Players.PlayerRemoving:Connect(unwatchPlayer)
	activeMapConnection = Workspace:GetAttributeChangedSignal("ActiveMapName"):Connect(function()
		task.spawn(resolveAndBindBarrierFolder)
	end)
	adminStateConnection = AdminPermissions.AdminStateChanged:Connect(function(player)
		applyCharacterCollisionGroup(player)
	end)
	vipOverrideConnection = VIPTestOverrides.Changed:Connect(function(player)
		applyCharacterCollisionGroup(player)
	end)

	for _, player in ipairs(Players:GetPlayers()) do
		watchPlayer(player)
	end

	task.spawn(resolveAndBindBarrierFolder)
end

function VIPBarrierService.Stop()
	if not started then
		return
	end
	started = false

	if playerAddedConnection then
		playerAddedConnection:Disconnect()
		playerAddedConnection = nil
	end
	if playerRemovingConnection then
		playerRemovingConnection:Disconnect()
		playerRemovingConnection = nil
	end
	if activeMapConnection then
		activeMapConnection:Disconnect()
		activeMapConnection = nil
	end
	if adminStateConnection then
		adminStateConnection:Disconnect()
		adminStateConnection = nil
	end
	if vipOverrideConnection then
		vipOverrideConnection:Disconnect()
		vipOverrideConnection = nil
	end

	for player in pairs(playerStates) do
		unwatchPlayer(player)
	end
	disconnectAll(barrierFolderConnections)
	barrierFolder = nil
end

return VIPBarrierService
