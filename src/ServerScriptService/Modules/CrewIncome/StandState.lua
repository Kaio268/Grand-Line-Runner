local Module = {}

function Module.Install(ctx)
	local CREW_ITEM_KIND = ctx.CREW_ITEM_KIND
	local CrewCatalog = ctx.CrewCatalog
	local CrewFoodProgression = ctx.CrewFoodProgression
	local CrewIncomeBalance = ctx.CrewIncomeBalance
	local CrewInstanceService = ctx.CrewInstanceService
	local CrewSlotAssignmentReconciler = ctx.CrewSlotAssignmentReconciler
	local CrewStandIncomeAuthority = ctx.CrewStandIncomeAuthority
	local DataManager = ctx.DataManager
	local ensuredStandFolders = ctx.ensuredStandFolders
	local function findCrewMemberInfoByName(...)
		return ctx.findCrewMemberInfoByName(...)
	end
	local INCOME_SHADOW_BANK_THROTTLE_SECONDS = ctx.INCOME_SHADOW_BANK_THROTTLE_SECONDS
	local IncomeClaimMath = ctx.IncomeClaimMath
	local MAX_INCOME_ON_JOIN = ctx.MAX_INCOME_ON_JOIN
	local PlotUpgradeConfig = ctx.PlotUpgradeConfig
	local RebirthConfig = ctx.RebirthConfig
	local function resolveCrewMemberRecord(...)
		return ctx.resolveCrewMemberRecord(...)
	end
	local ServerScriptService = ctx.ServerScriptService
	local function standDebug(...)
		return ctx.standDebug(...)
	end
	local function syncPlacedOverheadMetadata(...)
		return ctx.syncPlacedOverheadMetadata(...)
	end
	local TUTORIAL_RUNTIME_ACTIVE_ATTRIBUTE = ctx.TUTORIAL_RUNTIME_ACTIVE_ATTRIBUTE
	local TUTORIAL_RUNTIME_STEP_ATTRIBUTE = ctx.TUTORIAL_RUNTIME_STEP_ATTRIBUTE

	local CrewStorageModule = nil
	local CrewMemberCanonicalReadGateModule = nil
	local dmGet
	local dmSet
	local getCrewMemberLevel
	local getPlayerStandCrewMemberInstanceId
	local getPlayerStandCrewMemberName

	local function resolveCanonicalCrewMemberId(...)
		return ctx.resolveCanonicalCrewMemberId(...)
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
			if typeof(DataManager.TryGetValue) == "function" then
				return DataManager:TryGetValue(player, "CrewMemberIncome")
			end
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

		return CrewIncomeBalance.GetClaimMultiplier(lvl, RebirthConfig.GetShipIncomeMultiplier(rebirthCount))
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

	local function getTitleBeliMultiplier(player)
		if typeof(IncomeClaimMath.GetTitleBeliMultiplier) == "function" then
			return IncomeClaimMath.GetTitleBeliMultiplier(player)
		end

		return 1
	end

	local function getToolCrewMemberInstanceId(tool)
		if not tool or not tool:IsA("Tool") then
			return ""
		end
		return tostring(tool:GetAttribute("CrewMemberInstanceId") or tool:GetAttribute("CrewInstanceId") or "")
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
			if typeof(DataManager.TryGetValue) == "function" then
				local value = DataManager:TryGetValue(player, path)
				return value
			end
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
			if typeof(DataManager.TrySetValue) == "function" then
				return DataManager:TrySetValue(player, path, value)
			end
			return DataManager:SetValue(player, path, value)
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

	getCrewMemberLevel = function(player, crewMemberName)
		local progress = CrewFoodProgression.GetProgress(player, crewMemberName)
		if not progress then
			return 1
		end
		return progress.Level
	end

	local function getBaseIncome(player, crewMemberName, crewMemberInstanceId)
		crewMemberInstanceId = tostring(crewMemberInstanceId or "")
		if crewMemberInstanceId ~= "" then
			local _, instanceData = CrewInstanceService.GetInstance(player, crewMemberInstanceId)
			local rawIncome = CrewIncomeBalance.GetRawBankIncomePerSecond(instanceData)
			if rawIncome > 0 then
				return rawIncome
			end
		end

		local resolved = resolveCrewMemberRecord(player, crewMemberName)
		local info = resolved and resolved.Info or findCrewMemberInfoByName(crewMemberName, player)
		local base = info and (tonumber(info.Income) or 0) or 0
		return base
	end

	local function getRawBankIncomePerSecond(player, crewMemberName, crewMemberInstanceId)
		return getBaseIncome(player, crewMemberName, crewMemberInstanceId)
	end

	local function getIncomeWithLevel(player, crewMemberName, crewMemberInstanceId)
		local base = getBaseIncome(player, crewMemberName, crewMemberInstanceId)
		if base <= 0 then
			return 0
		end

		local target = if tostring(crewMemberInstanceId or "") ~= "" then tostring(crewMemberInstanceId) else tostring(crewMemberName or "")
		return base * CrewIncomeBalance.GetLevelIncomeMultiplier(getCrewMemberLevel(player, target))
	end

	local function getStandIncomeDisplay(player, standName)
		standDebug("getStandIncomeDisplay begin player=%s stand=%s", player.Name, standName)
		local base = getPlayerStandIncome(player, standName)
		if base <= 0 then
			standDebug("getStandIncomeDisplay early_zero player=%s stand=%s", player.Name, standName)
			return 0
		end
		local summary = IncomeClaimMath.BuildClaimSummary(
			base,
			getStandCollectMultiplier(player, standName),
			getTitleBeliMultiplier(player)
		)
		local display = math.max(0, tonumber(summary.FinalAmount) or 0)
		standDebug(
			"getStandIncomeDisplay done player=%s stand=%s base=%s display=%s",
			player.Name,
			standName,
			tostring(base),
			tostring(display)
		)
		return display
	end

	local function buildStandClaimSummary(player, standName)
		return IncomeClaimMath.BuildClaimSummary(
			getPlayerStandIncome(player, standName),
			getStandCollectMultiplier(player, standName),
			getTitleBeliMultiplier(player)
		)
	end

	local function buildStandIncomeRateSummary(player, standName, crewMemberName)
		local crewMemberInstanceId = getPlayerStandCrewMemberInstanceId(player, standName)
		return IncomeClaimMath.BuildRateSummary(
			getRawBankIncomePerSecond(player, crewMemberName, crewMemberInstanceId),
			getBeliBoostMultiplier(player),
			getStandCollectMultiplier(player, standName),
			getTitleBeliMultiplier(player)
		)
	end

	local function getStandIncomePerSecond(player, standName, crewMemberName)
		local summary = buildStandIncomeRateSummary(player, standName, crewMemberName)
		return math.max(0, tonumber(summary.FinalAmount) or 0)
	end

	local function isStandIncomeBoosted(player, standName, crewMemberName)
		return buildStandIncomeRateSummary(player, standName, crewMemberName).IsBoosted == true
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

	local function updateStandHover(player, standModel, crewMemberName)
		local placed = standModel:FindFirstChild("PlacedCrewMember")
		if placed and placed:IsA("Model") then
			syncPlacedOverheadMetadata(player, standModel, crewMemberName, placed)
		end
	end

	local function setStandLevel(player, standName, level)
		local safeLevel = CrewIncomeBalance.NormalizeLevel(level)
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


	ctx.clearPlacedStandIncome = clearPlacedStandIncome
	ctx.dmEnsureStandFolder = dmEnsureStandFolder
	ctx.dmGet = dmGet
	ctx.dmSet = dmSet
	ctx.findAvailableTutorialPlacementReward = findAvailableTutorialPlacementReward
	ctx.getBaseIncome = getBaseIncome
	ctx.getBeliBoostMultiplier = getBeliBoostMultiplier
	ctx.getBeliBoostRemaining = getBeliBoostRemaining
	ctx.getTitleBeliMultiplier = getTitleBeliMultiplier
	ctx.getCrewMemberCanonicalReadGate = getCrewMemberCanonicalReadGate
	ctx.getCrewMemberLevel = getCrewMemberLevel
	ctx.getCrewStorage = getCrewStorage
	ctx.getEquippedCrewMemberToolInfo = getEquippedCrewMemberToolInfo
	ctx.getIncomeWithLevel = getIncomeWithLevel
	ctx.getInventoryQuantity = getInventoryQuantity
	ctx.getRawBankIncomePerSecond = getRawBankIncomePerSecond
	ctx.getPickupDebugField = getPickupDebugField
	ctx.getPickupStandSnapshot = getPickupStandSnapshot
	ctx.getPlayerShipUpgradeLevel = getPlayerShipUpgradeLevel
	ctx.getPlayerStandCrewMemberInstanceId = getPlayerStandCrewMemberInstanceId
	ctx.getPlayerStandCrewMemberName = getPlayerStandCrewMemberName
	ctx.getPlayerStandIncome = getPlayerStandIncome
	ctx.getShipSlotsTable = getShipSlotsTable
	ctx.getStandClaimSummary = buildStandClaimSummary
	ctx.getStandIncomeDisplay = getStandIncomeDisplay
	ctx.getStandIncomePerSecond = getStandIncomePerSecond
	ctx.getStandCollectMultiplier = getStandCollectMultiplier
	ctx.getStandSlotState = getStandSlotState
	ctx.getToolCrewMemberInstanceId = getToolCrewMemberInstanceId
	ctx.isActiveTutorialPlacementStep = isActiveTutorialPlacementStep
	ctx.isBeliBoostActive = isBeliBoostActive
	ctx.isStandIncomeBoosted = isStandIncomeBoosted
	ctx.logCrewSwitchFailure = logCrewSwitchFailure
	ctx.normalizeIncomeSnapshotSlotKey = normalizeIncomeSnapshotSlotKey
	ctx.reconcileSlotAssignmentsForRender = reconcileSlotAssignmentsForRender
	ctx.refreshBankedIncomeShadow = refreshBankedIncomeShadow
	ctx.refreshCollectedIncomeShadow = refreshCollectedIncomeShadow
	ctx.refreshCrewMemberShadow = refreshCrewMemberShadow
	ctx.resetHugeIncomeOnJoin = resetHugeIncomeOnJoin
	ctx.setStandLevel = setStandLevel
	ctx.syncShipSlotAssignment = syncShipSlotAssignment
	ctx.syncStandLevelFromCrewMember = syncStandLevelFromCrewMember
	ctx.tutorialStandPlacementLog = tutorialStandPlacementLog
	ctx.updateStandHover = updateStandHover
end

return Module
