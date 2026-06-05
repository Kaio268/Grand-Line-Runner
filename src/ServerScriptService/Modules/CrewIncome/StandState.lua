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
	local getRawBankIncomePerSecond
	local getRawBankIncomePerSecondReadOnly

	local function resolveCanonicalCrewMemberId(...)
		return ctx.resolveCanonicalCrewMemberId(...)
	end

	local function getRegisteredStandModel(player, standName)
		local stands = ctx.playerStandList and ctx.playerStandList[player]
		if typeof(stands) ~= "table" then
			return nil
		end

		standName = tostring(standName or "")
		for _, standModel in ipairs(stands) do
			if
				typeof(standModel) == "Instance"
				and standModel:IsA("Model")
				and standModel.Parent ~= nil
				and standModel.Name == standName
			then
				return standModel
			end
		end

		return nil
	end

	local function publishStandStateForName(player, standName, options)
		if typeof(ctx.publishPlacedCrewState) ~= "function" then
			return false, "publish_unavailable"
		end

		local standModel = getRegisteredStandModel(player, standName)
		if not standModel then
			return false, "stand_model_unavailable"
		end

		local crewMemberName = if typeof(getPlayerStandCrewMemberName) == "function"
			then getPlayerStandCrewMemberName(player, standName)
			else ""
		if crewMemberName == "" then
			return false, "missing_crew_member"
		end

		return ctx.publishPlacedCrewState(player, standModel, crewMemberName, options)
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

	local function getIndexMoneyMultiplier(player)
		if typeof(IncomeClaimMath.GetIndexMoneyMultiplier) == "function" then
			return IncomeClaimMath.GetIndexMoneyMultiplier(player)
		end

		return 1
	end

	local function getRewardBeliMultiplier(player)
		if typeof(IncomeClaimMath.GetRewardBeliMultiplier) == "function" then
			return IncomeClaimMath.GetRewardBeliMultiplier(player)
		end

		return getTitleBeliMultiplier(player) * getIndexMoneyMultiplier(player)
	end

	local function getRewardMultiplierMetadata(player)
		return {
			TitleMultiplier = getTitleBeliMultiplier(player),
			IndexMultiplier = getIndexMoneyMultiplier(player),
		}
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

	local function getPlayerStandCrewMemberInstanceIdReadOnly(player, standName, inventoryOverride)
		standName = tostring(standName or "")
		if standName == "" then
			return ""
		end

		local standData = CrewStandIncomeAuthority.GetStandData(player, standName)
		if typeof(standData) ~= "table" or tostring(standData.CrewMemberName or "") == "" then
			return ""
		end

		if typeof(CrewInstanceService.GetStandInstanceIdReadOnly) == "function" then
			return tostring(CrewInstanceService.GetStandInstanceIdReadOnly(player, standName, inventoryOverride) or "")
		end

		return ""
	end

	local function getPlayerStandIncome(player, standName)
		dmEnsureStandFolder(player, standName)
		local standData = CrewStandIncomeAuthority.GetStandData(player, standName)
		local baseIncome = tonumber(standData and standData.IncomeToCollect) or 0
		local crewMemberName = tostring(standData and standData.CrewMemberName or "")
		if crewMemberName == "" then
			return math.max(0, baseIncome)
		end

		local lastAccruedAtUnix = math.max(0, math.floor(tonumber(standData.LastAccruedAtUnix) or 0))
		if lastAccruedAtUnix <= 0 then
			return math.max(0, baseIncome)
		end

		local elapsed = math.max(0, os.time() - lastAccruedAtUnix)
		if elapsed <= 0 then
			return math.max(0, baseIncome)
		end

		local crewMemberInstanceId = tostring(standData.CrewMemberInstanceId or "")
		local rawIncomePerSecond = getRawBankIncomePerSecond(player, crewMemberName, crewMemberInstanceId)
			* getBeliBoostMultiplier(player)
		return math.max(0, baseIncome + (rawIncomePerSecond * elapsed))
	end

	local function getPlayerStandIncomeReadOnly(player, standName, inventoryOverride)
		local standData = CrewStandIncomeAuthority.GetStandData(player, standName)
		local baseIncome = tonumber(standData and standData.IncomeToCollect) or 0
		local crewMemberName = tostring(standData and standData.CrewMemberName or "")
		if crewMemberName == "" then
			return math.max(0, baseIncome)
		end

		local lastAccruedAtUnix = math.max(0, math.floor(tonumber(standData.LastAccruedAtUnix) or 0))
		if lastAccruedAtUnix <= 0 then
			return math.max(0, baseIncome)
		end

		local elapsed = math.max(0, os.time() - lastAccruedAtUnix)
		if elapsed <= 0 then
			return math.max(0, baseIncome)
		end

		local crewMemberInstanceId = getPlayerStandCrewMemberInstanceIdReadOnly(player, standName, inventoryOverride)
		local rawIncomePerSecond = getRawBankIncomePerSecondReadOnly(player, crewMemberName, crewMemberInstanceId, inventoryOverride)
			* getBeliBoostMultiplier(player)
		return math.max(0, baseIncome + (rawIncomePerSecond * elapsed))
	end

	local function materializeStandIncome(player, standName, sourcePath)
		local accruedIncome = getPlayerStandIncome(player, standName)
		local ok, reason = CrewStandIncomeAuthority.MaterializeIncomeToCollect(
			player,
			standName,
			accruedIncome,
			os.time(),
			sourcePath or "income_materialize"
		)
		if ok == true then
			publishStandStateForName(player, standName, {
				Reason = sourcePath or "income_materialize",
				RefreshIncomeTimestamp = true,
				RefreshUpdatedTimestamp = true,
			})
		end
		return ok, reason
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

	local function getBaseIncomeReadOnly(player, crewMemberName, crewMemberInstanceId, inventoryOverride)
		crewMemberInstanceId = tostring(crewMemberInstanceId or "")
		if crewMemberInstanceId ~= "" and typeof(CrewInstanceService.GetInstanceReadOnly) == "function" then
			local _, instanceData = CrewInstanceService.GetInstanceReadOnly(player, crewMemberInstanceId, inventoryOverride)
			local rawIncome = CrewIncomeBalance.GetRawBankIncomePerSecond(instanceData)
			if rawIncome > 0 then
				return rawIncome
			end
		end

		local resolved = resolveCrewMemberRecord(player, crewMemberName)
		local info = resolved and resolved.Info or findCrewMemberInfoByName(crewMemberName, player)
		return info and (tonumber(info.Income) or 0) or 0
	end

	getRawBankIncomePerSecond = function(player, crewMemberName, crewMemberInstanceId)
		return getBaseIncome(player, crewMemberName, crewMemberInstanceId)
	end

	getRawBankIncomePerSecondReadOnly = function(player, crewMemberName, crewMemberInstanceId, inventoryOverride)
		return getBaseIncomeReadOnly(player, crewMemberName, crewMemberInstanceId, inventoryOverride)
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
			getRewardBeliMultiplier(player),
			getRewardMultiplierMetadata(player)
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

	local function getStandIncomeDisplayReadOnly(player, standName, inventoryOverride)
		local base = getPlayerStandIncomeReadOnly(player, standName, inventoryOverride)
		if base <= 0 then
			return 0
		end

		local summary = IncomeClaimMath.BuildClaimSummary(
			base,
			getStandCollectMultiplier(player, standName),
			getRewardBeliMultiplier(player),
			getRewardMultiplierMetadata(player)
		)
		return math.max(0, tonumber(summary.FinalAmount) or 0)
	end

	local function buildStandClaimSummary(player, standName)
		return IncomeClaimMath.BuildClaimSummary(
			getPlayerStandIncome(player, standName),
			getStandCollectMultiplier(player, standName),
			getRewardBeliMultiplier(player),
			getRewardMultiplierMetadata(player)
		)
	end

	local function buildStandIncomeRateSummary(player, standName, crewMemberName)
		local crewMemberInstanceId = getPlayerStandCrewMemberInstanceId(player, standName)
		return IncomeClaimMath.BuildRateSummary(
			getRawBankIncomePerSecond(player, crewMemberName, crewMemberInstanceId),
			getBeliBoostMultiplier(player),
			getStandCollectMultiplier(player, standName),
			getRewardBeliMultiplier(player),
			getRewardMultiplierMetadata(player)
		)
	end

	local function buildStandIncomeRateSummaryReadOnly(player, standName, crewMemberName, inventoryOverride)
		local crewMemberInstanceId = getPlayerStandCrewMemberInstanceIdReadOnly(player, standName, inventoryOverride)
		return IncomeClaimMath.BuildRateSummary(
			getRawBankIncomePerSecondReadOnly(player, crewMemberName, crewMemberInstanceId, inventoryOverride),
			getBeliBoostMultiplier(player),
			getStandCollectMultiplier(player, standName),
			getRewardBeliMultiplier(player),
			getRewardMultiplierMetadata(player)
		)
	end

	local function getStandIncomePerSecond(player, standName, crewMemberName)
		local summary = buildStandIncomeRateSummary(player, standName, crewMemberName)
		return math.max(0, tonumber(summary.FinalAmount) or 0)
	end

	local function getStandIncomePerSecondReadOnly(player, standName, crewMemberName, inventoryOverride)
		local summary = buildStandIncomeRateSummaryReadOnly(player, standName, crewMemberName, inventoryOverride)
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

	local function updateStandHover(player, standModel, crewMemberName, options)
		local placed = standModel:FindFirstChild("PlacedCrewMember")
		if placed and placed:IsA("Model") then
			syncPlacedOverheadMetadata(player, standModel, crewMemberName, placed)
		end
		if typeof(ctx.publishPlacedCrewState) == "function" and tostring(crewMemberName or "") ~= "" then
			ctx.publishPlacedCrewState(player, standModel, crewMemberName, options)
		end
	end

	local function setStandLevel(player, standName, level)
		local safeLevel = CrewIncomeBalance.NormalizeLevel(level)
		if CrewStandIncomeAuthority.GetStandLevel(player, standName) ~= safeLevel then
			local changed = CrewStandIncomeAuthority.SetStandLevel(player, standName, safeLevel, "stand_level_sync")
			if changed == true then
				local crewMemberName = getPlayerStandCrewMemberName(player, standName)
				local standModel = getRegisteredStandModel(player, standName)
				if crewMemberName ~= "" and standModel then
					updateStandHover(player, standModel, crewMemberName, {
						Reason = "stand_level_changed",
						RefreshIncomeTimestamp = true,
						RefreshUpdatedTimestamp = true,
					})
				end
			end
			return safeLevel, changed == true
		end
		return safeLevel, false
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
	ctx.getIndexMoneyMultiplier = getIndexMoneyMultiplier
	ctx.getRewardBeliMultiplier = getRewardBeliMultiplier
	ctx.getRewardMultiplierMetadata = getRewardMultiplierMetadata
	ctx.getTitleBeliMultiplier = getTitleBeliMultiplier
	ctx.getCrewMemberCanonicalReadGate = getCrewMemberCanonicalReadGate
	ctx.getCrewMemberLevel = getCrewMemberLevel
	ctx.getCrewStorage = getCrewStorage
	ctx.getEquippedCrewMemberToolInfo = getEquippedCrewMemberToolInfo
	ctx.getIncomeWithLevel = getIncomeWithLevel
	ctx.getInventoryQuantity = getInventoryQuantity
	ctx.getRawBankIncomePerSecond = getRawBankIncomePerSecond
	ctx.getRawBankIncomePerSecondReadOnly = getRawBankIncomePerSecondReadOnly
	ctx.getPickupDebugField = getPickupDebugField
	ctx.getPickupStandSnapshot = getPickupStandSnapshot
	ctx.getPlayerShipUpgradeLevel = getPlayerShipUpgradeLevel
	ctx.getPlayerStandCrewMemberInstanceId = getPlayerStandCrewMemberInstanceId
	ctx.getPlayerStandCrewMemberInstanceIdReadOnly = getPlayerStandCrewMemberInstanceIdReadOnly
	ctx.getPlayerStandCrewMemberName = getPlayerStandCrewMemberName
	ctx.getPlayerStandIncome = getPlayerStandIncome
	ctx.getPlayerStandIncomeReadOnly = getPlayerStandIncomeReadOnly
	ctx.getShipSlotsTable = getShipSlotsTable
	ctx.getStandClaimSummary = buildStandClaimSummary
	ctx.getStandIncomeDisplay = getStandIncomeDisplay
	ctx.getStandIncomeDisplayReadOnly = getStandIncomeDisplayReadOnly
	ctx.getStandIncomePerSecond = getStandIncomePerSecond
	ctx.getStandIncomePerSecondReadOnly = getStandIncomePerSecondReadOnly
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
	ctx.materializeStandIncome = materializeStandIncome
	ctx.setStandLevel = setStandLevel
	ctx.syncShipSlotAssignment = syncShipSlotAssignment
	ctx.syncStandLevelFromCrewMember = syncStandLevelFromCrewMember
	ctx.tutorialStandPlacementLog = tutorialStandPlacementLog
	ctx.updateStandHover = updateStandHover
end

return Module
