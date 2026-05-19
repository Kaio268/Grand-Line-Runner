local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local DataManager = require(ServerScriptService:WaitForChild("Data"):WaitForChild("DataManager"))
local Gears = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("Gears"))
local MonetizationConfig = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("Monetization"))
local PopUpModule = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("PopUpModule"))
local RemoteGuard = require(ServerScriptService:WaitForChild("Modules"):WaitForChild("RemoteGuard"))

local RobuxRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("GearStoreRobux")

RobuxRemote.OnServerEvent:Connect(function(player, gearName)
	-- Security: only valid string gear keys can request a server-owned product prompt.
	if not RemoteGuard.Check(player, "GearStoreRobux", { gearName }, {
		Cooldown = 0.5,
		Args = {
			{ Type = "string", MaxLength = 80 },
		},
	}) then
		return
	end

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
	if not MonetizationConfig.CanPromptDeveloperProduct(productId) then
		warn(string.format(
			"[GearShopRobux] Blocked disabled/non-GTR gear product prompt player=%s gear=%s productId=%s",
			player.Name,
			tostring(gearName),
			tostring(productId)
		))
		PopUpModule:Server_SendPopUp(
			player,
			MonetizationConfig.UnavailableMessage,
			Color3.fromRGB(255, 104, 104),
			Color3.fromRGB(0, 0, 0),
			3,
			true
		)
		return
	end

	DataManager:PromptProductPurchase(player, productId)
end)
