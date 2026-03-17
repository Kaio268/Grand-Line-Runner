local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

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
local chestToolServiceCache = nil
local sliceServiceCache = nil
local CHEST_DEBUG = true

local function chestDebug(message, ...)
	if CHEST_DEBUG ~= true then
		return
	end

	warn(string.format("[GLR ChestDebug][InventorySystem] " .. tostring(message), ...))
end

local function getChestToolService()
	if chestToolServiceCache ~= nil then
		return chestToolServiceCache
	end

	local ok, service = pcall(function()
		return require(game:GetService("ServerScriptService"):WaitForChild("Modules"):WaitForChild("GrandLineRushChestToolService"))
	end)

	chestToolServiceCache = if ok then service else false
	return if chestToolServiceCache == false then nil else chestToolServiceCache
end

local function getSliceService()
	if sliceServiceCache ~= nil then
		return sliceServiceCache
	end

	local ok, service = pcall(function()
		return require(ServerScriptService:WaitForChild("Modules"):WaitForChild("GrandLineRushVerticalSliceService"))
	end)

	sliceServiceCache = if ok then service else false
	return if sliceServiceCache == false then nil else sliceServiceCache
end

local function getHumanoid(player)
	local char = player.Character
	if not char then return nil end
	return char:FindFirstChildOfClass("Humanoid")
end

local function findInventoryTool(container, kind, name)
	if not container then return nil end

	for _, child in ipairs(container:GetChildren()) do
		if child:IsA("Tool") then
			local itemKind = child:GetAttribute("InventoryItemKind")
			local itemName = child:GetAttribute("InventoryItemName")
			if itemKind == kind and itemName == name then
				return child
			end

			if child.Name == name then
				return child
			end
		end
	end

	return nil
end

local function unequipIfEquipped(player, toolName, itemKind)
	local char = player.Character
	if not char then return end
	local humanoid = getHumanoid(player)
	if not humanoid then return end
	local t = findInventoryTool(char, itemKind, toolName) or char:FindFirstChild(toolName)
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

local function ownsDevilFruit(player, fruitKey)
	local inv = player:FindFirstChild("Inventory")
	if not inv then return false end
	local devilFruits = inv:FindFirstChild("DevilFruits")
	if not devilFruits or not devilFruits:IsA("Folder") then return false end
	local fruitFolder = devilFruits:FindFirstChild(fruitKey)
	if not fruitFolder or not fruitFolder:IsA("Folder") then return false end
	local q = fruitFolder:FindFirstChild("Quantity")
	if not q or not q:IsA("NumberValue") then return false end
	return q.Value > 0
end

local function ownsChest(player, tierName)
	local sliceService = getSliceService()
	if sliceService and sliceService.GetState then
		local state = sliceService.GetState(player)
		local unopenedChests = state and state.UnopenedChests or {}
		for _, chest in ipairs(unopenedChests) do
			if tostring(chest.Tier) == tostring(tierName) then
				return true
			end
		end
	end

	local chestInventory = player:FindFirstChild("ChestInventory")
	if not chestInventory then return false end
	local folder = chestInventory:FindFirstChild(tierName)
	if not folder or not folder:IsA("Folder") then return false end
	local q = folder:FindFirstChild("Quantity")
	if not q or not q:IsA("NumberValue") then return false end
	return q.Value > 0
end

local function toggleEquip(player, kind, toolName)
	local humanoid = getHumanoid(player)
	if not humanoid then return end

	local char = player.Character
	if not char then return end

	local equipped = findInventoryTool(char, kind, toolName) or char:FindFirstChild(toolName)
	if equipped and equipped:IsA("Tool") then
		if kind == "Chest" then
			chestDebug(
				"toggleEquip chest already equipped player=%s tool=%s -> unequip",
				player.Name,
				tostring(toolName)
			)
		end
		humanoid:UnequipTools()
		return
	end

	local bp = player:FindFirstChild("Backpack")
	if not bp then return end

	local tool = findInventoryTool(bp, kind, toolName) or bp:FindFirstChild(toolName)
	if kind == "Chest" then
		chestDebug(
			"toggleEquip chest pre-equip player=%s tool=%s backpackTool=%s backpack=%s",
			player.Name,
			tostring(toolName),
			tostring(tool ~= nil and tool:IsA("Tool")),
			bp:GetFullName()
		)
	end
	if not tool or not tool:IsA("Tool") then return end

	humanoid:UnequipTools()
	if kind == "Chest" then
		chestDebug("toggleEquip chest calling Humanoid:EquipTool player=%s tool=%s", player.Name, tostring(tool.Name))
	end
	humanoid:EquipTool(tool)

	task.defer(function()
		if player.Parent ~= Players then
			return
		end

		local refreshedChar = player.Character
		if not refreshedChar then
			return
		end

		local equipped = findInventoryTool(refreshedChar, kind, toolName) or refreshedChar:FindFirstChild(toolName)
		if equipped and equipped:IsA("Tool") then
			if kind == "Chest" then
				chestDebug(
					"toggleEquip chest success player=%s tool=%s parent=%s",
					player.Name,
					tostring(equipped.Name),
					equipped.Parent and equipped.Parent:GetFullName() or "nil"
				)
			end
			return
		end

		local backpack = player:FindFirstChildOfClass("Backpack")
		local fallbackTool = findInventoryTool(backpack, kind, toolName) or (backpack and backpack:FindFirstChild(toolName))
		if fallbackTool and fallbackTool:IsA("Tool") then
			if kind == "Chest" then
				chestDebug(
					"toggleEquip chest fallback parent->Character player=%s tool=%s from=%s",
					player.Name,
					tostring(fallbackTool.Name),
					fallbackTool.Parent and fallbackTool.Parent:GetFullName() or "nil"
				)
			end
			pcall(function()
				fallbackTool.Parent = refreshedChar
			end)
		elseif kind == "Chest" then
			chestDebug(
				"toggleEquip chest failed to find tool after EquipTool player=%s tool=%s",
				player.Name,
				tostring(toolName)
			)
		end
	end)
end

local function watchInventory(player, inventory)
	local hooked = {}
	local devilFruitHooked = {}

	local function push(name, qty)
		updateRemote:FireClient(player, "Brainrot", name, qty)
	end

	local function pushDevilFruit(name, qty)
		updateRemote:FireClient(player, "DevilFruit", name, qty)
	end

	local function hookFolder(folder)
		if hooked[folder] then return end
		hooked[folder] = true

		local qty = folder:WaitForChild("Quantity", 10)
		if not qty or not qty:IsA("NumberValue") then return end

		push(folder.Name, qty.Value)
		if qty.Value <= 0 then
			unequipIfEquipped(player, folder.Name, "Brainrot")
		end

		qty.Changed:Connect(function()
			push(folder.Name, qty.Value)
			if qty.Value <= 0 then
				unequipIfEquipped(player, folder.Name, "Brainrot")
			end
		end)
	end

	local function hookDevilFruitFolder(folder)
		if devilFruitHooked[folder] then return end
		devilFruitHooked[folder] = true

		local qty = folder:WaitForChild("Quantity", 10)
		if not qty or not qty:IsA("NumberValue") then return end

		pushDevilFruit(folder.Name, qty.Value)
		if qty.Value <= 0 then
			unequipIfEquipped(player, folder.Name, "DevilFruit")
		end

		qty.Changed:Connect(function()
			pushDevilFruit(folder.Name, qty.Value)
			if qty.Value <= 0 then
				unequipIfEquipped(player, folder.Name, "DevilFruit")
			end
		end)
	end

	for _, ch in ipairs(inventory:GetChildren()) do
		if ch:IsA("Folder") and ch.Name ~= "DevilFruits" then
			hookFolder(ch)
		elseif ch:IsA("Folder") and ch.Name == "DevilFruits" then
			for _, fruitFolder in ipairs(ch:GetChildren()) do
				if fruitFolder:IsA("Folder") then
					hookDevilFruitFolder(fruitFolder)
				end
			end

			ch.ChildAdded:Connect(function(fruitFolder)
				if fruitFolder:IsA("Folder") then
					hookDevilFruitFolder(fruitFolder)
				end
			end)

			ch.ChildRemoved:Connect(function(fruitFolder)
				if fruitFolder:IsA("Folder") then
					pushDevilFruit(fruitFolder.Name, 0)
					unequipIfEquipped(player, fruitFolder.Name, "DevilFruit")
				end
			end)
		end
	end

	inventory.ChildAdded:Connect(function(ch)
		if ch:IsA("Folder") and ch.Name ~= "DevilFruits" then
			hookFolder(ch)
		elseif ch:IsA("Folder") and ch.Name == "DevilFruits" then
			for _, fruitFolder in ipairs(ch:GetChildren()) do
				if fruitFolder:IsA("Folder") then
					hookDevilFruitFolder(fruitFolder)
				end
			end

			ch.ChildAdded:Connect(function(fruitFolder)
				if fruitFolder:IsA("Folder") then
					hookDevilFruitFolder(fruitFolder)
				end
			end)

			ch.ChildRemoved:Connect(function(fruitFolder)
				if fruitFolder:IsA("Folder") then
					pushDevilFruit(fruitFolder.Name, 0)
					unequipIfEquipped(player, fruitFolder.Name, "DevilFruit")
				end
			end)
		end
	end)

	inventory.ChildRemoved:Connect(function(ch)
		if ch:IsA("Folder") and ch.Name ~= "DevilFruits" then
			push(ch.Name, 0)
			unequipIfEquipped(player, ch.Name, "Brainrot")
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

local function watchChestInventory(player, chestInventory)
	local hooked = {}

	local function push(name, qty)
		chestDebug("InventoryGearRemote fire from watcher player=%s payload={kind=Chest,name=%s,qty=%s}", player.Name, tostring(name), tostring(qty))
		updateRemote:FireClient(player, "Chest", name, qty)
	end

	local function hookFolder(folder)
		if hooked[folder] then return end
		hooked[folder] = true

		local qty = folder:WaitForChild("Quantity", 10)
		if not qty or not qty:IsA("NumberValue") then return end

		chestDebug("watchChestInventory hook player=%s tier=%s initialQty=%s", player.Name, folder.Name, tostring(qty.Value))
		push(folder.Name, qty.Value)
		if qty.Value <= 0 then
			unequipIfEquipped(player, folder.Name, "Chest")
		end

		qty.Changed:Connect(function()
			chestDebug("watchChestInventory changed player=%s tier=%s qty=%s", player.Name, folder.Name, tostring(qty.Value))
			push(folder.Name, qty.Value)
			if qty.Value <= 0 then
				unequipIfEquipped(player, folder.Name, "Chest")
			end
		end)
	end

	for _, ch in ipairs(chestInventory:GetChildren()) do
		if ch:IsA("Folder") then
			hookFolder(ch)
		end
	end

	chestInventory.ChildAdded:Connect(function(ch)
		if ch:IsA("Folder") then
			hookFolder(ch)
		end
	end)

	chestInventory.ChildRemoved:Connect(function(ch)
		if ch:IsA("Folder") then
			push(ch.Name, 0)
			unequipIfEquipped(player, ch.Name, "Chest")
		end
	end)
end

equipRemote.OnServerEvent:Connect(function(player, kind, name)
	if typeof(kind) ~= "string" or typeof(name) ~= "string" then return end
	if kind == "Chest" then
		chestDebug(
			"EquipToggleRemote received player=%s payload={kind=%s,name=%s}",
			player.Name,
			tostring(kind),
			tostring(name)
		)
	end

	if kind == "Brainrot" then
		if not ownsBrainrot(player, name) then return end
		toggleEquip(player, kind, name)
		return
	end

	if kind == "Gear" then
		if not ownsGear(player, name) then return end
		toggleEquip(player, kind, name)
		return
	end

	if kind == "DevilFruit" then
		if not ownsDevilFruit(player, name) then return end
		toggleEquip(player, kind, name)
		return
	end

	if kind == "Chest" then
		local owns = ownsChest(player, name)
		chestDebug("Chest equip validation player=%s tier=%s ownsChest=%s", player.Name, tostring(name), tostring(owns))
		if not owns then return end
		local chestToolService = getChestToolService()
		if chestToolService and chestToolService.EnsureToolForTier then
			local ensuredTool = chestToolService.EnsureToolForTier(player, name)
			chestDebug(
				"Chest EnsureToolForTier result player=%s tier=%s tool=%s parent=%s",
				player.Name,
				tostring(name),
				ensuredTool and ensuredTool.Name or "nil",
				ensuredTool and ensuredTool.Parent and ensuredTool.Parent:GetFullName() or "nil"
			)
		else
			chestDebug("Chest equip missing ChestToolService player=%s tier=%s", player.Name, tostring(name))
		end
		toggleEquip(player, kind, name)
		return
	end
end)

function Module.Start()
	local function setup(player)
		local inv = player:WaitForChild("Inventory")
		local gears = player:WaitForChild("Gears")
		watchInventory(player, inv)
		watchGears(player, gears)

		local chestInventory = player:FindFirstChild("ChestInventory") or player:WaitForChild("ChestInventory", 10)
		if chestInventory and chestInventory:IsA("Folder") then
			watchChestInventory(player, chestInventory)
		else
			player.ChildAdded:Connect(function(child)
				if child.Name == "ChestInventory" and child:IsA("Folder") then
					watchChestInventory(player, child)
				end
			end)
		end
	end

	Players.PlayerAdded:Connect(setup)
	for _, p in ipairs(Players:GetPlayers()) do
		task.spawn(setup, p)
	end
end

return Module
