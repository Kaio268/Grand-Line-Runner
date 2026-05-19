local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local MoneyCollectedRE = Remotes:WaitForChild("StandMoneyCollected")

local Particles = ReplicatedStorage:FindFirstChild("Particles")
local MoneyEffectTemplate = Particles and Particles:FindFirstChild("MoneyEffect")

local dropMod = ReplicatedStorage.Modules.MoneyEffect

local BeliDropEffect = dropMod and require(dropMod) or nil

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

local function formatAmount(amount)
	local text = tostring(math.floor((tonumber(amount) or 0) + 0.5))
	local left, num, right = text:match("^([^%d]*%d)(%d*)(.-)$")
	return left .. (num:reverse():gsub("(%d%d%d)", "%1,"):reverse()) .. right
end

local function showIncomeToastDisplayName(primaryPart, amount, displayPayload)
	if typeof(displayPayload) ~= "table" then
		return
	end
	if tostring(displayPayload.Path or "") ~= "gameplay.helper.income_toast_display_name" then
		return
	end
	if displayPayload.IsAuthoritative == true then
		return
	end

	local displayName = tostring(displayPayload.DisplayName or "")
	if displayName == "" then
		return
	end

	local gui = Instance.new("BillboardGui")
	gui.Name = "IncomeToastDisplayName"
	gui.Adornee = primaryPart
	gui.AlwaysOnTop = true
	gui.MaxDistance = 120
	gui.Size = UDim2.fromOffset(180, 54)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 3.2, 0)
	gui.Parent = primaryPart

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.Size = UDim2.fromScale(1, 1)
	label.Text = string.format("+%s Beli\n%s", formatAmount(amount), displayName)
	label.TextColor3 = Color3.fromRGB(255, 235, 137)
	label.TextScaled = true
	label.TextStrokeColor3 = Color3.fromRGB(52, 38, 14)
	label.TextStrokeTransparency = 0.1
	label.Parent = gui

	local scale = Instance.new("UIScale")
	scale.Scale = 0.88
	scale.Parent = label

	TweenService:Create(scale, TweenInfo.new(0.14, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Scale = 1,
	}):Play()
	task.delay(1.05, function()
		if not label.Parent then
			return
		end
		TweenService:Create(label, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			TextTransparency = 1,
			TextStrokeTransparency = 1,
		}):Play()
	end)
	Debris:AddItem(gui, 1.5)
end

MoneyCollectedRE.OnClientEvent:Connect(function(standModel, amount, displayPayload)
	if typeof(standModel) ~= "Instance" or not standModel.Parent then
		return
	end

	local placed = standModel:FindFirstChild("PlacedCrewMember")
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

	if BeliDropEffect and typeof(BeliDropEffect.DropBeli) == "function" then
		local a = tonumber(amount) or 0
		local tokens = math.clamp(math.floor(a / 25), 6, 25)
		BeliDropEffect:DropBeli(pp.CFrame, tokens)
	end

	showIncomeToastDisplayName(pp, amount, displayPayload)
end)
