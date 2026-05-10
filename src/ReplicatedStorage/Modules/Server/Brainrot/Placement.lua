local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Compatibility path. New server code should require Modules.Server.Crew.Placement.
return require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Server"):WaitForChild("Crew"):WaitForChild("Placement"))
