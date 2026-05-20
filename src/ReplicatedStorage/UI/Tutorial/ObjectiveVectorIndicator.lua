local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local React = require(Packages:WaitForChild("React"))

local Theme = require(script.Parent.Parent:WaitForChild("Index"):WaitForChild("Theme"))

local e = React.createElement

local LOCAL_PLAYER = Players.LocalPlayer

local LEGACY_WORLD_FOLDER_NAME = "FirstTimeTutorialVectorIndicator"
local ARROW_IMAGE_ASSET = "rbxassetid://136351759076111"

local EDGE_PADDING = 58
local TOP_PADDING = 86
local BOTTOM_PADDING = 220
local START_BOTTOM_OFFSET = 76
local START_STANDOFF = 50
local START_WORLD_STANDOFF = 0.5
local OBJECTIVE_WORLD_STANDOFF = 1.5
local OBJECTIVE_SCREEN_GAP = 24
local MIN_PATH_LENGTH = 96
local FIXED_SCREEN_PATH_LENGTH = 320
local MIN_CHEVRON_SIZE = 52
local MAX_CHEVRON_SIZE = 84
local CHEVRON_SCALE_REFERENCE = 720
local MIN_CHEVRON_SCREEN_SCALE = 0.72
local CHEVRON_GLOW_PADDING_RATIO = 0.24
local FIXED_CHEVRON_COUNT = 6
local SMOOTHING_SPEED = 14
local FINAL_POINT_SMOOTHING_MULTIPLIER = 1.35
local SNAP_DISTANCE = 180
local SNAP_ROTATION_DELTA = 110
local MIN_VISIBLE_DISTANCE = 14

local COLORS = {
	Gold = Theme.Palette.Gold,
	GoldSoft = Theme.Palette.GoldSoft,
	GoldShadow = Theme.Palette.GoldShadow,
}

local function getTargetPosition(target)
	if typeof(target) ~= "table" then
		return nil
	end

	local position = target.position
	if typeof(position) == "Vector3" then
		return position
	end
	if typeof(position) == "table" then
		local x = tonumber(position.x or position.X)
		local y = tonumber(position.y or position.Y)
		local z = tonumber(position.z or position.Z)
		if x and y and z then
			return Vector3.new(x, y, z)
		end
	end

	return nil
end

local function getRootPart()
	local character = LOCAL_PLAYER and LOCAL_PLAYER.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	if rootPart and rootPart:IsA("BasePart") then
		return rootPart
	end

	return nil
end

local function cleanupLegacyWorldResources()
	for _, child in ipairs(Workspace:GetChildren()) do
		if child.Name == LEGACY_WORLD_FOLDER_NAME then
			child:Destroy()
		end
	end
end

local function getSafeBounds(viewport)
	local left = EDGE_PADDING
	local right = math.max(left + 1, viewport.X - EDGE_PADDING)
	local top = TOP_PADDING
	local bottom = math.max(top + 1, viewport.Y - BOTTOM_PADDING)

	if bottom - top < MIN_PATH_LENGTH then
		top = math.max(24, math.min(TOP_PADDING, viewport.Y * 0.16))
		bottom = math.max(top + 1, viewport.Y - math.max(72, viewport.Y * 0.22))
	end

	if right - left < MIN_PATH_LENGTH then
		left = math.max(18, viewport.X * 0.08)
		right = math.max(left + 1, viewport.X - left)
	end

	return {
		left = left,
		right = right,
		top = top,
		bottom = bottom,
	}
end

local function getChevronScale(viewport)
	local smallestAxis = math.min(viewport.X, viewport.Y)
	if smallestAxis <= 0 then
		return 1
	end

	return math.clamp(smallestAxis / CHEVRON_SCALE_REFERENCE, MIN_CHEVRON_SCREEN_SCALE, 1)
end

local function getChevronSizeRange(viewport)
	local scale = getChevronScale(viewport)
	return math.floor(MIN_CHEVRON_SIZE * scale + 0.5), math.floor(MAX_CHEVRON_SIZE * scale + 0.5)
end

local function getFixedPathLength(viewport)
	return math.floor(FIXED_SCREEN_PATH_LENGTH * getChevronScale(viewport) + 0.5)
end

local function clampToBounds(point, bounds)
	return Vector2.new(
		math.clamp(point.X, bounds.left, bounds.right),
		math.clamp(point.Y, bounds.top, bounds.bottom)
	)
end

local function isInsideBounds(point, bounds)
	return point.X >= bounds.left and point.X <= bounds.right and point.Y >= bounds.top and point.Y <= bounds.bottom
end

local function isInsideViewport(point, viewport)
	return point.X >= 0 and point.X <= viewport.X and point.Y >= 0 and point.Y <= viewport.Y
end

local function getFallbackStartPoint(viewport, bounds)
	local bottomStart = bounds.bottom - START_BOTTOM_OFFSET
	local y = math.clamp(bottomStart, bounds.top, bounds.bottom)
	return Vector2.new((bounds.left + bounds.right) * 0.5, y)
end

local function getStartPoint(camera, viewport, bounds)
	local rootPart = getRootPart()
	if rootPart then
		local screenPosition = camera:WorldToViewportPoint(rootPart.Position + Vector3.new(0, 2, 0))
		local projected = Vector2.new(screenPosition.X, screenPosition.Y)
		if screenPosition.Z > 0 and isInsideViewport(projected, viewport) then
			return clampToBounds(projected, bounds)
		end
	end

	return getFallbackStartPoint(viewport, bounds)
end

local function getRayDistanceToBounds(origin, direction, bounds)
	local distances = {}

	if direction.X > 0.001 then
		distances[#distances + 1] = (bounds.right - origin.X) / direction.X
	elseif direction.X < -0.001 then
		distances[#distances + 1] = (bounds.left - origin.X) / direction.X
	end

	if direction.Y > 0.001 then
		distances[#distances + 1] = (bounds.bottom - origin.Y) / direction.Y
	elseif direction.Y < -0.001 then
		distances[#distances + 1] = (bounds.top - origin.Y) / direction.Y
	end

	local bestDistance = math.huge
	for _, distance in ipairs(distances) do
		if distance > 0 and distance < bestDistance then
			bestDistance = distance
		end
	end

	if bestDistance == math.huge then
		return 0
	end

	return math.max(0, bestDistance)
end

local function getProjectedOffset(point, direction)
	return point.X * direction.X + point.Y * direction.Y
end

local function lerpNumber(startValue, endValue, alpha)
	return startValue + (endValue - startValue) * alpha
end

local function lerpVector2(startValue, endValue, alpha)
	return startValue + (endValue - startValue) * alpha
end

local function roundVector2(value)
	return Vector2.new(math.floor(value.X + 0.5), math.floor(value.Y + 0.5))
end

local function getShortestAngleDelta(fromDegrees, toDegrees)
	return ((toDegrees - fromDegrees + 180) % 360) - 180
end

local function lerpAngle(fromDegrees, toDegrees, alpha)
	return fromDegrees + getShortestAngleDelta(fromDegrees, toDegrees) * alpha
end

local function getTargetKey(target)
	if typeof(target) ~= "table" then
		return ""
	end

	return table.concat({
		tostring(target.id or ""),
		tostring(target.kind or ""),
		tostring(target.label or ""),
	}, "|")
end

local function getPathFirstPoint(path)
	if typeof(path) ~= "table" then
		return nil
	end
	if typeof(path.firstPoint) == "Vector2" then
		return path.firstPoint
	end
	if typeof(path.chevrons) == "table" then
		local chevron = path.chevrons[1]
		return chevron and chevron.position or nil
	end

	return nil
end

local function getPathFinalPoint(path)
	if typeof(path) ~= "table" then
		return nil
	end
	if typeof(path.finalPoint) == "Vector2" then
		return path.finalPoint
	end
	if typeof(path.chevrons) == "table" then
		local chevron = path.chevrons[#path.chevrons]
		return chevron and chevron.position or nil
	end

	return nil
end

local function getPathRotation(path)
	if typeof(path) ~= "table" then
		return nil
	end
	if typeof(path.rotation) == "number" then
		return path.rotation
	end
	if typeof(path.chevrons) == "table" then
		local chevron = path.chevrons[#path.chevrons]
		return chevron and chevron.rotation or nil
	end

	return nil
end

local function projectWorldPoint(camera, viewport, worldPoint)
	local screenPosition = camera:WorldToViewportPoint(worldPoint)
	local point = Vector2.new(screenPosition.X, screenPosition.Y)
	if screenPosition.Z <= 0 or not isInsideViewport(point, viewport) then
		return nil
	end

	return point
end

local function buildWorldLinePath(camera, viewport, bounds, rootPart, targetPosition, targetKey)
	if not rootPart then
		return nil
	end

	local targetVector = targetPosition - rootPart.Position
	local targetDistance = targetVector.Magnitude
	if targetDistance <= START_WORLD_STANDOFF + OBJECTIVE_WORLD_STANDOFF + 0.1 then
		return nil
	end

	local worldDirection = targetVector.Unit
	local worldStart = rootPart.Position + worldDirection * START_WORLD_STANDOFF
	local worldEnd = targetPosition - worldDirection * OBJECTIVE_WORLD_STANDOFF
	local projectedPositions = {}

	for index = 1, FIXED_CHEVRON_COUNT do
		local alpha = index / FIXED_CHEVRON_COUNT
		local worldPoint = worldStart:Lerp(worldEnd, alpha)
		local projectedPoint = projectWorldPoint(camera, viewport, worldPoint)
		if not projectedPoint or not isInsideBounds(projectedPoint, bounds) then
			return nil
		end

		projectedPositions[index] = projectedPoint
	end

	local chevrons = {}
	local fallbackDirection
	local firstPoint = projectedPositions[1]
	local finalPoint = projectedPositions[#projectedPositions]
	if firstPoint and finalPoint and (finalPoint - firstPoint).Magnitude > 0.001 then
		fallbackDirection = (finalPoint - firstPoint).Unit
	else
		fallbackDirection = Vector2.new(0, -1)
	end

	for index, position in ipairs(projectedPositions) do
		local direction
		if index < #projectedPositions then
			local nextPoint = projectedPositions[index + 1]
			if nextPoint and (nextPoint - position).Magnitude > 0.001 then
				direction = (nextPoint - position).Unit
			end
		elseif index > 1 then
			local previousPoint = projectedPositions[index - 1]
			if previousPoint and (position - previousPoint).Magnitude > 0.001 then
				direction = (position - previousPoint).Unit
			end
		end

		direction = direction or fallbackDirection
		chevrons[index] = {
			position = position,
			rotation = math.deg(math.atan2(direction.Y, direction.X)) - 90,
		}
	end

	return {
		chevrons = chevrons,
		targetKey = targetKey,
		viewport = viewport,
		visibilityState = "world",
	}
end

local function buildAnchoredPath(startPoint, finalPoint, direction, bounds, viewport, maxChevronSize, targetKey, visibilityState)
	finalPoint = clampToBounds(finalPoint, bounds)

	local pathVector = finalPoint - startPoint
	local finalDirection = direction
	if pathVector.Magnitude > 0.001 then
		finalDirection = pathVector.Unit
	elseif finalDirection.Magnitude < 0.001 then
		finalDirection = Vector2.new(0, -1)
	else
		finalDirection = finalDirection.Unit
	end

	local fixedPathLength = getFixedPathLength(viewport)
	local maxBackwardLength = math.max(
		0,
		getRayDistanceToBounds(finalPoint, -finalDirection, bounds) - (maxChevronSize * 0.5)
	)
	local pathLength = math.min(fixedPathLength, maxBackwardLength)
	if pathLength <= MIN_VISIBLE_DISTANCE then
		return nil
	end

	local firstPoint = finalPoint - finalDirection * pathLength
	local startToFinalDistance = pathVector.Magnitude
	if startToFinalDistance > MIN_VISIBLE_DISTANCE then
		local minimumStartOffset = math.min(START_STANDOFF, startToFinalDistance * 0.45)
		local firstOffset = getProjectedOffset(firstPoint - startPoint, finalDirection)
		if firstOffset < minimumStartOffset then
			firstPoint = startPoint + finalDirection * minimumStartOffset
		end
	end

	local finalPathVector = finalPoint - firstPoint
	local finalPathLength = finalPathVector.Magnitude
	if finalPathLength <= MIN_VISIBLE_DISTANCE then
		return nil
	end

	finalDirection = finalPathVector.Unit
	local rotation = math.deg(math.atan2(finalDirection.Y, finalDirection.X)) - 90

	return {
		finalPoint = finalPoint,
		firstPoint = firstPoint,
		rotation = rotation,
		targetKey = targetKey,
		viewport = viewport,
		visibilityState = visibilityState,
	}
end

local function buildRawPath(target)
	local camera = Workspace.CurrentCamera
	local targetPosition = getTargetPosition(target)
	if not camera or not targetPosition then
		return nil
	end

	local viewport = camera.ViewportSize
	if viewport.X <= 0 or viewport.Y <= 0 then
		return nil
	end

	local bounds = getSafeBounds(viewport)
	local startPoint = getStartPoint(camera, viewport, bounds)
	local screenPosition, visible = camera:WorldToViewportPoint(targetPosition)
	local rawTargetPoint = Vector2.new(screenPosition.X, screenPosition.Y)
	local inFront = screenPosition.Z > 0
	local targetOnScreen = visible and inFront and isInsideViewport(rawTargetPoint, viewport)
	local visibilityState = if targetOnScreen then "onscreen" elseif inFront then "offscreen" else "behind"

	local direction = rawTargetPoint - startPoint
	if not inFront then
		direction = -direction
	end
	if direction.Magnitude < 0.001 then
		direction = Vector2.new(0, -1)
	else
		direction = direction.Unit
	end

	local _, maxChevronSize = getChevronSizeRange(viewport)
	local maxLengthInBounds = math.max(0, getRayDistanceToBounds(startPoint, direction, bounds) - (maxChevronSize * 0.5))
	if maxLengthInBounds <= MIN_VISIBLE_DISTANCE then
		return nil
	end

	local targetKey = getTargetKey(target)
	local rootPart = getRootPart()
	if targetOnScreen then
		local worldLinePath = buildWorldLinePath(camera, viewport, bounds, rootPart, targetPosition, targetKey)
		if worldLinePath then
			return worldLinePath
		end
	end

	local finalPoint
	if targetOnScreen then
		local objectiveScreenGap = math.max(OBJECTIVE_SCREEN_GAP, maxChevronSize * 0.35)
		local origin = if rootPart then rootPart.Position else camera.CFrame.Position
		local worldDirection = targetPosition - origin
		local finalWorld = targetPosition
		if worldDirection.Magnitude > 0.001 then
			finalWorld = targetPosition - worldDirection.Unit * OBJECTIVE_WORLD_STANDOFF
		end

		local finalScreenPosition = camera:WorldToViewportPoint(finalWorld)
		local projectedFinalPoint = Vector2.new(finalScreenPosition.X, finalScreenPosition.Y)
		if finalScreenPosition.Z > 0 and isInsideViewport(projectedFinalPoint, viewport) then
			finalPoint = projectedFinalPoint
		else
			finalPoint = rawTargetPoint - direction * objectiveScreenGap
		end

		local clampedFinalPoint = clampToBounds(finalPoint, bounds)
		local wasClamped = (clampedFinalPoint - finalPoint).Magnitude > 0.001
		finalPoint = clampedFinalPoint

		if wasClamped or (rawTargetPoint - finalPoint).Magnitude < objectiveScreenGap then
			finalPoint = rawTargetPoint - direction * objectiveScreenGap
			finalPoint = clampToBounds(finalPoint, bounds)
		end
	else
		local edgeLength = math.max(MIN_VISIBLE_DISTANCE, maxLengthInBounds)
		finalPoint = clampToBounds(startPoint + direction * edgeLength, bounds)
	end

	return buildAnchoredPath(
		startPoint,
		finalPoint,
		direction,
		bounds,
		viewport,
		maxChevronSize,
		targetKey,
		visibilityState
	)
end

local function shouldSnap(previousPath, rawPath)
	if not previousPath then
		return true
	end
	if previousPath.targetKey ~= rawPath.targetKey then
		return true
	end
	if previousPath.visibilityState ~= rawPath.visibilityState then
		return true
	end
	if previousPath.viewport ~= rawPath.viewport then
		return true
	end

	local previousFirstPoint = getPathFirstPoint(previousPath)
	local rawFirstPoint = getPathFirstPoint(rawPath)
	local previousFinalPoint = getPathFinalPoint(previousPath)
	local rawFinalPoint = getPathFinalPoint(rawPath)
	local previousRotation = getPathRotation(previousPath)
	local rawRotation = getPathRotation(rawPath)

	if not previousFirstPoint or not rawFirstPoint or not previousFinalPoint or not rawFinalPoint then
		return true
	end
	if (previousFirstPoint - rawFirstPoint).Magnitude > SNAP_DISTANCE then
		return true
	end
	if (previousFinalPoint - rawFinalPoint).Magnitude > SNAP_DISTANCE then
		return true
	end
	if not previousRotation or not rawRotation then
		return true
	end
	if math.abs(getShortestAngleDelta(previousRotation, rawRotation)) > SNAP_ROTATION_DELTA then
		return true
	end

	return false
end

local function buildChevrons(path)
	local chevrons = {}
	local minChevronSize, maxChevronSize = getChevronSizeRange(path.viewport)
	for index = 1, FIXED_CHEVRON_COUNT do
		local alpha = if FIXED_CHEVRON_COUNT == 1 then 1 else (index - 1) / (FIXED_CHEVRON_COUNT - 1)
		local pathChevron = if typeof(path.chevrons) == "table" then path.chevrons[index] else nil
		local position = if pathChevron
			then roundVector2(pathChevron.position)
			else roundVector2(lerpVector2(path.firstPoint, path.finalPoint, alpha))
		local size = math.floor(lerpNumber(minChevronSize, maxChevronSize, alpha) + 0.5)
		local transparency = lerpNumber(0.16, 0, alpha)
		local glowTransparency = lerpNumber(0.66, 0.4, alpha)
		local rotation = if pathChevron then pathChevron.rotation else path.rotation

		chevrons[index] = {
			position = position,
			size = size,
			transparency = transparency,
			glowTransparency = glowTransparency,
			rotation = math.floor(rotation + 0.5),
		}
	end

	return {
		chevrons = chevrons,
	}
end

local function smoothPath(previousPath, rawPath, deltaTime)
	if shouldSnap(previousPath, rawPath) then
		return rawPath
	end

	local alpha = 1 - math.exp(-(tonumber(deltaTime) or 0) * SMOOTHING_SPEED)
	alpha = math.clamp(alpha, 0, 1)
	local finalPointAlpha = math.clamp(alpha * FINAL_POINT_SMOOTHING_MULTIPLIER, 0, 1)

	if typeof(previousPath.chevrons) == "table" and typeof(rawPath.chevrons) == "table" then
		local chevrons = {}
		for index = 1, FIXED_CHEVRON_COUNT do
			local previousChevron = previousPath.chevrons[index]
			local rawChevron = rawPath.chevrons[index]
			if not previousChevron or not rawChevron then
				return rawPath
			end

			chevrons[index] = {
				position = lerpVector2(previousChevron.position, rawChevron.position, alpha),
				rotation = lerpAngle(previousChevron.rotation, rawChevron.rotation, alpha),
			}
		end

		return {
			chevrons = chevrons,
			targetKey = rawPath.targetKey,
			viewport = rawPath.viewport,
			visibilityState = rawPath.visibilityState,
		}
	end

	return {
		finalPoint = lerpVector2(previousPath.finalPoint, rawPath.finalPoint, finalPointAlpha),
		firstPoint = lerpVector2(previousPath.firstPoint, rawPath.firstPoint, alpha),
		rotation = lerpAngle(previousPath.rotation, rawPath.rotation, alpha),
		targetKey = rawPath.targetKey,
		viewport = rawPath.viewport,
		visibilityState = rawPath.visibilityState,
	}
end

local function ObjectiveVectorIndicator(props)
	local targetRef = React.useRef(props.target)
	local pathRef = React.useRef(nil)
	local layout, setLayout = React.useState(nil)
	targetRef.current = props.target

	React.useEffect(function()
		local alive = true
		cleanupLegacyWorldResources()

		local function update()
			if not alive then
				return
			end

			local rawPath = buildRawPath(targetRef.current)
			if not rawPath then
				pathRef.current = nil
				setLayout(nil)
				return
			end

			local smoothedPath = smoothPath(pathRef.current, rawPath, 1 / 60)
			pathRef.current = smoothedPath
			setLayout(buildChevrons(smoothedPath))
		end

		update()
		local connection = RunService.RenderStepped:Connect(function(deltaTime)
			if not alive then
				return
			end

			local rawPath = buildRawPath(targetRef.current)
			if not rawPath then
				pathRef.current = nil
				setLayout(nil)
				return
			end

			local smoothedPath = smoothPath(pathRef.current, rawPath, deltaTime)
			pathRef.current = smoothedPath
			setLayout(buildChevrons(smoothedPath))
		end)

		return function()
			alive = false
			pathRef.current = nil
			if connection then
				connection:Disconnect()
			end
			cleanupLegacyWorldResources()
		end
	end, {})

	if not layout then
		return nil
	end

	local zIndex = tonumber(props.zIndex) or 184

	return e("Frame", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		ZIndex = zIndex,
	}, (function()
		local children = {}
		for index, chevron in ipairs(layout.chevrons) do
			children["ChevronGlow" .. tostring(index)] = e("ImageLabel", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				Image = ARROW_IMAGE_ASSET,
				ImageColor3 = COLORS.GoldShadow,
				ImageTransparency = chevron.glowTransparency,
				Position = UDim2.fromOffset(chevron.position.X, chevron.position.Y),
				Rotation = chevron.rotation,
				ScaleType = Enum.ScaleType.Fit,
				Size = UDim2.fromOffset(
					chevron.size + math.floor(chevron.size * CHEVRON_GLOW_PADDING_RATIO + 0.5),
					chevron.size + math.floor(chevron.size * CHEVRON_GLOW_PADDING_RATIO + 0.5)
				),
				ZIndex = zIndex + 1,
			})
			children["Chevron" .. tostring(index)] = e("ImageLabel", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				Image = ARROW_IMAGE_ASSET,
				ImageColor3 = Color3.new(1, 1, 1),
				ImageTransparency = chevron.transparency,
				Position = UDim2.fromOffset(chevron.position.X, chevron.position.Y),
				Rotation = chevron.rotation,
				ScaleType = Enum.ScaleType.Fit,
				Size = UDim2.fromOffset(chevron.size, chevron.size),
				ZIndex = zIndex + 2,
			})
		end

		return children
	end)())
end

return ObjectiveVectorIndicator
