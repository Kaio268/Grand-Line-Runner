local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ServerModules = ServerScriptService:WaitForChild("Modules")
local CorridorRunController = require(ServerModules:WaitForChild("GrandLineRushCorridorRunController"))
local ChestRushService = require(ServerModules:WaitForChild("GrandLineRushChestRushService"))
local VerticalSliceService = require(ServerModules:WaitForChild("GrandLineRushVerticalSliceService"))
local CrewInteraction = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Server"):WaitForChild("Crew"):WaitForChild("Interaction"))

local CorridorRewardSnapshotService = {}

local DEFAULT_DETAIL_LIMIT = 80

local function readCount(value)
	return math.max(0, math.floor(tonumber(value) or 0))
end

local function safeSnapshot(label, callback)
	local ok, result = pcall(callback)
	if ok and typeof(result) == "table" then
		return result
	end

	warn(string.format("[CorridorRewardSnapshotService] %s snapshot failed: %s", tostring(label), tostring(result)))
	return {}
end

local function appendDetails(target, source, limit)
	if typeof(source) ~= "table" then
		return
	end

	for _, detail in ipairs(source) do
		if #target >= limit then
			return
		end
		if typeof(detail) == "table" then
			target[#target + 1] = detail
		end
	end
end

function CorridorRewardSnapshotService.BuildSnapshot(options)
	options = if typeof(options) == "table" then options else {}
	local detailLimit = math.max(0, math.floor(tonumber(options.DetailLimit) or DEFAULT_DETAIL_LIMIT))
	local sharedChestSnapshot = safeSnapshot("shared_chests", function()
		return CorridorRunController.GetSharedChestSnapshot({
			MaxDetails = detailLimit,
		})
	end)
	local physicalCrewSnapshot = safeSnapshot("physical_crew", function()
		return CrewInteraction.GetActiveCrewSnapshot({
			MaxDetails = detailLimit,
		})
	end)
	local runtimeSnapshot = safeSnapshot("runtime_rewards", function()
		return VerticalSliceService.GetCorridorRuntimeSnapshot({
			MaxDetails = detailLimit,
		})
	end)
	local chestRushState = safeSnapshot("chest_rush", function()
		return ChestRushService.GetStatus()
	end)

	local spawnedRuntime = if typeof(runtimeSnapshot.Spawned) == "table" then runtimeSnapshot.Spawned else {}
	local carriedRuntime = if typeof(runtimeSnapshot.Carried) == "table" then runtimeSnapshot.Carried else {}
	local activeChests = readCount(sharedChestSnapshot.WorldAvailableCount) + readCount(spawnedRuntime.Chests)
	local activeCrewmates = readCount(physicalCrewSnapshot.WorldAvailableCount) + readCount(spawnedRuntime.Crewmates)
	local droppedRewards = readCount(sharedChestSnapshot.Dropped) + readCount(physicalCrewSnapshot.Dropped)
	local carriedRewards = readCount(carriedRuntime.Total)
	local details = {}
	appendDetails(details, sharedChestSnapshot.Details, detailLimit)
	appendDetails(details, physicalCrewSnapshot.Details, detailLimit)
	appendDetails(details, runtimeSnapshot.Details, detailLimit)
	sharedChestSnapshot.Details = nil
	physicalCrewSnapshot.Details = nil
	runtimeSnapshot.Details = nil

	return {
		GeneratedAtUnix = os.time(),
		ServerTime = Workspace:GetServerTimeNow(),
		DetailLimit = detailLimit,
		Summary = {
			ActiveWorldRewards = activeChests + activeCrewmates,
			ActiveChests = activeChests,
			ActiveCrewmates = activeCrewmates,
			DroppedRewards = droppedRewards,
			CarriedRewards = carriedRewards,
			SharedChests = readCount(sharedChestSnapshot.WorldAvailableCount),
			PhysicalCrewmates = readCount(physicalCrewSnapshot.WorldAvailableCount),
			LegacySpawnedRewards = readCount(runtimeSnapshot.WorldAvailableCount),
		},
		Chests = sharedChestSnapshot,
		Crewmates = physicalCrewSnapshot,
		Runtime = runtimeSnapshot,
		ChestRush = chestRushState,
		Details = details,
	}
end

return CorridorRewardSnapshotService
