local CrewIncomeRuntime = {}
local started = false

local STEAL_PRODUCT_BY_RARITY = {
	Common = 3512126073,
	Uncommon = 3512126073,
	Rare = 3512126073,
	Epic = 3512126073,

	Legendary = 3512126373,
	Mythic = 3512127278,
	Godly = 3512127790,
	Secret = 3512128038,
	Omega = 3512128716,
}

local RARITY_PRIORITY = { "Omega", "Secret", "Godly", "Mythic", "Legendary", "Epic", "Rare", "Uncommon", "Common" }

local function normalizeRarity(rarity)
	rarity = tostring(rarity or "")
	if rarity == "" then
		return "Common"
	end

	local lower = string.lower(rarity)
	for _, key in ipairs(RARITY_PRIORITY) do
		if string.find(lower, string.lower(key), 1, true) then
			return key
		end
	end

	return "Common"
end

local function formatVector3(value)
	if typeof(value) ~= "Vector3" then
		return tostring(value)
	end

	return string.format("(%.2f, %.2f, %.2f)", value.X, value.Y, value.Z)
end

local function formatInstancePath(instance)
	if not instance then
		return "<nil>"
	end

	return instance:GetFullName()
end

local function countSavedStandEntries(incomeCrewMembers)
	if typeof(incomeCrewMembers) ~= "table" then
		return 0
	end

	local count = 0
	for _, standData in pairs(incomeCrewMembers) do
		if
			typeof(standData) == "table"
			and tostring(standData.CrewMemberName or standData.LegacyStorageName or "") ~= ""
		then
			count += 1
		end
	end

	return count
end

local function countTableEntries(value)
	if typeof(value) ~= "table" then
		return 0
	end

	local count = 0
	for _ in pairs(value) do
		count += 1
	end

	return count
end

local function bootstrapExistingCrewIncomePlayer(runtime, player)
	runtime.standDebug("bootstrap existing_player=%s", player.Name)

	local plot = runtime.waitForPlot(player, 5)
	if plot then
		runtime.scanAndBindPlot(player, plot)
		runtime.reconcilePlayerStandAssignments(player)
		runtime.resetHugeIncomeOnJoin(player)
		runtime.refreshPlayerIncomeDisplaysAfterLifecycleUpdate(player)
	else
		runtime.standDebug("bootstrap existing_player=%s reason=no_active_ship", player.Name)
	end
end

local function bootstrapExistingCrewIncomePlayers(runtime)
	for _, player in ipairs(runtime.Players:GetPlayers()) do
		task.spawn(bootstrapExistingCrewIncomePlayer, runtime, player)
	end
end

local function updateCrewStandIncomeForTick(runtime, player, standModel, equippedCrewMember, totalFoodCount, zeroIncomeLogged)
	if not standModel or not standModel.Parent then
		return false
	end

	local standName = standModel.Name
	local cache = runtime.getSlotRuntime(player, standModel.Parent, standModel)
	runtime.dmEnsureStandFolder(player, standName)

	local slotState = runtime.getStandSlotState(player, standName)
	local crewMemberName = runtime.getPlayerStandCrewMemberName(player, standName)
	local crewMemberInstanceId = if crewMemberName ~= "" then runtime.getPlayerStandCrewMemberInstanceId(player, standName) else ""

	if not slotState.Usable then
		runtime.clearStandVisual(standModel)
		runtime.updateStandMoneyText(player, standModel, cache, slotState, crewMemberName)
		runtime.updateLevelUpUI(player, standModel, cache, slotState, crewMemberName, crewMemberInstanceId, false, totalFoodCount)
		runtime.updateStandPromptTexts(player, standModel, cache, slotState, crewMemberName, equippedCrewMember)
		return false
	end

	local didBankIncome = false
	if crewMemberName ~= "" then
		if not standModel:FindFirstChild("PlacedCrewMember") then
			local handle = cache and cache.Handle or runtime.resolveSlotHandle(standModel)
			if handle and handle:IsA("BasePart") then
				runtime.spawnStandCrewMember(player, standModel, handle, crewMemberName)
			end
		end

		local inc = runtime.getIncomeWithLevel(player, crewMemberName) * runtime.getBeliBoostMultiplier(player)
		zeroIncomeLogged[player] = zeroIncomeLogged[player] or {}
		if inc ~= 0 then
			zeroIncomeLogged[player][standName] = nil
			if runtime.CrewStandIncomeAuthority.AdjustIncomeToCollect(player, standName, inc, "income_bank") then
				didBankIncome = true
			end
		elseif zeroIncomeLogged[player][standName] ~= true then
			zeroIncomeLogged[player][standName] = true
			runtime.standDebug("income zero player=%s stand=%s crewMember=%s", player.Name, standName, tostring(crewMemberName))
		end

		runtime.updateStandHover(player, standModel, crewMemberName)
	end

	runtime.updateStandMoneyText(player, standModel, cache, slotState, crewMemberName)
	runtime.updateLevelUpUI(player, standModel, cache, slotState, crewMemberName, crewMemberInstanceId, false, totalFoodCount)
	runtime.updateStandPromptTexts(player, standModel, cache, slotState, crewMemberName, equippedCrewMember)

	return didBankIncome
end

local function updateCrewPlayerIncomeForTick(runtime, player, stands, zeroIncomeLogged)
	if not player.Parent then
		runtime.clearPlayerStandRuntime(player)
		return
	end

	if typeof(stands) ~= "table" then
		return
	end

	local didBankIncome = false
	local equippedCrewMember = runtime.getEquippedCrewMemberToolInfo(player)
	local totalFoodCount = runtime.CrewFoodProgression.GetTotalFoodCount(player)

	for i = 1, #stands do
		if updateCrewStandIncomeForTick(runtime, player, stands[i], equippedCrewMember, totalFoodCount, zeroIncomeLogged) then
			didBankIncome = true
		end
	end

	if didBankIncome then
		runtime.refreshBankedIncomeShadow(player)
	end
end

local function runCrewIncomeBankLoop(runtime)
	local zeroIncomeLogged = {}

	while true do
		task.wait(1)

		for player, stands in pairs(runtime.playerStandList) do
			updateCrewPlayerIncomeForTick(runtime, player, stands, zeroIncomeLogged)
		end
	end
end

function CrewIncomeRuntime.Start()
	if started then
		return
	end
	started = true

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local MarketplaceService = game:GetService("MarketplaceService")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")

local MAX_INCOME_ON_JOIN = 1e16

local CrewFoodProgression = require(ServerScriptService.Modules:WaitForChild("CrewFoodProgression"))
local CrewInstanceService = require(ServerScriptService.Modules:WaitForChild("CrewInstanceService"))
local CrewQuickSlotService = require(ServerScriptService.Modules:WaitForChild("CrewQuickSlotService"))
local CaptainSlotRuntime = require(ServerScriptService.Modules:WaitForChild("CaptainSlotRuntime"))
local CrewSlotAssignmentReconciler = require(ServerScriptService.Modules:WaitForChild("CrewSlotAssignmentReconciler"))
local CrewStandIncomeAuthority = require(ServerScriptService.Modules:WaitForChild("CrewStandIncomeAuthority"))
local IncomeClaimMath = require(ServerScriptService.Modules:WaitForChild("IncomeClaimMath"))
local QuestSignals = require(ServerScriptService.Modules:WaitForChild("GrandLineRushQuestSignals"))
local ShipRuntimeSignals = require(ServerScriptService.Modules:WaitForChild("ShipRuntimeSignals"))
local ShipRuntimeService = require(ServerScriptService.Modules:WaitForChild("ShipRuntimeService"))
local ShipSlotService = require(ServerScriptService.Modules:WaitForChild("ShipSlotService"))
local StandUpgradeMults = require(ServerScriptService.Modules.StandsMultiply)

local CurrencyUtil = require(ReplicatedStorage.Modules:WaitForChild("CurrencyUtil"))
local MonetizationConfig = require(ReplicatedStorage.Modules:WaitForChild("Configs"):WaitForChild("Monetization"))
local PopUpModule = require(ReplicatedStorage.Modules:WaitForChild("PopUpModule"))

local Remotes = ReplicatedStorage:FindFirstChild("Remotes")
if not Remotes then
	Remotes = Instance.new("Folder")
	Remotes.Name = "Remotes"
	Remotes.Parent = ReplicatedStorage
end

local MoneyCollectedRE = Remotes:FindFirstChild("StandMoneyCollected")
if not MoneyCollectedRE then
	MoneyCollectedRE = Instance.new("RemoteEvent")
	MoneyCollectedRE.Name = "StandMoneyCollected"
	MoneyCollectedRE.Parent = Remotes
end

local incomeStatusDisplayMetadataRequest = ReplicatedStorage:FindFirstChild("IncomeStatusDisplayMetadataRequest")
if incomeStatusDisplayMetadataRequest and not incomeStatusDisplayMetadataRequest:IsA("RemoteFunction") then
	incomeStatusDisplayMetadataRequest:Destroy()
	incomeStatusDisplayMetadataRequest = nil
end
if not incomeStatusDisplayMetadataRequest then
	incomeStatusDisplayMetadataRequest = Instance.new("RemoteFunction")
	incomeStatusDisplayMetadataRequest.Name = "IncomeStatusDisplayMetadataRequest"
	incomeStatusDisplayMetadataRequest.Parent = ReplicatedStorage
end

local dmMod = script.Parent.Parent.Data.DataManager
local DataManager = dmMod and require(dmMod) or nil
local CrewStorageModule = nil
local CrewMemberCanonicalReadGateModule = nil

local Modules = ReplicatedStorage:WaitForChild("Modules")
local Configs = Modules:WaitForChild("Configs")
local CrewCatalog = require(Modules:WaitForChild("Crew"):WaitForChild("CrewCatalog"))
local CrewOverhead = require(Modules:WaitForChild("Crew"):WaitForChild("CrewOverhead"))
local VariantCfg = CrewCatalog.GetVariantConfig()
local PlotUpgradeConfig = require(Configs:WaitForChild("PlotUpgrade"))
local RebirthConfig = require(Configs:WaitForChild("Rebirths"))
local ShipVisuals = require(Configs:WaitForChild("ShipVisuals"))
local CrewRegistry = require(Modules:WaitForChild("Server"):WaitForChild("Crew"):WaitForChild("Registry"))
local dmGet
local ShipSlotGuiIdentity = require(Modules:WaitForChild("ShipSlotGuiIdentity"))
local CAPTAIN_SLOT_KEY = ShipSlotService.CaptainSlotKey or "Captain"
local CAPTAIN_RUNTIME_GUI_ATTRIBUTE = "ShipCaptainSlotRuntimeGui"
local CAPTAIN_RUNTIME_GUI_SLOT_ATTRIBUTE = "ShipCaptainSlotKey"
local CAPTAIN_RUNTIME_GUI_NAME = "ShipCaptainSlotLevelUp"

pcall(function()
	CrewRegistry.Build()
end)

local getPlayerStandCrewMemberName
local getPlayerStandCrewMemberInstanceId
local getCrewMemberLevel
local dmSet
local STAND_DEBUG = false
local ensuredStandFolders = {}
local standCommandFunction = ShipRuntimeSignals.GetStandCommandFunction()
local DEBUG_TRACE = RunService:IsStudio() and game:GetAttribute("CrewIncomeDebugTrace") == true
local TUTORIAL_RUNTIME_ACTIVE_ATTRIBUTE = "FirstTimeTutorialActive"
local TUTORIAL_RUNTIME_STEP_ATTRIBUTE = "FirstTimeTutorialStepId"
local CREW_ITEM_KIND = "CrewMember"
local LEGACY_STAND_CREW_PLACEMENT_ROTATION_OFFSET_DEGREES = 90
local PLACEMENT_PICKUP_GUARD_SECONDS = 1.25
local INCOME_SHADOW_BANK_THROTTLE_SECONDS = 3
local INCOME_STATUS_DISPLAY_METADATA_CACHE_SECONDS = 15
local crewRecordCache = setmetatable({}, { __mode = "k" })
local OVERHEAD_ATTRIBUTES = CrewOverhead.Attribute

local function ownershipTrace(message, ...)
	if not DEBUG_TRACE then
		return
	end

	print(string.format("[OWNERSHIP TRACE] t=%.3f " .. message, os.clock(), ...))
end

local function plotTrace(message, ...)
	if not DEBUG_TRACE then
		return
	end

	print(string.format("[PLOT TRACE] t=%.3f " .. message, os.clock(), ...))
end

local function saveTrace(message, ...)
	if not DEBUG_TRACE then
		return
	end

	print(string.format("[SAVE TRACE] t=%.3f " .. message, os.clock(), ...))
end

local function logSavedShipSnapshot(player, context)
	if not DEBUG_TRACE or not DataManager then
		return
	end

	local ok, result = pcall(function()
		local crewMemberIncome = DataManager:GetValue(player, "CrewMemberIncome")
		local shipSlots = DataManager:GetValue(player, "Ship.Slots")
		local plotUpgrade = DataManager:GetValue(player, "HiddenLeaderstats.PlotUpgrade")

		return {
			CrewMemberIncome = crewMemberIncome,
			ShipSlots = shipSlots,
			PlotUpgrade = plotUpgrade,
		}
	end)

	if not ok then
		saveTrace(
			"snapshot context=%s player=%s userId=%s result=lookup_failed reason=%s",
			tostring(context),
			player.Name,
			tostring(player.UserId),
			tostring(result)
		)
		return
	end

	saveTrace(
		"snapshot context=%s player=%s userId=%s plotUpgrade=%s savedStandEntries=%s shipSlots=%s",
		tostring(context),
		player.Name,
		tostring(player.UserId),
		tostring(result.PlotUpgrade),
		tostring(countSavedStandEntries(result.CrewMemberIncome)),
		tostring(countTableEntries(result.ShipSlots))
	)
end

local CREW_PICKUP_DEBUG = true

local function standDebug(message, ...)
	if STAND_DEBUG ~= true then
		return
	end

	warn(string.format("[GLR StandDebug] " .. tostring(message), ...))
end

local function crewPickupDebug(message, ...)
	if CREW_PICKUP_DEBUG ~= true then
		return
	end

	local prefix = "[CrewPickupDebug] "
	if select("#", ...) == 0 then
		warn(prefix .. tostring(message))
		return
	end

	local ok, formatted = pcall(string.format, prefix .. tostring(message), ...)
	warn(ok and formatted or (prefix .. tostring(message)))
end

local function formatCrewPickupDebugFields(fields)
	local parts = {}
	for _, field in ipairs(fields or {}) do
		parts[#parts + 1] = tostring(field[1]) .. "=" .. tostring(field[2])
	end
	return table.concat(parts, " ")
end

local function getCrewStorage()
	if CrewStorageModule == nil then
		CrewStorageModule = require(ServerScriptService:WaitForChild("Modules"):WaitForChild("CrewStorage"))
	end
	return CrewStorageModule
end

local function getCrewMemberCanonicalReadGate()
	if CrewMemberCanonicalReadGateModule == nil then
		CrewMemberCanonicalReadGateModule = require(
			ServerScriptService:WaitForChild("Modules"):WaitForChild("CrewMemberCanonicalReadGate")
		)
	end
	return CrewMemberCanonicalReadGateModule
end

local function refreshCrewMemberShadow(_player, _reason, _options)
	-- Normal stand/income flow now writes CrewMemberIncome directly. Legacy
	-- projection is kept for explicit migration/repair commands, not runtime.
	return nil
end

local function refreshBankedIncomeShadow(player)
	return refreshCrewMemberShadow(player, "income_bank", {
		ThrottleKey = "income_bank",
		ThrottleSeconds = INCOME_SHADOW_BANK_THROTTLE_SECONDS,
	})
end

local function refreshCollectedIncomeShadow(player)
	return refreshCrewMemberShadow(player, "income_collect")
end

local function logCrewSwitchFailure(player, standName, reason, detail)
	warn(string.format(
		"[CrewSwitch] player=%s stand=%s reason=%s%s",
		player and player.Name or "unknown",
		tostring(standName or ""),
		tostring(reason or "unknown"),
		if detail and detail ~= "" then " " .. tostring(detail) else ""
	))
end

local function isActiveTutorialPlacementStep(player)
	return typeof(player) == "Instance"
		and player:IsA("Player")
		and player:GetAttribute(TUTORIAL_RUNTIME_ACTIVE_ATTRIBUTE) == true
		and player:GetAttribute(TUTORIAL_RUNTIME_STEP_ATTRIBUTE) == "place_on_stand"
end

local function tutorialStandPlacementLog(player, standName, reason, detail)
	if not isActiveTutorialPlacementStep(player) then
		return
	end

	warn(string.format(
		"[TutorialStandPlacement] player=%s stand=%s reason=%s%s",
		player.Name,
		tostring(standName or ""),
		tostring(reason or "unknown"),
		if detail and detail ~= "" then " " .. tostring(detail) else ""
	))
end

local function findAvailableTutorialPlacementReward(player, storageName)
	if not isActiveTutorialPlacementStep(player) then
		return nil, nil
	end

	local filters = {
		RequireAvailable = true,
	}
	storageName = tostring(storageName or "")
	if storageName ~= "" then
		filters.StorageName = storageName
	end

	return CrewInstanceService.FindTutorialRewardInstance(player, filters)
end

standDebug("script init")

local function resetHugeIncomeOnJoin(player)
	if not DataManager then
		return
	end

	local ok, crewMemberIncome = pcall(function()
		return DataManager:GetValue(player, "CrewMemberIncome")
	end)

	if not ok or typeof(crewMemberIncome) ~= "table" then
		return
	end

	local changed = false

	for _, standData in pairs(crewMemberIncome) do
		if typeof(standData) == "table" then
			local income = standData.IncomeToCollect
			if typeof(income) == "number" and income >= MAX_INCOME_ON_JOIN then
				standData.IncomeToCollect = 0
				changed = true
			end
		end
	end

	if changed then
		local didSaveIncomeReset = pcall(function()
			for standName, standData in pairs(crewMemberIncome) do
				CrewStandIncomeAuthority.SetStandData(player, standName, standData, "income_join_cap_reset")
			end
		end)
		if didSaveIncomeReset then
			refreshCollectedIncomeShadow(player)
		end
	end
end


local function getVariantAndBaseName(fullName)
	fullName = tostring(fullName)

	for _, vKey in ipairs(VariantCfg.Order or {}) do
		if vKey ~= "Normal" then
			local v = (VariantCfg.Versions or {})[vKey]
			local prefix = tostring((v and v.Prefix) or (vKey .. " "))
			if prefix ~= "" and fullName:sub(1, #prefix) == prefix then
				local baseName = fullName:sub(#prefix + 1)
				return vKey, baseName, v
			end
		end
	end

	return "Normal", fullName, (VariantCfg.Versions or {}).Normal
end

local function resolveCanonicalCrewMemberId(itemName)
	local canonicalItemName, info = CrewCatalog.ResolveCanonicalCrewMemberId(itemName)
	if info then
		return canonicalItemName
	end
	return ""
end

local function findTemplateForName(crewMemberName)
	local canonicalName = resolveCanonicalCrewMemberId(crewMemberName)
	if canonicalName == "" then
		return nil
	end
	local variantKey, baseName = getVariantAndBaseName(canonicalName)

	local registryTemplate = CrewRegistry.GetTemplateWithFallback(baseName, variantKey)
	if registryTemplate and registryTemplate:IsA("Model") then
		return registryTemplate
	end

	registryTemplate = CrewRegistry.GetTemplateWithFallback(canonicalName, "Normal")
	if registryTemplate and registryTemplate:IsA("Model") then
		return registryTemplate
	end

	return nil
end

local function ensurePrimaryPart(model)
	if model.PrimaryPart and model.PrimaryPart:IsA("BasePart") then
		return model.PrimaryPart
	end
	local pp = model:FindFirstChildWhichIsA("BasePart", true)
	if pp then
		pcall(function()
			model.PrimaryPart = pp
		end)
	end
	return model.PrimaryPart or pp
end

local function anchorModel(model)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.AssemblyLinearVelocity = Vector3.zero
			d.AssemblyAngularVelocity = Vector3.zero
		end
	end
end

local function makeStandVisualNonBlocking(model)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.CanQuery = false
			d.CanCollide = false
		end
	end
end

local function tryPlayIdle(model, animId)
	animId = tonumber(animId)
	if not animId or animId == 0 then
		return
	end
	local controller = model:FindFirstChildOfClass("Humanoid") or model:FindFirstChildOfClass("AnimationController")
	if not controller then
		return
	end
	local animator = controller:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = controller
	end
	local anim = Instance.new("Animation")
	anim.AnimationId = "rbxassetid://" .. tostring(animId)
	pcall(function()
		local track = animator:LoadAnimation(anim)
		track.Looped = true
		track:Play()
	end)
end

local function getStandCollectMultiplier(player, standName)
	local crewMemberName = getPlayerStandCrewMemberName(player, standName)
	local crewMemberInstanceId = getPlayerStandCrewMemberInstanceId(player, standName)
	local lvl
	if crewMemberName ~= "" then
		lvl = getCrewMemberLevel(player, crewMemberInstanceId ~= "" and crewMemberInstanceId or crewMemberName)
		if CrewStandIncomeAuthority.GetStandLevel(player, standName) ~= lvl then
			CrewStandIncomeAuthority.SetStandLevel(player, standName, lvl, "stand_collect_multiplier_level_sync")
		end
	else
		lvl = CrewStandIncomeAuthority.GetStandLevel(player, standName)
	end
	if lvl < 1 then
		lvl = 1
	end

	local mult = tonumber(StandUpgradeMults[tostring(lvl)]) or 1
	if mult <= 0 then
		mult = 1
	end
	local rebirthCount = 0

	local leaderstats = player:FindFirstChild("leaderstats")
	if leaderstats then
		local rebirthValue = leaderstats:FindFirstChild("Rebirths")
		if rebirthValue and rebirthValue:IsA("NumberValue") then
			rebirthCount = math.max(0, math.floor(tonumber(rebirthValue.Value) or 0))
		else
			local storedRebirths = dmGet(player, "leaderstats.Rebirths")
			if typeof(storedRebirths) == "number" then
				rebirthCount = math.max(0, math.floor(storedRebirths))
			end
		end
	else
		local storedRebirths = dmGet(player, "leaderstats.Rebirths")
		if typeof(storedRebirths) == "number" then
			rebirthCount = math.max(0, math.floor(storedRebirths))
		end
	end

	return mult * RebirthConfig.GetShipIncomeMultiplier(rebirthCount)
end

local function getBeliBoostRemaining(player)
	local potions = player and player:FindFirstChild("Potions")
	local timeValue = potions and potions:FindFirstChild("x2MoneyTime")
	if timeValue and timeValue:IsA("NumberValue") then
		return math.max(0, tonumber(timeValue.Value) or 0)
	end

	local storedTime = dmGet(player, "Potions.x2MoneyTime")
	return math.max(0, tonumber(storedTime) or 0)
end

local function isBeliBoostActive(player)
	return getBeliBoostRemaining(player) > 0
end

local function getBeliBoostMultiplier(player)
	return if isBeliBoostActive(player) then 2 else 1
end

 
local function getToolCrewMemberInstanceId(tool)
	if not tool or not tool:IsA("Tool") then
		return ""
	end
	return tostring(tool:GetAttribute("CrewMemberInstanceId") or tool:GetAttribute("CrewInstanceId") or "")
end

local function getAvailableInstanceIdForEquippedName(player, crewMemberName)
	crewMemberName = tostring(crewMemberName or "")
	if crewMemberName == "" then
		return ""
	end

	local ok, crewInventory = pcall(function()
		return CrewInstanceService.GetCrewInventory(player)
	end)
	if not ok or typeof(crewInventory) ~= "table" or typeof(crewInventory.ById) ~= "table" then
		return ""
	end

	local matchedInstanceId = ""
	local matchCount = 0
	for instanceId, instanceData in pairs(crewInventory.ById) do
		if
			typeof(instanceData) == "table"
			and tostring(instanceData.CrewMemberId or instanceData.StorageName or "") == crewMemberName
			and tostring(instanceData.AssignedStand or "") == ""
		then
			matchedInstanceId = tostring(instanceId)
			matchCount += 1
			if matchCount > 1 then
				return ""
			end
		end
	end

	return if matchCount == 1 then matchedInstanceId else ""
end

local function getEquippedCrewMemberToolInfo(player)
	local char = player.Character
	if not char then
		return nil
	end
	for _, c in ipairs(char:GetChildren()) do
		if c:IsA("Tool") then
			local itemKind = c:GetAttribute("InventoryItemKind")
			if typeof(itemKind) == "string" and itemKind ~= "" and itemKind ~= CREW_ITEM_KIND then
				continue
			end

			local rawName = c:GetAttribute("InvItem") or c:GetAttribute("InventoryItemName") or c.Name
			local canonicalName, info = CrewCatalog.ResolveCanonicalCrewMemberId(rawName)
			if info then
				local instanceId = getToolCrewMemberInstanceId(c)
				if instanceId == "" then
					instanceId = getAvailableInstanceIdForEquippedName(player, canonicalName)
					if instanceId ~= "" then
						c:SetAttribute("CrewMemberInstanceId", instanceId)
						c:SetAttribute("CrewInstanceId", instanceId)
					end
				end

				return {
					Tool = c,
					Name = canonicalName,
					InstanceId = instanceId,
					HasExactInstanceId = instanceId ~= "",
				}
			end
		end
	end
	return nil
end

local function getInventoryQuantity(player, itemName)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return 0
	end
	itemName = tostring(itemName or "")
	if itemName == "" then
		return 0
	end
	itemName = resolveCanonicalCrewMemberId(itemName)
	if itemName == "" then
		return 0
	end

	local ok, crewInventory = pcall(function()
		return CrewInstanceService.GetCrewInventory(player)
	end)
	if not ok or typeof(crewInventory) ~= "table" or typeof(crewInventory.ById) ~= "table" then
		return 0
	end

	local count = 0
	for _, instanceData in pairs(crewInventory.ById) do
		if
			typeof(instanceData) == "table"
			and tostring(instanceData.CrewMemberId or instanceData.StorageName or "") == itemName
			and tostring(instanceData.AssignedStand or "") == ""
		then
			count += 1
		end
	end
	return count
end

dmGet = function(player, path)
	if not DataManager then
		return nil
	end
	local ok, v = pcall(function()
		return DataManager:GetValue(player, path)
	end)
	if ok then
		return v
	end
	return nil
end

dmSet = function(player, path, value)
	if not DataManager then
		return false
	end
	local ok, result = pcall(function()
		DataManager:SetValue(player, path, value)
	end)
	return ok and result ~= false
end

local function getPlayerShipUpgradeLevel(player)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return 0
	end

	local hiddenLeaderstats = player:FindFirstChild("HiddenLeaderstats")
	if hiddenLeaderstats then
		local plotUpgradeValue = hiddenLeaderstats:FindFirstChild("PlotUpgrade")
		if plotUpgradeValue and plotUpgradeValue:IsA("NumberValue") then
			return PlotUpgradeConfig.ClampLevel(plotUpgradeValue.Value)
		end
	end

	local storedUpgrade = dmGet(player, "HiddenLeaderstats.PlotUpgrade")
	if typeof(storedUpgrade) == "number" then
		return PlotUpgradeConfig.ClampLevel(storedUpgrade)
	end

	return 0
end

local function getStandSlotState(player, standName)
	local upgradeLevel = getPlayerShipUpgradeLevel(player)
	local leaderstats = player:FindFirstChild("leaderstats")
	local rebirthValue = leaderstats and leaderstats:FindFirstChild("Rebirths")
	local rebirthCount = 0
	if rebirthValue and rebirthValue:IsA("NumberValue") then
		rebirthCount = math.max(0, math.floor(tonumber(rebirthValue.Value) or 0))
	else
		local storedRebirths = dmGet(player, "leaderstats.Rebirths")
		if typeof(storedRebirths) == "number" then
			rebirthCount = math.max(0, math.floor(storedRebirths))
		end
	end

	local isVisible = PlotUpgradeConfig.IsStandVisible(upgradeLevel, standName, rebirthCount)
	local isUsable = PlotUpgradeConfig.IsStandUsable(upgradeLevel, standName, rebirthCount)
	return {
		Level = upgradeLevel,
		Rebirths = rebirthCount,
		Visible = isVisible,
		Usable = isUsable,
		BonusInfo = nil,
		BonusPercent = 0,
		UnlockLevel = PlotUpgradeConfig.GetStandUnlockLevel(standName),
	}
end

local function getShipSlotsTable(player)
	local slots = dmGet(player, "Ship.Slots")
	if typeof(slots) ~= "table" then
		return {}
	end

	return slots
end

local function syncShipSlotAssignment(player, standName, slotData)
	local slots = getShipSlotsTable(player)
	if slotData == nil then
		slots[standName] = nil
	else
		slots[standName] = slotData
	end

	dmSet(player, "Ship.Slots", slots)
end

local function reconcileSlotAssignmentsForRender(player, activeShip, source)
	if CrewSlotAssignmentReconciler.IsResetInProgress(player) then
		return false, "reset_in_progress"
	end

	local ok, result, reasonOrSummary, maybeSummary = pcall(function()
		return CrewSlotAssignmentReconciler.ReconcilePlayer(player, {
			ActiveShip = activeShip,
			Source = source,
		})
	end)

	if not ok then
		warn(("[CrewIncomeRuntime] Slot assignment reconciliation errored for %s during %s: %s"):format(
			player and player.Name or "unknown",
			tostring(source),
			tostring(result)
		))
		return false, result
	end

	if result ~= true then
		local summary = maybeSummary or reasonOrSummary
		warn(("[CrewIncomeRuntime] Slot assignment reconciliation failed for %s during %s: %s"):format(
			player and player.Name or "unknown",
			tostring(source),
			tostring(summary)
		))
		return false, summary
	end

	return true, maybeSummary or reasonOrSummary
end

local function clearPlacedStandIncome(player, standName)
	if CrewStandIncomeAuthority.SetIncomeToCollect(player, standName, 0, "stand_income_clear") then
		refreshCollectedIncomeShadow(player)
	end
	syncShipSlotAssignment(player, standName, nil)
end

local function getPickupStandSnapshot(player, standName)
	local standData, standMeta = CrewStandIncomeAuthority.GetStandData(player, standName)
	local canonicalRow = if typeof(standMeta) == "table" then standMeta.CanonicalRow else nil
	local crewMemberName = tostring(standData and standData.CrewMemberName or "")
	local standCrewMemberInstanceId = tostring(standData and standData.CrewMemberInstanceId or "")
	local crewMemberInstanceId = tostring((canonicalRow and canonicalRow.CrewMemberInstanceId) or standCrewMemberInstanceId)
	local legacyStorageName = tostring((canonicalRow and canonicalRow.LegacyStorageName) or crewMemberName)
	local incomeToCollect = tonumber(standData and standData.IncomeToCollect) or 0
	local exists = typeof(standMeta) == "table" and standMeta.MissingCanonical ~= true

	return {
		Exists = exists,
		CrewMemberName = crewMemberName,
		CrewMemberInstanceId = crewMemberInstanceId,
		LegacyStorageName = legacyStorageName,
		IncomeToCollect = incomeToCollect,
		HasAssignment = crewMemberName ~= "" or crewMemberInstanceId ~= "" or legacyStorageName ~= "",
	}
end

local function getPickupDebugField(debugInfo, key, fallback)
	if typeof(debugInfo) == "table" and debugInfo[key] ~= nil then
		return debugInfo[key]
	end
	return fallback
end

local function dmEnsureStandFolder(player, standName)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return false
	end
	if typeof(standName) ~= "string" or standName == "" then
		return false
	end

	local playerCache = ensuredStandFolders[player]
	if playerCache and playerCache[standName] == true then
		return true
	end

	local ok = pcall(function()
		CrewStandIncomeAuthority.EnsureStandRow(player, standName, "crew_member_income_shape_ensure")
	end)
	if not ok then
		return false
	end

	playerCache = ensuredStandFolders[player]
	if not playerCache then
		playerCache = {}
		ensuredStandFolders[player] = playerCache
	end
	playerCache[standName] = true

	return true
end


getPlayerStandCrewMemberName = function(player, standName)
	dmEnsureStandFolder(player, standName)
	local standData = CrewStandIncomeAuthority.GetStandData(player, standName)
	local v = standData and standData.CrewMemberName
	if typeof(v) ~= "string" then
		return ""
	end
	return v
end

getPlayerStandCrewMemberInstanceId = function(player, standName)
	dmEnsureStandFolder(player, standName)

	local standCrewMemberName = getPlayerStandCrewMemberName(player, standName)
	if standCrewMemberName == "" then
		return ""
	end

	local instanceId = CrewInstanceService.GetStandInstanceId(player, standName)
	if instanceId ~= "" then
		return instanceId
	end

	local ensuredInstanceId = CrewInstanceService.EnsureStandInstance(player, standName, standCrewMemberName)
	return tostring(ensuredInstanceId or "")
end

local function getPlayerStandIncome(player, standName)
	dmEnsureStandFolder(player, standName)
	local standData = CrewStandIncomeAuthority.GetStandData(player, standName)
	local v = standData and standData.IncomeToCollect
	if typeof(v) ~= "number" then
		return 0
	end
	return v
end

local function findCatalogInfoByName(crewMemberName)
	local crewInfo, crewId = CrewCatalog.FindInfoByName(crewMemberName)
	if crewInfo then
		return crewInfo, crewId
	end

	return nil, nil
end

local function hasInventoryCrewMemberEntry(player, itemName)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return false
	end

	if typeof(itemName) ~= "string" or itemName == "" then
		return false
	end
	local canonicalItemName = resolveCanonicalCrewMemberId(itemName)
	if canonicalItemName == "" then
		return false
	end

	local crewInventory = CrewInstanceService.GetCrewInventory(player)
	if typeof(crewInventory) == "table" and typeof(crewInventory.ById) == "table" then
		for _, instanceData in pairs(crewInventory.ById) do
			if typeof(instanceData) == "table"
				and (
					tostring(instanceData.CrewMemberId or instanceData.StorageName or "") == canonicalItemName
					or tostring(instanceData.LegacyStorageName or "") == itemName
				)
			then
				return true
			end
		end
	end

	return false
end

local function getInventoryCrewMemberMetadata(player, itemName)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return nil, nil
	end

	if typeof(itemName) ~= "string" or itemName == "" then
		return nil, nil
	end
	local canonicalItemName = resolveCanonicalCrewMemberId(itemName)
	if canonicalItemName == "" then
		return nil, nil
	end

	local crewInventory = CrewInstanceService.GetCrewInventory(player)
	if typeof(crewInventory) == "table" and typeof(crewInventory.ById) == "table" then
		for _, instanceData in pairs(crewInventory.ById) do
			if typeof(instanceData) == "table"
				and (
					tostring(instanceData.CrewMemberId or instanceData.StorageName or "") == canonicalItemName
					or tostring(instanceData.LegacyStorageName or "") == itemName
				)
			then
				local baseName = tostring(instanceData.BaseName or "")
				local variantKey = tostring(instanceData.Variant or "")
				if baseName ~= "" then
					if variantKey == "" then
						variantKey = "Normal"
					end
					return variantKey, baseName
				end
			end
		end
	end

	return nil, nil
end

local function clearCrewRecordCache(player)
	if player ~= nil then
		crewRecordCache[player] = nil
		return
	end

	for cachedPlayer in pairs(crewRecordCache) do
		crewRecordCache[cachedPlayer] = nil
	end
end

local function readCachedCrewRecord(player, rawName)
	local playerCache = crewRecordCache[player]
	if playerCache == nil then
		return nil, false
	end

	local cached = playerCache[rawName]
	if cached == nil then
		return nil, false
	end
	if cached == false then
		return nil, true
	end
	return cached, true
end

local function writeCachedCrewRecord(player, rawName, record)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return record
	end

	local playerCache = crewRecordCache[player]
	if playerCache == nil then
		playerCache = {}
		crewRecordCache[player] = playerCache
	end
	playerCache[rawName] = record or false
	return record
end

local function resolveCrewMemberRecord(player, crewMemberName)
	local rawName = tostring(crewMemberName or "")
	if rawName == "" then
		return nil
	end

	local cachedRecord, foundCachedRecord = readCachedCrewRecord(player, rawName)
	if foundCachedRecord then
		return cachedRecord
	end

	local candidates = {}
	local seen = {}

	local function pushCandidate(itemName)
		if typeof(itemName) ~= "string" or itemName == "" or seen[itemName] then
			return
		end
		seen[itemName] = true
		table.insert(candidates, itemName)
	end

	pushCandidate(rawName)
	pushCandidate(resolveCanonicalCrewMemberId(rawName))

	local invVariant, invBase = getInventoryCrewMemberMetadata(player, rawName)
	if invBase then
		pushCandidate(CrewRegistry.MakeVariantId(invBase, invVariant))
	end

	local parsedVariant, parsedBase = getVariantAndBaseName(rawName)
	pushCandidate(CrewRegistry.MakeVariantId(parsedBase, parsedVariant))
	pushCandidate(parsedBase)

	local legacyInfo, legacyId = findCatalogInfoByName(rawName)
	if legacyId then
		pushCandidate(legacyId)
	end

	for _, candidateName in ipairs(candidates) do
		candidateName = resolveCanonicalCrewMemberId(candidateName)
		if candidateName == "" then
			continue
		end
		local variantKey, baseName = getVariantAndBaseName(candidateName)
		local template, usedVariant = CrewRegistry.GetTemplateWithFallback(baseName, variantKey)
		local finalVariant = usedVariant or variantKey or "Normal"
		local info = CrewRegistry.GetOrBuildVariantInfo(baseName, finalVariant)

		if template or info then
			local canonicalName = CrewRegistry.MakeVariantId(baseName, finalVariant)
			local storageName = rawName

				if hasInventoryCrewMemberEntry(player, candidateName) then
					storageName = candidateName
				elseif hasInventoryCrewMemberEntry(player, canonicalName) or not hasInventoryCrewMemberEntry(player, rawName) then
					storageName = canonicalName
				end

			return writeCachedCrewRecord(player, rawName, {
				RawName = rawName,
				CanonicalName = canonicalName,
				StorageName = storageName,
				BaseName = baseName,
				VariantKey = finalVariant,
				Template = template,
				Info = info or legacyInfo,
			})
		end
	end

	if legacyInfo then
		return writeCachedCrewRecord(player, rawName, {
			RawName = rawName,
			CanonicalName = tostring(legacyId or rawName),
			StorageName = hasInventoryCrewMemberEntry(player, rawName) and rawName or tostring(legacyId or rawName),
			BaseName = tostring(legacyId or rawName),
			VariantKey = parsedVariant,
			Template = findTemplateForName(tostring(legacyId or rawName)),
			Info = legacyInfo,
		})
	end

	return writeCachedCrewRecord(player, rawName, nil)
end

local function findCrewMemberInfoByName(crewMemberName, player)
	local resolved = resolveCrewMemberRecord(player, crewMemberName)
	if resolved and resolved.Info then
		return resolved.Info, resolved.CanonicalName
	end

	return findCatalogInfoByName(crewMemberName)
end

local function getLegacyStandStatusDisplayName(player, crewMemberName)
	local resolved = resolveCrewMemberRecord(player, crewMemberName)
	local info = resolved and resolved.Info or findCrewMemberInfoByName(crewMemberName, player)
	return info and tostring(info.Name or info.DisplayName or resolved and resolved.CanonicalName or crewMemberName)
		or tostring(crewMemberName)
end

local function resolveStandStatusDisplayName(player, crewMemberName)
	local fallbackDisplayName = getLegacyStandStatusDisplayName(player, crewMemberName)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return fallbackDisplayName, nil
	end

	local gate = getCrewMemberCanonicalReadGate()
	if typeof(gate) ~= "table" or typeof(gate.ResolveStandStatusDisplayName) ~= "function" then
		return fallbackDisplayName, nil
	end

	local ok, value, result = pcall(function()
		return gate.ResolveStandStatusDisplayName(player, crewMemberName, {
			Player = player,
			SkipLog = true,
		})
	end)
	if not ok then
		if DEBUG_TRACE then
			warn(string.format(
				"[CrewMemberStandStatusHelper] fallback player=%s item=%s reason=%s",
				player.Name,
				tostring(crewMemberName),
				tostring(value)
			))
		end
		return fallbackDisplayName, nil
	end

	local displayName = tostring(value or "")
	if displayName == "" then
		return fallbackDisplayName, result
	end

	return displayName, result
end

local function resolveIncomeStatusReadAuthorityDisplayName(player, standName)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return nil, nil
	end

	local gate = getCrewMemberCanonicalReadGate()
	if typeof(gate) ~= "table" or typeof(gate.ResolveIncomeStatusReadAuthority) ~= "function" then
		return nil, nil
	end

	local ok, _, result = pcall(function()
		return gate.ResolveIncomeStatusReadAuthority(player, standName, {
			Player = player,
			SkipLog = true,
		})
	end)
	if not ok or typeof(result) ~= "table" then
		if DEBUG_TRACE then
			warn(string.format(
				"[CrewMemberIncomeStatusReadAuthority] fallback player=%s stand=%s reason=%s",
				player.Name,
				tostring(standName),
				tostring(_)
			))
		end
		return nil, nil
	end

	local fallbackReason = tostring(result.FallbackReason or "")
	local readGateReason = tostring(result.ReadGateReason or "")
	local readAuthorityDisabled = fallbackReason == "read_authority_disabled"
		or fallbackReason == "income_status_read_authority_disabled"
		or readGateReason == "read_authority_disabled"
		or readGateReason == "income_status_read_authority_disabled"
	if readAuthorityDisabled then
		return nil, nil
	end

	local displayName = tostring(result.DisplayName or "")
	if displayName == "" then
		return nil, result
	end
	return displayName, result
end

local function resolveIncomeStatusDisplayName(player, standName, crewMemberName)
	local fallbackDisplayName = getLegacyStandStatusDisplayName(player, crewMemberName)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return fallbackDisplayName, nil
	end

	if tostring(standName or "") ~= "" then
		local authorityDisplayName, authorityResult = resolveIncomeStatusReadAuthorityDisplayName(player, standName)
		if authorityResult ~= nil then
			return authorityDisplayName or fallbackDisplayName, authorityResult
		end
	end

	local gate = getCrewMemberCanonicalReadGate()
	if typeof(gate) ~= "table" or typeof(gate.ResolveIncomeStatusDisplayName) ~= "function" then
		return fallbackDisplayName, nil
	end

	local ok, value, result = pcall(function()
		return gate.ResolveIncomeStatusDisplayName(player, crewMemberName, {
			Player = player,
			SkipLog = true,
		})
	end)
	if not ok then
		if DEBUG_TRACE then
			warn(string.format(
				"[CrewMemberIncomeStatusHelper] fallback player=%s item=%s reason=%s",
				player.Name,
				tostring(crewMemberName),
				tostring(value)
			))
		end
		return fallbackDisplayName, nil
	end

	local displayName = tostring(value or "")
	if displayName == "" then
		return fallbackDisplayName, result
	end

	return displayName, result
end

local function resolveIncomeToastDisplayName(player, crewMemberName)
	local fallbackDisplayName = getLegacyStandStatusDisplayName(player, crewMemberName)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return fallbackDisplayName, nil
	end

	local gate = getCrewMemberCanonicalReadGate()
	if typeof(gate) ~= "table" or typeof(gate.ResolveIncomeToastDisplayName) ~= "function" then
		return fallbackDisplayName, nil
	end

	local ok, value, result = pcall(function()
		return gate.ResolveIncomeToastDisplayName(player, crewMemberName, {
			Player = player,
			SkipLog = true,
		})
	end)
	if not ok then
		if DEBUG_TRACE then
			warn(string.format(
				"[CrewMemberIncomeToastHelper] fallback player=%s item=%s reason=%s",
				player.Name,
				tostring(crewMemberName),
				tostring(value)
			))
		end
		return fallbackDisplayName, nil
	end

	local displayName = tostring(value or "")
	if displayName == "" then
		return fallbackDisplayName, result
	end

	return displayName, result
end

local function buildIncomeToastDisplayPayload(player, crewMemberName)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return nil
	end

	local legacyIdentity = tostring(crewMemberName or "")
	if legacyIdentity == "" then
		return nil
	end

	local gate = getCrewMemberCanonicalReadGate()
	if typeof(gate) ~= "table" or typeof(gate.GetFlags) ~= "function" then
		return nil
	end

	local flags = gate.GetFlags()
	if flags.CrewMemberCanaryGameplayHelperReadsEnabled ~= true
		or flags.CrewMemberCanaryIncomeToastHelperReadEnabled ~= true
		or flags.CrewMemberCanaryGameplayReadsEnabled == true
		or flags.CrewMemberCanonicalReadEnabled == true
	then
		return nil
	end

	local fallbackDisplayName = getLegacyStandStatusDisplayName(player, legacyIdentity)
	local displayName, result = resolveIncomeToastDisplayName(player, legacyIdentity)
	if typeof(result) ~= "table" then
		return {
			DisplayName = tostring(fallbackDisplayName or legacyIdentity),
			LegacyIdentity = legacyIdentity,
			UsedCanonical = false,
			FallbackReason = "helper_result_missing",
			Path = "gameplay.helper.income_toast_display_name",
			IsAuthoritative = false,
		}
	end

	return {
		DisplayName = tostring(displayName or fallbackDisplayName or legacyIdentity),
		LegacyIdentity = tostring(result.LegacyIdentity or legacyIdentity),
		UsedCanonical = result.UsedCanonical == true,
		FallbackReason = result.FallbackReason,
		Path = tostring(result.Path or "gameplay.helper.income_toast_display_name"),
		IsAuthoritative = false,
	}
end

local function buildIncomeStatusDisplayDescriptor(result, fallbackDisplayName, crewMemberName)
	if typeof(result) ~= "table" then
		return {
			DisplayName = tostring(fallbackDisplayName or crewMemberName or ""),
			UsedCanonical = false,
			FallbackReason = "helper_result_missing",
			LegacyIdentity = tostring(crewMemberName or ""),
			IsAuthoritative = false,
			Path = "gameplay.helper.income_status_display_name",
		}
	end

	return {
		DisplayName = tostring(result.DisplayName or result.Value or fallbackDisplayName or crewMemberName or ""),
		UsedCanonical = result.UsedCanonical == true,
		FallbackReason = result.FallbackReason,
		LegacyValue = result.LegacyValue,
		CanonicalValue = result.CanonicalValue,
		LegacyIdentity = tostring(result.LegacyIdentity or crewMemberName or ""),
		Path = tostring(result.Path or "gameplay.helper.income_status_display_name"),
		IsAuthoritative = result.IsAuthoritative == true,
		IsAuthoritativeRead = result.IsAuthoritativeRead == true,
		IsMutationAuthority = result.IsMutationAuthority == true,
		Source = result.Source,
		AuthorityMode = result.AuthorityMode,
		ValidationAgeSeconds = tonumber(result.ValidationAgeSeconds) or -1,
	}
end

local buildIncomeSnapshot

local function buildIncomeStatusDisplayMetadataResponse(player)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return {
			Ready = false,
			Reason = "invalid_player",
			Metadata = {},
		}
	end
	if not DataManager then
		return {
			Ready = false,
			Reason = "data_manager_unavailable",
			Metadata = {},
		}
	end

	local ok, crewMemberIncome = pcall(function()
		return DataManager:GetValue(player, "CrewMemberIncome")
	end)
	if not ok or typeof(crewMemberIncome) ~= "table" then
		return {
			Ready = false,
			Reason = "income_unavailable",
			Metadata = {},
		}
	end

	local metadataByStand = {}
	local standNames = {}
	for standName in pairs(crewMemberIncome) do
		standNames[#standNames + 1] = tostring(standName)
	end
	table.sort(standNames)

	local canonicalCount = 0
	local fallbackReasons = {}
	for _, standName in ipairs(standNames) do
		local standData = crewMemberIncome[standName]
		local crewMemberName = if typeof(standData) == "table"
			then tostring(standData.LegacyStorageName or standData.CrewMemberName or "")
			else ""
		if crewMemberName ~= "" then
			local displayName, result = resolveIncomeStatusDisplayName(player, standName, crewMemberName)
			local descriptor = buildIncomeStatusDisplayDescriptor(result, displayName, crewMemberName)
			metadataByStand[standName] = descriptor
			if descriptor.UsedCanonical == true then
				canonicalCount += 1
			elseif descriptor.FallbackReason ~= nil then
				local reason = tostring(descriptor.FallbackReason)
				fallbackReasons[reason] = (fallbackReasons[reason] or 0) + 1
			end
		end
	end

	return {
		Ready = true,
		CacheSeconds = INCOME_STATUS_DISPLAY_METADATA_CACHE_SECONDS,
		IncomeSnapshotCacheSeconds = 1,
		Metadata = metadataByStand,
		IncomeSnapshot = if typeof(buildIncomeSnapshot) == "function" then buildIncomeSnapshot(player) else {},
		CanonicalValues = canonicalCount,
		FallbackReasons = fallbackReasons,
	}
end

incomeStatusDisplayMetadataRequest.OnServerInvoke = function(player)
	return buildIncomeStatusDisplayMetadataResponse(player)
end

local function getStealProductIdForCrewMember(crewMemberName)
	local info = findCrewMemberInfoByName(crewMemberName)
	local rarity = info and info.Rarity or "Common"
	local fixed = normalizeRarity(rarity)
	return STEAL_PRODUCT_BY_RARITY[fixed] or 3512126073
end

local getSlotRuntime

local function updateStandPromptTexts(player, standModel, cache, slotState, crewMemberName, equippedCrewMember)
	if typeof(standModel) ~= "Instance" or not standModel:IsA("Model") then
		return
	end

	cache = cache or getSlotRuntime(player, standModel.Parent, standModel)
	local prompt = cache and cache.Prompt
	if not prompt then
		return
	end

	local standName = standModel.Name
	slotState = slotState or (player and player:IsA("Player") and getStandSlotState(player, standName) or nil)
	local hasCrewMemberName = crewMemberName ~= nil
	crewMemberName = crewMemberName or ""

	if player and player:IsA("Player") then
		if not hasCrewMemberName then
			crewMemberName = getPlayerStandCrewMemberName(player, standName)
		end
		if equippedCrewMember == nil then
			equippedCrewMember = getEquippedCrewMemberToolInfo(player)
		end
	end

	local objectText
	local actionText

	if slotState and slotState.Visible and not slotState.Usable then
		objectText = "Slot Locked"
		actionText = PlotUpgradeConfig.GetLockedSlotDescription(slotState.Level, standName, slotState.Rebirths) or "Upgrade Ship"
	elseif crewMemberName ~= "" then
		local displayName = resolveStandStatusDisplayName(player, crewMemberName)
		if slotState and slotState.BonusInfo then
			objectText = string.format(
				"%s (%s +%d%%)",
				displayName,
				tostring(slotState.BonusInfo.Label or "Bonus"),
				slotState.BonusPercent
			)
		else
			objectText = displayName
		end
		actionText = if equippedCrewMember then "Switch" else "Pick Up"
	elseif slotState and slotState.BonusInfo then
		objectText = tostring(slotState.BonusInfo.Label or standName)
		actionText = if equippedCrewMember
			then string.format("Place Here (+%d%%)", slotState.BonusPercent)
			else "Empty Slot"
	else
		objectText = tostring(standName)
		actionText = if equippedCrewMember then "Place Here" else "Empty Slot"
	end

	if cache.LastPromptObjectText ~= objectText then
		prompt.ObjectText = objectText
		cache.LastPromptObjectText = objectText
	end
	if cache.LastPromptActionText ~= actionText then
		prompt.ActionText = actionText
		cache.LastPromptActionText = actionText
	end
end

getCrewMemberLevel = function(player, crewMemberName)
	local progress = CrewFoodProgression.GetProgress(player, crewMemberName)
	if not progress then
		return 1
	end
	return progress.Level
end

local function getBaseIncome(player, crewMemberName)
	local resolved = resolveCrewMemberRecord(player, crewMemberName)
	local info = resolved and resolved.Info or findCrewMemberInfoByName(crewMemberName, player)
	local base = info and (tonumber(info.Income) or 0) or 0
	return base
end

local function getIncomeWithLevel(player, crewMemberName)
	local base = getBaseIncome(player, crewMemberName)
	if base <= 0 then
		return 0
	end
	local mult =1
	return base * mult
end

local function getStandIncomeDisplay(player, standName)
	standDebug("getStandIncomeDisplay begin player=%s stand=%s", player.Name, standName)
	local base = getPlayerStandIncome(player, standName)
	if base <= 0 then
		standDebug("getStandIncomeDisplay early_zero player=%s stand=%s", player.Name, standName)
		return 0
	end
	local display = IncomeClaimMath.GetWholeClaimableAmount(base, getStandCollectMultiplier(player, standName))
	standDebug("getStandIncomeDisplay done player=%s stand=%s base=%s display=%s", player.Name, standName, tostring(base), tostring(display))
	return display
end

local function getStandIncomePerSecond(player, standName, crewMemberName)
	return getIncomeWithLevel(player, crewMemberName) * getStandCollectMultiplier(player, standName) * getBeliBoostMultiplier(player)
end

local function normalizeIncomeSnapshotSlotKey(value)
	local numeric = tonumber(value)
	if not numeric or numeric ~= numeric or numeric == math.huge or numeric == -math.huge then
		return nil
	end

	numeric = math.floor(numeric)
	if numeric < 1 then
		return nil
	end

	return tostring(numeric)
end

buildIncomeSnapshot = function(player)
	local snapshot = {
		Stands = {},
		Captain = nil,
		TotalClaimReadyAmount = 0,
		CaptainLog = {
			Rows = {},
			PlacedCount = 0,
			TotalCount = 0,
			TotalClaimReadyAmount = 0,
			TotalIncomePerSecond = 0,
		},
	}

	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return snapshot
	end

	local captainLog = snapshot.CaptainLog
	local captainLogRows = captainLog.Rows
	local function appendCaptainLogRow(row, insertFirst)
		if typeof(row) ~= "table" then
			return
		end

		if insertFirst == true then
			table.insert(captainLogRows, 1, row)
		else
			captainLogRows[#captainLogRows + 1] = row
		end
		captainLog.PlacedCount += 1
		captainLog.TotalCount = captainLog.PlacedCount
		captainLog.TotalClaimReadyAmount += math.max(0, math.floor(tonumber(row.ClaimReadyAmount) or 0))
		captainLog.TotalIncomePerSecond += math.max(0, tonumber(row.IncomePerSecond) or 0)
	end

	local standNames = {}
	for standName, standData in pairs(CrewStandIncomeAuthority.GetAllStandData(player)) do
		local slotKey = normalizeIncomeSnapshotSlotKey(standName)
		local crewMemberName = if typeof(standData) == "table" then tostring(standData.CrewMemberName or "") else ""
		if slotKey and crewMemberName ~= "" then
			standNames[#standNames + 1] = slotKey
		end
	end
	table.sort(standNames, function(a, b)
		return (tonumber(a) or 0) < (tonumber(b) or 0)
	end)

	for _, standName in ipairs(standNames) do
		local standData = CrewStandIncomeAuthority.GetStandData(player, standName)
		local crewMemberName = tostring(standData and standData.CrewMemberName or "")
		if crewMemberName ~= "" then
			local rawIncomeToCollect = math.max(0, tonumber(standData.IncomeToCollect) or 0)
			local collectMultiplier = getStandCollectMultiplier(player, standName)
			local claimReadyAmount, exactClaimReadyAmount =
				IncomeClaimMath.GetWholeClaimableAmount(rawIncomeToCollect, collectMultiplier)
			local incomePerSecond = math.max(0, getStandIncomePerSecond(player, standName, crewMemberName))

			snapshot.Stands[standName] = {
				SlotKey = standName,
				CrewMemberName = crewMemberName,
				CrewMemberInstanceId = tostring(standData.CrewMemberInstanceId or ""),
				StandLevel = math.max(1, math.floor(tonumber(standData.StandLevel) or 1)),
				RawIncomeToCollect = rawIncomeToCollect,
				CollectMultiplier = collectMultiplier,
				IncomePerSecond = incomePerSecond,
				ExactClaimReadyAmount = exactClaimReadyAmount,
				ClaimReadyAmount = claimReadyAmount,
				ClaimRemainderAmount = math.max(0, exactClaimReadyAmount - claimReadyAmount),
			}
			snapshot.TotalClaimReadyAmount += claimReadyAmount
			appendCaptainLogRow({
				Key = standName,
				RowType = "Normal",
				SlotKey = standName,
				StandName = standName,
				CrewMemberName = crewMemberName,
				CrewMemberInstanceId = tostring(standData.CrewMemberInstanceId or ""),
				StandLevel = math.max(1, math.floor(tonumber(standData.StandLevel) or 1)),
				RawIncomeToCollect = rawIncomeToCollect,
				CollectMultiplier = collectMultiplier,
				IncomePerSecond = incomePerSecond,
				ExactClaimReadyAmount = exactClaimReadyAmount,
				ClaimReadyAmount = claimReadyAmount,
				ClaimRemainderAmount = math.max(0, exactClaimReadyAmount - claimReadyAmount),
			})
		end
	end

	local captainAssignment = CaptainSlotRuntime.GetAssignment(player)
	if typeof(captainAssignment) == "table" then
		local rawCaptainIncome = math.max(0, tonumber(captainAssignment.IncomeToCollect) or 0)
		local captainCollectMultiplier = math.max(0, CaptainSlotRuntime.GetCaptainCollectMultiplier(player))
		local captainClaimReady, captainExactClaimReady =
			IncomeClaimMath.GetWholeClaimableAmount(rawCaptainIncome, captainCollectMultiplier)
		local captainIncomePerSecond = math.max(0, CaptainSlotRuntime.GetCaptainIncomePerSecond(player))
		local captainCrewMemberName = tostring(
			captainAssignment.CrewMemberName
				or captainAssignment.CrewMemberId
				or captainAssignment.StorageName
				or captainAssignment.LegacyStorageName
				or ""
		)
		local captainCrewMemberInstanceId = tostring(
			captainAssignment.CrewMemberInstanceId
				or captainAssignment.InstanceId
				or captainAssignment.CrewInstanceId
				or ""
		)
		local captainStandLevel = math.max(
			1,
			math.floor(tonumber(captainAssignment.Level or captainAssignment.StandLevel) or 1)
		)
		if captainCrewMemberName ~= "" then
			snapshot.Captain = {
				SlotKey = CAPTAIN_SLOT_KEY,
				CrewMemberName = captainCrewMemberName,
				CrewMemberInstanceId = captainCrewMemberInstanceId,
				StandLevel = captainStandLevel,
				RawIncomeToCollect = rawCaptainIncome,
				CollectMultiplier = captainCollectMultiplier,
				IncomePerSecond = captainIncomePerSecond,
				ExactClaimReadyAmount = captainExactClaimReady,
				ClaimReadyAmount = captainClaimReady,
				ClaimRemainderAmount = math.max(0, captainExactClaimReady - captainClaimReady),
			}
			snapshot.TotalClaimReadyAmount += captainClaimReady
			appendCaptainLogRow({
				Key = CAPTAIN_SLOT_KEY,
				RowType = "Captain",
				SlotKey = CAPTAIN_SLOT_KEY,
				StandName = "Captain's Spot",
				CrewMemberName = captainCrewMemberName,
				CrewMemberInstanceId = captainCrewMemberInstanceId,
				StandLevel = captainStandLevel,
				RawIncomeToCollect = rawCaptainIncome,
				CollectMultiplier = captainCollectMultiplier,
				IncomePerSecond = captainIncomePerSecond,
				ExactClaimReadyAmount = captainExactClaimReady,
				ClaimReadyAmount = captainClaimReady,
				ClaimRemainderAmount = math.max(0, captainExactClaimReady - captainClaimReady),
			}, true)
		end
	end

	return snapshot
end

local function getTextTarget(root, name)
	local obj = root:FindFirstChild(name, true)
	if not obj then
		return nil
	end
	if obj:IsA("TextLabel") or obj:IsA("TextButton") or obj:IsA("TextBox") then
		return obj
	end
	return obj:FindFirstChildWhichIsA("TextLabel", true) or obj:FindFirstChildWhichIsA("TextButton", true) or obj:FindFirstChildWhichIsA("TextBox", true)
end

local SLOT_LEVEL_UI_REFRESH_INTERVAL_SECONDS = 5
local slotRuntimeByStand = setmetatable({}, { __mode = "k" })

local function isLiveInstance(instance)
	return typeof(instance) == "Instance" and instance.Parent ~= nil
end

local function resolveSlotHandle(standModel)
	local handle = standModel and standModel:FindFirstChild("Handle", true)
	return if handle and handle:IsA("BasePart") then handle else nil
end

local function resolveSlotLevelUpPart(standModel)
	local part = standModel and standModel:FindFirstChild("LevelUp", true)
	return if part and part:IsA("BasePart") then part else nil
end

local function resolvePlayerLevelUpSurfaceGui(player, slotKey, levelUpPart, allowPartFallback)
	if player and player:IsA("Player") then
		local playerGui = player:FindFirstChild("PlayerGui")
		if playerGui then
			if slotKey == CAPTAIN_SLOT_KEY then
				local captainGui = playerGui:FindFirstChild(CAPTAIN_RUNTIME_GUI_NAME)
				if
					captainGui
					and captainGui:IsA("SurfaceGui")
					and captainGui:GetAttribute(CAPTAIN_RUNTIME_GUI_ATTRIBUTE) == true
					and tostring(captainGui:GetAttribute(CAPTAIN_RUNTIME_GUI_SLOT_ATTRIBUTE) or CAPTAIN_SLOT_KEY) == CAPTAIN_SLOT_KEY
				then
					return captainGui
				end

				for _, child in ipairs(playerGui:GetChildren()) do
					if
						child:IsA("SurfaceGui")
						and child:GetAttribute(CAPTAIN_RUNTIME_GUI_ATTRIBUTE) == true
						and tostring(child:GetAttribute(CAPTAIN_RUNTIME_GUI_SLOT_ATTRIBUTE) or CAPTAIN_SLOT_KEY) == CAPTAIN_SLOT_KEY
					then
						return child
					end
				end

				return nil
			end

			local legacyGui = playerGui:FindFirstChild(slotKey)
			if legacyGui and legacyGui:IsA("SurfaceGui") then
				return legacyGui
			end

			local runtimeGuiName = ShipSlotGuiIdentity.GetRuntimeGuiName(slotKey)
			local runtimeGui = runtimeGuiName and playerGui:FindFirstChild(runtimeGuiName)
			if runtimeGui and runtimeGui:IsA("SurfaceGui") then
				return runtimeGui
			end

			for _, child in ipairs(playerGui:GetChildren()) do
				if child:IsA("SurfaceGui") and ShipSlotGuiIdentity.GetSlotKeyFromGui(child) == slotKey then
					return child
				end
			end
		end
	end

	if allowPartFallback and levelUpPart then
		return levelUpPart:FindFirstChildWhichIsA("SurfaceGui", true) or levelUpPart:FindFirstChild("SurfaceGui")
	end

	return nil
end

local function resolveLevelUpRefs(cache)
	local surfaceGui = cache.LevelUpSurfaceGui
	if not isLiveInstance(surfaceGui) or not surfaceGui:IsA("SurfaceGui") then
		return
	end

	local root = surfaceGui:FindFirstChild("LevelUp")
	if root and not root:IsA("GuiObject") then
		root = nil
	end

	local container = root or surfaceGui
	local main = container:FindFirstChild("Main", true) or container
	cache.LevelUpRoot = root
	cache.LevelUpMain = main
	cache.LevelUpPrice = getTextTarget(main, "Price")
	cache.LevelUpUpgrade = getTextTarget(main, "Upgarde") or getTextTarget(main, "Upgrade")
end

local function disconnectSlotRuntime(cache)
	if not cache or typeof(cache.Connections) ~= "table" then
		return
	end

	for _, connection in pairs(cache.Connections) do
		if connection and connection.Connected then
			connection:Disconnect()
		end
	end
	table.clear(cache.Connections)
	cache.PromptTriggeredConnection = nil
	cache.ZoneTouchedConnection = nil
end

local function resetSlotRenderState(cache)
	if cache then
		cache.LastMoneyText = nil
		cache.LastPromptActionText = nil
		cache.LastPromptObjectText = nil
		cache.LastLevelVisible = nil
		cache.LastLevelRootVisible = nil
		cache.LastLevelPriceText = nil
		cache.LastLevelUpgradeText = nil
		cache.LastLevelProgressKey = nil
		cache.NextLevelUiRefreshAt = 0
		cache.NextLevelUpLookupAt = nil
	end
end

local function cleanupSlotRuntime(standModel)
	local cache = slotRuntimeByStand[standModel]
	if not cache then
		return
	end

	disconnectSlotRuntime(cache)
	slotRuntimeByStand[standModel] = nil
end

local function buildSlotRuntime(player, plot, standModel)
	local slotKey = if ShipSlotService.IsCaptainSlotName(standModel.Name)
		then CAPTAIN_SLOT_KEY
		else tostring(standModel.Name)
	local handle = resolveSlotHandle(standModel)
	local levelUpPart = resolveSlotLevelUpPart(standModel)
	local allowLevelUpPartFallback = not ShipRuntimeService.IsActiveShip(standModel.Parent)
	local cache = {
		Player = player,
		Plot = plot,
		StandModel = standModel,
		SlotKey = slotKey,
		Handle = handle,
		Prompt = handle and handle:FindFirstChildOfClass("ProximityPrompt") or nil,
		ClaimHitBox = ShipSlotService.GetClaimHitBox(standModel),
		MoneyLabel = ShipSlotService.GetClaimMoneyLabel(standModel),
		LevelUpPart = levelUpPart,
		LevelUpSurfaceGui = resolvePlayerLevelUpSurfaceGui(player, slotKey, levelUpPart, allowLevelUpPartFallback),
		Connections = {},
		NextLevelUiRefreshAt = 0,
	}

	resolveLevelUpRefs(cache)
	slotRuntimeByStand[standModel] = cache
	return cache
end

function getSlotRuntime(player, plot, standModel)
	if typeof(standModel) ~= "Instance" or not standModel:IsA("Model") then
		return nil
	end

	local cache = slotRuntimeByStand[standModel]
	if
		cache
		and cache.Player == player
		and cache.StandModel == standModel
		and standModel.Parent ~= nil
	then
		if plot and cache.Plot == nil then
			cache.Plot = plot
		end
		return cache
	end

	if cache then
		cleanupSlotRuntime(standModel)
	end

	return buildSlotRuntime(player, plot or standModel.Parent, standModel)
end

local function getExistingSlotRuntime(standModel)
	return slotRuntimeByStand[standModel]
end

local function isLiveSlotDescendant(cache, instance)
	return cache
		and isLiveInstance(cache.StandModel)
		and isLiveInstance(instance)
		and instance:IsDescendantOf(cache.StandModel)
end

local function refreshSlotRuntimeRefs(cache)
	if not cache or not isLiveInstance(cache.StandModel) then
		return
	end

	local standModel = cache.StandModel
	if not isLiveSlotDescendant(cache, cache.Handle) then
		cache.Handle = resolveSlotHandle(standModel)
	end
	if cache.Handle and not isLiveSlotDescendant(cache, cache.Prompt) then
		cache.Prompt = cache.Handle:FindFirstChildOfClass("ProximityPrompt")
	end
	if not isLiveSlotDescendant(cache, cache.ClaimHitBox) then
		cache.ClaimHitBox = ShipSlotService.GetClaimHitBox(standModel)
	end
	if not isLiveSlotDescendant(cache, cache.MoneyLabel) then
		cache.MoneyLabel = ShipSlotService.GetClaimMoneyLabel(standModel)
		cache.LastMoneyText = nil
	end
	if not isLiveSlotDescendant(cache, cache.LevelUpPart) then
		cache.LevelUpPart = resolveSlotLevelUpPart(standModel)
	end
end

local function cleanupPlayerSlotRuntime(player)
	for standModel, cache in pairs(slotRuntimeByStand) do
		if cache.Player == player then
			cleanupSlotRuntime(standModel)
		end
	end
end

local function setTextIfChanged(cache, fieldName, label, text)
	if not cache then
		return
	end

	if not label or not label.Parent then
		return
	end

	text = tostring(text or "")
	if cache[fieldName] == text and label.Text == text then
		return
	end

	label.TextWrapped = true
	label.Text = text
	cache[fieldName] = text
end

local function setCachedLevelUpVisible(cache, visible)
	if not cache then
		return
	end

	local surfaceGui = cache.LevelUpSurfaceGui
	if surfaceGui and surfaceGui.Parent and (cache.LastLevelVisible ~= visible or surfaceGui.Enabled ~= visible) then
		surfaceGui.Enabled = visible
		cache.LastLevelVisible = visible
	end

	local root = cache.LevelUpRoot
	if root and root.Parent and (cache.LastLevelRootVisible ~= visible or root.Visible ~= visible) then
		root.Visible = visible
		cache.LastLevelRootVisible = visible
	end

	local clickDetector = cache.ClickDetector
	if clickDetector and clickDetector.Parent then
		local maxDistance = if visible then 15 else 0
		if clickDetector.MaxActivationDistance ~= maxDistance then
			clickDetector.MaxActivationDistance = maxDistance
		end
	end
end

local VariantOrder = { "Normal", "Golden", "Diamond" }
local VariantPrefix = {
	Normal = "",
	Golden = "Golden ",
	Diamond = "Diamond ",
}

local function startsWith(s, pref)
	return s:sub(1, #pref) == pref
end

local function detectVariant(text)
	text = tostring(text or "")
	for _, v in ipairs(VariantOrder) do
		if v ~= "Normal" then
			local pref = tostring(VariantPrefix[v] or (v .. " "))
			if pref ~= "" and startsWith(text, pref) then
				return v
			end
			local alt = v .. " "
			if startsWith(text, alt) then
				return v
			end
		end
	end
	return "Normal"
end

local function stripVariantPrefix(text, variantKey)
	text = tostring(text or "")
	if not variantKey or variantKey == "Normal" then
		return text
	end
	local pref = tostring(VariantPrefix[variantKey] or (variantKey .. " "))
	if pref ~= "" and startsWith(text, pref) then
		local out = text:sub(#pref + 1)
		if out ~= "" then
			return out
		end
	end
	local alt = variantKey .. " "
	if startsWith(text, alt) then
		local out = text:sub(#alt + 1)
		if out ~= "" then
			return out
		end
	end
	return text
end

local function setAttributeIfChanged(instance, attributeName, value)
	if instance:GetAttribute(attributeName) ~= value then
		instance:SetAttribute(attributeName, value)
	end
end

local function removeLegacyCrewHover(model)
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant.Name == "CrewMemberHover" and descendant:IsA("BillboardGui") then
			descendant:Destroy()
		end
	end
end

local function syncPlacedOverheadMetadata(player, standModel, crewMemberName, placedModel)
	if not placedModel or not placedModel:IsA("Model") then
		return
	end

	local resolved = resolveCrewMemberRecord(player, crewMemberName)
	local info = resolved and resolved.Info or findCrewMemberInfoByName(crewMemberName, player)
	local canonicalName = resolved and resolved.CanonicalName or tostring(crewMemberName)
	local rawName = info and tostring(info.Name or info.DisplayName or canonicalName) or tostring(crewMemberName)
	local rawRarity = info and tostring(info.Rarity or "") or "Common"
	local variantKey = resolved and resolved.VariantKey or detectVariant(crewMemberName)
	if variantKey == "Normal" then
		variantKey = detectVariant(rawName)
	end
	if variantKey == "Normal" then
		variantKey = detectVariant(rawRarity)
	end

	local displayName = stripVariantPrefix(rawName, variantKey)
	local helperDisplayName = resolveStandStatusDisplayName(player, crewMemberName)
	if helperDisplayName ~= "" then
		displayName = stripVariantPrefix(helperDisplayName, variantKey)
	end

	local displayRarity = stripVariantPrefix(rawRarity, variantKey)
	local isCaptainSlot = ShipSlotService.IsCaptainSlotName(standModel.Name)
	local incomePerSecond = if isCaptainSlot
		then CaptainSlotRuntime.GetCaptainIncomePerSecond(player)
		else getStandIncomePerSecond(player, standModel.Name, canonicalName)
	local slotState = if isCaptainSlot then nil else getStandSlotState(player, standModel.Name)
	local slotBonusInfo = slotState and slotState.BonusInfo or nil

	setAttributeIfChanged(placedModel, OVERHEAD_ATTRIBUTES.Kind, CrewOverhead.Kind.Placed)
	setAttributeIfChanged(placedModel, OVERHEAD_ATTRIBUTES.DisplayName, displayName)
	setAttributeIfChanged(placedModel, OVERHEAD_ATTRIBUTES.Rarity, if displayRarity ~= "" then displayRarity else "Common")
	setAttributeIfChanged(placedModel, OVERHEAD_ATTRIBUTES.Variant, variantKey)
	setAttributeIfChanged(placedModel, OVERHEAD_ATTRIBUTES.IncomePerSecond, math.max(0, incomePerSecond))
	setAttributeIfChanged(placedModel, OVERHEAD_ATTRIBUTES.BeliBoosted, isBeliBoostActive(player))
	setAttributeIfChanged(
		placedModel,
		OVERHEAD_ATTRIBUTES.SlotBonusLabel,
		if slotBonusInfo then tostring(slotBonusInfo.Label or "Bonus") else nil
	)
	setAttributeIfChanged(
		placedModel,
		OVERHEAD_ATTRIBUTES.SlotBonusPercent,
		if slotBonusInfo then math.max(0, slotState.BonusPercent or 0) else nil
	)
	setAttributeIfChanged(placedModel, OVERHEAD_ATTRIBUTES.ExpiresAt, nil)
	removeLegacyCrewHover(placedModel)
	CollectionService:AddTag(placedModel, CrewOverhead.Tag)
end

local function clearStandVisual(standModel)
	local existing = standModel:FindFirstChild("PlacedCrewMember")
	if existing and existing:IsA("Model") then
		existing:Destroy()
	end
	resetSlotRenderState(getExistingSlotRuntime(standModel))
end

local function findActiveShipAncestor(instance)
	local current = instance

	while current do
		if ShipRuntimeService.IsActiveShip(current) then
			return current
		end

		current = current.Parent
	end

	return nil
end

local function isNumericShipCrewSlot(standModel)
	return ShipSlotService.NormalizeSlotNumber(standModel and standModel.Name) ~= nil
		and findActiveShipAncestor(standModel) ~= nil
end

local function getCrewPlacementRotationOffsetDegrees(standModel)
	if
		isNumericShipCrewSlot(standModel)
		or (
			ShipSlotService.IsCaptainSlotName(standModel and standModel.Name)
			and findActiveShipAncestor(standModel) ~= nil
		)
	then
		return tonumber(ShipVisuals.ShipCrewPlacementRotationOffsetDegrees)
			or LEGACY_STAND_CREW_PLACEMENT_ROTATION_OFFSET_DEGREES
	end

	return LEGACY_STAND_CREW_PLACEMENT_ROTATION_OFFSET_DEGREES
end

local function getCrewPlacementCFrame(model, handle, standModel)
	local boxCF, boxSize = model:GetBoundingBox()
	local offset = model:GetPivot():ToObjectSpace(boxCF)
	local up = handle.CFrame.UpVector
	local surface = handle.Position + up * (handle.Size.Y / 2)
	local rotationOffsetDegrees = getCrewPlacementRotationOffsetDegrees(standModel)
	local rot = (handle.CFrame - handle.Position) * CFrame.Angles(0, math.rad(rotationOffsetDegrees), 0)
	local desiredBox = CFrame.new(surface + up * (boxSize.Y / 2)) * rot
	return desiredBox * offset:Inverse()
end

local function placeModelBottomOnHandle(model, handle, standModel)
	model:PivotTo(getCrewPlacementCFrame(model, handle, standModel))
end

local function spawnStandCrewMember(player, standModel, handle, crewMemberName)
	clearStandVisual(standModel)

	local resolved = resolveCrewMemberRecord(player, crewMemberName)
	local template = resolved and resolved.Template or findTemplateForName(crewMemberName)
	standDebug(
		"spawnStandCrewMember begin player=%s stand=%s savedName=%s canonical=%s template=%s",
		player and player.Name or "?",
		standModel and standModel.Name or "?",
		tostring(crewMemberName),
		tostring(resolved and resolved.CanonicalName or crewMemberName),
		tostring(template and template:GetFullName() or "nil")
	)
	if not template or not template:IsA("Model") then
		warn(string.format("[CrewMemberIncome] Failed to restore stand crew template player=%s stand=%s savedName=%s", player and player.Name or "?", standModel.Name, tostring(crewMemberName)))
		standDebug(
			"spawnStandCrewMember failed player=%s stand=%s reason=no_template",
			player and player.Name or "?",
			standModel and standModel.Name or "?"
		)
		return nil, "no_template"
	end

	local clone = template:Clone()
	clone.Name = "PlacedCrewMember"
	clone.Parent = standModel

	ensurePrimaryPart(clone)
	anchorModel(clone)
	makeStandVisualNonBlocking(clone)
	placeModelBottomOnHandle(clone, handle, standModel)

	local info = resolved and resolved.Info or findCrewMemberInfoByName(crewMemberName, player)
	if info then
		tryPlayIdle(clone, info.IdleAnim)
	end

	syncPlacedOverheadMetadata(player, standModel, crewMemberName, clone)
	resetSlotRenderState(getExistingSlotRuntime(standModel))
	standDebug(
		"spawnStandCrewMember success player=%s stand=%s model=%s incomeBase=%s",
		player and player.Name or "?",
		standModel and standModel.Name or "?",
		clone:GetFullName(),
		tostring(resolved and resolved.Info and resolved.Info.Income or info and info.Income or "nil")
	)
	return clone, nil
end

local function findCrewMemberToolByInstanceId(player, instanceId)
	instanceId = tostring(instanceId or "")
	if instanceId == "" then
		return nil
	end

	local function scan(container)
		if not container then
			return nil
		end
		for _, child in ipairs(container:GetChildren()) do
			if child:IsA("Tool") and getToolCrewMemberInstanceId(child) == instanceId then
				return child
			end
		end
		return nil
	end

	return scan(player.Character) or scan(player:FindFirstChildOfClass("Backpack"))
end

local function equipCrewMemberToolByInstanceId(player, instanceId, storageName)
	instanceId = tostring(instanceId or "")
	if instanceId == "" then
		return
	end

	task.spawn(function()
		for attempt = 1, 12 do
			if player.Parent ~= Players then
				return
			end

			local character = player.Character
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			local tool = findCrewMemberToolByInstanceId(player, instanceId)
			if humanoid and tool and tool:IsA("Tool") then
				if tool.Parent ~= character then
					humanoid:UnequipTools()
					humanoid:EquipTool(tool)
				end
				return
			end

			task.wait(if attempt == 1 then 0.05 else 0.1)
		end

		logCrewSwitchFailure(
			player,
			"",
			"outgoing_equip_failed",
			string.format("instanceId=%s storage=%s", instanceId, tostring(storageName or ""))
		)
	end)
end

local function setMoneyLabelText(cache, text)
	setTextIfChanged(cache, "LastMoneyText", cache and cache.MoneyLabel, text)
end

local function updateStandMoneyText(player, standModel, cache, slotState, crewMemberName)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return
	end

	cache = cache or getSlotRuntime(player, standModel.Parent, standModel)
	if cache and not isLiveSlotDescendant(cache, cache.MoneyLabel) then
		refreshSlotRuntimeRefs(cache)
	end
	if not cache or not isLiveSlotDescendant(cache, cache.MoneyLabel) then
		return
	end

	local standName = standModel.Name
	slotState = slotState or getStandSlotState(player, standName)
	if slotState.Visible and not slotState.Usable then
		setMoneyLabelText(cache, "LOCKED")
		return
	end

	crewMemberName = if crewMemberName ~= nil then crewMemberName else getPlayerStandCrewMemberName(player, standName)
	local incomeText = CurrencyUtil.formatIncomeCompactAmount(getStandIncomeDisplay(player, standName))
	if crewMemberName == "" and slotState.BonusInfo then
		setMoneyLabelText(
			cache,
			string.format("%s +%d%%", tostring(slotState.BonusInfo.Label or "Bonus"), slotState.BonusPercent)
		)
		return
	end

	if crewMemberName ~= "" and slotState.BonusInfo then
		setMoneyLabelText(
			cache,
			string.format("%s +%d%%\n%s", tostring(slotState.BonusInfo.Label or "Bonus"), slotState.BonusPercent, incomeText)
		)
		return
	end

	setMoneyLabelText(cache, incomeText)
end

local function getHitBoxPart(standModel, cache)
	cache = cache or getExistingSlotRuntime(standModel)
	if cache then
		return cache.ClaimHitBox
	end

	return ShipSlotService.GetClaimHitBox(standModel)
end

local function waitForPlot(player, timeout)
	local t0 = os.clock()
	standDebug("waitForShip begin player=%s timeout=%s", player.Name, tostring(timeout or 15))
	saveTrace(
		"restoreWait begin player=%s userId=%s timeout=%s check=active_ship.OwnerUserId==player.UserId",
		player.Name,
		tostring(player.UserId),
		tostring(timeout or 15)
	)
	ownershipTrace(
		"waitForShip begin player=%s userId=%s timeout=%s",
		player.Name,
		tostring(player.UserId),
		tostring(timeout or 15)
	)
	while os.clock() - t0 < (timeout or 15) do
		local activeShip = ShipRuntimeService.GetActiveShip(player)
		if activeShip then
			standDebug("waitForShip found player=%s ship=%s", player.Name, activeShip:GetFullName())
			saveTrace(
				"restoreWait accepted player=%s userId=%s ship=%s reason=active_ship_runtime",
				player.Name,
				tostring(player.UserId),
				formatInstancePath(activeShip)
			)
			return activeShip
		end

		task.wait(0.25)
	end
	standDebug("waitForShip timed_out player=%s", player.Name)
	saveTrace(
		"restoreWait skipped player=%s userId=%s reason=no_active_ship_with_matching_owner_userid timeout=%s",
		player.Name,
		tostring(player.UserId),
		tostring(timeout or 15)
	)
	ownershipTrace(
		"waitForShip timed_out player=%s userId=%s timeout=%s",
		player.Name,
		tostring(player.UserId),
		tostring(timeout or 15)
	)
	return nil
end

local function getLevelUpPart(standModel)
	local cache = getExistingSlotRuntime(standModel)
	if cache and isLiveInstance(cache.LevelUpPart) then
		return cache.LevelUpPart
	end

	return resolveSlotLevelUpPart(standModel)
end

local function getLevelUpGuiRoot(standModel, player, cache)
	cache = cache or getSlotRuntime(player, standModel.Parent, standModel)
	if not cache or not isLiveInstance(cache.LevelUpPart) then
		return nil, nil, nil
	end

	if not isLiveInstance(cache.LevelUpSurfaceGui) then
		local now = os.clock()
		if cache.NextLevelUpLookupAt and now < cache.NextLevelUpLookupAt then
			return cache.LevelUpPart, nil, nil
		end
		cache.NextLevelUpLookupAt = now + SLOT_LEVEL_UI_REFRESH_INTERVAL_SECONDS
		local allowPartFallback = not ShipRuntimeService.IsActiveShip(standModel.Parent)
		cache.LevelUpSurfaceGui = resolvePlayerLevelUpSurfaceGui(player, cache.SlotKey, cache.LevelUpPart, allowPartFallback)
		resolveLevelUpRefs(cache)
		if cache.LevelUpSurfaceGui then
			cache.NextLevelUpLookupAt = nil
		end
	end

	if not cache.LevelUpSurfaceGui or not cache.LevelUpSurfaceGui:IsA("SurfaceGui") then
		return cache.LevelUpPart, nil, nil
	end

	return cache.LevelUpPart, cache.LevelUpSurfaceGui, cache.LevelUpRoot
end

local function getLevelUpRefs(standModel, player, cache)
	cache = cache or getSlotRuntime(player, standModel.Parent, standModel)
	local part, sg = getLevelUpGuiRoot(standModel, player, cache)
	if not part or not sg or not cache then
		return nil
	end

	return {
		Part = part,
		SurfaceGui = sg,
		Root = cache.LevelUpRoot,
		Main = cache.LevelUpMain,
		Price = cache.LevelUpPrice,
		Upgrade = cache.LevelUpUpgrade,
	}
end

local function ensureLevelUpClickDetector(standModel)
	local part = getLevelUpPart(standModel)
	if not part then
		return nil
	end
	local cd = part:FindFirstChildOfClass("ClickDetector")
	if not cd then
		cd = Instance.new("ClickDetector")
		cd.MaxActivationDistance = 15
		cd.Parent = part
	end
	return cd
end

local function updateStandHover(player, standModel, crewMemberName)
	local placed = standModel:FindFirstChild("PlacedCrewMember")
	if placed and placed:IsA("Model") then
		syncPlacedOverheadMetadata(player, standModel, crewMemberName, placed)
	end
end

local function setStandLevel(player, standName, level)
	local safeLevel = math.max(1, math.floor(tonumber(level) or 1))
	if CrewStandIncomeAuthority.GetStandLevel(player, standName) ~= safeLevel then
		CrewStandIncomeAuthority.SetStandLevel(player, standName, safeLevel, "stand_level_sync")
	end
	return safeLevel
end

local function syncStandLevelFromCrewMember(player, standName, crewMemberName)
	if crewMemberName == nil or crewMemberName == "" then
		return setStandLevel(player, standName, 1)
	end

	local lvl = getCrewMemberLevel(player, crewMemberName)
	return setStandLevel(player, standName, lvl)
end

local function updateLevelUpUI(player, standModel, cache, slotState, crewMemberName, crewMemberInstanceId, forceRefresh, totalFoodCount)
	cache = cache or getSlotRuntime(player, standModel.Parent, standModel)
	local refs = getLevelUpRefs(standModel, player, cache)
	if not refs then
		return
	end

	local standName = standModel.Name
	local isCaptainSlot = ShipSlotService.IsCaptainSlotName(standName)
	slotState = slotState or (if isCaptainSlot then {
		Visible = true,
		Usable = true,
	} else getStandSlotState(player, standName))
	if slotState.Visible and not slotState.Usable then
		setCachedLevelUpVisible(cache, false)
		setTextIfChanged(cache, "LastLevelPriceText", refs.Price, "")
		setTextIfChanged(cache, "LastLevelUpgradeText", refs.Upgrade, "")
		return
	end

	crewMemberName = if crewMemberName ~= nil then crewMemberName else getPlayerStandCrewMemberName(player, standName)
	crewMemberInstanceId = if crewMemberInstanceId ~= nil then crewMemberInstanceId else getPlayerStandCrewMemberInstanceId(player, standName)

	if crewMemberName == "" then
		setCachedLevelUpVisible(cache, false)
		setTextIfChanged(cache, "LastLevelPriceText", refs.Price, "")
		setTextIfChanged(cache, "LastLevelUpgradeText", refs.Upgrade, "")
		standDebug("updateLevelUpUI hidden player=%s stand=%s reason=no_crew_member", player.Name, standName)
		return
	end

	local now = os.clock()
	local availableFoodCount = if totalFoodCount ~= nil then totalFoodCount else CrewFoodProgression.GetTotalFoodCount(player)
	local progressKey = table.concat({
		crewMemberName,
		tostring(crewMemberInstanceId or ""),
		tostring(availableFoodCount),
	}, "|")
	if
		forceRefresh ~= true
		and cache.LastLevelProgressKey == progressKey
		and now < (cache.NextLevelUiRefreshAt or 0)
	then
		return
	end
	cache.LastLevelProgressKey = progressKey
	cache.NextLevelUiRefreshAt = now + SLOT_LEVEL_UI_REFRESH_INTERVAL_SECONDS

	local progress = CrewFoodProgression.GetProgress(player, crewMemberInstanceId ~= "" and crewMemberInstanceId or crewMemberName)
	if not progress then
		setCachedLevelUpVisible(cache, false)
		setTextIfChanged(cache, "LastLevelPriceText", refs.Price, "")
		setTextIfChanged(cache, "LastLevelUpgradeText", refs.Upgrade, "")
		return
	end

	local currentLevel = if isCaptainSlot then progress.Level else setStandLevel(player, standName, progress.Level)
	local xpText = string.format("XP: %d / %d", math.max(0, progress.CurrentXP), math.max(0, progress.NextLevelXP))
	if availableFoodCount > 0 then
		xpText ..= " | Auto-feed"
	else
		xpText ..= " | No Food"
	end

	if currentLevel >= progress.MaxLevel then
		setCachedLevelUpVisible(cache, true)
		setTextIfChanged(cache, "LastLevelUpgradeText", refs.Upgrade, "Current Level: " .. tostring(currentLevel))
		setTextIfChanged(cache, "LastLevelPriceText", refs.Price, "Max Level")
		standDebug("updateLevelUpUI maxed player=%s stand=%s currentLevel=%s", player.Name, standName, tostring(currentLevel))
		return
	end

	setCachedLevelUpVisible(cache, true)
	setTextIfChanged(cache, "LastLevelUpgradeText", refs.Upgrade, "Current Level: " .. tostring(currentLevel))
	setTextIfChanged(cache, "LastLevelPriceText", refs.Price, xpText)
	standDebug(
		"updateLevelUpUI visible player=%s stand=%s currentLevel=%s currentXP=%s nextXP=%s",
		player.Name,
		standName,
		tostring(currentLevel),
		tostring(progress.CurrentXP),
		tostring(progress.NextLevelXP)
	)
end

local playerStandList = {}
local touchDebounce = {}
local stealPromptDebounce = {}
local placementPickupGuardUntil = {}

local function setPlacementPickupGuard(player, standName)
	placementPickupGuardUntil[player] = placementPickupGuardUntil[player] or {}
	placementPickupGuardUntil[player][tostring(standName or "")] = os.clock() + PLACEMENT_PICKUP_GUARD_SECONDS
end

local function getPlacementPickupGuardRemaining(player, standName)
	local bucket = placementPickupGuardUntil[player]
	if not bucket then
		return 0
	end

	standName = tostring(standName or "")
	local expiresAt = tonumber(bucket[standName]) or 0
	local remaining = expiresAt - os.clock()
	if remaining <= 0 then
		bucket[standName] = nil
		if next(bucket) == nil then
			placementPickupGuardUntil[player] = nil
		end
		return 0
	end

	return remaining
end

local function fireMoneyCollected(player, standModel, collected, incomeToastDisplayPayload)
	if not MoneyCollectedRE then
		return
	end

	if incomeToastDisplayPayload ~= nil then
		MoneyCollectedRE:FireClient(player, standModel, collected, incomeToastDisplayPayload)
	else
		MoneyCollectedRE:FireClient(player, standModel, collected)
	end
end

local function updateCaptainLevelUpUI(player, captainSpot, slotState, crewMemberName, crewMemberInstanceId, forceRefresh, totalFoodCount)
	if typeof(captainSpot) ~= "Instance" or not captainSpot:IsA("Model") then
		return
	end

	local cache = getSlotRuntime(player, captainSpot.Parent, captainSpot)
	updateLevelUpUI(player, captainSpot, cache, slotState, crewMemberName, crewMemberInstanceId, forceRefresh, totalFoodCount)
end

local function refreshPlayerIncomeDisplays(player)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return
	end

	local stands = playerStandList[player]
	if typeof(stands) ~= "table" then
		return
	end

	local equippedCrewMember = getEquippedCrewMemberToolInfo(player)
	local totalFoodCount = CrewFoodProgression.GetTotalFoodCount(player)
	for _, standModel in ipairs(stands) do
		if standModel and standModel.Parent then
			local standName = standModel.Name
			local cache = getSlotRuntime(player, standModel.Parent, standModel)
			local slotState = getStandSlotState(player, standName)
			local crewMemberName = getPlayerStandCrewMemberName(player, standName)
			local crewMemberInstanceId = if crewMemberName ~= "" then getPlayerStandCrewMemberInstanceId(player, standName) else ""
			if crewMemberName ~= "" then
				updateStandHover(player, standModel, crewMemberName)
			end
			updateStandMoneyText(player, standModel, cache, slotState, crewMemberName)
			updateLevelUpUI(player, standModel, cache, slotState, crewMemberName, crewMemberInstanceId, false, totalFoodCount)
			updateStandPromptTexts(player, standModel, cache, slotState, crewMemberName, equippedCrewMember)
		end
	end
end

local function refreshPlayerIncomeDisplaysAfterLifecycleUpdate(player)
	refreshPlayerIncomeDisplays(player)
	task.defer(function()
		if player and player.Parent == Players then
			refreshPlayerIncomeDisplays(player)
		end
	end)
end

CaptainSlotRuntime.Configure({
	BuildIncomeToastDisplayPayload = buildIncomeToastDisplayPayload,
	CanEquipCrewMember = function(player, crewMemberId)
		return CrewQuickSlotService.CanEquipCrewMember(player, crewMemberId)
	end,
	ClearCrewRecordCache = clearCrewRecordCache,
	ClearVisual = clearStandVisual,
	EquipCrewMemberToolByInstanceId = equipCrewMemberToolByInstanceId,
	FindAvailableTutorialPlacementReward = findAvailableTutorialPlacementReward,
	FireMoneyCollected = fireMoneyCollected,
	GetBaseIncome = getBaseIncome,
	GetBeliBoostMultiplier = getBeliBoostMultiplier,
	GetCrewMemberLevel = getCrewMemberLevel,
	GetEquippedCrewMemberToolInfo = getEquippedCrewMemberToolInfo,
	GetInventoryQuantity = getInventoryQuantity,
	LogCrewSwitchFailure = logCrewSwitchFailure,
	PromptUnlockForCrewMember = function(player, crewMemberId)
		CrewQuickSlotService.PromptUnlockForCrewMember(player, crewMemberId)
	end,
	RefreshNormalIncomeDisplays = refreshPlayerIncomeDisplays,
	ResolveDisplayName = resolveStandStatusDisplayName,
	SpawnCrewMember = spawnStandCrewMember,
	SyncPlacedOverheadMetadata = syncPlacedOverheadMetadata,
	UpdateCaptainLevelUpUI = updateCaptainLevelUpUI,
})

local function bindZoneCollect(player, plot, standModel, cache)
	cache = cache or getSlotRuntime(player, plot, standModel)
	local zone = getHitBoxPart(standModel, cache)
	if not zone then
		return
	end
	if cache.ZoneTouchedConnection and cache.ZoneTouchedConnection.Connected and cache.ClaimHitBox == zone then
		return
	end

	if cache.ZoneTouchedConnection and cache.ZoneTouchedConnection.Connected then
		cache.ZoneTouchedConnection:Disconnect()
	end

	cache.ZoneTouchedConnection = zone.Touched:Connect(function(hit)
		if not hit or hit.Name ~= "HumanoidRootPart" then
			return
		end

		local char = hit.Parent
		if not char then
			return
		end

		local plr = Players:GetPlayerFromCharacter(char)
		if not plr or plr ~= player then
			return
		end

		local owner = plot:GetAttribute("OwnerUserId")
		if owner ~= plr.UserId then
			return
		end

		touchDebounce[plr] = touchDebounce[plr] or {}
		local now = os.clock()
		local last = touchDebounce[plr][zone]
		if last and (now - last) < 0.35 then
			return
		end
		touchDebounce[plr][zone] = now

		local standName = standModel.Name

		if not dmEnsureStandFolder(plr, standName) then
			return
		end
		local collectedCrewMemberName = getPlayerStandCrewMemberName(plr, standName)

		local slotState = getStandSlotState(plr, standName)
		if slotState.Visible and not slotState.Usable then
			updateStandMoneyText(plr, standModel)
			return
		end

		local baseToCollect = getPlayerStandIncome(plr, standName)
		if baseToCollect <= 0 then
			updateStandMoneyText(plr, standModel)
			return
		end

		local mult = getStandCollectMultiplier(plr, standName)
		local collected = IncomeClaimMath.GetWholeClaimableAmount(baseToCollect, mult)
		if collected <= 0 then
			updateStandMoneyText(plr, standModel)
			return
		end

		local remainingRawIncome = IncomeClaimMath.GetRawRemainderAfterClaim(baseToCollect, mult, collected)
		if CrewStandIncomeAuthority.SetIncomeToCollect(plr, standName, remainingRawIncome, "income_collect") then
			refreshCollectedIncomeShadow(plr)
		else
			return
		end

		DataManager:AddValue(plr, CurrencyUtil.getPrimaryPath(), collected)
		DataManager:AddValue(plr, CurrencyUtil.getTotalPath(), collected)
		QuestSignals.Record(plr, "EarnBeli", collected, {
			Source = "StandIncome",
			StandName = standName,
		})

		local incomeToastDisplayPayload = buildIncomeToastDisplayPayload(plr, collectedCrewMemberName)
		if MoneyCollectedRE then
			if incomeToastDisplayPayload ~= nil then
				MoneyCollectedRE:FireClient(plr, standModel, collected, incomeToastDisplayPayload)
			else
				MoneyCollectedRE:FireClient(plr, standModel, collected)
			end
		end

		updateStandMoneyText(plr, standModel)
	end)
	cache.Connections.ZoneTouched = cache.ZoneTouchedConnection
end


local function bindLevelUp(player, _plot, standModel, cache)
	local cd = ensureLevelUpClickDetector(standModel)
	if not cd then
		return
	end

	cache = cache or getSlotRuntime(player, standModel.Parent, standModel)
	if cache then
		cache.ClickDetector = cd
	end
	cd.MaxActivationDistance = 0

	updateLevelUpUI(player, standModel, cache, nil, nil, nil, true)
end

local function bindStandPrompt(player, plot, standModel)
	local cache = getSlotRuntime(player, plot, standModel)
	refreshSlotRuntimeRefs(cache)
	local handle = cache and cache.Handle
	if not handle or not handle:IsA("BasePart") then
		standDebug("bindStandPrompt skip player=%s stand=%s reason=no_handle", player.Name, standModel.Name)
		return
	end

	local prompt = cache.Prompt
	if not prompt then
		standDebug("bindStandPrompt skip player=%s stand=%s reason=no_prompt", player.Name, standModel.Name)
		return
	end

	dmEnsureStandFolder(player, standModel.Name)
	standDebug("bindStandPrompt ready player=%s stand=%s savedCrewMember=%s", player.Name, standModel.Name, tostring(getPlayerStandCrewMemberName(player, standModel.Name)))
	updateStandMoneyText(player, standModel, cache)
	bindZoneCollect(player, plot, standModel, cache)
	bindLevelUp(player, plot, standModel, cache)
	updateStandPromptTexts(player, standModel, cache)

	if cache.PromptTriggeredConnection and cache.PromptTriggeredConnection.Connected and cache.Prompt == prompt then
		standDebug("bindStandPrompt already_bound player=%s stand=%s", player.Name, standModel.Name)
		return
	end

	if cache.PromptTriggeredConnection and cache.PromptTriggeredConnection.Connected then
		cache.PromptTriggeredConnection:Disconnect()
	end

	cache.PromptTriggeredConnection = prompt.Triggered:Connect(function(plr)
		local ok, err = xpcall(function()
			standDebug("prompt triggered actor=%s standOwner=%s stand=%s", plr and plr.Name or "nil", player.Name, standModel.Name)
			if not plr or not plr:IsA("Player") then
				standDebug("prompt rejected stand=%s reason=invalid_player", standModel.Name)
				return
			end

			local ownerUserId = plot:GetAttribute("OwnerUserId")
			if ownerUserId ~= player.UserId then
				standDebug("prompt rejected actor=%s stand=%s reason=owner_mismatch boundOwner=%s plotOwner=%s", plr.Name, standModel.Name, tostring(player.UserId), tostring(ownerUserId))
				return
			end

			local standName = standModel.Name

			if plr.UserId ~= ownerUserId then
				if getEquippedCrewMemberToolInfo(plr) then
					logCrewSwitchFailure(plr, standName, "stand_not_owned", string.format("ownerUserId=%s", tostring(ownerUserId)))
				end
				local crewMemberToSteal = getPlayerStandCrewMemberName(player, standName)
				if crewMemberToSteal == "" then
					standDebug("steal rejected actor=%s stand=%s reason=empty_stand", plr.Name, standName)
					return
				end
				local now = os.clock()
				local last = stealPromptDebounce[plr]
				if last and (now - last) < 1 then
					return
				end
				stealPromptDebounce[plr] = now

				local productId = getStealProductIdForCrewMember(crewMemberToSteal)
				if not MonetizationConfig.CanPromptDeveloperProduct(productId) then
					standDebug(
						"steal rejected actor=%s stand=%s crewMember=%s productId=%s reason=disabled_non_gtr_product",
						plr.Name,
						standName,
						tostring(crewMemberToSteal),
						tostring(productId)
					)
					PopUpModule:Server_SendPopUp(
						plr,
						MonetizationConfig.UnavailableMessage,
						Color3.fromRGB(255, 104, 104),
						Color3.fromRGB(0, 0, 0),
						3,
						true
					)
					return
				end
				if not CrewQuickSlotService.CanGainOrNotify(plr, crewMemberToSteal, 1, "StealPrompt:" .. tostring(standName)) then
					standDebug("steal rejected actor=%s stand=%s crewMember=%s reason=quick_slots_full", plr.Name, standName, tostring(crewMemberToSteal))
					return
				end
				local crewMemberInstanceId = getPlayerStandCrewMemberInstanceId(player, standName)
				local _, crewMemberInstance = CrewInstanceService.GetInstance(player, crewMemberInstanceId)
				if CrewInstanceService.IsTutorialRewardProtected(player, crewMemberInstance) then
					standDebug("steal rejected actor=%s stand=%s crewMember=%s reason=tutorial_reward_protected", plr.Name, standName, tostring(crewMemberToSteal))
					return
				end

				plr:SetAttribute("StealOwnerUserId", ownerUserId)
				plr:SetAttribute("StealStandName", standName)
				plr:SetAttribute("StealCrewMemberName", crewMemberToSteal)
				plr:SetAttribute("StealCrewMemberInstanceId", crewMemberInstanceId)
				plr:SetAttribute("StealProductId", productId)
				plr:SetAttribute("StealTime", os.time())

				if DataManager and typeof(DataManager.PromptProductPurchase) == "function" then
					DataManager:PromptProductPurchase(plr, productId)
				elseif MonetizationConfig.DeveloperProductRequiresPaidRandomItemPolicy(productId) then
					standDebug(
						"steal prompt rejected actor=%s stand=%s crewMember=%s productId=%s reason=paid_random_policy_handler_unavailable",
						plr.Name,
						standName,
						tostring(crewMemberToSteal),
						tostring(productId)
					)
				else
					MarketplaceService:PromptProductPurchase(plr, productId)
				end
				standDebug("steal prompt actor=%s stand=%s crewMember=%s productId=%s", plr.Name, standName, tostring(crewMemberToSteal), tostring(productId))
				return
			end

			dmEnsureStandFolder(plr, standName)
			local slotState = getStandSlotState(plr, standName)
			local equippedInfo = getEquippedCrewMemberToolInfo(plr)
			if slotState.Visible and not slotState.Usable then
				if equippedInfo then
					logCrewSwitchFailure(plr, standName, "stand_locked", string.format("level=%s", tostring(slotState.Level)))
				end
				tutorialStandPlacementLog(plr, standName, "stand_unavailable", string.format("level=%s", tostring(slotState.Level)))
				updateStandMoneyText(plr, standModel)
				updateLevelUpUI(plr, standModel)
				updateStandPromptTexts(plr, standModel)
				return
			end

			local current = getPlayerStandCrewMemberName(plr, standName)
			if current ~= "" then
				local placementGuardRemaining = getPlacementPickupGuardRemaining(plr, standName)
				if placementGuardRemaining > 0 then
					if DEBUG_TRACE then
						warn(string.format(
							"[StandPlacementGuard] player=%s stand=%s reason=recent_place action=ignore_pickup cooldown=%.2f",
							plr.Name,
							standName,
							placementGuardRemaining
						))
					end
					tutorialStandPlacementLog(plr, standName, "recent_place", string.format("action=ignore_pickup cooldown=%.2f", placementGuardRemaining))
					updateStandMoneyText(plr, standModel)
					updateLevelUpUI(plr, standModel)
					updateStandPromptTexts(plr, standModel)
					return
				end

				if equippedInfo and equippedInfo.Name ~= "" then
					if equippedInfo.InstanceId == "" then
						logCrewSwitchFailure(plr, standName, "incoming_instance_missing", "equipped_tool_missing_instance_id")
						updateStandMoneyText(plr, standModel)
						updateLevelUpUI(plr, standModel)
						updateStandPromptTexts(plr, standModel)
						return
					end

					local tutorialInstanceId, tutorialInstance = findAvailableTutorialPlacementReward(plr, equippedInfo.Name)
					local incomingInstanceId, incomingInstance, outgoingInstanceId, outgoingInstance, switchReason =
						CrewInstanceService.SwapStandInstance(plr, standName, equippedInfo.InstanceId, {
							ExpectedIncomingStorageName = equippedInfo.Name,
							ClearIncomingTutorialMetadataAfterAssign = tutorialInstance ~= nil
								and tostring(tutorialInstanceId) == tostring(equippedInfo.InstanceId),
						})
					if not incomingInstance then
						logCrewSwitchFailure(plr, standName, switchReason or "swap_commit_failed")
						updateStandMoneyText(plr, standModel)
						updateLevelUpUI(plr, standModel)
						updateStandPromptTexts(plr, standModel)
						return
					end

					clearCrewRecordCache(plr)
					getCrewMemberLevel(plr, incomingInstanceId)
					syncStandLevelFromCrewMember(plr, standName, incomingInstanceId)
					setPlacementPickupGuard(plr, standName)

					local placedModel, visualReason = spawnStandCrewMember(plr, standModel, handle, incomingInstance.StorageName)
					if not placedModel then
						logCrewSwitchFailure(
							plr,
							standName,
							"visual_refresh_failed",
							string.format("incomingInstanceId=%s reason=%s", tostring(incomingInstanceId), tostring(visualReason or "unknown"))
						)
					end

					if tutorialInstance then
						QuestSignals.Record(plr, "PlaceOnStand", 1, {
							Source = "StandPlacement",
							StandName = standName,
							CrewMemberName = tostring(incomingInstance.StorageName or equippedInfo.Name),
							CrewMemberInstanceId = tostring(incomingInstanceId),
							TutorialPlacement = true,
							TutorialRewardConverted = true,
							SwitchPlacement = true,
						})
					end

					standDebug(
						"switch accepted player=%s stand=%s incoming=%s outgoing=%s incomingStorage=%s outgoingStorage=%s",
						plr.Name,
						standName,
						tostring(incomingInstanceId),
						tostring(outgoingInstanceId),
						tostring(incomingInstance.StorageName or ""),
						tostring(outgoingInstance and outgoingInstance.StorageName or "")
					)
					equipCrewMemberToolByInstanceId(plr, outgoingInstanceId, outgoingInstance and outgoingInstance.StorageName or "")
					updateStandMoneyText(plr, standModel)
					updateLevelUpUI(plr, standModel)
					updateStandPromptTexts(plr, standModel)
					return
				end

				local pickupBefore = getPickupStandSnapshot(plr, standName)
				local releasedInstanceId, releasedInstance, releaseReason, releaseDebug = CrewInstanceService.ReleaseStandInstance(plr, standName)
				clearCrewRecordCache(plr)
				local pickupAfter = getPickupStandSnapshot(plr, standName)
				crewPickupDebug(formatCrewPickupDebugFields({
					{ "event", "prompt_release_result" },
					{ "player", plr.Name },
					{ "userId", plr.UserId },
					{ "stand", standName },
					{ "success", releasedInstance ~= nil },
					{ "reason", releaseReason or "none" },
					{ "releasedInstanceId", tostring(releasedInstanceId or "") },
					{ "releasedStorage", releasedInstance and tostring(releasedInstance.StorageName or "") or "" },
					{ "beforeAssignedName", pickupBefore.CrewMemberName },
					{ "beforeCrewMemberInstanceId", pickupBefore.CrewMemberInstanceId },
					{ "beforeCrewMemberInstanceId", pickupBefore.CrewMemberInstanceId },
					{ "beforeLegacyStorageName", pickupBefore.LegacyStorageName },
					{ "beforeIncome", pickupBefore.IncomeToCollect },
					{ "afterStandDataExists", pickupAfter.Exists },
					{ "afterHasAssignment", pickupAfter.HasAssignment },
					{ "afterAssignedName", pickupAfter.CrewMemberName },
					{ "afterCrewMemberInstanceId", pickupAfter.CrewMemberInstanceId },
					{ "afterCrewMemberInstanceId", pickupAfter.CrewMemberInstanceId },
					{ "afterLegacyStorageName", pickupAfter.LegacyStorageName },
					{ "afterIncome", pickupAfter.IncomeToCollect },
					{ "quickOccupied", getPickupDebugField(releaseDebug, "QuickSlotOccupied", "") },
					{ "quickUnlocked", getPickupDebugField(releaseDebug, "QuickSlotUnlocked", "") },
					{ "quickMax", getPickupDebugField(releaseDebug, "QuickSlotMax", "") },
					{ "instanceExists", getPickupDebugField(releaseDebug, "InstanceExistsInCrewInventory", "") },
					{ "playerOwnsInstance", getPickupDebugField(releaseDebug, "PlayerOwnsInstance", "") },
					{ "placedTrackingRefs", getPickupDebugField(releaseDebug, "AssignedStandRefs", "") },
					{ "inventorySaveOk", getPickupDebugField(releaseDebug, "InventorySaveOk", "") },
					{ "inventorySaveReason", getPickupDebugField(releaseDebug, "InventorySaveReason", "") },
					{ "standClearOk", getPickupDebugField(releaseDebug, "StandClearOk", "") },
					{ "standClearReason", getPickupDebugField(releaseDebug, "StandClearReason", "") },
					{ "inventoryRollbackOk", getPickupDebugField(releaseDebug, "InventoryRollbackOk", "") },
					{ "inventoryRollbackReason", getPickupDebugField(releaseDebug, "InventoryRollbackReason", "") },
				}))
				if not releasedInstance then
					standDebug(
						"pickup from stand blocked player=%s stand=%s reason=%s",
						plr.Name,
						standName,
						tostring(releaseReason or "no_instance_available")
					)
					return
				end
				local storageName = releasedInstance and releasedInstance.StorageName or current
				standDebug("pickup from stand player=%s stand=%s savedName=%s storageName=%s instanceId=%s", plr.Name, standName, tostring(current), tostring(storageName), tostring(releasedInstanceId))
				clearPlacedStandIncome(plr, standName)
				setStandLevel(plr, standName, 1)
				clearStandVisual(standModel)
				updateStandMoneyText(plr, standModel)
				updateLevelUpUI(plr, standModel)
				updateStandPromptTexts(plr, standModel)
				return
			end

			local toolName = equippedInfo and equippedInfo.Name or nil
			local tutorialInstanceId, tutorialInstance = findAvailableTutorialPlacementReward(plr, toolName)
			if not toolName or toolName == "" then
				tutorialStandPlacementLog(plr, standName, "no_equipped_crewmate", "action=reject requires_equipped_tutorial_reward")
				logCrewSwitchFailure(plr, standName, "no_equipped_crewmate", "empty_slot_place_rejected")
				standDebug("place rejected player=%s stand=%s reason=no_equipped_crewmate", plr.Name, standName)
				return
			end

			local qty = getInventoryQuantity(plr, toolName)
			if qty < 1 then
				if tutorialInstance then
					tutorialStandPlacementLog(
						plr,
						standName,
						"no_inventory",
						string.format(
							"action=bypass tool=%s quantity=%s tutorialInstanceId=%s",
							tostring(toolName),
							tostring(qty),
							tostring(tutorialInstanceId)
						)
					)
				else
					tutorialStandPlacementLog(
						plr,
						standName,
						"no_inventory",
						string.format("action=reject tool=%s quantity=%s", tostring(toolName), tostring(qty))
					)
					standDebug("place rejected player=%s stand=%s tool=%s reason=no_inventory quantity=%s", plr.Name, standName, tostring(toolName), tostring(qty))
					return
				end
			end

			local quickSlotUnlocked = CrewQuickSlotService.CanEquipCrewMember(plr, toolName)
			if not quickSlotUnlocked and not tutorialInstance then
				CrewQuickSlotService.PromptUnlockForCrewMember(plr, toolName)
				tutorialStandPlacementLog(plr, standName, "quick_slot_locked", string.format("action=reject tool=%s", tostring(toolName)))
				standDebug("place rejected player=%s stand=%s tool=%s reason=quick_slot_locked", plr.Name, standName, tostring(toolName))
				return
			elseif not quickSlotUnlocked and tutorialInstance then
				tutorialStandPlacementLog(
					plr,
					standName,
					"quick_slot_locked",
					string.format("action=bypass tool=%s tutorialInstanceId=%s", tostring(toolName), tostring(tutorialInstanceId))
				)
			end

			local placedInstanceId, placedInstance, placeReason
			if tutorialInstance then
				placedInstanceId, placedInstance, placeReason = CrewInstanceService.AssignTutorialRewardInstanceToStand(plr, standName, {
					InstanceId = tutorialInstanceId,
					StorageName = toolName,
					ClearTutorialMetadataAfterAssign = true,
				})
			elseif equippedInfo.InstanceId ~= "" then
				placedInstanceId, placedInstance, placeReason = CrewInstanceService.AssignInstanceToStand(plr, equippedInfo.InstanceId, standName, {
					ExpectedIncomingStorageName = toolName,
				})
			else
				placeReason = "incoming_instance_missing"
			end
			if not placedInstance then
				tutorialStandPlacementLog(
					plr,
					standName,
					tostring(placeReason or "no_instance_available"),
					string.format("action=reject tool=%s tutorialReward=%s", tostring(toolName), tostring(tutorialInstance ~= nil))
				)
				if placeReason then
					logCrewSwitchFailure(plr, standName, placeReason, "empty_slot_place_rejected")
				end
				standDebug("place rejected player=%s stand=%s tool=%s reason=%s", plr.Name, standName, tostring(toolName), tostring(placeReason or "no_instance_available"))
				return
			end

			clearCrewRecordCache(plr)
			getCrewMemberLevel(plr, placedInstanceId)
			syncStandLevelFromCrewMember(plr, standName, placedInstanceId)
			setPlacementPickupGuard(plr, standName)
			if tutorialInstance then
				tutorialStandPlacementLog(
					plr,
					standName,
					"accepted",
					string.format("tool=%s tutorialInstanceId=%s", tostring(toolName), tostring(placedInstanceId))
				)
				QuestSignals.Record(plr, "PlaceOnStand", 1, {
					Source = "StandPlacement",
					StandName = standName,
					CrewMemberName = tostring(placedInstance.StorageName or toolName),
					CrewMemberInstanceId = tostring(placedInstanceId),
					TutorialPlacement = true,
					TutorialRewardConverted = true,
				})
			end
			standDebug("place accepted player=%s stand=%s tool=%s quantityBefore=%s instanceId=%s", plr.Name, standName, tostring(toolName), tostring(qty), tostring(placedInstanceId))

			local placedModel, visualReason = spawnStandCrewMember(plr, standModel, handle, placedInstance.StorageName)
			if not placedModel then
				logCrewSwitchFailure(
					plr,
					standName,
					"visual_refresh_failed",
					string.format("placedInstanceId=%s reason=%s", tostring(placedInstanceId), tostring(visualReason or "unknown"))
				)
			end
			placedModel = standModel:FindFirstChild("PlacedCrewMember")
			standDebug(
				"place post-spawn player=%s stand=%s tool=%s placedModel=%s incomePerTick=%s instanceId=%s",
				plr.Name,
				standName,
				tostring(toolName),
				tostring(placedModel and placedModel:GetFullName() or "nil"),
				tostring(getIncomeWithLevel(plr, placedInstance.StorageName)),
				tostring(placedInstanceId)
			)
			updateStandMoneyText(plr, standModel)
			updateLevelUpUI(plr, standModel)
			updateStandPromptTexts(plr, standModel)
		end, debug.traceback)

		if not ok then
			standDebug("prompt handler error stand=%s err=%s", standModel.Name, tostring(err))
		end
	end)
	cache.Connections.PromptTriggered = cache.PromptTriggeredConnection
end

local function registerStand(player, plot, standModel)
	standDebug("registerStand begin player=%s stand=%s", player.Name, standModel.Name)
	saveTrace(
		"registerStand begin player=%s userId=%s plot=%s stand=%s standPath=%s ownerUserId=%s ownerName=%s",
		player.Name,
		tostring(player.UserId),
		formatInstancePath(plot),
		tostring(standModel.Name),
		formatInstancePath(standModel),
		tostring(plot and plot:GetAttribute("OwnerUserId")),
		tostring(plot and plot:GetAttribute("OwnerName"))
	)
	local list = playerStandList[player]
	if not list then
		list = {}
		playerStandList[player] = list
	end
	local cache = getSlotRuntime(player, plot, standModel)

	for i = 1, #list do
		if list[i] == standModel then
			standDebug("registerStand reuse player=%s stand=%s", player.Name, standModel.Name)
			bindStandPrompt(player, plot, standModel)
			local slotState = getStandSlotState(player, standModel.Name)
			local crewMemberName = getPlayerStandCrewMemberName(player, standModel.Name)
			local crewMemberInstanceId = if crewMemberName ~= "" then getPlayerStandCrewMemberInstanceId(player, standModel.Name) else ""
			updateStandMoneyText(player, standModel, cache, slotState, crewMemberName)
			updateLevelUpUI(
				player,
				standModel,
				cache,
				slotState,
				crewMemberName,
				crewMemberInstanceId,
				true,
				CrewFoodProgression.GetTotalFoodCount(player)
			)
			updateStandPromptTexts(player, standModel, cache, slotState, crewMemberName)
			return
		end
	end

	table.insert(list, standModel)

	bindStandPrompt(player, plot, standModel)
	standDebug("registerStand after bindStandPrompt player=%s stand=%s", player.Name, standModel.Name)

	task.spawn(function()
		standDebug("registerStand init-task begin player=%s stand=%s", player.Name, standModel.Name)
		local ok, err = xpcall(function()
			standDebug("registerStand before handle lookup player=%s stand=%s", player.Name, standModel.Name)
			local handle = cache and cache.Handle or resolveSlotHandle(standModel)
			standDebug("registerStand after handle lookup player=%s stand=%s handle=%s", player.Name, standModel.Name, tostring(handle ~= nil))
			if handle and handle:IsA("BasePart") then
				standDebug("registerStand before savedName lookup player=%s stand=%s", player.Name, standModel.Name)
				local name = getPlayerStandCrewMemberName(player, standModel.Name)
				local savedInstanceId = getPlayerStandCrewMemberInstanceId(player, standModel.Name)
				saveTrace(
					"restoreCheck player=%s userId=%s plot=%s stand=%s savedName=%s savedInstanceId=%s handle=%s",
					player.Name,
					tostring(player.UserId),
					formatInstancePath(plot),
					tostring(standModel.Name),
					tostring(name),
					tostring(savedInstanceId),
					formatInstancePath(handle)
				)
				standDebug("registerStand after savedName lookup player=%s stand=%s savedName=%s", player.Name, standModel.Name, tostring(name))
				if name ~= "" then
					local slotState = getStandSlotState(player, standModel.Name)
					if not slotState.Usable then
						saveTrace(
							"restoreDeferred player=%s userId=%s stand=%s savedName=%s reason=slot_locked level=%s",
							player.Name,
							tostring(player.UserId),
							tostring(standModel.Name),
							tostring(name),
							tostring(slotState.Level)
						)
						clearStandVisual(standModel)
						updateStandMoneyText(player, standModel, cache, slotState, name)
						updateLevelUpUI(player, standModel, cache, slotState, name, savedInstanceId, true)
						updateStandPromptTexts(player, standModel, cache, slotState, name)
						return
					end

					standDebug("registerStand savedCrewMember branch entered player=%s stand=%s", player.Name, standModel.Name)
					standDebug("registerStand restore-begin player=%s stand=%s savedName=%s", player.Name, standModel.Name, tostring(name))
					standDebug("registerStand before ensureStandInstance player=%s stand=%s", player.Name, standModel.Name)
					local restoredInstanceId, restoredInstance = CrewInstanceService.EnsureStandInstance(player, standModel.Name, name)
					local persistedName = restoredInstance and restoredInstance.StorageName or name
					saveTrace(
						"restoreLookup player=%s userId=%s stand=%s requestedName=%s restoredInstanceId=%s persistedName=%s",
						player.Name,
						tostring(player.UserId),
						tostring(standModel.Name),
						tostring(name),
						tostring(restoredInstanceId),
						tostring(persistedName)
					)
					standDebug("registerStand after ensureStandInstance player=%s stand=%s instanceId=%s persisted=%s", player.Name, standModel.Name, tostring(restoredInstanceId), tostring(persistedName))
					name = persistedName
					standDebug("registerStand before getCrewMemberLevel player=%s stand=%s", player.Name, standModel.Name)
					getCrewMemberLevel(player, restoredInstanceId ~= nil and tostring(restoredInstanceId) ~= "" and restoredInstanceId or name)
					standDebug("registerStand after getCrewMemberLevel player=%s stand=%s", player.Name, standModel.Name)
					standDebug("registerStand before syncStandLevelFromCrewMember player=%s stand=%s", player.Name, standModel.Name)
					syncStandLevelFromCrewMember(player, standModel.Name, restoredInstanceId ~= nil and tostring(restoredInstanceId) ~= "" and restoredInstanceId or name)
					standDebug("registerStand after syncStandLevelFromCrewMember player=%s stand=%s", player.Name, standModel.Name)
					standDebug("registerStand before spawnStandCrewMember player=%s stand=%s", player.Name, standModel.Name)
					spawnStandCrewMember(player, standModel, handle, name)
					local placedModel = standModel:FindFirstChild("PlacedCrewMember")
					saveTrace(
						"restoreApplied player=%s userId=%s stand=%s savedName=%s restoredInstanceId=%s placedModel=%s placedPivot=%s",
						player.Name,
						tostring(player.UserId),
						tostring(standModel.Name),
						tostring(name),
						tostring(restoredInstanceId),
						formatInstancePath(placedModel),
						formatVector3(placedModel and placedModel:IsA("Model") and placedModel:GetPivot().Position or nil)
					)
					standDebug("registerStand after spawnStandCrewMember player=%s stand=%s", player.Name, standModel.Name)
					standDebug("registerStand before updateStandHover player=%s stand=%s", player.Name, standModel.Name)
					updateStandHover(player, standModel, name)
					standDebug("registerStand after updateStandHover player=%s stand=%s", player.Name, standModel.Name)
					standDebug("registerStand restore-done player=%s stand=%s incomePerTick=%s", player.Name, standModel.Name, tostring(getIncomeWithLevel(player, name)))
				else
					saveTrace(
						"restoreSkipped player=%s userId=%s stand=%s reason=empty_saved_name",
						player.Name,
						tostring(player.UserId),
						tostring(standModel.Name)
					)
					standDebug("registerStand empty branch entered player=%s stand=%s", player.Name, standModel.Name)
					clearPlacedStandIncome(player, standModel.Name)
					setStandLevel(player, standModel.Name, 1)
					clearStandVisual(standModel)
					standDebug("registerStand empty player=%s stand=%s", player.Name, standModel.Name)
				end
			end

			standDebug("registerStand before setMoneyText player=%s stand=%s", player.Name, standModel.Name)
			updateStandMoneyText(player, standModel, cache)
			standDebug("registerStand after setMoneyText player=%s stand=%s", player.Name, standModel.Name)
			standDebug("registerStand before updateLevelUpUI player=%s stand=%s", player.Name, standModel.Name)
			updateLevelUpUI(player, standModel, cache, nil, nil, nil, true)
			standDebug("registerStand after updateLevelUpUI player=%s stand=%s", player.Name, standModel.Name)
		end, debug.traceback)

		if not ok then
			standDebug("registerStand init-task error player=%s stand=%s err=%s", player.Name, standModel.Name, tostring(err))
			warn(("[CrewIncomeRuntime] Failed to initialize crew slot %s for %s: %s"):format(
				standModel:GetFullName(),
				player.Name,
				tostring(err)
			))
		end
	end)
end


local plotScanBound = {} 

local function waitForStandContainer(plot, _timeout)
	if ShipRuntimeService.IsActiveShip(plot) then
		return plot, "ship"
	end

	return nil, nil
end

local function scanAndBindShipSlots(player, activeShip)
	local slotNumbers = ShipSlotService.GetAvailableSlotNumbers(activeShip)
	if #slotNumbers == 0 then
		warn(("[CrewIncomeRuntime] Active ship has no numbered crew slots with Handles: %s"):format(activeShip:GetFullName()))
		return
	end

	for _, slotNumber in ipairs(slotNumbers) do
		local slotModel = ShipSlotService.GetSlot(activeShip, slotNumber)
		if slotModel and slotModel:IsA("Model") then
			registerStand(player, activeShip, slotModel)
		elseif slotModel then
			warn(("[CrewIncomeRuntime] Ship slot %s is not a Model and cannot host crew visuals yet: %s"):format(
				tostring(slotNumber),
				slotModel:GetFullName()
			))
		end
	end
end

local function scanAndBindCaptainSlot(player, activeShip)
	CaptainSlotRuntime.RefreshPlayer(player, activeShip)
end

local function scanAndBindPlot(player, plot)
	standDebug("scanAndBindPlot begin player=%s plot=%s", player and player.Name or "nil", plot and plot:GetFullName() or "nil")
	plotTrace(
		"scanAndBindPlot player=%s userId=%s plot=%s ownerUserId=%s ownerName=%s",
		player and player.Name or "nil",
		tostring(player and player.UserId or "nil"),
		formatInstancePath(plot),
		tostring(plot and plot:GetAttribute("OwnerUserId")),
		tostring(plot and plot:GetAttribute("OwnerName"))
	)
	if not player or not player.Parent then
		standDebug("scanAndBindPlot abort reason=invalid_player")
		saveTrace("scanAndBindPlot skipped player=<nil> reason=invalid_player")
		return
	end
	if not plot or not plot.Parent then
		standDebug("scanAndBindPlot abort player=%s reason=invalid_plot", player.Name)
		saveTrace("scanAndBindPlot skipped player=%s userId=%s reason=invalid_plot", player.Name, tostring(player.UserId))
		return
	end

	if plotScanBound[plot] then
		standDebug("scanAndBindPlot skip player=%s plot=%s reason=already_bound", player.Name, plot:GetFullName())
		saveTrace("scanAndBindPlot skipped player=%s userId=%s plot=%s reason=already_bound", player.Name, tostring(player.UserId), formatInstancePath(plot))
		return
	end
	plotScanBound[plot] = true

	local stands, containerKind = waitForStandContainer(plot, 25)
	if not stands or containerKind ~= "ship" then
		standDebug("scanAndBindPlot failed player=%s plot=%s reason=no_active_ship_slots", player.Name, plot:GetFullName())
		saveTrace(
			"scanAndBindPlot failed player=%s userId=%s plot=%s reason=no_active_ship_slots",
			player.Name,
			tostring(player.UserId),
			formatInstancePath(plot)
		)
		plotScanBound[plot] = nil
		return
	end
	standDebug("scanAndBindPlot active_ship player=%s ship=%s", player.Name, stands:GetFullName())
	reconcileSlotAssignmentsForRender(player, plot, "scan_and_bind_ship")
	scanAndBindShipSlots(player, plot)
	scanAndBindCaptainSlot(player, plot)
end

local function clearBoundStateForStand(standModel)
	if typeof(standModel) ~= "Instance" or not standModel:IsA("Model") then
		return
	end

	cleanupSlotRuntime(standModel)
end

local function clearPlotScanStateForPlayer(player)
	for plot in pairs(plotScanBound) do
		if not plot or not plot.Parent then
			plotScanBound[plot] = nil
		else
			local ownerUserId = plot:GetAttribute("OwnerUserId")
			local ownerName = plot:GetAttribute("OwnerName")
			if ownerUserId == player.UserId or plot.Name == player.Name or ownerName == player.Name then
				plotScanBound[plot] = nil
			end
		end
	end
end

local reconcilePlayerStandAssignments

local function clearPlayerStandRuntime(player)
	local stands = playerStandList[player]
	if stands then
		for i = 1, #stands do
			clearBoundStateForStand(stands[i])
		end
	end

	CaptainSlotRuntime.CleanupPlayer(player)
	playerStandList[player] = nil
	cleanupPlayerSlotRuntime(player)
	ensuredStandFolders[player] = nil
	touchDebounce[player] = nil
	stealPromptDebounce[player] = nil
	placementPickupGuardUntil[player] = nil
	clearCrewRecordCache(player)
	clearPlotScanStateForPlayer(player)
end

local function refreshPlayerStandRuntime(player)
	clearPlayerStandRuntime(player)

	local plot = waitForPlot(player, 10)
	if not plot then
		return false, "active_ship_not_found"
	end

	scanAndBindPlot(player, plot)
	reconcilePlayerStandAssignments(player)
	refreshPlayerIncomeDisplaysAfterLifecycleUpdate(player)
	return true, plot
end

reconcilePlayerStandAssignments = function(player)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return
	end

	clearCrewRecordCache(player)
	local stands = playerStandList[player]
	if typeof(stands) ~= "table" then
		return
	end

	for i = 1, #stands do
		local standModel = stands[i]
		if standModel and standModel.Parent then
			CrewInstanceService.ReconcileStandAssignment(player, standModel.Name)
		end
	end
end

CrewInstanceService.RegisterCrewInventorySavedCallback(function(player)
	if player and player.Parent == Players then
		if CrewSlotAssignmentReconciler.IsResetInProgress(player) then
			return
		end

		task.defer(function()
			if CrewSlotAssignmentReconciler.IsResetInProgress(player) then
				return
			end

			local activeShip = ShipRuntimeService.GetActiveShip(player)
			reconcileSlotAssignmentsForRender(player, activeShip, "inventory_saved")
			if activeShip then
				scanAndBindCaptainSlot(player, activeShip)
			end
			reconcilePlayerStandAssignments(player)
			refreshPlayerIncomeDisplaysAfterLifecycleUpdate(player)
		end)
	end
end)


Players.PlayerAdded:Connect(function(player)
	standDebug("PlayerAdded player=%s", player.Name)
	task.spawn(function()
		saveTrace("PlayerAdded begin player=%s userId=%s event=restore_begin", player.Name, tostring(player.UserId))
		logSavedShipSnapshot(player, "PlayerAdded")
		resetHugeIncomeOnJoin(player)

		local plot = waitForPlot(player, 25)
		if not plot then
			standDebug("PlayerAdded abort player=%s reason=no_active_ship", player.Name)
			saveTrace("PlayerAdded restoreSkipped player=%s userId=%s reason=no_active_ship_owned_by_userid", player.Name, tostring(player.UserId))
			return
		end
		saveTrace(
			"PlayerAdded plotReady player=%s userId=%s plot=%s ownerUserId=%s ownerUserIdType=%s ownerName=%s event=restore_continue",
			player.Name,
			tostring(player.UserId),
			formatInstancePath(plot),
			tostring(plot:GetAttribute("OwnerUserId")),
			typeof(plot:GetAttribute("OwnerUserId")),
			tostring(plot:GetAttribute("OwnerName"))
		)
		scanAndBindPlot(player, plot)
		reconcilePlayerStandAssignments(player)
		refreshPlayerIncomeDisplaysAfterLifecycleUpdate(player)
	end)
end)


Players.PlayerRemoving:Connect(function(player)
	clearPlayerStandRuntime(player)
	getCrewStorage().ClearIncomeShadowSyncState(player)
end)

standCommandFunction.OnInvoke = function(action, player)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return false, "invalid_player"
	end

	if action == "clear" then
		clearPlayerStandRuntime(player)
		return true
	end

	if action == "refresh" then
		return refreshPlayerStandRuntime(player)
	end

	return false, "unsupported_action"
end

task.spawn(bootstrapExistingCrewIncomePlayers, {
	Players = Players,
	standDebug = standDebug,
	waitForPlot = waitForPlot,
	scanAndBindPlot = scanAndBindPlot,
	reconcilePlayerStandAssignments = reconcilePlayerStandAssignments,
	resetHugeIncomeOnJoin = resetHugeIncomeOnJoin,
	refreshPlayerIncomeDisplaysAfterLifecycleUpdate = refreshPlayerIncomeDisplaysAfterLifecycleUpdate,
})

task.spawn(runCrewIncomeBankLoop, {
	CrewFoodProgression = CrewFoodProgression,
	CrewStandIncomeAuthority = CrewStandIncomeAuthority,
	clearPlayerStandRuntime = clearPlayerStandRuntime,
	clearStandVisual = clearStandVisual,
	dmEnsureStandFolder = dmEnsureStandFolder,
	getBeliBoostMultiplier = getBeliBoostMultiplier,
	getEquippedCrewMemberToolInfo = getEquippedCrewMemberToolInfo,
	getIncomeWithLevel = getIncomeWithLevel,
	getPlayerStandCrewMemberInstanceId = getPlayerStandCrewMemberInstanceId,
	getPlayerStandCrewMemberName = getPlayerStandCrewMemberName,
	getSlotRuntime = getSlotRuntime,
	getStandSlotState = getStandSlotState,
	playerStandList = playerStandList,
	refreshBankedIncomeShadow = refreshBankedIncomeShadow,
	resolveSlotHandle = resolveSlotHandle,
	spawnStandCrewMember = spawnStandCrewMember,
	standDebug = standDebug,
	updateLevelUpUI = updateLevelUpUI,
	updateStandHover = updateStandHover,
	updateStandMoneyText = updateStandMoneyText,
	updateStandPromptTexts = updateStandPromptTexts,
})

end

return CrewIncomeRuntime
