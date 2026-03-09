local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local inv = player:WaitForChild("Potions")
local gui = player.PlayerGui:WaitForChild("HUD"):WaitForChild("Boosts") 
local template = gui:WaitForChild("Template")

local active = {}

local function setImageFor(ui, icon)
	if typeof(icon) == "number" then
		icon = "rbxassetid://" .. icon
	else
		icon = tostring(icon)
	end
	if ui:IsA("ImageLabel") or ui:IsA("ImageButton") then
		ui.Image = icon
	elseif ui:FindFirstChild("Icon") and ui.Icon:IsA("ImageLabel") then
		ui.Icon.Image = icon
	end
end

local function getScale(ui)
	local s = ui:FindFirstChildOfClass("UIScale")
	if not s then
		s = Instance.new("UIScale")
		s.Scale = 0
		s.Parent = ui
	end
	return s
end

local function animateIn(ui)
	local scale = getScale(ui)
	scale.Scale = 0
	task.defer(function()
		TweenService:Create(scale, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Scale = 1}):Play()
	end)
end

local function animateOutAndDestroy(ui)
	local scale = getScale(ui)
	local t = TweenService:Create(scale, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {Scale = 0})
	t.Completed:Once(function()
		ui:Destroy()
	end)
	t:Play()
end

local function formatTime(seconds)
	seconds = math.max(0, math.floor(tonumber(seconds) or 0))
	local d = math.floor(seconds/86400)
	seconds = seconds % 86400
	local h = math.floor(seconds/3600)
	seconds = seconds % 3600
	local m = math.floor(seconds/60)
	local s = seconds % 60
	local parts = {}
	if d > 0 then table.insert(parts, d.."d") end
	if h > 0 then table.insert(parts, h.."h") end
	if m > 0 then table.insert(parts, m.."m") end
	if s > 0 or #parts == 0 then table.insert(parts, s.."s") end
	if #parts >= 2 then
		return parts[1].." "..parts[2]
	else
		return parts[1]
	end
end

local function updateUIFor(timeValue)
	local ui = active[timeValue]
	local v = timeValue.Value
	if v > 0 then
		if not ui or not ui.Parent then
			local baseName = string.sub(timeValue.Name, 1, #timeValue.Name - 4)
			local base = timeValue.Parent and timeValue.Parent:FindFirstChild(baseName)
			local iconAttr = base and base:GetAttribute("Icon")
			ui = template:Clone()
			ui.Name = baseName
			ui.Visible = true
			ui.Parent = gui
			if iconAttr ~= nil then
				setImageFor(ui, iconAttr)
			end
			animateIn(ui)
			active[timeValue] = ui
		end
		local countLabel = ui:FindFirstChild("Count")
		if countLabel and countLabel:IsA("TextLabel") then
			countLabel.Text = formatTime(v)
		end
	else
		if ui then
			active[timeValue] = nil
			animateOutAndDestroy(ui)
		end
	end
end

local function hookValue(nv)
	if nv:IsA("NumberValue") and string.sub(nv.Name, -4) == "Time" then
		updateUIFor(nv)
		nv:GetPropertyChangedSignal("Value"):Connect(function()
			updateUIFor(nv)
		end)
		nv.AncestryChanged:Connect(function(_, parent)
			if not parent then
				local ui = active[nv]
				if ui then
					active[nv] = nil
					animateOutAndDestroy(ui)
				end
			end
		end)
	end
end

for _, d in ipairs(inv:GetDescendants()) do
	hookValue(d)
end

inv.DescendantAdded:Connect(hookValue)
