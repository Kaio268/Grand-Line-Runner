local AFK_PLACE_ID = 122987301330026
local MAIN_PLACE_ID = 110640828025742

workspace:SetAttribute("GrandTideRush_ProjectRole", "Main")
workspace:SetAttribute("GrandTideRush_ExpectedPlaceId", MAIN_PLACE_ID)
workspace:SetAttribute("GrandTideRush_ProjectPlaceMismatch", game.PlaceId == AFK_PLACE_ID)

if game.PlaceId == AFK_PLACE_ID then
	warn(
		string.format(
			"[DataInit] Main project boot script is running in AFK Lobby place %s. Boot stopped.",
			tostring(AFK_PLACE_ID)
		)
	)
	return
end

require(script.Parent.DataManager).init()
