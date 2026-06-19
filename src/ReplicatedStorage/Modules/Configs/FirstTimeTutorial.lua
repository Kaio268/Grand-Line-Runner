local FirstTimeTutorial = {
	Version = 1,
	CompletionPath = "HiddenLeaderstats.Tutorial",

	TutorialCrewMember = {
		Name = "Mask Dancer",
		GrantedPath = "HiddenLeaderstats.TutorialCrewMemberGranted",
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
			Body = "Grab Crewmates, bring them home, put them to work, and use Beli to get faster.",
			Instruction = "Start with the basics.",
			ActionText = "Start",
			CompletionMode = "Acknowledge",
		},
		{
			Id = "pickup_crew_member",
			Title = "Grab a Crewmate",
			Body = "A tutorial Crewmate has appeared nearby.",
			Instruction = "Hold E to pick up the Crewmate.",
			WaitText = "Pick up a Crewmate",
			CompletionMode = "CarryCrewMember",
		},
		{
			Id = "place_on_stand",
			Title = "Bring it home",
			Body = "Your Crewmate is in your crew inventory.",
			Instruction = "Place the Crewmate on a stand to put them to work.",
			WaitText = "Place the Crewmate",
			CompletionMode = "PlaceOnStand",
		},
		{
			Id = "collect_beli",
			Title = "Collect Beli",
			Body = "Your stand banks Beli over time.",
			Instruction = "Touch the collection zone after your Crewmate earns Beli.",
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
			Body = "Keep collecting Crewmates, opening chests, completing quests, and pushing deeper into runs.",
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
