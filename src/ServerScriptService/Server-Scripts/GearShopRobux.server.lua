local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local DataManager = require(ServerScriptService:WaitForChild("Data"):WaitForChild("DataManager"))
local Gears = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("Gears"))

local RobuxRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("GearStoreRobux")

RobuxRemote.OnServerEvent:Connect(function(player, gearName)
	if typeof(gearName) ~= "string" then
		return
	end

	local gearData = Gears[gearName]
	if not gearData then
		return
	end

	local productId = tonumber(gearData.ProductID)
	if not productId then
		return
	end

	DataManager:PromptProductPurchase(player, productId)
end)
