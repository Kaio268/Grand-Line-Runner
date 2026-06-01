local MovementSpeed = {
	FallbackBaseWalkSpeed = 16,
	RuntimeBaselineWalkSpeed = 20,
	RuntimeStatBaseline = 1,
	RuntimeWalkSpeedPerStat = 1,
	Attributes = {
		BaseWalkSpeed = "GrandLineRushBaseWalkSpeed",
		DisplaySpeed = "GrandLineRushDisplaySpeed",
	},
}

local function getValueNumber(instance)
	if instance and instance:IsA("ValueBase") then
		return tonumber(instance.Value)
	end

	return nil
end

function MovementSpeed.GetFallbackBaseWalkSpeed()
	return math.max(0, tonumber(MovementSpeed.FallbackBaseWalkSpeed) or 16)
end

function MovementSpeed.GetRuntimeBaseWalkSpeed(baseWalkSpeed)
	local fallbackBaseWalkSpeed = MovementSpeed.GetFallbackBaseWalkSpeed()
	local runtimeBaselineWalkSpeed = math.max(
		0,
		tonumber(MovementSpeed.RuntimeBaselineWalkSpeed) or fallbackBaseWalkSpeed
	)
	local baseWalkSpeedValue = tonumber(baseWalkSpeed) or fallbackBaseWalkSpeed
	return math.max(0, baseWalkSpeedValue + (runtimeBaselineWalkSpeed - fallbackBaseWalkSpeed))
end

function MovementSpeed.GetRuntimeWalkSpeedFromStat(baseWalkSpeed, selectedSpeed)
	local runtimeStatBaseline = math.max(0, tonumber(MovementSpeed.RuntimeStatBaseline) or 1)
	local runtimeWalkSpeedPerStat = math.max(0.001, tonumber(MovementSpeed.RuntimeWalkSpeedPerStat) or 1)
	local selectedSpeedValue = tonumber(selectedSpeed) or runtimeStatBaseline
	local speedStatOffset = math.max(0, selectedSpeedValue - runtimeStatBaseline)
	return MovementSpeed.GetRuntimeBaseWalkSpeed(baseWalkSpeed) + (speedStatOffset * runtimeWalkSpeedPerStat)
end

function MovementSpeed.GetStatSpeedFromRuntimeWalkSpeed(baseWalkSpeed, runtimeWalkSpeed)
	local runtimeStatBaseline = math.max(0, tonumber(MovementSpeed.RuntimeStatBaseline) or 1)
	local runtimeWalkSpeedPerStat = math.max(0.001, tonumber(MovementSpeed.RuntimeWalkSpeedPerStat) or 1)
	local runtimeWalkSpeedValue = tonumber(runtimeWalkSpeed) or 0
	local runtimeBaseWalkSpeed = MovementSpeed.GetRuntimeBaseWalkSpeed(baseWalkSpeed)
	local speedStatOffset = (runtimeWalkSpeedValue - runtimeBaseWalkSpeed) / runtimeWalkSpeedPerStat
	return math.max(0, runtimeStatBaseline + speedStatOffset)
end

function MovementSpeed.GetBaseWalkSpeedFromRuntimeStat(runtimeWalkSpeed, selectedSpeed)
	local fallbackBaseWalkSpeed = MovementSpeed.GetFallbackBaseWalkSpeed()
	local runtimeBaselineWalkSpeed = math.max(
		0,
		tonumber(MovementSpeed.RuntimeBaselineWalkSpeed) or fallbackBaseWalkSpeed
	)
	local runtimeStatBaseline = math.max(0, tonumber(MovementSpeed.RuntimeStatBaseline) or 1)
	local runtimeWalkSpeedPerStat = math.max(0.001, tonumber(MovementSpeed.RuntimeWalkSpeedPerStat) or 1)
	local runtimeWalkSpeedValue = tonumber(runtimeWalkSpeed) or 0
	local selectedSpeedValue = tonumber(selectedSpeed) or runtimeStatBaseline
	local speedStatOffset = math.max(0, selectedSpeedValue - runtimeStatBaseline)
	return runtimeWalkSpeedValue
		- (runtimeBaselineWalkSpeed - fallbackBaseWalkSpeed)
		- (speedStatOffset * runtimeWalkSpeedPerStat)
end

function MovementSpeed.GetPlayerSelectedSpeed(player)
	local hiddenStats = player and player:FindFirstChild("HiddenLeaderstats") or nil
	local speedValue = hiddenStats and hiddenStats:FindFirstChild("Speed") or nil
	local earnedSpeed = math.max(1, math.floor((getValueNumber(speedValue) or 1) + 0.5))
	local settings = player and player:FindFirstChild("Settings") or nil
	local autoMaxValue = settings and settings:FindFirstChild("SpeedAutoMax") or nil
	local selectedValue = settings and settings:FindFirstChild("SelectedSpeed") or nil

	if not (autoMaxValue and autoMaxValue:IsA("BoolValue") and autoMaxValue.Value == false) then
		return earnedSpeed
	end

	return math.clamp(math.floor((getValueNumber(selectedValue) or earnedSpeed) + 0.5), 1, earnedSpeed)
end

function MovementSpeed.GetPlayerRuntimeWalkSpeed(player, baseWalkSpeed)
	local resolvedBaseWalkSpeed = baseWalkSpeed
	if resolvedBaseWalkSpeed == nil and player then
		resolvedBaseWalkSpeed = player:GetAttribute(MovementSpeed.Attributes.BaseWalkSpeed)
	end

	return MovementSpeed.GetRuntimeWalkSpeedFromStat(resolvedBaseWalkSpeed, MovementSpeed.GetPlayerSelectedSpeed(player))
end

return MovementSpeed
