local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Types = require(ReplicatedStorage.Modules.Types)
local CurrencyUtil = require(ReplicatedStorage.Modules:WaitForChild("CurrencyUtil"))

local Premades = {}
local DataManager: Types.DataManager

function Premades.AddMoney(DataManager: Types.DataManager, Player: Player, Amount: number)
	local finalAmount = Amount  * Player.Gamepasses.x2MoneyValue.Value * Player.Active.x2Money.Value
		
	if finalAmount ~= 0 then
		DataManager:AddValue(Player, CurrencyUtil.getPrimaryPath(), finalAmount)
		DataManager:AddValue(Player, CurrencyUtil.getTotalPath(), finalAmount)
	end
end

Premades.Init = function(_DataManager: Types.DataManager)
	DataManager = _DataManager
end

return Premades
