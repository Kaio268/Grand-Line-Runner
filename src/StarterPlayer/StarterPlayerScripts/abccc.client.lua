local Players = game:GetService("Players")
local GuiService = game:GetService("GuiService")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local remote = ReplicatedStorage:WaitForChild("RewardRemote")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local hud = playerGui:WaitForChild("HUD")
local leaving = hud:WaitForChild("Leaving")
local leavingInfo = hud:WaitForChild("LeavingInfo")

local gradientFolder = leaving:WaitForChild("Gradient")
local g1 = gradientFolder:WaitForChild("1")
local uiGradient = g1:IsA("UIGradient") and g1 or g1:FindFirstChildOfClass("UIGradient")

local letsDoIt = leaving:WaitForChild("LetsDoIt")
local timeLabel = leavingInfo:WaitForChild("Time")

local menuOpen = false
local spinning = false
local spinConn = nil

local countdownRunning = false
local countdownFinished = false
local remaining = 300

local claimedValueObj = nil

local function getClaimed()
	local attr = player:GetAttribute("ClaimedTolilola")
	if attr ~= nil then
		return attr == true
	end

	local hidden = player:FindFirstChild("HiddenLeaderstats")
	if hidden then
		local v = hidden:FindFirstChild("ClaimedTolilola")
		if v and v:IsA("BoolValue") then
			claimedValueObj = v
			return v.Value == true
		end
	end

	if claimedValueObj and claimedValueObj:IsA("BoolValue") then
		return claimedValueObj.Value == true
	end

	return false
end

local function hideAll()
	leaving.Visible = false
	leavingInfo.Visible = false
end

local function startSpin()
	if spinning then return end
	spinning = true
	if uiGradient then
		uiGradient.Rotation = -180
	end
	spinConn = RunService.RenderStepped:Connect(function(dt)
		if uiGradient then
			uiGradient.Rotation = (uiGradient.Rotation + dt * 180) % 360
		end
	end)
end

local function stopSpin()
	spinning = false
	if spinConn then
		spinConn:Disconnect()
		spinConn = nil
	end
end

local function setMenuState(open)
	if getClaimed() then
		hideAll()
		stopSpin()
		return
	end

	if open == menuOpen then return end
	menuOpen = open

	if menuOpen then
		leaving.Visible = true
		startSpin()
	else
		if not leavingInfo.Visible then
			leaving.Visible = false
		end
		stopSpin()
	end
end

local function formatTime(sec)
	local m = math.floor(sec / 60)
	local s = sec % 60
	return string.format("%02d:%02d", m, s)
end

local function countdownLoop()
	if countdownRunning or countdownFinished then return end
	if getClaimed() then
		hideAll()
		return
	end

	countdownRunning = true
	while remaining > 0 do
		if getClaimed() then
			hideAll()
			countdownRunning = false
			countdownFinished = true
			return
		end
		timeLabel.Text = formatTime(remaining)
		task.wait(1)
		remaining -= 1
	end

	timeLabel.Text = "00:00"
	leavingInfo.Visible = false
	countdownFinished = true
	countdownRunning = false
	remote:FireServer()
end

letsDoIt.MouseButton1Click:Connect(function()
	if getClaimed() then
		hideAll()
		return
	end

	leaving.Visible = false
	leavingInfo.Visible = true
	stopSpin()

	timeLabel.Text = formatTime(remaining)

	if not countdownFinished and not countdownRunning then
		task.spawn(countdownLoop)
	end
end)

if GuiService.MenuOpened then
	GuiService.MenuOpened:Connect(function()
		setMenuState(true)
	end)
end

if GuiService.MenuClosed then
	
end

UserInputService.InputBegan:Connect(function(input)
	if input.KeyCode == Enum.KeyCode.Escape then
		task.defer(function()
			if GuiService.MenuIsOpen ~= nil then
				setMenuState(GuiService.MenuIsOpen)
	 
			end
		end)
	end
end)

task.defer(function()
	hideAll()
	if GuiService.MenuIsOpen ~= nil then
		setMenuState(GuiService.MenuIsOpen)
	end
end)

player:GetAttributeChangedSignal("ClaimedTolilola"):Connect(function()
	if getClaimed() then
		hideAll()
		stopSpin()
	end
end)

task.spawn(function()
	local hidden = player:WaitForChild("HiddenLeaderstats", 10)
	if hidden then
		local v = hidden:FindFirstChild("ClaimedTolilola")
		if v and v:IsA("BoolValue") then
			claimedValueObj = v
			v.Changed:Connect(function()
				if getClaimed() then
					hideAll()
					stopSpin()
				end
			end)
		end
	end
end)
