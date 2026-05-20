local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local React = require(Packages:WaitForChild("React"))

local Theme = require(script.Parent.Parent:WaitForChild("Index"):WaitForChild("Theme"))
local ObjectiveVectorIndicator = require(script.Parent:WaitForChild("ObjectiveVectorIndicator"))

local e = React.createElement

local VECTOR_PATH_INDICATOR_STYLE = "VectorPath"
local EDGE_PADDING = 54
local TOP_PADDING = 74
local BOTTOM_PADDING = 220
local MARKER_OFFSET = 42
local ARROW_IMAGE_ASSET = "rbxassetid://136351759076111"
local PICKUP_CREW_MEMBER_TARGET_ID = "tutorial_crew_member"
local PICKUP_CREW_MEMBER_TARGET_KIND = "crew_member"
local SPEED_UPGRADE_NPC_TARGET_ID = "speed_upgrade_npc"

local COLORS = {
	Gold = Theme.Palette.Gold,
	GoldSoft = Theme.Palette.GoldSoft,
	GoldShadow = Theme.Palette.GoldShadow,
	Text = Theme.Palette.Text,
	Panel = Color3.fromRGB(14, 26, 38),
}

local DEFAULT_SIZES = {
	ArrowOnScreen = 42,
	ArrowOffScreen = 52,
	IndicatorOnScreen = 52,
	IndicatorOffScreen = 66,
	Dot = 9,
	LabelWidth = 142,
	LabelHeight = 26,
	LabelText = 13,
}

local PICKUP_CREW_MEMBER_SIZES = {
	ArrowOnScreen = 68,
	ArrowOffScreen = 82,
	IndicatorOnScreen = 82,
	IndicatorOffScreen = 96,
	Dot = 13,
	LabelWidth = 184,
	LabelHeight = 30,
	LabelText = 15,
}

local function isPickupCrewMemberTarget(target)
	if typeof(target) ~= "table" then
		return false
	end

	return tostring(target.id or "") == PICKUP_CREW_MEMBER_TARGET_ID
		and tostring(target.kind or "") == PICKUP_CREW_MEMBER_TARGET_KIND
end

local function isSpeedUpgradeNpcTarget(target)
	if typeof(target) ~= "table" then
		return false
	end

	return tostring(target.id or "") == SPEED_UPGRADE_NPC_TARGET_ID
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

local function clampToSafeScreen(point, viewport)
	local maxY = math.max(TOP_PADDING, viewport.Y - BOTTOM_PADDING)
	return Vector2.new(
		math.clamp(point.X, EDGE_PADDING, math.max(EDGE_PADDING, viewport.X - EDGE_PADDING)),
		math.clamp(point.Y, TOP_PADDING, maxY)
	)
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

local function ObjectiveScreenIndicator(props)
	local target = props.target
	local projected, setProjected = React.useState(nil)
	local arrowImageRef = React.useRef(nil)
	local arrowImageLoaded, setArrowImageLoaded = React.useState(false)

	React.useEffect(function()
		local alive = true
		local connection

		local function update()
			if alive then
				setProjected(projectTarget(target))
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
	end, { target })

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

	if typeof(target) ~= "table" or not projected then
		return nil
	end

	local label = tostring(target.label or "Objective")
	local position = projected.position
	local zIndex = tonumber(props.zIndex) or 184
	local isPickupTarget = isPickupCrewMemberTarget(target)
	local isSpeedUpgradeTarget = isSpeedUpgradeNpcTarget(target)
	local isLargeTarget = isPickupTarget or isSpeedUpgradeTarget
	local showLabel = not isSpeedUpgradeTarget
	local sizes = if isLargeTarget then PICKUP_CREW_MEMBER_SIZES else DEFAULT_SIZES
	local arrowSize = if projected.onScreen then sizes.ArrowOnScreen else sizes.ArrowOffScreen
	local indicatorSize = if projected.onScreen then sizes.IndicatorOnScreen else sizes.IndicatorOffScreen
	local labelOffsetY = (indicatorSize / 2) + 8

	local indicatorChildren = {
		Corner = e("UICorner", {
			CornerRadius = UDim.new(1, 0),
		}),
		Stroke = e("UIStroke", {
			Color = COLORS.GoldSoft,
			Thickness = if isLargeTarget then 3 else 2,
			Transparency = if isLargeTarget then 0 else 0.08,
		}),
		FallbackArrow = createFallbackArrow(projected.rotation, arrowSize, zIndex + 3, not arrowImageLoaded),
		Arrow = createArrowPointer(projected.rotation, arrowSize, zIndex + 4, arrowImageRef),
	}

	if isLargeTarget then
		indicatorChildren.PickupGlow = e("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(indicatorSize + 18, indicatorSize + 18),
			ZIndex = zIndex + 1,
		}, {
			Corner = e("UICorner", {
				CornerRadius = UDim.new(1, 0),
			}),
			Stroke = e("UIStroke", {
				ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
				Color = COLORS.GoldShadow,
				Thickness = 4,
				Transparency = 0.58,
			}),
		})
	end

	if projected.onScreen then
		indicatorChildren.Dot = e("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = COLORS.Gold,
			BorderSizePixel = 0,
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(sizes.Dot, sizes.Dot),
			ZIndex = zIndex + 2,
		}, {
			Corner = e("UICorner", {
				CornerRadius = UDim.new(1, 0),
			}),
		})
	end

	return e("Frame", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		ZIndex = zIndex,
	}, {
		Indicator = e("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = COLORS.Panel,
			BackgroundTransparency = if projected.onScreen then 0.48 else 0.06,
			BorderSizePixel = 0,
			Position = UDim2.fromOffset(position.X, position.Y),
			Size = UDim2.fromOffset(indicatorSize, indicatorSize),
			ZIndex = zIndex + 1,
		}, indicatorChildren),
		Label = showLabel and e("TextLabel", {
			AnchorPoint = Vector2.new(0.5, 0),
			BackgroundColor3 = COLORS.Panel,
			BackgroundTransparency = 0.12,
			BorderSizePixel = 0,
			Font = Theme.Fonts.BodyStrong,
			Position = UDim2.fromOffset(position.X, position.Y + labelOffsetY),
			Size = UDim2.fromOffset(sizes.LabelWidth, sizes.LabelHeight),
			Text = label,
			TextColor3 = COLORS.Text,
			TextSize = sizes.LabelText,
			TextTruncate = Enum.TextTruncate.AtEnd,
			ZIndex = zIndex + 1,
		}, {
			Corner = e("UICorner", {
				CornerRadius = UDim.new(0, 8),
			}),
			Stroke = e("UIStroke", {
				Color = if isLargeTarget then COLORS.GoldSoft else COLORS.GoldShadow,
				Thickness = if isLargeTarget then 2 else 1,
				Transparency = if isLargeTarget then 0.12 else 0.35,
			}),
		}) or nil,
	})
end

local function ObjectiveIndicator(props)
	if tostring(props.indicatorStyle or "") == VECTOR_PATH_INDICATOR_STYLE then
		return e(ObjectiveVectorIndicator, {
			target = props.target,
		})
	end

	return e(ObjectiveScreenIndicator, props)
end

return ObjectiveIndicator
