--[[
	Neutral FlameDash VFX backend.

	This keeps the FlameDash VFX API stable while leaving the move with no
	custom visuals so it can be rebuilt from a clean baseline.
]]

local FlameDashVfx = {}

local function createState(kind)
	return {
		Kind = kind,
		Destroyed = false,
	}
end

local function isLiveState(state)
	return type(state) == "table" and state.Destroyed ~= true
end

local function stopState(state)
	if type(state) ~= "table" then
		return false
	end

	state.Destroyed = true
	return true
end

function FlameDashVfx.PlayStartup(_options)
	return createState("FlameDashStartup")
end

function FlameDashVfx.StopStartup(state, _options)
	return stopState(state)
end

function FlameDashVfx.StartBody(_options)
	return createState("FlameDashMountedBody")
end

function FlameDashVfx.UpdateBody(state, _options)
	return isLiveState(state)
end

function FlameDashVfx.StopBody(state, _options)
	return stopState(state)
end

function FlameDashVfx.StartTrail(_options)
	return createState("FlameDashMountedTrail")
end

function FlameDashVfx.UpdateTrail(state, _options)
	return isLiveState(state)
end

function FlameDashVfx.StopTrail(state, _options)
	return stopState(state)
end

return FlameDashVfx
