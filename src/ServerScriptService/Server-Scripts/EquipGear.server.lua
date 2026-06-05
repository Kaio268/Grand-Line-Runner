local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GearToolsFolder = ReplicatedStorage:FindFirstChild("Gears") or ReplicatedStorage:WaitForChild("Gears", 10)
if not GearToolsFolder then
	warn("[EquipGear] ReplicatedStorage.Gears is missing; gear equip sync disabled.")
	return
end

local function getBackpack(player)
	return player:FindFirstChildOfClass("Backpack") or player:WaitForChild("Backpack", 10)
end

local function removeTool(player, gearName)
	local backpack = getBackpack(player)
	if not backpack then
		return
	end
	local t1 = backpack:FindFirstChild(gearName)
	if t1 and t1:IsA("Tool") then
		t1:Destroy()
	end

	local char = player.Character
	if char then
		local t2 = char:FindFirstChild(gearName)
		if t2 and t2:IsA("Tool") then
			t2:Destroy()
		end
	end
end

local function equipTool(player, gearName)
	local backpack = getBackpack(player)
	if not backpack then
		return
	end
	if backpack:FindFirstChild(gearName) then
		return
	end

	local char = player.Character
	if char and char:FindFirstChild(gearName) then
		return
	end

	local toolTemplate = GearToolsFolder:FindFirstChild(gearName)
	if toolTemplate and toolTemplate:IsA("Tool") then
		toolTemplate:Clone().Parent = backpack
	end
end

local function applyBool(player, bv)
	if bv.Value == true then
		equipTool(player, bv.Name)
	else
		removeTool(player, bv.Name)
	end
end

local function bindBool(player, bv)
	if not bv:IsA("BoolValue") then
		return
	end
	applyBool(player, bv)
	bv.Changed:Connect(function()
		applyBool(player, bv)
	end)
end

local function syncEquippedOnSpawn(player)
	local gearsFolder = player:FindFirstChild("Gears") or player:WaitForChild("Gears", 10)
	if not gearsFolder then
		return
	end
	for _, inst in ipairs(gearsFolder:GetChildren()) do
		if inst:IsA("BoolValue") and inst.Value == true then
			equipTool(player, inst.Name)
		end
	end
end

local function onPlayerAdded(player)
	local gearsFolder = player:FindFirstChild("Gears") or player:WaitForChild("Gears", 10)
	if not gearsFolder then
		warn(string.format("[EquipGear] Player %s missing Gears folder; skipping gear equip binding.", player.Name))
		return
	end

	for _, inst in ipairs(gearsFolder:GetChildren()) do
		bindBool(player, inst)
	end

	gearsFolder.ChildAdded:Connect(function(inst)
		bindBool(player, inst)
	end)

	gearsFolder.ChildRemoved:Connect(function(inst)
		if inst:IsA("BoolValue") then
			removeTool(player, inst.Name)
		end
	end)

	player.CharacterAdded:Connect(function()
		syncEquippedOnSpawn(player)
	end)

	syncEquippedOnSpawn(player)
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, p in ipairs(Players:GetPlayers()) do
	onPlayerAdded(p)
end
