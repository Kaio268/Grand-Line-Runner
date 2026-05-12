local Players = game:GetService("Players")

local CARRIED_CREW_MEMBER_ATTRIBUTE = "CarriedCrewMember"
local CARRIED_CREW_MEMBER_IMAGE_ATTRIBUTE = "CarriedCrewMemberImage"
local LEGACY_CARRIED_BRAINROT_ATTRIBUTE = "CarriedBrainrot"
local LEGACY_CARRIED_BRAINROT_IMAGE_ATTRIBUTE = "CarriedBrainrotImage"

local function clearCarriedCrewMemberAttributes(plr)
	plr:SetAttribute(CARRIED_CREW_MEMBER_ATTRIBUTE, nil)
	plr:SetAttribute(CARRIED_CREW_MEMBER_IMAGE_ATTRIBUTE, nil)
	plr:SetAttribute(LEGACY_CARRIED_BRAINROT_ATTRIBUTE, nil)
	plr:SetAttribute(LEGACY_CARRIED_BRAINROT_IMAGE_ATTRIBUTE, nil)
end

local function hook(plr)
	plr:SetAttribute("IsDead", false)
	if plr:GetAttribute(CARRIED_CREW_MEMBER_ATTRIBUTE) == nil and plr:GetAttribute(LEGACY_CARRIED_BRAINROT_ATTRIBUTE) == nil then
		clearCarriedCrewMemberAttributes(plr)
	end

	local function onChar(char)
		plr:SetAttribute("IsDead", false)
		local hum = char:WaitForChild("Humanoid", 10)
		if hum then
			hum.Died:Connect(function()
				if plr and plr.Parent then
					plr:SetAttribute("IsDead", true)
					clearCarriedCrewMemberAttributes(plr)
				end
			end)
		end
	end

	plr.CharacterAdded:Connect(onChar)
	if plr.Character then
		onChar(plr.Character)
	end
end

Players.PlayerAdded:Connect(hook)
for _, p in ipairs(Players:GetPlayers()) do
	hook(p)
end
