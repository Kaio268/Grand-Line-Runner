local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MapResolver = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("MapResolver"))

local refs = MapResolver.WaitForRefs(
	{ "MapRoot" },
	nil,
	{
		warn = true,
		context = "LegacyGroupRewardPrompt",
	}
)
local prompt = refs.MapRoot:WaitForChild("Lobby"):WaitForChild("GroupReward"):WaitForChild("Hitbox"):WaitForChild("ProximityPrompt")

prompt.Triggered:Connect(function()
	game.MarketplaceService:PromptProductPurchase(game.Players.LocalPlayer, 3512059347)
end)
