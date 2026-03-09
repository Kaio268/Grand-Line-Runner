local remote = game.ReplicatedStorage.Remotes:WaitForChild("StandUpgradeRemote")
local shorten = require(game.ReplicatedStorage.Modules.Shorten)
local StandsUpgrades = require(game.ServerScriptService.Modules:WaitForChild("StandsUpgrades"))
local DataMenager = require(game.ServerScriptService.Data:WaitForChild("DataManager"))

remote.OnServerEvent:Connect(function(player, stand)
	if not player.StandsLevels:FindFirstChild(stand) then return end
	
	local price = StandsUpgrades[tostring(player.StandsLevels:FindFirstChild(stand).Value+1)]
	
	if player.leaderstats.Money.Value >= price then

		DataMenager:AddValue(player, "leaderstats.Money", -price)
		DataMenager:AddValue(player, "StandsLevels."..stand, 1)
		
		player.PlayerGui:FindFirstChild(stand).LevelUp.Main.Price.Text = "$"..shorten.roundNumber(StandsUpgrades[tostring(player.StandsLevels:FindFirstChild(stand).Value+1)])
		player.PlayerGui:FindFirstChild(stand).LevelUp.Main.Upgarde.Text = "Upgrade Level " .. tostring(player.StandsLevels:FindFirstChild(stand).Value+1)
	end
end)