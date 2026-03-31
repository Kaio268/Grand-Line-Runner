local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local MoneyCollectedRE = Remotes:WaitForChild("StandMoneyCollected")

local Particles = ReplicatedStorage:FindFirstChild("Particles")
local MoneyEffectTemplate = Particles and Particles:FindFirstChild("MoneyEffect")

local dropMod = ReplicatedStorage.Modules.MoneyEffect

local DropDollars = dropMod and require(dropMod) or nil

local function getPrimaryPart(inst)
	if inst:IsA("BasePart") then
		return inst
	end
	if inst:IsA("Model") then
		if inst.PrimaryPart and inst.PrimaryPart:IsA("BasePart") then
			return inst.PrimaryPart
		end
		local pp = inst:FindFirstChildWhichIsA("BasePart", true)
		if pp then
			pcall(function()
				inst.PrimaryPart = pp
			end)
			return pp
		end
	end
	return nil
end

local function emitAll(effect)
	for _, d in ipairs(effect:GetDescendants()) do
		if d:IsA("ParticleEmitter") then
			if d.Name == "New Coin Particle" then
				d:Emit(15)
			else
				d:Emit(5)
			end
		end
	end
end

MoneyCollectedRE.OnClientEvent:Connect(function(standModel, amount)
	if typeof(standModel) ~= "Instance" or not standModel.Parent then
		return
	end

	local placed = standModel:FindFirstChild("PlacedBrainrot")
	if not placed then
		return
	end

	local pp = getPrimaryPart(placed)
	if not pp then
		return
	end

	if MoneyEffectTemplate then
		local fx = MoneyEffectTemplate:Clone()
		fx.Parent = pp
		emitAll(fx)
		Debris:AddItem(fx, 3)
	end

	if DropDollars and typeof(DropDollars.DropDollars) == "function" then
		local a = tonumber(amount) or 0
		local coins = math.clamp(math.floor(a / 25), 6, 25)
		DropDollars:DropDollars(pp.CFrame, coins)
	end
end)
