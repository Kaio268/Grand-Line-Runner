local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local DevilFruitInventoryService = {}

local TOOL_ATTR_KIND = "InventoryItemKind"
local TOOL_ATTR_NAME = "InventoryItemName"
local TOOL_ATTR_FRUIT_KEY = "FruitKey"
local TOOL_ATTR_FRUIT_NAME = "FruitName"
local TOOL_ATTR_GRIP_VERSION = "FruitToolGripVersion"
local DEVIL_FRUITS_FOLDER_NAME = "DevilFruits"
local PROMPT_TIMEOUT = 20
local TOOL_HANDLE_SIZE = Vector3.new(0.35, 0.35, 0.35)
local FRUIT_TOOL_GRIP_VERSION = "authored_tool_template_v5"
local CONSUME_BIND_ATTRIBUTE = "__DevilFruitConsumeBound"
local CONSUME_BIND_VERSION = "consume_bind_v2"
local CONSUME_BIND_ID_ATTRIBUTE = "__DevilFruitConsumeBindId"
local CONSUME_DEBUG = true
local R6G_WELD_DEBUG = true
local EXPLICIT_GRIP_ATTACHMENT_NAMES = {
	"RightGripAttachment",
	"GripAttachment",
	"ToolGripAttachment",
}
local EXPLICIT_GRIP_PART_NAMES = {
	"Grip",
	"Hold",
}
local MODEL_VARIANT_R6G = "R6G"
local MODEL_VARIANT_ATTRIBUTE_NAMES = {
	"FruitHoldModelVariant",
	"FruitGripModelVariant",
	"FruitModelVariant",
	"EatAnimationRig",
	"CurrentModelAsset",
}

local DevilFruitConfig = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("DevilFruits"))
local DevilFruitAssets = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("DevilFruits"):WaitForChild("Assets"))
local FruitGripController = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("DevilFruits"):WaitForChild("FruitGripController"))
local DevilFruitLogger = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("DevilFruits"):WaitForChild("Shared"):WaitForChild("DevilFruitLogger"))
local DevilFruitService = require(ServerScriptService:WaitForChild("Modules"):WaitForChild("DevilFruitService"))
local IndexCollectionService = require(ServerScriptService:WaitForChild("Modules"):WaitForChild("IndexCollectionService"))
local DataManager = require(ServerScriptService:WaitForChild("Data"):WaitForChild("DataManager"))

local promptRemote
local responseRemote
local requestRemote
local pendingConsumeByPlayer = {}
local started = false
local nextConsumeBindId = 0

local function consumeDebug(message, ...)
	if not CONSUME_DEBUG then
		return
	end

	local ok, formatted = pcall(string.format, "[FruitConsumeDebug] " .. tostring(message), ...)
	print(ok and formatted or ("[FruitConsumeDebug] " .. tostring(message)))
end

local function debugInstancePath(instance)
	if typeof(instance) == "Instance" then
		return instance:GetFullName()
	end

	return "<nil>"
end

local function debugToolBindId(tool)
	if tool and tool:IsA("Tool") then
		return tostring(tool:GetAttribute(CONSUME_BIND_ID_ATTRIBUTE) or "?")
	end

	return "?"
end

local function r6gWeldDebug(message, ...)
	if not R6G_WELD_DEBUG then
		return
	end

	local ok, formatted = pcall(string.format, "[R6G FRUIT WELD][SERVER][InventoryService] " .. tostring(message), ...)
	print(ok and formatted or ("[R6G FRUIT WELD][SERVER][InventoryService] " .. tostring(message)))
end

local function formatCFrameForDebug(value)
	if typeof(value) ~= "CFrame" then
		return tostring(value)
	end

	local x, y, z = value:ToOrientation()
	return string.format(
		"pos=(%.2f, %.2f, %.2f) rot=(%.1f, %.1f, %.1f)",
		value.Position.X,
		value.Position.Y,
		value.Position.Z,
		math.deg(x),
		math.deg(y),
		math.deg(z)
	)
end

local function formatJointCFrameForDebug(joint, propertyName)
	local ok, value = pcall(function()
		return joint[propertyName]
	end)

	if ok and typeof(value) == "CFrame" then
		return formatCFrameForDebug(value)
	end

	return "<unavailable>"
end

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
	requestRemote = getOrCreateRemote(remotesFolder, "RemoteEvent", "DevilFruitConsumeRequest")
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
	local liveQuantity = if quantityValue then tonumber(quantityValue.Value) or 0 else nil

	local quantity, quantityReason = DataManager:TryGetValue(player, getFruitInventoryPath(fruit.FruitKey))
	if quantityReason ~= nil then
		if liveQuantity ~= nil then
			return liveQuantity
		end

		return nil, quantityReason
	end

	local persistedQuantity = tonumber(quantity) or 0
	if liveQuantity ~= nil then
		return math.max(liveQuantity, persistedQuantity)
	end

	return persistedQuantity
end

function DevilFruitInventoryService.IsOwned(player, fruitIdentifier)
	local fruit, reason = resolveFruit(fruitIdentifier)
	if not fruit then
		return false, reason
	end

	local currentQuantity, quantityReason = DevilFruitInventoryService.GetFruitQuantity(player, fruit.FruitKey)
	if currentQuantity == nil and quantityReason ~= nil then
		return false, quantityReason
	end

	if math.max(0, tonumber(currentQuantity) or 0) > 0 then
		return true, nil
	end

	return DevilFruitService.GetEquippedFruitKey(player) == fruit.FruitKey, nil
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

local function getGripPart(character)
	if not character then
		return nil
	end

	return character:FindFirstChild("RightHand")
		or character:FindFirstChild("RightLowerArm")
		or character:FindFirstChild("Right Arm")
end

local function isR6GModelValue(value)
	return typeof(value) == "string" and string.upper(value) == MODEL_VARIANT_R6G
end

local function isR6GCharacter(character)
	if typeof(character) ~= "Instance" then
		return false
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	for _, target in ipairs({ character, humanoid }) do
		if typeof(target) == "Instance" then
			for _, attributeName in ipairs(MODEL_VARIANT_ATTRIBUTE_NAMES) do
				if isR6GModelValue(target:GetAttribute(attributeName)) then
					return true
				end
			end
		end
	end

	return false
end

local function clearManualGrip(tool)
	if not tool or not tool:IsA("Tool") then
		return
	end

	local handle = tool:FindFirstChild("Handle")
	if not handle or not handle:IsA("BasePart") then
		return
	end

	local manualGrip = handle:FindFirstChild("ManualGrip")
	if manualGrip then
		manualGrip:Destroy()
	end
end

local function resolveManualGripC0(gripPart)
	local attachment = gripPart:FindFirstChild("RightGripAttachment")
		or gripPart:FindFirstChild("RightGrip")
	if not (attachment and attachment:IsA("Attachment")) then
		return CFrame.new(), "", "PartOrigin"
	end

	return attachment.CFrame, attachment.Name, "AttachmentCFrame"
end

local function getConnectedRightGripJoints(character, handle)
	local joints = {}
	if typeof(character) ~= "Instance" or typeof(handle) ~= "Instance" then
		return joints
	end

	for _, descendant in ipairs(character:GetDescendants()) do
		if descendant.Name == "RightGrip"
			and descendant:IsA("JointInstance")
			and (descendant.Part0 == handle or descendant.Part1 == handle) then
			table.insert(joints, descendant)
		end
	end

	return joints
end

local function logR6GLiveGripState(source, tool, character)
	if not (tool and tool:IsA("Tool") and isR6GCharacter(character)) then
		return
	end

	local handle = tool:FindFirstChild("Handle")
	local gripPart = getGripPart(character)
	local attachment = gripPart and (gripPart:FindFirstChild("RightGripAttachment") or gripPart:FindFirstChild("RightGrip")) or nil
	local attachmentIsAttachment = attachment and attachment:IsA("Attachment")
	r6gWeldDebug(
		"%s tool=%s parent=%s handle=%s gripPart=%s attachmentExists=%s attachment=%s attachmentClass=%s attachmentCFrame=%s toolGrip=%s manualMode=%s",
		tostring(source),
		tool.Name,
		debugInstancePath(tool.Parent),
		debugInstancePath(handle),
		debugInstancePath(gripPart),
		tostring(attachmentIsAttachment == true),
		attachment and attachment.Name or "",
		attachment and attachment.ClassName or "",
		attachmentIsAttachment and formatCFrameForDebug(attachment.CFrame) or "<none>",
		formatCFrameForDebug(tool.Grip),
		tostring(tool:GetAttribute("FruitManualGripC0Mode") or "")
	)

	local foundJoint = false
	if typeof(character) == "Instance" then
		for _, descendant in ipairs(character:GetDescendants()) do
			if descendant:IsA("JointInstance") and (descendant.Name == "RightGrip" or descendant.Name == "ManualGrip") then
				foundJoint = true
				r6gWeldDebug(
					"%s joint name=%s class=%s parent=%s part0=%s part1=%s connectedToHandle=%s C0=%s C1=%s",
					tostring(source),
					descendant.Name,
					descendant.ClassName,
					debugInstancePath(descendant.Parent),
					debugInstancePath(descendant.Part0),
					debugInstancePath(descendant.Part1),
					tostring(handle ~= nil and (descendant.Part0 == handle or descendant.Part1 == handle)),
					formatJointCFrameForDebug(descendant, "C0"),
					formatJointCFrameForDebug(descendant, "C1")
				)
			end
		end
	end

	if not foundJoint then
		r6gWeldDebug("%s joint name=<none>", tostring(source))
	end
end

local function enforceManualGrip(tool, character, source)
	if not tool or not tool:IsA("Tool") or not character then
		return false
	end

	local handle = tool:FindFirstChild("Handle")
	if not handle or not handle:IsA("BasePart") then
		return false
	end

	local useR6GripFrame = isR6GCharacter(character)
	if useR6GripFrame then
		logR6GLiveGripState((source or "enforceManualGrip") .. ":before", tool, character)
	end

	local existingGrips = getConnectedRightGripJoints(character, handle)
	if #existingGrips > 0 then
		if not useR6GripFrame then
			clearManualGrip(tool)
			return false
		end

		for _, existingGrip in ipairs(existingGrips) do
			r6gWeldDebug(
				"%s replacing connected RightGrip class=%s parent=%s",
				tostring(source or "enforceManualGrip"),
				existingGrip.ClassName,
				debugInstancePath(existingGrip.Parent)
			)
			existingGrip:Destroy()
		end
	end

	clearManualGrip(tool)

	local gripPart = getGripPart(character)
	if not gripPart or not gripPart:IsA("BasePart") then
		return false
	end

	local weld = Instance.new("Weld")
	weld.Name = "ManualGrip"
	weld.Part0 = gripPart
	weld.Part1 = handle
	weld.C1 = tool.Grip

	if useR6GripFrame then
		tool:SetAttribute("FruitManualGripFrame", "R6")
	end

	local gripC0, attachmentName, c0Mode = resolveManualGripC0(gripPart)
	weld.C0 = gripC0
	tool:SetAttribute("FruitManualGripAttachmentUsed", attachmentName)
	tool:SetAttribute("FruitManualGripC0Mode", c0Mode)

	weld.Parent = handle
	if useR6GripFrame then
		logR6GLiveGripState((source or "enforceManualGrip") .. ":after", tool, character)
	end
	return true
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
	if not template or not (template:IsA("Model") or template:IsA("WorldModel") or template:IsA("Tool")) then
		return nil
	end

	if template:IsA("Model") or template:IsA("WorldModel") then
		local primaryPart = template.PrimaryPart
		if primaryPart and primaryPart:IsA("BasePart") then
			return primaryPart
		end
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

local function getRenderableTemplateParts(template)
	local renderableParts = {}

	for _, part in ipairs(getTemplateParts(template)) do
		if part.Transparency < 0.98 then
			table.insert(renderableParts, part)
		end
	end

	if #renderableParts > 0 then
		return renderableParts
	end

	return getTemplateParts(template)
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

local function findToolGripAttachmentPivot(template)
	local templateParts = getTemplateParts(template)
	for _, part in ipairs(templateParts) do
		local attachment = part:FindFirstChild("ToolGripAttachment")
		if attachment and attachment:IsA("Attachment") then
			return attachment.WorldCFrame
		end
	end

	return nil
end

local function getAutomaticGripPivot(template, primaryPart, fruit, gripOptions)
	local templateParts = getRenderableTemplateParts(template)
	if #templateParts == 0 then
		return CFrame.new(primaryPart.Position)
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

	return CFrame.new(primaryPart.CFrame:PointToWorldSpace(gripLocalPosition))
end

local function getGripPivot(template, primaryPart, fruit, gripOptions)
	-- Some imported fruit assets carry legacy grip attachments on the stem; generated tools should hold the fruit body.
	return getAutomaticGripPivot(template, primaryPart, fruit, gripOptions)
end

local function applyFruitToolMetadata(tool, fruit)
	tool.Name = fruit.FruitKey
	tool.ToolTip = fruit.DisplayName
	tool.CanBeDropped = false
	tool:SetAttribute(TOOL_ATTR_KIND, "DevilFruit")
	tool:SetAttribute(TOOL_ATTR_NAME, fruit.FruitKey)
	tool:SetAttribute(TOOL_ATTR_FRUIT_KEY, fruit.FruitKey)
	tool:SetAttribute(TOOL_ATTR_FRUIT_NAME, fruit.DisplayName)
	tool:SetAttribute(TOOL_ATTR_GRIP_VERSION, FRUIT_TOOL_GRIP_VERSION)
end

local function setUpToolParts(tool)
	for _, descendant in ipairs(tool:GetDescendants()) do
		if descendant:IsA("BasePart") then
			setUpPart(descendant)
		end
	end
end

local function buildFruitTool(player, fruitKey)
	local isValid, worldModelOrReason, fruit = DevilFruitAssets.ValidateWorldModel(fruitKey)
	if not isValid then
		return nil, worldModelOrReason
	end

	local template = worldModelOrReason
	if not (template:IsA("Model") or template:IsA("WorldModel") or template:IsA("Tool")) then
		return nil, "unsupported_tool_template"
	end

	local character = player and player.Character or nil
	if template:IsA("Tool") then
		local tool = template:Clone()
		applyFruitToolMetadata(tool, fruit)
		setUpToolParts(tool)
		FruitGripController.MarkAuthoredRuntimeGrip(tool, tool.Grip)
		FruitGripController.ApplyToolGrip(tool, fruit.FruitKey, {
			Tool = tool,
			Player = player,
			Character = character,
		})

		return tool
	end

	local primaryPart = getPrimaryPartFromTemplate(template)
	if not primaryPart then
		return nil, "missing_primary_part"
	end

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
	tool.RequiresHandle = false
	applyFruitToolMetadata(tool, fruit)

	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = TOOL_HANDLE_SIZE
	handle.Transparency = 1
	setUpPart(handle)
	handle.CFrame = CFrame.new()
	handle.Parent = tool

	for _, part in ipairs(templateParts) do
		local clone = part:Clone()
		for _, descendant in ipairs(clone:GetDescendants()) do
			if descendant:IsA("JointInstance") or descendant:IsA("Constraint") then
				descendant:Destroy()
			end
		end
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

local function isPendingConsumeExpired(pending)
	local requestedAt = type(pending) == "table" and tonumber(pending.RequestedAt) or nil
	return requestedAt == nil or (os.clock() - requestedAt) > PROMPT_TIMEOUT
end

local function requestConsume(player, tool)
	consumeDebug(
		"request entry player=%s tool=%s bindId=%s parent=%s",
		player.Name,
		tostring(tool and tool.Name or "<nil>"),
		debugToolBindId(tool),
		debugInstancePath(tool and tool.Parent)
	)

	local existingPending = pendingConsumeByPlayer[player]
	if existingPending ~= nil then
		if not isPendingConsumeExpired(existingPending) then
			consumeDebug("request blocked player=%s reason=pending_active fruit=%s", player.Name, tostring(existingPending.FruitKey))
			return
		end

		consumeDebug("request clearing stale pending player=%s fruit=%s", player.Name, tostring(existingPending.FruitKey))
		clearPendingConsume(player)
	end

	local fruitKey = tool:GetAttribute(TOOL_ATTR_FRUIT_KEY)
	local fruitName = tool:GetAttribute(TOOL_ATTR_FRUIT_NAME)
	if typeof(fruitKey) ~= "string" or fruitKey == "" then
		consumeDebug("request blocked player=%s reason=missing_fruit_key tool=%s", player.Name, tostring(tool and tool.Name or "<nil>"))
		return
	end

	local equippedFruitName = DevilFruitService.GetEquippedFruit(player)
	pendingConsumeByPlayer[player] = {
		FruitKey = fruitKey,
		Tool = tool,
		RequestedAt = os.clock(),
	}

	consumeDebug(
		"prompt fire player=%s fruit=%s current=%s",
		player.Name,
		tostring(fruitKey),
		tostring(equippedFruitName)
	)
	promptRemote:FireClient(player, {
		FruitKey = fruitKey,
		FruitName = fruitName,
		CurrentFruitName = equippedFruitName,
	})

	task.delay(PROMPT_TIMEOUT, function()
		local pending = pendingConsumeByPlayer[player]
		if pending and pending.Tool == tool and pending.FruitKey == fruitKey and isPendingConsumeExpired(pending) then
			clearPendingConsume(player)
		end
	end)
end

local function hookTool(player, tool)
	if tool:GetAttribute(CONSUME_BIND_ATTRIBUTE) == CONSUME_BIND_VERSION then
		consumeDebug(
			"bind skipped player=%s tool=%s bindId=%s fruit=%s parent=%s",
			player.Name,
			tool.Name,
			debugToolBindId(tool),
			tostring(tool:GetAttribute(TOOL_ATTR_FRUIT_KEY)),
			debugInstancePath(tool.Parent)
		)
		return
	end

	nextConsumeBindId += 1
	local bindId = nextConsumeBindId
	tool:SetAttribute(CONSUME_BIND_ATTRIBUTE, CONSUME_BIND_VERSION)
	tool:SetAttribute(CONSUME_BIND_ID_ATTRIBUTE, bindId)
	consumeDebug(
		"bind player=%s tool=%s bindId=%s fruit=%s parent=%s enabled=%s manual=%s requiresHandle=%s hasHandle=%s",
		player.Name,
		tool.Name,
		tostring(bindId),
		tostring(tool:GetAttribute(TOOL_ATTR_FRUIT_KEY)),
		debugInstancePath(tool.Parent),
		tostring(tool.Enabled),
		tostring(tool.ManualActivationOnly),
		tostring(tool.RequiresHandle),
		tostring(tool:FindFirstChild("Handle") ~= nil)
	)
	tool:GetPropertyChangedSignal("Parent"):Connect(function()
		consumeDebug(
			"parent changed player=%s tool=%s bindId=%s fruit=%s parent=%s",
			player.Name,
			tool.Name,
			debugToolBindId(tool),
			tostring(tool:GetAttribute(TOOL_ATTR_FRUIT_KEY)),
			debugInstancePath(tool.Parent)
		)
	end)
	tool.Destroying:Connect(function()
		consumeDebug(
			"destroying player=%s tool=%s bindId=%s fruit=%s parent=%s",
			player.Name,
			tool.Name,
			debugToolBindId(tool),
			tostring(tool:GetAttribute(TOOL_ATTR_FRUIT_KEY)),
			debugInstancePath(tool.Parent)
		)
	end)
	tool.Equipped:Connect(function()
		consumeDebug(
			"equipped event player=%s tool=%s bindId=%s fruit=%s parent=%s",
			player.Name,
			tool.Name,
			debugToolBindId(tool),
			tostring(tool:GetAttribute(TOOL_ATTR_FRUIT_KEY)),
			debugInstancePath(tool.Parent)
		)
		FruitGripController.ApplyToolGrip(tool, tool:GetAttribute(TOOL_ATTR_FRUIT_KEY), {
			Tool = tool,
			Player = player,
			Character = player.Character,
		})
		task.defer(function()
			if player.Parent ~= Players then
				return
			end

			local character = player.Character
			if not character or tool.Parent ~= character then
				return
			end

			enforceManualGrip(tool, character, "equipped.defer")
		end)
		task.delay(0.25, function()
			if player.Parent ~= Players then
				return
			end

			local character = player.Character
			if not character or tool.Parent ~= character then
				return
			end

			enforceManualGrip(tool, character, "equipped.delay0.25")
		end)
	end)
	tool.Unequipped:Connect(function()
		consumeDebug(
			"unequipped event player=%s tool=%s bindId=%s fruit=%s parent=%s",
			player.Name,
			tool.Name,
			debugToolBindId(tool),
			tostring(tool:GetAttribute(TOOL_ATTR_FRUIT_KEY)),
			debugInstancePath(tool.Parent)
		)
		clearManualGrip(tool)
		FruitGripController.ApplyToolGrip(tool, tool:GetAttribute(TOOL_ATTR_FRUIT_KEY), {
			Tool = tool,
			Player = player,
			Character = player.Character,
		})
	end)
	tool.Activated:Connect(function()
		local ownedByPlayer = isToolOwnedByPlayer(tool, player)
		consumeDebug(
			"activated player=%s tool=%s bindId=%s fruit=%s owned=%s parent=%s",
			player.Name,
			tool.Name,
			debugToolBindId(tool),
			tostring(tool:GetAttribute(TOOL_ATTR_FRUIT_KEY)),
			tostring(ownedByPlayer),
			debugInstancePath(tool.Parent)
		)
		if not ownedByPlayer then
			return
		end

		requestConsume(player, tool)
	end)
end

local function findConsumableFruitTool(player, fruitKey)
	local characterTools = findFruitTools(player.Character, fruitKey)
	if #characterTools > 0 then
		return characterTools[1]
	end

	local backpackTools = findFruitTools(player:FindFirstChildOfClass("Backpack"), fruitKey)
	if #backpackTools > 0 then
		return backpackTools[1]
	end

	return nil
end

function DevilFruitInventoryService.RequestConsume(player, fruitIdentifier)
	local fruit, reason = resolveFruit(fruitIdentifier)
	if not fruit then
		consumeDebug(
			"external request blocked player=%s fruit=%s reason=%s",
			player and player.Name or "<nil>",
			tostring(fruitIdentifier),
			tostring(reason)
		)
		return false, reason
	end

	local tool = findConsumableFruitTool(player, fruit.FruitKey)
	if not tool then
		consumeDebug("external request blocked player=%s fruit=%s reason=no_tool", player.Name, fruit.FruitKey)
		return false, "no_tool"
	end

	if not isToolOwnedByPlayer(tool, player) then
		consumeDebug(
			"external request blocked player=%s fruit=%s reason=tool_not_owned tool=%s bindId=%s parent=%s",
			player.Name,
			fruit.FruitKey,
			tool.Name,
			debugToolBindId(tool),
			debugInstancePath(tool.Parent)
		)
		return false, "tool_not_owned"
	end

	hookTool(player, tool)
	consumeDebug(
		"external request player=%s fruit=%s tool=%s bindId=%s parent=%s",
		player.Name,
		fruit.FruitKey,
		tool.Name,
		debugToolBindId(tool),
		debugInstancePath(tool.Parent)
	)
	requestConsume(player, tool)
	return true, nil
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

	for index = #allTools, 1, -1 do
		local tool = allTools[index]
		if tool:GetAttribute(TOOL_ATTR_GRIP_VERSION) ~= FRUIT_TOOL_GRIP_VERSION then
			if tool.Parent then
				tool:Destroy()
			end
			table.remove(allTools, index)
		end
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
			consumeDebug(
				"sync parented player=%s tool=%s bindId=%s fruit=%s parent=%s",
				player.Name,
				tool.Name,
				debugToolBindId(tool),
				tostring(fruitKey),
				debugInstancePath(tool.Parent)
			)
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
	consumeDebug(
		"response entry player=%s accepted=%s fruit=%s hasPending=%s",
		player.Name,
		tostring(accepted),
		tostring(fruitKey),
		tostring(pending ~= nil)
	)
	if not pending then
		DevilFruitLogger.Warn("SERVER", "consume ignored player=%s reason=no_pending", player.Name)
		return
	end

	clearPendingConsume(player)

	if accepted ~= true then
		consumeDebug("response blocked player=%s reason=not_accepted", player.Name)
		DevilFruitLogger.Info("SERVER", "consume cancelled player=%s fruit=%s", player.Name, tostring(pending.FruitKey))
		return
	end

	if typeof(fruitKey) ~= "string" or fruitKey ~= pending.FruitKey then
		consumeDebug(
			"response blocked player=%s reason=fruit_mismatch expected=%s got=%s",
			player.Name,
			tostring(pending.FruitKey),
			tostring(fruitKey)
		)
		DevilFruitLogger.Warn(
			"SERVER",
			"consume ignored player=%s reason=fruit_mismatch expected=%s got=%s",
			player.Name,
			tostring(pending.FruitKey),
			tostring(fruitKey)
		)
		return
	end

	if os.clock() - pending.RequestedAt > PROMPT_TIMEOUT then
		consumeDebug("response blocked player=%s reason=timeout fruit=%s", player.Name, tostring(fruitKey))
		DevilFruitLogger.Warn("SERVER", "consume ignored player=%s reason=prompt_timeout", player.Name)
		return
	end

	local tool = pending.Tool
	if not isToolOwnedByPlayer(tool, player) then
		consumeDebug(
			"response blocked player=%s reason=tool_not_owned fruit=%s tool=%s parent=%s",
			player.Name,
			tostring(fruitKey),
			tostring(tool and tool.Name or "<nil>"),
			debugInstancePath(tool and tool.Parent)
		)
		return
	end

	local quantity, quantityReason = DevilFruitInventoryService.GetFruitQuantity(player, fruitKey)
	if quantity == nil and quantityReason ~= nil then
		DevilFruitLogger.Warn(
			"SERVER",
			"consume ignored player=%s reason=quantity_error fruit=%s err=%s",
			player.Name,
			tostring(fruitKey),
			tostring(quantityReason)
		)
		return
	end

	if (tonumber(quantity) or 0) <= 0 then
		DevilFruitLogger.Warn(
			"SERVER",
			"consume ignored player=%s reason=not_owned fruit=%s quantity=%s",
			player.Name,
			tostring(fruitKey),
			tostring(quantity)
		)
		return
	end

	local currentFruitName = DevilFruitService.GetEquippedFruit(player)
	local targetFruitName = DevilFruitConfig.ResolveFruitName(fruitKey)
	if currentFruitName ~= DevilFruitConfig.None and currentFruitName == targetFruitName then
		consumeDebug("response blocked player=%s reason=same_fruit fruit=%s", player.Name, tostring(fruitKey))
		DevilFruitLogger.Info(
			"SERVER",
			"consume ignored player=%s reason=already_equipped fruit=%s",
			player.Name,
			tostring(targetFruitName)
		)
		return
	end

	DevilFruitLogger.Info(
		"SERVER",
		"consume confirmed player=%s currentFruit=%s targetFruit=%s tool=%s",
		player.Name,
		tostring(currentFruitName),
		tostring(targetFruitName),
		tostring(tool and tool:GetFullName() or "<nil>")
	)

	consumeDebug("consume start player=%s fruit=%s", player.Name, tostring(fruitKey))
	local consumed, consumeReason = DevilFruitInventoryService.ConsumeFruit(player, fruitKey, 1)
	consumeDebug(
		"consume result player=%s fruit=%s ok=%s reason=%s",
		player.Name,
		tostring(fruitKey),
		tostring(consumed),
		tostring(consumeReason)
	)
	if not consumed then
		warn(string.format("[DevilFruitInventoryService] Failed to consume %s for %s: %s", fruitKey, player.Name, tostring(consumeReason)))
		return
	end

	consumeDebug("equip start player=%s fruit=%s target=%s", player.Name, tostring(fruitKey), tostring(targetFruitName))
	local equipped = DevilFruitService.SetEquippedFruit(player, fruitKey)
	consumeDebug("equip result player=%s fruit=%s ok=%s", player.Name, tostring(fruitKey), tostring(equipped))
	if not equipped then
		DevilFruitInventoryService.GrantFruit(player, fruitKey, 1)
		warn(string.format("[DevilFruitInventoryService] Failed to equip %s for %s after consuming", fruitKey, player.Name))
		return
	end
	DevilFruitLogger.Info(
		"SERVER",
		"consume equip applied player=%s equippedFruit=%s targetFruit=%s",
		player.Name,
		tostring(DevilFruitService.GetEquippedFruit(player)),
		tostring(targetFruitName)
	)

	if tool and tool.Parent then
		tool:Destroy()
	elseif not isToolOwnedByPlayer(tool, player) then
		DevilFruitLogger.Info(
			"SERVER",
			"consume succeeded without tool-destroy player=%s fruit=%s",
			player.Name,
			tostring(targetFruitName)
		)
	end
end

local function handleConsumeRequest(player, fruitIdentifier, source)
	consumeDebug(
		"client request entry player=%s fruit=%s source=%s",
		player.Name,
		tostring(fruitIdentifier),
		tostring(source)
	)
	local requested, reason = DevilFruitInventoryService.RequestConsume(player, fruitIdentifier)
	consumeDebug(
		"client request result player=%s fruit=%s ok=%s reason=%s",
		player.Name,
		tostring(fruitIdentifier),
		tostring(requested),
		tostring(reason)
	)
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
	requestRemote.OnServerEvent:Connect(handleConsumeRequest)
	responseRemote.OnServerEvent:Connect(handleConsumeResponse)
end

return DevilFruitInventoryService
