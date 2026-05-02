local Players = game:GetService("Players")

local AbilityTargeting = {}

local function isAliveHumanoid(humanoid)
	return humanoid and humanoid:IsA("Humanoid") and humanoid.Health > 0
end

local function getHumanoidRootPart(character)
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	if rootPart and rootPart:IsA("BasePart") then
		return rootPart
	end

	return nil
end

local function buildTargetContext(target, player, character, humanoid, rootPart)
	return {
		Instance = target,
		Player = player,
		Character = character,
		Humanoid = humanoid,
		RootPart = rootPart,
		IsPlayer = player ~= nil,
	}
end

function AbilityTargeting.GetPlayerCharacterContext(player)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return nil
	end

	local character = player.Character
	if not character then
		return nil
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local rootPart = getHumanoidRootPart(character)
	if not isAliveHumanoid(humanoid) or not rootPart then
		return nil
	end

	return buildTargetContext(player, player, character, humanoid, rootPart)
end

function AbilityTargeting.GetCharacterContext(target)
	if typeof(target) ~= "Instance" then
		return nil
	end

	if target:IsA("Player") then
		return AbilityTargeting.GetPlayerCharacterContext(target)
	end

	if target:IsA("Model") then
		local player = Players:GetPlayerFromCharacter(target)
		if player then
			return AbilityTargeting.GetPlayerCharacterContext(player)
		end
	end

	return nil
end

function AbilityTargeting.GetCharacterContextFromDescendant(instance)
	if typeof(instance) ~= "Instance" then
		return nil
	end

	local model = if instance:IsA("Model") then instance else instance:FindFirstAncestorOfClass("Model")
	if not model then
		return nil
	end

	return AbilityTargeting.GetCharacterContext(model)
end

function AbilityTargeting.GetCharacterTargets(options)
	options = type(options) == "table" and options or {}

	local includePlayers = options.IncludePlayers ~= false
	local excludePlayer = options.ExcludePlayer
	local excludeCharacter = options.ExcludeCharacter
	local targets = {}

	if includePlayers then
		for _, player in ipairs(Players:GetPlayers()) do
			if player ~= excludePlayer then
				local context = AbilityTargeting.GetPlayerCharacterContext(player)
				if context and context.Character ~= excludeCharacter then
					targets[#targets + 1] = context
				end
			end
		end
	end

	return targets
end

function AbilityTargeting.ForEachCharacterTarget(options, callback)
	if type(callback) ~= "function" then
		return 0
	end

	local count = 0
	for _, targetContext in ipairs(AbilityTargeting.GetCharacterTargets(options)) do
		count += 1
		callback(targetContext)
	end

	return count
end

return AbilityTargeting
