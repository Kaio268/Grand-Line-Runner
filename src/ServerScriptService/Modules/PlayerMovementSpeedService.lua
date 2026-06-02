local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MapResolver = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("MapResolver"))
local HitEffectConfig = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("HitEffects"))
local MovementSpeedConfig = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("MovementSpeed"))

local PlayerMovementSpeedService = {}

local DEBUG_TRACE = RunService:IsStudio()
local SELECTED_SPEED_SETTING_NAME = "SelectedSpeed"
local SPEED_AUTO_MAX_SETTING_NAME = "SpeedAutoMax"
local SPEED_PATH = "HiddenLeaderstats.Speed"
local SELECTED_SPEED_PATH = "Settings.SelectedSpeed"
local SPEED_AUTO_MAX_PATH = "Settings.SpeedAutoMax"
local HORO_GHOST_ATTRIBUTE = "HoroProjectionGhost"
local HORO_BODY_ATTRIBUTE = "HoroProjectionBody"
local HORO_SOURCE_SPEED_ATTRIBUTE = "HoroProjectionSourceWalkSpeed"
local HIE_FREEZE_SHOT_CAST_UNTIL_ATTRIBUTE = "HieFreezeShotCastSlowUntil"
local HIE_FREEZE_SHOT_CAST_SPEED_ATTRIBUTE = "HieFreezeShotCastSpeedMultiplier"
local BOMU_MOVEMENT_LOCK_UNTIL_ATTRIBUTE = "BomuMovementLockUntil"
local BOMU_MOVEMENT_LOCK_SPEED_ATTRIBUTE = "BomuMovementLockSpeedMultiplier"
local MOGU_MOVEMENT_LOCK_UNTIL_ATTRIBUTE = "MoguMovementLockUntil"
local MOGU_MOVEMENT_LOCK_SPEED_ATTRIBUTE = "MoguMovementLockSpeedMultiplier"
local LEGACY_DECREASE_SPEED_FLOOR = nil

local started = false
local missingDecreaseSpeedWarned = false
local contextsByPlayer = {}
local playerConnectionsByPlayer = {}
local serviceConnections = {}
local decreasePart = nil

local function roundSpeed(value)
	return math.floor((tonumber(value) or 0) + 0.5)
end

local function formatVector3(value)
	if typeof(value) ~= "Vector3" then
		return tostring(value)
	end

	return string.format("(%.2f, %.2f, %.2f)", value.X, value.Y, value.Z)
end

local function formatInstancePath(instance)
	if not instance then
		return "<nil>"
	end

	return instance:GetFullName()
end

local function zoneTrace(message, ...)
	if not DEBUG_TRACE then
		return
	end

	print(string.format("[ZONE TRACE] " .. message, ...))
end

local function setAttributeIfChanged(instance, attributeName, value)
	if not instance then
		return
	end

	if instance:GetAttribute(attributeName) == value then
		return
	end

	instance:SetAttribute(attributeName, value)
end

local function getRuntimeWalkSpeedFromStat(baseWalkSpeed, selectedSpeed)
	return MovementSpeedConfig.GetRuntimeWalkSpeedFromStat(baseWalkSpeed, selectedSpeed)
end

local function getBaseWalkSpeedFromRuntimeStat(runtimeWalkSpeed, selectedSpeed)
	return MovementSpeedConfig.GetBaseWalkSpeedFromRuntimeStat(runtimeWalkSpeed, selectedSpeed)
end

local function resolveDecreasePart()
	local part = Workspace:FindFirstChild("DecreaseSpeed")
	if part and part:IsA("BasePart") then
		decreasePart = part
		missingDecreaseSpeedWarned = false
		return part
	end

	decreasePart = nil
	if not missingDecreaseSpeedWarned then
		missingDecreaseSpeedWarned = true
		warn("[PlayerMovementSpeedService] Workspace.DecreaseSpeed is missing or not a BasePart; slow-zone speed handling is disabled.")
	end
	return nil
end

local function getDecreasePart()
	if decreasePart and decreasePart.Parent then
		return decreasePart
	end

	return resolveDecreasePart()
end

local function logZoneResolution(context)
	if not DEBUG_TRACE then
		return
	end

	local refs = MapResolver.GetRefs()
	local part = getDecreasePart()
	zoneTrace(
		"context=%s activeMap=%s mapPath=%s boundary=%s boundaryPos=%s boundarySize=%s",
		tostring(context),
		tostring(refs.ActiveMapName),
		formatInstancePath(refs.MapRoot),
		formatInstancePath(part),
		formatVector3(part and part.Position or nil),
		formatVector3(part and part.Size or nil)
	)
end

local function getSettingsValue(player, valueName)
	local settings = player and player:FindFirstChild("Settings")
	return settings and settings:FindFirstChild(valueName) or nil
end

local function getEarnedSpeedValue(player)
	local hidden = player and player:FindFirstChild("HiddenLeaderstats")
	local speed = hidden and hidden:FindFirstChild("Speed")
	if speed and (speed:IsA("NumberValue") or speed:IsA("IntValue")) then
		return speed
	end

	return nil
end

function PlayerMovementSpeedService.ClampSelectedSpeed(value, earnedMax)
	local maximum = math.max(1, roundSpeed(earnedMax))
	return math.clamp(roundSpeed(value), 1, maximum)
end

function PlayerMovementSpeedService.GetEarnedMaxSpeed(player, dataManager)
	local speedValue = getEarnedSpeedValue(player)
	if speedValue then
		return math.max(1, roundSpeed(speedValue.Value))
	end

	if dataManager then
		local stored = dataManager:GetValue(player, SPEED_PATH)
		if typeof(stored) == "number" then
			return math.max(1, roundSpeed(stored))
		end
	end

	return 1
end

function PlayerMovementSpeedService.IsSpeedAutoMax(player)
	local autoValue = getSettingsValue(player, SPEED_AUTO_MAX_SETTING_NAME)
	if autoValue and autoValue:IsA("BoolValue") then
		return autoValue.Value == true
	end

	return true
end

function PlayerMovementSpeedService.GetSelectedSpeed(player, dataManager)
	local earnedMax = PlayerMovementSpeedService.GetEarnedMaxSpeed(player, dataManager)
	if PlayerMovementSpeedService.IsSpeedAutoMax(player) then
		return earnedMax
	end

	local selectedValue = getSettingsValue(player, SELECTED_SPEED_SETTING_NAME)
	if selectedValue and (selectedValue:IsA("NumberValue") or selectedValue:IsA("IntValue")) then
		return PlayerMovementSpeedService.ClampSelectedSpeed(selectedValue.Value, earnedMax)
	end

	return earnedMax
end

local function setProfileValueIfChanged(dataManager, player, path, value, instance)
	if instance and instance:IsA("ValueBase") and instance.Value == value then
		return true
	end

	return dataManager:SetValue(player, path, value) ~= false
end

function PlayerMovementSpeedService.NormalizePlayerSpeedSettings(player, dataManager, _reason)
	if not dataManager then
		return nil, "missing_data_manager"
	end

	local earnedMax = PlayerMovementSpeedService.GetEarnedMaxSpeed(player, dataManager)
	local selectedValue = getSettingsValue(player, SELECTED_SPEED_SETTING_NAME)
	local autoValue = getSettingsValue(player, SPEED_AUTO_MAX_SETTING_NAME)
	local autoMax = PlayerMovementSpeedService.IsSpeedAutoMax(player)
	local selected = earnedMax

	if not autoMax and selectedValue and (selectedValue:IsA("NumberValue") or selectedValue:IsA("IntValue")) then
		selected = selectedValue.Value
	end
	selected = if autoMax then earnedMax else PlayerMovementSpeedService.ClampSelectedSpeed(selected, earnedMax)

	if not setProfileValueIfChanged(dataManager, player, SPEED_AUTO_MAX_PATH, autoMax, autoValue) then
		return nil, "save_auto_failed"
	end
	if not setProfileValueIfChanged(dataManager, player, SELECTED_SPEED_PATH, selected, selectedValue) then
		return nil, "save_selected_failed"
	end

	return {
		SelectedSpeed = selected,
		EarnedMaxSpeed = earnedMax,
		SpeedAutoMax = autoMax,
	}
end

local function getHieIceBoostSpeedMultiplier(player)
	local untilTime = player:GetAttribute("HieIceBoostUntil")
	local speedMultiplier = player:GetAttribute("HieIceBoostSpeedMultiplier")

	if typeof(untilTime) ~= "number" or typeof(speedMultiplier) ~= "number" then
		return 1
	end

	if untilTime <= os.clock() then
		return 1
	end

	return math.max(1, speedMultiplier)
end

local function getHieFreezeShotCastSpeedMultiplier(player)
	local untilTime = player:GetAttribute(HIE_FREEZE_SHOT_CAST_UNTIL_ATTRIBUTE)
	local speedMultiplier = player:GetAttribute(HIE_FREEZE_SHOT_CAST_SPEED_ATTRIBUTE)

	if typeof(untilTime) ~= "number" or typeof(speedMultiplier) ~= "number" then
		return 1
	end

	if untilTime <= os.clock() then
		return 1
	end

	return math.max(0, speedMultiplier)
end

local function getBomuMovementLockSpeedMultiplier(player)
	local untilTime = player:GetAttribute(BOMU_MOVEMENT_LOCK_UNTIL_ATTRIBUTE)
	local speedMultiplier = player:GetAttribute(BOMU_MOVEMENT_LOCK_SPEED_ATTRIBUTE)

	if typeof(untilTime) ~= "number" or typeof(speedMultiplier) ~= "number" then
		return 1
	end

	if untilTime <= os.clock() then
		return 1
	end

	return math.max(0, speedMultiplier)
end

local function getMoguMovementLockSpeedMultiplier(player)
	local untilTime = player:GetAttribute(MOGU_MOVEMENT_LOCK_UNTIL_ATTRIBUTE)
	local speedMultiplier = player:GetAttribute(MOGU_MOVEMENT_LOCK_SPEED_ATTRIBUTE)

	if typeof(untilTime) ~= "number" or typeof(speedMultiplier) ~= "number" then
		return 1
	end

	if untilTime <= os.clock() then
		return 1
	end

	return math.max(0, speedMultiplier)
end

local function getDevilFruitSpeedMultiplier(player)
	return getHieIceBoostSpeedMultiplier(player)
		* getHieFreezeShotCastSpeedMultiplier(player)
		* getBomuMovementLockSpeedMultiplier(player)
		* getMoguMovementLockSpeedMultiplier(player)
end

local function getHitEffectSpeedMultiplier(player)
	local attributes = HitEffectConfig.Attributes
	local untilTime = player:GetAttribute(attributes.Until)
	local speedMultiplier = player:GetAttribute(attributes.WalkSpeedMultiplier)

	if typeof(untilTime) ~= "number" or typeof(speedMultiplier) ~= "number" then
		return 1
	end

	if untilTime <= os.clock() then
		return 1
	end

	return math.max(0, speedMultiplier)
end

local function disconnectContext(player)
	local context = contextsByPlayer[player]
	if not context then
		return
	end

	context.Disconnect()
end

local function hookCharacter(player, character)
	local existing = contextsByPlayer[player]
	if existing and existing.Character == character then
		existing.Apply("rehook_same_character")
		return true
	end

	disconnectContext(player)

	local humanoid = character:FindFirstChildOfClass("Humanoid") or character:WaitForChild("Humanoid", 10)
	if not (humanoid and humanoid:IsA("Humanoid")) then
		warn(string.format("[PlayerMovementSpeedService] Missing Humanoid for %s", player.Name))
		return false
	end

	local hidden = player:FindFirstChild("HiddenLeaderstats") or player:WaitForChild("HiddenLeaderstats", 30)
	local speedObj = hidden and (hidden:FindFirstChild("Speed") or hidden:WaitForChild("Speed", 30))
	if not (speedObj and (speedObj:IsA("NumberValue") or speedObj:IsA("IntValue"))) then
		warn(string.format("[PlayerMovementSpeedService] Missing HiddenLeaderstats.Speed for %s", player.Name))
		return false
	end
	if player.Parent ~= Players or character.Parent == nil then
		return false
	end

	local base = humanoid.WalkSpeed
	setAttributeIfChanged(player, MovementSpeedConfig.Attributes.BaseWalkSpeed, base)

	local inDecreaseZone = false
	local touchingCount = 0
	local updating = false
	local bomuExpiryApplyToken = 0
	local moguExpiryApplyToken = 0
	local disconnected = false
	local conns = {}
	local context

	local function getSelectedSpeed()
		return PlayerMovementSpeedService.GetSelectedSpeed(player)
	end

	local function getNormalUnboostedSpeed()
		return getRuntimeWalkSpeedFromStat(base, getSelectedSpeed())
	end

	local function isProjectedBody()
		return character:GetAttribute(HORO_BODY_ATTRIBUTE) == true
	end

	local function getNonProjectionDesiredSpeed()
		return getNormalUnboostedSpeed() * getDevilFruitSpeedMultiplier(player) * getHitEffectSpeedMultiplier(player)
	end

	local function getDesiredSpeed(nonProjectionDesiredSpeed)
		if character:GetAttribute(HORO_GHOST_ATTRIBUTE) == true and player:GetAttribute("HoroProjectionActive") == true then
			local ghostSpeed = player:GetAttribute("HoroProjectionGhostSpeed")
			local carrySpeed = player:GetAttribute("HoroProjectionCarrySpeed")
			local carrying = player:GetAttribute("HoroProjectionCarryingReward") == true
			local horoSpeed = if carrying then carrySpeed else ghostSpeed
			if typeof(horoSpeed) == "number" and horoSpeed > 0 then
				return horoSpeed
			end
		end

		return nonProjectionDesiredSpeed or getNonProjectionDesiredSpeed()
	end

	local function apply(reason)
		if updating or disconnected then return end
		local selectedSpeed = getSelectedSpeed()
		local nonProjectionDesiredSpeed = getNonProjectionDesiredSpeed()
		setAttributeIfChanged(player, HORO_SOURCE_SPEED_ATTRIBUTE, nonProjectionDesiredSpeed)
		if isProjectedBody() then return end
		local desiredSpeed = getDesiredSpeed(nonProjectionDesiredSpeed)
		updating = true
		humanoid.WalkSpeed = desiredSpeed
		updating = false
		setAttributeIfChanged(player, MovementSpeedConfig.Attributes.DisplaySpeed, selectedSpeed)
		if reason then
			zoneTrace("player=%s apply reason=%s speed=%s", player.Name, tostring(reason), tostring(desiredSpeed))
		end
	end

	local function disconnect()
		if disconnected then
			return
		end
		disconnected = true
		for _, connection in ipairs(conns) do
			connection:Disconnect()
		end
		table.clear(conns)
		if contextsByPlayer[player] == context then
			contextsByPlayer[player] = nil
		end
	end

	context = {
		Character = character,
		Humanoid = humanoid,
		Apply = apply,
		Disconnect = disconnect,
	}
	contextsByPlayer[player] = context

	local function scheduleBomuLockExpiryApply()
		bomuExpiryApplyToken += 1
		local token = bomuExpiryApplyToken
		local untilTime = player:GetAttribute(BOMU_MOVEMENT_LOCK_UNTIL_ATTRIBUTE)
		if typeof(untilTime) ~= "number" then
			return
		end

		local delaySeconds = math.max(0, untilTime - os.clock()) + 0.05
		task.delay(delaySeconds, function()
			if token == bomuExpiryApplyToken and humanoid.Parent and humanoid.Health > 0 then
				apply("bomu_lock_expired")
			end
		end)
	end

	local function scheduleMoguLockExpiryApply()
		moguExpiryApplyToken += 1
		local token = moguExpiryApplyToken
		local untilTime = player:GetAttribute(MOGU_MOVEMENT_LOCK_UNTIL_ATTRIBUTE)
		if typeof(untilTime) ~= "number" then
			return
		end

		local delaySeconds = math.max(0, untilTime - os.clock()) + 0.05
		task.delay(delaySeconds, function()
			if token == moguExpiryApplyToken and humanoid.Parent and humanoid.Health > 0 then
				apply("mogu_lock_expired")
			end
		end)
	end

	local function logSpeedState(reason, oldState, newState)
		local part = getDecreasePart()
		zoneTrace(
			"player=%s reason=%s zone=%s zonePos=%s zoneSize=%s oldState=%s newState=%s appliedSpeed=%s base=%s earnedSpeed=%s selectedSpeed=%s normalUnboostedSpeed=%s legacyFloor=%s activeMap=%s mapPath=%s",
			player.Name,
			tostring(reason),
			formatInstancePath(part),
			formatVector3(part and part.Position or nil),
			formatVector3(part and part.Size or nil),
			tostring(oldState),
			tostring(newState),
			tostring(humanoid.WalkSpeed),
			tostring(base),
			tostring(speedObj.Value),
			tostring(getSelectedSpeed()),
			tostring(getNormalUnboostedSpeed()),
			tostring(LEGACY_DECREASE_SPEED_FLOOR),
			tostring(MapResolver.GetRefs().ActiveMapName),
			formatInstancePath(MapResolver.GetRefs().MapRoot)
		)
	end

	apply("character_hooked")
	scheduleBomuLockExpiryApply()
	scheduleMoguLockExpiryApply()
	zoneTrace(
		"player=%s hookCharacter zone=%s initialInZone=%s appliedSpeed=%s character=%s",
		player.Name,
		formatInstancePath(getDecreasePart()),
		tostring(inDecreaseZone),
		tostring(humanoid.WalkSpeed),
		formatInstancePath(character)
	)

	conns[#conns + 1] = speedObj.Changed:Connect(function()
		apply("earned_speed_changed")
	end)

	local function bindSpeedSettingValue(instance)
		if not (instance and instance:IsA("ValueBase")) then
			return
		end
		if instance.Name ~= SELECTED_SPEED_SETTING_NAME and instance.Name ~= SPEED_AUTO_MAX_SETTING_NAME then
			return
		end

		conns[#conns + 1] = instance:GetPropertyChangedSignal("Value"):Connect(function()
			apply("speed_setting_changed")
		end)
	end

	local function bindSpeedSettingsFolder(folder)
		if not folder then
			return
		end

		bindSpeedSettingValue(folder:FindFirstChild(SELECTED_SPEED_SETTING_NAME))
		bindSpeedSettingValue(folder:FindFirstChild(SPEED_AUTO_MAX_SETTING_NAME))
		conns[#conns + 1] = folder.ChildAdded:Connect(function(child)
			bindSpeedSettingValue(child)
			apply("speed_setting_added")
		end)
	end

	bindSpeedSettingsFolder(player:FindFirstChild("Settings"))
	apply("settings_bound")
	conns[#conns + 1] = player.ChildAdded:Connect(function(child)
		if child.Name == "Settings" then
			bindSpeedSettingsFolder(child)
			apply("settings_folder_added")
		end
	end)

	conns[#conns + 1] = player:GetAttributeChangedSignal("HieIceBoostUntil"):Connect(function()
		apply("hie_ice_until_changed")
	end)

	conns[#conns + 1] = player:GetAttributeChangedSignal("HieIceBoostSpeedMultiplier"):Connect(function()
		apply("hie_ice_multiplier_changed")
	end)

	conns[#conns + 1] = player:GetAttributeChangedSignal("HieIceBoostSpeedBonus"):Connect(function()
		apply("hie_ice_bonus_changed")
	end)

	conns[#conns + 1] = player:GetAttributeChangedSignal(HIE_FREEZE_SHOT_CAST_UNTIL_ATTRIBUTE):Connect(function()
		apply("hie_freeze_until_changed")
	end)

	conns[#conns + 1] = player:GetAttributeChangedSignal(HIE_FREEZE_SHOT_CAST_SPEED_ATTRIBUTE):Connect(function()
		apply("hie_freeze_multiplier_changed")
	end)

	conns[#conns + 1] = player:GetAttributeChangedSignal(BOMU_MOVEMENT_LOCK_UNTIL_ATTRIBUTE):Connect(function()
		apply("bomu_lock_until_changed")
		scheduleBomuLockExpiryApply()
	end)

	conns[#conns + 1] = player:GetAttributeChangedSignal(BOMU_MOVEMENT_LOCK_SPEED_ATTRIBUTE):Connect(function()
		apply("bomu_lock_multiplier_changed")
	end)

	conns[#conns + 1] = player:GetAttributeChangedSignal(MOGU_MOVEMENT_LOCK_UNTIL_ATTRIBUTE):Connect(function()
		apply("mogu_lock_until_changed")
		scheduleMoguLockExpiryApply()
	end)

	conns[#conns + 1] = player:GetAttributeChangedSignal(MOGU_MOVEMENT_LOCK_SPEED_ATTRIBUTE):Connect(function()
		apply("mogu_lock_multiplier_changed")
	end)

	conns[#conns + 1] = player:GetAttributeChangedSignal(HitEffectConfig.Attributes.Until):Connect(function()
		apply("hit_effect_until_changed")
	end)

	conns[#conns + 1] = player:GetAttributeChangedSignal(HitEffectConfig.Attributes.WalkSpeedMultiplier):Connect(function()
		apply("hit_effect_multiplier_changed")
	end)

	conns[#conns + 1] = player:GetAttributeChangedSignal("HoroProjectionGhostSpeed"):Connect(function()
		apply("horo_ghost_speed_changed")
	end)

	conns[#conns + 1] = player:GetAttributeChangedSignal("HoroProjectionCarrySpeed"):Connect(function()
		apply("horo_carry_speed_changed")
	end)

	conns[#conns + 1] = player:GetAttributeChangedSignal("HoroProjectionActive"):Connect(function()
		apply("horo_projection_changed")
	end)

	conns[#conns + 1] = player:GetAttributeChangedSignal("HoroProjectionCarryingReward"):Connect(function()
		apply("horo_carrying_changed")
	end)

	conns[#conns + 1] = character:GetAttributeChangedSignal(HORO_BODY_ATTRIBUTE):Connect(function()
		apply("horo_body_changed")
	end)

	conns[#conns + 1] = humanoid:GetPropertyChangedSignal("WalkSpeed"):Connect(function()
		if updating then return end
		if isProjectedBody() then return end

		if inDecreaseZone then
			apply("walkspeed_changed_in_slow_zone")
			return
		end

		local totalSpeedMultiplier = getDevilFruitSpeedMultiplier(player) * getHitEffectSpeedMultiplier(player)
		local expected = getDesiredSpeed()
		if humanoid.WalkSpeed ~= expected then
			if totalSpeedMultiplier <= 0 then
				apply("walkspeed_changed_locked")
				return
			end

			local normalizedSpeed = humanoid.WalkSpeed / totalSpeedMultiplier
			base = getBaseWalkSpeedFromRuntimeStat(normalizedSpeed, getSelectedSpeed())
			setAttributeIfChanged(player, MovementSpeedConfig.Attributes.BaseWalkSpeed, base)
			apply("base_walkspeed_changed")
		end
	end)

	local part = getDecreasePart()
	if part then
		local function isCharacterPart(hit)
			return hit and hit:IsDescendantOf(character)
		end

		conns[#conns + 1] = part.Touched:Connect(function(hit)
			if not isCharacterPart(hit) then return end

			touchingCount += 1
			if not inDecreaseZone then
				local oldState = inDecreaseZone
				inDecreaseZone = true
				apply("decrease_speed_touched")
				logSpeedState("DecreaseSpeed.Touched", oldState, inDecreaseZone)
			end
		end)

		conns[#conns + 1] = part.TouchEnded:Connect(function(hit)
			if not isCharacterPart(hit) then return end

			touchingCount -= 1
			if touchingCount <= 0 then
				touchingCount = 0
				if inDecreaseZone then
					local oldState = inDecreaseZone
					inDecreaseZone = false
					apply("decrease_speed_touch_ended")
					logSpeedState("DecreaseSpeed.TouchEnded", oldState, inDecreaseZone)
				end
			end
		end)

		local timer = 0
		conns[#conns + 1] = RunService.Heartbeat:Connect(function(dt)
			if not inDecreaseZone then return end

			timer += dt
			if timer < 0.25 then return end
			timer = 0

			local stillTouching = false
			for _, touchingPart in ipairs(part:GetTouchingParts()) do
				if touchingPart:IsDescendantOf(character) then
					stillTouching = true
					break
				end
			end

			if not stillTouching then
				local oldState = inDecreaseZone
				inDecreaseZone = false
				touchingCount = 0
				apply("decrease_speed_heartbeat_exit")
				logSpeedState("DecreaseSpeed.HeartbeatExit", oldState, inDecreaseZone)
			end
		end)
	end

	conns[#conns + 1] = character.AncestryChanged:Connect(function(_, parent)
		if not parent then
			disconnect()
		end
	end)

	return true
end

local function bindPlayer(player)
	if playerConnectionsByPlayer[player] then
		return
	end

	local conns = {}
	playerConnectionsByPlayer[player] = conns

	conns[#conns + 1] = player.CharacterAdded:Connect(function(character)
		task.spawn(hookCharacter, player, character)
	end)

	conns[#conns + 1] = player.CharacterRemoving:Connect(function(character)
		local context = contextsByPlayer[player]
		if context and context.Character == character then
			disconnectContext(player)
		end
	end)

	if player.Character then
		task.spawn(hookCharacter, player, player.Character)
	end
end

local function unbindPlayer(player)
	disconnectContext(player)

	local conns = playerConnectionsByPlayer[player]
	if not conns then
		return
	end

	for _, connection in ipairs(conns) do
		connection:Disconnect()
	end
	playerConnectionsByPlayer[player] = nil
end

function PlayerMovementSpeedService.ApplyPlayerSpeed(player, reason)
	local context = contextsByPlayer[player]
	if context and context.Apply then
		context.Apply(reason or "external")
		return true
	end

	local character = player and player.Character
	local hidden = player and player:FindFirstChild("HiddenLeaderstats")
	local speedObj = hidden and hidden:FindFirstChild("Speed")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if character and humanoid and speedObj then
		local ok = hookCharacter(player, character)
		local nextContext = contextsByPlayer[player]
		if ok and nextContext and nextContext.Apply then
			nextContext.Apply(reason or "external_after_hook")
			return true
		end
	end

	return false, "not_ready"
end

function PlayerMovementSpeedService.Start()
	if started then
		return
	end
	started = true

	resolveDecreasePart()
	logZoneResolution("PlayerMovementSpeedService.Start")

	serviceConnections[#serviceConnections + 1] = Players.PlayerAdded:Connect(bindPlayer)
	serviceConnections[#serviceConnections + 1] = Players.PlayerRemoving:Connect(unbindPlayer)

	for _, player in ipairs(Players:GetPlayers()) do
		bindPlayer(player)
	end
end

return PlayerMovementSpeedService
