local FirstTimeTutorial = {
	Version = 1,
	CompletionPath = "HiddenLeaderstats.Tutorial",

	TutorialBrainrot = {
		Name = "Lirili Larila",
		GrantedPath = "HiddenLeaderstats.TutorialBrainrotGranted",
		SpawnDistance = 10,
		SpawnLifetime = 900,
	},

	Remotes = {
		RequestName = "FirstTimeTutorialRequest",
		StateName = "FirstTimeTutorialState",
	},

	Steps = {
		{
			Id = "welcome",
			Title = "Welcome aboard",
			Body = "Grab Brainrots, bring them home, put them to work, and use Beli to get faster.",
			Instruction = "Start with the basics.",
			ActionText = "Start",
			CompletionMode = "Acknowledge",
		},
		{
			Id = "move",
			Title = "Find your footing",
			Body = "Move around the island to get a feel for your character.",
			Instruction = "Move 18 studs to continue.",
			WaitText = "Move to continue",
			CompletionMode = "MoveDistance",
			RequiredDistance = 18,
		},
		{
			Id = "pickup_brainrot",
			Title = "Grab a Brainrot",
			Body = "A tutorial Brainrot has appeared nearby.",
			Instruction = "Hold E to pick up the Brainrot.",
			WaitText = "Pick up a Brainrot",
			CompletionMode = "CarryBrainrot",
		},
		{
			Id = "extract_brainrot",
			Title = "Bring it home",
			Body = "Carry the Brainrot back through the extraction boundary to add it to your crew.",
			Instruction = "Reach the extraction zone while carrying it.",
			WaitText = "Extract the Brainrot",
			CompletionMode = "ExtractBrainrot",
		},
		{
			Id = "place_on_stand",
			Title = "Put crew to work",
			Body = "Brainrots earn Beli when they are placed on your stand.",
			Instruction = "Select your Brainrot from the hotbar, then place it on an empty stand.",
			WaitText = "Place on a stand",
			CompletionMode = "PlaceOnStand",
		},
		{
			Id = "collect_beli",
			Title = "Collect Beli",
			Body = "Your stand banks Beli over time.",
			Instruction = "Touch the stand collection zone after it has earned Beli.",
			WaitText = "Collect Beli",
			CompletionMode = "CollectBeli",
		},
		{
			Id = "buy_speed",
			Title = "Buy speed",
			Body = "Speed helps you move rewards around the map faster.",
			Instruction = "Open Speed Upgrades and buy the first speed upgrade.",
			WaitText = "Buy speed",
			CompletionMode = "BuySpeed",
		},
		{
			Id = "final_guidance",
			Title = "Set sail",
			Body = "Keep collecting Brainrots, opening chests, completing quests, and pushing deeper into runs.",
			Instruction = "You are ready to play.",
			ActionText = "Finish",
			CompletionMode = "Acknowledge",
		},
	},
}

function FirstTimeTutorial.GetStep(index)
	local numericIndex = math.floor(tonumber(index) or 0)
	return FirstTimeTutorial.Steps[numericIndex]
end

function FirstTimeTutorial.GetStepCount()
	return #FirstTimeTutorial.Steps
end

return FirstTimeTutorial
