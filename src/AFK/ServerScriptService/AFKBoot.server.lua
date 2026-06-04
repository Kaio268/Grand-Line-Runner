local ServerScriptService = game:GetService("ServerScriptService")

local EXPECTED_AFK_PLACE_ID = 135767110031089

workspace:SetAttribute("GrandTideRush_ProjectRole", "AFK")
workspace:SetAttribute("GrandTideRush_ExpectedPlaceId", EXPECTED_AFK_PLACE_ID)
workspace:SetAttribute("GrandTideRush_ProjectPlaceMismatch", game.PlaceId ~= EXPECTED_AFK_PLACE_ID)

if game.PlaceId ~= EXPECTED_AFK_PLACE_ID then
	warn(
		string.format(
			"[AFKBoot] AFK project is running in place %s, but expected AFK Lobby place %s. Boot stopped.",
			tostring(game.PlaceId),
			tostring(EXPECTED_AFK_PLACE_ID)
		)
	)
	return
end

local DataManager = require(ServerScriptService:WaitForChild("Data"):WaitForChild("DataManager"))
local expectedMode = DataManager.BootModes.AFK

DataManager.init({
	Mode = expectedMode,
})

task.defer(function()
	local bootMode = workspace:GetAttribute("DataManager_BootMode")
	workspace:SetAttribute("AFKBoot_DataManagerBootModeObserved", bootMode)
	workspace:SetAttribute("AFKBoot_DataManagerBootModeOk", bootMode == expectedMode)
	if bootMode ~= expectedMode then
		warn(
			string.format(
				"[AFKBoot] Expected DataManager boot mode %s, but observed %s.",
				tostring(expectedMode),
				tostring(bootMode)
			)
		)
	end
end)
