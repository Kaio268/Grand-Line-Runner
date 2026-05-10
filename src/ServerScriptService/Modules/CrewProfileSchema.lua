local CrewProfileSchema = {}

CrewProfileSchema.SchemaVersion = 1

CrewProfileSchema.Keys = {
	Inventory = "CrewMemberInventory",
	QuickSlots = "CrewMemberQuickSlots",
	Income = "CrewMemberIncome",
	IndexCollection = "IndexCollection",
	Index = "CrewMembers",
	CarriedAttribute = "CarriedCrewMember",
	CarriedImageAttribute = "CarriedCrewMemberImage",
	StandName = "CrewMemberName",
	StandInstanceId = "CrewMemberInstanceId",
}

CrewProfileSchema.LegacyKeys = {
	Inventory = "BrainrotInventory",
	QuickSlots = "BrainrotQuickSlots",
	QuickSlotsLegacy = "BrainrotStorage",
	Income = "IncomeBrainrots",
	IndexCollection = "IndexCollection",
	Index = "Brainrots",
	CarriedAttribute = "CarriedBrainrot",
	CarriedImageAttribute = "CarriedBrainrotImage",
	StandName = "BrainrotName",
	StandInstanceId = "BrainrotInstanceId",
}

CrewProfileSchema.CrewMemberInstanceFields = {
	"InstanceId",
	"CrewMemberId",
	"DisplayName",
	"LegacyStorageName",
	"StorageName",
	"BaseName",
	"Variant",
	"Rarity",
	"Income",
	"Render",
	"GoldenRender",
	"DiamondRender",
	"Level",
	"CurrentXP",
	"AssignedStand",
	"AcquiredAt",
	"LastReleasedAt",
	"TutorialReward",
	"TutorialToken",
	"ProjectionSource",
}

local function floorNumber(value, fallback)
	return math.floor(tonumber(value) or fallback or 0)
end

function CrewProfileSchema.NewCrewMemberInventory(overrides)
	overrides = if typeof(overrides) == "table" then overrides else {}

	return {
		SchemaVersion = CrewProfileSchema.SchemaVersion,
		NextInstanceId = math.max(1, floorNumber(overrides.NextInstanceId, 1)),
		ById = if typeof(overrides.ById) == "table" then table.clone(overrides.ById) else {},
		Order = if typeof(overrides.Order) == "table" then table.clone(overrides.Order) else {},
	}
end

function CrewProfileSchema.NewCrewMemberQuickSlots(overrides)
	overrides = if typeof(overrides) == "table" then overrides else {}

	return {
		SchemaVersion = CrewProfileSchema.SchemaVersion,
		UnlockedSlots = math.max(0, floorNumber(overrides.UnlockedSlots, 0)),
		MaxSlots = math.max(0, floorNumber(overrides.MaxSlots, 0)),
	}
end

function CrewProfileSchema.NewCrewMemberIncome()
	return {}
end

function CrewProfileSchema.NewCrewMemberIndex()
	return {}
end

function CrewProfileSchema.NewProjection()
	return {
		[CrewProfileSchema.Keys.Inventory] = CrewProfileSchema.NewCrewMemberInventory(),
		[CrewProfileSchema.Keys.QuickSlots] = CrewProfileSchema.NewCrewMemberQuickSlots(),
		[CrewProfileSchema.Keys.Income] = CrewProfileSchema.NewCrewMemberIncome(),
		[CrewProfileSchema.Keys.IndexCollection] = {
			[CrewProfileSchema.Keys.Index] = CrewProfileSchema.NewCrewMemberIndex(),
		},
	}
end

return CrewProfileSchema
