local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local Configs = Modules:WaitForChild("Configs")
local ServerCrewModules = Modules:WaitForChild("Server"):WaitForChild("Crew")

local DataManager = require(ServerScriptService:WaitForChild("Data"):WaitForChild("DataManager"))
local AddCrewMember = require(ServerScriptService:WaitForChild("Modules"):WaitForChild("AddCrewMember"))
local CrewInstanceService = require(ServerScriptService:WaitForChild("Modules"):WaitForChild("CrewInstanceService"))
local CrewStandIncomeAuthority = require(ServerScriptService:WaitForChild("Modules"):WaitForChild("CrewStandIncomeAuthority"))
local QuestSignals = require(ServerScriptService:WaitForChild("Modules"):WaitForChild("GrandLineRushQuestSignals"))
local ShipRuntimeSignals = require(ServerScriptService:WaitForChild("Modules"):WaitForChild("ShipRuntimeSignals"))
local CrewInteraction = require(ServerCrewModules:WaitForChild("Interaction"))
local CrewRegistry = require(ServerCrewModules:WaitForChild("Registry"))
local CurrencyUtil = require(Modules:WaitForChild("CurrencyUtil"))
local Economy = require(Configs:WaitForChild("GrandLineRushEconomy"))
local MapResolver = require(Modules:WaitForChild("MapResolver"))
local PopUpModule = require(Modules:WaitForChild("PopUpModule"))
local PlotUpgradeConfig = require(Configs:WaitForChild("PlotUpgrade"))
local SpeedUpgradeConfig = require(Configs:WaitForChild("SpeedUpgrade"))
local TutorialConfig = require(Configs:WaitForChild("FirstTimeTutorial"))

local FirstTimeTutorialService = {}

local INFO_COLOR = Color3.fromRGB(242, 209, 107)
local ERROR_COLOR = Color3.fromRGB(255, 104, 104)
local STROKE_COLOR = Color3.fromRGB(0, 0, 0)
local OBJECTIVE_CHECK_INTERVAL = 0.35
local PUSH_PROGRESS_DELTA = 0.05
local HIDDEN_LEADERSTATS_NAME = "HiddenLeaderstats"
local TUTORIAL_VALUE_NAME = "Tutorial"
local TUTORIAL_STARTER_GRANTED_PATH = "HiddenLeaderstats.TutorialStarterDoubloonsGranted"
local TUTORIAL_CREW_MEMBER_GRANTED_PATH = tostring(
	(TutorialConfig.TutorialCrewMember and TutorialConfig.TutorialCrewMember.GrantedPath)
		or "HiddenLeaderstats.TutorialCrewMemberGranted"
)
local TUTORIAL_SPEED_TOP_UP_GRANTED_PATH = "HiddenLeaderstats.TutorialSpeedTopUpGranted"
local TUTORIAL_OWNER_ATTRIBUTE = "TutorialOwnerUserId"
local TUTORIAL_CREW_MEMBER_ATTRIBUTE = "TutorialCrewMember"
local TUTORIAL_TOKEN_ATTRIBUTE = "TutorialToken"
local TUTORIAL_REWARD_NAME_ATTRIBUTE = "TutorialRewardName"
local CARRIED_CREW_MEMBER_ATTRIBUTE = "CarriedCrewMember"
local CARRIED_CREW_MEMBER_IMAGE_ATTRIBUTE = "CarriedCrewMemberImage"
local TUTORIAL_RUNTIME_ACTIVE_ATTRIBUTE = "FirstTimeTutorialActive"
local TUTORIAL_RUNTIME_STEP_ATTRIBUTE = "FirstTimeTutorialStepId"
local SAVE_FAILURE_MESSAGE = "Tutorial progress could not be saved yet. Try again in a moment."

local started = false
local requestRemote
local stateRemote
local heartbeatConnection
local questSignalConnection
local sessions = {}
local playerConnections = {}
local objectiveCheckAccumulator = 0
local registryEntries = nil

local cleanupTutorialTarget

local function hasCarriedCrewMember(player)
	local carried = player:GetAttribute(CARRIED_CREW_MEMBER_ATTRIBUTE)
	return typeof(carried) == "string" and carried ~= ""
end

local function clearCarriedCrewMemberAttributes(player)
	player:SetAttribute(CARRIED_CREW_MEMBER_ATTRIBUTE, nil)
	player:SetAttribute(CARRIED_CREW_MEMBER_IMAGE_ATTRIBUTE, nil)
end

local function clearTutorialRuntimeAttributes(player)
	player:SetAttribute(TUTORIAL_RUNTIME_ACTIVE_ATTRIBUTE, nil)
	player:SetAttribute(TUTORIAL_RUNTIME_STEP_ATTRIBUTE, nil)
end

local function setTutorialRuntimeAttributes(player, session, step)
	if session and session.active == true and typeof(step) == "table" then
		player:SetAttribute(TUTORIAL_RUNTIME_ACTIVE_ATTRIBUTE, true)
		player:SetAttribute(TUTORIAL_RUNTIME_STEP_ATTRIBUTE, tostring(step.Id or ""))
	else
		clearTutorialRuntimeAttributes(player)
	end
end

-- Client-advanceable steps must be explicitly registered here. This keeps
-- future gameplay/objective steps from becoming skippable by config alone.
local StepHandlers = {
	welcome = {
		AllowClientAdvance = true,
	},
	move = {
		AllowClientAdvance = false,
	},
	pickup_crew_member = {
		AllowClientAdvance = false,
	},
	extract_crew_member = {
		AllowClientAdvance = false,
	},
	place_on_stand = {
		AllowClientAdvance = false,
	},
	collect_beli = {
		AllowClientAdvance = false,
	},
	buy_speed = {
		AllowClientAdvance = false,
	},
	final_guidance = {
		AllowClientAdvance = true,
	},
}

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
	local remotes = getOrCreateRemotesFolder()
	requestRemote = getOrCreateRemote(remotes, "RemoteFunction", TutorialConfig.Remotes.RequestName)
	stateRemote = getOrCreateRemote(remotes, "RemoteEvent", TutorialConfig.Remotes.StateName)
end

local function disconnectPlayer(player)
	if cleanupTutorialTarget then
		cleanupTutorialTarget(player, sessions[player])
	end
	clearTutorialRuntimeAttributes(player)

	local bucket = playerConnections[player]
	if bucket then
		for _, connection in ipairs(bucket) do
			connection:Disconnect()
		end
	end

	playerConnections[player] = nil
	sessions[player] = nil
end

local function getTutorialValueObject(player)
	local hiddenLeaderstats = player:FindFirstChild(HIDDEN_LEADERSTATS_NAME)
	if not hiddenLeaderstats then
		return nil
	end

	return hiddenLeaderstats:FindFirstChild(TUTORIAL_VALUE_NAME)
end

local function isTutorialCompleted(player)
	local value, reason = DataManager:TryGetValue(player, TutorialConfig.CompletionPath)
	if reason == nil and typeof(value) == "boolean" then
		return value
	end

	local tutorialValue = getTutorialValueObject(player)
	return tutorialValue ~= nil and tutorialValue:IsA("BoolValue") and tutorialValue.Value == true
end

local function getRootPosition(player)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root.Position
	end

	return nil
end

local function getNumberValue(player, folderName, valueName)
	local folder = player:FindFirstChild(folderName)
	local value = folder and folder:FindFirstChild(valueName)
	if value and value:IsA("ValueBase") and typeof(value.Value) == "number" then
		return value.Value
	end

	return nil
end

local function getDataNumber(player, path, fallback)
	local value, reason = DataManager:TryGetValue(player, path)
	if reason == nil and typeof(value) == "number" then
		return value
	end

	return fallback
end

local function getPlayerShipUpgradeLevel(player)
	local hiddenLeaderstats = player:FindFirstChild(HIDDEN_LEADERSTATS_NAME)
	local valueObject = hiddenLeaderstats and hiddenLeaderstats:FindFirstChild("PlotUpgrade")
	if valueObject and valueObject:IsA("NumberValue") then
		return PlotUpgradeConfig.ClampLevel(valueObject.Value)
	end

	local storedLevel = getDataNumber(player, "HiddenLeaderstats.PlotUpgrade", 0)
	return PlotUpgradeConfig.ClampLevel(storedLevel)
end

local function getPlayerRebirthCount(player)
	local leaderstats = player:FindFirstChild("leaderstats")
	local valueObject = leaderstats and leaderstats:FindFirstChild("Rebirths")
	if valueObject and valueObject:IsA("NumberValue") then
		return math.max(0, math.floor(tonumber(valueObject.Value) or 0))
	end

	return math.max(0, math.floor(tonumber(getDataNumber(player, "leaderstats.Rebirths", 0)) or 0))
end

local function getPrimaryBalance(player)
	local dataValue = getDataNumber(player, CurrencyUtil.getPrimaryPath(), nil)
	if typeof(dataValue) == "number" then
		return dataValue
	end

	local valueObject = CurrencyUtil.findPrimaryValueObject(player)
	if valueObject then
		return valueObject.Value
	end

	return 0
end

local function getSpeedValue(player)
	local objectValue = getNumberValue(player, HIDDEN_LEADERSTATS_NAME, "Speed")
	if typeof(objectValue) == "number" then
		return objectValue
	end

	return getDataNumber(player, "HiddenLeaderstats.Speed", 1) or 1
end

local function getCurrentSpeedUpgradeCost(player)
	local cfg = SpeedUpgradeConfig[1]
	if typeof(cfg) ~= "table" then
		return 200
	end

	local starter = tonumber(cfg.Starter_Price) or 0
	local multiplier = tonumber(cfg.Price_Mult) or 1
	local addSpeed = math.max(1, math.floor(tonumber(cfg.AddSpeed) or 1))
	local speedValue = math.max(1, tonumber(getSpeedValue(player)) or 1)
	local level = math.max(speedValue - 1, 0)

	local total = 0
	for index = 0, addSpeed - 1 do
		total += starter * (multiplier ^ (level + index))
	end

	return math.floor(total + 0.5)
end

local function ensureTutorialStarterDoubloons(player)
	local granted, reason = DataManager:TryGetValue(player, TUTORIAL_STARTER_GRANTED_PATH)
	if reason ~= nil or granted == true then
		return
	end

	local tutorialAmount = math.max(0, math.floor(tonumber(Economy.Tutorial and Economy.Tutorial.StartingDoubloons) or 0))
	if tutorialAmount > 0 then
		local shortfall = math.max(0, tutorialAmount - getPrimaryBalance(player))
		if shortfall > 0 then
			local added = DataManager:TryAddValue(player, CurrencyUtil.getPrimaryPath(), shortfall)
			if added ~= true then
				return
			end
			DataManager:TryAddValue(player, CurrencyUtil.getTotalPath(), shortfall)
		end
	end

	DataManager:TrySetValue(player, TUTORIAL_STARTER_GRANTED_PATH, true)
end

local function canRecoverSpeedUpgradePurchase(player)
	local cost = getCurrentSpeedUpgradeCost(player)
	local shortfall = math.max(0, cost - getPrimaryBalance(player))
	if shortfall <= 0 then
		return true
	end
	if isTutorialCompleted(player) or getSpeedValue(player) > 1 then
		return false
	end

	local granted, reason = DataManager:TryGetValue(player, TUTORIAL_SPEED_TOP_UP_GRANTED_PATH)
	return reason == nil and granted ~= true
end

local function getTutorialCrewMemberGranted(player)
	local granted, reason = DataManager:TryGetValue(player, TUTORIAL_CREW_MEMBER_GRANTED_PATH)
	return reason == nil and granted == true
end

local function countCrewMemberInstances(player)
	local crewInventory = CrewInstanceService.GetCrewInventory(player)
	if typeof(crewInventory) ~= "table" or typeof(crewInventory.ById) ~= "table" then
		return 0
	end

	local count = 0
	for _, instanceData in pairs(crewInventory.ById) do
		if typeof(instanceData) == "table" and tostring(instanceData.StorageName or "") ~= "" then
			count += 1
		end
	end

	return count
end

local function getCrewInventoryCount(player)
	return countCrewMemberInstances(player)
end

local function getTutorialRewardInstance(player, requireAssigned)
	return CrewInstanceService.FindTutorialRewardInstance(player, {
		RequireAssigned = requireAssigned == true,
	})
end

local function hasTutorialReward(player, _session)
	local _, instanceData = getTutorialRewardInstance(player, false)
	return instanceData ~= nil
end

local function getSessionPlacedTutorialStandName(player, session)
	if not session then
		return ""
	end

	local standName = tostring(session.placedTutorialStandName or "")
	if standName == "" then
		return ""
	end

	local standData = CrewStandIncomeAuthority.GetStandData(player, standName)
	local expectedInstanceId = tostring(session.placedTutorialInstanceId or "")
	if typeof(standData) == "table" and tostring(standData.CrewMemberName or "") ~= "" then
		if expectedInstanceId == "" or tostring(standData.CrewMemberInstanceId or "") == expectedInstanceId then
			return standName
		end
	end

	if expectedInstanceId == "" then
		return ""
	end

	for candidateStandName, candidateStandData in pairs(CrewStandIncomeAuthority.GetAllStandData(player)) do
		if
			typeof(candidateStandData) == "table"
			and tostring(candidateStandData.CrewMemberName or "") ~= ""
			and tostring(candidateStandData.CrewMemberInstanceId or "") == expectedInstanceId
		then
			local resolvedStandName = tostring(candidateStandName)
			session.placedTutorialStandName = resolvedStandName
			return resolvedStandName
		end
	end

	return ""
end

local function getPlacedTutorialStandName(player, session)
	local sessionStandName = getSessionPlacedTutorialStandName(player, session)
	if sessionStandName ~= "" then
		return sessionStandName
	end

	local instanceId, instanceData = getTutorialRewardInstance(player, true)
	if instanceData and tostring(instanceData.AssignedStand or "") ~= "" then
		local standName = tostring(instanceData.AssignedStand)
		if session then
			session.placedTutorialStandName = standName
			session.placedTutorialInstanceId = tostring(instanceId or "")
		end
		return standName
	end

	for standName, standData in pairs(CrewStandIncomeAuthority.GetAllStandData(player)) do
		standData = CrewStandIncomeAuthority.GetStandData(player, standName)
		if typeof(standData) == "table" then
			local standInstanceId = tostring(standData.CrewMemberInstanceId or "")
			if standInstanceId ~= "" and instanceId ~= nil and standInstanceId == instanceId then
				return tostring(standName)
			end
		end
	end

	return ""
end

local function hasPlacedTutorialCrewMember(player, session)
	return getPlacedTutorialStandName(player, session) ~= ""
end

local function isTutorialCrewMemberOnStand(player, session, standName)
	standName = tostring(standName or "")
	if standName == "" then
		return false
	end

	return getPlacedTutorialStandName(player, session) == standName
end

local function getBankedTutorialStandIncome(player, session)
	local standName = getPlacedTutorialStandName(player, session)
	if standName == "" then
		return 0
	end

	local standData = CrewStandIncomeAuthority.GetStandData(player, standName)
	if typeof(standData) ~= "table" then
		return 0
	end

	return math.max(0, tonumber(standData.IncomeToCollect) or 0)
end

local function getHeldCrewMemberModel(player)
	local context = CrewInteraction.GetActiveContext()
	if not context or typeof(context.HeldByUserId) ~= "table" then
		return nil
	end

	return context.HeldByUserId[player.UserId]
end

local function isTutorialTargetModelForSession(player, session, model)
	if not model or not model.Parent then
		return false
	end
	if model:GetAttribute(TUTORIAL_CREW_MEMBER_ATTRIBUTE) ~= true then
		return false
	end
	if model:GetAttribute(TUTORIAL_OWNER_ATTRIBUTE) ~= player.UserId then
		return false
	end

	local sessionToken = session and tostring(session.tutorialToken or "") or ""
	local modelToken = tostring(model:GetAttribute(TUTORIAL_TOKEN_ATTRIBUTE) or "")
	return sessionToken ~= "" and modelToken == sessionToken
end

local function destroyTutorialTargetModel(player, model)
	if not model then
		return false
	end

	local removed = model.Parent ~= nil
	local wasHeldByPlayer = false
	local context = CrewInteraction.GetActiveContext()
	if context then
		local activeState = nil
		if typeof(context.Active) == "table" then
			activeState = context.Active[model]
			context.Active[model] = nil
			if activeState ~= nil then
				removed = true
			end
		end
		if typeof(context.HeldByUserId) == "table" and context.HeldByUserId[player.UserId] == model then
			context.HeldByUserId[player.UserId] = nil
			wasHeldByPlayer = true
			removed = true
		end
		if activeState and activeState.OriginData and activeState.SlotIndex then
			local originData = activeState.OriginData
			local slotIndex = activeState.SlotIndex
			if originData.SlotOccupied and originData.SlotOccupied[slotIndex] == model then
				originData.SlotOccupied[slotIndex] = nil
			end
			if originData.SlotOffsets then
				originData.SlotOffsets[slotIndex] = nil
			end
		end
	end

	if wasHeldByPlayer then
		clearCarriedCrewMemberAttributes(player)
	end

	if model and model.Parent then
		pcall(function()
			model:Destroy()
		end)
	end

	return removed
end

local function isHoldingTutorialTarget(player, session)
	return isTutorialTargetModelForSession(player, session, getHeldCrewMemberModel(player))
end

cleanupTutorialTarget = function(player, session)
	session = session or sessions[player]
	if not session or not session.tutorialCrewMemberModel then
		return false
	end

	local model = session.tutorialCrewMemberModel
	session.tutorialCrewMemberModel = nil
	return destroyTutorialTargetModel(player, model)
end

local function cleanupTutorialWorldTargets(player, session)
	local removedCount = 0
	if cleanupTutorialTarget(player, session) then
		removedCount += 1
	end

	local heldModel = getHeldCrewMemberModel(player)
	if
		heldModel
		and heldModel:GetAttribute(TUTORIAL_CREW_MEMBER_ATTRIBUTE) == true
		and heldModel:GetAttribute(TUTORIAL_OWNER_ATTRIBUTE) == player.UserId
	then
		if destroyTutorialTargetModel(player, heldModel) then
			removedCount += 1
		end
	end

	for _, instance in ipairs(Workspace:GetDescendants()) do
		if
			instance:IsA("Model")
			and instance:GetAttribute(TUTORIAL_CREW_MEMBER_ATTRIBUTE) == true
			and instance:GetAttribute(TUTORIAL_OWNER_ATTRIBUTE) == player.UserId
		then
			if destroyTutorialTargetModel(player, instance) then
				removedCount += 1
			end
		end
	end

	return removedCount
end

local function ensureCrewRegistry()
	if CrewRegistry._Built == true and registryEntries ~= nil then
		return true
	end

	local success, entriesOrReason = pcall(function()
		local entries = CrewRegistry.Build()
		return entries
	end)

	if not success then
		warn(string.format("[FirstTimeTutorialService] Could not build crew registry: %s", tostring(entriesOrReason)))
		return false
	end

	registryEntries = entriesOrReason
	if #registryEntries <= 0 then
		return false
	end
	return true
end

local function getTutorialCrewMemberEntry()
	if not ensureCrewRegistry() then
		return nil
	end

	local crewConfig = TutorialConfig.TutorialCrewMember or {}
	local preferredName = tostring(crewConfig.Name or "")
	if preferredName ~= "" then
		local template, usedVariant = CrewRegistry.GetTemplateWithFallback(preferredName, "Normal")
		usedVariant = usedVariant or "Normal"
		local info = CrewRegistry.GetOrBuildVariantInfo(preferredName, usedVariant)
		if template and info then
			return {
				BaseId = preferredName,
				FinalId = CrewRegistry.MakeVariantId(preferredName, usedVariant),
				Info = info,
				Rarity = tostring(info.Rarity or "Common"),
				Template = template,
				Variant = usedVariant,
			}
		end
	end

	for _, entry in ipairs(registryEntries or {}) do
		if entry.Template and entry.Info then
			return {
				BaseId = tostring(entry.Id),
				FinalId = tostring(entry.Id),
				Info = entry.Info,
				Rarity = tostring(entry.Rarity or entry.Info.Rarity or "Common"),
				Template = entry.Template,
				Variant = "Normal",
			}
		end
	end

	return nil
end

local function addUniqueName(list, seen, value)
	value = tostring(value or "")
	if value == "" or seen[value] == true then
		return
	end

	seen[value] = true
	table.insert(list, value)
end

local function getTutorialRewardStorageNames(session, extraNames)
	local names = {}
	local seen = {}
	local crewConfig = TutorialConfig.TutorialCrewMember or {}
	addUniqueName(names, seen, crewConfig.Name)

	if session then
		addUniqueName(names, seen, session.tutorialCrewMemberName)
	end

	local entry = getTutorialCrewMemberEntry()
	if entry then
		addUniqueName(names, seen, entry.BaseId)
		addUniqueName(names, seen, entry.FinalId)
	end

	if typeof(extraNames) == "table" then
		for _, name in ipairs(extraNames) do
			addUniqueName(names, seen, name)
		end
	end

	return names
end

local function getToolStorageName(tool)
	if not tool or not tool:IsA("Tool") then
		return ""
	end

	local canonical = tool:GetAttribute("InvItem") or tool:GetAttribute("InventoryItemName")
	if typeof(canonical) == "string" and canonical ~= "" then
		return canonical
	end

	return tostring(tool.Name or "")
end

local function getReplicatedInventoryQuantity(player, storageName)
	storageName = tostring(storageName or "")
	if storageName == "" then
		return 0
	end

	local inventory = CrewInstanceService.GetCrewInventory(player)
	if typeof(inventory) == "table" and typeof(inventory.ById) == "table" then
		local count = 0
		for _, instanceData in pairs(inventory.ById) do
			if typeof(instanceData) == "table"
				and tostring(instanceData.StorageName or "") == storageName
				and tostring(instanceData.AssignedStand or "") == ""
			then
				count += 1
			end
		end
		return count
	end

	return 0
end

local function removeStaleTutorialTools(player, tutorialStorageNames)
	if typeof(tutorialStorageNames) ~= "table" or #tutorialStorageNames <= 0 then
		return 0
	end

	local tutorialNameSet = {}
	for _, storageName in ipairs(tutorialStorageNames) do
		storageName = tostring(storageName or "")
		if storageName ~= "" then
			tutorialNameSet[storageName] = true
		end
	end

	local toolsByStorageName = {}
	local function collectTools(container)
		if not container then
			return
		end

		for _, child in ipairs(container:GetChildren()) do
			if child:IsA("Tool") then
				local storageName = getToolStorageName(child)
				if tutorialNameSet[storageName] == true then
					toolsByStorageName[storageName] = toolsByStorageName[storageName] or {}
					table.insert(toolsByStorageName[storageName], child)
				end
			end
		end
	end

	collectTools(player.Character)
	collectTools(player:FindFirstChildOfClass("Backpack") or player:FindFirstChild("Backpack"))

	local removedCount = 0
	for storageName, tools in pairs(toolsByStorageName) do
		local desiredCount = getReplicatedInventoryQuantity(player, storageName)
		local excessCount = math.max(0, #tools - desiredCount)
		if desiredCount <= 0 then
			excessCount = #tools
		end

		for index = 1, excessCount do
			local tool = tools[index]
			if tool and tool.Parent then
				tool:Destroy()
				removedCount += 1
			end
		end
	end

	return removedCount
end

local function restoreGrantedTutorialReward(player, session)
	if isTutorialCompleted(player) or hasTutorialReward(player, session) then
		return true, nil
	end
	if not getTutorialCrewMemberGranted(player) then
		return false, nil
	end

	local entry = getTutorialCrewMemberEntry()
	if not entry then
		return false, "Tutorial Crewmate reward is not available."
	end

	session.tutorialCrewMemberName = entry.FinalId
	if tostring(session.tutorialToken or "") == "" then
		session.tutorialToken = HttpService:GenerateGUID(false)
	end

	local added = AddCrewMember:AddCrewMember(player, entry.FinalId, 1, {
		TutorialReward = true,
		TutorialRecovery = true,
		TutorialToken = tostring(session.tutorialToken or ""),
	})
	if added == true then
		return true, nil
	end

	return false, "Tutorial Crewmate reward could not be restored yet."
end

local function reconcileTutorialCrewMemberGrant(player, session)
	if hasTutorialReward(player, session) and not getTutorialCrewMemberGranted(player) then
		DataManager:TrySetValue(player, TUTORIAL_CREW_MEMBER_GRANTED_PATH, true)
	end
end

local function reconcileTutorialSpeedRecovery(player)
	local granted, reason = DataManager:TryGetValue(player, TUTORIAL_SPEED_TOP_UP_GRANTED_PATH)
	if reason == nil and granted == true and not isTutorialCompleted(player) and getSpeedValue(player) <= 1 then
		DataManager:TrySetValue(player, TUTORIAL_SPEED_TOP_UP_GRANTED_PATH, false)
	end
end

local function getInstanceWorldPosition(instance)
	if not instance or not instance.Parent then
		return nil
	end

	if instance:IsA("BasePart") then
		return instance.Position
	end

	if instance:IsA("Model") then
		local primaryPart = instance.PrimaryPart
		if primaryPart and primaryPart:IsA("BasePart") then
			return primaryPart.Position
		end

		local part = instance:FindFirstChildWhichIsA("BasePart", true)
		if part then
			return part.Position
		end

		return instance:GetPivot().Position
	end

	local part = instance:FindFirstChildWhichIsA("BasePart", true)
	if part then
		return part.Position
	end

	return nil
end

local function getTutorialExtractionPart(refs)
	refs = refs or MapResolver.GetRefs({
		context = "FirstTimeTutorialService",
	})

	return refs.HitBox
		or refs.ExtractionTouchPart
		or refs.ExtractionTouch
		or refs.ExtractionZone
		or refs.WaveEnd
end

local function spawnTutorialCrewMemberTarget(player, session)
	local context = CrewInteraction.GetActiveContext()
	if not context or typeof(context.Active) ~= "table" then
		return false, "World rewards are still loading."
	end
	if hasTutorialReward(player, session) then
		reconcileTutorialCrewMemberGrant(player, session)
		return true, nil
	end
	if getTutorialCrewMemberGranted(player) then
		local restored, restoreMessage = restoreGrantedTutorialReward(player, session)
		if restored then
			return true, nil
		end

		return false, restoreMessage or "Tutorial Crewmate reward is being restored."
	end

	local entry = getTutorialCrewMemberEntry()
	if not entry then
		return false, "Tutorial Crewmate is not available."
	end
	session.tutorialCrewMemberName = entry.FinalId
	if tostring(session.tutorialToken or "") == "" then
		session.tutorialToken = HttpService:GenerateGUID(false)
	end

	if typeof(context.SpawnTutorialCrewMember) ~= "function" then
		return false, "Biome 1 Crewmate spawns are still loading."
	end

	local lifetime = math.max(60, tonumber(TutorialConfig.TutorialCrewMember and TutorialConfig.TutorialCrewMember.SpawnLifetime) or 900)
	local clone, message = context.SpawnTutorialCrewMember({
		Player = player,
		Entry = {
			FinalId = entry.FinalId,
			Id = entry.FinalId,
			Info = entry.Info,
			Template = entry.Template,
			Rarity = entry.Rarity,
			Tier = 1,
			Foot = 0,
			BaseId = entry.BaseId,
			Variant = entry.Variant,
		},
		Token = tostring(session.tutorialToken or ""),
		RewardName = entry.FinalId,
		Lifetime = lifetime,
	})
	if not clone then
		return false, message or "Tutorial Crewmate spawn is not available yet."
	end

	clone:SetAttribute(TUTORIAL_CREW_MEMBER_ATTRIBUTE, true)
	clone:SetAttribute(TUTORIAL_OWNER_ATTRIBUTE, player.UserId)
	clone:SetAttribute(TUTORIAL_TOKEN_ATTRIBUTE, session.tutorialToken)
	clone:SetAttribute(TUTORIAL_REWARD_NAME_ATTRIBUTE, entry.FinalId)

	session.tutorialCrewMemberModel = clone
	return true, nil
end

local function ensureTutorialCrewMemberTarget(player, session)
	if isHoldingTutorialTarget(player, session) or hasTutorialReward(player, session) then
		return true
	end
	if hasCarriedCrewMember(player) then
		session.warning = "Extract or drop your current Crewmate first."
		return false
	end

	local existing = session.tutorialCrewMemberModel
	if isTutorialTargetModelForSession(player, session, existing) then
		return true
	end

	cleanupTutorialTarget(player, session)
	local success, message = spawnTutorialCrewMemberTarget(player, session)
	if success then
		session.warning = nil
		return true
	end

	session.warning = message or "Tutorial target is loading."
	return false
end

local function serializeStep(step)
	if typeof(step) ~= "table" then
		return nil
	end

	return {
		id = tostring(step.Id or ""),
		title = tostring(step.Title or ""),
		body = tostring(step.Body or ""),
		instruction = tostring(step.Instruction or ""),
		actionText = tostring(step.ActionText or ""),
		waitText = tostring(step.WaitText or ""),
		completionMode = tostring(step.CompletionMode or ""),
		requiredDistance = tonumber(step.RequiredDistance) or 0,
	}
end

local function getModelWorldPosition(model)
	return getInstanceWorldPosition(model)
end

local ObjectiveTargetResolvers = {}

local function getObjectiveTargetCache(session, stepId)
	if typeof(session.objectiveTargetCache) ~= "table" then
		session.objectiveTargetCache = {}
	end

	return session.objectiveTargetCache[tostring(stepId or "")]
end

local function setObjectiveTargetCache(session, stepId, value)
	if typeof(session.objectiveTargetCache) ~= "table" then
		session.objectiveTargetCache = {}
	end

	session.objectiveTargetCache[tostring(stepId or "")] = value
end

local function getObjectiveTargetSignature(target)
	if typeof(target) ~= "table" then
		return ""
	end

	local position = target.position
	local x, y, z = 0, 0, 0
	if typeof(position) == "Vector3" then
		x, y, z = position.X, position.Y, position.Z
	elseif typeof(position) == "table" then
		x = tonumber(position.x or position.X) or 0
		y = tonumber(position.y or position.Y) or 0
		z = tonumber(position.z or position.Z) or 0
	end

	return string.format(
		"%s|%s|%s|%.1f|%.1f|%.1f",
		tostring(target.id or ""),
		tostring(target.kind or ""),
		tostring(target.label or ""),
		x,
		y,
		z
	)
end

local function getPlayerPlot(player)
	local plotSystem = Workspace:FindFirstChild("PlotSystem")
	local plots = plotSystem and plotSystem:FindFirstChild("Plots")
	if not plots then
		return nil
	end

	for _, plot in ipairs(plots:GetChildren()) do
		if plot:IsA("Model") and plot:GetAttribute("OwnerUserId") == player.UserId then
			return plot
		end
	end

	return nil
end

local function getStandsFolder(plot)
	local stands = plot and plot:FindFirstChild("Stands", true)
	if stands and stands:IsA("Folder") then
		return stands
	end

	return nil
end

local function getStandPromptRefs(standModel)
	if not standModel or not standModel:IsA("Model") then
		return nil, nil
	end

	local handle = standModel:FindFirstChild("Handle", true)
	if not handle or not handle:IsA("BasePart") then
		return nil, nil
	end

	local prompt = handle:FindFirstChildOfClass("ProximityPrompt")
	if not prompt or prompt.Enabled == false then
		return nil, nil
	end
	if (tonumber(prompt.MaxActivationDistance) or 0) <= 0 then
		return nil, nil
	end

	return handle, prompt
end

local function findOwnedStandModel(player, standName)
	standName = tostring(standName or "")
	if standName == "" then
		return nil
	end

	local plot = getPlayerPlot(player)
	local stands = getStandsFolder(plot)
	if not stands then
		return nil
	end

	for _, descendant in ipairs(stands:GetDescendants()) do
		if descendant:IsA("Model") and descendant.Name == standName and getStandPromptRefs(descendant) then
			return descendant
		end
	end

	return nil
end

local function getStandCrewMemberName(player, standName)
	standName = tostring(standName or "")
	if standName == "" then
		return ""
	end

	local standData = CrewStandIncomeAuthority.GetStandData(player, standName)
	if typeof(standData) == "table" and typeof(standData.CrewMemberName) == "string" then
		return standData.CrewMemberName
	end

	return ""
end

local function isStandUsableForPlacement(player, standModel)
	if not standModel or not standModel:IsA("Model") then
		return false
	end

	local standName = tostring(standModel.Name or "")
	if not tonumber(standName) then
		return false
	end

	if standModel:GetAttribute("ShipSlotVisible") == false or standModel:GetAttribute("ShipSlotUsable") == false then
		return false
	end

	local upgradeLevel = getPlayerShipUpgradeLevel(player)
	local rebirthCount = getPlayerRebirthCount(player)
	return PlotUpgradeConfig.IsStandUsable(upgradeLevel, standName, rebirthCount)
end

local function isStandEmptyForPlacement(player, standModel)
	if getStandCrewMemberName(player, standModel.Name) ~= "" then
		return false
	end

	return standModel:FindFirstChild("PlacedCrewMember") == nil
end

local function buildStandObjectiveTarget(player, standModel)
	if not isStandUsableForPlacement(player, standModel) or not isStandEmptyForPlacement(player, standModel) then
		return nil
	end

	local handle, prompt = getStandPromptRefs(standModel)
	if not handle then
		return nil
	end

	local position = getInstanceWorldPosition(handle) or getInstanceWorldPosition(standModel)
	if not position then
		return nil
	end

	local standName = tostring(standModel.Name)
	return {
		id = "stand_" .. standName,
		kind = "stand_interaction",
		label = "Empty Stand",
		position = position,
		standName = standName,
		promptName = prompt and prompt.Name or "",
	}
end

local function selectNearestStandObjectiveTarget(player)
	local plot = getPlayerPlot(player)
	local stands = getStandsFolder(plot)
	if not stands then
		return nil
	end

	local rootPosition = getRootPosition(player)
	local candidates = {}

	for _, descendant in ipairs(stands:GetDescendants()) do
		if descendant:IsA("Model") and tonumber(descendant.Name) and getStandPromptRefs(descendant) then
			local target = buildStandObjectiveTarget(player, descendant)
			if target then
				local distance = math.huge
				if rootPosition and typeof(target.position) == "Vector3" then
					distance = (target.position - rootPosition).Magnitude
				end

				table.insert(candidates, {
					Distance = distance,
					StandNumber = tonumber(target.standName) or math.huge,
					Target = target,
				})
			end
		end
	end

	table.sort(candidates, function(left, right)
		if math.abs(left.Distance - right.Distance) > 0.05 then
			return left.Distance < right.Distance
		end

		if left.StandNumber ~= right.StandNumber then
			return left.StandNumber < right.StandNumber
		end

		return tostring(left.Target.id) < tostring(right.Target.id)
	end)

	local chosen = candidates[1]
	return chosen and chosen.Target or nil
end

ObjectiveTargetResolvers.pickup_crew_member = function(player, session)
	local model = session.tutorialCrewMemberModel
	if not isTutorialTargetModelForSession(player, session, model) then
		return nil
	end

	local position = getModelWorldPosition(model)
	if not position then
		return nil
	end

	local label = tostring(session.tutorialCrewMemberName or "")
	if label == "" then
		label = "Tutorial Crewmate"
	end

	return {
		id = "tutorial_crew_member",
		kind = "crew_member",
		label = label,
		position = position,
	}
end

ObjectiveTargetResolvers.extract_crew_member = function(player, session)
	if isHoldingTutorialTarget(player, session) then
		local refs = MapResolver.GetRefs({
			context = "FirstTimeTutorialService",
		})
		local extractionPart = getTutorialExtractionPart(refs)
		local position = getInstanceWorldPosition(extractionPart)
		if not position then
			return nil
		end

		return {
			id = "starting_area_extraction",
			kind = "extraction",
			label = "Extraction Zone",
			position = position,
		}
	end

	local model = session.tutorialCrewMemberModel
	if not isTutorialTargetModelForSession(player, session, model) then
		return nil
	end

	local position = getModelWorldPosition(model)
	if not position then
		return nil
	end

	return {
		id = "tutorial_crew_member",
		kind = "crew_member",
		label = "Tutorial Crewmate",
		position = position,
	}
end

ObjectiveTargetResolvers.place_on_stand = function(player, session)
	if hasPlacedTutorialCrewMember(player, session) or not hasTutorialReward(player, session) then
		setObjectiveTargetCache(session, "place_on_stand", nil)
		return nil
	end

	local cached = getObjectiveTargetCache(session, "place_on_stand")
	if cached and cached.StandName then
		local standModel = findOwnedStandModel(player, cached.StandName)
		local target = standModel and buildStandObjectiveTarget(player, standModel)
		if target then
			return target
		end
	end

	local target = selectNearestStandObjectiveTarget(player)
	setObjectiveTargetCache(session, "place_on_stand", if target then { StandName = target.standName } else nil)
	return target
end

local function serializeObjectiveTarget(player, session, step)
	if typeof(step) ~= "table" or not session then
		return nil
	end

	local resolver = ObjectiveTargetResolvers[tostring(step.Id or "")]
	if not resolver then
		return nil
	end

	return resolver(player, session, step)
end

local function getCurrentStep(session)
	if not session then
		return nil
	end

	return TutorialConfig.GetStep(session.stepIndex)
end

local function getStepHandler(step)
	if typeof(step) ~= "table" then
		return nil
	end

	return StepHandlers[tostring(step.Id or "")]
end

local function canAdvanceManually(session)
	local step = getCurrentStep(session)
	local handler = getStepHandler(step)
	if not handler then
		return false
	end

	return handler.AllowClientAdvance == true
end

local function validateClientAdvance(player, session)
	local step = getCurrentStep(session)
	local handler = getStepHandler(step)
	if not handler or handler.AllowClientAdvance ~= true then
		return false, "Follow the tutorial objective first."
	end

	if handler.ValidateClientAdvance then
		local success, allowed, message = pcall(handler.ValidateClientAdvance, player, session, step)
		if not success then
			warn(string.format("[FirstTimeTutorialService] Tutorial step validation failed for %s: %s", player.Name, tostring(allowed)))
			return false, "Tutorial step could not be validated."
		end

		if allowed ~= true then
			return false, message or "Follow the tutorial objective first."
		end
	end

	return true, nil
end

local function buildState(player)
	local session = sessions[player]
	local completed = isTutorialCompleted(player)
	if completed or not session or session.active ~= true then
		return {
			active = false,
			completed = completed,
			version = TutorialConfig.Version,
			stepIndex = 0,
			totalSteps = TutorialConfig.GetStepCount(),
			progress = 0,
			canAdvance = false,
		}
	end

	return {
		active = true,
		completed = false,
		version = TutorialConfig.Version,
		stepIndex = session.stepIndex,
		totalSteps = TutorialConfig.GetStepCount(),
		step = serializeStep(getCurrentStep(session)),
		target = serializeObjectiveTarget(player, session, getCurrentStep(session)),
		progress = session.progress or 0,
		canAdvance = canAdvanceManually(session),
		warning = session.warning,
	}
end

local function pushState(player)
	if stateRemote and player.Parent == Players then
		local state = buildState(player)
		local session = sessions[player]
		if session then
			session.lastPushedObjectiveTargetSignature = getObjectiveTargetSignature(state.target)
		end
		stateRemote:FireClient(player, state)
	end
end

local function pushStateIfObjectiveTargetChanged(player, session, step)
	if not session or session.active ~= true then
		return
	end

	local target = serializeObjectiveTarget(player, session, step)
	local signature = getObjectiveTargetSignature(target)
	if signature ~= tostring(session.lastPushedObjectiveTargetSignature or "") then
		pushState(player)
	end
end

local function setProgress(player, session, progress)
	progress = math.clamp(tonumber(progress) or 0, 0, 1)
	session.progress = progress

	if math.abs(progress - (session.lastPushedProgress or 0)) >= PUSH_PROGRESS_DELTA then
		session.lastPushedProgress = progress
		pushState(player)
	end
end

local function sendPopup(player, text, isError)
	PopUpModule:Server_SendPopUp(
		player,
		text,
		if isError then ERROR_COLOR else INFO_COLOR,
		STROKE_COLOR,
		3,
		isError == true
	)
end

local function completeTutorial(player)
	local session = sessions[player]
	if not session or session.active ~= true then
		return false, "Tutorial is not active."
	end

	local success, reason = DataManager:TrySetValue(player, TutorialConfig.CompletionPath, true)
	if success ~= true then
		warn(string.format("[FirstTimeTutorialService] Could not save tutorial completion for %s: %s", player.Name, tostring(reason)))
		session.warning = SAVE_FAILURE_MESSAGE
		sendPopup(player, SAVE_FAILURE_MESSAGE, true)
		pushState(player)
		return false, SAVE_FAILURE_MESSAGE
	end

	session.active = false
	session.completed = true
	session.warning = nil
	cleanupTutorialTarget(player, session)
	clearTutorialRuntimeAttributes(player)

	sendPopup(player, "Tutorial complete!", false)
	pushState(player)
	return true, nil
end

local function startStep(player, stepIndex)
	local session = sessions[player]
	if not session then
		return
	end

	local step = TutorialConfig.GetStep(stepIndex)
	if not step then
		completeTutorial(player)
		return
	end

	session.stepIndex = stepIndex
	session.progress = 0
	session.lastPushedProgress = -1
	session.moveStartPosition = nil
	session.warning = nil
	session.objectiveTargetCache = {}
	session.lastPushedObjectiveTargetSignature = nil
	setTutorialRuntimeAttributes(player, session, step)

	local stepId = tostring(step.Id or "")
	if stepId ~= "pickup_crew_member" and not hasCarriedCrewMember(player) then
		cleanupTutorialTarget(player, session)
	end

	if step.CompletionMode == "MoveDistance" then
		session.moveStartPosition = getRootPosition(player)
	end

	local handler = getStepHandler(step)
	if handler and handler.OnStart then
		local success, err = pcall(handler.OnStart, player, session, step)
		if not success then
			warn(string.format("[FirstTimeTutorialService] Tutorial step setup failed for %s: %s", player.Name, tostring(err)))
			session.warning = "Tutorial objective is loading."
		end
	end

	pushState(player)
end

local function advanceTutorial(player)
	local session = sessions[player]
	if not session or session.active ~= true then
		return false, "Tutorial is not active."
	end

	if session.stepIndex >= TutorialConfig.GetStepCount() then
		return completeTutorial(player)
	end

	startStep(player, session.stepIndex + 1)
	return true, nil
end

local function createSession(player)
	if sessions[player] then
		return sessions[player]
	end

	if isTutorialCompleted(player) then
		pushState(player)
		return nil
	end

	ensureTutorialStarterDoubloons(player)

	local session = {
		active = true,
		completed = false,
		stepIndex = 1,
		progress = 0,
		lastPushedProgress = -1,
		moveStartPosition = nil,
		tutorialCrewMemberName = tostring(TutorialConfig.TutorialCrewMember and TutorialConfig.TutorialCrewMember.Name or ""),
		tutorialToken = HttpService:GenerateGUID(false),
		extractStartInventoryCount = getCrewInventoryCount(player),
		collectStartBalance = getPrimaryBalance(player),
		buySpeedStartValue = getSpeedValue(player),
	}
	sessions[player] = session
	reconcileTutorialCrewMemberGrant(player, session)
	reconcileTutorialSpeedRecovery(player)
	restoreGrantedTutorialReward(player, session)
	startStep(player, 1)
	return session
end

local function ensureSession(player)
	local session = sessions[player]
	if session then
		return session
	end

	if not DataManager:WaitUntilReady(player, 10) then
		return nil, "Tutorial data is still loading."
	end

	return createSession(player), nil
end

local function trySetTutorialResetFlag(player, path, failures)
	local success, reason = DataManager:TrySetValue(player, path, false)
	if success ~= true then
		table.insert(failures, string.format("%s:%s", tostring(path), tostring(reason or "set_failed")))
	end
end

local function refreshStandRuntime(player)
	local standCommand = ShipRuntimeSignals.GetStandCommandFunction()
	if not standCommand then
		return false, "stand_runtime_unavailable"
	end

	local ok, result, extra = pcall(function()
		return standCommand:Invoke("refresh", player)
	end)
	if not ok then
		return false, tostring(result)
	end
	if result == false then
		return false, tostring(extra or "stand_runtime_refresh_failed")
	end

	return true, nil
end

local function skipTutorial(player)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return false, "Invalid player.", nil
	end

	if not DataManager:WaitUntilReady(player, 10) then
		return false, "Tutorial data is still loading.", nil
	end

	local success, reason = DataManager:TrySetValue(player, TutorialConfig.CompletionPath, true)
	if success == false then
		warn(string.format("[FirstTimeTutorialService] Could not save tutorial skip for %s: %s", player.Name, tostring(reason)))
		local session = sessions[player]
		if session then
			session.warning = SAVE_FAILURE_MESSAGE
		end
		sendPopup(player, SAVE_FAILURE_MESSAGE, true)
		pushState(player)
		return false, SAVE_FAILURE_MESSAGE, nil
	end

	local session = sessions[player]
	local removedWorldTargets = cleanupTutorialWorldTargets(player, session)
	if session then
		session.active = false
		session.completed = true
		session.warning = nil
	end
	sessions[player] = nil
	clearTutorialRuntimeAttributes(player)

	local tutorialStorageNames = getTutorialRewardStorageNames(session)
	local rewardCleanup = CrewInstanceService.RemoveTutorialRewardInstances(player, {
		StorageNames = tutorialStorageNames,
		ClearStaleStorageAssignments = true,
	})
	tutorialStorageNames = getTutorialRewardStorageNames(session, rewardCleanup.RemovedStorageNames)
	local removedTutorialTools = removeStaleTutorialTools(player, tutorialStorageNames)
	local standRefreshOk, standRefreshReason = refreshStandRuntime(player)

	sendPopup(player, "Tutorial skipped.", false)
	pushState(player)

	return true, nil, {
		RemovedTutorialRewards = math.max(0, tonumber(rewardCleanup.RemovedCount) or 0),
		ClearedStands = if typeof(rewardCleanup.ClearedStands) == "table" then rewardCleanup.ClearedStands else {},
		RemovedWorldTargets = removedWorldTargets,
		RemovedTutorialTools = removedTutorialTools,
		StandRuntimeRefreshed = standRefreshOk == true,
		StandRefreshReason = standRefreshReason,
	}
end

function FirstTimeTutorialService.ResetForTesting(player)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return {
			Success = false,
			Detail = "invalid player",
		}
	end

	if not DataManager:WaitUntilReady(player, 10) then
		return {
			Success = false,
			Detail = "tutorial data is still loading",
		}
	end

	local session = sessions[player]
	local removedWorldTargets = cleanupTutorialWorldTargets(player, session)
	if session then
		session.active = false
		session.completed = false
		session.warning = nil
	end
	sessions[player] = nil
	clearTutorialRuntimeAttributes(player)

	local tutorialStorageNames = getTutorialRewardStorageNames(session)
	local rewardCleanup = CrewInstanceService.RemoveTutorialRewardInstances(player, {
		StorageNames = tutorialStorageNames,
		ClearStaleStorageAssignments = true,
	})
	tutorialStorageNames = getTutorialRewardStorageNames(session, rewardCleanup.RemovedStorageNames)
	local removedTutorialTools = removeStaleTutorialTools(player, tutorialStorageNames)

	local flagFailures = {}
	trySetTutorialResetFlag(player, TutorialConfig.CompletionPath, flagFailures)
	trySetTutorialResetFlag(player, TUTORIAL_CREW_MEMBER_GRANTED_PATH, flagFailures)
	trySetTutorialResetFlag(player, TUTORIAL_SPEED_TOP_UP_GRANTED_PATH, flagFailures)

	if #flagFailures > 0 then
		pushState(player)
		return {
			Success = false,
			Detail = "failed to reset " .. table.concat(flagFailures, ", "),
			RemovedTutorialRewards = rewardCleanup.RemovedCount or 0,
			ClearedStands = rewardCleanup.ClearedStands or {},
			RemovedWorldTargets = removedWorldTargets,
			RemovedTutorialTools = removedTutorialTools,
		}
	end

	local standRefreshOk, standRefreshReason = refreshStandRuntime(player)
	local nextSession = createSession(player)
	if not nextSession then
		pushState(player)
	end

	local removedRewards = math.max(0, tonumber(rewardCleanup.RemovedCount) or 0)
	local clearedStands = if typeof(rewardCleanup.ClearedStands) == "table" then rewardCleanup.ClearedStands else {}
	local detail = string.format(
		"reset for %s; flags=false; removed tutorial rewards=%d; cleared stands=%d; world targets=%d; tools=%d",
		player.Name,
		removedRewards,
		#clearedStands,
		removedWorldTargets,
		removedTutorialTools
	)
	if standRefreshOk ~= true then
		detail ..= "; stand refresh warning=" .. tostring(standRefreshReason or "unknown")
	end

	return {
		Success = true,
		Detail = detail,
		RemovedTutorialRewards = removedRewards,
		ClearedStands = clearedStands,
		RemovedWorldTargets = removedWorldTargets,
		RemovedTutorialTools = removedTutorialTools,
		StandRuntimeRefreshed = standRefreshOk == true,
		StandRefreshReason = standRefreshReason,
	}
end

local function handleAdvanceRequest(player)
	local session, message = ensureSession(player)
	if not session then
		return {
			success = isTutorialCompleted(player),
			message = message,
			state = buildState(player),
		}
	end

	local allowed, validationMessage = validateClientAdvance(player, session)
	if not allowed then
		return {
			success = false,
			message = validationMessage or "Follow the tutorial objective first.",
			state = buildState(player),
		}
	end

	local success, reason = advanceTutorial(player)
	return {
		success = success,
		message = reason,
		state = buildState(player),
	}
end

local function handleSkipRequest(player)
	local success, message, cleanup = skipTutorial(player)
	return {
		success = success,
		message = message,
		cleanup = cleanup,
		state = buildState(player),
	}
end

local function handleRequest(player, actionName)
	if actionName == "GetState" then
		local _, message = ensureSession(player)
		return {
			success = message == nil,
			message = message,
			state = buildState(player),
		}
	elseif actionName == "Advance" then
		return handleAdvanceRequest(player)
	elseif actionName == "Skip" then
		return handleSkipRequest(player)
	end

	return {
		success = false,
		message = "Unknown tutorial action.",
		state = buildState(player),
	}
end

local function advanceIfCurrentStep(player, expectedStepId)
	local session = sessions[player]
	if not session or session.active ~= true then
		return false
	end

	local step = getCurrentStep(session)
	if not step or tostring(step.Id or "") ~= expectedStepId then
		return false
	end

	session.progress = 1
	session.lastPushedProgress = 1
	advanceTutorial(player)
	return true
end

local function updateMoveDistanceStep(player, session, step)
	local position = getRootPosition(player)
	if not position then
		return
	end

	if not session.moveStartPosition then
		session.moveStartPosition = position
		session.progress = 0
		pushState(player)
		return
	end

	local requiredDistance = math.max(1, tonumber(step.RequiredDistance) or 1)
	local distance = (position - session.moveStartPosition).Magnitude
	local progress = math.clamp(distance / requiredDistance, 0, 1)

	if distance >= requiredDistance then
		advanceTutorial(player)
		return
	end

	setProgress(player, session, progress)
end

StepHandlers.move.Update = updateMoveDistanceStep

StepHandlers.pickup_crew_member.OnStart = function(player, session)
	if hasTutorialReward(player, session) then
		return
	end
	ensureTutorialCrewMemberTarget(player, session)
end

StepHandlers.pickup_crew_member.Update = function(player, session)
	if isHoldingTutorialTarget(player, session) then
		advanceTutorial(player)
		return
	end
	if hasTutorialReward(player, session) then
		advanceTutorial(player)
		return
	end

	ensureTutorialCrewMemberTarget(player, session)
	setProgress(player, session, 0)
end

StepHandlers.extract_crew_member.OnStart = function(player, session)
	session.extractStartInventoryCount = getCrewInventoryCount(player)
	if isHoldingTutorialTarget(player, session) then
		session.progress = 0.5
	end
end

StepHandlers.extract_crew_member.Update = function(player, session)
	if hasTutorialReward(player, session) then
		advanceTutorial(player)
		return
	end

	if not hasCarriedCrewMember(player) then
		ensureTutorialCrewMemberTarget(player, session)
	end

	setProgress(player, session, if isHoldingTutorialTarget(player, session) then 0.5 else 0)
end

StepHandlers.place_on_stand.Update = function(player, session)
	if hasPlacedTutorialCrewMember(player, session) then
		advanceTutorial(player)
		return
	end

	setProgress(player, session, if hasTutorialReward(player, session) then 0.45 else 0)
end

StepHandlers.collect_beli.OnStart = function(player, session)
	session.collectStartBalance = getPrimaryBalance(player)
	session.collectedTutorialBeli = false
end

StepHandlers.collect_beli.Update = function(player, session)
	if session.collectedTutorialBeli == true then
		advanceTutorial(player)
		return
	end

	setProgress(player, session, if getBankedTutorialStandIncome(player, session) > 0 then 0.5 else 0)
end

StepHandlers.buy_speed.OnStart = function(player, session)
	session.buySpeedStartValue = getSpeedValue(player)
	if session.buySpeedRecoveryAvailable ~= true and getSpeedValue(player) <= session.buySpeedStartValue then
		session.buySpeedRecoveryAvailable = canRecoverSpeedUpgradePurchase(player)
	end
end

StepHandlers.buy_speed.Update = function(player, session)
	local speedValue = getSpeedValue(player)
	local startValue = tonumber(session.buySpeedStartValue) or 1
	if speedValue > startValue or speedValue > 1 then
		advanceTutorial(player)
		return
	end
	if session.buySpeedRecoveryAvailable ~= true then
		session.buySpeedRecoveryAvailable = canRecoverSpeedUpgradePurchase(player)
	end

	setProgress(player, session, if canRecoverSpeedUpgradePurchase(player) then 0.5 else 0)
end

local function onHeartbeat(deltaTime)
	objectiveCheckAccumulator += deltaTime
	if objectiveCheckAccumulator < OBJECTIVE_CHECK_INTERVAL then
		return
	end
	objectiveCheckAccumulator = 0

	for player, session in pairs(sessions) do
		if player.Parent == Players and session.active == true then
			local step = getCurrentStep(session)
			local handler = getStepHandler(step)
			if handler and handler.Update then
				handler.Update(player, session, step)
			end
			if session.active == true and getCurrentStep(session) == step then
				pushStateIfObjectiveTargetChanged(player, session, step)
			end
		end
	end
end

local function onObjectiveRecorded(player, eventData)
	if typeof(eventData) ~= "table" then
		return
	end

	local objectiveType = tostring(eventData.Type or "")
	local context = if typeof(eventData.Context) == "table" then eventData.Context else {}
	local source = tostring(context.Source or "")

	if objectiveType == "ExtractCrew" and source == "SpawnCrewMembers" and context.TutorialCrewMember == true then
		local session = sessions[player]
		local eventToken = tostring(context.TutorialToken or "")
		if session and (eventToken == tostring(session.tutorialToken or "") or hasTutorialReward(player, session)) then
			advanceIfCurrentStep(player, "extract_crew_member")
		end
	elseif objectiveType == "PlaceOnStand" and source == "StandPlacement" and context.TutorialPlacement == true then
		local session = sessions[player]
		local standName = tostring(context.StandName or "")
		if session and standName ~= "" then
			session.placedTutorialStandName = standName
			session.placedTutorialInstanceId = tostring(context.CrewMemberInstanceId or "")
			session.placedTutorialCrewMemberName = tostring(context.CrewMemberName or "")
			advanceIfCurrentStep(player, "place_on_stand")
		end
	elseif objectiveType == "EarnDoubloons" and source == "StandIncome" then
		local session = sessions[player]
		if session and isTutorialCrewMemberOnStand(player, session, context.StandName) then
			session.collectedTutorialBeli = true
			advanceIfCurrentStep(player, "collect_beli")
		end
	end
end

local function markCompletedFromValue(player)
	local session = sessions[player]
	if session then
		session.active = false
		session.completed = true
		session.warning = nil
		cleanupTutorialTarget(player, session)
	end
	clearTutorialRuntimeAttributes(player)

	pushState(player)
end

local function observeTutorialCompletionValue(player, bucket)
	local boundValues = {}

	local function bindTutorialValue(valueObject)
		if not valueObject or not valueObject:IsA("BoolValue") or boundValues[valueObject] == true then
			return
		end

		boundValues[valueObject] = true

		local function applyValue()
			if valueObject.Value == true then
				markCompletedFromValue(player)
			end
		end

		table.insert(bucket, valueObject:GetPropertyChangedSignal("Value"):Connect(applyValue))
		applyValue()
	end

	local function bindHiddenLeaderstats(folder)
		if not folder or folder.Name ~= HIDDEN_LEADERSTATS_NAME then
			return
		end

		bindTutorialValue(folder:FindFirstChild(TUTORIAL_VALUE_NAME))

		table.insert(bucket, folder.ChildAdded:Connect(function(child)
			if child.Name == TUTORIAL_VALUE_NAME then
				bindTutorialValue(child)
			end
		end))
	end

	bindHiddenLeaderstats(player:FindFirstChild(HIDDEN_LEADERSTATS_NAME))

	table.insert(bucket, player.ChildAdded:Connect(function(child)
		if child.Name == HIDDEN_LEADERSTATS_NAME then
			bindHiddenLeaderstats(child)
		end
	end))
end

local function bindPlayer(player)
	local bucket = {}
	playerConnections[player] = bucket
	observeTutorialCompletionValue(player, bucket)

	table.insert(bucket, player.CharacterAdded:Connect(function()
		local session = sessions[player]
		local step = getCurrentStep(session)
		if session and step and step.CompletionMode == "MoveDistance" then
			session.moveStartPosition = nil
			session.progress = 0
			task.delay(0.25, function()
				if player.Parent == Players then
					pushState(player)
				end
			end)
		end
	end))

	task.spawn(function()
		if not DataManager:WaitUntilReady(player, 30) then
			return
		end

		createSession(player)
	end)
end

function FirstTimeTutorialService.Start()
	if started then
		return
	end
	started = true

	ensureRemotes()

	requestRemote.OnServerInvoke = function(player, actionName)
		return handleRequest(player, tostring(actionName or ""))
	end

	heartbeatConnection = RunService.Heartbeat:Connect(onHeartbeat)
	questSignalConnection = QuestSignals.ObjectiveRecorded:Connect(onObjectiveRecorded)

	Players.PlayerAdded:Connect(bindPlayer)
	Players.PlayerRemoving:Connect(disconnectPlayer)

	for _, player in ipairs(Players:GetPlayers()) do
		bindPlayer(player)
	end
end

function FirstTimeTutorialService.Stop()
	if heartbeatConnection then
		heartbeatConnection:Disconnect()
		heartbeatConnection = nil
	end

	if questSignalConnection then
		questSignalConnection:Disconnect()
		questSignalConnection = nil
	end

	for _, player in ipairs(Players:GetPlayers()) do
		disconnectPlayer(player)
	end

	started = false
end

return FirstTimeTutorialService
