local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local MapResolver = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("MapResolver"))

local BaseAreaService = {}

local ACTIVE_MAP_ATTRIBUTE = "ActiveMapName"
local BASE_AREA_PADDING = 24
local TOUCH_HEAL_DEBOUNCE_SECONDS = 0.75
local CHARACTER_SPAWN_HEAL_DELAY_SECONDS = 0.25

local BASE_AREA_NAMES = {
	"StartingArea",
	"Starting Area",
	"StartArea",
	"BaseArea",
	"Lobby",
}

local started = false
local verticalSliceService = nil
local warnedVerticalSliceUnavailable = false
local warnedMissingTouchParts = false
local touchConnections = {}
local playerConnections = {}
local lastHealAttemptByPlayer = {}

local function warnOnce(flagName, message)
	if flagName == "verticalSliceUnavailable" then
		if warnedVerticalSliceUnavailable then
			return
		end
		warnedVerticalSliceUnavailable = true
	elseif flagName == "missingTouchParts" then
		if warnedMissingTouchParts then
			return
		end
		warnedMissingTouchParts = true
	end

	warn(message)
end

local function findBaseArea()
	local refs = MapResolver.GetRefs({ context = "BaseAreaService" })
	if refs.StartingArea and (refs.StartingArea:IsA("BasePart") or refs.StartingArea:IsA("Model")) then
		return refs.StartingArea
	end
	if refs.HitBox and refs.HitBox:IsA("BasePart") then
		return refs.HitBox
	end

	for _, name in ipairs(BASE_AREA_NAMES) do
		local found = Workspace:FindFirstChild(name, true)
		if found and (found:IsA("BasePart") or found:IsA("Model")) then
			return found
		end
	end
	return nil
end

local function getVerticalSliceService()
	if verticalSliceService ~= nil then
		return verticalSliceService
	end

	local modules = ServerScriptService:FindFirstChild("Modules")
	local module = modules and modules:FindFirstChild("GrandLineRushVerticalSliceService")
	if module == nil then
		warnOnce(
			"verticalSliceUnavailable",
			"[BaseAreaService] GrandLineRushVerticalSliceService is unavailable; skipping base-area healing."
		)
		return nil
	end

	local ok, service = pcall(require, module)
	if not ok then
		warnOnce(
			"verticalSliceUnavailable",
			string.format(
				"[BaseAreaService] Failed to require GrandLineRushVerticalSliceService; skipping base-area healing. Error: %s",
				tostring(service)
			)
		)
		return nil
	end

	verticalSliceService = service
	return verticalSliceService
end

local function isPlayerInActiveRun(player)
	local service = getVerticalSliceService()
	if typeof(service) ~= "table" or typeof(service.GetState) ~= "function" then
		warnOnce(
			"verticalSliceUnavailable",
			"[BaseAreaService] GrandLineRushVerticalSliceService.GetState is unavailable; skipping base-area healing."
		)
		return true
	end

	local ok, state = pcall(service.GetState, player)
	if not ok then
		warnOnce(
			"verticalSliceUnavailable",
			string.format(
				"[BaseAreaService] Failed to read vertical slice run state; skipping base-area healing. Error: %s",
				tostring(state)
			)
		)
		return true
	end

	local run = state and state.Run
	return typeof(run) == "table" and run.InRun == true
end

local function isPointInsidePart(part, position, padding)
	local relative = part.CFrame:PointToObjectSpace(position)
	local halfSize = (part.Size * 0.5) + Vector3.new(padding, padding, padding)
	return math.abs(relative.X) <= halfSize.X
		and math.abs(relative.Y) <= halfSize.Y
		and math.abs(relative.Z) <= halfSize.Z
end

local function isPointInsideModel(model, position, padding)
	local cframe, size = model:GetBoundingBox()
	local relative = cframe:PointToObjectSpace(position)
	local halfSize = (size * 0.5) + Vector3.new(padding, padding, padding)
	return math.abs(relative.X) <= halfSize.X
		and math.abs(relative.Y) <= halfSize.Y
		and math.abs(relative.Z) <= halfSize.Z
end

local function collectBaseTouchParts()
	local refs = MapResolver.GetRefs({ context = "BaseAreaService" })
	local parts = {}
	local seen = {}

	local function addPart(part)
		if not part or not part:IsA("BasePart") or seen[part] then
			return
		end

		seen[part] = true
		parts[#parts + 1] = part
	end

	addPart(refs.HitBox)

	if #parts == 0 then
		local startingArea = refs.StartingArea
		if startingArea and startingArea:IsA("BasePart") then
			addPart(startingArea)
		elseif startingArea and startingArea:IsA("Model") then
			for _, descendant in ipairs(startingArea:GetDescendants()) do
				addPart(descendant)
			end
		end
	end

	if #parts == 0 then
		local area = findBaseArea()
		if area and area:IsA("BasePart") then
			addPart(area)
		elseif area and area:IsA("Model") and area.Name ~= "Lobby" then
			for _, descendant in ipairs(area:GetDescendants()) do
				addPart(descendant)
			end
		end
	end

	return parts
end

local function getPlayerFromHit(hit)
	if typeof(hit) ~= "Instance" then
		return nil
	end

	local model = hit:FindFirstAncestorOfClass("Model")
	if model == nil then
		return nil
	end

	return Players:GetPlayerFromCharacter(model)
end

local function clearTouchConnections()
	for _, connection in ipairs(touchConnections) do
		connection:Disconnect()
	end
	table.clear(touchConnections)
end

local function bindBaseTouchParts()
	clearTouchConnections()

	local parts = collectBaseTouchParts()
	if #parts == 0 then
		warnOnce("missingTouchParts", "[BaseAreaService] No starting/base area touch parts found for health restore.")
		return
	end

	for _, part in ipairs(parts) do
		touchConnections[#touchConnections + 1] = part.Touched:Connect(function(hit)
			local player = getPlayerFromHit(hit)
			if player then
				BaseAreaService.HealPlayerInStartingArea(player, "base_area_touch")
			end
		end)
	end
end

local function bindPlayer(player)
	if playerConnections[player] then
		return
	end

	playerConnections[player] = player.CharacterAdded:Connect(function()
		task.delay(CHARACTER_SPAWN_HEAL_DELAY_SECONDS, function()
			if player.Parent == Players and BaseAreaService.IsPlayerInBaseArea(player) then
				BaseAreaService.HealPlayerInStartingArea(player, "character_spawn")
			end
		end)
	end)

	task.defer(function()
		if player.Parent == Players and BaseAreaService.IsPlayerInBaseArea(player) then
			BaseAreaService.HealPlayerInStartingArea(player, "player_added")
		end
	end)
end

function BaseAreaService.IsPlayerInBaseArea(player)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return false
	end

	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return false
	end

	local area = findBaseArea()
	if area == nil then
		return false
	end

	if area:IsA("BasePart") then
		return isPointInsidePart(area, root.Position, BASE_AREA_PADDING)
	elseif area:IsA("Model") then
		return isPointInsideModel(area, root.Position, BASE_AREA_PADDING)
	end
	return false
end

function BaseAreaService.HealPlayerInStartingArea(player, _reason)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return false
	end

	local now = os.clock()
	local lastAttempt = lastHealAttemptByPlayer[player]
	if lastAttempt and now - lastAttempt < TOUCH_HEAL_DEBOUNCE_SECONDS then
		return false
	end
	lastHealAttemptByPlayer[player] = now

	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid == nil or humanoid.Health <= 0 then
		return false
	end
	if humanoid.Health >= humanoid.MaxHealth then
		return false
	end
	if not BaseAreaService.IsPlayerInBaseArea(player) then
		return false
	end
	if isPlayerInActiveRun(player) then
		return false
	end

	humanoid.Health = humanoid.MaxHealth
	return true
end

function BaseAreaService.Start()
	if started then
		return
	end
	started = true

	bindBaseTouchParts()
	Workspace:GetAttributeChangedSignal(ACTIVE_MAP_ATTRIBUTE):Connect(bindBaseTouchParts)

	for _, player in ipairs(Players:GetPlayers()) do
		bindPlayer(player)
	end

	Players.PlayerAdded:Connect(bindPlayer)
	Players.PlayerRemoving:Connect(function(player)
		local connection = playerConnections[player]
		if connection then
			connection:Disconnect()
			playerConnections[player] = nil
		end
		lastHealAttemptByPlayer[player] = nil
	end)
end

return BaseAreaService
