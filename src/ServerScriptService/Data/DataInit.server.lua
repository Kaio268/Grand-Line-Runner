local DataEnvironment = require(script.Parent.DataEnvironment)

local placeInfo = DataEnvironment.ResolvePlace(game.PlaceId)
local placePair = DataEnvironment.GetPlacePairForEnvironment(placeInfo.Environment)
local expectedMainPlaceId = if placePair ~= nil then placePair.MainPlaceId else 0

workspace:SetAttribute("GrandTideRush_ProjectRole", "Main")
workspace:SetAttribute("GrandTideRush_ExpectedPlaceId", expectedMainPlaceId)
workspace:SetAttribute("GrandTideRush_ProjectPlaceMismatch", placeInfo.PlaceRole == DataEnvironment.PlaceRoles.AFK)

if placeInfo.PlaceRole == DataEnvironment.PlaceRoles.AFK then
	warn(
		string.format(
			"[DataInit] Main project boot script is running in %s AFK place %s. Boot stopped.",
			tostring(placeInfo.Environment),
			tostring(game.PlaceId)
		)
	)
	return
end

require(script.Parent.DataManager).init()
