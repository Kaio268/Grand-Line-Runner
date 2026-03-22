local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local responseRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("DevilFruitConsumeResponse")

local function swapToModifiedR15(player, newModelName)
	local oldCharacter = player.Character
	if not oldCharacter or not oldCharacter.Parent then
		return
	end

	local modelTemplate = ReplicatedStorage.Assets.CharacterModels:FindFirstChild(newModelName)
	if not modelTemplate then
		warn("Could not find model template: " .. newModelName)
		return
	end

	-- 2. SETUP THE NEW RIG
	local originalCFrame = oldCharacter:GetPivot()
	local newCharacter = modelTemplate:Clone()
	newCharacter.Name = player.Name
	newCharacter:PivotTo(originalCFrame)

	local newHumanoid = newCharacter:FindFirstChildOfClass("Humanoid")
	if not newHumanoid then
		return
	end

	-- 3. APPLY APPEARANCE SAFELY (Preserving custom limbs)
	local success, playerDescription = pcall(function()
		return Players:GetHumanoidDescriptionFromUserId(player.UserId)
	end)

	if success and playerDescription then
		-- Force scales to 1 to prevent distortion
		playerDescription.HeadScale = 1
		playerDescription.HeightScale = 1
		playerDescription.WidthScale = 1
		playerDescription.DepthScale = 1

		-- Get the template's current description to preserve its built-in limbs
		local templateDescription = newHumanoid:GetAppliedDescription()

		-- Override the player's limb IDs with the template's limb IDs
		-- This ensures clothes/hats apply, but arms/legs stay the same
		playerDescription.LeftArm = templateDescription.LeftArm
		playerDescription.RightArm = templateDescription.RightArm
		playerDescription.LeftLeg = templateDescription.LeftLeg
		playerDescription.RightLeg = templateDescription.RightLeg
		playerDescription.Torso = templateDescription.Torso

		-- Optional: If you want to force the template's head too, uncomment the line below:
		-- playerDescription.Head = templateDescription.Head

		-- Apply clothing/accessories to the perfectly intact new clone
		pcall(function()
			newHumanoid:ApplyDescription(playerDescription)
		end)
	end

	-- 4. TRANSFER CRITICAL SCRIPTS (Animate & Health)
	-- First, remove any default Animate script that might exist in the template

	-- Explicitly clone the Animate and Health scripts from the original model

	-- 5. PERFORM THE SWAP
	player.Character = newCharacter
	newCharacter.Parent = workspace
	oldCharacter:Destroy() -- Cleans up the old parts safely
end

responseRemote.OnServerEvent:Connect(function(player, success, fruitKey)
	if success and tostring(fruitKey) == "Gomu" then
		swapToModifiedR15(player, "R6G")
	end
end)
