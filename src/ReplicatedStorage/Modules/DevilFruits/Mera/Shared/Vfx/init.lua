--[[
	Mera shared VFX bootstrap.

	This file is intentionally a thin adapter between high-level presentation code and
	per-move VFX modules such as `FlameDashVfx` and `FireBurstVfx`.

	It owns:
	- isolated module loading so one move's VFX cannot break another's
	- a stable public API for `MeraPresentationClient`
	- defensive `pcall` wrappers around each delegated VFX call
	- a small legacy `StopRuntimeState` helper for older state shapes

	It does not own:
	- move sequencing
	- gameplay logic
	- animation timing
]]

local Debris = game:GetService("Debris")
local RunService = game:GetService("RunService")

print("[MERA VFX] bootstrap load begin")

local FlameDashVfx = nil
local FireBurstVfx = nil

-- ============================================================================
-- Isolated Module Loading
-- ============================================================================
-- Each move module is loaded separately so a failure in one visual stack does not
-- cascade into the other move.

local function loadIsolatedVfxModule(moduleName)
	local ok, result = pcall(function()
		return require(script:WaitForChild(moduleName))
	end)

	if ok and result then
		print("[MERA VFX] bootstrap load success module=" .. moduleName)
		return result
	end

	warn("[MERA VFX] bootstrap load fail module=" .. moduleName .. " reason=" .. tostring(result))
	return nil
end

FlameDashVfx = loadIsolatedVfxModule("FlameDashVfx")
FireBurstVfx = loadIsolatedVfxModule("FireBurstVfx")

local allLoaded = FlameDashVfx ~= nil and FireBurstVfx ~= nil
print("[MERA VFX] bootstrap load " .. (allLoaded and "success" or "partial"))

-- ============================================================================
-- Safe Delegation Helpers
-- ============================================================================
-- Presentation code should not have to repeat the same `pcall`/warning pattern for
-- every phase call, so this file centralizes that defensive wrapper behavior.

local function callVfxMethod(moduleRef, methodName, failureLabel, ...)
	if not moduleRef then
		print("[MERA VFX] " .. tostring(failureLabel) .. " skip reason=module_not_loaded")
		return false, nil
	end

	local method = moduleRef[methodName]
	if type(method) ~= "function" then
		warn("[MERA VFX] missing method label=" .. tostring(failureLabel) .. " method=" .. tostring(methodName))
		return false, nil
	end

	local ok, result = pcall(method, ...)
	if not ok then
		warn("[MERA VFX] " .. tostring(failureLabel) .. " error=" .. tostring(result))
		return false, nil
	end

	return true, result
end

local MeraVfx = {}

-- ============================================================================
-- FlameDash Delegation
-- ============================================================================
-- Presentation treats FlameDash as startup + body/follow + trail + cleanup.
-- The public names here stay aligned with that presentation vocabulary.

function MeraVfx.PlayFlameDashStartup(options)
	local ok, result = callVfxMethod(FlameDashVfx, "PlayStartup", "FlameDash startup", options)
	return ok and result or nil
end

-- Legacy naming note:
-- `Head` is the active body/follow slash. The public API name remains stable for
-- callers, but the comment clarifies the move role.
function MeraVfx.StartFlameDashHead(options)
	local ok, result = callVfxMethod(FlameDashVfx, "StartBody", "FlameDash body", options)
	return ok and result or nil
end

-- Legacy naming note:
-- `Part` is the stamped trail layer. The comment keeps the role obvious without
-- changing the external method name expected by presentation code.
function MeraVfx.StartFlameDashPart(options)
	local ok, result = callVfxMethod(FlameDashVfx, "StartTrail", "FlameDash trail", options)
	return ok and result or nil
end

function MeraVfx.UpdateFlameDashHead(state, options)
	local ok, result = callVfxMethod(FlameDashVfx, "UpdateBody", "FlameDash body update", state, options)
	return ok and result == true or false
end

function MeraVfx.UpdateFlameDashPart(state, options)
	local ok, result = callVfxMethod(FlameDashVfx, "UpdateTrail", "FlameDash trail update", state, options)
	return ok and result == true or false
end

function MeraVfx.StopFlameDashHead(state, options)
	callVfxMethod(FlameDashVfx, "StopBody", "FlameDash body stop", state, options)
end

function MeraVfx.StopFlameDashPart(state, options)
	callVfxMethod(FlameDashVfx, "StopTrail", "FlameDash trail stop", state, options)
end

function MeraVfx.StopFlameDashStartup(state, options)
	callVfxMethod(FlameDashVfx, "StopStartup", "FlameDash startup stop", state, options)
end

-- Some older state shapes still need a generic cleanup path. This is kept as a
-- small fallback helper, not the preferred orchestration path for new move code.
function MeraVfx.StopRuntimeState(state, options)
	if type(state) ~= "table" then
		return
	end

	if typeof(state.FollowConnection) == "RBXScriptConnection" then
		state.FollowConnection:Disconnect()
		state.FollowConnection = nil
	end
	if typeof(state.Connection) == "RBXScriptConnection" then
		state.Connection:Disconnect()
		state.Connection = nil
	end

	state.Active = false
	local clone = state.Clone
	state.Clone = nil
	if clone and clone.Parent then
		local immediate = options and options.ImmediateCleanup
		local fadeTime = math.max(0, tonumber(options and options.FadeTime) or 0.1)
		if immediate then
			pcall(function()
				clone:Destroy()
			end)
		else
			Debris:AddItem(clone, fadeTime + 0.4)
		end
	end
end

function MeraVfx.LogFlameDashCleanup(_options)
	return nil
end

-- ============================================================================
-- FireBurst Delegation
-- ============================================================================
-- Presentation treats FireBurst as startup/charge -> release/burst -> cleanup.

function MeraVfx.PlayFireBurstStartup(options)
	local ok, result = callVfxMethod(FireBurstVfx, "PlayStartup", "FireBurst startup", options)
	return ok and result or nil
end

function MeraVfx.StopFireBurstStartup(state, options)
	local ok, result = callVfxMethod(FireBurstVfx, "StopStartup", "FireBurst startup stop", state, options)
	return ok and result == true or false
end

function MeraVfx.PlayFireBurst(options)
	local ok, result = callVfxMethod(FireBurstVfx, "PlayBurst", "FireBurst burst", options)
	return ok and result or nil
end

function MeraVfx.StopFireBurst(state, options)
	local ok, result = callVfxMethod(FireBurstVfx, "StopBurst", "FireBurst burst stop", state, options)
	return ok and result == true or false
end

-- Alias kept for older call sites that still say FlameBurst.
MeraVfx.PlayFlameBurst = MeraVfx.PlayFireBurst

return MeraVfx
