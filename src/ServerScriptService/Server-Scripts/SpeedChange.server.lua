local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MapResolver = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("MapResolver"))
local DECREASE_PART = Workspace:WaitForChild("DecreaseSpeed")
-- Legacy Studio part name. The part is still observed for diagnostics, but it no longer changes speed.
local LEGACY_DECREASE_SPEED_FLOOR = nil
local HitEffectConfig = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("HitEffects"))
local MovementSpeedConfig = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("MovementSpeed"))
local DEBUG_TRACE = RunService:IsStudio()
local SELECTED_SPEED_SETTING_NAME = "SelectedSpeed"
local SPEED_AUTO_MAX_SETTING_NAME = "SpeedAutoMax"
local HORO_GHOST_ATTRIBUTE = "HoroProjectionGhost"
local HORO_BODY_ATTRIBUTE = "HoroProjectionBody"
local HORO_SOURCE_SPEED_ATTRIBUTE = "HoroProjectionSourceWalkSpeed"
local HIE_FREEZE_SHOT_CAST_UNTIL_ATTRIBUTE = "HieFreezeShotCastSlowUntil"
local HIE_FREEZE_SHOT_CAST_SPEED_ATTRIBUTE = "HieFreezeShotCastSpeedMultiplier"
local BOMU_MOVEMENT_LOCK_UNTIL_ATTRIBUTE = "BomuMovementLockUntil"
local BOMU_MOVEMENT_LOCK_SPEED_ATTRIBUTE = "BomuMovementLockSpeedMultiplier"
local MOGU_MOVEMENT_LOCK_UNTIL_ATTRIBUTE = "MoguMovementLockUntil"
local MOGU_MOVEMENT_LOCK_SPEED_ATTRIBUTE = "MoguMovementLockSpeedMultiplier"

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

local function logZoneResolution(context)
	if not DEBUG_TRACE then
		return
	end

	local refs = MapResolver.GetRefs()
	zoneTrace(
		"context=%s activeMap=%s mapPath=%s boundary=%s boundaryPos=%s boundarySize=%s",
		tostring(context),
		tostring(refs.ActiveMapName),
		formatInstancePath(refs.MapRoot),
		formatInstancePath(DECREASE_PART),
		formatVector3(DECREASE_PART.Position),
		formatVector3(DECREASE_PART.Size)
	)
end

logZoneResolution("SpeedChange.server")

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

local function hookCharacter(player, character)
	local humanoid = character:WaitForChild("Humanoid")
	local hidden = player:WaitForChild("HiddenLeaderstats")
	local speedObj = hidden:WaitForChild("Speed")

	local base = humanoid.WalkSpeed
	setAttributeIfChanged(player, MovementSpeedConfig.Attributes.BaseWalkSpeed, base)

	local inDecreaseZone = false

	local touchingCount = 0

	local updating = false
	local bomuExpiryApplyToken = 0
	local moguExpiryApplyToken = 0

	local conns = {}

	local function getEarnedMaxSpeed()
		return math.max(1, math.floor((tonumber(speedObj.Value) or 1) + 0.5))
	end

	local function getSelectedSpeed()
		local earnedMax = getEarnedMaxSpeed()
		local settings = player:FindFirstChild("Settings")
		local autoValue = settings and settings:FindFirstChild(SPEED_AUTO_MAX_SETTING_NAME)
		local selectedValue = settings and settings:FindFirstChild(SELECTED_SPEED_SETTING_NAME)
		local autoMax = true

		if autoValue and autoValue:IsA("BoolValue") then
			autoMax = autoValue.Value == true
		end

		if autoMax then
			return earnedMax
		end

		if selectedValue and (selectedValue:IsA("NumberValue") or selectedValue:IsA("IntValue")) then
			return math.clamp(math.floor((tonumber(selectedValue.Value) or earnedMax) + 0.5), 1, earnedMax)
		end

		return earnedMax
	end

	local function getNormalUnboostedSpeed()
		return base + getSelectedSpeed()
	end

	local function getUnboostedSpeed()
		return getNormalUnboostedSpeed()
	end

	local function isProjectedBody()
		return character:GetAttribute(HORO_BODY_ATTRIBUTE) == true
	end

	local function getNonProjectionDesiredSpeed()
		return getUnboostedSpeed() * getDevilFruitSpeedMultiplier(player) * getHitEffectSpeedMultiplier(player)
	end

	local function getDesiredSpeed()
		if character:GetAttribute(HORO_GHOST_ATTRIBUTE) == true and player:GetAttribute("HoroProjectionActive") == true then
			local ghostSpeed = player:GetAttribute("HoroProjectionGhostSpeed")
			local carrySpeed = player:GetAttribute("HoroProjectionCarrySpeed")
			local carrying = player:GetAttribute("HoroProjectionCarryingReward") == true
			local horoSpeed = if carrying then carrySpeed else ghostSpeed
			if typeof(horoSpeed) == "number" and horoSpeed > 0 then
				return horoSpeed
			end
		end

		return getNonProjectionDesiredSpeed()
	end

	local function apply()
		if updating then return end
		setAttributeIfChanged(player, HORO_SOURCE_SPEED_ATTRIBUTE, getNonProjectionDesiredSpeed())
		if isProjectedBody() then return end
		updating = true
		humanoid.WalkSpeed = getDesiredSpeed()
		updating = false
	end

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
				apply()
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
				apply()
			end
		end)
	end

	local function logSpeedState(reason, oldState, newState)
		zoneTrace(
			"player=%s reason=%s zone=%s zonePos=%s zoneSize=%s oldState=%s newState=%s appliedSpeed=%s base=%s earnedSpeed=%s selectedSpeed=%s normalUnboostedSpeed=%s legacyFloor=%s activeMap=%s mapPath=%s",
			player.Name,
			tostring(reason),
			formatInstancePath(DECREASE_PART),
			formatVector3(DECREASE_PART.Position),
			formatVector3(DECREASE_PART.Size),
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

	apply()
	scheduleBomuLockExpiryApply()
	scheduleMoguLockExpiryApply()
	zoneTrace(
		"player=%s hookCharacter zone=%s initialInZone=%s appliedSpeed=%s character=%s",
		player.Name,
		formatInstancePath(DECREASE_PART),
		tostring(inDecreaseZone),
		tostring(humanoid.WalkSpeed),
		formatInstancePath(character)
	)

	conns[#conns + 1] = speedObj.Changed:Connect(function()
		apply()
	end)

	local function bindSpeedSettingValue(instance)
		if not (instance and instance:IsA("ValueBase")) then
			return
		end
		if instance.Name ~= SELECTED_SPEED_SETTING_NAME and instance.Name ~= SPEED_AUTO_MAX_SETTING_NAME then
			return
		end

		conns[#conns + 1] = instance:GetPropertyChangedSignal("Value"):Connect(function()
			apply()
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
			apply()
		end)
	end

	bindSpeedSettingsFolder(player:FindFirstChild("Settings"))
	apply()
	conns[#conns + 1] = player.ChildAdded:Connect(function(child)
		if child.Name == "Settings" then
			bindSpeedSettingsFolder(child)
			apply()
		end
	end)

	conns[#conns + 1] = player:GetAttributeChangedSignal("HieIceBoostUntil"):Connect(function()
		apply()
	end)

	conns[#conns + 1] = player:GetAttributeChangedSignal("HieIceBoostSpeedMultiplier"):Connect(function()
		apply()
	end)

	conns[#conns + 1] = player:GetAttributeChangedSignal("HieIceBoostSpeedBonus"):Connect(function()
		apply()
	end)

	conns[#conns + 1] = player:GetAttributeChangedSignal(HIE_FREEZE_SHOT_CAST_UNTIL_ATTRIBUTE):Connect(function()
		apply()
	end)

	conns[#conns + 1] = player:GetAttributeChangedSignal(HIE_FREEZE_SHOT_CAST_SPEED_ATTRIBUTE):Connect(function()
		apply()
	end)

	conns[#conns + 1] = player:GetAttributeChangedSignal(BOMU_MOVEMENT_LOCK_UNTIL_ATTRIBUTE):Connect(function()
		apply()
		scheduleBomuLockExpiryApply()
	end)

	conns[#conns + 1] = player:GetAttributeChangedSignal(BOMU_MOVEMENT_LOCK_SPEED_ATTRIBUTE):Connect(function()
		apply()
	end)

	conns[#conns + 1] = player:GetAttributeChangedSignal(MOGU_MOVEMENT_LOCK_UNTIL_ATTRIBUTE):Connect(function()
		apply()
		scheduleMoguLockExpiryApply()
	end)

	conns[#conns + 1] = player:GetAttributeChangedSignal(MOGU_MOVEMENT_LOCK_SPEED_ATTRIBUTE):Connect(function()
		apply()
	end)

	conns[#conns + 1] = player:GetAttributeChangedSignal(HitEffectConfig.Attributes.Until):Connect(function()
		apply()
	end)

	conns[#conns + 1] = player:GetAttributeChangedSignal(HitEffectConfig.Attributes.WalkSpeedMultiplier):Connect(function()
		apply()
	end)

	conns[#conns + 1] = player:GetAttributeChangedSignal("HoroProjectionGhostSpeed"):Connect(function()
		apply()
	end)

	conns[#conns + 1] = player:GetAttributeChangedSignal("HoroProjectionCarrySpeed"):Connect(function()
		apply()
	end)

	conns[#conns + 1] = player:GetAttributeChangedSignal("HoroProjectionActive"):Connect(function()
		apply()
	end)

	conns[#conns + 1] = player:GetAttributeChangedSignal("HoroProjectionCarryingReward"):Connect(function()
		apply()
	end)

	conns[#conns + 1] = character:GetAttributeChangedSignal(HORO_BODY_ATTRIBUTE):Connect(function()
		apply()
	end)

	conns[#conns + 1] = humanoid:GetPropertyChangedSignal("WalkSpeed"):Connect(function()
		if updating then return end
		if isProjectedBody() then return end

		if inDecreaseZone then
			apply()
			return
		end

		local totalSpeedMultiplier = getDevilFruitSpeedMultiplier(player) * getHitEffectSpeedMultiplier(player)
		local expected = getDesiredSpeed()
		if humanoid.WalkSpeed ~= expected then
			if totalSpeedMultiplier <= 0 then
				apply()
				return
			end

			local normalizedSpeed = humanoid.WalkSpeed / totalSpeedMultiplier
			base = normalizedSpeed - getSelectedSpeed()
			setAttributeIfChanged(player, MovementSpeedConfig.Attributes.BaseWalkSpeed, base)
			apply()
		end
	end)

	local function isCharacterPart(part)
		return part and part:IsDescendantOf(character)
	end

	conns[#conns + 1] = DECREASE_PART.Touched:Connect(function(hit)
		if not isCharacterPart(hit) then return end

		touchingCount += 1
		if not inDecreaseZone then
			local oldState = inDecreaseZone
			inDecreaseZone = true
			apply()
			logSpeedState("DecreaseSpeed.Touched", oldState, inDecreaseZone)
		end
	end)

	conns[#conns + 1] = DECREASE_PART.TouchEnded:Connect(function(hit)
		if not isCharacterPart(hit) then return end

		touchingCount -= 1
		if touchingCount <= 0 then
			touchingCount = 0
			if inDecreaseZone then
				local oldState = inDecreaseZone
				inDecreaseZone = false
				apply()
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
		for _, part in ipairs(DECREASE_PART:GetTouchingParts()) do
			if part:IsDescendantOf(character) then
				stillTouching = true
				break
			end
		end

		if not stillTouching then
			local oldState = inDecreaseZone
			inDecreaseZone = false
			touchingCount = 0
			apply()
			logSpeedState("DecreaseSpeed.HeartbeatExit", oldState, inDecreaseZone)
		end
	end)

	conns[#conns + 1] = character.AncestryChanged:Connect(function(_, parent)
		if not parent then
			for _, c in ipairs(conns) do
				c:Disconnect()
			end
		end
	end)
end

Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(function(character)
		hookCharacter(player, character)
	end)

	if player.Character then
		hookCharacter(player, player.Character)
	end
end)
