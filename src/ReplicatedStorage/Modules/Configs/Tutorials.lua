local Tutorials = {
	SchemaVersion = 1,
	CompletionRoot = "Tutorials.Completed",
	LegacyFirstRunCompletionPath = "HiddenLeaderstats.Tutorial",

	Remotes = {
		RequestName = "TutorialRequest",
		StateName = "TutorialState",
	},

	Definitions = {
		Inventory = {
			Id = "Inventory",
			Title = "Inventory",
			Enabled = true,
			Trigger = {
				Type = "ClientModalOpened",
				ModalName = "Inventory",
			},
			SkipCompletes = true,
			BackfillForLegacyFirstRunComplete = true,
			Steps = {
				{
					Id = "inventory_opened",
					Title = "Inventory",
					Body = "This is where your crew, chests, fruits, resources, and titles live.",
					Instruction = "Open it when you want to equip items, check resources, or manage rewards.",
					ActionText = "Got it",
					CompletionMode = "Acknowledge",
				},
			},
		},
	},
}

local definitionOrder = {
	"Inventory",
}

local function copyArray(source)
	local copy = {}
	for index, value in ipairs(source or {}) do
		copy[index] = value
	end
	return copy
end

function Tutorials.GetDefinition(tutorialId)
	return Tutorials.Definitions[tostring(tutorialId or "")]
end

function Tutorials.GetStep(tutorialId, stepIndex)
	local definition = Tutorials.GetDefinition(tutorialId)
	local steps = definition and definition.Steps
	local index = math.floor(tonumber(stepIndex) or 0)
	return steps and steps[index] or nil
end

function Tutorials.GetStepCount(tutorialId)
	local definition = Tutorials.GetDefinition(tutorialId)
	local steps = definition and definition.Steps
	return if typeof(steps) == "table" then #steps else 0
end

function Tutorials.GetCompletionPath(tutorialId)
	local id = tostring(tutorialId or "")
	if id == "" then
		return nil
	end

	return string.format("%s.%s", Tutorials.CompletionRoot, id)
end

function Tutorials.GetDefinitionOrder()
	return copyArray(definitionOrder)
end

function Tutorials.GetLegacyFirstRunBackfillIds()
	local ids = {}
	for _, tutorialId in ipairs(definitionOrder) do
		local definition = Tutorials.GetDefinition(tutorialId)
		if definition and definition.BackfillForLegacyFirstRunComplete == true then
			table.insert(ids, tutorialId)
		end
	end
	return ids
end

return Tutorials
