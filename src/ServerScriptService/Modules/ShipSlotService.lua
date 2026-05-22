local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ShipVisuals = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("ShipVisuals"))

local ShipSlotService = {}

local SLOT_CONTAINER_NAME = "CrewSlots"
local HANDLE_NAME = "Handle"
local CLAIM_EXACT_NAME = "claim"
local HITBOX_EXACT_NAME = "hitbox"
local CAPTAIN_SLOT_KEY = "Captain"
local CAPTAIN_SLOT_NAME = tostring(ShipVisuals.CaptainSlotName or "Captain's Spot")

local MONEY_LABEL_NAMES = {
	"Money",
	"Beli",
	"Amount",
}

local ACTIVE_ASSET_CAPACITY_ATTRIBUTE = "ActiveShipAssetNormalSlotCapacity"

local TEXT_CLASSES = {
	TextLabel = true,
	TextButton = true,
	TextBox = true,
}

local function normalizeInstanceName(name)
	return string.lower(tostring(name or "")):gsub("[^%w]", "")
end

local function parseSlotNumber(slotNumber)
	local numberValue = tonumber(slotNumber)
	if not numberValue or numberValue ~= numberValue or numberValue == math.huge or numberValue == -math.huge then
		return nil
	end

	numberValue = math.floor(numberValue)
	if numberValue < 1 then
		return nil
	end

	return numberValue
end

local function normalizeSlotNumber(slotNumber)
	local numberValue = parseSlotNumber(slotNumber)
	return if numberValue then tostring(numberValue) else nil
end

local function findSlotContainer(activeShip)
	if not activeShip then
		return nil
	end

	local container = activeShip:FindFirstChild(SLOT_CONTAINER_NAME)
	if container then
		return container
	end

	return activeShip
end

local function getHandleFromSlot(slot)
	if not slot then
		return nil
	end

	if slot:IsA("BasePart") then
		return slot
	end

	local directHandle = slot:FindFirstChild(HANDLE_NAME)
	if directHandle and directHandle:IsA("BasePart") then
		return directHandle
	end

	local nestedHandle = slot:FindFirstChild(HANDLE_NAME, true)
	if nestedHandle and nestedHandle:IsA("BasePart") then
		return nestedHandle
	end

	return nil
end

local function getMaxSlotNumber(activeShip, options)
	if options and options.IgnoreCapacity == true then
		return nil
	end

	local configuredMax = options and (options.MaxSlotNumber or options.MaxSlots or options.NormalSlotCapacity)
	if configuredMax == nil and activeShip then
		configuredMax = activeShip:GetAttribute(ACTIVE_ASSET_CAPACITY_ATTRIBUTE)
	end

	return parseSlotNumber(configuredMax)
end

local function isTextControl(instance)
	return typeof(instance) == "Instance" and TEXT_CLASSES[instance.ClassName] == true
end

local function isClaimContainerName(name)
	local normalized = normalizeInstanceName(name)
	if normalized == CLAIM_EXACT_NAME then
		return true
	end

	local hasClaim = string.find(normalized, "claim", 1, true) ~= nil
	local hasCollection = string.find(normalized, "collection", 1, true) ~= nil
	local hasPad = string.find(normalized, "pad", 1, true) ~= nil
	local hasBeli = string.find(normalized, "beli", 1, true) ~= nil
	local hasCrewmate = string.find(normalized, "crewmate", 1, true) ~= nil

	return (hasClaim and (hasCollection or hasPad or hasBeli or hasCrewmate))
		or (hasCollection and hasPad)
		or (hasCrewmate and hasBeli and hasCollection)
end

local function isHitboxName(name)
	return normalizeInstanceName(name) == HITBOX_EXACT_NAME
end

local function findFirstChildByNormalizedName(root, normalizedName, recursive)
	if not root then
		return nil
	end

	for _, child in ipairs(if recursive then root:GetDescendants() else root:GetChildren()) do
		if normalizeInstanceName(child.Name) == normalizedName then
			return child
		end
	end

	return nil
end

local function findFirstBasePartByNormalizedName(root, normalizedName, recursive)
	local instance = findFirstChildByNormalizedName(root, normalizedName, recursive)
	if instance and instance:IsA("BasePart") then
		return instance
	end

	if not root then
		return nil
	end

	for _, child in ipairs(if recursive then root:GetDescendants() else root:GetChildren()) do
		if child:IsA("BasePart") and normalizeInstanceName(child.Name) == normalizedName then
			return child
		end
	end

	return nil
end

local function findClaimContainerInChildren(root, recursive, descriptive)
	if not root then
		return nil
	end

	local children = if recursive then root:GetDescendants() else root:GetChildren()
	for _, child in ipairs(children) do
		local normalizedName = normalizeInstanceName(child.Name)
		if descriptive then
			if isClaimContainerName(child.Name) then
				return child
			end
		elseif normalizedName == CLAIM_EXACT_NAME then
			return child
		end
	end

	return nil
end

local function getTextTarget(root, name)
	if not root then
		return nil
	end

	local target = root:FindFirstChild(name, true)
	if target then
		if isTextControl(target) then
			return target
		end

		for _, descendant in ipairs(target:GetDescendants()) do
			if isTextControl(descendant) then
				return descendant
			end
		end
	end

	local normalizedName = normalizeInstanceName(name)
	for _, descendant in ipairs(root:GetDescendants()) do
		if isTextControl(descendant) and normalizeInstanceName(descendant.Name) == normalizedName then
			return descendant
		end
	end

	return nil
end

local function collectBillboardGuis(root)
	local billboards = {}
	if not root then
		return billboards
	end

	if root:IsA("BillboardGui") then
		billboards[#billboards + 1] = root
	end

	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant:IsA("BillboardGui") then
			billboards[#billboards + 1] = descendant
		end
	end

	return billboards
end

local function collectTextControls(roots)
	local controls = {}

	for _, root in ipairs(roots) do
		if isTextControl(root) then
			controls[#controls + 1] = root
		end

		for _, descendant in ipairs(root:GetDescendants()) do
			if isTextControl(descendant) then
				controls[#controls + 1] = descendant
			end
		end
	end

	return controls
end

function ShipSlotService.NormalizeSlotNumber(slotNumber)
	return normalizeSlotNumber(slotNumber)
end

ShipSlotService.CaptainSlotKey = CAPTAIN_SLOT_KEY
ShipSlotService.CaptainSlotName = CAPTAIN_SLOT_NAME

function ShipSlotService.NormalizeInstanceName(name)
	return normalizeInstanceName(name)
end

function ShipSlotService.IsCaptainSlotName(name)
	return normalizeInstanceName(name) == normalizeInstanceName(CAPTAIN_SLOT_NAME)
end

function ShipSlotService.IsClaimContainerName(name)
	return isClaimContainerName(name)
end

function ShipSlotService.IsHitboxName(name)
	return isHitboxName(name)
end

function ShipSlotService.GetSlot(activeShip, slotNumber)
	local slotName = normalizeSlotNumber(slotNumber)
	if not slotName then
		return nil
	end

	local container = findSlotContainer(activeShip)
	if not container then
		return nil
	end

	return container:FindFirstChild(slotName)
end

function ShipSlotService.GetCaptainSlot(activeShip)
	if not activeShip then
		return nil
	end

	local direct = activeShip:FindFirstChild(CAPTAIN_SLOT_NAME)
	if direct then
		return direct
	end

	for _, child in ipairs(activeShip:GetChildren()) do
		if ShipSlotService.IsCaptainSlotName(child.Name) then
			return child
		end
	end

	return nil
end

function ShipSlotService.GetSlotHandle(activeShip, slotNumber)
	local slot = ShipSlotService.GetSlot(activeShip, slotNumber)
	if not slot then
		return nil, nil
	end

	local handle = getHandleFromSlot(slot)
	if not handle then
		warn(("[ShipSlotService] Ship slot %s is missing a BasePart Handle: %s"):format(
			tostring(slotNumber),
			slot:GetFullName()
		))
	end

	return slot, handle
end

function ShipSlotService.GetCaptainSlotHandle(activeShip)
	local captainSlot = ShipSlotService.GetCaptainSlot(activeShip)
	if not captainSlot then
		return nil, nil
	end

	local handle = getHandleFromSlot(captainSlot)
	if not handle then
		warn(("[ShipSlotService] Captain slot is missing a BasePart Handle: %s"):format(
			captainSlot:GetFullName()
		))
	end

	return captainSlot, handle
end

function ShipSlotService.GetCaptainSlotPrompt(activeShip)
	local captainSlot, handle = ShipSlotService.GetCaptainSlotHandle(activeShip)
	if not handle then
		return captainSlot, handle, nil
	end

	return captainSlot, handle, handle:FindFirstChildOfClass("ProximityPrompt")
end

function ShipSlotService.IsCaptainSlot(instance)
	return typeof(instance) == "Instance" and ShipSlotService.IsCaptainSlotName(instance.Name)
end

function ShipSlotService.GetAvailableSlotNumbers(activeShip, options)
	local container = findSlotContainer(activeShip)
	if not container then
		return {}
	end

	local slotNumbers = {}
	local maxSlotNumber = getMaxSlotNumber(activeShip, options)

	for _, child in ipairs(container:GetChildren()) do
		local slotNumber = parseSlotNumber(child.Name)
		if slotNumber and (not maxSlotNumber or slotNumber <= maxSlotNumber) and getHandleFromSlot(child) then
			slotNumbers[#slotNumbers + 1] = slotNumber
		end
	end

	table.sort(slotNumbers)

	local normalized = table.create(#slotNumbers)
	for index, slotNumber in ipairs(slotNumbers) do
		normalized[index] = tostring(slotNumber)
	end

	return normalized
end

function ShipSlotService.GetAllSlotNumbers(activeShip)
	return ShipSlotService.GetAvailableSlotNumbers(activeShip, {
		IgnoreCapacity = true,
	})
end

function ShipSlotService.HasSlot(activeShip, slotNumber)
	local _, handle = ShipSlotService.GetSlotHandle(activeShip, slotNumber)
	return handle ~= nil
end

function ShipSlotService.GetClaimContainer(slotModel)
	if not slotModel then
		return nil
	end

	return findClaimContainerInChildren(slotModel, false, false)
		or findClaimContainerInChildren(slotModel, true, false)
		or findClaimContainerInChildren(slotModel, false, true)
		or findClaimContainerInChildren(slotModel, true, true)
end

function ShipSlotService.GetClaimHitBox(slotModel)
	if not slotModel then
		return nil
	end

	local claim = ShipSlotService.GetClaimContainer(slotModel)
	local searchRoot = claim or slotModel
	local hitBox = findFirstBasePartByNormalizedName(searchRoot, HITBOX_EXACT_NAME, false)
		or findFirstBasePartByNormalizedName(searchRoot, HITBOX_EXACT_NAME, true)

	if hitBox then
		return hitBox
	end

	if claim then
		return findFirstBasePartByNormalizedName(slotModel, HITBOX_EXACT_NAME, true)
	end

	return nil
end

function ShipSlotService.GetClaimMoneyLabel(slotModel)
	if not slotModel then
		return nil
	end

	local claim = ShipSlotService.GetClaimContainer(slotModel)
	local billboards = collectBillboardGuis(claim or slotModel)
	if #billboards == 0 then
		return nil
	end

	for _, labelName in ipairs(MONEY_LABEL_NAMES) do
		for _, billboard in ipairs(billboards) do
			local label = getTextTarget(billboard, labelName)
			if label then
				return label
			end
		end
	end

	local textControls = collectTextControls(billboards)
	return if #textControls == 1 then textControls[1] else nil
end

function ShipSlotService.IsClaimHitBox(instance)
	return typeof(instance) == "Instance" and instance:IsA("BasePart") and isHitboxName(instance.Name)
end

function ShipSlotService.IsInteractionPart(part)
	if typeof(part) ~= "Instance" or not part:IsA("BasePart") then
		return false
	end

	local normalizedName = normalizeInstanceName(part.Name)
	if normalizedName == "handle" or normalizedName == "levelup" or normalizedName == HITBOX_EXACT_NAME then
		return true
	end

	if part:FindFirstChildWhichIsA("ProximityPrompt", true)
		or part:FindFirstChildWhichIsA("ClickDetector", true)
		or part:FindFirstChildWhichIsA("BillboardGui", true)
		or part:FindFirstChildWhichIsA("SurfaceGui", true)
	then
		return true
	end

	local parent = part.Parent
	while parent do
		if isClaimContainerName(parent.Name) then
			return true
		end

		parent = parent.Parent
	end

	return false
end

return ShipSlotService
