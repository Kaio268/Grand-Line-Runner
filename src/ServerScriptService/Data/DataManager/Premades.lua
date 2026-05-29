local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Types = require(ReplicatedStorage.Modules.Types)
local CurrencyUtil = require(ReplicatedStorage.Modules:WaitForChild("CurrencyUtil"))

local Premades = {}

local function getCaptainPassMultiplier(player: Player)
	local passes = player and player:FindFirstChild("Passes")
	local vip = passes and passes:FindFirstChild("VIP")
	if vip and vip:IsA("BoolValue") and vip.Value == true then
		return 1.1
	end
	return 1
end

function Premades.AddBeli(dataManager: Types.DataManager, Player: Player, Amount: number)
	local finalAmount = Amount
		* Player.Gamepasses.x2MoneyValue.Value
		* Player.Active.x2Money.Value
		* getCaptainPassMultiplier(Player)
	finalAmount = math.floor(finalAmount + 0.5)
		
	if finalAmount ~= 0 then
		dataManager:AddValue(Player, CurrencyUtil.getPrimaryPath(), finalAmount)
		dataManager:AddValue(Player, CurrencyUtil.getTotalPath(), finalAmount)
	end
end

Premades.AddMoney = Premades.AddBeli

Premades.Init = function(_dataManager: Types.DataManager)
end

return Premades
