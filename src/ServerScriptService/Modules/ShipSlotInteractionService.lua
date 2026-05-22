local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local PlotUpgradeConfig = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("PlotUpgrade"))
local ShipSlotGuiIdentity = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("ShipSlotGuiIdentity"))
local ShipVisuals = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("ShipVisuals"))
local ShipSlotService = require(ServerScriptService.Modules:WaitForChild("ShipSlotService"))

local ShipSlotInteractionService = {}

local RUNTIME_GUI_ATTRIBUTE = ShipSlotGuiIdentity.RuntimeGuiAttribute
local RUNTIME_GUI_SLOT_ATTRIBUTE = ShipSlotGuiIdentity.SlotNumberAttribute
local RUNTIME_GUI_SHIP_ATTRIBUTE = "ShipSlotRuntimeShip"

local SLOT_ATTRIBUTES = {
	Visible = "ShipSlotVisible",
	Usable = "ShipSlotUsable",
	Locked = "ShipSlotLocked",
	Role = "ShipSlotRole",
	BonusPercent = "ShipSlotBonusPercent",
	UnlockLevel = "ShipSlotUnlockLevel",
}

local CAPTAIN_ATTRIBUTES = {
	IsCaptainSlot = "ShipCaptainSlot",
	Unlocked = "ShipCaptainSlotUnlocked",
	State = "ShipCaptainState",
	BonusPercent = "ShipCaptainBonusPercent",
	BonusLabel = "ShipCaptainBonusLabel",
}

local playerState = {}
local warned = {}

local function warnOnce(key, message, ...)
	if warned[key] then
		return
	end

	warned[key] = true
	warn(string.format(message, ...))
end

local function normalizeSlotName(slotName)
	local numeric = tonumber(slotName)
	if not numeric then
		return nil
	end

	numeric = math.floor(numeric)
	if numeric < 1 then
		return nil
	end

	return tostring(numeric)
end

local function getPlayerGui(player)
	return player and player:FindFirstChild("PlayerGui") or nil
end

local function getPlayerUpgradeLevel(player, override)
	if override ~= nil then
		return PlotUpgradeConfig.ClampLevel(override)
	end

	local hiddenLeaderstats = player and player:FindFirstChild("HiddenLeaderstats")
	local valueObject = hiddenLeaderstats and hiddenLeaderstats:FindFirstChild(PlotUpgradeConfig.InternalStatName or "PlotUpgrade")
	if valueObject and valueObject:IsA("ValueBase") then
		return PlotUpgradeConfig.ClampLevel(valueObject.Value)
	end

	return 0
end

local function getPlayerRebirthCount(player)
	local leaderstats = player and player:FindFirstChild("leaderstats")
	local valueObject = leaderstats and leaderstats:FindFirstChild("Rebirths")
	if valueObject and valueObject:IsA("ValueBase") then
		return math.max(0, math.floor(tonumber(valueObject.Value) or 0))
	end

	return 0
end

local function getState(player)
	local state = playerState[player]
	if not state then
		state = {
			activeShip = nil,
			guisBySlot = {},
		}
		playerState[player] = state
	end

	return state
end

local function isRuntimeGui(instance)
	return instance and instance:IsA("SurfaceGui") and instance:GetAttribute(RUNTIME_GUI_ATTRIBUTE) == true
end

local function destroyGui(gui)
	if gui and gui.Parent then
		gui:Destroy()
	end
end

local function cleanupRuntimeGuiBySlot(player, slotName, keepGui)
	local state = playerState[player]
	if state and state.guisBySlot[slotName] and state.guisBySlot[slotName] ~= keepGui then
		destroyGui(state.guisBySlot[slotName])
		state.guisBySlot[slotName] = nil
	end

	local playerGui = getPlayerGui(player)
	if not playerGui then
		return
	end

	for _, child in ipairs(playerGui:GetChildren()) do
		if
			child:IsA("SurfaceGui")
			and isRuntimeGui(child)
			and ShipSlotGuiIdentity.GetSlotKeyFromGui(child) == slotName
			and child ~= keepGui
		then
			destroyGui(child)
		end
	end
end

local function cleanupAllRuntimeGuis(player)
	local state = playerState[player]
	if state then
		for slotName, gui in pairs(state.guisBySlot) do
			destroyGui(gui)
			state.guisBySlot[slotName] = nil
		end
	end

	local playerGui = getPlayerGui(player)
	if not playerGui then
		return
	end

	for _, child in ipairs(playerGui:GetChildren()) do
		if isRuntimeGui(child) then
			child:Destroy()
		end
	end
end

local function setSlotAttributes(slotModel, slotName, upgradeLevel, rebirthCount)
	local isVisible = PlotUpgradeConfig.IsStandVisible(upgradeLevel, slotName, rebirthCount)
	local isUsable = PlotUpgradeConfig.IsStandUsable(upgradeLevel, slotName, rebirthCount)
	local unlockLevel = PlotUpgradeConfig.GetStandUnlockLevel(slotName)

	slotModel:SetAttribute(SLOT_ATTRIBUTES.Visible, isVisible)
	slotModel:SetAttribute(SLOT_ATTRIBUTES.Usable, isUsable)
	slotModel:SetAttribute(SLOT_ATTRIBUTES.Locked, isVisible and not isUsable)
	slotModel:SetAttribute(SLOT_ATTRIBUTES.Role, "")
	slotModel:SetAttribute(SLOT_ATTRIBUTES.BonusPercent, 0)
	slotModel:SetAttribute(SLOT_ATTRIBUTES.UnlockLevel, unlockLevel)

	return {
		Visible = isVisible,
		Usable = isUsable,
		Locked = isVisible and not isUsable,
	}
end

local function getHandlePrompt(handle)
	if not handle or not handle:IsA("BasePart") then
		return nil
	end

	return handle:FindFirstChildOfClass("ProximityPrompt")
end

local function getClaimHitBox(slotModel)
	return ShipSlotService.GetClaimHitBox(slotModel)
end

local function getLevelUpPart(slotModel)
	local levelUp = slotModel:FindFirstChild("LevelUp", true)
	if levelUp and levelUp:IsA("BasePart") then
		return levelUp
	end

	return nil
end

local function setSlotInteractionEnabled(slotModel, handle, slotState)
	local enabled = slotState.Usable == true
	local prompt = getHandlePrompt(handle)
	if prompt then
		prompt.Enabled = enabled
	elseif enabled then
		warnOnce(
			"missing_prompt_" .. slotModel:GetFullName(),
			"[ShipSlotInteractionService] Usable ship slot is missing a Handle ProximityPrompt: %s",
			slotModel:GetFullName()
		)
	end

	local hitBox = getClaimHitBox(slotModel)
	if hitBox then
		hitBox.CanTouch = enabled
	elseif enabled then
		warnOnce(
			"missing_hitbox_" .. slotModel:GetFullName(),
			"[ShipSlotInteractionService] Usable ship slot is missing a claim collection hitbox: %s",
			slotModel:GetFullName()
		)
	end

	local levelUpPart = getLevelUpPart(slotModel)
	if levelUpPart then
		local clickDetector = levelUpPart:FindFirstChildOfClass("ClickDetector")
		if clickDetector then
			clickDetector.MaxActivationDistance = if enabled then 15 else 0
		end
	elseif enabled then
		warnOnce(
			"missing_levelup_" .. slotModel:GetFullName(),
			"[ShipSlotInteractionService] Usable ship slot is missing LevelUp part: %s",
			slotModel:GetFullName()
		)
	end
end

local function tagRuntimeGui(gui, player, activeShip, slotName)
	gui.Name = ShipSlotGuiIdentity.GetRuntimeGuiName(slotName) or ("ShipSlotLevelUp_" .. slotName)
	gui.ResetOnSpawn = false
	gui:SetAttribute(RUNTIME_GUI_ATTRIBUTE, true)
	gui:SetAttribute(RUNTIME_GUI_SLOT_ATTRIBUTE, slotName)
	gui:SetAttribute(RUNTIME_GUI_SHIP_ATTRIBUTE, activeShip:GetFullName())
	gui:SetAttribute("OwnerUserId", player.UserId)
end

local function getExistingRuntimeGui(player, activeShip, slotName, levelUpPart)
	local state = getState(player)
	local gui = state.guisBySlot[slotName]
	if
		gui
		and gui.Parent == getPlayerGui(player)
		and isRuntimeGui(gui)
		and gui.Adornee == levelUpPart
		and gui:GetAttribute(RUNTIME_GUI_SHIP_ATTRIBUTE) == activeShip:GetFullName()
	then
		return gui
	end

	return nil
end

local function setupLevelUpSurfaceGui(player, activeShip, slotModel, slotName, slotState)
	if slotState.Usable ~= true then
		local levelUpPart = getLevelUpPart(slotModel)
		local sourceGui = levelUpPart and levelUpPart:FindFirstChildOfClass("SurfaceGui")
		if sourceGui then
			sourceGui.Enabled = false
		end

		cleanupRuntimeGuiBySlot(player, slotName)
		return
	end

	local playerGui = getPlayerGui(player)
	if not playerGui then
		warnOnce(
			"missing_player_gui_" .. tostring(player.UserId),
			"[ShipSlotInteractionService] PlayerGui missing while setting up ship slot UI for %s.",
			player.Name
		)
		return
	end

	local levelUpPart = getLevelUpPart(slotModel)
	if not levelUpPart then
		return
	end

	local existingGui = getExistingRuntimeGui(player, activeShip, slotName, levelUpPart)
	if existingGui then
		cleanupRuntimeGuiBySlot(player, slotName, existingGui)
		return
	end

	cleanupRuntimeGuiBySlot(player, slotName)

	local sourceGui = levelUpPart:FindFirstChildOfClass("SurfaceGui")
	if not sourceGui then
		warnOnce(
			"missing_surface_gui_" .. slotModel:GetFullName(),
			"[ShipSlotInteractionService] Ship slot LevelUp part is missing SurfaceGui: %s",
			slotModel:GetFullName()
		)
		return
	end

	local surfaceGui = sourceGui:Clone()
	sourceGui.Enabled = false
	surfaceGui.Adornee = levelUpPart
	surfaceGui.Enabled = false
	tagRuntimeGui(surfaceGui, player, activeShip, slotName)
	surfaceGui.Parent = playerGui

	local state = getState(player)
	state.guisBySlot[slotName] = surfaceGui
end

local function disableInteractionInstance(instance)
	if instance:IsA("ProximityPrompt") or instance:IsA("LayerCollector") then
		instance.Enabled = false
	elseif instance:IsA("ClickDetector") then
		instance.MaxActivationDistance = 0
	elseif ShipSlotService.IsClaimHitBox(instance) then
		instance.CanTouch = false
	end
end

local function disableInteractionDescendants(root)
	if not root then
		return
	end

	disableInteractionInstance(root)
	for _, descendant in ipairs(root:GetDescendants()) do
		disableInteractionInstance(descendant)
	end
end

local function warnForMissingUsableSlots(player, activeShip, upgradeLevel, rebirthCount)
	local effectiveLevel = PlotUpgradeConfig.GetEffectiveLevel(upgradeLevel, rebirthCount)
	local usableCount = ShipVisuals.GetNormalCrewSlotsForUpgradeLevel(effectiveLevel)

	for slotNumber = 1, usableCount do
		local slotName = tostring(slotNumber)
		if not ShipSlotService.GetSlot(activeShip, slotName) then
			warnOnce(
				string.format("missing_usable_slot_%d_%s_%s", player.UserId, tostring(activeShip:GetAttribute("ActiveShipModelName")), slotName),
				"[ShipSlotInteractionService] %s is missing usable crew slot %s for PlotUpgrade %d. Saved crew remains intact but cannot be placed physically until the asset has this slot.",
				activeShip:GetFullName(),
				slotName,
				upgradeLevel
			)
		end
	end
end

local function disableNonnumericInteractions(activeShip)
	for _, child in ipairs(activeShip:GetChildren()) do
		if normalizeSlotName(child.Name) then
			continue
		end

		if child.Name == "CrewSlots" then
			continue
		end

		if ShipSlotService.IsCaptainSlotName(child.Name) then
			continue
		end

		if child.Name == tostring((ShipVisuals.RuntimePoints and ShipVisuals.RuntimePoints.FolderName) or "ShipRuntimePoints") then
			continue
		end

		disableInteractionDescendants(child)
	end
end

local function disableExtraNumericSlotInteractions(activeShip, activeSlots)
	for _, slotName in ipairs(ShipSlotService.GetAllSlotNumbers(activeShip)) do
		if activeSlots[slotName] then
			continue
		end

		local slotModel = ShipSlotService.GetSlot(activeShip, slotName)
		if slotModel then
			slotModel:SetAttribute(SLOT_ATTRIBUTES.Visible, false)
			slotModel:SetAttribute(SLOT_ATTRIBUTES.Usable, false)
			slotModel:SetAttribute(SLOT_ATTRIBUTES.Locked, true)
			slotModel:SetAttribute(SLOT_ATTRIBUTES.Role, "extra")
			slotModel:SetAttribute(SLOT_ATTRIBUTES.BonusPercent, 0)
			slotModel:SetAttribute(SLOT_ATTRIBUTES.UnlockLevel, nil)
			disableInteractionDescendants(slotModel)
		end
	end
end

local function setupCaptainSpot(activeShip, upgradeLevel, rebirthCount)
	local effectiveLevel = PlotUpgradeConfig.GetEffectiveLevel(upgradeLevel, rebirthCount)
	local captainInfo = ShipVisuals.GetCaptainSlotInfoForUpgradeLevel(effectiveLevel)
	local captainSpot, handle, prompt = ShipSlotService.GetCaptainSlotPrompt(activeShip)

	activeShip:SetAttribute(CAPTAIN_ATTRIBUTES.Unlocked, captainInfo.Unlocked)
	activeShip:SetAttribute(CAPTAIN_ATTRIBUTES.State, captainInfo.State)
	activeShip:SetAttribute(CAPTAIN_ATTRIBUTES.BonusPercent, captainInfo.BonusPercent)
	activeShip:SetAttribute(CAPTAIN_ATTRIBUTES.BonusLabel, captainInfo.BonusLabel)

	if not captainSpot then
		if captainInfo.Unlocked then
			warnOnce(
				"missing_captain_spot_" .. activeShip:GetFullName(),
				"[ShipSlotInteractionService] Active ship is missing %s for PlotUpgrade %d: %s",
				tostring(ShipVisuals.CaptainSlotName),
				effectiveLevel,
				activeShip:GetFullName()
			)
		end
		return
	end

	captainSpot:SetAttribute(CAPTAIN_ATTRIBUTES.IsCaptainSlot, true)
	captainSpot:SetAttribute(CAPTAIN_ATTRIBUTES.Unlocked, captainInfo.Unlocked)
	captainSpot:SetAttribute(CAPTAIN_ATTRIBUTES.State, captainInfo.State)
	captainSpot:SetAttribute(CAPTAIN_ATTRIBUTES.BonusPercent, captainInfo.BonusPercent)
	captainSpot:SetAttribute(CAPTAIN_ATTRIBUTES.BonusLabel, captainInfo.BonusLabel)
	captainSpot:SetAttribute(SLOT_ATTRIBUTES.Visible, captainInfo.Unlocked)
	captainSpot:SetAttribute(SLOT_ATTRIBUTES.Usable, captainInfo.Unlocked)
	captainSpot:SetAttribute(SLOT_ATTRIBUTES.Locked, not captainInfo.Unlocked)
	captainSpot:SetAttribute(SLOT_ATTRIBUTES.Role, "captain")
	captainSpot:SetAttribute(SLOT_ATTRIBUTES.BonusPercent, captainInfo.BonusPercent)
	captainSpot:SetAttribute(SLOT_ATTRIBUTES.UnlockLevel, nil)

	disableInteractionDescendants(captainSpot)

	if not captainInfo.Unlocked then
		return
	end

	if prompt then
		prompt.Enabled = true
		prompt.ObjectText = "Captain's Spot"
		prompt.ActionText = "Assign Captain"
	elseif handle then
		warnOnce(
			"missing_captain_prompt_" .. captainSpot:GetFullName(),
			"[ShipSlotInteractionService] Unlocked Captain's Spot is missing a Handle ProximityPrompt: %s",
			captainSpot:GetFullName()
		)
	end
end

function ShipSlotInteractionService.RefreshPlayerShip(player, activeShip, options)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return false, "invalid_player"
	end

	if typeof(activeShip) ~= "Instance" or not activeShip:IsA("Model") then
		return false, "invalid_ship"
	end

	options = options or {}

	local state = getState(player)
	if state.activeShip ~= activeShip then
		cleanupAllRuntimeGuis(player)
		state.activeShip = activeShip
	end

	local upgradeLevel = getPlayerUpgradeLevel(player, options.UpgradeLevel)
	local rebirthCount = getPlayerRebirthCount(player)
	local activeSlots = {}
	local slotNumbers = ShipSlotService.GetAvailableSlotNumbers(activeShip)

	disableNonnumericInteractions(activeShip)
	setupCaptainSpot(activeShip, upgradeLevel, rebirthCount)

	if #slotNumbers == 0 then
		warnOnce(
			"no_numeric_slots_" .. activeShip:GetFullName(),
			"[ShipSlotInteractionService] Active ship has no numeric crew slots with Handles: %s",
			activeShip:GetFullName()
		)
	end

	for _, slotName in ipairs(slotNumbers) do
		local slotModel, handle = ShipSlotService.GetSlotHandle(activeShip, slotName)
		if slotModel and slotModel:IsA("Model") then
			activeSlots[slotName] = true

			local slotState = setSlotAttributes(slotModel, slotName, upgradeLevel, rebirthCount)
			setSlotInteractionEnabled(slotModel, handle, slotState)
			setupLevelUpSurfaceGui(player, activeShip, slotModel, slotName, slotState)
		end
	end

	disableExtraNumericSlotInteractions(activeShip, activeSlots)

	for slotName in pairs(state.guisBySlot) do
		if not activeSlots[slotName] then
			cleanupRuntimeGuiBySlot(player, slotName)
		end
	end

	warnForMissingUsableSlots(player, activeShip, upgradeLevel, rebirthCount)

	return true
end

function ShipSlotInteractionService.CleanupPlayer(player)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return
	end

	cleanupAllRuntimeGuis(player)
	playerState[player] = nil
end

Players.PlayerRemoving:Connect(function(player)
	ShipSlotInteractionService.CleanupPlayer(player)
end)

return ShipSlotInteractionService
