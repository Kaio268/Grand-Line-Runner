do
	return require(game:GetService("ReplicatedStorage"):WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("LavaWaves"))
end

local Waves = {
	["HAHAH"] = {
		Speed = 60,
		Chance = 100,
		
		RotX = 0,
		RotY = 0,
		RotZ = 0,
		
		IMAGE = "rbxassetid://96345846540605"
	},
	
}

return Waves
