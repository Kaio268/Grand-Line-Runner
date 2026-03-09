local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local updateRemote = ReplicatedStorage:FindFirstChild("InventoryGearRemote")
if not updateRemote then
	updateRemote = Instance.new("RemoteEvent")
	updateRemote.Name = "InventoryGearRemote"
	updateRemote.Parent = ReplicatedStorage
end

local equipRemote = ReplicatedStorage:FindFirstChild("EquipToggleRemote")
if not equipRemote then
	equipRemote = Instance.new("RemoteEvent")
	equipRemote.Name = "EquipToggleRemote"
	equipRemote.Parent = ReplicatedStorage
end

local Module = {}

local function getHumanoid(player)
	local char = player.Character
	if not char then return nil end
	return char:FindFirstChildOfClass("Humanoid")
end

local function unequipIfEquipped(player, toolName)
	local char = player.Character
	if not char then return end
	local humanoid = getHumanoid(player)
	if not humanoid then return end
	local t = char:FindFirstChild(toolName)
	if t and t:IsA("Tool") then
		humanoid:UnequipTools()
	end
end

local function ownsBrainrot(player, name)
	local inv = player:FindFirstChild("Inventory")
	if not inv then return false end
	local f = inv:FindFirstChild(name)
	if not f or not f:IsA("Folder") then return false end
	local q = f:FindFirstChild("Quantity")
	if not q or not q:IsA("NumberValue") then return false end
	return q.Value > 0
end

local function ownsGear(player, name)
	local gears = player:FindFirstChild("Gears")
	if not gears then return false end
	local bv = gears:FindFirstChild(name)
	if not bv or not bv:IsA("BoolValue") then return false end
	return bv.Value == true
end

local function toggleEquip(player, toolName)
	local humanoid = getHumanoid(player)
	if not humanoid then return end

	local char = player.Character
	if not char then return end

	local equipped = char:FindFirstChild(toolName)
	if equipped and equipped:IsA("Tool") then
		humanoid:UnequipTools()
		return
	end

	local bp = player:FindFirstChild("Backpack")
	if not bp then return end

	local tool = bp:FindFirstChild(toolName)
	if not tool or not tool:IsA("Tool") then return end

	humanoid:UnequipTools()
	humanoid:EquipTool(tool)
end

local function watchInventory(player, inventory)
	local hooked = {}

	local function push(name, qty)
		updateRemote:FireClient(player, "Brainrot", name, qty)
	end

	local function hookFolder(folder)
		if hooked[folder] then return end
		hooked[folder] = true

		local qty = folder:WaitForChild("Quantity", 10)
		if not qty or not qty:IsA("NumberValue") then return end

		push(folder.Name, qty.Value)
		if qty.Value <= 0 then
			unequipIfEquipped(player, folder.Name)
		end

		qty.Changed:Connect(function()
			push(folder.Name, qty.Value)
			if qty.Value <= 0 then
				unequipIfEquipped(player, folder.Name)
			end
		end)
	end

	for _, ch in ipairs(inventory:GetChildren()) do
		if ch:IsA("Folder") then
			hookFolder(ch)
		end
	end

	inventory.ChildAdded:Connect(function(ch)
		if ch:IsA("Folder") then
			hookFolder(ch)
		end
	end)

	inventory.ChildRemoved:Connect(function(ch)
		if ch:IsA("Folder") then
			push(ch.Name, 0)
			unequipIfEquipped(player, ch.Name)
		end
	end)
end

local function watchGears(player, gearsFolder)
	local hooked = {}

	local function push(name, owned)
		updateRemote:FireClient(player, "Gear", name, owned)
	end

	local function hookBool(bv)
		if hooked[bv] then return end
		hooked[bv] = true

		push(bv.Name, bv.Value)
		if bv.Value == false then
			unequipIfEquipped(player, bv.Name)
		end

		bv.Changed:Connect(function()
			push(bv.Name, bv.Value)
			if bv.Value == false then
				unequipIfEquipped(player, bv.Name)
			end
		end)
	end

	for _, ch in ipairs(gearsFolder:GetChildren()) do
		if ch:IsA("BoolValue") then
			hookBool(ch)
		end
	end

	gearsFolder.ChildAdded:Connect(function(ch)
		if ch:IsA("BoolValue") then
			hookBool(ch)
		end
	end)

	gearsFolder.ChildRemoved:Connect(function(ch)
		if ch:IsA("BoolValue") then
			push(ch.Name, false)
			unequipIfEquipped(player, ch.Name)
		end
	end)
end

equipRemote.OnServerEvent:Connect(function(player, kind, name)
	if typeof(kind) ~= "string" or typeof(name) ~= "string" then return end

	if kind == "Brainrot" then
		if not ownsBrainrot(player, name) then return end
		toggleEquip(player, name)
		return
	end

	if kind == "Gear" then
		if not ownsGear(player, name) then return end
		toggleEquip(player, name)
		return
	end
end)

function Module.Start()
	local function setup(player)
		local inv = player:WaitForChild("Inventory")
		local gears = player:WaitForChild("Gears")
		watchInventory(player, inv)
		watchGears(player, gears)
	end

	Players.PlayerAdded:Connect(setup)
	for _, p in ipairs(Players:GetPlayers()) do
		task.spawn(setup, p)
	end
end

return Module
