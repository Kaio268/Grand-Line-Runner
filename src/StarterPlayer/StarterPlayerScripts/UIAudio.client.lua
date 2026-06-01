local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameSounds = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("GameSounds"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local boundButtons = setmetatable({}, { __mode = "k" })
local lastClickAtByButton = setmetatable({}, { __mode = "k" })

local CLICK_THROTTLE = 0.05

local function playUiSound(soundId, volume)
	GameSounds.Play2D(soundId, {
		Name = "GLRUiSound",
		Volume = volume or 0.75,
		Lifetime = 3,
	})
end

local function bindButton(button)
	if not button:IsA("GuiButton") or boundButtons[button] then
		return
	end

	boundButtons[button] = true
	button.MouseEnter:Connect(function()
		if button.Active ~= false and button.Visible ~= false then
			playUiSound(GameSounds.Ids.UI.Hover, 0.45)
		end
	end)

	button.Activated:Connect(function()
		local now = os.clock()
		if now - (lastClickAtByButton[button] or 0) < CLICK_THROTTLE then
			return
		end
		lastClickAtByButton[button] = now
		playUiSound(GameSounds.Ids.UI.Click, 0.7)
	end)
end

for _, descendant in ipairs(playerGui:GetDescendants()) do
	bindButton(descendant)
end

playerGui.DescendantAdded:Connect(bindButton)
