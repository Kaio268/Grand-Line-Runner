local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local Configs = Modules:WaitForChild("Configs")

local CaptainSlotRuntime = require(ServerScriptService.Modules:WaitForChild("CaptainSlotRuntime"))
local CrewFoodProgression = require(ServerScriptService.Modules:WaitForChild("CrewFoodProgression"))
local CrewStandIncomeAuthority = require(ServerScriptService.Modules:WaitForChild("CrewStandIncomeAuthority"))
local ShipRuntimeService = require(ServerScriptService.Modules:WaitForChild("ShipRuntimeService"))
local ShipSlotService = require(ServerScriptService.Modules:WaitForChild("ShipSlotService"))
local ShipVisuals = require(Configs:WaitForChild("ShipVisuals"))

local TutorialTargetResolvers = {}

local RUNTIME_POINTS = ShipVisuals.RuntimePoints or {}
local RUNTIME_POINTS_FOLDER_NAME = tostring(RUNTIME_POINTS.FolderName or "ShipRuntimePoints")
local UPGRADE_POINT_CONFIG = RUNTIME_POINTS.Upgrade or {}

local function getInstancePosition(instance)
	if typeof(instance) ~= "Instance" then
		return nil
	end

	if instance:IsA("BasePart") then
		return instance.Position
	end
	if instance:IsA("Attachment") then
		return instance.WorldPosition
	end
	if instance:IsA("Model") then
		local ok, cframe = pcall(instance.GetBoundingBox, instance)
		if ok and typeof(cframe) == "CFrame" then
			return cframe.Position
		end
	end
	if instance:IsA("SurfaceGui") then
		local adornee = instance.Adornee
		if adornee then
			return getInstancePosition(adornee)
		end
		return getInstancePosition(instance.Parent)
	end

	return nil
end

local function getGuideBasePart(instance)
	if typeof(instance) ~= "Instance" or instance.Parent == nil then
		return nil
	end

	if instance:IsA("BasePart") then
		return instance
	end
	if instance:IsA("Attachment") then
		local parent = instance.Parent
		return if parent and parent:IsA("BasePart") then parent else nil
	end
	if instance:IsA("Model") then
		local primaryPart = instance.PrimaryPart
		if primaryPart and primaryPart:IsA("BasePart") then
			return primaryPart
		end

		for _, childName in ipairs({ "LevelUp", "HumanoidRootPart", "RootPart", "Handle" }) do
			local part = instance:FindFirstChild(childName, true)
			if part and part:IsA("BasePart") then
				return part
			end
		end

		return instance:FindFirstChildWhichIsA("BasePart", true)
	end

	return instance:FindFirstChildWhichIsA("BasePart", true)
end

local function getGuideBottomSurfaceOffset(part, clearance)
	if typeof(part) ~= "Instance" or not part:IsA("BasePart") then
		return Vector3.new(0, -0.35, 0)
	end

	return Vector3.new(0, -part.Size.Y * 0.5 + (tonumber(clearance) or 0.05), 0)
end

local function getRootPosition(player)
	local character = player and player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root.Position
	end

	return nil
end

local function getActiveShip(player)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return nil
	end

	local ok, activeShip = pcall(ShipRuntimeService.GetActiveShip, player)
	if ok and typeof(activeShip) == "Instance" and activeShip.Parent ~= nil then
		return activeShip
	end

	return nil
end

local function getLevelUpPart(slotModel)
	local part = slotModel and slotModel:FindFirstChild("LevelUp", true)
	return if part and part:IsA("BasePart") then part else nil
end

local function getCrewTotalFoodCount(player)
	if typeof(CrewFoodProgression.TryGetTotalFoodCount) == "function" then
		local ok, count = pcall(CrewFoodProgression.TryGetTotalFoodCount, player)
		if ok and count ~= nil then
			return math.max(0, tonumber(count) or 0)
		end
	end

	local ok, count = pcall(CrewFoodProgression.GetTotalFoodCount, player)
	if ok and count ~= nil then
		return math.max(0, tonumber(count) or 0)
	end

	return nil
end

local function getProgress(player, progressTarget)
	progressTarget = tostring(progressTarget or "")
	if progressTarget == "" then
		return nil
	end

	local ok, progress = pcall(CrewFoodProgression.GetProgress, player, progressTarget)
	return if ok and typeof(progress) == "table" then progress else nil
end

local function buildCrewFeedCandidate(player, rootPosition, candidates, slotKey, slotModel, assignment)
	if typeof(slotModel) ~= "Instance" then
		return
	end
	if typeof(assignment) ~= "table" then
		return
	end

	local instanceId = tostring(assignment.CrewMemberInstanceId or assignment.InstanceId or assignment.CrewInstanceId or "")
	local crewName = tostring(assignment.CrewMemberName or assignment.CrewMemberId or assignment.StorageName or assignment.Name or "")
	if instanceId == "" and crewName == "" then
		return
	end

	local levelUpPart = getLevelUpPart(slotModel)
	local position = getInstancePosition(levelUpPart)
	if not position then
		return
	end

	local progressTarget = if instanceId ~= "" then instanceId else crewName
	local progress = getProgress(player, progressTarget)
	if not progress then
		return
	end
	if (tonumber(progress.Level) or 1) >= (tonumber(progress.MaxLevel) or 1) then
		return
	end

	local distance = math.huge
	if rootPosition then
		distance = (position - rootPosition).Magnitude
	end

	candidates[#candidates + 1] = {
		Distance = distance,
		SlotOrder = tonumber(slotKey) or math.huge,
		Target = {
			id = "crew_feed_panel_" .. tostring(slotKey or ""),
			kind = "crew_feed_panel",
			label = "Feed Crewmate",
			position = position,
			slotKey = tostring(slotKey or ""),
			crewMemberInstanceId = instanceId,
			guidePart = levelUpPart,
			guideOffset = getGuideBottomSurfaceOffset(levelUpPart, 0.05),
		},
	}
end

local function getVector3(value, fallback)
	return if typeof(value) == "Vector3" then value else fallback
end

local function getFlatLookVector(sourceCFrame)
	local lookVector = sourceCFrame.LookVector
	local flatLook = Vector3.new(lookVector.X, 0, lookVector.Z)
	if flatLook.Magnitude > 0.001 then
		return flatLook.Unit
	end

	local rightVector = sourceCFrame.RightVector
	local flatRight = Vector3.new(rightVector.X, 0, rightVector.Z)
	if flatRight.Magnitude > 0.001 then
		local unit = flatRight.Unit
		return Vector3.new(unit.Z, 0, -unit.X).Unit
	end

	return Vector3.new(0, 0, -1)
end

local function getShipFacingPositionAt(activeShip, position)
	local shipPivot = activeShip and activeShip:GetPivot()
	local flatLook = shipPivot and getFlatLookVector(shipPivot) or Vector3.new(0, 0, -1)
	local yawOffset = math.rad(tonumber(UPGRADE_POINT_CONFIG.PromptYawOffsetDegrees) or 0)
	local promptWorldOffset = getVector3(UPGRADE_POINT_CONFIG.PromptWorldOffset, Vector3.new())
	local promptLocalOffset = getVector3(UPGRADE_POINT_CONFIG.PromptLocalOffset, Vector3.new())
	local facing = CFrame.lookAt(position, position + flatLook, Vector3.yAxis) * CFrame.Angles(0, yawOffset, 0)
	return facing.Position + promptWorldOffset + facing:VectorToWorldSpace(promptLocalOffset)
end

local function isRuntimePointDescendant(activeShip, instance)
	local folder = activeShip and activeShip:FindFirstChild(RUNTIME_POINTS_FOLDER_NAME)
	return folder ~= nil and typeof(instance) == "Instance" and instance:IsDescendantOf(folder)
end

local function findUpgradeMarker(activeShip)
	for _, markerName in ipairs(UPGRADE_POINT_CONFIG.MarkerNames or { "ShipUpgradePoint" }) do
		markerName = tostring(markerName)
		local direct = activeShip and activeShip:FindFirstChild(markerName, true)
		if direct and not isRuntimePointDescendant(activeShip, direct) and getInstancePosition(direct) then
			return direct
		end
	end

	return nil
end

local function getUpgradeFallbackPosition(activeShip)
	if typeof(activeShip) ~= "Instance" or not activeShip:IsA("Model") then
		return nil
	end

	local fallback = UPGRADE_POINT_CONFIG.Fallback
	if typeof(fallback) ~= "table" then
		return getInstancePosition(activeShip)
	end

	local boxCFrame, boxSize = activeShip:GetBoundingBox()
	local positionScale = getVector3(fallback.PositionScale, Vector3.new(0.6, 0.2, 0))
	local localOffset = getVector3(fallback.LocalOffset, Vector3.new())
	local worldOffset = getVector3(fallback.WorldOffset, Vector3.new())
	local scaledOffset = Vector3.new(
		boxSize.X * positionScale.X,
		boxSize.Y * positionScale.Y,
		boxSize.Z * positionScale.Z
	)

	return boxCFrame:PointToWorldSpace(scaledOffset + localOffset) + worldOffset
end

TutorialTargetResolvers.Resolvers = {
	ActiveShip = function(player, context)
		local activeShip = getActiveShip(player)
		local position = getInstancePosition(activeShip)
		if not position then
			return nil
		end

		local session = context and context.session
		return {
			position = position + Vector3.new(0, 8, 0),
			label = tostring((session and session.context and session.context.TargetLabel) or "Your ship"),
		}
	end,

	CrewFeedPanel = function(player, _context)
		local activeShip = getActiveShip(player)
		if not activeShip then
			return nil
		end

		local totalFoodCount = getCrewTotalFoodCount(player)
		if totalFoodCount == nil or totalFoodCount <= 0 then
			return nil
		end

		local rootPosition = getRootPosition(player)
		local candidates = {}
		for _, slotKey in ipairs(ShipSlotService.GetAvailableSlotNumbers(activeShip)) do
			local standData = CrewStandIncomeAuthority.GetStandData(player, slotKey)
			buildCrewFeedCandidate(player, rootPosition, candidates, slotKey, ShipSlotService.GetSlot(activeShip, slotKey), standData)
		end

		local captainAssignment = CaptainSlotRuntime.GetAssignment(player)
		buildCrewFeedCandidate(
			player,
			rootPosition,
			candidates,
			ShipSlotService.CaptainSlotKey or "Captain",
			ShipSlotService.GetCaptainSlot(activeShip),
			captainAssignment
		)

		table.sort(candidates, function(left, right)
			if math.abs(left.Distance - right.Distance) > 0.05 then
				return left.Distance < right.Distance
			end

			if left.SlotOrder ~= right.SlotOrder then
				return left.SlotOrder < right.SlotOrder
			end

			return tostring(left.Target.id) < tostring(right.Target.id)
		end)

		return candidates[1] and candidates[1].Target or nil
	end,

	ShipUpgradePanel = function(player, _context)
		local activeShip = getActiveShip(player)
		if not activeShip then
			return nil
		end

		local marker = findUpgradeMarker(activeShip)
		local basePosition = getInstancePosition(marker) or getUpgradeFallbackPosition(activeShip)
		if not basePosition then
			return nil
		end
		local guidePart = getGuideBasePart(marker)

		return {
			id = "ship_upgrade_panel",
			kind = "ship_upgrade_panel",
			label = "Ship Upgrade",
			position = getShipFacingPositionAt(activeShip, basePosition),
			guidePart = guidePart,
			guideOffset = getGuideBottomSurfaceOffset(guidePart, 0.05),
		}
	end,
}

function TutorialTargetResolvers.Resolve(resolverKey, player, context)
	resolverKey = tostring(resolverKey or "")
	local resolver = TutorialTargetResolvers.Resolvers[resolverKey]
	if typeof(resolver) ~= "function" then
		return nil
	end

	return resolver(player, context or {})
end

return TutorialTargetResolvers
