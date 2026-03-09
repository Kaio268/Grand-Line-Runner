local player = game.Players.LocalPlayer
local playerGui = player.PlayerGui

local remote = game.ReplicatedStorage.Remotes:WaitForChild("StandUpgradeRemote")

local Connections = {}

playerGui.ChildAdded:Connect(function(gui)
	if gui:IsA("SurfaceGui") and tonumber(gui.Name) then
		
		Connections[gui.Name] = gui:FindFirstChildOfClass("TextButton").MouseButton1Click:Connect(function()
			remote:FireServer(gui.Name)
		end)
		
	end
end)

playerGui.ChildRemoved:Connect(function(gui)
	if gui and gui:IsA("SurfaceGui") and tonumber(gui.Name) then
		
		Connections[gui.Name]:Disconnect()
		Connections[gui.Name] = nil
		
	end
end)