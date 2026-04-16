local Players = game:GetService("Players")
local PhysicsService = game:GetService("PhysicsService")
local GroupName = "Players"

pcall(function()
	PhysicsService:RegisterCollisionGroup(GroupName)
end)
PhysicsService:CollisionGroupSetCollidable(GroupName, GroupName, false)

Players.PlayerAdded:Connect(function(Player)
	Player.CharacterAdded:Connect(function(Character)
		local function ChangeGroup(Part)
			if Part:IsA("BasePart") then
				Part.CollisionGroup = GroupName
			end
		end

		Character.ChildAdded:Connect(ChangeGroup)
		for _, Object in ipairs(Character:GetChildren()) do
			ChangeGroup(Object)
		end
	end)
end)
