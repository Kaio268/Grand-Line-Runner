local TweenService    = game:GetService("TweenService")
local HttpService     = game:GetService("HttpService")
local Players         = game:GetService("Players")

local popup = require(game.ReplicatedStorage.Modules.PopUpModule)

local initialGoal  = 25
local currentGoal  = initialGoal
local universeId   = game.GameId
local pollDelay    = 25       -- seconds between polls
local tweenTime    = 0.5     -- seconds for the bar animation

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ServerEvents = ReplicatedStorage:FindFirstChild("ServerEvents")
if not ServerEvents then
	ServerEvents = Instance.new("Folder")
	ServerEvents.Name = "ServerEvents"
	ServerEvents.Parent = ReplicatedStorage
end

local LikeGoalSpawnSecret = ServerEvents:FindFirstChild("LikeGoalSpawnSecret")
if not LikeGoalSpawnSecret then
	LikeGoalSpawnSecret = Instance.new("BindableEvent")
	LikeGoalSpawnSecret.Name = "LikeGoalSpawnSecret"
	LikeGoalSpawnSecret.Parent = ServerEvents
end

local firstRun = true

local surfaceGuis = {}
for _, model in ipairs(workspace:WaitForChild("LikeGoals"):GetChildren()) do
	local timers = model:FindFirstChild("Timers")
	if timers then
		for _, gui in ipairs(timers:GetDescendants()) do
			if gui:IsA("SurfaceGui") then
				table.insert(surfaceGuis, gui)
			end
		end
	end
end

local function updateAllGuis(upVotes, goal)
	local pct = math.clamp(upVotes/goal, 0, 1)
	local targetSize = UDim2.fromScale(pct, 1)

	for _, sg in ipairs(surfaceGuis) do
		local txt = sg:FindFirstChild("Likes")
		local bar = sg:FindFirstChild("Bar") and sg.Bar:FindFirstChild("Bar")
		if txt then
			txt.Text = math.min(upVotes, goal) .. "/" .. goal .. " Likes"
		end
		if bar then
			local info = TweenInfo.new(tweenTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
			TweenService:Create(bar, info, { Size = targetSize }):Play()
		end
	end
end

local function spawnSecretPet()
	print("We reached the like goal, spawning Secret Pet!")
	LikeGoalSpawnSecret:Fire(1)
end

local function notifyAllPlayers()
	for _, ply in ipairs(Players:GetPlayers()) do
		popup:Server_SendPopUp(
			ply,
			"We reached the like goal, spawning Secret Pet!",
			Color3.new(0, 1, 0),      
			Color3.new(0, 0.5, 0),    
			10,                     
			false                    
		)
	end
end

local function pollLikes()
	local ok, res = pcall(HttpService.RequestAsync, HttpService, {
		Url    = string.format("https://games.roproxy.com/v1/games/%d/votes", universeId),
		Method = "GET",
	})
	if not ok or res.StatusCode < 200 or res.StatusCode >= 300 then
		warn("Like-fetch failed:", res)
		return
	end

	local data    = HttpService:JSONDecode(res.Body)
	local upVotes = data.upVotes or 0

	if firstRun then
		local reached = math.floor(upVotes / initialGoal)
		currentGoal = (reached + 1) * initialGoal
		updateAllGuis(upVotes, currentGoal)
		firstRun = false
		return
	end

	if upVotes >= currentGoal then
		spawnSecretPet()
		notifyAllPlayers()
		currentGoal = currentGoal + initialGoal
	end

	updateAllGuis(upVotes, currentGoal)
end

while true do
	pollLikes()
	task.wait(pollDelay)
end
 