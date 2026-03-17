do
	return require(game:GetService("ReplicatedStorage"):WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("LeaderboardChatConfig"))
end

return {
	Order = { "TotalMoney", "TotalPower", 'TotalWins'},

	Boards = {
		TotalMoney = {
			attr    = "TotalMoneyRank",
			emoji   = "??",
			showTop = 100,
			fmt     = "[%s #%d]",
			color   = ColorSequence.new({
				ColorSequenceKeypoint.new(0, Color3.fromRGB(112, 255, 136)),
				ColorSequenceKeypoint.new(1, Color3.fromRGB(80, 255, 49)),
			}),
		},

		TotalPower = {
			attr    = "TotalPowerRank",
			emoji   = "??",
			showTop = 100,
			fmt     = "[%s #%d]",
			color   = Color3.fromRGB(255, 49, 49),
		},

		TotalWins = {
			attr    = "TotalWinsRank",
			emoji   = "??",
			showTop = 100,
			fmt     = "[%s #%d]",
			color   = Color3.fromRGB(255, 201, 37),
		},
	},
}
