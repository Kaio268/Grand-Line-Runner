local Module = {}

function Module.Install(ctx)
	local function bindZoneCollect(...)
		return ctx.bindZoneCollect(...)
	end
	local function clearCrewRecordCache(...)
		return ctx.clearCrewRecordCache(...)
	end
	local function clearPlacedStandIncome(...)
		return ctx.clearPlacedStandIncome(...)
	end
	local function clearStandVisual(...)
		return ctx.clearStandVisual(...)
	end
	local CrewInstanceService = ctx.CrewInstanceService
	local function crewPickupDebug(...)
		return ctx.crewPickupDebug(...)
	end
	local DEBUG_TRACE = ctx.DEBUG_TRACE
	local function dmEnsureStandFolder(...)
		return ctx.dmEnsureStandFolder(...)
	end
	local function ensureLevelUpClickDetector(...)
		return ctx.ensureLevelUpClickDetector(...)
	end
	local function formatCrewPickupDebugFields(...)
		return ctx.formatCrewPickupDebugFields(...)
	end
	local function getCrewMemberLevel(...)
		return ctx.getCrewMemberLevel(...)
	end
	local function getEquippedCrewMemberToolInfo(...)
		return ctx.getEquippedCrewMemberToolInfo(...)
	end
	local function getIncomeWithLevel(...)
		return ctx.getIncomeWithLevel(...)
	end
	local function getPickupDebugField(...)
		return ctx.getPickupDebugField(...)
	end
	local function getPickupStandSnapshot(...)
		return ctx.getPickupStandSnapshot(...)
	end
	local function getPlayerStandCrewMemberName(...)
		return ctx.getPlayerStandCrewMemberName(...)
	end
	local function getSlotRuntime(...)
		return ctx.getSlotRuntime(...)
	end
	local function getStandSlotState(...)
		return ctx.getStandSlotState(...)
	end
	local function getToolCrewMemberInstanceId(...)
		return ctx.getToolCrewMemberInstanceId(...)
	end
	local function logCrewSwitchFailure(...)
		return ctx.logCrewSwitchFailure(...)
	end
	local PLACEMENT_PICKUP_GUARD_SECONDS = ctx.PLACEMENT_PICKUP_GUARD_SECONDS
	local placementPickupGuardUntil = ctx.placementPickupGuardUntil
	local Players = ctx.Players
	local PopUpModule = ctx.PopUpModule
	local PremiumCrewStealService = ctx.PremiumCrewStealService
	local QuestSignals = ctx.QuestSignals
	local function refreshSlotRuntimeRefs(...)
		return ctx.refreshSlotRuntimeRefs(...)
	end
	local function setStandLevel(...)
		return ctx.setStandLevel(...)
	end
	local ShipRuntimeService = ctx.ShipRuntimeService
	local function spawnStandCrewMember(...)
		return ctx.spawnStandCrewMember(...)
	end
	local function standDebug(...)
		return ctx.standDebug(...)
	end
	local function syncStandLevelFromCrewMember(...)
		return ctx.syncStandLevelFromCrewMember(...)
	end
	local function tutorialStandPlacementLog(...)
		return ctx.tutorialStandPlacementLog(...)
	end
	local function updateLevelUpUI(...)
		return ctx.updateLevelUpUI(...)
	end
	local function updateStandMoneyText(...)
		return ctx.updateStandMoneyText(...)
	end
	local function updateStandPromptTexts(...)
		local result = ctx.updateStandPromptTexts(...)
		local owner = select(1, ...)
		local standModel = select(2, ...)
		local cache = select(3, ...)
		if ctx.PremiumCrewStealPromptRuntime and typeof(ctx.PremiumCrewStealPromptRuntime.UpdateStandPrompt) == "function" then
			local activeShip = standModel and standModel.Parent
			ctx.PremiumCrewStealPromptRuntime.UpdateStandPrompt(ctx, owner, activeShip, standModel, cache)
		end
		return result
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

				if not ShipRuntimeService.IsActiveShip(plot) then
					standDebug("prompt rejected actor=%s stand=%s reason=inactive_ship", plr.Name, standModel.Name)
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
					standDebug(
						"prompt rejected actor=%s stand=%s reason=non_owner_use_premium_steal_prompt ownerUserId=%s",
						plr.Name,
						standName,
						tostring(ownerUserId)
					)
					return
				end

				dmEnsureStandFolder(plr, standName)
				if PremiumCrewStealService and typeof(PremiumCrewStealService.IsStandLocked) == "function" then
					local locked = PremiumCrewStealService.IsStandLocked(plr, standName)
					if locked then
						PopUpModule:Server_SendPopUp(
							plr,
							"This stand is reserved for a premium steal purchase. Try again in a moment.",
							Color3.fromRGB(255, 104, 104),
							Color3.fromRGB(0, 0, 0),
							3,
							true
						)
						updateStandMoneyText(plr, standModel)
						updateLevelUpUI(plr, standModel)
						updateStandPromptTexts(plr, standModel)
						return
					end
				end
				local slotState = getStandSlotState(plr, standName)
				local equippedInfo = getEquippedCrewMemberToolInfo(plr)
				local function getExactTutorialPlacementInstance()
					if not equippedInfo or tostring(equippedInfo.InstanceId or "") == "" then
						return nil, nil
					end

					local tutorialInstanceId, tutorialInstance = CrewInstanceService.GetInstance(plr, equippedInfo.InstanceId)
					if tutorialInstance and tutorialInstance.TutorialReward == true then
						return tutorialInstanceId, tutorialInstance
					end
					return nil, nil
				end
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

						local tutorialInstanceId, tutorialInstance = getExactTutorialPlacementInstance()
						local incomingInstanceId, incomingInstance, outgoingInstanceId, outgoingInstance, switchReason, switchDebug =
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
							"switch accepted player=%s stand=%s incoming=%s outgoing=%s incomingStorage=%s outgoingStorage=%s outgoingDestination=%s",
							plr.Name,
							standName,
							tostring(incomingInstanceId),
							tostring(outgoingInstanceId),
							tostring(incomingInstance.StorageName or ""),
							tostring(outgoingInstance and outgoingInstance.StorageName or ""),
							tostring(switchDebug and switchDebug.OutgoingDestination or "")
						)
						if tostring(switchDebug and switchDebug.OutgoingDestination or "") == "Hotbar" then
							equipCrewMemberToolByInstanceId(plr, outgoingInstanceId, outgoingInstance and outgoingInstance.StorageName or "")
						end
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
						{ "destination", getPickupDebugField(releaseDebug, "ReleaseDestination", "") },
						{ "quickSlotIndex", getPickupDebugField(releaseDebug, "ReleaseQuickSlotIndex", "") },
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
				if not toolName or toolName == "" then
					tutorialStandPlacementLog(plr, standName, "no_equipped_crewmate", "action=reject requires_equipped_tutorial_reward")
					logCrewSwitchFailure(plr, standName, "no_equipped_crewmate", "empty_slot_place_rejected")
					standDebug("place rejected player=%s stand=%s reason=no_equipped_crewmate", plr.Name, standName)
					return
				end

				if tostring(equippedInfo.InstanceId or "") == "" then
					tutorialStandPlacementLog(plr, standName, "incoming_instance_missing", string.format("action=reject tool=%s", tostring(toolName)))
					logCrewSwitchFailure(plr, standName, "incoming_instance_missing", "equipped_tool_missing_instance_id")
					standDebug("place rejected player=%s stand=%s tool=%s reason=incoming_instance_missing", plr.Name, standName, tostring(toolName))
					return
				end

				local tutorialInstanceId, tutorialInstance = getExactTutorialPlacementInstance()
				local placedInstanceId, placedInstance, placeReason
				placedInstanceId, placedInstance, placeReason = CrewInstanceService.AssignInstanceToStand(plr, equippedInfo.InstanceId, standName, {
					ExpectedIncomingStorageName = toolName,
					ClearTutorialMetadataAfterAssign = tutorialInstance ~= nil
						and tostring(tutorialInstanceId) == tostring(equippedInfo.InstanceId),
				})
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
				standDebug("place accepted player=%s stand=%s tool=%s instanceId=%s", plr.Name, standName, tostring(toolName), tostring(placedInstanceId))

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



	ctx.bindLevelUp = bindLevelUp
	ctx.bindStandPrompt = bindStandPrompt
	ctx.equipCrewMemberToolByInstanceId = equipCrewMemberToolByInstanceId
	ctx.findCrewMemberToolByInstanceId = findCrewMemberToolByInstanceId
	ctx.getPlacementPickupGuardRemaining = getPlacementPickupGuardRemaining
	ctx.setPlacementPickupGuard = setPlacementPickupGuard
end

return Module
