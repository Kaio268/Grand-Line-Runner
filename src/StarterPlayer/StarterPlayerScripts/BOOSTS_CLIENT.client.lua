local Players = game:GetService("Players")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local function hideLegacyBoosts()
	local hud = playerGui:FindFirstChild("HUD")
	if not hud then
		return
	end

	local boosts = hud:FindFirstChild("Boosts")
	if not boosts or not boosts:IsA("GuiObject") then
		return
	end

	boosts.Visible = false
	boosts.BackgroundTransparency = 1
	boosts.Size = UDim2.fromOffset(0, 0)

	for _, descendant in ipairs(boosts:GetDescendants()) do
		if descendant:IsA("GuiObject") then
			descendant.Visible = false
			if descendant:IsA("TextLabel") or descendant:IsA("TextButton") or descendant:IsA("TextBox") then
				descendant.TextTransparency = 1
				descendant.TextStrokeTransparency = 1
			elseif descendant:IsA("ImageLabel") or descendant:IsA("ImageButton") then
				descendant.ImageTransparency = 1
			end
		elseif descendant:IsA("UIStroke") or descendant:IsA("UIGradient") then
			descendant.Enabled = false
		end
	end
end

hideLegacyBoosts()

playerGui.DescendantAdded:Connect(function(descendant)
	if descendant.Name == "HUD" or descendant.Name == "Boosts" then
		task.defer(hideLegacyBoosts)
	end
end)
