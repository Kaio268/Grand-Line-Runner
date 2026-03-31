local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local Registry = require(Modules:WaitForChild("DevilFruits"):WaitForChild("Shared"):WaitForChild("Registry"))

local DevilFruitUiController = {}

function DevilFruitUiController.FormatAbilityName(abilityName)
	return tostring(abilityName):gsub("(%l)(%u)", "%1 %2")
end

function DevilFruitUiController.FormatCooldownTime(seconds)
	local remaining = math.max(0, tonumber(seconds) or 0)
	if remaining >= 10 then
		return string.format("%.0fs", math.ceil(remaining))
	end

	return string.format("%.1fs", math.ceil(remaining * 10) / 10)
end

function DevilFruitUiController.GetOrderedAbilities(fruitName)
	local abilityEntries = Registry.GetUiAbilities(fruitName)
	local orderedAbilities = {}

	for _, abilityEntry in ipairs(abilityEntries) do
		orderedAbilities[#orderedAbilities + 1] = {
			Name = abilityEntry.Name,
			Config = abilityEntry.Config,
		}
	end

	return orderedAbilities
end

function DevilFruitUiController.ShouldShowCooldownHud(fruitName)
	return Registry.GetFruit(fruitName) ~= nil
end

return DevilFruitUiController
