local Module = {}

function Module.Install(ctx)
	local CaptainSlotRuntime = ctx.CaptainSlotRuntime
	local CollectionService = ctx.CollectionService
	local CrewOverhead = ctx.CrewOverhead
	local CrewCatalog = ctx.CrewCatalog
	local CrewIncomeBalance = ctx.CrewIncomeBalance
	local CrewInstanceService = ctx.CrewInstanceService
	local CrewProtectionService = ctx.CrewProtectionService
	local PlacedCrewState = require(ctx.Modules:WaitForChild("Crew"):WaitForChild("PlacedCrewState"))
	local function findCrewMemberInfoByName(...)
		return ctx.findCrewMemberInfoByName(...)
	end
	local function findTemplateForName(...)
		return ctx.findTemplateForName(...)
	end
	local function getExistingSlotRuntime(...)
		return ctx.getExistingSlotRuntime(...)
	end
	local function getStandIncomePerSecond(...)
		return ctx.getStandIncomePerSecond(...)
	end
	local function getStandSlotState(...)
		return ctx.getStandSlotState(...)
	end
	local function getPlayerStandCrewMemberInstanceId(...)
		if typeof(ctx.getPlayerStandCrewMemberInstanceId) == "function" then
			return ctx.getPlayerStandCrewMemberInstanceId(...)
		end

		return ""
	end
	local function isStandIncomeBoosted(...)
		if typeof(ctx.isStandIncomeBoosted) == "function" then
			return ctx.isStandIncomeBoosted(...)
		end

		return false
	end
	local LEGACY_STAND_CREW_PLACEMENT_ROTATION_OFFSET_DEGREES = ctx.LEGACY_STAND_CREW_PLACEMENT_ROTATION_OFFSET_DEGREES
	local OVERHEAD_ATTRIBUTES = ctx.OVERHEAD_ATTRIBUTES
	local function resetSlotRenderState(...)
		return ctx.resetSlotRenderState(...)
	end
	local function resolveCrewMemberRecord(...)
		return ctx.resolveCrewMemberRecord(...)
	end
	local function resolveStandStatusDisplayName(...)
		return ctx.resolveStandStatusDisplayName(...)
	end
	local function setAttributeIfChanged(...)
		return ctx.setAttributeIfChanged(...)
	end
	local ShipRuntimeService = ctx.ShipRuntimeService
	local ShipSlotService = ctx.ShipSlotService
	local ShipVisuals = ctx.ShipVisuals
	local PremiumCrewStealProtectionVisuals = ctx.PremiumCrewStealProtectionVisuals
	local function standDebug(...)
		return ctx.standDebug(...)
	end
	local function removeLegacyCrewHover(model)
		for _, descendant in ipairs(model:GetDescendants()) do
			if descendant.Name == "CrewMemberHover" and descendant:IsA("BillboardGui") then
				descendant:Destroy()
			end
		end
	end

	local function getInstanceDataReadOnly(player, instanceId)
		instanceId = tostring(instanceId or "")
		if
			instanceId == ""
			or CrewInstanceService == nil
			or typeof(CrewInstanceService.GetInstanceReadOnly) ~= "function"
		then
			return nil
		end

		local _, instanceData = CrewInstanceService.GetInstanceReadOnly(player, instanceId)
		if typeof(instanceData) == "table" then
			return instanceData
		end
		return nil
	end

	local function resolveSavedRarityVariant(instanceData, fallbackRarity, fallbackVariant)
		local rarity = tostring(fallbackRarity or "")
		local variant = tostring(fallbackVariant or "Normal")
		if typeof(instanceData) == "table" then
			local savedRarity = tostring(instanceData.Rarity or "")
			if savedRarity ~= "" then
				rarity = if CrewIncomeBalance and typeof(CrewIncomeBalance.NormalizeRarity) == "function"
					then CrewIncomeBalance.NormalizeRarity(savedRarity)
					else savedRarity
			end

			local savedVariant = tostring(instanceData.Variant or "")
			if savedVariant ~= "" then
				variant = if CrewIncomeBalance and typeof(CrewIncomeBalance.NormalizeVariant) == "function"
					then CrewIncomeBalance.NormalizeVariant(savedVariant)
					else savedVariant
			end
		end

		if rarity == "" then
			rarity = "Common"
		end
		if variant == "" then
			variant = "Normal"
		end
		return rarity, variant
	end

	local function syncPlacedOverheadMetadata(player, standModel, crewMemberName, placedModel)
		if typeof(placedModel) ~= "Instance" then
			return
		end

		local resolved = resolveCrewMemberRecord(player, crewMemberName)
		local info = resolved and resolved.Info or findCrewMemberInfoByName(crewMemberName, player)
		local canonicalName = resolved and resolved.CanonicalName or tostring(crewMemberName)
		local rawName = info and tostring(info.Name or info.DisplayName or canonicalName) or tostring(crewMemberName)
		local rawRarity = info and tostring(info.Rarity or "") or "Common"
		local displayInfo = if CrewCatalog and typeof(CrewCatalog.GetDisplayInfo) == "function"
			then CrewCatalog.GetDisplayInfo(canonicalName, {
				DisplayName = rawName,
				Variant = resolved and resolved.VariantKey,
			})
			else nil
		local variantKey = tostring((displayInfo and displayInfo.Variant) or (resolved and resolved.VariantKey) or "Normal")
		local displayName = tostring((displayInfo and displayInfo.DisplayName) or rawName)
		local helperDisplayName = resolveStandStatusDisplayName(player, crewMemberName)
		if helperDisplayName ~= "" then
			local helperDisplayInfo = if CrewCatalog and typeof(CrewCatalog.GetDisplayInfo) == "function"
				then CrewCatalog.GetDisplayInfo(canonicalName, {
					DisplayName = helperDisplayName,
					Variant = variantKey,
				})
				else nil
			displayName = tostring((helperDisplayInfo and helperDisplayInfo.DisplayName) or helperDisplayName)
		end

		local displayRarity = rawRarity
		local isCaptainSlot = ShipSlotService.IsCaptainSlotName(standModel.Name)
		local crewMemberInstanceId = if isCaptainSlot
			then ""
			else tostring(getPlayerStandCrewMemberInstanceId(player, standModel.Name) or "")
		if isCaptainSlot and typeof(CaptainSlotRuntime.GetAssignment) == "function" then
			local assignment = CaptainSlotRuntime.GetAssignment(player)
			if typeof(assignment) == "table" then
				crewMemberInstanceId = tostring(
					assignment.CrewMemberInstanceId
						or assignment.InstanceId
						or assignment.CrewInstanceId
						or crewMemberInstanceId
				)
			end
		end
		local incomePerSecond = if isCaptainSlot
			then CaptainSlotRuntime.GetCaptainIncomePerSecond(player)
			else getStandIncomePerSecond(player, standModel.Name, canonicalName)
		local incomeBoosted = if isCaptainSlot
			then CaptainSlotRuntime.IsCaptainIncomeBoosted(player)
			else isStandIncomeBoosted(player, standModel.Name, canonicalName)
		local slotState = if isCaptainSlot then nil else getStandSlotState(player, standModel.Name)
		local slotBonusInfo = slotState and slotState.BonusInfo or nil
		local instanceData = getInstanceDataReadOnly(player, crewMemberInstanceId)
		displayRarity, variantKey = resolveSavedRarityVariant(instanceData, displayRarity, variantKey)

		setAttributeIfChanged(placedModel, OVERHEAD_ATTRIBUTES.Kind, CrewOverhead.Kind.Placed)
		setAttributeIfChanged(placedModel, OVERHEAD_ATTRIBUTES.DisplayName, displayName)
		setAttributeIfChanged(placedModel, OVERHEAD_ATTRIBUTES.Rarity, if displayRarity ~= "" then displayRarity else "Common")
		setAttributeIfChanged(placedModel, OVERHEAD_ATTRIBUTES.Variant, variantKey)
		setAttributeIfChanged(placedModel, OVERHEAD_ATTRIBUTES.IncomePerSecond, math.max(0, incomePerSecond))
		setAttributeIfChanged(placedModel, OVERHEAD_ATTRIBUTES.BeliBoosted, incomeBoosted == true)
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
		setAttributeIfChanged(
			placedModel,
			OVERHEAD_ATTRIBUTES.InstanceId,
			if crewMemberInstanceId ~= "" then crewMemberInstanceId else nil
		)
		setAttributeIfChanged(placedModel, OVERHEAD_ATTRIBUTES.ExpiresAt, nil)
		setAttributeIfChanged(placedModel, OVERHEAD_ATTRIBUTES.DespawnSeconds, nil)
		if
			CrewProtectionService
			and typeof(CrewProtectionService.ApplyPlacedProtectionAttributes) == "function"
			and placedModel:IsA("Model")
		then
			CrewProtectionService.ApplyPlacedProtectionAttributes(
				player,
				placedModel,
				crewMemberInstanceId,
				true,
				ctx.DataManager
			)
		end
		removeLegacyCrewHover(placedModel)
		if placedModel:IsA("Model") and not CollectionService:HasTag(placedModel, CrewOverhead.Tag) then
			CollectionService:AddTag(placedModel, CrewOverhead.Tag)
		end
	end

	local function getPlacedProtectionState(player, instanceId, isPlaced)
		if
			CrewProtectionService
			and typeof(CrewProtectionService.ResolveProtectionDisplayState) == "function"
		then
			local state = CrewProtectionService.ResolveProtectionDisplayState(player, instanceId, isPlaced == true, ctx.DataManager)
			if typeof(state) == "table" then
				return state
			end
		end

		return {
			Type = "none",
			Label = "",
			Detail = "",
		}
	end

	local timestampAttributes = {
		[PlacedCrewState.Attribute.IncomeUpdatedAtUnix] = true,
		[PlacedCrewState.Attribute.UpdatedAtUnix] = true,
	}

	local function hasAttributeChanges(instance, attributes)
		if typeof(instance) ~= "Instance" or typeof(attributes) ~= "table" then
			return false
		end

		for attributeName, value in pairs(attributes) do
			if timestampAttributes[attributeName] ~= true and instance:GetAttribute(attributeName) ~= value then
				return true
			end
		end

		return false
	end

	local function buildPlacedCrewStateAttributes(player, standModel, crewMemberName)
		local resolved = resolveCrewMemberRecord(player, crewMemberName)
		local info = resolved and resolved.Info or findCrewMemberInfoByName(crewMemberName, player)
		local canonicalName = resolved and resolved.CanonicalName or tostring(crewMemberName)
		local rawName = info and tostring(info.Name or info.DisplayName or canonicalName) or tostring(crewMemberName)
		local displayInfo = if CrewCatalog and typeof(CrewCatalog.GetDisplayInfo) == "function"
			then CrewCatalog.GetDisplayInfo(canonicalName, {
				DisplayName = rawName,
				Variant = resolved and resolved.VariantKey,
			})
			else nil
		local variantKey = tostring((displayInfo and displayInfo.Variant) or (resolved and resolved.VariantKey) or "Normal")
		local displayName = tostring((displayInfo and displayInfo.DisplayName) or rawName)
		local helperDisplayName = resolveStandStatusDisplayName(player, crewMemberName)
		if helperDisplayName ~= "" then
			local helperDisplayInfo = if CrewCatalog and typeof(CrewCatalog.GetDisplayInfo) == "function"
				then CrewCatalog.GetDisplayInfo(canonicalName, {
					DisplayName = helperDisplayName,
					Variant = variantKey,
				})
				else nil
			displayName = tostring((helperDisplayInfo and helperDisplayInfo.DisplayName) or helperDisplayName)
		end

		local standName = tostring(standModel and standModel.Name or "")
		local isCaptainSlot = ShipSlotService.IsCaptainSlotName(standName)
		local crewMemberInstanceId = if isCaptainSlot
			then ""
			else tostring(getPlayerStandCrewMemberInstanceId(player, standName) or "")
		if isCaptainSlot and typeof(CaptainSlotRuntime.GetAssignment) == "function" then
			local assignment = CaptainSlotRuntime.GetAssignment(player)
			if typeof(assignment) == "table" then
				crewMemberInstanceId = tostring(
					assignment.CrewMemberInstanceId
						or assignment.InstanceId
						or assignment.CrewInstanceId
						or crewMemberInstanceId
				)
			end
		end
		local slotState = if isCaptainSlot then nil else getStandSlotState(player, standName)
		local slotBonusInfo = slotState and slotState.BonusInfo or nil
		local instanceData = getInstanceDataReadOnly(player, crewMemberInstanceId)
		local displayRarity = if tostring(info and info.Rarity or "") ~= "" then tostring(info.Rarity) else "Common"
		displayRarity, variantKey = resolveSavedRarityVariant(instanceData, displayRarity, variantKey)
		local stateBaseName = tostring(
			typeof(instanceData) == "table" and tostring(instanceData.BaseName or "") ~= "" and instanceData.BaseName
				or resolved and resolved.BaseName
				or canonicalName
		)
		local incomePerSecond = if isCaptainSlot
			then CaptainSlotRuntime.GetCaptainIncomePerSecond(player)
			else getStandIncomePerSecond(player, standName, canonicalName)
		local rawIncomePerSecond = 0
		local rawIncomeToCollect = 0
		local claimReadyAmount = 0
		if isCaptainSlot then
			if typeof(CaptainSlotRuntime.GetCaptainRawIncomePerSecond) == "function" then
				rawIncomePerSecond = CaptainSlotRuntime.GetCaptainRawIncomePerSecond(player)
			end
			if typeof(CaptainSlotRuntime.GetCaptainRawIncomeToCollect) == "function" then
				rawIncomeToCollect = CaptainSlotRuntime.GetCaptainRawIncomeToCollect(player)
			end
			if typeof(CaptainSlotRuntime.GetCaptainIncomeToCollect) == "function" then
				claimReadyAmount = CaptainSlotRuntime.GetCaptainIncomeToCollect(player)
			end
		else
			if typeof(ctx.getRawBankIncomePerSecond) == "function" then
				rawIncomePerSecond = ctx.getRawBankIncomePerSecond(player, canonicalName, crewMemberInstanceId)
					* (if typeof(ctx.getBeliBoostMultiplier) == "function" then ctx.getBeliBoostMultiplier(player) else 1)
			end
			if typeof(ctx.getPlayerStandIncome) == "function" then
				rawIncomeToCollect = ctx.getPlayerStandIncome(player, standName)
			end
			if typeof(ctx.getStandClaimSummary) == "function" then
				local claimSummary = ctx.getStandClaimSummary(player, standName)
				claimReadyAmount = math.max(0, tonumber(claimSummary and claimSummary.FinalAmount) or 0)
			end
		end

		local protectionState = getPlacedProtectionState(player, crewMemberInstanceId, true)
		local generation = if ctx.ShipRuntimeService and typeof(ctx.ShipRuntimeService.GetCrewVisualGeneration) == "function"
			then ctx.ShipRuntimeService.GetCrewVisualGeneration(player)
			else 0
		local slotKey = if isCaptainSlot
			then tostring(ctx.CAPTAIN_SLOT_KEY or "Captain")
			else tostring(ShipSlotService.NormalizeSlotNumber(standName) or standName)
		return {
			Placed = {
				[PlacedCrewState.Attribute.Active] = true,
				[PlacedCrewState.Attribute.OwnerUserId] = player and player.UserId or 0,
				[PlacedCrewState.Attribute.SlotKey] = slotKey,
				[PlacedCrewState.Attribute.IsCaptain] = isCaptainSlot,
				[PlacedCrewState.Attribute.CrewMemberName] = tostring(crewMemberName or ""),
				[PlacedCrewState.Attribute.CanonicalName] = canonicalName,
				[PlacedCrewState.Attribute.BaseName] = stateBaseName,
				[PlacedCrewState.Attribute.CrewMemberInstanceId] = if crewMemberInstanceId ~= "" then crewMemberInstanceId else nil,
				[PlacedCrewState.Attribute.DisplayName] = displayName,
				[PlacedCrewState.Attribute.Rarity] = displayRarity,
				[PlacedCrewState.Attribute.Variant] = variantKey,
				[PlacedCrewState.Attribute.IncomePerSecond] = math.max(0, incomePerSecond),
				[PlacedCrewState.Attribute.RawIncomePerSecond] = math.max(0, rawIncomePerSecond),
				[PlacedCrewState.Attribute.RawIncomeToCollect] = math.max(0, rawIncomeToCollect),
				[PlacedCrewState.Attribute.ClaimReadyAmount] = math.max(0, claimReadyAmount),
				[PlacedCrewState.Attribute.ClaimIncomePerSecond] = math.max(0, incomePerSecond),
				[PlacedCrewState.Attribute.BeliBoosted] = if isCaptainSlot
					then CaptainSlotRuntime.IsCaptainIncomeBoosted(player)
					else isStandIncomeBoosted(player, standName, canonicalName),
				[PlacedCrewState.Attribute.SlotBonusLabel] = if slotBonusInfo then tostring(slotBonusInfo.Label or "Bonus") else nil,
				[PlacedCrewState.Attribute.SlotBonusPercent] = if slotBonusInfo then math.max(0, slotState.BonusPercent or 0) else nil,
				[PlacedCrewState.Attribute.ProtectionType] = tostring(protectionState.Type or "none"),
				[PlacedCrewState.Attribute.ProtectionLabel] = tostring(protectionState.Label or ""),
				[PlacedCrewState.Attribute.ProtectionDetail] = tostring(protectionState.Detail or ""),
				[PlacedCrewState.Attribute.VisualGeneration] = generation,
			},
			Overhead = {
				[OVERHEAD_ATTRIBUTES.Kind] = CrewOverhead.Kind.Placed,
				[OVERHEAD_ATTRIBUTES.DisplayName] = displayName,
				[OVERHEAD_ATTRIBUTES.Rarity] = displayRarity,
				[OVERHEAD_ATTRIBUTES.Variant] = variantKey,
				[OVERHEAD_ATTRIBUTES.IncomePerSecond] = math.max(0, incomePerSecond),
				[OVERHEAD_ATTRIBUTES.BeliBoosted] = if isCaptainSlot
					then CaptainSlotRuntime.IsCaptainIncomeBoosted(player)
					else isStandIncomeBoosted(player, standName, canonicalName),
				[OVERHEAD_ATTRIBUTES.SlotBonusLabel] = if slotBonusInfo then tostring(slotBonusInfo.Label or "Bonus") else nil,
				[OVERHEAD_ATTRIBUTES.SlotBonusPercent] = if slotBonusInfo then math.max(0, slotState.BonusPercent or 0) else nil,
				[OVERHEAD_ATTRIBUTES.InstanceId] = if crewMemberInstanceId ~= "" then crewMemberInstanceId else nil,
				[OVERHEAD_ATTRIBUTES.ProtectionType] = tostring(protectionState.Type or "none"),
				[OVERHEAD_ATTRIBUTES.ProtectionLabel] = tostring(protectionState.Label or ""),
				[OVERHEAD_ATTRIBUTES.ProtectionDetail] = tostring(protectionState.Detail or ""),
				[OVERHEAD_ATTRIBUTES.ExpiresAt] = nil,
				[OVERHEAD_ATTRIBUTES.DespawnSeconds] = nil,
			},
		}
	end

	local function publishPlacedCrewState(player, standModel, crewMemberName, options)
		if typeof(standModel) ~= "Instance" or not standModel:IsA("Model") then
			return false, "invalid_stand"
		end
		if tostring(crewMemberName or "") == "" then
			return false, "missing_crew_member"
		end

		options = if typeof(options) == "table" then options else {}
		local attributes = buildPlacedCrewStateAttributes(player, standModel, crewMemberName)
		local semanticChanged = hasAttributeChanges(standModel, attributes.Placed)
			or hasAttributeChanges(standModel, attributes.Overhead)
		local now = os.time()
		if options.RefreshIncomeTimestamp == true then
			attributes.Placed[PlacedCrewState.Attribute.IncomeUpdatedAtUnix] = now
		end
		if options.RefreshUpdatedTimestamp == true or semanticChanged then
			attributes.Placed[PlacedCrewState.Attribute.UpdatedAtUnix] = now
		end

		PlacedCrewState.ApplyAttributes(standModel, attributes.Placed)
		PlacedCrewState.ApplyAttributes(standModel, attributes.Overhead)
		if
			CrewProtectionService
			and typeof(CrewProtectionService.ApplyPlacedProtectionAttributes) == "function"
		then
			CrewProtectionService.ApplyPlacedProtectionAttributes(
				player,
				standModel,
				attributes.Placed[PlacedCrewState.Attribute.CrewMemberInstanceId],
				true,
				ctx.DataManager
			)
		end
		if not CollectionService:HasTag(standModel, PlacedCrewState.Tag) then
			CollectionService:AddTag(standModel, PlacedCrewState.Tag)
		end
		return true, nil
	end

	local function publishClaimIncomeState(_player, standModel, claimSummary, options)
		if typeof(standModel) ~= "Instance" or not standModel:IsA("Model") then
			return false, "invalid_stand"
		end

		claimSummary = if typeof(claimSummary) == "table" then claimSummary else {}
		options = if typeof(options) == "table" then options else {}
		local now = os.time()
		local rawIncomeToCollect = math.max(
			0,
			tonumber(claimSummary.RawIncomeToCollect or claimSummary.RawRemainderAmount or claimSummary.RawIncome) or 0
		)
		local claimReadyAmount = math.max(
			0,
			tonumber(claimSummary.ClaimReadyAmount or claimSummary.FinalAmount) or 0
		)

		PlacedCrewState.SetAttributeIfChanged(
			standModel,
			PlacedCrewState.Attribute.RawIncomeToCollect,
			rawIncomeToCollect
		)
		PlacedCrewState.SetAttributeIfChanged(
			standModel,
			PlacedCrewState.Attribute.ClaimReadyAmount,
			claimReadyAmount
		)
		if options.RefreshIncomeTimestamp ~= false then
			PlacedCrewState.SetAttributeIfChanged(standModel, PlacedCrewState.Attribute.IncomeUpdatedAtUnix, now)
		end
		if options.RefreshUpdatedTimestamp == true then
			PlacedCrewState.SetAttributeIfChanged(standModel, PlacedCrewState.Attribute.UpdatedAtUnix, now)
		end
		return true, nil
	end

	local function clearStandVisual(standModel)
		if PremiumCrewStealProtectionVisuals and typeof(PremiumCrewStealProtectionVisuals.ClearStand) == "function" then
			PremiumCrewStealProtectionVisuals.ClearStand(standModel)
		end
		local existing = standModel:FindFirstChild("PlacedCrewMember")
		if existing and existing:IsA("Model") then
			existing:Destroy()
		end
		PlacedCrewState.ClearAttributes(standModel)
		if CollectionService:HasTag(standModel, PlacedCrewState.Tag) then
			CollectionService:RemoveTag(standModel, PlacedCrewState.Tag)
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
		local rotationOffsetDegrees = getCrewPlacementRotationOffsetDegrees(standModel)
		return PlacedCrewState.GetPlacementCFrame(model, handle, rotationOffsetDegrees)
	end

	local function placeModelBottomOnHandle(model, handle, standModel)
		model:PivotTo(getCrewPlacementCFrame(model, handle, standModel))
	end

	local function spawnStandCrewMember(player, standModel, _handle, crewMemberName)
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

		local info = resolved and resolved.Info or findCrewMemberInfoByName(crewMemberName, player)
		local published, publishReason = publishPlacedCrewState(player, standModel, crewMemberName, {
			Reason = "spawn_stand_crew_member",
			RefreshIncomeTimestamp = true,
			RefreshUpdatedTimestamp = true,
		})
		if published ~= true then
			return nil, publishReason or "state_publish_failed"
		end
		if PremiumCrewStealProtectionVisuals and typeof(PremiumCrewStealProtectionVisuals.UpdateStand) == "function" then
			PremiumCrewStealProtectionVisuals.UpdateStand(player, standModel)
		end
		resetSlotRenderState(getExistingSlotRuntime(standModel))
		standDebug(
			"spawnStandCrewMember state_published player=%s stand=%s template=%s incomeBase=%s",
			player and player.Name or "?",
			standModel and standModel.Name or "?",
			template:GetFullName(),
			tostring(resolved and resolved.Info and resolved.Info.Income or info and info.Income or "nil")
		)
		return standModel, nil
	end


	ctx.clearStandVisual = clearStandVisual
	ctx.findActiveShipAncestor = findActiveShipAncestor
	ctx.getCrewPlacementCFrame = getCrewPlacementCFrame
	ctx.getCrewPlacementRotationOffsetDegrees = getCrewPlacementRotationOffsetDegrees
	ctx.isNumericShipCrewSlot = isNumericShipCrewSlot
	ctx.placeModelBottomOnHandle = placeModelBottomOnHandle
	ctx.removeLegacyCrewHover = removeLegacyCrewHover
	ctx.publishClaimIncomeState = publishClaimIncomeState
	ctx.publishPlacedCrewState = publishPlacedCrewState
	ctx.spawnStandCrewMember = spawnStandCrewMember
	ctx.syncPlacedOverheadMetadata = syncPlacedOverheadMetadata
end

return Module
