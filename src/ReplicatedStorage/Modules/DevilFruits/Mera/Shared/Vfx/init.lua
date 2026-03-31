-- Shared/Vfx/init.lua
-- Thin VFX bootstrap for Mera Mera no Mi.
--
-- Loads FlameDashVfx and FireBurstVfx in isolation via pcall.
-- One module failure cannot kill the other.
-- This file has well under 200 locals — the previous version exceeded Luau's
-- compile-time limit of 200 local registers, preventing the entire module
-- from loading at all.

local Debris = game:GetService("Debris")
local RunService = game:GetService("RunService")

print("[MERA VFX] bootstrap load begin")

local FlameDashVfx = nil
local FireBurstVfx = nil

do
	local ok, result = pcall(function()
		return require(script:WaitForChild("FlameDashVfx"))
	end)
	if ok and result then
		FlameDashVfx = result
		print("[MERA VFX] bootstrap load success module=FlameDashVfx")
	else
		warn("[MERA VFX] bootstrap load fail module=FlameDashVfx reason=" .. tostring(result))
	end
end

do
	local ok, result = pcall(function()
		return require(script:WaitForChild("FireBurstVfx"))
	end)
	if ok and result then
		FireBurstVfx = result
		print("[MERA VFX] bootstrap load success module=FireBurstVfx")
	else
		warn("[MERA VFX] bootstrap load fail module=FireBurstVfx reason=" .. tostring(result))
	end
end

local allLoaded = FlameDashVfx ~= nil and FireBurstVfx ~= nil
print("[MERA VFX] bootstrap load " .. (allLoaded and "success" or "partial"))

-- ─── Public API ──────────────────────────────────────────────────────────────
-- Matches the API surface expected by MeraPresentationClient exactly.
-- All calls are wrapped in pcall so a runtime error in one effect cannot
-- propagate back into the presentation layer.

local MeraVfx = {}

-- ── FlameDash ────────────────────────────────────────────────────────────────

function MeraVfx.PlayFlameDashStartup(options)
	if not FlameDashVfx then
		return nil
	end
	local ok, result = pcall(FlameDashVfx.PlayStartup, options)
	if not ok then
		warn("[MERA VFX] FlameDash startup error=" .. tostring(result))
		return nil
	end
	return result
end

-- StartFlameDashHead maps to the body flame that follows the player.
function MeraVfx.StartFlameDashHead(options)
	if not FlameDashVfx then
		return nil
	end
	local ok, result = pcall(FlameDashVfx.StartBody, options)
	if not ok then
		warn("[MERA VFX] FlameDash head error=" .. tostring(result))
		return nil
	end
	return result
end

-- StartFlameDashPart maps to the stamp-based trail.
function MeraVfx.StartFlameDashPart(options)
	if not FlameDashVfx then
		return nil
	end
	local ok, result = pcall(FlameDashVfx.StartTrail, options)
	if not ok then
		warn("[MERA VFX] FlameDash part error=" .. tostring(result))
		return nil
	end
	return result
end

function MeraVfx.UpdateFlameDashHead(state, options)
	if not FlameDashVfx or not state then
		return false
	end
	local ok, result = pcall(FlameDashVfx.UpdateBody, state, options)
	if not ok then
		return false
	end
	return result == true
end

function MeraVfx.UpdateFlameDashPart(state, options)
	if not FlameDashVfx or not state then
		return false
	end
	local ok, result = pcall(FlameDashVfx.UpdateTrail, state, options)
	if not ok then
		return false
	end
	return result == true
end

function MeraVfx.StopFlameDashHead(state, options)
	if not FlameDashVfx or not state then
		return
	end
	pcall(FlameDashVfx.StopBody, state, options)
end

function MeraVfx.StopFlameDashPart(state, options)
	if not FlameDashVfx or not state then
		return
	end
	pcall(FlameDashVfx.StopTrail, state, options)
end

-- StopRuntimeState handles any generic state (startup, body, trail, burst startup).
-- Works by disconnecting any follow/update connections then scheduling cleanup.
function MeraVfx.StopRuntimeState(state, options)
	if type(state) ~= "table" then
		return
	end
	-- Disconnect any follow or heartbeat connection stored on the state.
	if typeof(state.FollowConnection) == "RBXScriptConnection" then
		state.FollowConnection:Disconnect()
		state.FollowConnection = nil
	end
	if typeof(state.Connection) == "RBXScriptConnection" then
		state.Connection:Disconnect()
		state.Connection = nil
	end
	state.Active = false
	-- Clean up any clone.
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

function MeraVfx.LogFlameDashCleanup(options)
	if RunService:IsStudio() then
		print(string.format(
			"[MERA VFX] FlameDash cleanup complete startup=%s part=%s dash=%s",
			tostring(options and options.Startup),
			tostring(options and options.Part),
			tostring(options and options.Dash)
		))
	end
end

-- ── FireBurst ────────────────────────────────────────────────────────────────

function MeraVfx.PlayFireBurstStartup(options)
	if not FireBurstVfx then
		print("[MERA VFX] FireBurst start skip reason=module_not_loaded")
		return nil
	end
	local ok, result = pcall(FireBurstVfx.PlayStartup, options)
	if not ok then
		warn("[MERA VFX] FireBurst startup error=" .. tostring(result))
		return nil
	end
	return result
end

function MeraVfx.PlayFireBurst(options)
	if not FireBurstVfx then
		print("[MERA VFX] FireBurst release skip reason=module_not_loaded")
		return false
	end
	local ok, result = pcall(FireBurstVfx.PlayBurst, options)
	if not ok then
		warn("[MERA VFX] FireBurst burst error=" .. tostring(result))
		return false
	end
	return result == true
end

-- Alias used by older call sites.
MeraVfx.PlayFlameBurst = MeraVfx.PlayFireBurst

return MeraVfx
