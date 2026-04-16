local CommonValidation = {}

function CommonValidation.IsPlayer(target)
	return typeof(target) == "Instance" and target:IsA("Player")
end

function CommonValidation.GetPlayerRootPart(targetPlayer)
	if not CommonValidation.IsPlayer(targetPlayer) then
		return nil
	end

	local character = targetPlayer.Character
	if not character then
		return nil
	end

	return character:FindFirstChild("HumanoidRootPart")
end

function CommonValidation.GetCharacterHumanoid(character)
	if typeof(character) ~= "Instance" then
		return nil
	end

	return character:FindFirstChildOfClass("Humanoid")
end

return CommonValidation
