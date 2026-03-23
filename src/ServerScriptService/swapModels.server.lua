local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local responseRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("DevilFruitConsumeResponse")

-- Table to keep track of who has which fruit
local playerFruits = {}

local function swapToModifiedR15(player, newModelName)
	local character = player.Character or player.CharacterAdded:Wait()
	-- Wait a frame to ensure the character is fully in the workspace
	task.wait()

	local modelTemplate = ReplicatedStorage.Assets.CharacterModels:FindFirstChild(newModelName)
	if not modelTemplate then
		warn("Could not find model template: " .. newModelName)
		return
	end

	-- 1. SETUP THE NEW RIG
	local originalCFrame = character:GetPivot()
	local newCharacter = modelTemplate:Clone()
	newCharacter.Name = player.Name

	local newHumanoid = newCharacter:FindFirstChildOfClass("Humanoid")
	if not newHumanoid then
		return
	end

	-- 2. APPLY APPEARANCE
	local success, playerDescription = pcall(function()
		return Players:GetHumanoidDescriptionFromUserId(player.UserId)
	end)

	if success and playerDescription then
		playerDescription.HeadScale, playerDescription.HeightScale = 1, 1
		playerDescription.WidthScale, playerDescription.DepthScale = 1, 1

		local templateDescription = newHumanoid:GetAppliedDescription()
		playerDescription.LeftArm = templateDescription.LeftArm
		playerDescription.RightArm = templateDescription.RightArm
		playerDescription.LeftLeg = templateDescription.LeftLeg
		playerDescription.RightLeg = templateDescription.RightLeg
		playerDescription.Torso = templateDescription.Torso

		pcall(function()
			newHumanoid:ApplyDescription(playerDescription)
		end)
	end

	-- 3. PERFORM THE SWAP
	-- Setting .Character automatically destroys the old one in most cases,
	-- but we do it manually to be safe.
	player.Character = newCharacter
	newCharacter:PivotTo(originalCFrame)
	newCharacter.Parent = workspace

	character:Destroy()
end

-- Handle the initial consumption
responseRemote.OnServerEvent:Connect(function(player, success, fruitKey)
	if success and tostring(fruitKey) == "Gomu" then
		playerFruits[player.UserId] = "R6G" -- Store the model name for this player
		swapToModifiedR15(player, "R6G")
	end
end)

-- Handle Respawns
Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(function(character)
		-- Check if this player is supposed to have a custom model
		local fruitModel = playerFruits[player.UserId]
		if fruitModel then
			swapToModifiedR15(player, fruitModel)
		end
	end)
end)

-- Cleanup when player leaves
Players.PlayerRemoving:Connect(function(player)
	playerFruits[player.UserId] = nil
end)
