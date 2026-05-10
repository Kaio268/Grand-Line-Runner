local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local CrewModules = Modules:WaitForChild("Crew")
local CrewCatalog = require(CrewModules:WaitForChild("CrewCatalog"))
local CrewRegistry = require(CrewModules:WaitForChild("CrewRegistry"))

local function getInventory(player)
	return player:FindFirstChild("Invnetory") or player:FindFirstChild("Inventory")
end

local function getItemTools(container, itemName)
	local out = {}
	if not container then
		return out
	end
	for _, child in ipairs(container:GetChildren()) do
		if child:IsA("Tool") and child:GetAttribute("InvItem") == itemName then
			table.insert(out, child)
		end
	end
	return out
end

local function getVariantAndBaseName(itemName)
	return CrewCatalog.ParseVariantId(itemName)
end

local function findTemplate(itemName)
	local variantKey, baseName = getVariantAndBaseName(itemName)
	local template, usedVariant = CrewRegistry.GetTemplateWithFallback(baseName, variantKey)
	if template then
		return template, usedVariant or variantKey, baseName
	end

	template, usedVariant = CrewRegistry.GetTemplateWithFallback(itemName, "Normal")
	return template, usedVariant or variantKey, baseName
end

local function makeTool(itemName)
	local template, variantKey, baseName = findTemplate(itemName)
	if not template then
		return nil
	end

	local tool = Instance.new("Tool")
	tool.Name = itemName
	tool.RequiresHandle = true
	tool.CanBeDropped = false
	tool:SetAttribute("InvItem", itemName)

	tool:SetAttribute("Variant", variantKey)
	tool:SetAttribute("BaseName", baseName)

	local function setupPart(part)
		part.Anchored = false
		part.CanCollide = false
		part.Massless = true
	end

	if template:IsA("BasePart") then
		local handle = template:Clone()
		handle.Name = "Handle"
		setupPart(handle)
		handle.CFrame = CFrame.new()
		handle.Parent = tool
		return tool
	end

	if not template:IsA("Model") then
		tool:Destroy()
		return nil
	end

	local primary = template.PrimaryPart
	if not primary then
		for _, descendant in ipairs(template:GetDescendants()) do
			if descendant:IsA("BasePart") then
				primary = descendant
				break
			end
		end
	end
	if not primary then
		tool:Destroy()
		return nil
	end

	local base = CFrame.new()
	local clones = {}

	for _, descendant in ipairs(template:GetDescendants()) do
		if descendant:IsA("BasePart") then
			local clone = descendant:Clone()
			setupPart(clone)
			local rel = primary.CFrame:ToObjectSpace(descendant.CFrame)
			clone.CFrame = base * rel
			clone.Parent = tool
			clones[descendant] = clone
		end
	end

	local handle = clones[primary]
	if not handle then
		tool:Destroy()
		return nil
	end
	handle.Name = "Handle"

	for _, clone in pairs(clones) do
		if clone ~= handle then
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = handle
			weld.Part1 = clone
			weld.Parent = handle
		end
	end

	return tool
end

local function syncItem(player, itemName, desiredCount)
	local count = tonumber(desiredCount) or 0
	if count < 0 then
		count = 0
	end
	count = math.floor(count + 1e-9)

	local backpack = player:FindFirstChildOfClass("Backpack")
	if not backpack then
		return
	end

	local tools = {}
	for _, tool in ipairs(getItemTools(backpack, itemName)) do
		table.insert(tools, tool)
	end
	for _, tool in ipairs(getItemTools(player.Character, itemName)) do
		table.insert(tools, tool)
	end

	local current = #tools
	if current > count then
		for index = count + 1, current do
			local tool = tools[index]
			if tool and tool.Parent then
				tool:Destroy()
			end
		end
	elseif current < count then
		for _ = 1, count - current do
			local tool = makeTool(itemName)
			if tool then
				tool.Parent = backpack
			end
		end
	end
end

local function setupItemFolder(player, folder)
	if not folder or not folder:IsA("Folder") then
		return
	end

	local function bindQuantity(quantity)
		if not quantity or not quantity:IsA("NumberValue") or quantity.Name ~= "Quantity" then
			return
		end
		if quantity:GetAttribute("__BoundInv") then
			return
		end
		quantity:SetAttribute("__BoundInv", true)

		syncItem(player, folder.Name, quantity.Value)
		quantity.Changed:Connect(function()
			syncItem(player, folder.Name, quantity.Value)
		end)
	end

	local quantity = folder:FindFirstChild("Quantity")
	if quantity then
		bindQuantity(quantity)
	end

	folder.ChildAdded:Connect(function(child)
		if child.Name == "Quantity" and child:IsA("NumberValue") then
			bindQuantity(child)
		end
	end)

	folder.AncestryChanged:Connect(function(_, parent)
		if parent == nil then
			syncItem(player, folder.Name, 0)
		end
	end)
end

local function setupInventory(player, inventory)
	for _, child in ipairs(inventory:GetChildren()) do
		if child:IsA("Folder") then
			setupItemFolder(player, child)
		end
	end

	inventory.ChildAdded:Connect(function(child)
		if child:IsA("Folder") then
			setupItemFolder(player, child)
		end
	end)

	inventory.ChildRemoved:Connect(function(child)
		if child:IsA("Folder") then
			syncItem(player, child.Name, 0)
		end
	end)
end

Players.PlayerAdded:Connect(function(player)
	local function resyncAll()
		local inventory = getInventory(player)
		if not inventory then
			return
		end
		for _, folder in ipairs(inventory:GetChildren()) do
			if folder:IsA("Folder") then
				local quantity = folder:FindFirstChild("Quantity")
				if quantity and quantity:IsA("NumberValue") then
					syncItem(player, folder.Name, quantity.Value)
				else
					syncItem(player, folder.Name, 0)
				end
			end
		end
	end

	player.CharacterAdded:Connect(function()
		task.defer(resyncAll)
	end)

	local inventory = getInventory(player)
	if inventory then
		setupInventory(player, inventory)
		resyncAll()
	else
		player.ChildAdded:Connect(function(child)
			if child.Name == "Invnetory" or child.Name == "Inventory" then
				setupInventory(player, child)
				resyncAll()
			end
		end)
	end
end)
