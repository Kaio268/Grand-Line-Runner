local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local ChestUtils = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("GrandLineRushChestUtils"))
local BrainrotQuickSlotService = require(ServerScriptService:WaitForChild("Modules"):WaitForChild("BrainrotQuickSlotService"))
local DataManager = require(ServerScriptService:WaitForChild("Data"):WaitForChild("DataManager"))
local updateRemote = ReplicatedStorage:FindFirstChild("InventoryGearRemote")
if not updateRemote then
	updateRemote = Instance.new("RemoteEvent")
	updateRemote.Name = "InventoryGearRemote"
	updateRemote.Parent = ReplicatedStorage
end

local snapshotRemote = ReplicatedStorage:FindFirstChild("InventorySnapshotRequest")
if snapshotRemote and not snapshotRemote:IsA("RemoteFunction") then
	snapshotRemote:Destroy()
	snapshotRemote = nil
end
if not snapshotRemote then
	snapshotRemote = Instance.new("RemoteFunction")
	snapshotRemote.Name = "InventorySnapshotRequest"
	snapshotRemote.Parent = ReplicatedStorage
end

local equipRemote = ReplicatedStorage:FindFirstChild("EquipToggleRemote")
if not equipRemote then
	equipRemote = Instance.new("RemoteEvent")
	equipRemote.Name = "EquipToggleRemote"
	equipRemote.Parent = ReplicatedStorage
end

local Module = {}
local chestToolServiceCache = nil
local devilFruitInventoryServiceCache = nil
local sliceServiceCache = nil
local CHEST_DEBUG = true
local FRUIT_EQUIP_DEBUG = true
local R6G_WELD_DEBUG = true
local INVENTORY_SNAPSHOT_DEBUG = true
local DATA_READY_TIMEOUT = 30
local TOOL_KIND_DEVIL_FRUIT = "DevilFruit"
local TOOL_ATTR_KIND = "InventoryItemKind"
local CONSUME_BIND_ID_ATTRIBUTE = "__DevilFruitConsumeBindId"
local MODEL_VARIANT_R6G = "R6G"
local MODEL_VARIANT_ATTRIBUTE_NAMES = {
	"FruitHoldModelVariant",
	"FruitGripModelVariant",
	"FruitModelVariant",
	"EatAnimationRig",
	"CurrentModelAsset",
}
local EQUIPPED_ITEM_KIND_ATTRIBUTE = "EquippedInventoryItemKind"
local EQUIPPED_ITEM_NAME_ATTRIBUTE = "EquippedInventoryItemName"

local function chestDebug(message, ...)
	if CHEST_DEBUG ~= true then
		return
	end

	warn(string.format("[GLR ChestDebug][InventorySystem] " .. tostring(message), ...))
end

local function inventorySnapshotLog(...)
	if INVENTORY_SNAPSHOT_DEBUG then
		print("[INV][SNAPSHOT]", ...)
	end
end

local function fruitEquipDebug(message, ...)
	if FRUIT_EQUIP_DEBUG ~= true then
		return
	end

	local ok, formatted = pcall(string.format, "[FruitConsumeDebug][InventoryEquip] " .. tostring(message), ...)
	print(ok and formatted or ("[FruitConsumeDebug][InventoryEquip] " .. tostring(message)))
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

	local ok, formatted = pcall(string.format, "[R6G FRUIT WELD][SERVER][InventorySystem] " .. tostring(message), ...)
	print(ok and formatted or ("[R6G FRUIT WELD][SERVER][InventorySystem] " .. tostring(message)))
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

local function debugToolActivationState(tool)
	if not tool or not tool:IsA("Tool") then
		return "tool=<nil>"
	end

	return string.format(
		"bindId=%s parent=%s enabled=%s manual=%s requiresHandle=%s hasHandle=%s",
		debugToolBindId(tool),
		debugInstancePath(tool.Parent),
		tostring(tool.Enabled),
		tostring(tool.ManualActivationOnly),
		tostring(tool.RequiresHandle),
		tostring(tool:FindFirstChild("Handle") ~= nil)
	)
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

local function getDevilFruitInventoryService()
	if devilFruitInventoryServiceCache ~= nil then
		return devilFruitInventoryServiceCache
	end

	local ok, service = pcall(function()
		return require(ServerScriptService:WaitForChild("Modules"):WaitForChild("DevilFruitInventoryService"))
	end)

	devilFruitInventoryServiceCache = if ok then service else false
	return if devilFruitInventoryServiceCache == false then nil else devilFruitInventoryServiceCache
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

local function isR6GModelValue(value)
	return typeof(value) == "string" and string.upper(value) == MODEL_VARIANT_R6G
end

local function isR6GCharacter(player, character)
	local humanoid = character and character:FindFirstChildOfClass("Humanoid") or nil
	for _, target in ipairs({ character, humanoid, player }) do
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

local function shouldUseR6GripFrame(player, character, tool)
	return tool
		and tool:IsA("Tool")
		and tool:GetAttribute(TOOL_ATTR_KIND) == TOOL_KIND_DEVIL_FRUIT
		and isR6GCharacter(player, character)
end

local function getGripPart(character)
	if not character then
		return nil
	end

	return character:FindFirstChild("RightHand")
		or character:FindFirstChild("RightLowerArm")
		or character:FindFirstChild("Right Arm")
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

local function logR6GLiveGripState(source, player, tool, character)
	if not (tool and tool:IsA("Tool") and shouldUseR6GripFrame(player, character, tool)) then
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

local function setEquippedInventoryAttributes(player, itemKind, itemName)
	if typeof(itemKind) == "string" and itemKind ~= "" and typeof(itemName) == "string" and itemName ~= "" then
		player:SetAttribute(EQUIPPED_ITEM_KIND_ATTRIBUTE, itemKind)
		player:SetAttribute(EQUIPPED_ITEM_NAME_ATTRIBUTE, itemName)
	else
		player:SetAttribute(EQUIPPED_ITEM_KIND_ATTRIBUTE, nil)
		player:SetAttribute(EQUIPPED_ITEM_NAME_ATTRIBUTE, nil)
	end
end

local function resolveToolIdentity(player, tool)
	if not tool or not tool:IsA("Tool") then
		return nil, nil
	end

	local itemKind = tool:GetAttribute("InventoryItemKind")
	local itemName = tool:GetAttribute("InventoryItemName") or tool:GetAttribute("InvItem") or tool.Name
	if typeof(itemName) ~= "string" or itemName == "" then
		return nil, nil
	end

	if typeof(itemKind) == "string" and itemKind ~= "" then
		return itemKind, itemName
	end

	local inventory = player:FindFirstChild("Inventory")
	local devilFruits = inventory and inventory:FindFirstChild("DevilFruits")
	local gears = player:FindFirstChild("Gears")
	local chestInventory = player:FindFirstChild("ChestInventory")

	if inventory and inventory:FindFirstChild(itemName) then
		return "Brainrot", itemName
	end
	if devilFruits and devilFruits:FindFirstChild(itemName) then
		return "DevilFruit", itemName
	end
	if chestInventory and chestInventory:FindFirstChild(itemName) then
		return "Chest", itemName
	end
	if gears and gears:FindFirstChild(itemName) then
		return "Gear", itemName
	end

	return nil, itemName
end

local function syncEquippedInventoryAttributes(player)
	local character = player.Character
	if not character then
		setEquippedInventoryAttributes(player, nil, nil)
		return
	end

	for _, child in ipairs(character:GetChildren()) do
		if child:IsA("Tool") then
			local itemKind, itemName = resolveToolIdentity(player, child)
			setEquippedInventoryAttributes(player, itemKind, itemName)
			return
		end
	end

	setEquippedInventoryAttributes(player, nil, nil)
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
		task.defer(function()
			if player.Parent == Players then
				syncEquippedInventoryAttributes(player)
			end
		end)
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
			if ChestUtils.GetInventoryName(chest) == tostring(tierName) then
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

local function waitForPlayerDataReady(player)
	if player:GetAttribute("PlayerDataReady") == true and DataManager:IsReady(player) then
		return true
	end

	if DataManager.WaitUntilReady and DataManager:WaitUntilReady(player, DATA_READY_TIMEOUT) then
		local deadline = os.clock() + DATA_READY_TIMEOUT
		while player.Parent == Players and os.clock() < deadline do
			if player:GetAttribute("PlayerDataReady") == true then
				return true
			end
			task.wait(0.1)
		end
	end

	return player.Parent == Players and player:GetAttribute("PlayerDataReady") == true and DataManager:IsReady(player)
end

local function readPositiveQuantity(folder)
	if not folder or not folder:IsA("Folder") then
		return nil
	end

	local quantity = folder:FindFirstChild("Quantity")
	if not quantity or not quantity:IsA("NumberValue") then
		return nil
	end

	return math.max(0, math.floor(tonumber(quantity.Value) or 0))
end

local function appendQuantityEntry(list, name, quantity)
	if quantity and quantity > 0 then
		table.insert(list, {
			Name = tostring(name),
			Quantity = quantity,
		})
	end
end

local function buildInventorySnapshot(player)
	local ready = waitForPlayerDataReady(player)
	if not ready then
		inventorySnapshotLog("notReady", "player", player.Name)
		return {
			Ready = false,
			Reason = "data_not_ready",
			Brainrots = {},
			Gears = {},
			DevilFruits = {},
			Chests = {},
			Crew = {},
			Counts = {
				Brainrots = 0,
				Gears = 0,
				DevilFruits = 0,
				Chests = 0,
				Crew = 0,
			},
		}
	end

	local brainrots = {}
	local gears = {}
	local devilFruits = {}
	local chests = {}
	local crew = {}

	local inventory = player:FindFirstChild("Inventory") or player:WaitForChild("Inventory", 5)
	if inventory and inventory:IsA("Folder") then
		for _, child in ipairs(inventory:GetChildren()) do
			if child:IsA("Folder") then
				if child.Name == "DevilFruits" then
					for _, fruitFolder in ipairs(child:GetChildren()) do
						appendQuantityEntry(devilFruits, fruitFolder.Name, readPositiveQuantity(fruitFolder))
					end
				elseif child.Name ~= "Feed" then
					appendQuantityEntry(brainrots, child.Name, readPositiveQuantity(child))
				end
			end
		end
	end

	local gearsFolder = player:FindFirstChild("Gears") or player:WaitForChild("Gears", 5)
	if gearsFolder and gearsFolder:IsA("Folder") then
		for _, child in ipairs(gearsFolder:GetChildren()) do
			if child:IsA("BoolValue") and child.Value == true then
				table.insert(gears, {
					Name = child.Name,
					Owned = true,
				})
			end
		end
	end

	local chestInventory = player:FindFirstChild("ChestInventory")
	if chestInventory and chestInventory:IsA("Folder") then
		for _, child in ipairs(chestInventory:GetChildren()) do
			appendQuantityEntry(chests, child.Name, readPositiveQuantity(child))
		end
	end

	local crewInventory = player:FindFirstChild("CrewInventory")
	if crewInventory and crewInventory:IsA("Folder") then
		for _, child in ipairs(crewInventory:GetChildren()) do
			if child:IsA("Folder") then
				local quantity = readPositiveQuantity(child)
				if quantity then
					appendQuantityEntry(crew, child.Name, quantity)
				else
					table.insert(crew, { Name = child.Name })
				end
			elseif child:IsA("BoolValue") and child.Value == true then
				table.insert(crew, { Name = child.Name, Owned = true })
			end
		end
	end

	local snapshot = {
		Ready = true,
		Brainrots = brainrots,
		Gears = gears,
		DevilFruits = devilFruits,
		Chests = chests,
		Crew = crew,
		Counts = {
			Brainrots = #brainrots,
			Gears = #gears,
			DevilFruits = #devilFruits,
			Chests = #chests,
			Crew = #crew,
		},
	}

	inventorySnapshotLog(
		"sent",
		"player",
		player.Name,
		"brainrots",
		snapshot.Counts.Brainrots,
		"crew",
		snapshot.Counts.Crew,
		"devilFruits",
		snapshot.Counts.DevilFruits,
		"gears",
		snapshot.Counts.Gears,
		"chests",
		snapshot.Counts.Chests
	)

	return snapshot
end

local function toggleEquip(player, kind, toolName)
	local debugDevilFruit = kind == TOOL_KIND_DEVIL_FRUIT
	if debugDevilFruit then
		fruitEquipDebug(
			"toggle entry player=%s kind=%s name=%s character=%s",
			player.Name,
			tostring(kind),
			tostring(toolName),
			debugInstancePath(player.Character)
		)
	end

	local humanoid = getHumanoid(player)
	if not humanoid then
		if debugDevilFruit then
			fruitEquipDebug("toggle blocked player=%s name=%s reason=no_humanoid", player.Name, tostring(toolName))
		end
		return
	end

	local char = player.Character
	if not char then
		if debugDevilFruit then
			fruitEquipDebug("toggle blocked player=%s name=%s reason=no_character", player.Name, tostring(toolName))
		end
		return
	end

	local equipped = findInventoryTool(char, kind, toolName) or char:FindFirstChild(toolName)
	if equipped and equipped:IsA("Tool") then
		if debugDevilFruit then
			fruitEquipDebug(
				"toggle already equipped -> unequip player=%s name=%s %s",
				player.Name,
				tostring(toolName),
				debugToolActivationState(equipped)
			)
		end
		if kind == "Chest" then
			chestDebug(
				"toggleEquip chest already equipped player=%s tool=%s -> unequip",
				player.Name,
				tostring(toolName)
			)
		end
		humanoid:UnequipTools()
		task.defer(function()
			if player.Parent == Players then
				syncEquippedInventoryAttributes(player)
			end
		end)
		return
	end

	local bp = player:FindFirstChild("Backpack")
	if not bp then
		if debugDevilFruit then
			fruitEquipDebug("toggle blocked player=%s name=%s reason=no_backpack", player.Name, tostring(toolName))
		end
		return
	end

	local tool = findInventoryTool(bp, kind, toolName) or bp:FindFirstChild(toolName)
	if debugDevilFruit then
		fruitEquipDebug(
			"toggle backpack lookup player=%s name=%s found=%s %s",
			player.Name,
			tostring(toolName),
			tostring(tool ~= nil and tool:IsA("Tool")),
			debugToolActivationState(tool)
		)
	end
	if kind == "Chest" then
		chestDebug(
			"toggleEquip chest pre-equip player=%s tool=%s backpackTool=%s backpack=%s",
			player.Name,
			tostring(toolName),
			tostring(tool ~= nil and tool:IsA("Tool")),
			bp:GetFullName()
		)
	end
	if not tool or not tool:IsA("Tool") then
		if debugDevilFruit then
			fruitEquipDebug("toggle blocked player=%s name=%s reason=tool_not_found", player.Name, tostring(toolName))
		end
		return
	end

	humanoid:UnequipTools()
	if kind == "Chest" then
		chestDebug("toggleEquip chest calling Humanoid:EquipTool player=%s tool=%s", player.Name, tostring(tool.Name))
	end
	if debugDevilFruit then
		fruitEquipDebug(
			"toggle equip start player=%s name=%s tool=%s %s",
			player.Name,
			tostring(toolName),
			tool.Name,
			debugToolActivationState(tool)
		)
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

		local function enforceWeld(finalTool, source)
			local handle = finalTool:FindFirstChild("Handle")
			if not handle then return end

			local useR6GripFrame = shouldUseR6GripFrame(player, refreshedChar, finalTool)
			if useR6GripFrame then
				logR6GLiveGripState((source or "toggle.enforceWeld") .. ":before", player, finalTool, refreshedChar)
			end

			local existingGrips = getConnectedRightGripJoints(refreshedChar, handle)
			if #existingGrips > 0 and not useR6GripFrame then
				return
			end

			if #existingGrips > 0 then
				for _, existingGrip in ipairs(existingGrips) do
					r6gWeldDebug(
						"%s replacing connected RightGrip class=%s parent=%s",
						tostring(source or "toggle.enforceWeld"),
						existingGrip.ClassName,
						debugInstancePath(existingGrip.Parent)
					)
					existingGrip:Destroy()
				end
			end

			if #existingGrips == 0 or useR6GripFrame then
				local gripPart = getGripPart(refreshedChar)

				if gripPart then
					local weld = Instance.new("Weld")
					weld.Name = "ManualGrip"
					weld.Part0 = gripPart
					weld.Part1 = handle
					weld.C1 = finalTool.Grip

					if useR6GripFrame then
						finalTool:SetAttribute("FruitManualGripFrame", "R6")
					end

					local gripC0, attachmentName, c0Mode = resolveManualGripC0(gripPart)
					weld.C0 = gripC0
					finalTool:SetAttribute("FruitManualGripAttachmentUsed", attachmentName)
					finalTool:SetAttribute("FruitManualGripC0Mode", c0Mode)

					weld.Parent = handle
					print(string.format("[Inventory] Applied manual weld for R6G model compatibility c0Mode=%s.", c0Mode))
					if useR6GripFrame then
						logR6GLiveGripState((source or "toggle.enforceWeld") .. ":after", player, finalTool, refreshedChar)
					end
				end
			end
		end

		local equipped = findInventoryTool(refreshedChar, kind, toolName) or refreshedChar:FindFirstChild(toolName)
		if equipped and equipped:IsA("Tool") then
			if debugDevilFruit then
				fruitEquipDebug(
					"toggle equip success player=%s name=%s tool=%s %s",
					player.Name,
					tostring(toolName),
					equipped.Name,
					debugToolActivationState(equipped)
				)
				fruitEquipDebug(
					"activation expected after world click player=%s name=%s bindId=%s equippedInCharacter=%s enabled=%s manual=%s",
					player.Name,
					tostring(toolName),
					debugToolBindId(equipped),
					tostring(equipped.Parent == refreshedChar),
					tostring(equipped.Enabled),
					tostring(equipped.ManualActivationOnly)
				)
			end
			if kind == "Chest" then
				chestDebug(
					"toggleEquip chest success player=%s tool=%s parent=%s",
					player.Name,
					tostring(equipped.Name),
					equipped.Parent and equipped.Parent:GetFullName() or "nil"
				)
			end
			setEquippedInventoryAttributes(player, kind, toolName)
			enforceWeld(equipped, "toggle.equipped")
			if kind == TOOL_KIND_DEVIL_FRUIT then
				task.delay(0.25, function()
					if player.Parent == Players and equipped.Parent == refreshedChar then
						enforceWeld(equipped, "toggle.equipped.delay0.25")
					end
				end)
			end
			return
		end

		local backpack = player:FindFirstChildOfClass("Backpack")
		local fallbackTool = findInventoryTool(backpack, kind, toolName) or (backpack and backpack:FindFirstChild(toolName))
		if fallbackTool and fallbackTool:IsA("Tool") then
			if debugDevilFruit then
				fruitEquipDebug(
					"toggle fallback parent->Character player=%s name=%s tool=%s %s",
					player.Name,
					tostring(toolName),
					fallbackTool.Name,
					debugToolActivationState(fallbackTool)
				)
			end
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
			setEquippedInventoryAttributes(player, kind, toolName)
			enforceWeld(fallbackTool, "toggle.fallback")
			if kind == TOOL_KIND_DEVIL_FRUIT then
				task.delay(0.25, function()
					if player.Parent == Players and fallbackTool.Parent == refreshedChar then
						enforceWeld(fallbackTool, "toggle.fallback.delay0.25")
					end
				end)
			end
		else
			if debugDevilFruit then
				fruitEquipDebug("toggle equip failed player=%s name=%s reason=no_character_tool_after_equip", player.Name, tostring(toolName))
			end
		end

		if kind == "Chest" and not (fallbackTool and fallbackTool:IsA("Tool")) then
			chestDebug(
				"toggleEquip chest failed to find tool after EquipTool player=%s tool=%s",
				player.Name,
				tostring(toolName)
			)
		end
	end)
end

local function requestDevilFruitConsume(player, fruitKey)
	local inventoryService = getDevilFruitInventoryService()
	if not inventoryService or not inventoryService.RequestConsume then
		fruitEquipDebug("consume bridge blocked player=%s fruit=%s reason=missing_inventory_service", player.Name, tostring(fruitKey))
		return
	end

	local requested, reason = inventoryService.RequestConsume(player, fruitKey)
	fruitEquipDebug(
		"consume bridge result player=%s fruit=%s ok=%s reason=%s",
		player.Name,
		tostring(fruitKey),
		tostring(requested),
		tostring(reason)
	)
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

snapshotRemote.OnServerInvoke = function(player)
	inventorySnapshotLog("request", "player", player.Name)
	return buildInventorySnapshot(player)
end

equipRemote.OnServerEvent:Connect(function(player, kind, name)
	if typeof(kind) ~= "string" or typeof(name) ~= "string" then return end
	if kind == TOOL_KIND_DEVIL_FRUIT then
		fruitEquipDebug(
			"EquipToggleRemote received player=%s payload={kind=%s,name=%s}",
			player.Name,
			tostring(kind),
			tostring(name)
		)
	end
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
		local canEquip = BrainrotQuickSlotService.CanEquipBrainrot(player, name)
		if not canEquip then
			BrainrotQuickSlotService.PromptUnlockForBrainrot(player, name)
			return
		end
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
		local character = player.Character
		local equipped = findInventoryTool(character, kind, name) or (character and character:FindFirstChild(name))
		if equipped and equipped:IsA("Tool") then
			toggleEquip(player, kind, name)
			return
		end

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

		local function bindCharacter(character)
			syncEquippedInventoryAttributes(player)

			character.ChildAdded:Connect(function(child)
				if child:IsA("Tool") then
					task.defer(function()
						if player.Parent == Players and character.Parent ~= nil then
							syncEquippedInventoryAttributes(player)
						end
					end)
				end
			end)

			character.ChildRemoved:Connect(function(child)
				if child:IsA("Tool") then
					task.defer(function()
						if player.Parent == Players then
							syncEquippedInventoryAttributes(player)
						end
					end)
				end
			end)
		end

		if player.Character then
			bindCharacter(player.Character)
		else
			syncEquippedInventoryAttributes(player)
		end
		player.CharacterAdded:Connect(bindCharacter)

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
