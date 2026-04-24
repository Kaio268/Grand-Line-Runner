local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MapResolver = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("MapResolver"))

local refs = MapResolver.GetRefs({
	context = "LegacyGroupRewardPrompt",
})
local prompt = refs.GroupRewardPrompt

if not prompt then
	return
end

prompt.Triggered:Connect(function()
	game.MarketplaceService:PromptProductPurchase(game.Players.LocalPlayer, 3512059347)
end)
