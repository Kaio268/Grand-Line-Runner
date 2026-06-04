local AFK_PLACE_ID = 135767110031089
local MAIN_PLACE_ID = 111129977331443

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
