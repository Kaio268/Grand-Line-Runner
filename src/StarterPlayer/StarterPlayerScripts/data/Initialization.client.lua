local Start = tick()

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Player = Players.LocalPlayer

local function markDataRequestSent()
	local modules = ReplicatedStorage:FindFirstChild("Modules")
	local startupStateScript = modules and modules:FindFirstChild("StartupState")
	if startupStateScript and startupStateScript:IsA("ModuleScript") then
		local ok, StartupState = pcall(require, startupStateScript)
		if ok and typeof(StartupState) == "table" and StartupState.MarkDataRequestSent then
			if StartupState.MarkDataRequestSent(Player) then
				return
			end
		end
	end

	local playerGui = Player:FindFirstChildOfClass("PlayerGui")
	if playerGui then
		playerGui:SetAttribute("StartupDataRequestSent", true)
		return
	end

	task.spawn(function()
		playerGui = Player:WaitForChild("PlayerGui", 2)
		if playerGui then
			playerGui:SetAttribute("StartupDataRequestSent", true)
		end
	end)
end

local DataScript = require(script.Parent.Client_Data)
DataScript.New("PlayerDataStore")
markDataRequestSent()

local ready = DataScript.WaitUntilReady(30)
if ready then
	DataScript:GetData()
	print("Client {RP} took " .. (tick() - Start) .. "s to load!")
else
	warn(string.format(
		"[ClientData] Timed out waiting for PlayerDataStore for %s(%d) after %.1fs; continuing startup.",
		Player.Name,
		Player.UserId,
		tick() - Start
	))
end
