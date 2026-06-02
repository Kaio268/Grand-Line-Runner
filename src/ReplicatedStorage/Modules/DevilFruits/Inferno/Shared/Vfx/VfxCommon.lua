-- VfxCommon.lua
-- Minimal shared utilities for Mera VFX.
-- All helpers are pure functions with no global state.

local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local VfxCommon = {}

-- Navigate a path from ReplicatedStorage using a list of child names.
-- Returns nil if any step is missing.
function VfxCommon.FindAsset(...)
	local node = ReplicatedStorage
	for _, seg in ipairs({...}) do
		if not node then
			return nil
		end
		node = node:FindFirstChild(seg)
	end
	return node
end

-- Find the first child whose name matches any entry in `candidates`.
function VfxCommon.FindChild(parent, candidates)
	if not parent then
		return nil
	end
	for _, name in ipairs(candidates) do
		local child = parent:FindFirstChild(name)
		if child then
			return child
		end
	end
	return nil
end

-- Disable all physics interaction on BaseParts under `root`.
-- VFX clones must never collide with or push the player.
local function disablePartPhysics(root)
	local function apply(item)
		if item:IsA("BasePart") then
			item.CanCollide = false
			item.CanTouch = false
			item.CanQuery = false
		end
	end
	apply(root)
	for _, desc in ipairs(root:GetDescendants()) do
		apply(desc)
	end
end

-- Clone `source` and parent it to `newParent`. Returns nil on failure.
-- All BaseParts in the clone have physics interaction disabled so they
-- cannot push or affect the local player.
function VfxCommon.Clone(source, newParent)
	if not source then
		return nil
	end
	local ok, clone = pcall(function()
		return source:Clone()
	end)
	if not ok or not clone then
		return nil
	end
	disablePartPhysics(clone)
	clone.Parent = newParent
	return clone
end

-- Enable or disable all visual effect instances under `root`.
local function setEffectsEnabled(root, enabled)
	if not root then
		return
	end
	local check = function(item)
		if
			item:IsA("ParticleEmitter")
			or item:IsA("Trail")
			or item:IsA("Beam")
			or item:IsA("Smoke")
			or item:IsA("Fire")
			or item:IsA("Sparkles")
		then
			item.Enabled = enabled
		end
	end
	check(root)
	for _, desc in ipairs(root:GetDescendants()) do
		check(desc)
	end
end

function VfxCommon.EnableEffects(root)
	setEffectsEnabled(root, true)
end

function VfxCommon.DisableEffects(root)
	setEffectsEnabled(root, false)
end

-- Call :Emit(count) on every ParticleEmitter under `root`.
function VfxCommon.EmitAll(root, count)
	if not root then
		return
	end
	local n = math.max(1, math.floor(tonumber(count) or 20))
	local emit = function(item)
		if item:IsA("ParticleEmitter") then
			pcall(function()
				item:Emit(n)
			end)
		end
	end
	emit(root)
	for _, desc in ipairs(root:GetDescendants()) do
		emit(desc)
	end
end

-- Schedule destruction of `instance` after `delay` seconds via Debris.
function VfxCommon.Cleanup(instance, delay)
	if not instance then
		return
	end
	Debris:AddItem(instance, math.max(0, tonumber(delay) or 0))
end

-- Disable effects and schedule destruction after `fadeTime + holdTime` seconds.
function VfxCommon.FadeAndCleanup(root, fadeTime, holdTime)
	if not root then
		return
	end
	setEffectsEnabled(root, false)
	local total = math.max(0, tonumber(fadeTime) or 0.15) + math.max(0, tonumber(holdTime) or 0.5)
	Debris:AddItem(root, total)
end

return VfxCommon
