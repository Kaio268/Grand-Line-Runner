local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DevilFruitConfig = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("DevilFruits"))
local HitEffectConfig = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("HitEffects"))

local function getJumpHeightMultiplier(player)
	local fruitName = player:GetAttribute("EquippedDevilFruit")
	if typeof(fruitName) ~= "string" or fruitName == "" then
		fruitName = nil
	end

	local fruit = fruitName and DevilFruitConfig.GetFruit(fruitName) or nil
	local glideConfig = fruit and fruit.Passives and fruit.Passives.PhoenixGlide
	local jumpHeightMultiplier = glideConfig and tonumber(glideConfig.JumpHeightMultiplier)
	if not jumpHeightMultiplier or jumpHeightMultiplier <= 0 then
		jumpHeightMultiplier = 1
	end

	local attributes = HitEffectConfig.Attributes
	local untilTime = player:GetAttribute(attributes.Until)
	local hitEffectJumpMultiplier = player:GetAttribute(attributes.JumpMultiplier)
	if typeof(untilTime) == "number" and typeof(hitEffectJumpMultiplier) == "number" and untilTime > os.clock() then
		jumpHeightMultiplier *= math.max(0, hitEffectJumpMultiplier)
	end

	return jumpHeightMultiplier
end

local function getJumpPowerMultiplier(player)
	local jumpHeightMultiplier = getJumpHeightMultiplier(player)
	if jumpHeightMultiplier <= 0 then
		return 0
	end

	return math.sqrt(jumpHeightMultiplier)
end

local function hookCharacter(player, character)
	local humanoid = character:WaitForChild("Humanoid")

	local baseJumpPower = humanoid.JumpPower
	local baseJumpHeight = humanoid.JumpHeight
	local updating = false
	local connections = {}

	local function apply()
		if updating then
			return
		end

		updating = true

		if humanoid.UseJumpPower then
			humanoid.JumpPower = baseJumpPower * getJumpPowerMultiplier(player)
		else
			humanoid.JumpHeight = baseJumpHeight * getJumpHeightMultiplier(player)
		end

		updating = false
	end

	apply()

	connections[#connections + 1] = player:GetAttributeChangedSignal("EquippedDevilFruit"):Connect(function()
		apply()
	end)

	connections[#connections + 1] = player:GetAttributeChangedSignal(HitEffectConfig.Attributes.Until):Connect(function()
		apply()
	end)

	connections[#connections + 1] = player:GetAttributeChangedSignal(HitEffectConfig.Attributes.JumpMultiplier):Connect(function()
		apply()
	end)

	connections[#connections + 1] = humanoid:GetPropertyChangedSignal("UseJumpPower"):Connect(function()
		if updating then
			return
		end

		if humanoid.UseJumpPower then
			local currentMultiplier = getJumpPowerMultiplier(player)
			baseJumpPower = humanoid.JumpPower / math.max(currentMultiplier, 0.01)
		else
			local currentMultiplier = getJumpHeightMultiplier(player)
			baseJumpHeight = humanoid.JumpHeight / math.max(currentMultiplier, 0.01)
		end

		apply()
	end)

	connections[#connections + 1] = humanoid:GetPropertyChangedSignal("JumpPower"):Connect(function()
		if updating or not humanoid.UseJumpPower then
			return
		end

		local jumpPowerMultiplier = math.max(getJumpPowerMultiplier(player), 0.01)
		baseJumpPower = humanoid.JumpPower / jumpPowerMultiplier
		apply()
	end)

	connections[#connections + 1] = humanoid:GetPropertyChangedSignal("JumpHeight"):Connect(function()
		if updating or humanoid.UseJumpPower then
			return
		end

		local jumpHeightMultiplier = math.max(getJumpHeightMultiplier(player), 0.01)
		baseJumpHeight = humanoid.JumpHeight / jumpHeightMultiplier
		apply()
	end)

	connections[#connections + 1] = character.AncestryChanged:Connect(function(_, parent)
		if parent ~= nil then
			return
		end

		for _, connection in ipairs(connections) do
			connection:Disconnect()
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

for _, player in ipairs(Players:GetPlayers()) do
	if player.Character then
		hookCharacter(player, player.Character)
	end
end
