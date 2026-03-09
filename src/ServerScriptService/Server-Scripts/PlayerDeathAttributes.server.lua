local Players = game:GetService("Players")

local function hook(plr)
	plr:SetAttribute("IsDead", false)
	if plr:GetAttribute("CarriedBrainrot") == nil then
		plr:SetAttribute("CarriedBrainrot", nil)
	end

	local function onChar(char)
		plr:SetAttribute("IsDead", false)
		local hum = char:WaitForChild("Humanoid", 10)
		if hum then
			hum.Died:Connect(function()
				if plr and plr.Parent then
					plr:SetAttribute("IsDead", true)
					plr:SetAttribute("CarriedBrainrot", nil)
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
