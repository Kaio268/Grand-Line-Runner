local Settings = {
	["Music"] = {Path = "Settings.Music", Type = "Slider", Start = 100, Min = 0, Max = 100},
	["SoundEffects"] = {Path = "Settings.Sounds", Type = "Slider", Start = 100, Min = 0, Max = 100},
	["Speed"] = {
		Path = "Settings.SelectedSpeed",
		Type = "Slider",
		Start = 1,
		Min = 1,
		DynamicMaxPath = "HiddenLeaderstats.Speed",
		AutoMaxPath = "Settings.SpeedAutoMax",
	},
 
	["LowGraphic"] = {Path = "Settings.LowGraphic", Type = "Switch", Start = false},
	["HidePopUps"] = {Path = "Settings.HidePopUps", Type = "Switch", Start = false},
	["PremiumStealProtection"] = {Path = "Settings.PremiumStealProtectionEnabled", Type = "Switch", Start = true},

}

return Settings
