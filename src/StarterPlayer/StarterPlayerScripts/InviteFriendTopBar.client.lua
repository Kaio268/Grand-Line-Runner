local Icon = require(game:GetService("ReplicatedStorage").Icon)
local SocialService = game:GetService("SocialService")
local Player = game.Players.LocalPlayer

local icon = Icon.new()
	:align("Right") 
	:setLabel("Invite Friends", "deselected")
	:setLabel("Open", "selected")
	:setCaption("Invite your friends For Free Rewards!")

local function onButtonPressed()
	local success, result = pcall(function()
		return SocialService:CanSendGameInviteAsync(Player)
	end)

	if success and result == true then
		SocialService:PromptGameInvite(Player)
	end
end

icon.selected:Connect(function()
	onButtonPressed()
end)
