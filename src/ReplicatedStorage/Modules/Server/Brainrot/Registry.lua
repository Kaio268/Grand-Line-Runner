local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Legacy module path kept while saved data and callers still use Brainrot keys.
-- New runtime model/config resolution should flow through CrewRegistry.
return require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Crew"):WaitForChild("CrewRegistry"))
