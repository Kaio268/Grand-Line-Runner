local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local camera = Workspace.CurrentCamera

local LuckyBlockHit = ReplicatedStorage:WaitForChild("LuckyBlockHit")
local BillboardTemplate = ReplicatedStorage:WaitForChild("BillboardGui")

local folder = Workspace:WaitForChild("EventFX_LuckyBlocks")
local active = {}

local function getRoot(model: Instance)
	if model:IsA("Model") then
		if model.PrimaryPart then
			return model.PrimaryPart
		end
		local p = model:FindFirstChildWhichIsA("BasePart", true)
		if p then
			model.PrimaryPart = p
			return p
		end
	end
	return model:FindFirstChildWhichIsA("BasePart", true)
end

local function findLuckyModel(inst: Instance)
	local cur = inst
	for _ = 1, 10 do
		if not cur then break end
		if cur:IsA("Model") and cur:GetAttribute("LuckyBlockId") then
			return cur
		end
		cur = cur.Parent
	end
	return nil
end

local function updateGui(model: Model, gui: BillboardGui)
	local hp = tonumber(model:GetAttribute("Health")) or 0
	local maxHp = tonumber(model:GetAttribute("MaxHealth")) or 1
	if maxHp <= 0 then maxHp = 1 end

	local ratio = math.clamp(hp / maxHp, 0, 1)

	local hb = gui:FindFirstChild("HealthBar", true)
	if hb then
		local bar = hb:FindFirstChild("Bar", true)
		if bar and bar:IsA("Frame") then
			TweenService:Create(bar, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				Size = UDim2.new(ratio, 0, 1, 0)
			}):Play()
		end

		local hpText = hb:FindFirstChild("Health", true)
		if hpText and hpText:IsA("TextLabel") then
			hpText.Text = tostring(hp)
		end
	end
end

local function ensureBillboard(model: Model)
	if active[model] and active[model].Gui and active[model].Gui.Parent then
		return active[model].Gui
	end

	local root = getRoot(model)
	if not root then return nil end

	local gui = BillboardTemplate:Clone()
	gui.Adornee = root
	gui.Enabled = true
	gui.Parent = model

	active[model] = active[model] or {}
	active[model].Gui = gui

	local function upd()
		if not model or not model.Parent then return end
		updateGui(model, gui)
	end

	active[model].Update = upd
	upd()

	active[model].Conn1 = model:GetAttributeChangedSignal("Health"):Connect(upd)
	active[model].Conn2 = model:GetAttributeChangedSignal("MaxHealth"):Connect(upd)

	return gui
end

local function cleanupModel(model: Model)
	local st = active[model]
	if not st then return end
	if st.Conn1 then st.Conn1:Disconnect() end
	if st.Conn2 then st.Conn2:Disconnect() end
	active[model] = nil
end

folder.ChildRemoved:Connect(function(child)
	if child:IsA("Model") then
		cleanupModel(child)
	end
end)

local function raycastFromMouse()
	local mousePos = UserInputService:GetMouseLocation()
	local unitRay = camera:ViewportPointToRay(mousePos.X, mousePos.Y)

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.IgnoreWater = true

	local ignore = {}
	local char = player.Character
	if char then table.insert(ignore, char) end
	params.FilterDescendantsInstances = ignore

	return Workspace:Raycast(unitRay.Origin, unitRay.Direction * 500, params)
end

UserInputService.InputBegan:Connect(function(input, gp)
	if gp then return end
	if input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end

	local result = raycastFromMouse()
	if not result or not result.Instance then return end

	local model = findLuckyModel(result.Instance)
	if not model then return end

	local id = model:GetAttribute("LuckyBlockId")
	if type(id) ~= "string" then return end

	ensureBillboard(model)
	LuckyBlockHit:FireServer(id)
end)
