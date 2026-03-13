local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local DevilFruitConfig = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("DevilFruits"))

local DevilFruitAssets = {}

local ASSETS_FOLDER_NAME = "Assets"
local DEVIL_FRUITS_FOLDER_NAME = "DevilFruits"
local WORLD_MODEL_NAME = "WorldModel"

local function getDevilFruitAssetsFolder()
	local assetsFolder = ReplicatedStorage:FindFirstChild(ASSETS_FOLDER_NAME)
	if not assetsFolder then
		assetsFolder = ReplicatedStorage:WaitForChild(ASSETS_FOLDER_NAME, 10)
	end

	if not assetsFolder then
		return nil
	end

	local devilFruitsFolder = assetsFolder:FindFirstChild(DEVIL_FRUITS_FOLDER_NAME)
	if not devilFruitsFolder then
		devilFruitsFolder = assetsFolder:WaitForChild(DEVIL_FRUITS_FOLDER_NAME, 10)
	end

	return devilFruitsFolder
end

local function resolveFruit(fruitIdentifier)
	if fruitIdentifier == DevilFruitConfig.None then
		return nil, "no_fruit"
	end

	local fruit = DevilFruitConfig.GetFruit(fruitIdentifier)
	if not fruit then
		return nil, "unknown_fruit"
	end

	return fruit
end

local function getSpawnCFrame(spawnTarget)
	if spawnTarget == nil then
		return nil
	end

	local targetType = typeof(spawnTarget)
	if targetType == "CFrame" then
		return spawnTarget
	end

	if targetType == "Vector3" then
		return CFrame.new(spawnTarget)
	end

	if targetType == "Instance" then
		if spawnTarget:IsA("Attachment") then
			return spawnTarget.WorldCFrame
		end

		if spawnTarget:IsA("PVInstance") then
			return spawnTarget:GetPivot()
		end
	end

	return nil
end

local function applyFruitAttributes(model, fruit)
	model:SetAttribute("FruitKey", fruit.FruitKey)
	model:SetAttribute("FruitName", fruit.DisplayName)
end

local function isSupportedWorldModel(instance)
	return instance and (instance:IsA("Model") or instance:IsA("WorldModel"))
end

function DevilFruitAssets.GetFruitFolder(fruitIdentifier)
	local fruit, reason = resolveFruit(fruitIdentifier)
	if not fruit then
		return nil, reason
	end

	local devilFruitsFolder = getDevilFruitAssetsFolder()
	if not devilFruitsFolder then
		return nil, "missing_assets_root"
	end

	local fruitFolder = devilFruitsFolder:FindFirstChild(fruit.AssetFolder)
	if not fruitFolder then
		return nil, "missing_fruit_folder"
	end

	return fruitFolder, fruit
end

function DevilFruitAssets.GetWorldModel(fruitIdentifier)
	local fruitFolder, fruitOrReason = DevilFruitAssets.GetFruitFolder(fruitIdentifier)
	if not fruitFolder then
		return nil, fruitOrReason
	end

	local worldModel = fruitFolder:FindFirstChild(WORLD_MODEL_NAME)
	if not isSupportedWorldModel(worldModel) then
		return nil, "missing_world_model"
	end

	return worldModel, fruitOrReason
end

function DevilFruitAssets.GetWorldModelByKey(fruitKey)
	return DevilFruitAssets.GetWorldModel(fruitKey)
end

function DevilFruitAssets.ValidateWorldModel(fruitIdentifier)
	local fruit, reason = resolveFruit(fruitIdentifier)
	if not fruit then
		return false, reason
	end

	local worldModel, reason = DevilFruitAssets.GetWorldModel(fruit.FruitKey)
	if not worldModel then
		return false, reason
	end

	local fruitKeyAttribute = worldModel:GetAttribute("FruitKey")
	if fruitKeyAttribute ~= nil and fruitKeyAttribute ~= fruit.FruitKey then
		return false, "fruit_key_mismatch"
	end

	local fruitNameAttribute = worldModel:GetAttribute("FruitName")
	if fruitNameAttribute ~= nil and fruitNameAttribute ~= fruit.DisplayName then
		return false, "fruit_name_mismatch"
	end

	if not worldModel.PrimaryPart then
		return false, "missing_primary_part"
	end

	return true, worldModel, fruit
end

function DevilFruitAssets.HasWorldModel(fruitIdentifier)
	local isValid = DevilFruitAssets.ValidateWorldModel(fruitIdentifier)
	return isValid
end

function DevilFruitAssets.CloneWorldModel(fruitIdentifier, parent)
	local isValid, worldModelOrReason, fruit = DevilFruitAssets.ValidateWorldModel(fruitIdentifier)
	if not isValid then
		return nil, worldModelOrReason
	end

	local clone = worldModelOrReason:Clone()
	applyFruitAttributes(clone, fruit)

	if parent then
		clone.Parent = parent
	end

	return clone
end

function DevilFruitAssets.SpawnWorldModel(fruitIdentifier, spawnTarget, parent)
	local clone, reason = DevilFruitAssets.CloneWorldModel(fruitIdentifier)
	if not clone then
		return nil, reason
	end

	local spawnCFrame = getSpawnCFrame(spawnTarget)
	if spawnTarget ~= nil and not spawnCFrame then
		clone:Destroy()
		return nil, "invalid_spawn_target"
	end

	clone.Parent = parent or Workspace

	if spawnCFrame then
		clone:PivotTo(spawnCFrame)
	end

	return clone
end

return DevilFruitAssets
