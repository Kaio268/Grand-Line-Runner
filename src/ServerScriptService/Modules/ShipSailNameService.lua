local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextService = game:GetService("TextService")

local ShipVisuals = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("ShipVisuals"))

local ShipSailNameService = {}

local CONFIG = ShipVisuals.SailName or {}
local MODEL_CONFIGS = CONFIG.Models or {}
local ATTR = ShipVisuals.Attributes or {}

local FOLDER_NAME = tostring(CONFIG.FolderName or "ShipSailCustomization")
local ANCHOR_NAME = tostring(CONFIG.AnchorName or "ShipSailIdentityAnchor")
local RUNTIME_ATTRIBUTE = tostring(CONFIG.RuntimeAttribute or "ShipSailIdentityRuntime")
local ENABLED_ATTRIBUTE = tostring(CONFIG.EnabledAttribute or "SailIdentityEnabled")
local OWNER_USER_ID_ATTRIBUTE = tostring(CONFIG.OwnerUserIdAttribute or "ShipSailIdentityOwnerUserId")
local OWNER_NAME_ATTRIBUTE = tostring(CONFIG.OwnerNameAttribute or "ShipSailIdentityOwnerName")
local DISPLAY_TEXT_ATTRIBUTE = tostring(CONFIG.DisplayTextAttribute or "ShipSailIdentityDisplayText")
local OWNER_DISPLAY_TEXT_ATTRIBUTE = tostring(CONFIG.OwnerDisplayTextAttribute or "OwnerDisplayText")
local CONFIG_KEY_ATTRIBUTE = tostring(CONFIG.ConfigKeyAttribute or "ShipSailIdentityConfigKey")
local FAILURE_REASON_ATTRIBUTE = tostring(CONFIG.FailureReasonAttribute or "ShipSailIdentityFailureReason")
local ANCHOR_WELD_NAME = "ShipSailIdentityAnchorWeld"

local STALE_SURFACE_GUI_NAMES = {
	ShipSailNameFront = true,
	ShipSailNameBack = true,
	ShipSailIdentitySurfaceGui = true,
}

local STALE_PART_NAMES = {
	ShipSailNameFrontPlate = true,
	ShipSailNameBackPlate = true,
}

local STALE_ATTRIBUTE_NAMES = {
	"SailNameRenderMode",
	"SailNameOverlayPath",
	"SailNameTextureState",
	"SailNameTextureFailureReason",
	"SailNameEmblemPresetId",
	"ShipSailNameRuntime",
	"ShipSailNameOwnerUserId",
	"ShipSailNameText",
	"ShipSailNameModelName",
	"SailNameApplied",
	"SailNameTargetPath",
	"SailNameResolvedText",
	"SailNameFailureReason",
	"SailNameConfigKey",
}

local warned = {}

local function warnOnce(key, message, ...)
	if warned[key] then
		return
	end

	warned[key] = true
	warn(string.format(message, ...))
end

local function trim(value)
	if type(value) ~= "string" then
		return nil
	end

	local trimmed = string.match(value, "^%s*(.-)%s*$")
	if not trimmed or trimmed == "" then
		return nil
	end

	return trimmed
end

local function clampDisplayText(text)
	local maxLength = tonumber(CONFIG.MaxDisplayNameLength) or 24
	if maxLength <= 0 then
		return text
	end

	local ok, length = pcall(utf8.len, text)
	if ok and length and length > maxLength then
		local offset = utf8.offset(text, maxLength + 1)
		if offset then
			return string.sub(text, 1, offset - 1)
		end
	end

	return text
end

local function filterBroadcastDisplayText(player, text)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return nil
	end

	local ok, resultOrError = pcall(function()
		local filterResult = TextService:FilterStringAsync(text, player.UserId, Enum.TextFilterContext.PublicChat)
		return filterResult:GetNonChatStringForBroadcastAsync()
	end)

	if ok then
		return trim(resultOrError)
	end

	warnOnce(
		"filter_failed_" .. tostring(player.UserId),
		"[ShipSailNameService] Failed to filter custom sail display text for %s: %s",
		player.Name,
		tostring(resultOrError)
	)
	return nil
end

local function addUniqueString(values, seen, value)
	value = trim(value)
	if not value or seen[value] then
		return
	end

	seen[value] = true
	values[#values + 1] = value
end

local function getModelNameCandidates(activeShip, visual)
	local candidates = {}
	local seen = {}

	if visual then
		addUniqueString(candidates, seen, visual.ModelName)
	end

	if activeShip then
		addUniqueString(candidates, seen, ATTR.ActiveModelName and activeShip:GetAttribute(ATTR.ActiveModelName))
		addUniqueString(candidates, seen, ATTR.SourceModelName and activeShip:GetAttribute(ATTR.SourceModelName))
		addUniqueString(candidates, seen, activeShip.Name)
	end

	return candidates
end

local function resolvePath(root, path)
	if not root or type(path) ~= "table" then
		return nil
	end

	local current = root
	for _, segment in ipairs(path) do
		current = current:FindFirstChild(tostring(segment))
		if not current then
			return nil
		end
	end

	return current
end

local function getConfigValue(modelConfig, key, fallback)
	if type(modelConfig) == "table" and modelConfig[key] ~= nil then
		return modelConfig[key]
	end

	if CONFIG[key] ~= nil then
		return CONFIG[key]
	end

	return fallback
end

local function getVector3(value, fallback)
	if typeof(value) == "Vector3" then
		return value
	end

	return fallback
end

local function getCFrame(value, fallback)
	if typeof(value) == "CFrame" then
		return value
	end

	return fallback
end

local function getSideSign(modelConfig)
	local side = string.lower(tostring(getConfigValue(modelConfig, "Side", "Back")))
	if side == "front" then
		return -1
	end

	return 1
end

local function getSurfaceOffset(modelConfig)
	return math.max(0, tonumber(getConfigValue(modelConfig, "SurfaceOffset", nil)) or 0.12)
end

local function getAnchorSize(modelConfig, flagPart)
	local configuredSize = getVector3(getConfigValue(modelConfig, "AnchorSize", nil), nil)
	if configuredSize then
		return configuredSize
	end

	local depth = math.max(0.01, tonumber(getConfigValue(modelConfig, "AnchorDepth", nil)) or 0.05)
	return Vector3.new(math.max(flagPart.Size.X * 0.7, 1), math.max(flagPart.Size.Y * 0.3, 1), depth)
end

local function computeAnchorCFrame(flagPart, modelConfig)
	local localZ = getSideSign(modelConfig) * ((flagPart.Size.Z / 2) + getSurfaceOffset(modelConfig))
	local configuredOffset = getCFrame(getConfigValue(modelConfig, "LocalCFrame", nil), CFrame.new())
	return flagPart.CFrame * CFrame.new(0, 0, localZ) * configuredOffset
end

local function setIdentityAttributes(target, player, ownerName, displayText, modelName, enabled, failureReason)
	if not target then
		return
	end

	target:SetAttribute(ENABLED_ATTRIBUTE, enabled == true)
	target:SetAttribute(OWNER_USER_ID_ATTRIBUTE, player and player.UserId or nil)
	target:SetAttribute(OWNER_NAME_ATTRIBUTE, ownerName)
	target:SetAttribute(DISPLAY_TEXT_ATTRIBUTE, displayText)
	target:SetAttribute(OWNER_DISPLAY_TEXT_ATTRIBUTE, displayText)
	target:SetAttribute(CONFIG_KEY_ATTRIBUTE, modelName)
	target:SetAttribute(FAILURE_REASON_ATTRIBUTE, failureReason)
end

local function clearStaleAttributes(instance)
	if not instance then
		return
	end

	for _, attributeName in ipairs(STALE_ATTRIBUTE_NAMES) do
		instance:SetAttribute(attributeName, nil)
	end
end

local function removeStaleSurfaceGuis(parent)
	if not parent then
		return
	end

	for _, child in ipairs(parent:GetChildren()) do
		if child:IsA("SurfaceGui") and STALE_SURFACE_GUI_NAMES[child.Name] then
			child:Destroy()
		end
	end
end

local function cleanupOldRuntime(activeShip, flagPart)
	removeStaleSurfaceGuis(flagPart)
	clearStaleAttributes(activeShip)
	clearStaleAttributes(flagPart)

	local folder = activeShip and activeShip:FindFirstChild(FOLDER_NAME)
	if folder then
		for _, child in ipairs(folder:GetChildren()) do
			if child.Name ~= ANCHOR_NAME and STALE_PART_NAMES[child.Name] then
				child:Destroy()
			end
		end
	end

	local overlay = activeShip and resolvePath(activeShip, { "Ship Mesh", "FlagsCustomizationOverlay" })
	if overlay then
		removeStaleSurfaceGuis(overlay)
		clearStaleAttributes(overlay)
		for _, child in ipairs(overlay:GetChildren()) do
			if child.Name == "ShipSailNameTextureSurfaceAppearance" then
				child:Destroy()
			end
		end
	end
end

local function ensureUniqueFolder(parent, folderName)
	local selectedFolder = nil

	for _, child in ipairs(parent:GetChildren()) do
		if child.Name == folderName then
			if not selectedFolder and child:IsA("Folder") then
				selectedFolder = child
			else
				child:Destroy()
			end
		end
	end

	if selectedFolder then
		return selectedFolder
	end

	local folder = Instance.new("Folder")
	folder.Name = folderName
	folder.Parent = parent
	return folder
end

local function ensureUniqueAnchor(folder)
	local selectedAnchor = nil

	for _, child in ipairs(folder:GetChildren()) do
		if child.Name == ANCHOR_NAME then
			if not selectedAnchor and child:IsA("BasePart") then
				selectedAnchor = child
			else
				child:Destroy()
			end
		end
	end

	if selectedAnchor then
		return selectedAnchor
	end

	local anchor = Instance.new("Part")
	anchor.Name = ANCHOR_NAME
	anchor.Parent = folder
	return anchor
end

local function configureAnchor(anchor, flagPart, modelConfig)
	anchor:SetAttribute(RUNTIME_ATTRIBUTE, true)
	anchor.Transparency = 1
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.CastShadow = false
	anchor.Massless = true
	anchor.Material = Enum.Material.SmoothPlastic
	anchor.Size = getAnchorSize(modelConfig, flagPart)
	anchor.CFrame = computeAnchorCFrame(flagPart, modelConfig)

	local weld = anchor:FindFirstChild(ANCHOR_WELD_NAME)
	if flagPart.Anchored then
		if weld then
			weld:Destroy()
		end
		anchor.Anchored = true
		return
	end

	anchor.Anchored = false
	if weld and not weld:IsA("WeldConstraint") then
		weld:Destroy()
		weld = nil
	end
	if not weld then
		weld = Instance.new("WeldConstraint")
		weld.Name = ANCHOR_WELD_NAME
		weld.Parent = anchor
	end
	weld.Part0 = anchor
	weld.Part1 = flagPart
end

local function resolveFlagTarget(activeShip, modelConfig)
	return resolvePath(activeShip, modelConfig.FlagPath or modelConfig.TargetPath or modelConfig.Path)
end

local function formatOwnerDisplayText(ownerName)
	ownerName = trim(ownerName) or "Player"
	if string.sub(ownerName, -2) == "'s" or string.sub(ownerName, -2) == "'S" then
		return ownerName
	end

	return ownerName .. "'s"
end

function ShipSailNameService.ResolveDisplayName(player)
	if not player then
		return "Player"
	end

	local attributeNames = CONFIG.DisplayNameAttributes
	if type(attributeNames) == "table" then
		for _, attributeName in ipairs(attributeNames) do
			local displayName = trim(player:GetAttribute(tostring(attributeName)))
			if displayName then
				local filtered = filterBroadcastDisplayText(player, displayName)
				if filtered then
					return clampDisplayText(filtered)
				end
			end
		end
	end

	local displayName = trim(player.DisplayName)
	if displayName then
		return clampDisplayText(displayName)
	end

	return trim(player.Name) or "Player"
end

function ShipSailNameService.FindFlagTarget(activeShip, visual)
	if not activeShip then
		return nil, nil, "missingShip"
	end

	local candidates = getModelNameCandidates(activeShip, visual)
	local firstCandidate = candidates[1]

	for _, modelName in ipairs(candidates) do
		local modelConfig = MODEL_CONFIGS[modelName]
		if modelConfig then
			if CONFIG.Enabled == false or modelConfig.Enabled == false then
				return nil, modelName, "disabled", modelConfig
			end

			local target = resolveFlagTarget(activeShip, modelConfig)
			if not target then
				return nil, modelName, "missingTarget", modelConfig
			end

			if not target:IsA("BasePart") then
				return nil, modelName, "targetNotBasePart", modelConfig
			end

			return target, modelName, nil, modelConfig
		end
	end

	return nil, firstCandidate, "missingModelConfig"
end

function ShipSailNameService.Apply(player, activeShip, visual)
	local resolvedDisplayName = ShipSailNameService.ResolveDisplayName(player)
	local ownerName = trim(player and player.Name) or resolvedDisplayName
	local displayText = formatOwnerDisplayText(ownerName)
	local flagPart, modelName, reason, modelConfig = ShipSailNameService.FindFlagTarget(activeShip, visual)

	if not flagPart then
		setIdentityAttributes(activeShip, player, ownerName, displayText, modelName, false, reason)
		warnOnce(
			string.format("%s:%s", tostring(modelName), tostring(reason)),
			"[ShipSailNameService] Could not apply sail identity for %s (%s).",
			tostring(modelName or activeShip),
			tostring(reason)
		)
		return false, reason
	end

	cleanupOldRuntime(activeShip, flagPart)

	local folder = ensureUniqueFolder(activeShip, FOLDER_NAME)
	folder:SetAttribute(RUNTIME_ATTRIBUTE, true)

	local anchor = ensureUniqueAnchor(folder)
	configureAnchor(anchor, flagPart, modelConfig)

	removeStaleSurfaceGuis(anchor)
	setIdentityAttributes(activeShip, player, ownerName, displayText, modelName, true, nil)
	setIdentityAttributes(flagPart, player, ownerName, displayText, modelName, true, nil)
	setIdentityAttributes(anchor, player, ownerName, displayText, modelName, true, nil)

	return true, anchor
end

return ShipSailNameService
