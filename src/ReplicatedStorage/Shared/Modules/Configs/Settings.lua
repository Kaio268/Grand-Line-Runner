do
	return require(game:GetService("ReplicatedStorage"):WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("Settings"))
end

local Settings = {
	["Music"] = {Path = "Settings.Music", Type = "Slider", Start = 100},
	["SoundEffects"] = {Path = "Settings.Sounds", Type = "Slider", Start = 100},
 
	["LowGraphic"] = {Path = "Settings.LowGraphic", Type = "Switch", Start = false},
	["HidePopUps"] = {Path = "Settings.HidePopUps", Type = "Switch", Start = false},

}

return Settings
