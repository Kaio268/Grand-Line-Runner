local Players = game:GetService("Players")

local VIPTestOverrides = {}

local overridesByUserId = {}
local changedEvent = Instance.new("BindableEvent")

VIPTestOverrides.Changed = changedEvent.Event

local function getUserId(player: Player?): number?
	if player == nil then
		return nil
	end

	local numericUserId = tonumber(player.UserId)
	if numericUserId == nil then
		return nil
	end

	return math.floor(numericUserId)
end

local function getRealVipValue(player: Player?): boolean
	if player == nil then
		return false
	end

	local passes = player:FindFirstChild("Passes")
	local vip = passes and passes:FindFirstChild("VIP")
	return vip ~= nil and vip:IsA("BoolValue") and vip.Value == true
end

function VIPTestOverrides.GetOverride(player: Player?): boolean?
	local userId = getUserId(player)
	if userId == nil then
		return nil
	end

	return overridesByUserId[userId]
end

function VIPTestOverrides.SetOverride(player: Player, enabled: boolean): boolean
	local userId = getUserId(player)
	if userId == nil then
		return false
	end

	overridesByUserId[userId] = enabled == true
	changedEvent:Fire(player, overridesByUserId[userId])
	return true
end

function VIPTestOverrides.ClearOverride(player: Player): boolean
	local userId = getUserId(player)
	if userId == nil then
		return false
	end

	if overridesByUserId[userId] ~= nil then
		overridesByUserId[userId] = nil
		changedEvent:Fire(player, nil)
	end
	return true
end

function VIPTestOverrides.GetRealVip(player: Player?): boolean
	return getRealVipValue(player)
end

function VIPTestOverrides.GetEffectiveVip(player: Player?): (boolean, string)
	local override = VIPTestOverrides.GetOverride(player)
	if override ~= nil then
		return override == true, "temporary_override"
	end

	return getRealVipValue(player), "passes_vip_value"
end

Players.PlayerRemoving:Connect(function(player)
	local userId = getUserId(player)
	if userId ~= nil then
		overridesByUserId[userId] = nil
	end
end)

return VIPTestOverrides
