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
	if not char then
		return nil
	end
	-- The character might have just swapped, so we search the current character
	return char:FindFirstChildOfClass("Humanoid")
end

local function findInventoryTool(container, kind, name)
	if not container then
		return nil
	end

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
	if not char then
		return
	end
	local humanoid = getHumanoid(player)
	if not humanoid then
		return
	end
	local t = findInventoryTool(char, itemKind, toolName) or char:FindFirstChild(toolName)
	if t and t:IsA("Tool") then
		humanoid:UnequipTools()
	end
end

local function ownsBrainrot(player, name)
	local inv = player:FindFirstChild("Inventory")
	if not inv then
		return false
	end
	local f = inv:FindFirstChild(name)
	if not f or not f:IsA("Folder") then
		return false
	end
	local q = f:FindFirstChild("Quantity")
	if not q or not q:IsA("NumberValue") then
		return false
	end
	return q.Value > 0
end

local function ownsGear(player, name)
	local gears = player:FindFirstChild("Gears")
	if not gears then
		return false
	end
	local bv = gears:FindFirstChild(name)
	if not bv or not bv:IsA("BoolValue") then
		return false
	end
	return bv.Value == true
end

local function ownsDevilFruit(player, fruitKey)
	local inv = player:FindFirstChild("Inventory")
	if not inv then
		return false
	end
	local devilFruits = inv:FindFirstChild("DevilFruits")
	if not devilFruits or not devilFruits:IsA("Folder") then
		return false
	end
	local fruitFolder = devilFruits:FindFirstChild(fruitKey)
	if not fruitFolder or not fruitFolder:IsA("Folder") then
		return false
	end
	local q = fruitFolder:FindFirstChild("Quantity")
	if not q or not q:IsA("NumberValue") then
		return false
	end
	return q.Value > 0
end

local function toggleEquip(player, kind, name)
	local char = player.Character
	if not char then
		return
	end

	local humanoid = getHumanoid(player)
	if not humanoid then
		return
	end

	-- 1. Check if the tool is already equipped (in the Character)
	local equipped = findInventoryTool(char, kind, name)
	if equipped then
		humanoid:UnequipTools()
		-- Clean up any manual grips we created
		local manualGrip = char:FindFirstChild("ManualGrip", true)
		if manualGrip then
			manualGrip:Destroy()
		end
		return
	end

	-- 2. Find the tool in the Backpack
	local bp = player:FindFirstChild("Backpack")
	if not bp then
		return
	end

	local tool = findInventoryTool(bp, kind, name)
	if not tool then
		return
	end

	-- 3. Clear current tools and Equip the new one
	humanoid:UnequipTools()
	humanoid:EquipTool(tool)

	-- 4. R6G MODEL FIX: Manual Weld Enforcement
	-- We defer the logic to wait one frame for Roblox's default system to try and fail
	task.defer(function()
		if tool.Parent ~= char then
			return
		end

		local handle = tool:FindFirstChild("Handle")
		if not handle then
			return
		end

		-- Check if Roblox successfully created a RightGrip weld
		local existingGrip = char:FindFirstChild("RightGrip", true)
		local isActualWeld = existingGrip and existingGrip:IsA("Weld")

		if not isActualWeld then
			-- Identify the correct arm part for the R6G model
			local gripPart = char:FindFirstChild("RightHand") or char:FindFirstChild("RightLowerArm") or char:FindFirstChild("Right Arm")

			if gripPart then
				-- Create a manual weld because Roblox's default system ignored this rig
				local weld = Instance.new("Weld")
				weld.Name = "ManualGrip"
				weld.Part0 = gripPart
				weld.Part1 = handle
				weld.C1 = tool.Grip -- Keeps the offset defined in buildFruitTool

				-- Use an attachment for positioning if the rig has one
				local attachment = gripPart:FindFirstChild("RightGripAttachment")
					or gripPart:FindFirstChild("RightGrip")
				if attachment and attachment:IsA("Attachment") then
					weld.C0 = attachment.CFrame
				end

				weld.Parent = handle
				print("[Inventory] Applied manual weld for R6G model compatibility.")
			end
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
		if hooked[folder] then
			return
		end
		hooked[folder] = true

		local qty = folder:WaitForChild("Quantity", 10)
		if not qty or not qty:IsA("NumberValue") then
			return
		end

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
		if devilFruitHooked[folder] then
			return
		end
		devilFruitHooked[folder] = true

		local qty = folder:WaitForChild("Quantity", 10)
		if not qty or not qty:IsA("NumberValue") then
			return
		end

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
		if hooked[bv] then
			return
		end
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
	if typeof(kind) ~= "string" or typeof(name) ~= "string" then
		return
	end

	if kind == "Brainrot" then
		if not ownsBrainrot(player, name) then
			return
		end
		toggleEquip(player, kind, name)
		return
	end

	if kind == "Gear" then
		if not ownsGear(player, name) then
			return
		end
		toggleEquip(player, kind, name)
		return
	end

	if kind == "DevilFruit" then
		if not ownsDevilFruit(player, name) then
			return
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
	end

	Players.PlayerAdded:Connect(setup)
	for _, p in ipairs(Players:GetPlayers()) do
		task.spawn(setup, p)
	end
end

return Module
