local Module = {}

function Module.Install(ctx)
	local function buildIncomeStatusDisplayDescriptor(...)
		return ctx.buildIncomeStatusDisplayDescriptor(...)
	end
	local CAPTAIN_SLOT_KEY = ctx.CAPTAIN_SLOT_KEY
	local CaptainSlotRuntime = ctx.CaptainSlotRuntime
	local CrewFoodProgression = ctx.CrewFoodProgression
	local CrewIncomeBalance = ctx.CrewIncomeBalance
	local CrewStandIncomeAuthority = ctx.CrewStandIncomeAuthority
	local CurrencyUtil = ctx.CurrencyUtil
	local DataManager = ctx.DataManager
	local GTRActionDiagnostics = ctx.GTRActionDiagnostics
	local RunService = ctx.RunService
	local function getEquippedCrewMemberToolInfo(...)
		return ctx.getEquippedCrewMemberToolInfo(...)
	end
	local function getLevelUpRefs(...)
		return ctx.getLevelUpRefs(...)
	end
	local function getPlayerStandCrewMemberInstanceId(...)
		return ctx.getPlayerStandCrewMemberInstanceId(...)
	end
	local function getPlayerStandCrewMemberInstanceIdReadOnly(...)
		if typeof(ctx.getPlayerStandCrewMemberInstanceIdReadOnly) == "function" then
			return ctx.getPlayerStandCrewMemberInstanceIdReadOnly(...)
		end
		return ctx.getPlayerStandCrewMemberInstanceId(...)
	end
	local function getPlayerStandIncome(...)
		return ctx.getPlayerStandIncome(...)
	end
	local function getPlayerStandCrewMemberName(...)
		return ctx.getPlayerStandCrewMemberName(...)
	end
	local function getSlotRuntime(...)
		return ctx.getSlotRuntime(...)
	end
	local function getStandIncomeDisplay(...)
		return ctx.getStandIncomeDisplay(...)
	end
	local function getStandIncomeDisplayReadOnly(...)
		if typeof(ctx.getStandIncomeDisplayReadOnly) == "function" then
			return ctx.getStandIncomeDisplayReadOnly(...)
		end
		return ctx.getStandIncomeDisplay(...)
	end
	local function getStandIncomePerSecond(...)
		return ctx.getStandIncomePerSecond(...)
	end
	local function getStandCollectMultiplier(...)
		return ctx.getStandCollectMultiplier(...)
	end
	local function getStandClaimSummary(...)
		return ctx.getStandClaimSummary(...)
	end
	local function getRewardBeliMultiplier(...)
		return ctx.getRewardBeliMultiplier(...)
	end
	local function getRewardMultiplierMetadata(...)
		return ctx.getRewardMultiplierMetadata(...)
	end
	local function getStandSlotState(...)
		return ctx.getStandSlotState(...)
	end
	local INCOME_STATUS_DISPLAY_METADATA_CACHE_SECONDS = ctx.INCOME_STATUS_DISPLAY_METADATA_CACHE_SECONDS
	local IncomeClaimMath = ctx.IncomeClaimMath
	local incomeStatusDisplayMetadataRequest = ctx.incomeStatusDisplayMetadataRequest
	local function isLiveSlotDescendant(...)
		return ctx.isLiveSlotDescendant(...)
	end
	local MoneyCollectedRE = ctx.MoneyCollectedRE
	local function normalizeIncomeSnapshotSlotKey(...)
		return ctx.normalizeIncomeSnapshotSlotKey(...)
	end
	local PLACEMENT_PICKUP_GUARD_SECONDS = ctx.PLACEMENT_PICKUP_GUARD_SECONDS
	local placementPickupGuardUntil = ctx.placementPickupGuardUntil
	local Players = ctx.Players
	local playerStandList = ctx.playerStandList
	local PlotUpgradeConfig = ctx.PlotUpgradeConfig
	local function refreshSlotRuntimeRefs(...)
		return ctx.refreshSlotRuntimeRefs(...)
	end
	local function resolveIncomeStatusDisplayName(...)
		return ctx.resolveIncomeStatusDisplayName(...)
	end
	local function resolveStandStatusDisplayName(...)
		return ctx.resolveStandStatusDisplayName(...)
	end
	local function setStandLevel(...)
		return ctx.setStandLevel(...)
	end
	local ShipSlotLevelPanelState = ctx.ShipSlotLevelPanelState
	local ShipSlotService = ctx.ShipSlotService
	local SLOT_LEVEL_UI_REFRESH_INTERVAL_SECONDS = ctx.SLOT_LEVEL_UI_REFRESH_INTERVAL_SECONDS
	local function standDebug(...)
		return ctx.standDebug(...)
	end

	local function isPlayerDataReady(player)
		if typeof(player) ~= "Instance" or not player:IsA("Player") or player.Parent ~= Players then
			return false
		end
		if DataManager and typeof(DataManager.IsHardResetPending) == "function" and DataManager:IsHardResetPending(player.UserId) then
			return false
		end
		if DataManager and typeof(DataManager.IsReady) == "function" and not DataManager:IsReady(player) then
			return false
		end
		return true
	end
	local function getCrewInventorySnapshot(player)
		if DataManager and typeof(DataManager.TryGetValue) == "function" then
			local inventory = DataManager:TryGetValue(player, "CrewMemberInventory")
			if typeof(inventory) == "table" then
				return inventory
			end
		end
		return nil
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
			if typeof(DataManager.TryGetValue) == "function" then
				return DataManager:TryGetValue(player, "CrewMemberIncome")
			end
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
				local rawIncomeToCollect = math.max(0, tonumber(getPlayerStandIncome(player, standName)) or 0)
				local collectMultiplier = getStandCollectMultiplier(player, standName)
				local claimSummary = getStandClaimSummary(player, standName)
				local claimReadyAmount = math.max(0, math.floor(tonumber(claimSummary.FinalAmount) or 0))
				local exactClaimReadyAmount = math.max(0, tonumber(claimSummary.ExactAmount) or 0)
				local claimRemainderAmount = math.max(0, exactClaimReadyAmount - claimReadyAmount)
				local incomePerSecond = math.max(0, getStandIncomePerSecond(player, standName, crewMemberName))

				snapshot.Stands[standName] = {
					SlotKey = standName,
					CrewMemberName = crewMemberName,
					CrewMemberInstanceId = tostring(standData.CrewMemberInstanceId or ""),
					StandLevel = CrewIncomeBalance.NormalizeLevel(standData.StandLevel),
					RawIncomeToCollect = rawIncomeToCollect,
					CollectMultiplier = collectMultiplier,
					TitleMultiplier = math.max(0, tonumber(claimSummary.TitleMultiplier) or 1),
					IncomePerSecond = incomePerSecond,
					ExactClaimReadyAmount = exactClaimReadyAmount,
					ClaimReadyAmount = claimReadyAmount,
					ClaimRemainderAmount = claimRemainderAmount,
				}
				snapshot.TotalClaimReadyAmount += claimReadyAmount
				appendCaptainLogRow({
					Key = standName,
					RowType = "Normal",
					SlotKey = standName,
					StandName = standName,
					CrewMemberName = crewMemberName,
					CrewMemberInstanceId = tostring(standData.CrewMemberInstanceId or ""),
					StandLevel = CrewIncomeBalance.NormalizeLevel(standData.StandLevel),
					RawIncomeToCollect = rawIncomeToCollect,
					CollectMultiplier = collectMultiplier,
					TitleMultiplier = math.max(0, tonumber(claimSummary.TitleMultiplier) or 1),
					IncomePerSecond = incomePerSecond,
					ExactClaimReadyAmount = exactClaimReadyAmount,
					ClaimReadyAmount = claimReadyAmount,
					ClaimRemainderAmount = claimRemainderAmount,
				})
			end
		end

		local captainAssignment = CaptainSlotRuntime.GetAssignment(player)
		if typeof(captainAssignment) == "table" then
			local rawCaptainIncome = if typeof(CaptainSlotRuntime.GetCaptainRawIncomeToCollect) == "function"
				then math.max(0, tonumber(CaptainSlotRuntime.GetCaptainRawIncomeToCollect(player)) or 0)
				else math.max(0, tonumber(captainAssignment.IncomeToCollect) or 0)
			local captainCollectMultiplier = math.max(0, CaptainSlotRuntime.GetCaptainCollectMultiplier(player))
			local captainClaimSummary = IncomeClaimMath.BuildClaimSummary(
				rawCaptainIncome,
				captainCollectMultiplier,
				getRewardBeliMultiplier(player),
				getRewardMultiplierMetadata(player)
			)
			local captainClaimReady = math.max(0, math.floor(tonumber(captainClaimSummary.FinalAmount) or 0))
			local captainExactClaimReady = math.max(0, tonumber(captainClaimSummary.ExactAmount) or 0)
			local captainClaimRemainder = math.max(0, captainExactClaimReady - captainClaimReady)
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
			local captainStandLevel = CrewIncomeBalance.NormalizeLevel(captainAssignment.Level or captainAssignment.StandLevel)
			if captainCrewMemberName ~= "" then
				snapshot.Captain = {
					SlotKey = CAPTAIN_SLOT_KEY,
					CrewMemberName = captainCrewMemberName,
					CrewMemberInstanceId = captainCrewMemberInstanceId,
					StandLevel = captainStandLevel,
					RawIncomeToCollect = rawCaptainIncome,
					CollectMultiplier = captainCollectMultiplier,
					TitleMultiplier = math.max(0, tonumber(captainClaimSummary.TitleMultiplier) or 1),
					IncomePerSecond = captainIncomePerSecond,
					ExactClaimReadyAmount = captainExactClaimReady,
					ClaimReadyAmount = captainClaimReady,
					ClaimRemainderAmount = captainClaimRemainder,
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
					TitleMultiplier = math.max(0, tonumber(captainClaimSummary.TitleMultiplier) or 1),
					IncomePerSecond = captainIncomePerSecond,
					ExactClaimReadyAmount = captainExactClaimReady,
					ClaimReadyAmount = captainClaimReady,
					ClaimRemainderAmount = captainClaimRemainder,
				}, true)
			end
		end

		return snapshot
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
		if
			ctx.GTRPerformanceDiagnostics
			and typeof(ctx.GTRPerformanceDiagnostics.RecordDisplayUpdate) == "function"
		then
			ctx.GTRPerformanceDiagnostics.RecordDisplayUpdate("world_ui", 1)
		end
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

	local function setMoneyLabelText(cache, text)
		setTextIfChanged(cache, "LastMoneyText", cache and cache.MoneyLabel, text)
	end

	local function clearLevelPanelState(refs)
		if ShipSlotLevelPanelState and refs and refs.SurfaceGui then
			ShipSlotLevelPanelState.Clear(refs.SurfaceGui)
		end
	end

	local function publishLevelPanelState(refs, state)
		if not ShipSlotLevelPanelState then
			local progressText = if state.IsMaxLevel
				then "Max Level"
				else string.format("XP: %d / %d", math.max(0, state.CurrentXP), math.max(0, state.NextLevelXP))
			if not state.IsMaxLevel then
				progressText ..= if state.HasFood then " | Auto-feed" else " | No Food"
			end
			return {
				levelText = "Current Level: " .. tostring(state.CurrentLevel),
				progressText = progressText,
			}
		end

		local normalized = ShipSlotLevelPanelState.Publish(refs and refs.SurfaceGui, state) or state
		return {
			levelText = ShipSlotLevelPanelState.FormatLevelText(normalized),
			progressText = ShipSlotLevelPanelState.FormatProgressText(normalized),
		}
	end

	local function getUpgradeCostText(player, progressTarget, hasFood, isMaxLevel)
		if not hasFood or isMaxLevel then
			return ""
		end
		if tostring(progressTarget or "") == "" or typeof(CrewFoodProgression.GetNextAutoFeedStep) ~= "function" then
			return ""
		end

		local previewOk, preview = CrewFoodProgression.GetNextAutoFeedStep(player, progressTarget)
		local step = previewOk and preview and preview.Step
		if typeof(step) ~= "table" then
			return ""
		end

		local amountUsed = math.max(0, math.floor(tonumber(step.AmountUsed) or 0))
		local foodName = tostring(step.FoodDisplayName or step.FoodKey or "")
		if amountUsed <= 0 or foodName == "" then
			return ""
		end

		return string.format("%dx %s", amountUsed, foodName)
	end

	local function updateStandMoneyText(player, standModel, cache, slotState, crewMemberName, incomeDisplay)
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
		local resolvedIncomeDisplay = if incomeDisplay ~= nil then incomeDisplay else getStandIncomeDisplay(player, standName)
		local incomeText = CurrencyUtil.formatIncomeCompactAmount(resolvedIncomeDisplay)
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
			clearLevelPanelState(refs)
			setCachedLevelUpVisible(cache, false)
			setTextIfChanged(cache, "LastLevelPriceText", refs.Price, "")
			setTextIfChanged(cache, "LastLevelUpgradeText", refs.Upgrade, "")
			return
		end

		crewMemberName = if crewMemberName ~= nil then crewMemberName else getPlayerStandCrewMemberName(player, standName)
		crewMemberInstanceId = if crewMemberInstanceId ~= nil then crewMemberInstanceId else getPlayerStandCrewMemberInstanceId(player, standName)

		if crewMemberName == "" then
			clearLevelPanelState(refs)
			setCachedLevelUpVisible(cache, false)
			setTextIfChanged(cache, "LastLevelPriceText", refs.Price, "")
			setTextIfChanged(cache, "LastLevelUpgradeText", refs.Upgrade, "")
			standDebug("updateLevelUpUI hidden player=%s stand=%s reason=no_crew_member", player.Name, standName)
			return
		end

		local now = os.clock()
		local availableFoodCount = totalFoodCount
		if availableFoodCount == nil then
			if typeof(CrewFoodProgression.TryGetTotalFoodCount) == "function" then
				availableFoodCount = CrewFoodProgression.TryGetTotalFoodCount(player)
			else
				availableFoodCount = CrewFoodProgression.GetTotalFoodCount(player)
			end
		end
		if availableFoodCount == nil then
			return
		end
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

		local progressTarget = crewMemberInstanceId ~= "" and crewMemberInstanceId or crewMemberName
		local progress = CrewFoodProgression.GetProgress(player, progressTarget)
		if not progress then
			clearLevelPanelState(refs)
			setCachedLevelUpVisible(cache, false)
			setTextIfChanged(cache, "LastLevelPriceText", refs.Price, "")
			setTextIfChanged(cache, "LastLevelUpgradeText", refs.Upgrade, "")
			return
		end

		local currentLevel = if isCaptainSlot then progress.Level else setStandLevel(player, standName, progress.Level)
		local hasFood = availableFoodCount > 0
		local isMaxLevel = currentLevel >= progress.MaxLevel
		local levelPanelState = {
			CurrentLevel = currentLevel,
			CurrentXP = progress.CurrentXP,
			FoodCount = availableFoodCount,
			HasFood = hasFood,
			IsMaxLevel = isMaxLevel,
			MaxLevel = progress.MaxLevel,
			NextLevelXP = progress.NextLevelXP,
			UpgradeCostText = getUpgradeCostText(player, progressTarget, hasFood, isMaxLevel),
		}
		local panelText = publishLevelPanelState(refs, levelPanelState)

		if currentLevel >= progress.MaxLevel then
			setCachedLevelUpVisible(cache, true)
			setTextIfChanged(cache, "LastLevelUpgradeText", refs.Upgrade, panelText.levelText)
			setTextIfChanged(cache, "LastLevelPriceText", refs.Price, panelText.progressText)
			standDebug("updateLevelUpUI maxed player=%s stand=%s currentLevel=%s", player.Name, standName, tostring(currentLevel))
			return
		end

		setCachedLevelUpVisible(cache, true)
		setTextIfChanged(cache, "LastLevelUpgradeText", refs.Upgrade, panelText.levelText)
		setTextIfChanged(cache, "LastLevelPriceText", refs.Price, panelText.progressText)
		standDebug(
			"updateLevelUpUI visible player=%s stand=%s currentLevel=%s currentXP=%s nextXP=%s",
			player.Name,
			standName,
			tostring(currentLevel),
			tostring(progress.CurrentXP),
			tostring(progress.NextLevelXP)
		)
	end


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

	local function getTotalFoodCountForRefresh(player)
		if typeof(CrewFoodProgression.TryGetTotalFoodCount) == "function" then
			return CrewFoodProgression.TryGetTotalFoodCount(player)
		end
		return CrewFoodProgression.GetTotalFoodCount(player)
	end

	local DISPLAY_REFRESH_BUDGET_SECONDS = 0.004
	local DISPLAY_REFRESH_MAX_STANDS_PER_PASS = 4
	local displayRefreshQueue = {}
	local queuedPlayers = {}
	local refreshOrder = {}
	local refreshHeartbeatConnection = nil

	local function findStandModel(player, standName)
		local stands = playerStandList[player]
		if typeof(stands) ~= "table" then
			return nil, "stands_missing"
		end

		for _, candidate in ipairs(stands) do
			if candidate and candidate.Parent and candidate.Name == standName then
				return candidate, nil
			end
		end
		return nil, "stand_not_found"
	end

	local function buildRefreshContext(player)
		local totalFoodCount = getTotalFoodCountForRefresh(player)
		if totalFoodCount == nil then
			return nil, "food_count_unavailable"
		end

		return {
			EquippedCrewMember = getEquippedCrewMemberToolInfo(player),
			InventorySnapshot = getCrewInventorySnapshot(player),
			TotalFoodCount = totalFoodCount,
		}, nil
	end

	local function refreshStandIncomeDisplayForModel(player, standModel, _source, refreshContext)
		if typeof(player) ~= "Instance" or not player:IsA("Player") then
			return false, "invalid_player"
		end
		if typeof(standModel) ~= "Instance" or not standModel.Parent then
			return false, "stand_not_found"
		end

		refreshContext = if typeof(refreshContext) == "table" then refreshContext else nil
		if refreshContext == nil then
			local context, reason = buildRefreshContext(player)
			if context == nil then
				return false, reason
			end
			refreshContext = context
		end

		local standName = standModel.Name
		local cache = getSlotRuntime(player, standModel.Parent, standModel)
		local slotState = getStandSlotState(player, standName)
		local crewMemberName = getPlayerStandCrewMemberName(player, standName)
		local crewMemberInstanceId = if crewMemberName ~= ""
			then getPlayerStandCrewMemberInstanceIdReadOnly(player, standName, refreshContext.InventorySnapshot)
			else ""
		local incomeDisplay = getStandIncomeDisplayReadOnly(player, standName, refreshContext.InventorySnapshot)

		updateStandMoneyText(player, standModel, cache, slotState, crewMemberName, incomeDisplay)
		updateLevelUpUI(
			player,
			standModel,
			cache,
			slotState,
			crewMemberName,
			crewMemberInstanceId,
			false,
			refreshContext.TotalFoodCount
		)
		updateStandPromptTexts(player, standModel, cache, slotState, crewMemberName, refreshContext.EquippedCrewMember)
		return true, nil
	end

	local function refreshStandIncomeDisplay(player, standName, source)
		if typeof(player) ~= "Instance" or not player:IsA("Player") then
			return false, "invalid_player"
		end
		if not isPlayerDataReady(player) then
			return false, "data_not_ready"
		end

		standName = tostring(standName or "")
		if standName == "" then
			return false, "invalid_stand"
		end

		local standModel, findReason = findStandModel(player, standName)
		if standModel == nil then
			return false, findReason
		end

		return refreshStandIncomeDisplayForModel(player, standModel, source, nil)
	end

	local function countQueuedFullRefreshes()
		local count = 0
		for _, state in pairs(displayRefreshQueue) do
			if state.FullQueued == true then
				count += 1
			end
		end
		return count
	end

	local function countDirtyRefreshes(state)
		return if typeof(state) == "table" and typeof(state.DirtyOrder) == "table" then #state.DirtyOrder else 0
	end

	local function logRefreshPass(player, phase, durationSeconds, result, metadata)
		if not GTRActionDiagnostics or typeof(GTRActionDiagnostics.Log) ~= "function" then
			return
		end
		metadata = if typeof(metadata) == "table" then metadata else {}
		GTRActionDiagnostics.Log("CrewIncome.DisplayRefresh", player, phase, durationSeconds, result, metadata)
	end

	local processRefreshQueue

	local function ensureRefreshHeartbeat()
		if refreshHeartbeatConnection ~= nil then
			return
		end
		if not RunService or typeof(RunService.Heartbeat) ~= "RBXScriptSignal" then
			return
		end

		refreshHeartbeatConnection = RunService.Heartbeat:Connect(function()
			processRefreshQueue()
		end)
	end

	local function enqueuePlayerForRefresh(player)
		if typeof(player) ~= "Instance" or not player:IsA("Player") then
			return false, "invalid_player"
		end
		if queuedPlayers[player] == true then
			return true, nil
		end

		queuedPlayers[player] = true
		table.insert(refreshOrder, player)
		ensureRefreshHeartbeat()
		return true, nil
	end

	local function getRefreshState(player)
		local state = displayRefreshQueue[player]
		if state == nil then
			state = {
				DirtyMap = {},
				DirtyOrder = {},
				DirtySources = {},
				FullIndex = 1,
				FullQueued = false,
				FullSource = "",
			}
			displayRefreshQueue[player] = state
		end
		return state
	end

	local function enqueueStandIncomeDisplayRefresh(player, standName, source)
		if typeof(player) ~= "Instance" or not player:IsA("Player") then
			return false, "invalid_player"
		end
		standName = tostring(standName or "")
		if standName == "" then
			return false, "invalid_stand"
		end

		local state = getRefreshState(player)
		if state.DirtyMap[standName] ~= true then
			state.DirtyMap[standName] = true
			table.insert(state.DirtyOrder, standName)
		end
		state.DirtySources[standName] = tostring(source or "dirty_stand_refresh")
		return enqueuePlayerForRefresh(player)
	end

	local function enqueuePlayerIncomeDisplayRefresh(player, source)
		if typeof(player) ~= "Instance" or not player:IsA("Player") then
			return false, "invalid_player"
		end

		local state = getRefreshState(player)
		state.FullQueued = true
		state.FullIndex = 1
		state.FullSource = tostring(source or "full_display_refresh")
		return enqueuePlayerForRefresh(player)
	end

	processRefreshQueue = function()
		if #refreshOrder <= 0 then
			if refreshHeartbeatConnection ~= nil then
				refreshHeartbeatConnection:Disconnect()
				refreshHeartbeatConnection = nil
			end
			return
		end

		local player = table.remove(refreshOrder, 1)
		queuedPlayers[player] = nil
		local state = displayRefreshQueue[player]
		if typeof(player) ~= "Instance" or not player:IsA("Player") or player.Parent ~= Players or typeof(state) ~= "table" then
			displayRefreshQueue[player] = nil
			return
		end

		if not isPlayerDataReady(player) then
			task.delay(0.25, function()
				if player and player.Parent == Players and displayRefreshQueue[player] ~= nil then
					enqueuePlayerForRefresh(player)
				end
			end)
			return
		end

		local passStartedAt = os.clock()
		local processed = 0
		local failedReason = nil
		local refreshContext, contextReason = buildRefreshContext(player)
		if refreshContext == nil then
			failedReason = contextReason or "refresh_context_unavailable"
			task.delay(0.25, function()
				if player and player.Parent == Players and displayRefreshQueue[player] ~= nil then
					enqueuePlayerForRefresh(player)
				end
			end)
		else
			while
				processed < DISPLAY_REFRESH_MAX_STANDS_PER_PASS
				and (os.clock() - passStartedAt) < DISPLAY_REFRESH_BUDGET_SECONDS
				and #state.DirtyOrder > 0
			do
				local standName = table.remove(state.DirtyOrder, 1)
				if state.DirtyMap[standName] == true then
					state.DirtyMap[standName] = nil
					local source = state.DirtySources[standName] or "dirty_stand_refresh"
					state.DirtySources[standName] = nil
					local standModel = findStandModel(player, standName)
					if standModel ~= nil then
						local ok, reason = refreshStandIncomeDisplayForModel(player, standModel, source, refreshContext)
						if ok == false then
							failedReason = reason
						end
					end
					processed += 1
				end
			end

			if
				#state.DirtyOrder <= 0
				and state.FullQueued == true
				and processed < DISPLAY_REFRESH_MAX_STANDS_PER_PASS
				and (os.clock() - passStartedAt) < DISPLAY_REFRESH_BUDGET_SECONDS
			then
				local stands = playerStandList[player]
				if typeof(stands) ~= "table" then
					state.FullQueued = false
					state.FullIndex = 1
					failedReason = "stands_missing"
				else
					while
						state.FullQueued == true
						and state.FullIndex <= #stands
						and processed < DISPLAY_REFRESH_MAX_STANDS_PER_PASS
						and (os.clock() - passStartedAt) < DISPLAY_REFRESH_BUDGET_SECONDS
					do
						local standModel = stands[state.FullIndex]
						state.FullIndex += 1
						if standModel and standModel.Parent then
							local ok, reason = refreshStandIncomeDisplayForModel(
								player,
								standModel,
								state.FullSource or "queued_full_display_refresh",
								refreshContext
							)
							if ok == false then
								failedReason = reason
							end
							processed += 1
						end
					end

					if state.FullIndex > #stands then
						state.FullQueued = false
						state.FullIndex = 1
					end
				end
			end
		end

		local hasMoreWork = refreshContext ~= nil and (state.FullQueued == true or #state.DirtyOrder > 0)
		local durationSeconds = os.clock() - passStartedAt
		logRefreshPass(player, "pass", durationSeconds, if failedReason then "partial" else "ok", {
			Reason = failedReason,
			ProcessedStands = processed,
			QueuedFull = countQueuedFullRefreshes(),
			DirtyQueued = countDirtyRefreshes(state),
			Source = state.FullSource,
		})

		if refreshContext == nil then
			return
		end

		if hasMoreWork then
			enqueuePlayerForRefresh(player)
		else
			displayRefreshQueue[player] = nil
		end
	end

	local function refreshPlayerIncomeDisplays(player)
		return enqueuePlayerIncomeDisplayRefresh(player, "refresh_player_income_displays")
	end

	local function refreshPlayerIncomeDisplaysAfterLifecycleUpdate(player)
		return enqueuePlayerIncomeDisplayRefresh(player, "lifecycle_update")
	end


	ctx.buildIncomeSnapshot = buildIncomeSnapshot
	ctx.buildIncomeStatusDisplayMetadataResponse = buildIncomeStatusDisplayMetadataResponse
	ctx.fireMoneyCollected = fireMoneyCollected
	ctx.getPlacementPickupGuardRemaining = getPlacementPickupGuardRemaining
	ctx.enqueuePlayerIncomeDisplayRefresh = enqueuePlayerIncomeDisplayRefresh
	ctx.enqueueStandIncomeDisplayRefresh = enqueueStandIncomeDisplayRefresh
	ctx.refreshPlayerIncomeDisplays = refreshPlayerIncomeDisplays
	ctx.refreshPlayerIncomeDisplaysAfterLifecycleUpdate = refreshPlayerIncomeDisplaysAfterLifecycleUpdate
	ctx.refreshStandIncomeDisplay = refreshStandIncomeDisplay
	ctx.setCachedLevelUpVisible = setCachedLevelUpVisible
	ctx.setMoneyLabelText = setMoneyLabelText
	ctx.setPlacementPickupGuard = setPlacementPickupGuard
	ctx.setTextIfChanged = setTextIfChanged
	ctx.updateCaptainLevelUpUI = updateCaptainLevelUpUI
	ctx.updateLevelUpUI = updateLevelUpUI
	ctx.updateStandMoneyText = updateStandMoneyText
	ctx.updateStandPromptTexts = updateStandPromptTexts
end

return Module
