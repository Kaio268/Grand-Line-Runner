local ServerScriptService = game:GetService("ServerScriptService")

local MeleeAttackService = require(ServerScriptService:WaitForChild("Modules"):WaitForChild("MeleeAttackService"))

MeleeAttackService.BindTool(script.Parent, {
	MaxRange = 15,
	RagdollTime = 1.2,
	PushSpeed = 18,
	UpPush = 5,
	SwingWindow = 0.2,
	AttackCooldown = 0.25,
	MinFacingDot = 0.05,
})
