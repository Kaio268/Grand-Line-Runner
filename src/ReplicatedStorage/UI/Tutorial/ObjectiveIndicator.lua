local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local React = require(Packages:WaitForChild("React"))

local Responsive = require(script.Parent.Parent:WaitForChild("Responsive"))
local Theme = require(script.Parent.Parent:WaitForChild("Index"):WaitForChild("Theme"))

local e = React.createElement

local EDGE_PADDING = 54
local TOP_PADDING = 74
local BOTTOM_PADDING = 220
local MARKER_OFFSET = 42
local ARROW_IMAGE_ASSET = "rbxassetid://136351759076111"
local PATH_ARROW_SPACING_STUDS = 6
local PATH_MAX_ARROWS = 24
local PATH_MIN_DISTANCE_STUDS = 28
local PATH_START_CLEARANCE_STUDS = 0
local PATH_TARGET_CLEARANCE_STUDS = 0
local PATH_START_WORLD_Y_OFFSET = 0
local PATH_TARGET_WORLD_Y_OFFSET = 2.5
local PATH_ARROW_SIZE_DESKTOP = 36
local PATH_ARROW_SIZE_MOBILE = 42
local PATH_MIN_SCREEN_SPACING_PX = 8
local PATH_COLLAPSED_SCREEN_EXTENT_PX = 40
local PATH_FALLBACK_ARROW_COUNT = 8
local PATH_FALLBACK_START_Y_RATIO = 0.68
local PATH_FALLBACK_END_BLEND = 0.78

local COLORS = {
	Gold = Theme.Palette.Gold,
	GoldSoft = Theme.Palette.GoldSoft,
	GoldShadow = Theme.Palette.GoldShadow,
	Text = Theme.Palette.Text,
	Panel = Color3.fromRGB(14, 26, 38),
}

local function isMobileViewport()
	return Responsive.isMobile()
end

local function createFallbackArrow(rotation, size, zIndex, visible)
	return e("TextLabel", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Font = Theme.Fonts.Display,
		Position = UDim2.fromScale(0.5, 0.5),
		Rotation = rotation,
		Size = UDim2.fromOffset(size, size),
		Text = "\226\150\188",
		TextColor3 = COLORS.GoldSoft,
		TextSize = math.floor(size * 0.86),
		TextStrokeColor3 = COLORS.GoldShadow,
		TextStrokeTransparency = 0.12,
		Visible = visible,
		ZIndex = zIndex,
	})
end

local function createArrowPointer(rotation, size, zIndex, imageRef)
	return e("ImageLabel", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Image = ARROW_IMAGE_ASSET,
		ImageColor3 = Color3.new(1, 1, 1),
		ImageTransparency = 0,
		Position = UDim2.fromScale(0.5, 0.5),
		Rotation = rotation,
		ScaleType = Enum.ScaleType.Fit,
		Size = UDim2.fromOffset(size, size),
		ZIndex = zIndex,
		ref = imageRef,
	})
end

local function getOptionNumber(options, keys, fallback)
	if typeof(options) ~= "table" then
		return fallback
	end

	for _, key in ipairs(keys) do
		local value = tonumber(options[key])
		if value and value == value and value ~= math.huge and value ~= -math.huge then
			return value
		end
	end

	return fallback
end

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

local function getRootPosition()
	local player = Players.LocalPlayer
	local character = player and player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root.Position
	end

	return nil
end

local function clampToSafeScreen(point, viewport)
	local maxY = math.max(TOP_PADDING, viewport.Y - BOTTOM_PADDING)
	return Vector2.new(
		math.clamp(point.X, EDGE_PADDING, math.max(EDGE_PADDING, viewport.X - EDGE_PADDING)),
		math.clamp(point.Y, TOP_PADDING, maxY)
	)
end

local function projectWorldPosition(camera, viewport, worldPosition)
	local screenPosition, visible = camera:WorldToViewportPoint(worldPosition)
	local rawPoint = Vector2.new(screenPosition.X, screenPosition.Y)
	local inFront = screenPosition.Z > 0
	local withinBounds = rawPoint.X >= 0 and rawPoint.X <= viewport.X and rawPoint.Y >= 0 and rawPoint.Y <= viewport.Y

	return {
		inFront = inFront,
		onScreen = visible and inFront and withinBounds,
		position = rawPoint,
	}
end

local function projectPathPosition(camera, viewport, worldPosition)
	local projected = projectWorldPosition(camera, viewport, worldPosition)
	if projected.onScreen then
		return {
			onScreen = true,
			position = projected.position,
		}
	end

	local center = Vector2.new(viewport.X / 2, viewport.Y / 2)
	local direction = projected.position - center
	if projected.inFront ~= true then
		direction = -direction
	end
	if direction.Magnitude < 0.001 then
		direction = Vector2.new(0, -1)
	else
		direction = direction.Unit
	end

	return {
		onScreen = false,
		position = clampToSafeScreen(center + direction * 10000, viewport),
	}
end

local function projectTarget(target)
	local camera = Workspace.CurrentCamera
	local worldPosition = getTargetPosition(target)
	if not camera or not worldPosition then
		return nil
	end

	local viewport = camera.ViewportSize
	if viewport.X <= 0 or viewport.Y <= 0 then
		return nil
	end

	local screenPosition, visible = camera:WorldToViewportPoint(worldPosition)
	local center = Vector2.new(viewport.X / 2, viewport.Y / 2)
	local rawPoint = Vector2.new(screenPosition.X, screenPosition.Y)
	local inFront = screenPosition.Z > 0
	local withinBounds = rawPoint.X >= 0 and rawPoint.X <= viewport.X and rawPoint.Y >= 0 and rawPoint.Y <= viewport.Y
	local onScreen = visible and inFront and withinBounds

	if onScreen then
		local markerPoint = clampToSafeScreen(rawPoint - Vector2.new(0, MARKER_OFFSET), viewport)
		return {
			onScreen = true,
			position = markerPoint,
			rotation = 0,
		}
	end

	local direction = rawPoint - center
	if not inFront then
		direction = -direction
	end
	if direction.Magnitude < 0.001 then
		direction = Vector2.new(0, -1)
	else
		direction = direction.Unit
	end

	local edgePoint = clampToSafeScreen(center + direction * 10000, viewport)
	return {
		onScreen = false,
		position = edgePoint,
		rotation = math.deg(math.atan2(direction.Y, direction.X)) - 90,
	}
end

local function getPathOptions(options)
	return {
		spacingStuds = math.max(1, getOptionNumber(options, { "ArrowSpacingStuds", "SpacingStuds", "arrowSpacingStuds", "spacingStuds" }, PATH_ARROW_SPACING_STUDS)),
		maxArrows = math.max(0, math.floor(getOptionNumber(options, { "MaxArrows", "maxArrows" }, PATH_MAX_ARROWS))),
		minDistanceStuds = math.max(0, getOptionNumber(options, { "MinDistanceStuds", "minDistanceStuds" }, PATH_MIN_DISTANCE_STUDS)),
		startClearanceStuds = math.max(0, getOptionNumber(options, { "StartClearanceStuds", "startClearanceStuds" }, PATH_START_CLEARANCE_STUDS)),
		targetClearanceStuds = math.max(0, getOptionNumber(options, { "TargetClearanceStuds", "targetClearanceStuds" }, PATH_TARGET_CLEARANCE_STUDS)),
		startWorldYOffset = getOptionNumber(options, { "StartWorldYOffset", "startWorldYOffset" }, PATH_START_WORLD_Y_OFFSET),
		targetWorldYOffset = getOptionNumber(
			options,
			{ "TargetWorldYOffset", "targetWorldYOffset", "WorldYOffset", "worldYOffset" },
			PATH_TARGET_WORLD_Y_OFFSET
		),
	}
end

local function getScreenRotationToward(fromPoint, toPoint)
	local direction = toPoint - fromPoint
	if direction.Magnitude < 0.001 then
		return 0
	end

	direction = direction.Unit
	return math.deg(math.atan2(direction.Y, direction.X)) - 90
end

local function rotatePathArrows(arrows, fallbackTargetPoint)
	for index, arrow in ipairs(arrows) do
		local targetPoint = if index < #arrows then arrows[index + 1].position else nil
		local previousPoint = if index > 1 then arrows[index - 1].position else nil
		if targetPoint then
			arrow.rotation = getScreenRotationToward(arrow.position, targetPoint)
		elseif previousPoint then
			arrow.rotation = getScreenRotationToward(previousPoint, arrow.position)
		else
			arrow.rotation = getScreenRotationToward(arrow.position, fallbackTargetPoint)
		end
	end
end

local function getPathScreenExtent(arrows)
	if #arrows == 0 then
		return 0
	end

	local minX = math.huge
	local minY = math.huge
	local maxX = -math.huge
	local maxY = -math.huge
	for _, arrow in ipairs(arrows) do
		minX = math.min(minX, arrow.position.X)
		minY = math.min(minY, arrow.position.Y)
		maxX = math.max(maxX, arrow.position.X)
		maxY = math.max(maxY, arrow.position.Y)
	end

	return math.max(maxX - minX, maxY - minY)
end

local function buildFallbackPathArrows(viewport, targetProjection)
	local center = Vector2.new(viewport.X / 2, viewport.Y / 2)
	local startPoint = clampToSafeScreen(Vector2.new(center.X, viewport.Y * PATH_FALLBACK_START_Y_RATIO), viewport)
	local endPoint = clampToSafeScreen(startPoint + (targetProjection.position - startPoint) * PATH_FALLBACK_END_BLEND, viewport)

	if (endPoint - startPoint).Magnitude < PATH_COLLAPSED_SCREEN_EXTENT_PX then
		local direction = targetProjection.position - center
		if direction.Magnitude < 0.001 then
			direction = Vector2.new(0, -1)
		else
			direction = direction.Unit
		end
		endPoint = clampToSafeScreen(startPoint + direction * (PATH_COLLAPSED_SCREEN_EXTENT_PX * 2), viewport)
	end

	local arrows = {}
	for index = 1, PATH_FALLBACK_ARROW_COUNT do
		local alpha = if PATH_FALLBACK_ARROW_COUNT == 1 then 0 else (index - 1) / (PATH_FALLBACK_ARROW_COUNT - 1)
		local position = clampToSafeScreen(startPoint + (endPoint - startPoint) * alpha, viewport)
		arrows[#arrows + 1] = {
			position = position,
			rotation = 0,
		}
	end

	rotatePathArrows(arrows, targetProjection.position)
	return arrows
end

local function buildPathArrows(target, showPath, options)
	if showPath ~= true then
		return nil
	end

	local camera = Workspace.CurrentCamera
	local targetPosition = getTargetPosition(target)
	local rootPosition = getRootPosition()
	if not camera or not targetPosition or not rootPosition then
		return nil
	end

	local viewport = camera.ViewportSize
	if viewport.X <= 0 or viewport.Y <= 0 then
		return nil
	end

	local pathOptions = getPathOptions(options)
	if pathOptions.maxArrows <= 0 then
		return nil
	end

	local startPosition = rootPosition + Vector3.new(0, pathOptions.startWorldYOffset, 0)
	local endPosition = targetPosition + Vector3.new(0, pathOptions.targetWorldYOffset, 0)
	local delta = endPosition - startPosition
	local distance = delta.Magnitude
	if distance < pathOptions.minDistanceStuds then
		return nil
	end

	local targetProjection = projectPathPosition(camera, viewport, endPosition)
	if not targetProjection then
		return nil
	end

	local startDistance = math.min(pathOptions.startClearanceStuds, distance)
	local endDistance = math.max(startDistance, distance - pathOptions.targetClearanceStuds)
	local usableDistance = endDistance - startDistance
	if usableDistance <= 0 then
		return nil
	end

	local direction = delta.Unit
	local arrowCount = math.min(pathOptions.maxArrows, math.max(2, math.ceil(usableDistance / pathOptions.spacingStuds) + 1))
	local arrows = {}
	for index = 1, arrowCount do
		local alpha = if arrowCount == 1 then 0 else (index - 1) / (arrowCount - 1)
		local distanceFromPlayer = startDistance + usableDistance * alpha
		local worldPosition = startPosition + direction * distanceFromPlayer
		local projected = projectPathPosition(camera, viewport, worldPosition)
		if projected then
			local previousArrow = arrows[#arrows]
			local isEndpoint = index == 1 or index == arrowCount
			local hasEnoughScreenSpace = not previousArrow
				or (projected.position - previousArrow.position).Magnitude >= PATH_MIN_SCREEN_SPACING_PX
			if isEndpoint or hasEnoughScreenSpace then
				arrows[#arrows + 1] = {
					position = projected.position,
					rotation = 0,
				}
			end
		end
	end

	if #arrows < 2 or getPathScreenExtent(arrows) < PATH_COLLAPSED_SCREEN_EXTENT_PX then
		return buildFallbackPathArrows(viewport, targetProjection)
	end

	rotatePathArrows(arrows, targetProjection.position)
	return arrows
end

local function buildIndicatorState(target, showPath, pathOptions)
	local projected = projectTarget(target)
	if not projected then
		return nil
	end

	return {
		projected = projected,
		pathArrows = buildPathArrows(target, showPath, pathOptions),
	}
end

local function createPathArrow(pathArrow, _index, size, zIndex, arrowImageLoaded)
	return e("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(pathArrow.position.X, pathArrow.position.Y),
		Size = UDim2.fromOffset(size, size),
		ZIndex = zIndex,
	}, {
		FallbackArrow = createFallbackArrow(pathArrow.rotation, size, zIndex + 1, not arrowImageLoaded),
		Arrow = createArrowPointer(pathArrow.rotation, size, zIndex + 2, nil),
	})
end

local function ObjectiveIndicator(props)
	local target = props.target
	local indicatorState, setIndicatorState = React.useState(nil)
	local arrowImageRef = React.useRef(nil)
	local arrowImageLoaded, setArrowImageLoaded = React.useState(false)

	React.useEffect(function()
		local alive = true
		local connection

		local function update()
			if alive then
				setIndicatorState(buildIndicatorState(target, props.showPath == true, props.pathOptions))
			end
		end

		update()
		connection = RunService.RenderStepped:Connect(update)

		return function()
			alive = false
			if connection then
				connection:Disconnect()
			end
		end
	end, { target, props.showPath, props.pathOptions })

	React.useEffect(function()
		local alive = true
		local connection
		local attempts = 0
		setArrowImageLoaded(false)

		local function updateLoaded()
			if not alive then
				return
			end

			local imageLabel = arrowImageRef.current
			local loaded = false
			if imageLabel then
				local success, result = pcall(function()
					return imageLabel.IsLoaded
				end)
				loaded = success and result == true
			end

			setArrowImageLoaded(loaded)
		end

		local function bindWhenAvailable()
			if not alive then
				return
			end

			local imageLabel = arrowImageRef.current
			if imageLabel then
				local success, signal = pcall(function()
					return imageLabel:GetPropertyChangedSignal("IsLoaded")
				end)
				if success and signal then
					connection = signal:Connect(updateLoaded)
				end

				updateLoaded()
				return
			end

			attempts += 1
			if attempts < 30 then
				task.delay(0.1, bindWhenAvailable)
			else
				updateLoaded()
			end
		end

		task.defer(bindWhenAvailable)
		task.delay(3, updateLoaded)
		task.delay(8, updateLoaded)

		return function()
			alive = false
			if connection then
				connection:Disconnect()
			end
		end
	end, { target })

	if typeof(target) ~= "table" or not indicatorState then
		return nil
	end

	local projected = indicatorState.projected
	local label = tostring(target.label or "Objective")
	local position = projected.position
	local zIndex = tonumber(props.zIndex) or 184
	local mobile = isMobileViewport()
	local arrowSize = if mobile then (if projected.onScreen then 58 else 68) else (if projected.onScreen then 42 else 52)
	local indicatorSize = if mobile then (if projected.onScreen then 66 else 78) else (if projected.onScreen then 52 else 66)
	local pathArrowSize = if mobile then PATH_ARROW_SIZE_MOBILE else PATH_ARROW_SIZE_DESKTOP

	local indicatorChildren = {
		Corner = e("UICorner", {
			CornerRadius = UDim.new(1, 0),
		}),
		Stroke = e("UIStroke", {
			Color = COLORS.GoldSoft,
			Thickness = 2,
			Transparency = 0.08,
		}),
		FallbackArrow = createFallbackArrow(projected.rotation, arrowSize, zIndex + 3, not arrowImageLoaded),
		Arrow = createArrowPointer(projected.rotation, arrowSize, zIndex + 4, arrowImageRef),
	}

	if projected.onScreen then
		indicatorChildren.Dot = e("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = COLORS.Gold,
			BorderSizePixel = 0,
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(9, 9),
			ZIndex = zIndex + 2,
		}, {
			Corner = e("UICorner", {
				CornerRadius = UDim.new(1, 0),
			}),
		})
	end

	local rootChildren = {}
	for index, pathArrow in ipairs(indicatorState.pathArrows or {}) do
		rootChildren["PathArrow" .. tostring(index)] = createPathArrow(pathArrow, index, pathArrowSize, zIndex, arrowImageLoaded)
	end

	rootChildren.Indicator = e("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = COLORS.Panel,
		BackgroundTransparency = if projected.onScreen then 0.48 else 0.06,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(position.X, position.Y),
		Size = UDim2.fromOffset(indicatorSize, indicatorSize),
		ZIndex = zIndex + 1,
	}, indicatorChildren)

	rootChildren.Label = e("TextLabel", {
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundColor3 = COLORS.Panel,
		BackgroundTransparency = 0.12,
		BorderSizePixel = 0,
		Font = Theme.Fonts.BodyStrong,
		Position = UDim2.fromOffset(position.X, position.Y + if mobile then (if projected.onScreen then 42 else 50) else (if projected.onScreen then 34 else 41)),
		Size = UDim2.fromOffset(mobile and 154 or 142, mobile and 28 or 26),
		Text = label,
		TextColor3 = COLORS.Text,
		TextSize = mobile and 14 or 13,
		TextTruncate = Enum.TextTruncate.AtEnd,
		ZIndex = zIndex + 1,
	}, {
		Corner = e("UICorner", {
			CornerRadius = UDim.new(0, 8),
		}),
		Stroke = e("UIStroke", {
			Color = COLORS.GoldShadow,
			Thickness = 1,
			Transparency = 0.35,
		}),
	})

	return e("Frame", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		ZIndex = zIndex,
	}, rootChildren)
end

return ObjectiveIndicator
