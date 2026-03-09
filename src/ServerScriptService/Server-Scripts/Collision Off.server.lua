local Players = game:GetService("Players")
local PhysicsService = game:GetService("PhysicsService")
local GroupName = "Players"

PhysicsService:CreateCollisionGroup(GroupName)
PhysicsService:CollisionGroupSetCollidable(GroupName, GroupName, false)

Players.PlayerAdded:connect(function(Player)
	Player.CharacterAdded:Connect(function(Character)

		local function ChangeGroup(Part)
			if Part:IsA("BasePart") then
				PhysicsService:SetPartCollisionGroup(Part, "Players")
			end
		end

		Character.ChildAdded:Connect(ChangeGroup)
		for _, Object in pairs(Character:GetChildren()) do
			ChangeGroup(Object)
		end
	end)
end)