local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Compatibility module. New code should require Modules.Server.Crew.Interaction.
return require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Server"):WaitForChild("Crew"):WaitForChild("Interaction"))
