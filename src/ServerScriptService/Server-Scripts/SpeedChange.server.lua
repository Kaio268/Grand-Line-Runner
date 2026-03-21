local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DECREASE_PART = Workspace:WaitForChild("DecreaseSpeed")
local FORCED_SPEED = 35
local HitEffectConfig = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("HitEffects"))

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

	local function getDesiredSpeed()
		return getUnboostedSpeed() * getDevilFruitSpeedMultiplier(player) * getHitEffectSpeedMultiplier(player)
	end

	local function apply()
		if updating then return end
		updating = true
		humanoid.WalkSpeed = getDesiredSpeed()
		updating = false
	end

	apply()

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

	conns[#conns + 1] = humanoid:GetPropertyChangedSignal("WalkSpeed"):Connect(function()
		if updating then return end

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
			inDecreaseZone = true
			apply()
		end
	end)

	conns[#conns + 1] = DECREASE_PART.TouchEnded:Connect(function(hit)
		if not isCharacterPart(hit) then return end

		touchingCount -= 1
		if touchingCount <= 0 then
			touchingCount = 0
			if inDecreaseZone then
				inDecreaseZone = false
				apply()
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
			inDecreaseZone = false
			touchingCount = 0
			apply()
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
