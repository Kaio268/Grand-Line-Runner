local ServerScriptService = game:GetService("ServerScriptService")

local RaidShieldService = require(ServerScriptService.Modules:WaitForChild("RaidShieldService"))

local Protection = {}

function Protection.GetProtectionState(player)
	return RaidShieldService.GetState(player)
end

function Protection.RefreshPlayer(player)
	return RaidShieldService.RefreshPlayer(player)
end

function Protection.IsProtected(player)
	return RaidShieldService.IsPlayerProtected(player)
end

function Protection.CanPersistRemoval(_playerOrUserId)
	return true, nil
end

function Protection.ClearProtection(playerOrUserId, reason)
	return RaidShieldService.ApplyRaidCompletedPenalty(playerOrUserId, {
		Reason = reason or "premium_crew_steal_clear",
	})
end

function Protection.Start()
	RaidShieldService.Start()
end

return Protection
