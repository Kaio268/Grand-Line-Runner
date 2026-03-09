game:GetService('Workspace'):WaitForChild("Map"):WaitForChild("MainMap"):WaitForChild("GroupReward"):WaitForChild("Hitbox"):WaitForChild("ProximityPrompt").Triggered:Connect(function()
	game.MarketplaceService:PromptProductPurchase(game.Players.LocalPlayer, 3512059347)
end)