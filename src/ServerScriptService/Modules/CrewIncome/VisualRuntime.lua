local Module = {}

function Module.Install(ctx)
	local CaptainSlotRuntime = ctx.CaptainSlotRuntime
	local CollectionService = ctx.CollectionService
	local CrewOverhead = ctx.CrewOverhead
	local function detectVariant(...)
		return ctx.detectVariant(...)
	end
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
	local function isBeliBoostActive(...)
		return ctx.isBeliBoostActive(...)
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
	local function standDebug(...)
		return ctx.standDebug(...)
	end
	local function stripVariantPrefix(...)
		return ctx.stripVariantPrefix(...)
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


	ctx.clearStandVisual = clearStandVisual
	ctx.findActiveShipAncestor = findActiveShipAncestor
	ctx.getCrewPlacementCFrame = getCrewPlacementCFrame
	ctx.getCrewPlacementRotationOffsetDegrees = getCrewPlacementRotationOffsetDegrees
	ctx.isNumericShipCrewSlot = isNumericShipCrewSlot
	ctx.placeModelBottomOnHandle = placeModelBottomOnHandle
	ctx.removeLegacyCrewHover = removeLegacyCrewHover
	ctx.spawnStandCrewMember = spawnStandCrewMember
	ctx.syncPlacedOverheadMetadata = syncPlacedOverheadMetadata
end

return Module
