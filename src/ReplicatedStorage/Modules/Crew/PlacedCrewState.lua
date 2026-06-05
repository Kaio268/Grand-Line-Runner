local PlacedCrewState = {}

PlacedCrewState.Tag = "PlacedCrewState"

PlacedCrewState.Attribute = {
	Active = "PlacedCrewActive",
	OwnerUserId = "PlacedCrewOwnerUserId",
	SlotKey = "PlacedCrewSlotKey",
	IsCaptain = "PlacedCrewIsCaptain",
	CrewMemberName = "PlacedCrewMemberName",
	CanonicalName = "PlacedCrewCanonicalName",
	BaseName = "PlacedCrewBaseName",
	CrewMemberInstanceId = "PlacedCrewMemberInstanceId",
	DisplayName = "PlacedCrewDisplayName",
	Rarity = "PlacedCrewRarity",
	Variant = "PlacedCrewVariant",
	IncomePerSecond = "PlacedCrewIncomePerSecond",
	RawIncomePerSecond = "PlacedCrewRawIncomePerSecond",
	RawIncomeToCollect = "PlacedCrewRawIncomeToCollect",
	ClaimReadyAmount = "PlacedCrewClaimReadyAmount",
	ClaimIncomePerSecond = "PlacedCrewClaimIncomePerSecond",
	IncomeUpdatedAtUnix = "PlacedCrewIncomeUpdatedAtUnix",
	BeliBoosted = "PlacedCrewBeliBoosted",
	SlotBonusLabel = "PlacedCrewSlotBonusLabel",
	SlotBonusPercent = "PlacedCrewSlotBonusPercent",
	ProtectionType = "PlacedCrewProtectionType",
	ProtectionLabel = "PlacedCrewProtectionLabel",
	ProtectionDetail = "PlacedCrewProtectionDetail",
	VisualGeneration = "PlacedCrewVisualGeneration",
	UpdatedAtUnix = "PlacedCrewUpdatedAtUnix",
}

PlacedCrewState.ClearableAttributes = {}
for _, attributeName in pairs(PlacedCrewState.Attribute) do
	PlacedCrewState.ClearableAttributes[#PlacedCrewState.ClearableAttributes + 1] = attributeName
end
table.sort(PlacedCrewState.ClearableAttributes)

function PlacedCrewState.SetAttributeIfChanged(instance, attributeName, value)
	if typeof(instance) ~= "Instance" then
		return
	end

	if instance:GetAttribute(attributeName) ~= value then
		instance:SetAttribute(attributeName, value)
	end
end

function PlacedCrewState.ApplyAttributes(instance, attributes)
	if typeof(instance) ~= "Instance" or typeof(attributes) ~= "table" then
		return
	end

	for attributeName, value in pairs(attributes) do
		PlacedCrewState.SetAttributeIfChanged(instance, attributeName, value)
	end
end

function PlacedCrewState.ClearAttributes(instance)
	if typeof(instance) ~= "Instance" then
		return
	end

	for _, attributeName in ipairs(PlacedCrewState.ClearableAttributes) do
		PlacedCrewState.SetAttributeIfChanged(instance, attributeName, nil)
	end
end

function PlacedCrewState.GetPlacementCFrame(model, handle, rotationOffsetDegrees)
	if typeof(model) ~= "Instance" or not model:IsA("Model") then
		return nil
	end
	if typeof(handle) ~= "Instance" or not handle:IsA("BasePart") then
		return nil
	end

	local boxCF, boxSize = model:GetBoundingBox()
	local offset = model:GetPivot():ToObjectSpace(boxCF)
	local up = handle.CFrame.UpVector
	local surface = handle.Position + up * (handle.Size.Y / 2)
	local rot = (handle.CFrame - handle.Position) * CFrame.Angles(0, math.rad(tonumber(rotationOffsetDegrees) or 0), 0)
	local desiredBox = CFrame.new(surface + up * (boxSize.Y / 2)) * rot
	return desiredBox * offset:Inverse()
end

return PlacedCrewState
