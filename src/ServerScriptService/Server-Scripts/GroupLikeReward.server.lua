local ServerScriptService = game:GetService("ServerScriptService")

local GroupLikeRewardService = require(
	ServerScriptService:WaitForChild("Modules"):WaitForChild("GroupLikeRewardService")
)

GroupLikeRewardService.Start()
