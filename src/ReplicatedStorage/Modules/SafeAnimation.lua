local SafeAnimation = {}

local KNOWN_BLOCKED_IDS = {
	[84372816639111] = true,
	[71272992279195] = true,
	[81355594772429] = true,
	[88464588642501] = true,
	[90536498752484] = true,
	[94395632772482] = true,
	[101531100958187] = true,
	[107803805940614] = true,
	[108530253041260] = true,
	[109497771446379] = true,
	[110853770469931] = true,
	[119351181413931] = true,
	[121692489909418] = true,
	[124667521402664] = true,
	[133787706688058] = true,
	[135996778242052] = true,
	[136631925337185] = true,
	[136874323814262] = true,
}

local runtimeBlockedIds = {}

local function normalizeAnimationId(animationId)
	if typeof(animationId) == "number" then
		return math.floor(animationId)
	end

	if typeof(animationId) == "string" then
		local numeric = string.match(animationId, "(%d+)")
		return numeric and tonumber(numeric) or nil
	end

	return nil
end

local function getAnimator(target)
	if typeof(target) ~= "Instance" then
		return nil
	end

	local animator
	if target:IsA("Animator") then
		return target
	end

	local controller = nil
	if target:IsA("Humanoid") or target:IsA("AnimationController") then
		controller = target
	else
		controller = target:FindFirstChildOfClass("Humanoid")
			or target:FindFirstChildOfClass("AnimationController")
			or target:FindFirstChildWhichIsA("Humanoid", true)
			or target:FindFirstChildWhichIsA("AnimationController", true)
	end

	if not controller then
		return nil
	end

	animator = controller:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = controller
	end

	return animator
end

function SafeAnimation.IsBlocked(animationId)
	local normalized = normalizeAnimationId(animationId)
	return normalized ~= nil and (KNOWN_BLOCKED_IDS[normalized] == true or runtimeBlockedIds[normalized] == true)
end

function SafeAnimation.MarkBlocked(animationId)
	local normalized = normalizeAnimationId(animationId)
	if normalized then
		runtimeBlockedIds[normalized] = true
	end
end

function SafeAnimation.LoadTrack(target, animationId)
	local normalized = normalizeAnimationId(animationId)
	if not normalized or normalized == 0 or SafeAnimation.IsBlocked(normalized) then
		return nil, "blocked"
	end

	local animator = getAnimator(target)
	if not animator then
		return nil, "missing_animator"
	end

	local animation = Instance.new("Animation")
	animation.AnimationId = "rbxassetid://" .. tostring(normalized)

	local ok, track = pcall(function()
		return animator:LoadAnimation(animation)
	end)

	animation:Destroy()

	if not ok or not track then
		runtimeBlockedIds[normalized] = true
		return nil, "load_failed"
	end

	return track, nil
end

function SafeAnimation.PlayLooped(target, animationId)
	local track, reason = SafeAnimation.LoadTrack(target, animationId)
	if not track then
		return nil, reason
	end

	track.Looped = true

	local ok = pcall(function()
		track:Play()
	end)

	if not ok then
		SafeAnimation.MarkBlocked(animationId)
		return nil, "play_failed"
	end

	return track, nil
end

return SafeAnimation
