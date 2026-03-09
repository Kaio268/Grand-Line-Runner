local NametagSettings = {
	["ShowsDisplayName"] = false,
	["DisplayPremium"] = false,
	["DisplayOwner"] = false,
	["DisplayAdmins"] = {
		false,
		AdminList = {"Adamk0_o"}
	},
}

local Players = game:GetService("Players")

local SHOW_TOP = 100
local BoardNames = {"TotalMoney", "TotalSpeed", "TimePlayed"}

local function getRankForBoard(player, boardName)
	local r = player:GetAttribute("LB_" .. boardName)
	if typeof(r) == "number" then return r end
	return nil
end

Players.PlayerAdded:Connect(function(Player)
	local function LoadOverhead(Character)
		repeat task.wait() until not Character or Character:FindFirstChild("Head")
		if not Character then return end

		local Humanoid = Character:WaitForChild("Humanoid", 10)
		if not Humanoid then return end

		local Tag = script:WaitForChild("Nametag"):Clone()

		local Text = Player.Name
		if NametagSettings.ShowsDisplayName then
			Text = Player.DisplayName
		end

		local pn = Tag:FindFirstChild("PlayerName")
		if pn and pn:IsA("TextLabel") then
			pn.Text = Text
			local inner = pn:FindFirstChild("PlayerName")
			if inner and inner:IsA("TextLabel") then
				inner.Text = Text
			end
		end

		local function applyBoardIcon(boardName, rank)
			local lbs = Tag:FindFirstChild("Leaderboards")
			if not lbs then return end

			local icon = lbs:FindFirstChild(boardName)
			if not icon then return end
			if not (icon:IsA("ImageLabel") or icon:IsA("Frame")) then return end

			local place = icon:FindFirstChild("Place")
			local shadow = place and place:FindFirstChild("Shadow")

			if rank and rank >= 1 and rank <= SHOW_TOP then
				icon.Visible = true
				if place and place:IsA("TextLabel") then
					place.Visible = true
					place.Text = "#" .. tostring(rank)
				end
				if shadow and shadow:IsA("TextLabel") then
					shadow.Visible = true
					shadow.Text = "#" .. tostring(rank)
				end
			else
				icon.Visible = false
				if place then place.Visible = false end
				if shadow then shadow.Visible = false end
			end
		end

		local function refreshAllLeaderboards()
			for _, boardName in ipairs(BoardNames) do
				local rank = getRankForBoard(Player, boardName)
				applyBoardIcon(boardName, rank)
			end
		end

		refreshAllLeaderboards()

		for _, boardName in ipairs(BoardNames) do
			Player:GetAttributeChangedSignal("LB_" .. boardName):Connect(refreshAllLeaderboards)
		end

		Humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		Tag.Parent = Character
		Tag.Adornee = Character:FindFirstChild("Head")
	end

	Player.CharacterAdded:Connect(function(Character)
		LoadOverhead(Character)
	end)
end)
