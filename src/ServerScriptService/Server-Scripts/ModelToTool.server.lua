local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local brainrotFolder = ReplicatedStorage:WaitForChild("BrainrotFolder")

-- ✅ Variant config (prefixy + foldery)
local Modules = ReplicatedStorage:WaitForChild("Modules")
local Configs = Modules:WaitForChild("Configs")
local VariantCfg = require(Configs:WaitForChild("BrainrotVariants"))

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

-- ✅ wykrywa wariant + baseName po prefixach z configu
local function getVariantAndBaseName(itemName)
	itemName = tostring(itemName)

	for _, vKey in ipairs(VariantCfg.Order or {}) do
		if vKey ~= "Normal" then
			local v = (VariantCfg.Versions or {})[vKey]
			local prefix = tostring((v and v.Prefix) or (vKey .. " "))
			if prefix ~= "" and itemName:sub(1, #prefix) == prefix then
				local baseName = itemName:sub(#prefix + 1)
				return vKey, baseName, v
			end
		end
	end

	return "Normal", itemName, (VariantCfg.Versions or {}).Normal
end

-- ✅ znajduje template modelu dla itemName (obsługa wariantów)
local function findTemplate(itemName)
	local variantKey, baseName, v = getVariantAndBaseName(itemName)

	-- 1) jeśli to wariant -> szukaj w folderze wariantu po baseName
	if variantKey ~= "Normal" then
		local folderName = (v and v.Folder) or variantKey -- np. "Golden", "Diamond"
		local variantFolder = brainrotFolder:FindFirstChild(folderName)

		if variantFolder and variantFolder:IsA("Folder") then
			local t = variantFolder:FindFirstChild(baseName)
			if t then
				return t, variantKey, baseName
			end
			-- (opcjonalnie) gdyby ktoś nazwał model pełną nazwą wariantu
			local t2 = variantFolder:FindFirstChild(itemName)
			if t2 then
				return t2, variantKey, baseName
			end
		end
	end

	-- 2) fallback: szukaj normalnie
	local direct = brainrotFolder:FindFirstChild(itemName)
	if direct then
		return direct, variantKey, baseName
	end

	local base = brainrotFolder:FindFirstChild(baseName)
	if base then
		return base, "Normal", baseName
	end

	return nil, variantKey, baseName
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

	local function setupPart(p)
		p.Anchored = false
		p.CanCollide = false
		p.Massless = true
	end

	-- jeśli template jest częścią
	if template:IsA("BasePart") then
		local handle = template:Clone()
		handle.Name = "Handle"
		setupPart(handle)
		handle.CFrame = CFrame.new()
		handle.Parent = tool
		return tool
	end

	-- jeśli template jest modelem
	if not template:IsA("Model") then
		tool:Destroy()
		return nil
	end

	local primary = template.PrimaryPart
	if not primary then
		for _, d in ipairs(template:GetDescendants()) do
			if d:IsA("BasePart") then
				primary = d
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

	for _, d in ipairs(template:GetDescendants()) do
		if d:IsA("BasePart") then
			local c = d:Clone()
			setupPart(c)
			local rel = primary.CFrame:ToObjectSpace(d.CFrame)
			c.CFrame = base * rel
			c.Parent = tool
			clones[d] = c
		end
	end

	local handle = clones[primary]
	if not handle then
		tool:Destroy()
		return nil
	end
	handle.Name = "Handle"

	for orig, c in pairs(clones) do
		if c ~= handle then
			local w = Instance.new("WeldConstraint")
			w.Part0 = handle
			w.Part1 = c
			w.Parent = handle
		end
	end

	return tool
end

local function syncItem(player, itemName, desiredCount)
	local n = tonumber(desiredCount) or 0
	if n < 0 then
		n = 0
	end
	n = math.floor(n + 1e-9)

	local backpack = player:FindFirstChildOfClass("Backpack")
	if not backpack then
		return
	end

	local tools = {}
	for _, t in ipairs(getItemTools(backpack, itemName)) do
		table.insert(tools, t)
	end
	for _, t in ipairs(getItemTools(player.Character, itemName)) do
		table.insert(tools, t)
	end

	local current = #tools
	if current > n then
		for i = n + 1, current do
			local t = tools[i]
			if t and t.Parent then
				t:Destroy()
			end
		end
	elseif current < n then
		for _ = 1, (n - current) do
			local t = makeTool(itemName)
			if t then
				t.Parent = backpack
			end
		end
	end
end

local function setupItemFolder(player, folder)
	if not folder or not folder:IsA("Folder") then
		return
	end

	local function bindQuantity(q)
		-- w twoim systemie Quantity jest NumberValue
		if not q or not q:IsA("NumberValue") or q.Name ~= "Quantity" then
			return
		end
		if q:GetAttribute("__BoundInv") then
			return
		end
		q:SetAttribute("__BoundInv", true)

		syncItem(player, folder.Name, q.Value)
		q.Changed:Connect(function()
			syncItem(player, folder.Name, q.Value)
		end)
	end

	local q0 = folder:FindFirstChild("Quantity")
	if q0 then
		bindQuantity(q0)
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

local function setupInventory(player, inv)
	for _, child in ipairs(inv:GetChildren()) do
		if child:IsA("Folder") then
			setupItemFolder(player, child)
		end
	end

	inv.ChildAdded:Connect(function(child)
		if child:IsA("Folder") then
			setupItemFolder(player, child)
		end
	end)

	inv.ChildRemoved:Connect(function(child)
		if child:IsA("Folder") then
			syncItem(player, child.Name, 0)
		end
	end)
end

Players.PlayerAdded:Connect(function(player)
	local function resyncAll()
		local inv = getInventory(player)
		if not inv then
			return
		end
		for _, f in ipairs(inv:GetChildren()) do
			if f:IsA("Folder") then
				local q = f:FindFirstChild("Quantity")
				if q and q:IsA("NumberValue") then
					syncItem(player, f.Name, q.Value)
				else
					syncItem(player, f.Name, 0)
				end
			end
		end
	end

	player.CharacterAdded:Connect(function()
		task.defer(resyncAll)
	end)

	local inv = getInventory(player)
	if inv then
		setupInventory(player, inv)
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
