local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local DevilFruitInventoryService = {}

local TOOL_ATTR_KIND = "InventoryItemKind"
local TOOL_ATTR_NAME = "InventoryItemName"
local TOOL_ATTR_FRUIT_KEY = "FruitKey"
local TOOL_ATTR_FRUIT_NAME = "FruitName"
local DEVIL_FRUITS_FOLDER_NAME = "DevilFruits"
local PROMPT_TIMEOUT = 20
local TOOL_HANDLE_SIZE = Vector3.new(0.35, 0.35, 0.35)
local EXPLICIT_GRIP_ATTACHMENT_NAMES = {
	"RightGripAttachment",
	"GripAttachment",
	"ToolGripAttachment",
}
local EXPLICIT_GRIP_PART_NAMES = {
	"Handle",
	"Grip",
	"Hold",
}

local DevilFruitConfig = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("DevilFruits"))
local DevilFruitAssets = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("DevilFruits"):WaitForChild("Assets"))
local FruitGripController = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("DevilFruits"):WaitForChild("FruitGripController"))
local DevilFruitService = require(ServerScriptService:WaitForChild("Modules"):WaitForChild("DevilFruitService"))
local IndexCollectionService = require(ServerScriptService:WaitForChild("Modules"):WaitForChild("IndexCollectionService"))
local DataManager = require(ServerScriptService:WaitForChild("Data"):WaitForChild("DataManager"))

local promptRemote
local responseRemote
local pendingConsumeByPlayer = {}
local started = false

local function getOrCreateRemotesFolder()
	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	if not remotes then
		remotes = Instance.new("Folder")
		remotes.Name = "Remotes"
		remotes.Parent = ReplicatedStorage
	end

	return remotes
end

local function getOrCreateRemote(parent, className, name)
	local remote = parent:FindFirstChild(name)
	if remote and remote.ClassName == className then
		return remote
	end

	if remote then
		remote:Destroy()
	end

	remote = Instance.new(className)
	remote.Name = name
	remote.Parent = parent
	return remote
end

local function ensureRemotes()
	local remotesFolder = getOrCreateRemotesFolder()
	promptRemote = getOrCreateRemote(remotesFolder, "RemoteEvent", "DevilFruitConsumePrompt")
	responseRemote = getOrCreateRemote(remotesFolder, "RemoteEvent", "DevilFruitConsumeResponse")
end

local function resolveFruit(fruitIdentifier)
	local fruit = DevilFruitConfig.GetFruit(fruitIdentifier)
	if not fruit then
		return nil, "unknown_fruit"
	end

	return fruit
end

local function getInventory(player)
	return player:FindFirstChild("Inventory")
end

local function getDevilFruitsFolder(player)
	local inventory = getInventory(player)
	return inventory and inventory:FindFirstChild(DEVIL_FRUITS_FOLDER_NAME)
end

local function getFruitEntryFolder(player, fruitKey)
	local devilFruitsFolder = getDevilFruitsFolder(player)
	return devilFruitsFolder and devilFruitsFolder:FindFirstChild(fruitKey)
end

local function getFruitQuantityValue(player, fruitKey)
	local fruitFolder = getFruitEntryFolder(player, fruitKey)
	if not fruitFolder then
		return nil
	end

	local quantity = fruitFolder:FindFirstChild("Quantity")
	if quantity and quantity:IsA("NumberValue") then
		return quantity
	end

	return nil
end

local function getFruitInventoryPath(fruitKey)
	return string.format("Inventory.%s.%s.Quantity", DEVIL_FRUITS_FOLDER_NAME, fruitKey)
end

local function ensureFruitEntry(player, fruitKey)
	local devilFruitsData, reason = DataManager:TryGetValue(player, "Inventory." .. DEVIL_FRUITS_FOLDER_NAME)
	if reason ~= nil then
		return false, reason
	end

	if typeof(devilFruitsData) ~= "table" then
		return DataManager:TryAddValue(player, "Inventory", {
			[DEVIL_FRUITS_FOLDER_NAME] = {
				[fruitKey] = {
					Quantity = 0,
				},
			},
		})
	end

	local quantity, quantityReason = DataManager:TryGetValue(player, getFruitInventoryPath(fruitKey))
	if quantityReason ~= nil then
		return false, quantityReason
	end

	if typeof(quantity) ~= "number" then
		return DataManager:TryAddValue(player, "Inventory." .. DEVIL_FRUITS_FOLDER_NAME, {
			[fruitKey] = {
				Quantity = 0,
			},
		})
	end

	return true, nil
end

function DevilFruitInventoryService.GetFruitQuantity(player, fruitIdentifier)
	local fruit, reason = resolveFruit(fruitIdentifier)
	if not fruit then
		return nil, reason
	end

	local quantityValue = getFruitQuantityValue(player, fruit.FruitKey)
	if quantityValue then
		return quantityValue.Value
	end

	local quantity, quantityReason = DataManager:TryGetValue(player, getFruitInventoryPath(fruit.FruitKey))
	if quantityReason ~= nil then
		return nil, quantityReason
	end

	return tonumber(quantity) or 0
end

function DevilFruitInventoryService.GrantFruit(player, fruitIdentifier, amount)
	local fruit, reason = resolveFruit(fruitIdentifier)
	if not fruit then
		return false, reason
	end

	local increment = math.max(1, math.floor(tonumber(amount) or 1))
	local ensured, ensureReason = ensureFruitEntry(player, fruit.FruitKey)
	if not ensured then
		return false, ensureReason
	end

	local currentQuantity = DevilFruitInventoryService.GetFruitQuantity(player, fruit.FruitKey)
	if currentQuantity == nil then
		return false, "missing_quantity"
	end

	local success, setReason = DataManager:TrySetValue(player, getFruitInventoryPath(fruit.FruitKey), currentQuantity + increment)
	if success then
		IndexCollectionService.MarkDevilFruitDiscovered(player, fruit.FruitKey)
	end

	return success, setReason
end

function DevilFruitInventoryService.ConsumeFruit(player, fruitIdentifier, amount)
	local fruit, reason = resolveFruit(fruitIdentifier)
	if not fruit then
		return false, reason
	end

	local decrement = math.max(1, math.floor(tonumber(amount) or 1))
	local currentQuantity, quantityReason = DevilFruitInventoryService.GetFruitQuantity(player, fruit.FruitKey)
	if currentQuantity == nil then
		return false, quantityReason
	end

	if currentQuantity < decrement then
		return false, "not_enough_fruit"
	end

	return DataManager:TrySetValue(player, getFruitInventoryPath(fruit.FruitKey), currentQuantity - decrement)
end

local function isToolOwnedByPlayer(tool, player)
	if not tool or not tool:IsA("Tool") then
		return false
	end

	local parent = tool.Parent
	return parent == player.Backpack or parent == player.Character
end

local function findFruitTools(container, fruitKey)
	local tools = {}
	if not container then
		return tools
	end

	for _, child in ipairs(container:GetChildren()) do
		if child:IsA("Tool")
			and child:GetAttribute(TOOL_ATTR_KIND) == "DevilFruit"
			and child:GetAttribute(TOOL_ATTR_NAME) == fruitKey then
			table.insert(tools, child)
		end
	end

	return tools
end

local function destroyExtraTools(tools, desiredCount)
	for index = desiredCount + 1, #tools do
		local tool = tools[index]
		if tool and tool.Parent then
			tool:Destroy()
		end
	end
end

local function setUpPart(part)
	part.Anchored = false
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.Massless = true
end

local function getPrimaryPartFromTemplate(template)
	if not template or not (template:IsA("Model") or template:IsA("WorldModel")) then
		return nil
	end

	local primaryPart = template.PrimaryPart
	if primaryPart and primaryPart:IsA("BasePart") then
		return primaryPart
	end

	local handle = template:FindFirstChild("Handle", true)
	if handle and handle:IsA("BasePart") then
		return handle
	end

	local namedPart = template:FindFirstChild("Part", true)
	if namedPart and namedPart:IsA("BasePart") then
		return namedPart
	end

	return template:FindFirstChildWhichIsA("BasePart", true)
end

local function getTemplateParts(template)
	local parts = {}

	for _, descendant in ipairs(template:GetDescendants()) do
		if descendant:IsA("BasePart") then
			table.insert(parts, descendant)
		end
	end

	return parts
end

local function clampVector3(value, minValue, maxValue)
	return Vector3.new(
		math.clamp(value.X, minValue.X, maxValue.X),
		math.clamp(value.Y, minValue.Y, maxValue.Y),
		math.clamp(value.Z, minValue.Z, maxValue.Z)
	)
end

local function expandBounds(relativeCFrame, size, currentMin, currentMax)
	local halfSize = size * 0.5

	for xSign = -1, 1, 2 do
		for ySign = -1, 1, 2 do
			for zSign = -1, 1, 2 do
				local corner = relativeCFrame:PointToWorldSpace(Vector3.new(
					halfSize.X * xSign,
					halfSize.Y * ySign,
					halfSize.Z * zSign
				))

				currentMin = Vector3.new(
					math.min(currentMin.X, corner.X),
					math.min(currentMin.Y, corner.Y),
					math.min(currentMin.Z, corner.Z)
				)
				currentMax = Vector3.new(
					math.max(currentMax.X, corner.X),
					math.max(currentMax.Y, corner.Y),
					math.max(currentMax.Z, corner.Z)
				)
			end
		end
	end

	return currentMin, currentMax
end

local function findExplicitGripPivot(template)
	for _, attachmentName in ipairs(EXPLICIT_GRIP_ATTACHMENT_NAMES) do
		local attachment = template:FindFirstChild(attachmentName, true)
		if attachment and attachment:IsA("Attachment") and attachment.Parent and attachment.Parent:IsA("BasePart") then
			return attachment.WorldCFrame
		end
	end

	for _, partName in ipairs(EXPLICIT_GRIP_PART_NAMES) do
		local gripPart = template:FindFirstChild(partName, true)
		if gripPart and gripPart:IsA("BasePart") then
			return gripPart.CFrame
		end
	end

	return nil
end

local function getAutomaticGripPivot(template, primaryPart, fruit, gripOptions)
	local templateParts = getTemplateParts(template)
	if #templateParts == 0 then
		return primaryPart.CFrame
	end

	local localMin = Vector3.new(math.huge, math.huge, math.huge)
	local localMax = Vector3.new(-math.huge, -math.huge, -math.huge)

	for _, part in ipairs(templateParts) do
		local relativeCFrame = primaryPart.CFrame:ToObjectSpace(part.CFrame)
		localMin, localMax = expandBounds(relativeCFrame, part.Size, localMin, localMax)
	end

	local boundsCenter = (localMin + localMax) * 0.5
	local halfExtents = (localMax - localMin) * 0.5
	local gripProfile = FruitGripController.GetBuildGripSettings(fruit and fruit.FruitKey or nil, gripOptions)
	local gripBias = gripProfile.AssetGripBias
	local gripOffset = gripProfile.AssetGripOffset
	local gripLocalPosition = boundsCenter + Vector3.new(
		halfExtents.X * gripBias.X,
		halfExtents.Y * gripBias.Y,
		halfExtents.Z * gripBias.Z
	) + gripOffset

	gripLocalPosition = clampVector3(gripLocalPosition, localMin, localMax)

	return primaryPart.CFrame * CFrame.new(gripLocalPosition)
end

local function getGripPivot(template, primaryPart, fruit, gripOptions)
	return findExplicitGripPivot(template) or getAutomaticGripPivot(template, primaryPart, fruit, gripOptions)
end

local function buildFruitTool(player, fruitKey)
	local isValid, worldModelOrReason, fruit = DevilFruitAssets.ValidateWorldModel(fruitKey)
	if not isValid then
		return nil, worldModelOrReason
	end

	local template = worldModelOrReason
	if not (template:IsA("Model") or template:IsA("WorldModel")) then
		return nil, "unsupported_tool_template"
	end

	local primaryPart = getPrimaryPartFromTemplate(template)
	if not primaryPart then
		return nil, "missing_primary_part"
	end

	local character = player and player.Character or nil
	local gripOptions = {
		Player = player,
		Character = character,
	}
	local gripPivot = getGripPivot(template, primaryPart, fruit, gripOptions)
	local templateParts = getTemplateParts(template)
	if #templateParts == 0 then
		return nil, "missing_tool_parts"
	end

	local tool = Instance.new("Tool")
	tool.Name = fruit.FruitKey
	tool.ToolTip = fruit.DisplayName
	tool.CanBeDropped = false
	tool.RequiresHandle = false
	tool:SetAttribute(TOOL_ATTR_KIND, "DevilFruit")
	tool:SetAttribute(TOOL_ATTR_NAME, fruit.FruitKey)
	tool:SetAttribute(TOOL_ATTR_FRUIT_KEY, fruit.FruitKey)
	tool:SetAttribute(TOOL_ATTR_FRUIT_NAME, fruit.DisplayName)

	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = TOOL_HANDLE_SIZE
	handle.Transparency = 1
	setUpPart(handle)
	handle.CFrame = CFrame.new()
	handle.Parent = tool

	for _, part in ipairs(templateParts) do
		local clone = part:Clone()
		setUpPart(clone)
		if clone.Name == "Handle" then
			clone.Name = "FruitGeometryHandle"
		end
		clone.CFrame = gripPivot:ToObjectSpace(part.CFrame)
		clone.Parent = tool

		local weld = Instance.new("WeldConstraint")
		weld.Part0 = handle
		weld.Part1 = clone
		weld.Parent = handle
	end

	FruitGripController.ApplyToolGrip(tool, fruit.FruitKey, {
		Tool = tool,
		Player = player,
		Character = character,
	})

	return tool
end

local function clearPendingConsume(player)
	pendingConsumeByPlayer[player] = nil
end

local function requestConsume(player, tool)
	if pendingConsumeByPlayer[player] ~= nil then
		return
	end

	local fruitKey = tool:GetAttribute(TOOL_ATTR_FRUIT_KEY)
	local fruitName = tool:GetAttribute(TOOL_ATTR_FRUIT_NAME)
	if typeof(fruitKey) ~= "string" or fruitKey == "" then
		return
	end

	local equippedFruitName = DevilFruitService.GetEquippedFruit(player)
	pendingConsumeByPlayer[player] = {
		FruitKey = fruitKey,
		Tool = tool,
		RequestedAt = os.clock(),
	}

	promptRemote:FireClient(player, {
		FruitKey = fruitKey,
		FruitName = fruitName,
		CurrentFruitName = equippedFruitName,
	})
end

local function hookTool(player, tool)
	if tool:GetAttribute("__DevilFruitConsumeBound") == true then
		return
	end

	tool:SetAttribute("__DevilFruitConsumeBound", true)
	tool.Equipped:Connect(function()
		FruitGripController.ApplyToolGrip(tool, tool:GetAttribute(TOOL_ATTR_FRUIT_KEY), {
			Tool = tool,
			Player = player,
			Character = player.Character,
		})
	end)
	tool.Unequipped:Connect(function()
		FruitGripController.ApplyToolGrip(tool, tool:GetAttribute(TOOL_ATTR_FRUIT_KEY), {
			Tool = tool,
			Player = player,
			Character = player.Character,
		})
	end)
	tool.Activated:Connect(function()
		if not isToolOwnedByPlayer(tool, player) then
			return
		end

		requestConsume(player, tool)
	end)
end

local function syncFruitTool(player, fruitKey, desiredCount)
	local backpackTools = findFruitTools(player:FindFirstChildOfClass("Backpack"), fruitKey)
	local characterTools = findFruitTools(player.Character, fruitKey)
	local allTools = {}

	for _, tool in ipairs(characterTools) do
		table.insert(allTools, tool)
	end

	for _, tool in ipairs(backpackTools) do
		table.insert(allTools, tool)
	end

	local count = #allTools
	if count > desiredCount then
		destroyExtraTools(allTools, desiredCount)
		return
	end

	if count >= desiredCount then
		for _, tool in ipairs(allTools) do
			hookTool(player, tool)
		end
		return
	end

	local backpack = player:FindFirstChildOfClass("Backpack")
	if not backpack then
		return
	end

	for _ = 1, (desiredCount - count) do
		local tool, reason = buildFruitTool(player, fruitKey)
		if tool then
			hookTool(player, tool)
			tool.Parent = backpack
		else
			warn(string.format("[DevilFruitInventoryService] Failed to build fruit tool for %s (%s)", tostring(fruitKey), tostring(reason)))
		end
	end
end

local function bindQuantity(player, fruitFolder)
	if not fruitFolder or not fruitFolder:IsA("Folder") then
		return
	end

	local quantity = fruitFolder:FindFirstChild("Quantity")
	if not quantity or not quantity:IsA("NumberValue") then
		return
	end

	if quantity:GetAttribute("__DevilFruitInventoryBound") == true then
		return
	end

	quantity:SetAttribute("__DevilFruitInventoryBound", true)
	syncFruitTool(player, fruitFolder.Name, quantity.Value)

	quantity.Changed:Connect(function()
		syncFruitTool(player, fruitFolder.Name, quantity.Value)
	end)
end

local function hookDevilFruitFolder(player, devilFruitsFolder)
	if not devilFruitsFolder or not devilFruitsFolder:IsA("Folder") then
		return
	end

	for _, child in ipairs(devilFruitsFolder:GetChildren()) do
		if child:IsA("Folder") then
			bindQuantity(player, child)
		end
	end

	devilFruitsFolder.ChildAdded:Connect(function(child)
		if child:IsA("Folder") then
			task.defer(bindQuantity, player, child)
		end
	end)

	devilFruitsFolder.ChildRemoved:Connect(function(child)
		if child:IsA("Folder") then
			syncFruitTool(player, child.Name, 0)
		end
	end)
end

local function hookPlayer(player)
	local function hookInventory(inventory)
		local devilFruitsFolder = inventory:FindFirstChild(DEVIL_FRUITS_FOLDER_NAME)
		if devilFruitsFolder then
			hookDevilFruitFolder(player, devilFruitsFolder)
		end

		inventory.ChildAdded:Connect(function(child)
			if child:IsA("Folder") and child.Name == DEVIL_FRUITS_FOLDER_NAME then
				hookDevilFruitFolder(player, child)
			end
		end)
	end

	local inventory = getInventory(player)
	if inventory then
		hookInventory(inventory)
	else
		player.ChildAdded:Connect(function(child)
			if child:IsA("Folder") and child.Name == "Inventory" then
				hookInventory(child)
			end
		end)
	end

	player.CharacterAdded:Connect(function()
		task.defer(function()
			local devilFruitsFolder = getDevilFruitsFolder(player)
			if not devilFruitsFolder then
				return
			end

			for _, child in ipairs(devilFruitsFolder:GetChildren()) do
				if child:IsA("Folder") then
					local quantity = child:FindFirstChild("Quantity")
					if quantity and quantity:IsA("NumberValue") then
						syncFruitTool(player, child.Name, quantity.Value)
					end
				end
			end
		end)
	end)
end

local function handleConsumeResponse(player, accepted, fruitKey)
	local pending = pendingConsumeByPlayer[player]
	if not pending then
		return
	end

	clearPendingConsume(player)

	if accepted ~= true then
		return
	end

	if typeof(fruitKey) ~= "string" or fruitKey ~= pending.FruitKey then
		return
	end

	if os.clock() - pending.RequestedAt > PROMPT_TIMEOUT then
		return
	end

	local tool = pending.Tool
	if not isToolOwnedByPlayer(tool, player) then
		return
	end

	local currentFruitName = DevilFruitService.GetEquippedFruit(player)
	local targetFruitName = DevilFruitConfig.ResolveFruitName(fruitKey)
	if currentFruitName ~= DevilFruitConfig.None and currentFruitName == targetFruitName then
		return
	end

	local consumed, consumeReason = DevilFruitInventoryService.ConsumeFruit(player, fruitKey, 1)
	if not consumed then
		warn(string.format("[DevilFruitInventoryService] Failed to consume %s for %s: %s", fruitKey, player.Name, tostring(consumeReason)))
		return
	end

	local equipped = DevilFruitService.SetEquippedFruit(player, fruitKey)
	if not equipped then
		DevilFruitInventoryService.GrantFruit(player, fruitKey, 1)
		warn(string.format("[DevilFruitInventoryService] Failed to equip %s for %s after consuming", fruitKey, player.Name))
		return
	end

	if tool and tool.Parent then
		tool:Destroy()
	end
end

function DevilFruitInventoryService.Start()
	if started then
		return
	end

	started = true
	ensureRemotes()

	for _, player in ipairs(Players:GetPlayers()) do
		hookPlayer(player)
	end

	Players.PlayerAdded:Connect(hookPlayer)
	Players.PlayerRemoving:Connect(clearPendingConsume)
	responseRemote.OnServerEvent:Connect(handleConsumeResponse)
end

return DevilFruitInventoryService
