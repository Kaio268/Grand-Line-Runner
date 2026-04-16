local Debris = game:GetService("Debris")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Assets = ReplicatedStorage:WaitForChild("Assets")
local VfxAssets = Assets:WaitForChild("VFX")
local GomuVfxAssets = VfxAssets:WaitForChild("Gomu")

local GomuBombVfx = {}

local function getRootPart(player)
	if not player then
		return nil
	end

	local character = player.Character
	if not character then
		return nil
	end

	return character:FindFirstChild("HumanoidRootPart")
end

local function emitAll(effect)
	for _, obj in ipairs(effect:GetDescendants()) do
		if obj:IsA("ParticleEmitter") then
			local emitCount = obj:GetAttribute("EmitCount")
			if typeof(emitCount) ~= "number" or emitCount <= 0 then
				emitCount = 20
			end
			obj:Emit(emitCount)
		end
	end
end

function GomuBombVfx.Play(targetPlayer, payload)
	local template = GomuVfxAssets:FindFirstChild("GomuBomb")
	if not template then
		warn("[GomuBombVfx] Missing asset: ReplicatedStorage.Assets.VFX.Gomu.GomuBomb")
		return false
	end

	local effect = template:Clone()
	local position = payload and payload.Position
	local cf = payload and payload.CFrame

	if effect:IsA("Model") then
		if not effect.PrimaryPart then
			effect.PrimaryPart = effect:FindFirstChild("Start", true) or effect:FindFirstChildWhichIsA("BasePart", true)
		end

		if effect.PrimaryPart then
			if typeof(cf) == "CFrame" then
				effect:PivotTo(cf)
			elseif typeof(position) == "Vector3" then
				effect:PivotTo(CFrame.new(position))
			else
				local root = getRootPart(targetPlayer)
				if root then
					effect:PivotTo(root.CFrame)
				end
			end
		end
	end

	effect.Parent = Workspace
	emitAll(effect)
	Debris:AddItem(effect, 3)

	return true
end

return GomuBombVfx