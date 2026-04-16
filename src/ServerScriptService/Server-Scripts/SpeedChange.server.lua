local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MapResolver = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("MapResolver"))
local DECREASE_PART = Workspace:WaitForChild("DecreaseSpeed")
local FORCED_SPEED = 35
local HitEffectConfig = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("HitEffects"))
local DEBUG_TRACE = RunService:IsStudio()
local HORO_GHOST_ATTRIBUTE = "HoroProjectionGhost"
local HORO_BODY_ATTRIBUTE = "HoroProjectionBody"
local HORO_SOURCE_SPEED_ATTRIBUTE = "HoroProjectionSourceWalkSpeed"

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

local function getDevilFruitSpeedMultiplier(player)
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

	local inDecreaseZone = false

	local touchingCount = 0

	local updating = false

	local conns = {}

	local function getUnboostedSpeed()
		if inDecreaseZone then
			return FORCED_SPEED
		end

		return base + speedObj.Value
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

	local function logSpeedState(reason, oldState, newState)
		zoneTrace(
			"player=%s reason=%s zone=%s zonePos=%s zoneSize=%s oldState=%s newState=%s appliedSpeed=%s base=%s purchasedSpeed=%s activeMap=%s mapPath=%s",
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
			tostring(MapResolver.GetRefs().ActiveMapName),
			formatInstancePath(MapResolver.GetRefs().MapRoot)
		)
	end

	apply()
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

	conns[#conns + 1] = player:GetAttributeChangedSignal("HieIceBoostUntil"):Connect(function()
		apply()
	end)

	conns[#conns + 1] = player:GetAttributeChangedSignal("HieIceBoostSpeedMultiplier"):Connect(function()
		apply()
	end)

	conns[#conns + 1] = player:GetAttributeChangedSignal("HieIceBoostSpeedBonus"):Connect(function()
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
			base = normalizedSpeed - speedObj.Value
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
