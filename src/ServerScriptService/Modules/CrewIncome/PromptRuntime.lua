local Module = {}

function Module.Install(ctx)
	local ALLOW_NON_OWNER_STEAL_PROMPTS = ctx.ALLOW_NON_OWNER_STEAL_PROMPTS
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
	local CrewQuickSlotService = ctx.CrewQuickSlotService
	local DataManager = ctx.DataManager
	local DEBUG_TRACE = ctx.DEBUG_TRACE
	local function dmEnsureStandFolder(...)
		return ctx.dmEnsureStandFolder(...)
	end
	local function ensureLevelUpClickDetector(...)
		return ctx.ensureLevelUpClickDetector(...)
	end
	local function findAvailableTutorialPlacementReward(...)
		return ctx.findAvailableTutorialPlacementReward(...)
	end
	local function findCrewMemberInfoByName(...)
		return ctx.findCrewMemberInfoByName(...)
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
	local function getInventoryQuantity(...)
		return ctx.getInventoryQuantity(...)
	end
	local function getPickupDebugField(...)
		return ctx.getPickupDebugField(...)
	end
	local function getPickupStandSnapshot(...)
		return ctx.getPickupStandSnapshot(...)
	end
	local function getPlayerStandCrewMemberInstanceId(...)
		return ctx.getPlayerStandCrewMemberInstanceId(...)
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
	local MarketplaceService = ctx.MarketplaceService
	local MonetizationConfig = ctx.MonetizationConfig
	local function normalizeRarity(...)
		return ctx.normalizeRarity(...)
	end
	local PLACEMENT_PICKUP_GUARD_SECONDS = ctx.PLACEMENT_PICKUP_GUARD_SECONDS
	local placementPickupGuardUntil = ctx.placementPickupGuardUntil
	local Players = ctx.Players
	local PopUpModule = ctx.PopUpModule
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
	local STEAL_PRODUCT_BY_RARITY = ctx.STEAL_PRODUCT_BY_RARITY
	local stealPromptDebounce = ctx.stealPromptDebounce
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
		return ctx.updateStandPromptTexts(...)
	end

	local function getStealProductIdForCrewMember(crewMemberName)
		local info = findCrewMemberInfoByName(crewMemberName)
		local rarity = info and info.Rarity or "Common"
		local fixed = normalizeRarity(rarity)
		return STEAL_PRODUCT_BY_RARITY[fixed] or 3512126073
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
					if not ALLOW_NON_OWNER_STEAL_PROMPTS then
						standDebug(
							"prompt rejected actor=%s stand=%s reason=non_owner_interaction_disabled ownerUserId=%s",
							plr.Name,
							standName,
							tostring(ownerUserId)
						)
						return
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



	ctx.bindLevelUp = bindLevelUp
	ctx.bindStandPrompt = bindStandPrompt
	ctx.equipCrewMemberToolByInstanceId = equipCrewMemberToolByInstanceId
	ctx.findCrewMemberToolByInstanceId = findCrewMemberToolByInstanceId
	ctx.getPlacementPickupGuardRemaining = getPlacementPickupGuardRemaining
	ctx.getStealProductIdForCrewMember = getStealProductIdForCrewMember
	ctx.setPlacementPickupGuard = setPlacementPickupGuard
end

return Module
