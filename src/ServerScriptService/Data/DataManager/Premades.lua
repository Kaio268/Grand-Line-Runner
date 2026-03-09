local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Types = require(ReplicatedStorage.Modules.Types)

local Premades = {}
local DataManager: Types.DataManager

function Premades.AddMoney(DataManager: Types.DataManager, Player: Player, Amount: number)
	local finalAmount = Amount  * Player.Gamepasses.x2MoneyValue.Value * Player.Active.x2Money.Value
		
	if finalAmount ~= 0 then
		DataManager:AddValue(Player, "leaderstats.Money", finalAmount)
		DataManager:AddValue(Player, "TotalStats.TotalMoney", finalAmount)
	end
end

Premades.Init = function(_DataManager: Types.DataManager)
	DataManager = _DataManager
end

return Premades
