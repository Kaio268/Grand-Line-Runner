local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local AbilityTargeting = require(
	ReplicatedStorage:WaitForChild("Modules")
		:WaitForChild("DevilFruits")
		:WaitForChild("Shared")
		:WaitForChild("AbilityTargeting")
)
local AdminInvincibility = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("AdminInvincibility"))
local DevilFruitConfig = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("DevilFruits"))

local DamageProtection = {}

local MOGU_STARTUP_INVINCIBLE_FROM_ATTRIBUTE = "MoguStartupInvincibleFrom"
local MOGU_STARTUP_INVINCIBLE_UNTIL_ATTRIBUTE = "MoguStartupInvincibleUntil"
local MOGU_STARTUP_INVINCIBLE_SECONDS_ATTRIBUTE = "MoguStartupInvincibleSeconds"
local MOGU_STARTUP_INVINCIBLE_START_OFFSET_SECONDS_ATTRIBUTE = "MoguStartupInvincibleStartOffsetSeconds"
local MOGU_STARTUP_INVINCIBLE_SESSION_ID_ATTRIBUTE = "MoguStartupInvincibleSessionId"
local MOGU_BURROW_SESSION_ID_ATTRIBUTE = "MoguBurrowSessionId"
local MOGU_BURROW_SESSION_STATE_ATTRIBUTE = "MoguBurrowSessionState"
local MOGU_FRUIT_NAME = "Mogu Mogu no Mi"
local MOGU_BURROW_ABILITY = "Burrow"
local MOGU_STARTUP_STATE = "Startup"
local STARTUP_TRACE_RECENT_GRACE_SECONDS = 0.75

local function getMoguBurrowConfig()
	return DevilFruitConfig.GetAbility(MOGU_FRUIT_NAME, MOGU_BURROW_ABILITY) or {}
end

local function isMoguStartupDamageTraceEnabled()
	return getMoguBurrowConfig().DebugStartupDamageTrace == true
end

local function getPlayer(target, targetContext)
	if type(targetContext) == "table" and targetContext.Player and targetContext.Player:IsA("Player") then
		return targetContext.Player
	end

	if typeof(target) ~= "Instance" then
		return nil
	end

	if target:IsA("Player") then
		return target
	end

	if target:IsA("Model") then
		return Players:GetPlayerFromCharacter(target)
	end

	if target:IsA("Humanoid") then
		return Players:GetPlayerFromCharacter(target.Parent)
	end

	local character = target:FindFirstAncestorOfClass("Model")
	return character and Players:GetPlayerFromCharacter(character) or nil
end

local function getPosition(options, targetContext)
	if type(options) == "table" then
		if typeof(options.Position) == "Vector3" then
			return options.Position
		end
		if typeof(options.HitPosition) == "Vector3" then
			return options.HitPosition
		end
	end

	local rootPart = type(targetContext) == "table" and targetContext.RootPart or nil
	if rootPart and rootPart:IsA("BasePart") then
		return rootPart.Position
	end

	return nil
end

local function getMoguStartupInvincibility(player, position)
	if not player or not player:IsA("Player") then
		return nil
	end

	if player:GetAttribute(MOGU_BURROW_SESSION_STATE_ATTRIBUTE) ~= MOGU_STARTUP_STATE then
		return nil
	end

	local activeSessionId = player:GetAttribute(MOGU_BURROW_SESSION_ID_ATTRIBUTE)
	local invincibleSessionId = player:GetAttribute(MOGU_STARTUP_INVINCIBLE_SESSION_ID_ATTRIBUTE)
	if typeof(activeSessionId) ~= "string" or activeSessionId == "" or invincibleSessionId ~= activeSessionId then
		return nil
	end

	local now = Workspace:GetServerTimeNow()
	local invincibleFrom = player:GetAttribute(MOGU_STARTUP_INVINCIBLE_FROM_ATTRIBUTE)
	if typeof(invincibleFrom) == "number" and now < invincibleFrom then
		return nil
	end

	local invincibleUntil = player:GetAttribute(MOGU_STARTUP_INVINCIBLE_UNTIL_ATTRIBUTE)
	if typeof(invincibleUntil) ~= "number" or invincibleUntil <= now then
		return nil
	end

	return {
		Protected = true,
		Source = "MoguBurrow",
		Reason = "mogu_startup_invincible",
		Player = player,
		Position = position,
		SessionId = activeSessionId,
		From = invincibleFrom,
		Until = invincibleUntil,
	}
end

local function formatNumber(value)
	if typeof(value) ~= "number" then
		return tostring(value)
	end

	return string.format("%.3f", value)
end

local function formatVector3(value)
	if typeof(value) ~= "Vector3" then
		return tostring(value)
	end

	return string.format("(%.2f, %.2f, %.2f)", value.X, value.Y, value.Z)
end

local function isMoguStartupTraceRelevant(player, now)
	if not player or not player:IsA("Player") then
		return false
	end

	if player:GetAttribute(MOGU_BURROW_SESSION_STATE_ATTRIBUTE) == MOGU_STARTUP_STATE then
		return true
	end

	local invincibleUntil = player:GetAttribute(MOGU_STARTUP_INVINCIBLE_UNTIL_ATTRIBUTE)
	if typeof(invincibleUntil) == "number" and now <= invincibleUntil + STARTUP_TRACE_RECENT_GRACE_SECONDS then
		return true
	end

	return false
end

local function traceMoguStartupDamage(target, options)
	if not isMoguStartupDamageTraceEnabled() then
		return false
	end

	options = type(options) == "table" and options or {}
	local targetContext = type(options.TargetContext) == "table" and options.TargetContext
		or AbilityTargeting.GetCharacterContext(target)
	local player = getPlayer(target, targetContext)
	if not player then
		return false
	end

	local now = Workspace:GetServerTimeNow()
	if not isMoguStartupTraceRelevant(player, now) then
		return false
	end

	local position = getPosition(options, targetContext)
	local protection = if type(options.Protection) == "table"
		then options.Protection
		else getMoguStartupInvincibility(player, position)
	local invincibleFrom = player:GetAttribute(MOGU_STARTUP_INVINCIBLE_FROM_ATTRIBUTE)
	local invincibleUntil = player:GetAttribute(MOGU_STARTUP_INVINCIBLE_UNTIL_ATTRIBUTE)
	local startsIn = if typeof(invincibleFrom) == "number" then invincibleFrom - now else nil
	local remaining = if typeof(invincibleUntil) == "number" then invincibleUntil - now else nil
	local humanoid = targetContext and targetContext.Humanoid
	local health = if humanoid and humanoid:IsA("Humanoid") then humanoid.Health else nil

	print(string.format(
		"[MOGU STARTUP DAMAGE TRACE] path=%s source=%s player=%s now=%s state=%s session=%s invincibleFrom=%s invincibleStartsIn=%s invincibleUntil=%s invincibleRemaining=%s invincibleSession=%s invincibleSeconds=%s invincibleStartOffset=%s protected=%s reason=%s health=%s position=%s",
		tostring(options.Path or options.Source or "unknown"),
		tostring(options.Source or "unknown"),
		player.Name,
		formatNumber(now),
		tostring(player:GetAttribute(MOGU_BURROW_SESSION_STATE_ATTRIBUTE)),
		tostring(player:GetAttribute(MOGU_BURROW_SESSION_ID_ATTRIBUTE)),
		formatNumber(invincibleFrom),
		formatNumber(startsIn),
		formatNumber(invincibleUntil),
		formatNumber(remaining),
		tostring(player:GetAttribute(MOGU_STARTUP_INVINCIBLE_SESSION_ID_ATTRIBUTE)),
		formatNumber(player:GetAttribute(MOGU_STARTUP_INVINCIBLE_SECONDS_ATTRIBUTE)),
		formatNumber(player:GetAttribute(MOGU_STARTUP_INVINCIBLE_START_OFFSET_SECONDS_ATTRIBUTE)),
		tostring(protection ~= nil),
		tostring(protection and protection.Reason or "none"),
		formatNumber(health),
		formatVector3(position)
	))

	return true
end

function DamageProtection.GetProtection(target, options)
	options = type(options) == "table" and options or {}
	local targetContext = type(options.TargetContext) == "table" and options.TargetContext
		or AbilityTargeting.GetCharacterContext(target)
	local player = getPlayer(target, targetContext)
	if not player then
		return nil
	end

	local position = getPosition(options, targetContext)
	if AdminInvincibility.IsEnabled(player) then
		return {
			Protected = true,
			Source = "AdminInvincible",
			Reason = "admin_invincible",
			Player = player,
			Position = position,
		}
	end

	local protection = getMoguStartupInvincibility(player, position)
	if protection then
		traceMoguStartupDamage(player, {
			TargetContext = targetContext,
			Position = position,
			Source = options.Source or "DamageProtection",
			Path = "DamageProtection.GetProtection",
			Protection = protection,
		})
	end

	return protection
end

function DamageProtection.IsProtected(target, options)
	local protection = DamageProtection.GetProtection(target, options)
	if not protection then
		return false
	end

	return true, string.format("%s:%s", tostring(protection.Source), tostring(protection.Reason)), protection
end

function DamageProtection.IsMoguStartupDamageTraceEnabled()
	return isMoguStartupDamageTraceEnabled()
end

function DamageProtection.TraceMoguStartupDamage(target, options)
	return traceMoguStartupDamage(target, options)
end

return DamageProtection
