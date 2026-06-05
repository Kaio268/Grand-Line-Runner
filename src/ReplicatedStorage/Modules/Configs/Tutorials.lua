local Tutorials = {
	SchemaVersion = 2,
	CompletionRoot = "Tutorials.Completed",
	QueueRoot = "Tutorials.Queue",
	LegacyFirstRunCompletionPath = "HiddenLeaderstats.Tutorial",

	Remotes = {
		RequestName = "TutorialRequest",
		StateName = "TutorialState",
	},

	Definitions = {
		Inventory = {
			Id = "Inventory",
			Title = "Inventory",
			Enabled = false,
			Trigger = {
				Type = "ClientModalOpened",
				ModalName = "Inventory",
			},
			SkipCompletes = true,
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

		Resources = {
			Id = "Resources",
			Title = "Resources",
			Enabled = true,
			SkipCompletes = true,
			EligibleDelaySeconds = 10,
			Presentation = {
				Type = "ScreenGui",
				GuiName = "ResourcesGui",
				CompleteButtons = { "FeedButton" },
			},
			Steps = {
				{
					Id = "resources_intro",
					Title = "Resources",
					Body = "Beli, food, materials, and chests are the backbone of your crew.",
					Instruction = "Keep an eye on rewards after runs and quests so you know what to spend next.",
					ActionText = "Got it",
					CompletionMode = "Acknowledge",
				},
			},
		},

		FeedCrewmates = {
			Id = "FeedCrewmates",
			Title = "Feed Your Crewmates",
			Enabled = true,
			SkipCompletes = true,
			TargetResolver = "CrewFeedPanel",
			Presentation = {
				Type = "ScreenGui",
				GuiName = "FeedYourCrewmatesGui",
				CompleteButtons = { "SkipButton" },
				ShowObjectiveIndicator = true,
				ShowObjectivePath = true,
			},
			Steps = {
				{
					Id = "feed_crewmates",
					Title = "Feed Your Crewmates",
					Body = "Food can be used to level crewmates and improve the strength of your ship.",
					Instruction = "Open your crew controls at your ship when you are ready to feed someone.",
					ActionText = "Got it",
					CompletionMode = "Acknowledge",
				},
			},
		},

		RebirthInfo = {
			Id = "RebirthInfo",
			Title = "Rebirth Guide",
			Enabled = true,
			SkipCompletes = true,
			Presentation = {
				Type = "ScreenGui",
				GuiName = "RebirthInfoGui",
				CompleteButtons = { "SkipButton" },
				ActionButtons = {
					OpenInventoryButton = {
						Type = "OpenReactModal",
						ModalName = "Inventory",
						CompleteTutorial = true,
					},
				},
			},
			Steps = {
				{
					Id = "rebirth_info",
					Title = "Your Crew is Saved",
					Body = "Rebirth gives you a fresh start, but your collected Crewmates are saved.",
					Instruction = "Open Inventory, then select your Crewmates.",
					ActionText = "Open Inventory",
					CompletionMode = "Acknowledge",
				},
			},
		},

		Raiding = {
			Id = "Raiding",
			Title = "Raiding",
			Enabled = true,
			SkipCompletes = true,
			Presentation = {
				Type = "ScreenGui",
				GuiName = "RaidingGui",
				CompleteButtons = { "GotItButton" },
			},
			Steps = {
				{
					Id = "raiding_intro",
					Title = "Raiding",
					Body = "Enemy ships can be raided, but carried rewards are only safe once you bring them home.",
					Instruction = "Return to your base after risky plays so rewards can be secured.",
					ActionText = "Got it",
					CompletionMode = "Acknowledge",
				},
			},
		},

		QuestReward = {
			Id = "QuestReward",
			Title = "Quest Rewards",
			Enabled = true,
			SkipCompletes = true,
			Presentation = {
				Type = "ScreenGui",
				GuiName = "QuestRewardGui",
				CompleteButtons = { "FeedButton", "SkipButton" },
			},
			Steps = {
				{
					Id = "quest_reward",
					Title = "Quest Rewards",
					Body = "Some quests award Devil Fruit chests and other high-value items.",
					Instruction = "Claim completed quests, then open reward chests from your inventory.",
					ActionText = "Got it",
					CompletionMode = "Acknowledge",
				},
			},
		},

		ShipUpgrade = {
			Id = "ShipUpgrade",
			Title = "Ship Upgrade",
			Enabled = true,
			SkipCompletes = true,
			TargetResolver = "ShipUpgradePanel",
			Presentation = {
				Type = "ScreenGui",
				GuiName = "UpgradeYourShipGui",
				CompleteButtons = { "SkipButton" },
				ShowObjectiveIndicator = true,
				ShowObjectivePath = true,
			},
			Steps = {
				{
					Id = "ship_upgrade",
					Title = "Upgrade Your Ship",
					Body = "You have enough resources for your first ship upgrade.",
					Instruction = "Visit your ship upgrade controls to unlock more room for your crew.",
					ActionText = "Got it",
					CompletionMode = "Acknowledge",
				},
			},
		},

		CrewProtection = {
			Id = "CrewProtection",
			Title = "Crew Protection",
			Enabled = true,
			SkipCompletes = true,
			TargetResolver = "ActiveShip",
			Presentation = {
				Type = "ScreenGui",
				GuiName = "CrewProtectionMonetisationGui",
				CompleteButtons = { "SkipButton" },
				ActionButtons = {
					GotItButton = {
						Type = "OpenReactModal",
						ModalName = "Store",
						Payload = {
							SectionKey = "crew-protection",
						},
						CompleteTutorial = true,
					},
				},
			},
			Steps = {
				{
					Id = "crew_protection",
					Title = "Protect Rare Crew",
					Body = "Rare and stronger crewmates are valuable enough to protect from steals.",
					Instruction = "Use protection options when you want extra safety for important crew.",
					ActionText = "Got it",
					CompletionMode = "Acknowledge",
				},
			},
		},
	},
}

local definitionOrder = {
	"Resources",
	"FeedCrewmates",
	"RebirthInfo",
	"Raiding",
	"QuestReward",
	"ShipUpgrade",
	"CrewProtection",
}

local function copyArray(source)
	return table.clone(source or {})
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

function Tutorials.GetQueuePath()
	return Tutorials.QueueRoot
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
