local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CrewRewardResolver = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Crew"):WaitForChild("CrewRewardResolver"))
local AddCrewMember = require(script.Parent:WaitForChild("AddCrewMember"))

local CrewRewardService = {}

local warnedUnresolved = {}

local function warnUnresolved(context, input, resolved)
	local key = tostring(context or "CrewReward") .. ":" .. tostring(input or "")
	if warnedUnresolved[key] then
		return
	end

	warnedUnresolved[key] = true
	warn(
		"[CrewRewardResolver] Unresolved crew reward; grant skipped",
		"context=" .. tostring(context or "CrewReward"),
		"reward=" .. tostring(input or ""),
		"reason=" .. tostring(resolved and resolved.Reason or "unknown")
	)
end

function CrewRewardService.Resolve(input, config)
	return CrewRewardResolver.Resolve(input, config)
end

function CrewRewardService.GetDisplayName(input, config)
	return CrewRewardResolver.GetDisplayName(input, config)
end

function CrewRewardService.Grant(player, input, amount, options)
	local inputOptions = if typeof(options) == "table" then options else nil
	local resolved = CrewRewardResolver.Resolve(input, inputOptions and inputOptions.Config)
	local context = inputOptions and inputOptions.Context or inputOptions and inputOptions.Source or "CrewReward"

	if resolved.Resolved ~= true then
		warnUnresolved(context, input, resolved)
		return false, resolved, "unresolved_crew_reward"
	end

	local grantOptions = {}
	if inputOptions then
		for key, value in pairs(inputOptions) do
			if key ~= "Config" and key ~= "Context" then
				grantOptions[key] = value
			end
		end
	end

	local ok, createdIds = AddCrewMember:AddCrewMember(player, resolved.GrantName, amount or 1, grantOptions)
	if ok ~= true then
		return false, resolved, "crew_member_grant_failed"
	end

	return true, resolved, nil, createdIds
end

return CrewRewardService
