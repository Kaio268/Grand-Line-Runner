local ServerScriptService = game:GetService("ServerScriptService")

local DataEnvironment = require(ServerScriptService:WaitForChild("Data"):WaitForChild("DataEnvironment"))

local placeInfo = DataEnvironment.ResolvePlace(game.PlaceId)
local placePair = DataEnvironment.GetPlacePairForEnvironment(placeInfo.Environment)
local expectedAfkPlaceId = if placePair ~= nil then placePair.AFKPlaceId else 0

workspace:SetAttribute("GrandTideRush_ProjectRole", "AFK")
workspace:SetAttribute("GrandTideRush_ExpectedPlaceId", expectedAfkPlaceId)
workspace:SetAttribute("GrandTideRush_ProjectPlaceMismatch", placeInfo.PlaceRole ~= DataEnvironment.PlaceRoles.AFK)

if placeInfo.Environment == "Unknown" then
	error(string.format(
		"[AFKBoot] Place %s is not mapped to a data environment; AFK boot cannot choose a fallback datastore.",
		tostring(game.PlaceId)
	), 0)
end

if placeInfo.PlaceRole ~= DataEnvironment.PlaceRoles.AFK then
	warn(
		string.format(
			"[AFKBoot] AFK project is running in %s/%s place %s, but expected AFK place %s. Boot stopped.",
			tostring(placeInfo.Environment),
			tostring(placeInfo.PlaceRole),
			tostring(game.PlaceId),
			tostring(expectedAfkPlaceId)
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
