local Debris = game:GetService("Debris")
local Workspace = game:GetService("Workspace")

local BomuClient = {}
BomuClient.__index = BomuClient

local LAND_MINE_ABILITY = "LandMine"
local PLACEMENT_PULSE_NAME = "BomuLandMinePlacementPulse"

local function playLandMinePlacementPulse(worldPosition)
	if typeof(worldPosition) ~= "Vector3" then
		return false
	end

	local pulse = Instance.new("Part")
	pulse.Name = PLACEMENT_PULSE_NAME
	pulse.Anchored = true
	pulse.CanCollide = false
	pulse.CanTouch = false
	pulse.CanQuery = false
	pulse.Shape = Enum.PartType.Ball
	pulse.Material = Enum.Material.Neon
	pulse.Color = Color3.fromRGB(255, 89, 89)
	pulse.Transparency = 0.25
	pulse.Size = Vector3.new(1.1, 1.1, 1.1)
	pulse.CFrame = CFrame.new(worldPosition + Vector3.new(0, 0.35, 0))
	pulse.Parent = Workspace

	task.spawn(function()
		for _ = 1, 6 do
			if not pulse.Parent then
				break
			end

			pulse.Size += Vector3.new(0.18, 0.18, 0.18)
			pulse.Transparency += 0.1
			task.wait(0.03)
		end
	end)

	Debris:AddItem(pulse, 0.3)
	return true
end

function BomuClient.Create(config)
	local self = setmetatable({}, BomuClient)
	self.player = config and config.player or nil
	self.playOptionalEffect = type(config and config.PlayOptionalEffect) == "function" and config.PlayOptionalEffect or nil
	return self
end

function BomuClient:BeginPredictedRequest(abilityName, fallbackBuilder)
	if typeof(fallbackBuilder) == "function" then
		return fallbackBuilder()
	end

	return nil
end

function BomuClient:BuildRequestPayload(abilityName, abilityConfig, fallbackBuilder)
	if typeof(fallbackBuilder) == "function" then
		return fallbackBuilder()
	end

	return nil
end

function BomuClient:HandleEffect(targetPlayer, abilityName, payload)
	if abilityName ~= LAND_MINE_ABILITY or typeof(payload) ~= "table" then
		return false
	end

	if payload.Action ~= "Placed" then
		-- Detonation intentionally falls through so the current generic Bomu
		-- explosion fallback stays in control of that path.
		return false
	end

	local minePosition = payload.MinePosition or payload.OriginPosition
	if not playLandMinePlacementPulse(minePosition) then
		return false
	end

	return true
end

function BomuClient:HandleStateEvent(eventName, abilityName, value, payload)
	return false
end

function BomuClient:Update()
end

function BomuClient:HandleCharacterRemoving()
end

function BomuClient:HandlePlayerRemoving(leavingPlayer)
end

return BomuClient
