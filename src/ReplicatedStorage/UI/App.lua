local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local React = require(Packages:WaitForChild("React"))

local Modules = ReplicatedStorage:WaitForChild("Modules")
local DevilFruitAssets = require(Modules:WaitForChild("DevilFruits"):WaitForChild("Assets"))
local ChestVisuals = require(Modules:WaitForChild("GrandLineRushChestVisuals"))

local e = React.createElement
local INVENTORY_MODAL_OPEN_POSITION = UDim2.fromScale(0.5, 0.49)
local INVENTORY_MODAL_CLOSED_POSITION = UDim2.new(0.5, 0, 10, 0)
local INVENTORY_MODAL_OPEN_TIME = 0.16
local INVENTORY_MODAL_CLOSE_TIME = 0.16
local INVENTORY_MODAL_BACKDROP_TRANSPARENCY = 0.28

local PALETTE = {
	Background = Color3.fromRGB(16, 12, 11),
	Board = Color3.fromRGB(54, 36, 25),
	BoardDeep = Color3.fromRGB(33, 22, 17),
	Panel = Color3.fromRGB(28, 20, 17),
	PanelAlt = Color3.fromRGB(40, 29, 24),
	Ink = Color3.fromRGB(8, 15, 28),
	InkSoft = Color3.fromRGB(15, 23, 40),
	Card = Color3.fromRGB(57, 42, 33),
	CardSoft = Color3.fromRGB(45, 33, 28),
	Stroke = Color3.fromRGB(130, 93, 58),
	StrokeSoft = Color3.fromRGB(89, 64, 46),
	Text = Color3.fromRGB(248, 240, 228),
	Cream = Color3.fromRGB(242, 239, 229),
	Muted = Color3.fromRGB(197, 176, 150),
	MutedSoft = Color3.fromRGB(154, 132, 111),
	Steel = Color3.fromRGB(109, 123, 151),
	Orange = Color3.fromRGB(226, 144, 63),
	Gold = Color3.fromRGB(236, 190, 94),
	Green = Color3.fromRGB(110, 218, 145),
	Sea = Color3.fromRGB(88, 187, 184),
	Cyan = Color3.fromRGB(91, 212, 255),
	Rose = Color3.fromRGB(187, 66, 84),
	Violet = Color3.fromRGB(128, 124, 189),
	Shadow = Color3.fromRGB(10, 7, 6),
}

local function formatNumber(value)
	local number = tonumber(value) or 0
	local sign = number < 0 and "-" or ""
	local absValue = math.abs(number)

	local suffixes = {
		{ value = 1e18, suffix = "Qui" },
		{ value = 1e15, suffix = "Qd" },
		{ value = 1e12, suffix = "T" },
		{ value = 1e9, suffix = "B" },
		{ value = 1e6, suffix = "M" },
		{ value = 1e3, suffix = "K" },
	}

	for _, entry in ipairs(suffixes) do
		if absValue >= entry.value then
			local scaled = absValue / entry.value
			local decimals = if scaled >= 100 then 0 elseif scaled >= 10 then 1 else 2
			local text = string.format("%." .. tostring(decimals) .. "f", scaled)
			text = text:gsub("%.?0+$", "")
			return sign .. text .. entry.suffix
		end
	end

	return sign .. tostring(math.floor(absValue + 0.5))
end

local function formatLeaderboardRank(rank)
	local numericRank = tonumber(rank)
	if numericRank and numericRank >= 1 then
		return "#" .. tostring(math.floor(numericRank + 0.5))
	end

	return "Unranked"
end

local function initials(text)
	local letters = {}
	for token in string.gmatch(tostring(text or ""), "%S+") do
		letters[#letters + 1] = string.upper(string.sub(token, 1, 1))
		if #letters >= 2 then
			break
		end
	end

	if #letters == 0 then
		return "?"
	end

	return table.concat(letters)
end

local function clearChildren(instance)
	for _, child in ipairs(instance:GetChildren()) do
		child:Destroy()
	end
end

local function setPreviewPartDefaults(part)
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.Massless = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
end

local function createPreviewPart(parent, size, color, localCFrame, shape, material)
	local part = Instance.new("Part")
	part.Size = size
	part.Color = color
	part.CFrame = localCFrame
	part.Shape = shape or Enum.PartType.Block
	part.Material = material or Enum.Material.SmoothPlastic
	setPreviewPartDefaults(part)
	part.Parent = parent
	return part
end

local function buildResourcePreviewModel(resourceKey)
	local model = Instance.new("Model")
	model.Name = "ResourcePreview"

	if resourceKey == "Apple" then
		createPreviewPart(model, Vector3.new(0.9, 0.9, 0.9), Color3.fromRGB(214, 67, 52), CFrame.new(0, 0, 0), Enum.PartType.Ball)
		createPreviewPart(model, Vector3.new(0.12, 0.35, 0.12), Color3.fromRGB(86, 53, 31), CFrame.new(0, 0.5, 0), Enum.PartType.Cylinder, Enum.Material.Wood)
		createPreviewPart(model, Vector3.new(0.35, 0.12, 0.2), Color3.fromRGB(80, 170, 72), CFrame.new(0.18, 0.42, 0), Enum.PartType.Block, Enum.Material.Grass)
	elseif resourceKey == "Rice" then
		createPreviewPart(model, Vector3.new(1.0, 0.35, 1.0), Color3.fromRGB(171, 106, 57), CFrame.new(0, -0.18, 0), Enum.PartType.Cylinder, Enum.Material.Wood)
		createPreviewPart(model, Vector3.new(0.82, 0.28, 0.82), Color3.fromRGB(242, 240, 223), CFrame.new(0, 0.08, 0), Enum.PartType.Cylinder, Enum.Material.Sand)
	elseif resourceKey == "Meat" then
		createPreviewPart(model, Vector3.new(1.0, 0.7, 0.7), Color3.fromRGB(160, 64, 56), CFrame.new(0, 0, 0), Enum.PartType.Block)
		createPreviewPart(model, Vector3.new(0.22, 0.22, 0.9), Color3.fromRGB(231, 220, 208), CFrame.new(-0.6, 0, 0), Enum.PartType.Cylinder)
	elseif resourceKey == "SeaBeastMeat" then
		createPreviewPart(model, Vector3.new(1.05, 0.78, 0.74), Color3.fromRGB(105, 41, 56), CFrame.new(0, 0, 0), Enum.PartType.Block)
		createPreviewPart(model, Vector3.new(0.18, 0.82, 0.7), Color3.fromRGB(76, 186, 199), CFrame.new(0.52, 0, 0), Enum.PartType.Block, Enum.Material.Neon)
	elseif resourceKey == "Iron" then
		createPreviewPart(model, Vector3.new(0.95, 0.28, 0.55), Color3.fromRGB(180, 186, 196), CFrame.new(0, -0.08, 0), Enum.PartType.Block, Enum.Material.Metal)
		createPreviewPart(model, Vector3.new(0.8, 0.2, 0.45), Color3.fromRGB(150, 157, 168), CFrame.new(0.08, 0.16, 0.02), Enum.PartType.Block, Enum.Material.Metal)
	elseif resourceKey == "AncientTimber" then
		createPreviewPart(model, Vector3.new(1.0, 0.24, 0.32), Color3.fromRGB(112, 83, 55), CFrame.new(0, -0.12, 0), Enum.PartType.Block, Enum.Material.WoodPlanks)
		createPreviewPart(model, Vector3.new(0.92, 0.24, 0.32), Color3.fromRGB(128, 97, 65), CFrame.new(0.08, 0.14, 0.08), Enum.PartType.Block, Enum.Material.WoodPlanks)
		createPreviewPart(model, Vector3.new(0.16, 0.34, 0.16), Color3.fromRGB(110, 186, 136), CFrame.new(-0.3, 0.2, 0), Enum.PartType.Cylinder, Enum.Material.Neon)
	else
		createPreviewPart(model, Vector3.new(1.0, 0.25, 0.26), Color3.fromRGB(147, 103, 67), CFrame.new(0, -0.12, 0), Enum.PartType.Block, Enum.Material.WoodPlanks)
		createPreviewPart(model, Vector3.new(0.92, 0.25, 0.26), Color3.fromRGB(171, 121, 79), CFrame.new(0.06, 0.12, 0.06), Enum.PartType.Block, Enum.Material.WoodPlanks)
	end

	return model
end

local function buildInventoryIconModel()
	local model = Instance.new("Model")
	model.Name = "InventoryIcon"

	createPreviewPart(model, Vector3.new(0.95, 0.75, 0.46), Color3.fromRGB(204, 96, 42), CFrame.new(0, 0, 0), Enum.PartType.Block, Enum.Material.SmoothPlastic)
	createPreviewPart(model, Vector3.new(0.65, 0.2, 0.12), Color3.fromRGB(85, 49, 31), CFrame.new(0, 0.44, 0), Enum.PartType.Block, Enum.Material.Wood)
	createPreviewPart(model, Vector3.new(0.3, 0.28, 0.1), Color3.fromRGB(238, 203, 95), CFrame.new(0, -0.06, 0.24), Enum.PartType.Block, Enum.Material.Neon)

	return model
end

local function positionPreviewModel(previewModel, previewKind, previewName)
	local rotation = CFrame.Angles(math.rad(-12), math.rad(28), 0)
	if previewKind == "Resource" then
		rotation = CFrame.Angles(math.rad(-8), math.rad(26), 0)
	elseif previewKind == "Inventory" then
		rotation = CFrame.Angles(math.rad(-14), math.rad(-26), 0)
	elseif previewKind == "DevilFruit" and previewName == "Tori" then
		rotation = CFrame.Angles(math.rad(-4), math.rad(24), 0)
	end

	pcall(function()
		if previewModel:IsA("Model") or previewModel:IsA("WorldModel") then
			previewModel:PivotTo(rotation)
		elseif previewModel:IsA("BasePart") then
			previewModel.CFrame = rotation
		end
	end)

	for _, descendant in ipairs(previewModel:GetDescendants()) do
		if descendant:IsA("BasePart") then
			setPreviewPartDefaults(descendant)
		end
	end
end

local function getBoundingInfo(previewModel)
	if previewModel:IsA("BasePart") then
		return previewModel.CFrame, previewModel.Size
	end

	local ok, cf, size = pcall(function()
		return previewModel:GetBoundingBox()
	end)
	if ok then
		return cf, size
	end

	local part = previewModel:FindFirstChildWhichIsA("BasePart", true)
	if part then
		return part.CFrame, part.Size
	end

	return CFrame.new(), Vector3.new(1, 1, 1)
end

local function PreviewViewport(props)
	local viewportRef = React.useRef(nil)

	React.useEffect(function()
		local viewport = viewportRef.current
		if not viewport then
			return nil
		end

		clearChildren(viewport)

		local previewModel
		if props.previewKind == "DevilFruit" then
			previewModel = DevilFruitAssets.ClonePreviewWorldModel(props.previewName)
		elseif props.previewKind == "Chest" then
			previewModel = ChestVisuals.CreatePreviewModel(props.previewName)
		elseif props.previewKind == "Resource" then
			previewModel = buildResourcePreviewModel(props.previewName)
		elseif props.previewKind == "Inventory" then
			previewModel = buildInventoryIconModel()
		end

		if not previewModel then
			return function()
				if viewport.Parent then
					clearChildren(viewport)
				end
			end
		end

		local worldModel = Instance.new("WorldModel")
		worldModel.Parent = viewport
		previewModel.Parent = worldModel
		positionPreviewModel(previewModel, props.previewKind, props.previewName)

		local boxCF, boxSize = getBoundingInfo(previewModel)
		local maxSize = math.max(boxSize.X, boxSize.Y, boxSize.Z, 1)

		local camera = Instance.new("Camera")
		camera.Name = "PreviewCamera"
		camera.FieldOfView = props.fieldOfView or 36
		camera.CFrame = CFrame.lookAt(
			boxCF.Position + Vector3.new(maxSize * 0.92, maxSize * 0.38, maxSize * 1.7),
			boxCF.Position
		)
		camera.Parent = viewport
		viewport.CurrentCamera = camera

		return function()
			if viewport.Parent then
				clearChildren(viewport)
			end
		end
	end, { props.previewKind, props.previewName })

	return e("ViewportFrame", {
		ref = viewportRef,
		AnchorPoint = props.anchorPoint or Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = props.position,
		Size = props.size,
		Ambient = Color3.fromRGB(206, 196, 186),
		LightColor = Color3.fromRGB(255, 252, 246),
		LightDirection = Vector3.new(-1, -1, -1),
		ZIndex = props.zIndex,
	})
end

local function useInteractiveState(enabled, allowPress)
	local hovered, setHovered = React.useState(false)
	local pressed, setPressed = React.useState(false)
	local hoverRef = React.useRef(nil)
	local pressEnabled = allowPress ~= false

	local function isCursorOverTarget()
		local target = hoverRef.current
		if not target then
			return false
		end

		local mousePosition = UserInputService:GetMouseLocation()
		local absolutePosition = target.AbsolutePosition
		local absoluteSize = target.AbsoluteSize
		local minX = absolutePosition.X
		local minY = absolutePosition.Y
		local maxX = minX + absoluteSize.X
		local maxY = minY + absoluteSize.Y

		return mousePosition.X >= minX
			and mousePosition.X <= maxX
			and mousePosition.Y >= minY
			and mousePosition.Y <= maxY
	end

	React.useEffect(function()
		if not enabled then
			setHovered(false)
			setPressed(false)
			return nil
		end

		return function()
			setHovered(false)
			setPressed(false)
		end
	end, { enabled })

	local handlers = {}
	if enabled then
		handlers[React.Event.MouseEnter] = function()
			setHovered(true)
		end
		handlers[React.Event.MouseLeave] = function()
			task.defer(function()
				if not isCursorOverTarget() then
					setHovered(false)
					setPressed(false)
				end
			end)
		end
		if pressEnabled then
			handlers[React.Event.MouseButton1Down] = function()
				setPressed(true)
			end
			handlers[React.Event.MouseButton1Up] = function()
				setPressed(false)
			end
		end
	end

	return hovered, pressed, handlers, hoverRef
end

local function mergeProps(baseProps, extraProps)
	local merged = {}
	for key, value in pairs(baseProps) do
		merged[key] = value
	end
	for key, value in pairs(extraProps) do
		merged[key] = value
	end
	return merged
end

local function AnimatedInventoryModal(props)
	local mounted, setMounted = React.useState(props.isOpen == true)
	local cachedPanelChildren, setCachedPanelChildren = React.useState(props.panelChildren)
	local rootRef = React.useRef(nil)
	local backdropRef = React.useRef(nil)
	local panelRef = React.useRef(nil)
	local scaleRef = React.useRef(nil)
	local animationStateRef = React.useRef(props.isOpen and "open" or "closed")
	local activeTweensRef = React.useRef({})

	local function cancelActiveTweens()
		for _, tween in ipairs(activeTweensRef.current) do
			tween:Cancel()
		end
		table.clear(activeTweensRef.current)
	end

	local function playOpenAnimation()
		local backdrop = backdropRef.current
		local panel = panelRef.current
		local scale = scaleRef.current
		if not backdrop or not panel or not scale then
			return
		end

		cancelActiveTweens()
		animationStateRef.current = "opening"

		backdrop.BackgroundTransparency = 1
		panel.Position = props.closedPosition or INVENTORY_MODAL_CLOSED_POSITION
		scale.Scale = 0

		local tweenInfo = TweenInfo.new(
			props.openTime or INVENTORY_MODAL_OPEN_TIME,
			Enum.EasingStyle.Quad,
			Enum.EasingDirection.Out
		)

		local backdropTween = TweenService:Create(backdrop, tweenInfo, {
			BackgroundTransparency = props.backdropTransparency or INVENTORY_MODAL_BACKDROP_TRANSPARENCY,
		})
		local positionTween = TweenService:Create(panel, tweenInfo, {
			Position = props.openPosition or INVENTORY_MODAL_OPEN_POSITION,
		})
		local scaleTween = TweenService:Create(scale, tweenInfo, {
			Scale = 1,
		})

		activeTweensRef.current = { backdropTween, positionTween, scaleTween }
		positionTween.Completed:Connect(function()
			if animationStateRef.current == "opening" then
				animationStateRef.current = "open"
			end
		end)

		backdropTween:Play()
		positionTween:Play()
		scaleTween:Play()
	end

	local function playCloseAnimation()
		local backdrop = backdropRef.current
		local panel = panelRef.current
		local scale = scaleRef.current
		if not backdrop or not panel or not scale then
			setMounted(false)
			animationStateRef.current = "closed"
			return
		end

		cancelActiveTweens()
		animationStateRef.current = "closing"

		local tweenInfo = TweenInfo.new(
			props.closeTime or INVENTORY_MODAL_CLOSE_TIME,
			Enum.EasingStyle.Quad,
			Enum.EasingDirection.In
		)

		local backdropTween = TweenService:Create(backdrop, tweenInfo, {
			BackgroundTransparency = 1,
		})
		local positionTween = TweenService:Create(panel, tweenInfo, {
			Position = props.closedPosition or INVENTORY_MODAL_CLOSED_POSITION,
		})
		local scaleTween = TweenService:Create(scale, tweenInfo, {
			Scale = 0,
		})

		activeTweensRef.current = { backdropTween, positionTween, scaleTween }
		positionTween.Completed:Connect(function()
			if animationStateRef.current == "closing" then
				animationStateRef.current = "closed"
				setMounted(false)
			end
		end)

		backdropTween:Play()
		positionTween:Play()
		scaleTween:Play()
	end

	React.useEffect(function()
		if props.isOpen and props.panelChildren then
			setCachedPanelChildren(props.panelChildren)
		end
	end, { props.isOpen, props.panelChildren })

	React.useEffect(function()
		if props.isOpen then
			if not mounted then
				setMounted(true)
				return
			end

			if animationStateRef.current ~= "open" and animationStateRef.current ~= "opening" then
				task.defer(playOpenAnimation)
			end
		elseif mounted and animationStateRef.current ~= "closing" and animationStateRef.current ~= "closed" then
			task.defer(playCloseAnimation)
		end
	end, { props.isOpen, mounted, cachedPanelChildren })

	React.useEffect(function()
		return function()
			cancelActiveTweens()
		end
	end, {})

	if not mounted or not cachedPanelChildren then
		return nil
	end

	local panelChildren = {
		Scale = e("UIScale", {
			ref = scaleRef,
			Scale = props.isOpen and 1 or 0,
		}),
	}

	for key, value in pairs(cachedPanelChildren) do
		panelChildren[key] = value
	end

	return e("Frame", {
		ref = rootRef,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 4,
	}, {
		Backdrop = e("Frame", {
			ref = backdropRef,
			BackgroundColor3 = PALETTE.Ink,
			BackgroundTransparency = props.isOpen and (props.backdropTransparency or INVENTORY_MODAL_BACKDROP_TRANSPARENCY) or 1,
			BorderSizePixel = 0,
			Size = UDim2.fromScale(1, 1),
			ZIndex = 4,
		}),
		Panel = e("Frame", {
			ref = panelRef,
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundTransparency = 1,
			Position = props.isOpen and (props.openPosition or INVENTORY_MODAL_OPEN_POSITION) or (props.closedPosition or INVENTORY_MODAL_CLOSED_POSITION),
			Size = props.panelSize or UDim2.new(0.82, 0, 0.76, 0),
			ZIndex = 5,
		}, panelChildren),
	})
end

local function statChip(props)
	local accent = props.accentColor or PALETTE.Orange
	local size = props.size or UDim2.fromOffset(176, 58)
	local height = size.Y.Scale == 0 and size.Y.Offset or 58
	local compact = props.compact == true or height <= 40
	local showAccent = props.showAccent ~= false
	local backgroundColor = props.backgroundColor3 or PALETTE.Card
	local gradientStart = props.gradientStartColor3 or backgroundColor
	local gradientEnd = props.gradientEndColor3 or PALETTE.CardSoft
	local strokeTransparency = props.strokeTransparency or 0.38
	local labelColor = props.labelColor3 or PALETTE.MutedSoft
	local cornerRadius = compact and 13 or 16
	local accentHeight = compact and 2 or 3
	local labelHeight = compact and 10 or 12
	local valueY = compact and 12 or 20
	local valueHeight = compact and 14 or 16
	local paddingTop = compact and 8 or 12
	if not showAccent then
		paddingTop += compact and 1 or 2
	end

	return e("Frame", {
		BackgroundColor3 = backgroundColor,
		BorderSizePixel = 0,
		LayoutOrder = props.layoutOrder or 0,
		Size = size,
	}, {
		Corner = e("UICorner", {
			CornerRadius = UDim.new(0, cornerRadius),
		}),
		Stroke = e("UIStroke", {
			Color = accent,
			Transparency = strokeTransparency,
			Thickness = 1.1,
		}),
		Gradient = e("UIGradient", {
			Rotation = 90,
			Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, gradientStart),
				ColorSequenceKeypoint.new(1, gradientEnd),
			}),
		}),
		Accent = showAccent and e("Frame", {
			BackgroundColor3 = accent,
			BorderSizePixel = 0,
			Size = UDim2.new(1, 0, 0, accentHeight),
		}, {
			Corner = e("UICorner", {
				CornerRadius = UDim.new(0, cornerRadius),
			}),
		}) or nil,
		Padding = e("UIPadding", {
			PaddingTop = UDim.new(0, paddingTop),
			PaddingBottom = UDim.new(0, compact and 6 or 10),
			PaddingLeft = UDim.new(0, compact and 10 or 14),
			PaddingRight = UDim.new(0, compact and 10 or 14),
		}),
		Label = e("TextLabel", {
			BackgroundTransparency = 1,
			Font = Enum.Font.GothamMedium,
			Size = UDim2.new(1, 0, 0, labelHeight),
			Text = props.label or "",
			TextColor3 = labelColor,
			TextSize = compact and 9 or 10,
			TextXAlignment = Enum.TextXAlignment.Left,
		}),
		Value = e("TextLabel", {
			BackgroundTransparency = 1,
			Font = Enum.Font.GothamBold,
			Position = UDim2.fromOffset(0, valueY),
			Size = UDim2.new(1, 0, 0, valueHeight),
			Text = props.value or "",
			TextColor3 = PALETTE.Text,
			TextSize = props.valueTextSize or (compact and 14 or 17),
			TextXAlignment = Enum.TextXAlignment.Left,
		}),
	})
end

local function tabButton(props)
	local active = props.active == true
	local accent = props.accentColor or PALETTE.Orange

	return e("TextButton", {
		AutoButtonColor = false,
		BackgroundColor3 = active and PALETTE.Card or PALETTE.CardSoft,
		BackgroundTransparency = 0.02,
		BorderSizePixel = 0,
		LayoutOrder = props.layoutOrder or 0,
		Size = props.size or UDim2.new(1, 0, 0, 48),
		Text = "",
		[React.Event.Activated] = props.onActivated,
	}, {
		Corner = e("UICorner", {
			CornerRadius = UDim.new(0, 14),
		}),
		Stroke = e("UIStroke", {
			Color = active and accent or PALETTE.StrokeSoft,
			Transparency = active and 0.12 or 0.26,
			Thickness = active and 1.4 or 1,
		}),
		Gradient = e("UIGradient", {
			Rotation = 90,
			Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, active and Color3.fromRGB(70, 49, 37) or PALETTE.Card),
				ColorSequenceKeypoint.new(1, active and Color3.fromRGB(54, 39, 31) or PALETTE.CardSoft),
			}),
		}),
		AccentRail = e("Frame", {
			BackgroundColor3 = active and accent or PALETTE.StrokeSoft,
			BorderSizePixel = 0,
			Position = UDim2.fromOffset(0, 7),
			Size = UDim2.fromOffset(active and 6 or 3, 34),
		}, {
			Corner = e("UICorner", {
				CornerRadius = UDim.new(0, 999),
			}),
		}),
		Label = e("TextLabel", {
			BackgroundTransparency = 1,
			Font = Enum.Font.GothamSemibold,
			Position = UDim2.fromOffset(16, 0),
			Size = UDim2.new(1, -54, 1, 0),
			Text = props.label or "",
			TextColor3 = PALETTE.Text,
			TextSize = 12,
			TextXAlignment = Enum.TextXAlignment.Left,
		}),
		Count = e("TextLabel", {
			AnchorPoint = Vector2.new(1, 0.5),
			AutomaticSize = Enum.AutomaticSize.XY,
			BackgroundColor3 = PALETTE.Background,
			BackgroundTransparency = active and 0 or 0.08,
			Position = UDim2.new(1, -10, 0.5, 0),
			Font = Enum.Font.GothamBold,
			Text = tostring(props.count or 0),
			TextColor3 = active and accent or PALETTE.Muted,
			TextSize = 11,
		}, {
			Corner = e("UICorner", {
				CornerRadius = UDim.new(0, 999),
			}),
			Padding = e("UIPadding", {
				PaddingTop = UDim.new(0, 4),
				PaddingBottom = UDim.new(0, 4),
				PaddingLeft = UDim.new(0, 8),
				PaddingRight = UDim.new(0, 8),
			}),
		}),
	})
end

local function hotbarSlot(props)
	local slot = props.slot or {}
	local item = slot.item
	local accent = item and item.accentColor or Color3.fromRGB(76, 96, 132)
	local interactive = item ~= nil and props.onActivated ~= nil
	local hovered, pressed, handlers, hoverRef = useInteractiveState(interactive)
	local zIndexBase = props.zIndexBase or 0
	local slotBaseColor = item and accent:Lerp(Color3.fromRGB(20, 28, 44), 0.78) or Color3.fromRGB(13, 19, 31)
	local slotTopColor = item and accent:Lerp(Color3.fromRGB(28, 39, 61), 0.84) or Color3.fromRGB(18, 26, 41)
	local slotBottomColor = item and accent:Lerp(Color3.fromRGB(12, 17, 30), 0.92) or Color3.fromRGB(10, 14, 24)

	local slotProps = mergeProps({
		BackgroundColor3 = slotBaseColor,
		BackgroundTransparency = item and 0.3 or 0.76,
		BorderSizePixel = 0,
		LayoutOrder = props.layoutOrder or 0,
		ref = hoverRef,
		Size = UDim2.fromOffset(64, 64),
		ZIndex = zIndexBase + 1,
	}, handlers)

	if interactive then
		slotProps.AutoButtonColor = false
		slotProps.Text = ""
		slotProps[React.Event.Activated] = function()
			props.onActivated(item)
		end
	end

	local previewChild = item and item.image and item.image ~= "" and e("ImageLabel", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		Image = item.image,
		Position = UDim2.fromScale(0.5, 0.52),
		Size = UDim2.fromOffset(34, 34),
		ScaleType = Enum.ScaleType.Fit,
		ZIndex = zIndexBase + 3,
	}) or (item and item.previewKind and e(PreviewViewport, {
		previewKind = item.previewKind,
		previewName = item.previewName,
		position = UDim2.fromScale(0.5, 0.52),
		size = UDim2.fromOffset(40, 40),
		zIndex = zIndexBase + 3,
		fieldOfView = 34,
	})) or e("TextLabel", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamMedium,
		Position = UDim2.fromScale(0.5, 0.55),
		Size = UDim2.new(1, -12, 0, 18),
		Text = "",
		TextColor3 = PALETTE.Muted,
		TextSize = 10,
		ZIndex = zIndexBase + 3,
	})

	return e(interactive and "TextButton" or "Frame", slotProps, {
		Scale = e("UIScale", {
			Scale = (hovered and 1.03 or 1) - (pressed and 0.018 or 0),
		}),
		Corner = e("UICorner", {
			CornerRadius = UDim.new(0, 16),
		}),
		Stroke = e("UIStroke", {
			Color = accent,
			Transparency = item and (hovered and 0.08 or 0.18) or 0.7,
			Thickness = item and (hovered and 1.9 or 1.5) or 1.1,
		}),
		Glow = e("UIStroke", {
			Color = accent,
			Transparency = item and (hovered and 0.76 or 0.9) or 0.97,
			Thickness = 3,
		}),
		Gradient = e("UIGradient", {
			Rotation = 90,
			Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, slotTopColor),
				ColorSequenceKeypoint.new(1, slotBottomColor),
			}),
		}),
		Inset = e("Frame", {
			BackgroundColor3 = Color3.fromRGB(7, 11, 20),
			BackgroundTransparency = item and (hovered and 0.5 or 0.58) or 0.86,
			BorderSizePixel = 0,
			Position = UDim2.fromOffset(4, 4),
			Size = UDim2.new(1, -8, 1, -8),
			ZIndex = zIndexBase + 1,
		}, {
			Corner = e("UICorner", {
				CornerRadius = UDim.new(0, 13),
			}),
		}),
		KeyLabel = slot.slotLabel ~= nil and e("TextLabel", {
			AutomaticSize = Enum.AutomaticSize.XY,
			BackgroundColor3 = Color3.fromRGB(6, 10, 18),
			BackgroundTransparency = hovered and 0.08 or 0.16,
			Position = UDim2.fromOffset(6, 6),
			Font = Enum.Font.GothamBold,
			Text = tostring(slot.slotLabel),
			TextColor3 = item and PALETTE.Cream or PALETTE.Steel,
			TextSize = 10,
			ZIndex = zIndexBase + 4,
		}, {
			Corner = e("UICorner", {
				CornerRadius = UDim.new(0, 999),
			}),
			Padding = e("UIPadding", {
				PaddingTop = UDim.new(0, 3),
				PaddingBottom = UDim.new(0, 3),
				PaddingLeft = UDim.new(0, 7),
				PaddingRight = UDim.new(0, 7),
			}),
		}) or nil,
		Preview = previewChild,
		Count = item and (item.quantity or 0) > 1 and e("TextLabel", {
			AnchorPoint = Vector2.new(1, 1),
			AutomaticSize = Enum.AutomaticSize.XY,
			BackgroundColor3 = Color3.fromRGB(6, 10, 18),
			BackgroundTransparency = hovered and 0.08 or 0.16,
			Position = UDim2.new(1, -6, 1, -6),
			Font = Enum.Font.GothamBold,
			Text = tostring(item.quantity),
			TextColor3 = PALETTE.Cream,
			TextSize = 10,
			ZIndex = zIndexBase + 4,
		}, {
			Corner = e("UICorner", {
				CornerRadius = UDim.new(0, 999),
			}),
			Padding = e("UIPadding", {
				PaddingTop = UDim.new(0, 2),
				PaddingBottom = UDim.new(0, 2),
				PaddingLeft = UDim.new(0, 6),
				PaddingRight = UDim.new(0, 6),
			}),
		}) or nil,
	})
end

local function itemCard(props)
	local item = props.item or {}
	local accent = item.accentColor or PALETTE.Orange
	local interactive = item.interactive == true

	local itemProps = {
		BackgroundColor3 = PALETTE.Card,
		BorderSizePixel = 0,
		LayoutOrder = props.layoutOrder or 0,
		Size = UDim2.fromOffset(156, 190),
	}

	if interactive then
		itemProps.AutoButtonColor = false
		itemProps.Text = ""
		itemProps[React.Event.Activated] = function()
			props.onActivated(item)
		end
	end

	local previewChild = item.image and item.image ~= "" and e("ImageLabel", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		Image = item.image,
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(66, 66),
		ScaleType = Enum.ScaleType.Fit,
		ZIndex = 3,
	}) or (item.previewKind and e(PreviewViewport, {
		previewKind = item.previewKind,
		previewName = item.previewName,
		position = UDim2.fromScale(0.5, 0.5),
		size = UDim2.fromOffset(74, 74),
		zIndex = 3,
		fieldOfView = 34,
	})) or e("TextLabel", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, -12, 1, -12),
		Text = item.fallbackText or initials(item.displayName),
		TextColor3 = PALETTE.Text,
		TextSize = 22,
		TextWrapped = true,
		ZIndex = 3,
	})

	return e(interactive and "TextButton" or "Frame", itemProps, {
		Corner = e("UICorner", {
			CornerRadius = UDim.new(0, 18),
		}),
		Stroke = e("UIStroke", {
			Color = item.isEquipped and accent or PALETTE.Stroke,
			Transparency = item.isEquipped and 0.05 or 0.42,
			Thickness = item.isEquipped and 1.6 or 1,
		}),
		Gradient = e("UIGradient", {
			Rotation = 90,
			Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, PALETTE.Card),
				ColorSequenceKeypoint.new(1, Color3.fromRGB(48, 35, 29)),
			}),
		}),
		HeaderStrip = e("Frame", {
			BackgroundColor3 = accent,
			BackgroundTransparency = 0.18,
			BorderSizePixel = 0,
			Size = UDim2.new(1, 0, 0, 4),
		}, {
			Corner = e("UICorner", {
				CornerRadius = UDim.new(0, 18),
			}),
		}),
		PreviewShell = e("Frame", {
			BackgroundColor3 = PALETTE.PanelAlt,
			BackgroundTransparency = 0.02,
			BorderSizePixel = 0,
			Position = UDim2.fromOffset(12, 12),
			Size = UDim2.new(1, -24, 0, 86),
		}, {
			Corner = e("UICorner", {
				CornerRadius = UDim.new(0, 14),
			}),
			Stroke = e("UIStroke", {
				Color = accent,
				Transparency = 0.55,
			}),
			PreviewTint = e("Frame", {
				BackgroundColor3 = accent,
				BackgroundTransparency = 0.88,
				BorderSizePixel = 0,
				Size = UDim2.fromScale(1, 1),
				ZIndex = 1,
			}, {
				Corner = e("UICorner", {
					CornerRadius = UDim.new(0, 14),
				}),
			}),
			Preview = previewChild,
		}),
		Name = e("TextLabel", {
			BackgroundTransparency = 1,
			Font = Enum.Font.GothamBold,
			Position = UDim2.fromOffset(14, 106),
			Size = UDim2.new(1, -28, 0, 34),
			Text = item.displayName or "",
			TextColor3 = PALETTE.Text,
			TextSize = 13,
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Top,
		}),
		Subtitle = e("TextLabel", {
			BackgroundTransparency = 1,
			Font = Enum.Font.GothamMedium,
			Position = UDim2.fromOffset(14, 144),
			Size = UDim2.new(1, -28, 0, 14),
			Text = item.subtitle or "",
			TextColor3 = accent,
			TextSize = 10,
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left,
		}),
		Footer = e("TextLabel", {
			BackgroundTransparency = 1,
			Font = Enum.Font.Gotham,
			Position = UDim2.fromOffset(14, 160),
			Size = UDim2.new(1, -28, 0, 14),
			Text = item.footer or "",
			TextColor3 = PALETTE.Muted,
			TextSize = 9,
			TextXAlignment = Enum.TextXAlignment.Left,
		}),
		Count = (item.quantity or 0) > 1 and e("TextLabel", {
			AnchorPoint = Vector2.new(1, 0),
			AutomaticSize = Enum.AutomaticSize.XY,
			BackgroundColor3 = PALETTE.Background,
			BackgroundTransparency = 0.08,
			Position = UDim2.new(1, -12, 0, 12),
			Font = Enum.Font.GothamBold,
			Text = "x" .. tostring(item.quantity),
			TextColor3 = PALETTE.Text,
			TextSize = 10,
		}, {
			Corner = e("UICorner", {
				CornerRadius = UDim.new(0, 999),
			}),
			Padding = e("UIPadding", {
				PaddingTop = UDim.new(0, 3),
				PaddingBottom = UDim.new(0, 3),
				PaddingLeft = UDim.new(0, 7),
				PaddingRight = UDim.new(0, 7),
			}),
		}) or nil,
		Equipped = item.isEquipped and e("TextLabel", {
			AutomaticSize = Enum.AutomaticSize.XY,
			BackgroundColor3 = accent,
			BackgroundTransparency = 0.08,
			Position = UDim2.fromOffset(12, 82),
			Font = Enum.Font.GothamBold,
			Text = "Equipped",
			TextColor3 = PALETTE.Text,
			TextSize = 10,
		}, {
			Corner = e("UICorner", {
				CornerRadius = UDim.new(0, 999),
			}),
			Padding = e("UIPadding", {
				PaddingTop = UDim.new(0, 3),
				PaddingBottom = UDim.new(0, 3),
				PaddingLeft = UDim.new(0, 7),
				PaddingRight = UDim.new(0, 7),
			}),
		}) or nil,
	})
end

local function inventoryToggleButton(props)
	local layout = props.toggleLayout or {}
	local position = layout.position or UDim2.new(1, -26, 1, -24)
	local size = layout.size or UDim2.fromOffset(154, 54)
	local compact = layout.compact == true
	local hovered, pressed, handlers, hoverRef = useInteractiveState(props.onToggle ~= nil)
	local zIndexBase = props.zIndexBase or 0
	local iconPosition = compact and UDim2.new(0.5, 0, 0, 28) or UDim2.new(0.5, 0, 0.44, 0)
	local iconSize = compact and UDim2.fromOffset(34, 34) or UDim2.fromOffset(34, 34)
	local toggleIcon = props.toggleIcon or {}
	local hasLegacyIcon = typeof(toggleIcon.image) == "string" and toggleIcon.image ~= ""

	local iconChild
	if hasLegacyIcon then
		local imageProps = {
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundTransparency = 1,
			Image = toggleIcon.image,
			ImageColor3 = toggleIcon.imageColor3 or Color3.new(1, 1, 1),
			Position = iconPosition,
			ScaleType = toggleIcon.scaleType or Enum.ScaleType.Fit,
			Size = iconSize,
			ZIndex = zIndexBase + 3,
		}

		if toggleIcon.imageRectSize and (toggleIcon.imageRectSize.X > 0 or toggleIcon.imageRectSize.Y > 0) then
			imageProps.ImageRectOffset = toggleIcon.imageRectOffset
			imageProps.ImageRectSize = toggleIcon.imageRectSize
		end

		iconChild = e("ImageLabel", imageProps)
	else
		iconChild = e(PreviewViewport, {
			previewKind = "Inventory",
			previewName = "Inventory",
			position = iconPosition,
			anchorPoint = Vector2.new(0.5, 0.5),
			size = iconSize,
			zIndex = zIndexBase + 3,
			fieldOfView = 34,
		})
	end

	return e("TextButton", mergeProps({
		AnchorPoint = layout.anchorPoint or Vector2.new(0, 0),
		AutoButtonColor = false,
		BackgroundColor3 = PALETTE.InkSoft,
		BackgroundTransparency = compact and 0.6 or 0.5,
		BorderSizePixel = 0,
		Position = position,
		ref = hoverRef,
		Size = size,
		Text = "",
		ZIndex = zIndexBase + 1,
		[React.Event.Activated] = props.onToggle,
	}, handlers), {
		Scale = e("UIScale", {
			Scale = (hovered and 1.018 or 1) - (pressed and 0.016 or 0),
		}),
		Corner = e("UICorner", {
			CornerRadius = UDim.new(0, compact and 6 or 16),
		}),
		Gradient = e("UIGradient", {
			Rotation = 90,
			Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, Color3.fromRGB(21, 31, 49)),
				ColorSequenceKeypoint.new(1, Color3.fromRGB(8, 13, 24)),
			}),
		}),
		Stroke = e("UIStroke", {
			Color = Color3.fromRGB(72, 98, 146),
			Transparency = hovered and 0.08 or (compact and 0.22 or 0.18),
			Thickness = compact and (hovered and 2 or 1.8) or (hovered and 1.7 or 1.4),
		}),
		Shadow = e("UIStroke", {
			Color = PALETTE.Sea,
			Transparency = hovered and (compact and 0.82 or 0.84) or (compact and 0.94 or 0.95),
			Thickness = compact and 3 or 2,
		}),
		Inset = e("Frame", {
			BackgroundColor3 = Color3.fromRGB(7, 11, 20),
			BackgroundTransparency = compact and 0.66 or 0.74,
			BorderSizePixel = 0,
			Position = UDim2.fromOffset(4, 4),
			Size = UDim2.new(1, -8, 1, -8),
			ZIndex = zIndexBase + 1,
		}, {
			Corner = e("UICorner", {
				CornerRadius = UDim.new(0, compact and 5 or 12),
			}),
		}),
		Icon = iconChild,
		KeyHint = compact and e("TextLabel", {
			AnchorPoint = Vector2.new(0.5, 0),
			BackgroundColor3 = Color3.fromRGB(11, 18, 32),
			BackgroundTransparency = 0.14,
			BorderSizePixel = 0,
			Font = Enum.Font.GothamBlack,
			Position = UDim2.new(0.5, 0, 0, 4),
			Size = UDim2.fromOffset(18, 16),
			Text = "F",
			TextColor3 = Color3.fromRGB(233, 242, 255),
			TextSize = 10,
			TextStrokeTransparency = 0.7,
			ZIndex = zIndexBase + 4,
		}, {
			Corner = e("UICorner", {
				CornerRadius = UDim.new(0, 5),
			}),
			Stroke = e("UIStroke", {
				Color = Color3.fromRGB(91, 117, 166),
				Transparency = 0.3,
				Thickness = 1,
			}),
		}) or nil,
		Title = e("TextLabel", {
			AnchorPoint = compact and Vector2.new(0.5, 1) or Vector2.new(0.5, 0),
			BackgroundTransparency = 1,
			Font = Enum.Font.GothamBlack,
			Position = compact and UDim2.new(0.5, 0, 1, -3) or UDim2.new(0.5, 0, 0, 10),
			Size = UDim2.new(1, -8, 0, compact and 16 or 16),
			Text = "Inventory",
			TextColor3 = PALETTE.Cream,
			TextSize = compact and 10 or 13,
			TextStrokeTransparency = compact and 0.5 or 0.65,
			TextStrokeColor3 = Color3.fromRGB(8, 12, 20),
			TextWrapped = true,
			ZIndex = zIndexBase + 3,
		}),
		Body = not compact and e("TextLabel", {
			BackgroundTransparency = 1,
			Font = Enum.Font.Gotham,
			Position = UDim2.fromOffset(14, 28),
			Size = UDim2.new(1, -28, 0, 12),
			Text = "Press F or `",
			TextColor3 = PALETTE.Steel,
			TextSize = 10,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = zIndexBase + 3,
		}) or nil,
	})
end

local function modeTab(props)
	local active = props.active == true
	local hovered, pressed, handlers, hoverRef = useInteractiveState(props.onActivated ~= nil)
	local heldHover = hovered
	local heldActive = active and not hovered
	local heldScale = heldHover and 1.02 or (heldActive and 1.008 or 1)

	local buttonProps = mergeProps({
		AutoButtonColor = false,
		BackgroundColor3 = props.fillColor3 or PALETTE.Sea,
		BorderSizePixel = 0,
		LayoutOrder = props.layoutOrder or 0,
		ref = hoverRef,
		Size = props.size or UDim2.fromOffset(138, 36),
		Text = "",
		[React.Event.Activated] = props.onActivated,
	}, handlers)

	return e("TextButton", buttonProps, {
		Scale = e("UIScale", {
			Scale = heldScale - (pressed and 0.018 or 0),
		}),
		Corner = e("UICorner", {
			CornerRadius = UDim.new(0, 12),
		}),
		Stroke = e("UIStroke", {
			Color = active and PALETTE.Cream or Color3.fromRGB(17, 20, 32),
			Transparency = active and 0 or 0.18,
			Thickness = active and 2 or 1.4,
		}),
		Glow = e("UIStroke", {
			Color = PALETTE.Cream,
			Transparency = active and 0.72 or (hovered and 0.84 or 1),
			Thickness = 3,
		}),
		Gradient = e("UIGradient", {
			Rotation = 90,
			Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, active and props.fillColor3 or props.fillColor3:Lerp(Color3.new(0, 0, 0), 0.18)),
				ColorSequenceKeypoint.new(1, active and props.fillColor3:Lerp(Color3.new(0, 0, 0), 0.28) or props.fillColor3:Lerp(Color3.new(0, 0, 0), 0.42)),
			}),
		}),
		Label = e("TextLabel", {
			BackgroundTransparency = 1,
			Font = Enum.Font.Cartoon,
			Size = UDim2.new(1, -16, 1, 0),
			Position = UDim2.fromOffset(8, -1),
			Text = props.label or "",
			TextColor3 = PALETTE.Cream,
			TextSize = 20,
			TextStrokeTransparency = 0.35,
			TextStrokeColor3 = Color3.fromRGB(18, 18, 22),
			TextWrapped = true,
			ZIndex = 2,
		}),
	})
end

local function ledgerLine(props)
	local multiLine = props.multiLine == true

	return e("Frame", {
		BackgroundTransparency = 1,
		LayoutOrder = props.layoutOrder or 0,
		Size = UDim2.new(1, 0, 0, multiLine and 44 or 28),
	}, {
		Label = e("TextLabel", {
			BackgroundTransparency = 1,
			Font = Enum.Font.Cartoon,
			Position = UDim2.fromOffset(0, -1),
			Size = multiLine and UDim2.new(1, 0, 0, 16) or UDim2.new(0.58, 0, 1, 0),
			Text = props.label or "",
			TextColor3 = PALETTE.Cream,
			TextSize = 18,
			TextStrokeTransparency = 0.6,
			TextXAlignment = Enum.TextXAlignment.Left,
		}),
		Value = e("TextLabel", {
			AnchorPoint = multiLine and Vector2.new(0, 0) or Vector2.new(1, 0),
			BackgroundTransparency = 1,
			Font = Enum.Font.GothamBold,
			Position = multiLine and UDim2.fromOffset(0, 18) or UDim2.new(1, 0, 0, 3),
			Size = multiLine and UDim2.new(1, 0, 0, 22) or UDim2.new(0.42, 0, 1, 0),
			Text = props.value or "",
			TextColor3 = props.valueColor3 or PALETTE.Cyan,
			TextSize = multiLine and 15 or 18,
			TextStrokeTransparency = 0.8,
			TextTruncate = multiLine and Enum.TextTruncate.AtEnd or Enum.TextTruncate.None,
			TextWrapped = multiLine,
			TextXAlignment = multiLine and Enum.TextXAlignment.Left or Enum.TextXAlignment.Right,
			TextYAlignment = multiLine and Enum.TextYAlignment.Top or Enum.TextYAlignment.Center,
		}),
	})
end

local function categoryMenuTab(props)
	local active = props.active == true
	local accent = props.accentColor or PALETTE.Orange
	local hovered, pressed, handlers, hoverRef = useInteractiveState(props.onActivated ~= nil)
	local heldHover = hovered
	local heldActive = active and not hovered
	local heldScale = heldHover and 1.018 or (heldActive and 1.006 or 1)

	local buttonProps = mergeProps({
		AutoButtonColor = false,
		BackgroundColor3 = active and Color3.fromRGB(49, 49, 57) or Color3.fromRGB(37, 37, 42),
		BorderSizePixel = 0,
		LayoutOrder = props.layoutOrder or 0,
		ref = hoverRef,
		Size = props.size or UDim2.fromOffset(154, 34),
		Text = "",
		[React.Event.Activated] = props.onActivated,
	}, handlers)

	return e("TextButton", buttonProps, {
		Scale = e("UIScale", {
			Scale = heldScale - (pressed and 0.016 or 0),
		}),
		Corner = e("UICorner", {
			CornerRadius = UDim.new(0, 11),
		}),
		Stroke = e("UIStroke", {
			Color = active and accent or Color3.fromRGB(12, 12, 16),
			Transparency = active and 0 or 0.14,
			Thickness = active and 1.8 or 1.2,
		}),
		Gradient = e("UIGradient", {
			Rotation = 90,
			Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, active and Color3.fromRGB(63, 63, 69) or Color3.fromRGB(48, 48, 52)),
				ColorSequenceKeypoint.new(1, active and Color3.fromRGB(39, 39, 43) or Color3.fromRGB(27, 27, 31)),
			}),
		}),
		Label = e("TextLabel", {
			BackgroundTransparency = 1,
			Font = Enum.Font.Cartoon,
			Position = UDim2.fromOffset(14, -1),
			Size = UDim2.new(1, -52, 1, 0),
			Text = props.label or "",
			TextColor3 = active and PALETTE.Cream or Color3.fromRGB(234, 234, 234),
			TextSize = 19,
			TextStrokeTransparency = 0.6,
			TextXAlignment = Enum.TextXAlignment.Left,
		}),
		Count = e("TextLabel", {
			AnchorPoint = Vector2.new(1, 0.5),
			AutomaticSize = Enum.AutomaticSize.XY,
			BackgroundColor3 = Color3.fromRGB(19, 19, 23),
			BackgroundTransparency = 0.08,
			Position = UDim2.new(1, -10, 0.5, 0),
			Font = Enum.Font.GothamBold,
			Text = tostring(props.count or 0),
			TextColor3 = active and accent or PALETTE.Muted,
			TextSize = 11,
		}, {
			Corner = e("UICorner", {
				CornerRadius = UDim.new(0, 999),
			}),
			Padding = e("UIPadding", {
				PaddingTop = UDim.new(0, 4),
				PaddingBottom = UDim.new(0, 4),
				PaddingLeft = UDim.new(0, 8),
				PaddingRight = UDim.new(0, 8),
			}),
		}),
	})
end

local function searchGlyph()
	return e("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(12, 8),
		Size = UDim2.fromOffset(18, 18),
	}, {
		Lens = e("Frame", {
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Position = UDim2.fromOffset(0, 0),
			Size = UDim2.fromOffset(11, 11),
		}, {
			Stroke = e("UIStroke", {
				Color = Color3.fromRGB(139, 146, 160),
				Thickness = 2,
			}),
			Corner = e("UICorner", {
				CornerRadius = UDim.new(1, 0),
			}),
		}),
		Handle = e("Frame", {
			AnchorPoint = Vector2.new(0.5, 0),
			BackgroundColor3 = Color3.fromRGB(139, 146, 160),
			BorderSizePixel = 0,
			Position = UDim2.fromOffset(11, 9),
			Rotation = -45,
			Size = UDim2.fromOffset(2, 8),
		}, {
			Corner = e("UICorner", {
				CornerRadius = UDim.new(0, 999),
			}),
		}),
	})
end

local function manifestTile(props)
	local item = props.item or {}
	local accent = item.accentColor or PALETTE.Cyan
	local interactive = item.interactive == true
	local hovered, pressed, handlers, hoverRef = useInteractiveState(interactive)
	local heldHover = hovered
	local heldEquipped = item.isEquipped and not hovered
	local heldScale = heldHover and 1.034 or (heldEquipped and 1.01 or 1)
	local tileBaseTop = accent:Lerp(Color3.fromRGB(72, 74, 87), 0.82)
	local tileBaseBottom = accent:Lerp(Color3.fromRGB(49, 52, 61), 0.9)
	local innerTileColor = accent:Lerp(Color3.fromRGB(59, 61, 71), 0.92)
	local previewPlateColor = accent:Lerp(Color3.fromRGB(78, 80, 91), 0.88)

	local tileProps = mergeProps({
		AutoButtonColor = false,
		BackgroundColor3 = accent:Lerp(Color3.fromRGB(43, 45, 57), 0.72),
		BorderSizePixel = 0,
		LayoutOrder = props.layoutOrder or 0,
		ref = hoverRef,
		Size = UDim2.fromOffset(128, 136),
		Text = "",
		[React.Event.Activated] = interactive and function()
			props.onActivated(item)
		end or nil,
	}, handlers)

	local previewChild = item.image and item.image ~= "" and e("ImageLabel", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		Image = item.image,
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(64, 64),
		ScaleType = Enum.ScaleType.Fit,
		ZIndex = 3,
	}) or (item.previewKind and e(PreviewViewport, {
		previewKind = item.previewKind,
		previewName = item.previewName,
		position = UDim2.fromScale(0.5, 0.5),
		size = UDim2.fromOffset(74, 74),
		zIndex = 3,
		fieldOfView = 34,
	})) or e("TextLabel", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, -10, 1, -10),
		Text = item.fallbackText or initials(item.displayName),
		TextColor3 = PALETTE.Cream,
		TextSize = 20,
		ZIndex = 3,
	})

	return e("TextButton", tileProps, {
		Scale = e("UIScale", {
			Scale = heldScale - (pressed and 0.018 or 0),
		}),
		Corner = e("UICorner", {
			CornerRadius = UDim.new(0, 10),
		}),
		Stroke = e("UIStroke", {
			Color = item.isEquipped and PALETTE.Cream or accent,
			Transparency = hovered and 0 or (item.isEquipped and 0.03 or 0.12),
			Thickness = hovered and 2.4 or (item.isEquipped and 2.2 or 1.8),
		}),
		Glow = e("UIStroke", {
			Color = accent,
			Transparency = hovered and 0.66 or (item.isEquipped and 0.82 or 0.92),
			Thickness = hovered and 4 or 3.4,
		}),
		Gradient = e("UIGradient", {
			Rotation = 90,
			Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, tileBaseTop),
				ColorSequenceKeypoint.new(1, tileBaseBottom),
			}),
		}),
		AccentBorder = e("Frame", {
			BackgroundColor3 = accent,
			BackgroundTransparency = hovered and 0.1 or 0.16,
			BorderSizePixel = 0,
			Position = UDim2.fromOffset(0, 0),
			Size = UDim2.fromScale(1, 1),
			ZIndex = 1,
		}, {
			Corner = e("UICorner", {
				CornerRadius = UDim.new(0, 10),
			}),
			Inner = e("Frame", {
				BackgroundColor3 = innerTileColor,
				BorderSizePixel = 0,
				Position = UDim2.fromOffset(3, 3),
				Size = UDim2.new(1, -6, 1, -6),
				ZIndex = 1,
			}, {
				Corner = e("UICorner", {
					CornerRadius = UDim.new(0, 8),
				}),
			}),
		}),
		PreviewPlate = e("Frame", {
			BackgroundColor3 = previewPlateColor,
			BorderSizePixel = 0,
			Position = UDim2.fromOffset(10, 12),
			Size = UDim2.new(1, -20, 0, 84),
			ZIndex = 2,
		}, {
			Corner = e("UICorner", {
				CornerRadius = UDim.new(0, 7),
			}),
			Stroke = e("UIStroke", {
				Color = accent,
				Transparency = hovered and 0.18 or 0.38,
				Thickness = hovered and 1.2 or 1,
			}),
			HoverWash = e("Frame", {
				BackgroundColor3 = accent,
				BackgroundTransparency = hovered and 0.74 or 0.88,
				BorderSizePixel = 0,
				Size = UDim2.fromScale(1, 1),
				ZIndex = 1,
			}, {
				Corner = e("UICorner", {
					CornerRadius = UDim.new(0, 7),
				}),
			}),
			Preview = previewChild,
		}),
		Name = e("TextLabel", {
			BackgroundTransparency = 1,
			Font = Enum.Font.GothamBold,
			Position = UDim2.fromOffset(10, 101),
			Size = UDim2.new(1, -20, 0, 20),
			Text = item.displayName or "",
			TextColor3 = PALETTE.Cream,
			TextSize = 12,
			TextTruncate = Enum.TextTruncate.AtEnd,
			TextWrapped = false,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 3,
		}),
		Quantity = e("TextLabel", {
			AnchorPoint = Vector2.new(1, 1),
			BackgroundTransparency = 1,
			Font = Enum.Font.Cartoon,
			Position = UDim2.new(1, -8, 1, -4),
			Size = UDim2.fromOffset(34, 18),
			Text = "x" .. tostring(math.max(1, item.quantity or 1)),
			TextColor3 = PALETTE.Cream,
			TextSize = 20,
			TextStrokeTransparency = 0.35,
			ZIndex = 4,
		}),
	})
end

local function footerCategoryCell(props)
	local accent = props.accentColor or PALETTE.Sea

	return e("Frame", {
		BackgroundTransparency = 1,
		LayoutOrder = props.layoutOrder or 0,
		Size = props.size or UDim2.new(0.333, -8, 1, 0),
	}, {
		Tab = e(categoryMenuTab, {
			label = props.label,
			count = props.count,
			active = props.active,
			accentColor = accent,
			size = UDim2.new(1, 0, 0, 36),
			onActivated = props.onActivated,
		}),
		Rail = e("Frame", {
			BackgroundColor3 = accent,
			BackgroundTransparency = props.active and 0 or 0.44,
			BorderSizePixel = 0,
			Position = UDim2.new(0, 0, 1, -8),
			Size = UDim2.new(1, 0, 0, 8),
			ZIndex = 8,
		}, {
			Corner = e("UICorner", {
				CornerRadius = UDim.new(0, 999),
			}),
		}),
	})
end

local function captainsLogRow(props)
	local entry = props.entry or {}
	local accent = entry.accentColor or PALETTE.Sea

	local previewChild = entry.image and entry.image ~= "" and e("ImageLabel", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		Image = entry.image,
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(64, 64),
		ScaleType = Enum.ScaleType.Fit,
		ZIndex = 3,
	}) or e("TextLabel", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, -10, 1, -10),
		Text = entry.fallbackText or initials(entry.displayName),
		TextColor3 = PALETTE.Cream,
		TextSize = 20,
		ZIndex = 3,
	})

	return e("Frame", {
		BackgroundColor3 = Color3.fromRGB(16, 22, 35),
		BackgroundTransparency = 0.02,
		BorderSizePixel = 0,
		LayoutOrder = props.layoutOrder or 0,
		Size = UDim2.new(1, 0, 0, 88),
	}, {
		Corner = e("UICorner", {
			CornerRadius = UDim.new(0, 12),
		}),
		Stroke = e("UIStroke", {
			Color = accent,
			Transparency = 0.16,
			Thickness = 1.35,
		}),
		Glow = e("UIStroke", {
			Color = accent,
			Transparency = 0.93,
			Thickness = 2,
		}),
		Accent = e("Frame", {
			BackgroundColor3 = accent,
			BorderSizePixel = 0,
			Position = UDim2.fromOffset(0, 0),
			Size = UDim2.new(0, 5, 1, 0),
			ZIndex = 2,
		}, {
			Corner = e("UICorner", {
				CornerRadius = UDim.new(0, 12),
			}),
		}),
		PreviewPlate = e("Frame", {
			BackgroundColor3 = accent:Lerp(Color3.fromRGB(59, 63, 78), 0.9),
			BorderSizePixel = 0,
			Position = UDim2.fromOffset(16, 12),
			Size = UDim2.fromOffset(72, 64),
			ZIndex = 2,
		}, {
			Corner = e("UICorner", {
				CornerRadius = UDim.new(0, 10),
			}),
			Stroke = e("UIStroke", {
				Color = accent,
				Transparency = 0.42,
				Thickness = 1,
			}),
			Preview = previewChild,
		}),
		Name = e("TextLabel", {
			BackgroundTransparency = 1,
			Font = Enum.Font.Cartoon,
			Position = UDim2.fromOffset(102, 10),
			Size = UDim2.new(1, -340, 0, 28),
			Text = entry.displayName or "",
			TextColor3 = PALETTE.Cream,
			TextSize = 24,
			TextStrokeTransparency = 0.62,
			TextTruncate = Enum.TextTruncate.AtEnd,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 3,
		}),
		Subtitle = e("TextLabel", {
			BackgroundTransparency = 1,
			Font = Enum.Font.Gotham,
			Position = UDim2.fromOffset(104, 38),
			Size = UDim2.new(1, -360, 0, 18),
			Text = string.format("%s  |  %s", tostring(entry.subtitle or "Brainrot"), tostring(entry.standName or "Stand")),
			TextColor3 = Color3.fromRGB(181, 191, 210),
			TextSize = 12,
			TextTruncate = Enum.TextTruncate.AtEnd,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 3,
		}),
		Footer = e("TextLabel", {
			BackgroundTransparency = 1,
			Font = Enum.Font.GothamBold,
			Position = UDim2.fromOffset(104, 58),
			Size = UDim2.new(1, -360, 0, 16),
			Text = string.format(
				"Bounty: %s  |  %s D ready",
				formatNumber(entry.bounty or 0),
				formatNumber(entry.collectable or 0)
			),
			TextColor3 = accent,
			TextSize = 12,
			TextTruncate = Enum.TextTruncate.AtEnd,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 3,
		}),
		IncomeLabel = e("TextLabel", {
			AnchorPoint = Vector2.new(1, 0),
			BackgroundTransparency = 1,
			Font = Enum.Font.GothamBold,
			Position = UDim2.new(1, -18, 16 / 88, 0),
			Size = UDim2.fromOffset(150, 14),
			Text = "Making",
			TextColor3 = PALETTE.Muted,
			TextSize = 11,
			TextXAlignment = Enum.TextXAlignment.Right,
			ZIndex = 3,
		}),
		IncomeValue = e("TextLabel", {
			AnchorPoint = Vector2.new(1, 0),
			BackgroundTransparency = 1,
			Font = Enum.Font.Cartoon,
			Position = UDim2.new(1, -18, 33 / 88, 0),
			Size = UDim2.fromOffset(180, 30),
			Text = string.format("%s D / tick", formatNumber(entry.incomePerTick or 0)),
			TextColor3 = PALETTE.Cream,
			TextSize = 24,
			TextStrokeTransparency = 0.58,
			TextXAlignment = Enum.TextXAlignment.Right,
			ZIndex = 3,
		}),
	})
end

local function titleRegistryRow(props)
	local entry = props.entry or {}
	local unlocked = entry.unlocked == true or entry.isEquipped == true
	local accent = entry.accentColor or (unlocked and PALETTE.Gold or PALETTE.Steel)
	local surfaceColor = entry.surfaceColor or Color3.fromRGB(16, 22, 35)
	local surfaceColor2 = entry.surfaceColor2 or Color3.fromRGB(10, 15, 25)
	local sealColor = entry.sealColor or accent:Lerp(Color3.fromRGB(52, 57, 74), unlocked and 0.62 or 0.82)
	local stateFill = unlocked and (entry.stateColor or accent) or Color3.fromRGB(44, 51, 67)
	local stateTextColor = unlocked and PALETTE.Ink or PALETTE.Cream

	return e("Frame", {
		BackgroundColor3 = surfaceColor,
		BackgroundTransparency = 0.02,
		BorderSizePixel = 0,
		LayoutOrder = props.layoutOrder or 0,
		Size = UDim2.new(1, 0, 0, 104),
	}, {
		Corner = e("UICorner", {
			CornerRadius = UDim.new(0, 12),
		}),
		Stroke = e("UIStroke", {
			Color = accent,
			Transparency = unlocked and 0.12 or 0.34,
			Thickness = unlocked and 1.35 or 1.1,
		}),
		Glow = e("UIStroke", {
			Color = accent,
			Transparency = unlocked and 0.9 or 0.96,
			Thickness = 2,
		}),
		Gradient = e("UIGradient", {
			Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, surfaceColor),
				ColorSequenceKeypoint.new(1, surfaceColor2),
			}),
			Rotation = 90,
		}),
		Accent = e("Frame", {
			BackgroundColor3 = accent,
			BorderSizePixel = 0,
			Position = UDim2.fromOffset(0, 0),
			Size = UDim2.new(0, 5, 1, 0),
			ZIndex = 2,
		}, {
			Corner = e("UICorner", {
				CornerRadius = UDim.new(0, 12),
			}),
		}),
		Seal = e("Frame", {
			BackgroundColor3 = sealColor,
			BorderSizePixel = 0,
			Position = UDim2.fromOffset(16, 16),
			Size = UDim2.fromOffset(72, 72),
			ZIndex = 2,
		}, {
			Corner = e("UICorner", {
				CornerRadius = UDim.new(0, 14),
			}),
			Stroke = e("UIStroke", {
				Color = accent,
				Transparency = unlocked and 0.26 or 0.58,
				Thickness = 1,
			}),
			Mark = e("TextLabel", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				BackgroundTransparency = 1,
				Font = Enum.Font.Cartoon,
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.new(1, -12, 1, -12),
				Text = unlocked and (entry.fallbackText or initials(entry.displayName)) or "?",
				TextColor3 = PALETTE.Cream,
				TextSize = 30,
				TextStrokeTransparency = 0.56,
				ZIndex = 3,
			}),
		}),
		Name = e("TextLabel", {
			BackgroundTransparency = 1,
			Font = Enum.Font.Cartoon,
			Position = UDim2.fromOffset(104, 10),
			Size = UDim2.new(1, -250, 0, 28),
			Text = entry.displayName or "",
			TextColor3 = PALETTE.Cream,
			TextSize = 24,
			TextStrokeTransparency = 0.62,
			TextTruncate = Enum.TextTruncate.AtEnd,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 3,
		}),
		StateChip = e("TextLabel", {
			AnchorPoint = Vector2.new(1, 0),
			AutomaticSize = Enum.AutomaticSize.XY,
			BackgroundColor3 = stateFill,
			BackgroundTransparency = unlocked and 0.02 or 0.16,
			Position = UDim2.new(1, -18, 14 / 104, 0),
			Font = Enum.Font.GothamBold,
			Text = string.upper(entry.stateText or (unlocked and "Unlocked" or "Locked")),
			TextColor3 = stateTextColor,
			TextSize = 10,
			ZIndex = 3,
		}, {
			Corner = e("UICorner", {
				CornerRadius = UDim.new(0, 999),
			}),
			Padding = e("UIPadding", {
				PaddingTop = UDim.new(0, 5),
				PaddingBottom = UDim.new(0, 5),
				PaddingLeft = UDim.new(0, 10),
				PaddingRight = UDim.new(0, 10),
			}),
		}),
		Subtitle = e("TextLabel", {
			BackgroundTransparency = 1,
			Font = Enum.Font.GothamBold,
			Position = UDim2.fromOffset(106, 38),
			Size = UDim2.new(1, -268, 0, 16),
			Text = tostring(entry.subtitle or "Title"),
			TextColor3 = accent,
			TextSize = 11,
			TextTruncate = Enum.TextTruncate.AtEnd,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 3,
		}),
		Description = e("TextLabel", {
			BackgroundTransparency = 1,
			Font = Enum.Font.Gotham,
			Position = UDim2.fromOffset(106, 56),
			Size = UDim2.new(1, -176, 0, 16),
			Text = tostring(entry.description or ""),
			TextColor3 = Color3.fromRGB(181, 191, 210),
			TextSize = 12,
			TextTruncate = Enum.TextTruncate.AtEnd,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 3,
		}),
		Requirement = e("TextLabel", {
			BackgroundTransparency = 1,
			Font = Enum.Font.GothamMedium,
			Position = UDim2.fromOffset(106, 76),
			Size = UDim2.new(1, -176, 0, 16),
			Text = "Requirement: " .. tostring(entry.requirementText or ""),
			TextColor3 = unlocked and PALETTE.Cream or PALETTE.Muted,
			TextSize = 11,
			TextTruncate = Enum.TextTruncate.AtEnd,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 3,
		}),
		Rank = (entry.currentRank or entry.rankLabel) and e("TextLabel", {
			AnchorPoint = Vector2.new(1, 1),
			BackgroundTransparency = 1,
			Font = Enum.Font.GothamBold,
			Position = UDim2.new(1, -18, 1, -12),
			Size = UDim2.fromOffset(152, 16),
			Text = entry.currentRank and ("Rank " .. formatLeaderboardRank(entry.currentRank))
				or tostring(entry.rankLabel or ""),
			TextColor3 = accent,
			TextSize = 11,
			TextXAlignment = Enum.TextXAlignment.Right,
			ZIndex = 3,
		}) or nil,
		Action = entry.actionLabel and e("TextButton", {
			AnchorPoint = Vector2.new(1, 0.5),
			AutoButtonColor = false,
			BackgroundColor3 = entry.isEquipped and Color3.fromRGB(44, 54, 72) or accent,
			BackgroundTransparency = entry.canToggleEquipped and 0.02 or 0.28,
			BorderSizePixel = 0,
			Position = UDim2.new(1, -18, 0.5, 0),
			Size = UDim2.fromOffset(104, 34),
			Text = tostring(entry.actionLabel),
			TextColor3 = entry.isEquipped and PALETTE.Cream or Color3.fromRGB(14, 21, 22),
			TextSize = 16,
			Font = Enum.Font.GothamBold,
			ZIndex = 3,
			[React.Event.Activated] = function()
				if props.onToggleTitle then
					props.onToggleTitle(entry)
				end
			end,
		}, {
			Corner = e("UICorner", {
				CornerRadius = UDim.new(0, 10),
			}),
			Stroke = e("UIStroke", {
				Color = accent,
				Transparency = entry.isEquipped and 0.08 or 0.72,
				Thickness = entry.isEquipped and 1.2 or 1,
			}),
		}) or nil,
	})
end

local function shipUpgradeModal(props)
	local modal = props.modal or {}
	local lines = modal.Lines or modal.lines or {}
	local accent = modal.IsError and PALETTE.Rose or (modal.IsMaxLevel and PALETTE.Gold or PALETTE.Green)
	local listChildren = {
		List = e("UIListLayout", {
			FillDirection = Enum.FillDirection.Vertical,
			Padding = UDim.new(0, 8),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	}

	if #lines == 0 then
		lines = { "Ship upgraded successfully." }
	end

	for index, line in ipairs(lines) do
		listChildren["Gain" .. tostring(index)] = e("Frame", {
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundColor3 = PALETTE.PanelAlt,
			BackgroundTransparency = 0.04,
			BorderSizePixel = 0,
			LayoutOrder = index,
			Size = UDim2.new(1, 0, 0, 0),
			ZIndex = 84,
		}, {
			Corner = e("UICorner", {
				CornerRadius = UDim.new(0, 12),
			}),
			Stroke = e("UIStroke", {
				Color = accent,
				Transparency = 0.72,
				Thickness = 1,
			}),
			Padding = e("UIPadding", {
				PaddingTop = UDim.new(0, 10),
				PaddingBottom = UDim.new(0, 10),
				PaddingLeft = UDim.new(0, 14),
				PaddingRight = UDim.new(0, 14),
			}),
			Dot = e("Frame", {
				BackgroundColor3 = accent,
				BorderSizePixel = 0,
				Position = UDim2.fromOffset(0, 7),
				Size = UDim2.fromOffset(8, 8),
				ZIndex = 85,
			}, {
				Corner = e("UICorner", {
					CornerRadius = UDim.new(0, 999),
				}),
			}),
			Text = e("TextLabel", {
				AutomaticSize = Enum.AutomaticSize.Y,
				BackgroundTransparency = 1,
				Font = Enum.Font.GothamMedium,
				Position = UDim2.fromOffset(18, 0),
				Size = UDim2.new(1, -18, 0, 0),
				Text = tostring(line),
				TextColor3 = PALETTE.Text,
				TextSize = 16,
				TextWrapped = true,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextYAlignment = Enum.TextYAlignment.Top,
				ZIndex = 85,
			}),
		})
	end

	return e("ScreenGui", {
		Name = "ReactShipUpgradeModal",
		DisplayOrder = 500,
		IgnoreGuiInset = true,
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}, {
		ModalRoot = e("Frame", {
			Active = true,
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			ZIndex = 70,
		}, {
			Backdrop = e("Frame", {
				Active = true,
				BackgroundColor3 = PALETTE.Background,
				BackgroundTransparency = 0.26,
				BorderSizePixel = 0,
				Size = UDim2.fromScale(1, 1),
				ZIndex = 70,
			}),
			InputBlocker = e("Frame", {
				Active = true,
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				Selectable = false,
				Size = UDim2.fromScale(1, 1),
				ZIndex = 71,
				[React.Event.InputBegan] = function() end,
				[React.Event.InputChanged] = function() end,
				[React.Event.InputEnded] = function() end,
			}),
			Panel = e("Frame", {
				Active = true,
				AnchorPoint = Vector2.new(0.5, 0.5),
				AutomaticSize = Enum.AutomaticSize.Y,
				BackgroundColor3 = PALETTE.InkSoft,
				BorderSizePixel = 0,
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromOffset(500, 0),
				ZIndex = 80,
			}, {
				SizeConstraint = e("UISizeConstraint", {
					MaxSize = Vector2.new(540, 720),
					MinSize = Vector2.new(440, 0),
				}),
				Corner = e("UICorner", {
					CornerRadius = UDim.new(0, 18),
				}),
				Stroke = e("UIStroke", {
					Color = accent,
					Transparency = 0.42,
					Thickness = 1.2,
				}),
				Gradient = e("UIGradient", {
					Rotation = 90,
					Color = ColorSequence.new({
						ColorSequenceKeypoint.new(0, Color3.fromRGB(22, 33, 56)),
						ColorSequenceKeypoint.new(1, Color3.fromRGB(13, 21, 38)),
					}),
				}),
				Padding = e("UIPadding", {
					PaddingTop = UDim.new(0, 18),
					PaddingBottom = UDim.new(0, 18),
					PaddingLeft = UDim.new(0, 18),
					PaddingRight = UDim.new(0, 18),
				}),
				List = e("UIListLayout", {
					FillDirection = Enum.FillDirection.Vertical,
					Padding = UDim.new(0, 12),
					SortOrder = Enum.SortOrder.LayoutOrder,
				}),
				Eyebrow = e("TextLabel", {
					BackgroundTransparency = 1,
					Font = Enum.Font.GothamBold,
					LayoutOrder = 1,
					Size = UDim2.new(1, 0, 0, 16),
					Text = tostring(modal.AccentText or "Ship Upgrade Complete"),
					TextColor3 = accent,
					TextSize = 12,
					TextXAlignment = Enum.TextXAlignment.Left,
					ZIndex = 81,
				}),
				Title = e("TextLabel", {
					AutomaticSize = Enum.AutomaticSize.Y,
					BackgroundTransparency = 1,
					Font = Enum.Font.Cartoon,
					LayoutOrder = 2,
					Size = UDim2.new(1, 0, 0, 0),
					Text = tostring(modal.Title or "Ship upgraded"),
					TextColor3 = PALETTE.Cream,
					TextSize = 34,
					TextStrokeTransparency = 0.62,
					TextWrapped = true,
					TextXAlignment = Enum.TextXAlignment.Left,
					TextYAlignment = Enum.TextYAlignment.Top,
					ZIndex = 81,
				}),
				Body = e("Frame", {
					AutomaticSize = Enum.AutomaticSize.Y,
					BackgroundTransparency = 1,
					LayoutOrder = 3,
					Size = UDim2.new(1, 0, 0, 0),
					ZIndex = 81,
				}, listChildren),
				ActionRow = e("Frame", {
					BackgroundTransparency = 1,
					LayoutOrder = 4,
					Size = UDim2.new(1, 0, 0, 44),
					ZIndex = 81,
				}, {
					Okay = e("TextButton", {
						AnchorPoint = Vector2.new(1, 0),
						AutoButtonColor = false,
						BackgroundColor3 = accent,
						BorderSizePixel = 0,
						Position = UDim2.new(1, 0, 0, 0),
						Size = UDim2.fromOffset(136, 42),
						Text = "Okay",
						TextColor3 = Color3.fromRGB(14, 21, 22),
						TextSize = 18,
						Font = Enum.Font.GothamBold,
						ZIndex = 82,
						[React.Event.Activated] = props.onDismiss,
					}, {
						Corner = e("UICorner", {
							CornerRadius = UDim.new(0, 12),
						}),
						Stroke = e("UIStroke", {
							Color = Color3.fromRGB(255, 255, 255),
							Transparency = 0.86,
						}),
					}),
				}),
			}),
		}),
	})
end

local function App(props)
	local summary = props.summary or {}
	local titles = props.titles or {}
	local activeView = props.activeView or "Inventory"
	local showingCaptainLog = activeView == "CaptainLog"
	local showingTitles = activeView == "Titles"
	local showingInventory = not showingCaptainLog and not showingTitles
	local toggleLayout = props.toggleLayout or {}
	local dockToggleLeft = toggleLayout.dock == "hotbarLeft"
	local dockToggleSlot = toggleLayout.dock == "hotbarSlot"
	local toggleSlotIndex = math.max(1, math.floor(tonumber(toggleLayout.slotIndex) or 5))
	local toggleWidth = dockToggleLeft and ((toggleLayout.size and toggleLayout.size.X.Offset) or 74) or 0
	local toggleGap = dockToggleLeft and 20 or 0
	local hotbarSlotCount = math.max(1, #(props.hotbarSlots or {}))
	local hotbarSlotWidth = 64
	local hotbarSlotGap = 10
	local hotbarWidth = hotbarSlotCount * hotbarSlotWidth
		+ math.max(0, hotbarSlotCount - 1) * hotbarSlotGap
	local bottomBarWidth = dockToggleLeft and (toggleWidth + toggleGap + hotbarWidth) or hotbarWidth
	local toggleSlotX = math.max(0, (toggleSlotIndex - 1) * (hotbarSlotWidth + hotbarSlotGap))
	local resolvedTogglePosition = dockToggleLeft and UDim2.fromOffset(0, 20)
		or (dockToggleSlot and UDim2.fromOffset(toggleSlotX, 20) or toggleLayout.position)
	local hotbarOffsetX = dockToggleLeft and (toggleWidth + toggleGap) or 0
	local bottomBarZIndex = props.isOpen and 2 or 10
	local filledHotbarCount = 0
	local activeAccent = PALETTE.Sea

	for _, slot in ipairs(props.hotbarSlots or {}) do
		if slot.item then
			filledHotbarCount += 1
		end
	end

	for _, category in ipairs(props.categories or {}) do
		if category.key == props.activeCategory then
			activeAccent = category.accentColor or activeAccent
			break
		end
	end

	if showingCaptainLog then
		activeAccent = PALETTE.Orange
	elseif showingTitles then
		activeAccent = PALETTE.Gold
	end

	local children = {
		BottomBar = e("Frame", {
			AnchorPoint = Vector2.new(0.5, 1),
			BackgroundTransparency = 1,
			Position = UDim2.new(0.5, 0, 1, -20),
			Size = UDim2.fromOffset(bottomBarWidth, 92),
			ZIndex = bottomBarZIndex,
		}, {
			Toggle = e(inventoryToggleButton, {
				toggleLayout = {
					anchorPoint = Vector2.new(0, 0),
					position = resolvedTogglePosition,
					size = toggleLayout.size,
					compact = toggleLayout.compact,
				},
				toggleIcon = props.toggleIcon,
				zIndexBase = bottomBarZIndex,
				onToggle = props.onToggle,
			}),
			Hotbar = e("Frame", {
				BackgroundTransparency = 1,
				Position = UDim2.fromOffset(hotbarOffsetX, 0),
				Size = UDim2.fromOffset(hotbarWidth, 84),
				ZIndex = bottomBarZIndex,
			}, {
				Label = e("TextLabel", {
					BackgroundTransparency = 1,
					Font = Enum.Font.GothamBold,
					Position = UDim2.fromOffset(0, 0),
					Size = UDim2.new(1, 0, 0, 14),
					Text = "Quick Equip",
					TextColor3 = PALETTE.Steel,
					TextSize = 11,
					TextXAlignment = Enum.TextXAlignment.Left,
					ZIndex = bottomBarZIndex + 1,
				}),
				Scroller = e("ScrollingFrame", {
					AutomaticCanvasSize = Enum.AutomaticSize.X,
					BackgroundTransparency = 1,
					BorderSizePixel = 0,
					CanvasSize = UDim2.new(),
					Position = UDim2.fromOffset(0, 20),
					ScrollBarImageTransparency = 1,
					ScrollBarThickness = 0,
					ScrollingDirection = Enum.ScrollingDirection.X,
					Size = UDim2.new(1, 0, 0, 64),
					ZIndex = bottomBarZIndex + 1,
				}, (function()
					local slotChildren = {
						List = e("UIListLayout", {
							FillDirection = Enum.FillDirection.Horizontal,
							Padding = UDim.new(0, hotbarSlotGap),
							SortOrder = Enum.SortOrder.LayoutOrder,
							VerticalAlignment = Enum.VerticalAlignment.Center,
						}),
					}

					for index, slot in ipairs(props.hotbarSlots or {}) do
						slotChildren["Slot" .. tostring(index)] = e(hotbarSlot, {
							slot = slot,
							layoutOrder = index,
							zIndexBase = bottomBarZIndex,
							onActivated = props.onActivateItem,
						})
					end

					return slotChildren
				end)()),
			}),
		}),
	}
	local modalPanelChildren = nil

	if props.isOpen then
		local gridChildren = {
			Grid = e("UIGridLayout", {
				CellPadding = UDim2.fromOffset(10, 10),
				CellSize = UDim2.fromOffset(128, 136),
				FillDirectionMaxCells = 6,
				HorizontalAlignment = Enum.HorizontalAlignment.Left,
				SortOrder = Enum.SortOrder.LayoutOrder,
				VerticalAlignment = Enum.VerticalAlignment.Top,
			}),
		}

		for index, item in ipairs(props.items or {}) do
			gridChildren["Item" .. tostring(index)] = e(manifestTile, {
				item = item,
				layoutOrder = index,
				onActivated = props.onActivateItem,
			})
		end

		local footerChildren = {
			List = e("UIListLayout", {
				FillDirection = Enum.FillDirection.Horizontal,
				Padding = UDim.new(0, 10),
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),
		}

		local categoryCount = math.max(1, #(props.categories or {}))
		local footerCellOffset = math.floor((((categoryCount - 1) * 10) / categoryCount) + 0.5)
		for index, category in ipairs(props.categories or {}) do
			footerChildren["Cell" .. tostring(index)] = e(footerCategoryCell, {
				layoutOrder = index,
				label = category.label,
				count = category.count,
				active = category.key == props.activeCategory,
				accentColor = category.accentColor,
				size = UDim2.new(1 / categoryCount, -footerCellOffset, 1, 0),
				onActivated = function()
					props.onSelectCategory(category.key)
				end,
			})
		end

		local topModeChildren = {
			List = e("UIListLayout", {
				FillDirection = Enum.FillDirection.Horizontal,
				Padding = UDim.new(0, 8),
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),
		}

		local modeTabs = {
			{ key = "Inventory", label = "Inventory", fillColor3 = PALETTE.Sea, size = UDim2.fromOffset(124, 38) },
			{ key = "CaptainLog", label = "Captain's Log", fillColor3 = PALETTE.Orange, size = UDim2.fromOffset(152, 38) },
			{ key = "Titles", label = "Titles", fillColor3 = PALETTE.Gold, size = UDim2.fromOffset(112, 38) },
		}

		for index, mode in ipairs(modeTabs) do
			topModeChildren["Mode" .. tostring(index)] = e(modeTab, {
				layoutOrder = index,
				label = mode.label,
				fillColor3 = mode.fillColor3,
				active = activeView == mode.key,
				size = mode.size,
				onActivated = function()
					props.onSelectView(mode.key)
				end,
			})
		end

		local ledgerChildren = {
			List = e("UIListLayout", {
				FillDirection = Enum.FillDirection.Vertical,
				Padding = UDim.new(0, 3),
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),
		}

		local ledgerEntries
		if showingTitles then
			ledgerEntries = {
				{
					label = "Equipped Title",
					value = tostring(titles.equippedTitleLabel or "None"),
					valueColor3 = titles.equippedTitleColor or PALETTE.Cream,
					multiLine = true,
				},
				{
					label = "Unlocked Titles",
					value = string.format("%d / %d", titles.unlockedCount or 0, titles.totalCount or 0),
					valueColor3 = PALETTE.Gold,
				},
				{
					label = "Persistent Titles",
					value = tostring(titles.persistentUnlockedCount or 0),
					valueColor3 = PALETTE.Sea,
				},
				{
					label = "Dynamic Titles",
					value = tostring(titles.dynamicUnlockedCount or 0),
					valueColor3 = PALETTE.Orange,
				},
				{
					label = "Bounty Rank",
					value = tostring(titles.bountyRankLabel or formatLeaderboardRank(titles.bountyRank)),
					valueColor3 = PALETTE.Cyan,
				},
			}
		else
			ledgerEntries = {
				{ label = "Total Bounty", value = formatNumber(summary.bounty or 0), valueColor3 = PALETTE.Gold },
				{ label = "Ship Crew Bounty", value = formatNumber(summary.crewBounty or 0), valueColor3 = PALETTE.Orange },
				{ label = "Extraction Bounty", value = formatNumber(summary.extractionBounty or 0), valueColor3 = PALETTE.Green },
				{ label = "Doubloons", value = formatNumber(summary.doubloons or 0) .. " D", valueColor3 = PALETTE.Gold },
				{ label = "Rebirths", value = tostring(summary.rebirths or 0), valueColor3 = PALETTE.Sea },
				{ label = "Multiplier", value = tostring(summary.multiplier or "1.00x"), valueColor3 = PALETTE.Cyan },
				{ label = "Unopened Chests", value = tostring(summary.chests or 0), valueColor3 = PALETTE.Green },
				{ label = "Timber", value = formatNumber(summary.timber or 0), valueColor3 = Color3.fromRGB(112, 220, 140) },
				{ label = "Iron", value = formatNumber(summary.iron or 0), valueColor3 = Color3.fromRGB(91, 170, 255) },
				{ label = "Ancient Timber", value = formatNumber(summary.ancientTimber or 0), valueColor3 = Color3.fromRGB(255, 187, 74) },
			}
		end

		for index, entry in ipairs(ledgerEntries) do
			ledgerChildren["Entry" .. tostring(index)] = e(ledgerLine, {
				layoutOrder = index,
				label = entry.label,
				value = entry.value,
				valueColor3 = entry.valueColor3,
				multiLine = entry.multiLine,
			})
		end

		local captainLogChildren = {
			List = e("UIListLayout", {
				FillDirection = Enum.FillDirection.Vertical,
				Padding = UDim.new(0, 10),
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),
		}

		for index, entry in ipairs((props.captainLog and props.captainLog.entries) or {}) do
			captainLogChildren["Row" .. tostring(index)] = e(captainsLogRow, {
				entry = entry,
				layoutOrder = index,
			})
		end

		local titleChildren = {
			List = e("UIListLayout", {
				FillDirection = Enum.FillDirection.Vertical,
				Padding = UDim.new(0, 10),
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),
		}

		for index, entry in ipairs((props.titles and props.titles.entries) or {}) do
			titleChildren["Row" .. tostring(index)] = e(titleRegistryRow, {
				entry = entry,
				layoutOrder = index,
				onToggleTitle = props.onToggleTitle,
			})
		end

		modalPanelChildren = {
			SizeConstraint = e("UISizeConstraint", {
				MaxSize = Vector2.new(1180, 760),
				MinSize = Vector2.new(860, 560),
			}),
			Shell = e("Frame", {
				BackgroundColor3 = Color3.fromRGB(17, 27, 46),
				BorderSizePixel = 0,
				ClipsDescendants = true,
				Size = UDim2.fromScale(1, 1),
				ZIndex = 6,
			}, {
				Corner = e("UICorner", {
					CornerRadius = UDim.new(0, 26),
				}),
				Stroke = e("UIStroke", {
					Color = Color3.fromRGB(75, 107, 155),
					Transparency = 0.14,
					Thickness = 1.7,
				}),
				Gradient = e("UIGradient", {
					Rotation = 90,
					Color = ColorSequence.new({
						ColorSequenceKeypoint.new(0, Color3.fromRGB(24, 38, 63)),
						ColorSequenceKeypoint.new(0.45, Color3.fromRGB(15, 24, 42)),
						ColorSequenceKeypoint.new(1, Color3.fromRGB(9, 16, 29)),
					}),
				}),
				InnerGlow = e("Frame", {
					BackgroundColor3 = Color3.fromRGB(56, 86, 136),
					BackgroundTransparency = 0.95,
					BorderSizePixel = 0,
					Position = UDim2.fromOffset(12, 12),
					Size = UDim2.new(1, -24, 1, -24),
					ZIndex = 6,
				}, {
					Corner = e("UICorner", {
						CornerRadius = UDim.new(0, 22),
					}),
					Stroke = e("UIStroke", {
						Color = Color3.fromRGB(88, 123, 181),
						Transparency = 0.86,
					}),
				}),
				TopTabs = e("Frame", {
					AnchorPoint = Vector2.new(0, 0),
					BackgroundTransparency = 1,
					Position = UDim2.fromOffset(24, 16),
					Size = UDim2.fromOffset(412, 40),
					ZIndex = 8,
				}, topModeChildren),
				Close = e("TextButton", {
					AnchorPoint = Vector2.new(1, 0),
					AutoButtonColor = false,
					BackgroundColor3 = Color3.fromRGB(22, 16, 24),
					BorderSizePixel = 0,
					Position = UDim2.new(1, -32, 0, 16),
					Size = UDim2.fromOffset(38, 38),
					Text = "X",
					TextColor3 = PALETTE.Cream,
					TextSize = 18,
					Font = Enum.Font.Cartoon,
					ZIndex = 8,
					[React.Event.Activated] = props.onToggle,
				}, {
					Corner = e("UICorner", {
						CornerRadius = UDim.new(0, 12),
					}),
					Stroke = e("UIStroke", {
						Color = Color3.fromRGB(58, 54, 74),
						Transparency = 0.04,
					}),
				}),
				HeaderDivider = e("Frame", {
					BackgroundColor3 = Color3.fromRGB(87, 121, 176),
					BackgroundTransparency = 0.54,
					BorderSizePixel = 0,
					Position = UDim2.fromOffset(24, 68),
					Size = UDim2.new(1, -56, 0, 2),
					ZIndex = 7,
				}, {
					Corner = e("UICorner", {
						CornerRadius = UDim.new(0, 999),
					}),
				}),
				LeftPanel = e("Frame", {
					BackgroundColor3 = Color3.fromRGB(20, 31, 52),
					BackgroundTransparency = 0.03,
					BorderSizePixel = 0,
					Position = UDim2.fromOffset(26, 90),
					Size = UDim2.new(0, 240, 1, -116),
					ZIndex = 7,
				}, {
					Corner = e("UICorner", {
						CornerRadius = UDim.new(0, 10),
					}),
					Stroke = e("UIStroke", {
						Color = Color3.fromRGB(89, 121, 173),
						Transparency = 0.26,
						Thickness = 1.2,
					}),
					Gradient = e("UIGradient", {
						Rotation = 100,
						Color = ColorSequence.new({
							ColorSequenceKeypoint.new(0, Color3.fromRGB(31, 45, 72)),
							ColorSequenceKeypoint.new(1, Color3.fromRGB(18, 28, 47)),
						}),
					}),
					Title = e("TextLabel", {
						BackgroundTransparency = 1,
						Font = Enum.Font.Cartoon,
						Position = UDim2.fromOffset(16, 14),
						Size = UDim2.new(1, -32, 0, 28),
						Text = showingTitles and "Title Registry" or "Captain's Ledger",
						TextColor3 = PALETTE.Cream,
						TextSize = 28,
						TextStrokeTransparency = 0.6,
						TextXAlignment = Enum.TextXAlignment.Left,
						ZIndex = 8,
					}),
					Subtitle = e("TextLabel", {
						BackgroundTransparency = 1,
						Font = Enum.Font.Gotham,
						Position = UDim2.fromOffset(16, 44),
						Size = UDim2.new(1, -32, 0, 30),
						Text = showingTitles
								and "Honor marks tied to your long-term feats and current bounty rank."
							or "Current haul and ship stores at a glance.",
						TextColor3 = Color3.fromRGB(178, 189, 211),
						TextSize = 12,
						TextWrapped = true,
						TextXAlignment = Enum.TextXAlignment.Left,
						TextYAlignment = Enum.TextYAlignment.Top,
						ZIndex = 8,
					}),
					Divider = e("Frame", {
						BackgroundColor3 = Color3.fromRGB(67, 92, 136),
						BackgroundTransparency = 0.2,
						BorderSizePixel = 0,
						Position = UDim2.fromOffset(16, 84),
						Size = UDim2.new(1, -32, 0, 2),
						ZIndex = 8,
					}, {
						Corner = e("UICorner", {
							CornerRadius = UDim.new(0, 999),
						}),
					}),
					Stats = e("Frame", {
						BackgroundTransparency = 1,
						Position = UDim2.fromOffset(16, 102),
						Size = UDim2.new(1, -32, 1, -118),
						ZIndex = 8,
					}, ledgerChildren),
				}),
				MainPanel = e("Frame", {
					BackgroundColor3 = Color3.fromRGB(18, 28, 47),
					BackgroundTransparency = 0.02,
					BorderSizePixel = 0,
					Position = UDim2.fromOffset(286, 90),
					Size = showingInventory and UDim2.new(1, -312, 1, -186) or UDim2.new(1, -312, 1, -116),
					ZIndex = 7,
				}, {
					Corner = e("UICorner", {
						CornerRadius = UDim.new(0, 12),
					}),
					Stroke = e("UIStroke", {
						Color = Color3.fromRGB(88, 121, 173),
						Transparency = 0.2,
						Thickness = 1.25,
					}),
					Gradient = e("UIGradient", {
						Rotation = 100,
						Color = ColorSequence.new({
							ColorSequenceKeypoint.new(0, Color3.fromRGB(28, 43, 70)),
							ColorSequenceKeypoint.new(1, Color3.fromRGB(18, 28, 47)),
						}),
					}),
					Eyebrow = e("TextLabel", {
						BackgroundTransparency = 1,
						Font = Enum.Font.GothamBold,
						Position = UDim2.fromOffset(18, 12),
						Size = UDim2.new(1, -320, 0, 14),
						Text = showingCaptainLog and "Ship Income Overview"
							or (showingTitles and "Crew Honors" or "Captain's Hold"),
						TextColor3 = activeAccent,
						TextSize = 12,
						TextXAlignment = Enum.TextXAlignment.Left,
						ZIndex = 8,
					}),
					Title = e("TextLabel", {
						BackgroundTransparency = 1,
						Font = Enum.Font.Cartoon,
						Position = UDim2.fromOffset(18, 22),
						Size = UDim2.new(1, -320, 0, 30),
						Text = showingCaptainLog and "Captain's Log"
							or (showingTitles and "Titles" or (props.activeCategoryLabel or "Inventory")),
						TextColor3 = PALETTE.Cream,
						TextSize = 34,
						TextStrokeTransparency = 0.58,
						TextStrokeColor3 = Color3.fromRGB(11, 12, 17),
						TextXAlignment = Enum.TextXAlignment.Left,
						ZIndex = 8,
					}),
					Info = e("TextLabel", {
						BackgroundTransparency = 1,
						Font = Enum.Font.Gotham,
						Position = UDim2.fromOffset(18, 56),
						Size = UDim2.new(1, -320, 0, 18),
						Text = showingCaptainLog
							and string.format(
								"%d of %d placed brainrots visible in the log",
								(props.captainLog and props.captainLog.filteredCount) or 0,
								(props.captainLog and props.captainLog.totalCount) or 0
							)
							or (showingTitles
								and string.format(
									"%d of %d titles visible, %d unlocked",
									(props.titles and props.titles.filteredCount) or 0,
									(props.titles and props.titles.totalCount) or 0,
									(props.titles and props.titles.unlockedCount) or 0
								)
								or string.format("%d shown of %d items ready to manage", props.filteredCount or 0, props.totalCount or 0)),
						TextColor3 = Color3.fromRGB(175, 187, 207),
						TextSize = 12,
						TextXAlignment = Enum.TextXAlignment.Left,
						ZIndex = 8,
					}),
					SearchShell = e("Frame", {
						AnchorPoint = Vector2.new(1, 0),
						BackgroundColor3 = Color3.fromRGB(245, 241, 234),
						BorderSizePixel = 0,
						Position = UDim2.new(1, -18, 0, 16),
						Size = UDim2.fromOffset(236, 38),
						ZIndex = 8,
					}, {
						Corner = e("UICorner", {
							CornerRadius = UDim.new(0, 8),
						}),
						Stroke = e("UIStroke", {
							Color = Color3.fromRGB(150, 154, 165),
							Transparency = 0.24,
						}),
						Icon = searchGlyph(),
						Search = e("TextBox", {
							BackgroundTransparency = 1,
							BorderSizePixel = 0,
							ClearTextOnFocus = false,
							Font = Enum.Font.GothamBold,
							PlaceholderColor3 = Color3.fromRGB(133, 136, 144),
							PlaceholderText = showingCaptainLog and "Search placed brainrots..."
								or (showingTitles and "Search titles..." or "Search inventory..."),
							Position = UDim2.fromOffset(36, 0),
							Size = UDim2.new(1, -44, 1, 0),
							Text = props.query or "",
							TextColor3 = Color3.fromRGB(45, 47, 55),
							TextSize = 13,
							TextXAlignment = Enum.TextXAlignment.Left,
							ZIndex = 8,
							[React.Change.Text] = function(box)
								props.onQueryChanged(box.Text)
							end,
						}),
					}),
					GridShell = e("Frame", {
						BackgroundColor3 = Color3.fromRGB(8, 10, 16),
						BackgroundTransparency = 0.18,
						BorderSizePixel = 0,
						ClipsDescendants = true,
						Position = UDim2.fromOffset(18, 84),
						Size = UDim2.new(1, -36, 1, -102),
						ZIndex = 7,
					}, {
						Corner = e("UICorner", {
							CornerRadius = UDim.new(0, 10),
						}),
						Stroke = e("UIStroke", {
							Color = Color3.fromRGB(63, 80, 117),
							Transparency = 0.08,
						}),
						LogSummary = showingCaptainLog and e("Frame", {
							BackgroundColor3 = Color3.fromRGB(16, 22, 37),
							BackgroundTransparency = 0.04,
							BorderSizePixel = 0,
							Position = UDim2.fromOffset(14, 14),
							Size = UDim2.new(1, -28, 0, 58),
							ZIndex = 8,
						}, {
							Corner = e("UICorner", {
								CornerRadius = UDim.new(0, 10),
							}),
							Stroke = e("UIStroke", {
								Color = Color3.fromRGB(72, 93, 134),
								Transparency = 0.12,
							}),
							ReadyLabel = e("TextLabel", {
								BackgroundTransparency = 1,
								Font = Enum.Font.GothamBold,
								Position = UDim2.fromOffset(16, 10),
								Size = UDim2.new(0.5, 0, 0, 14),
								Text = "Ready to Collect",
								TextColor3 = PALETTE.Muted,
								TextSize = 11,
								TextXAlignment = Enum.TextXAlignment.Left,
								ZIndex = 9,
							}),
							ReadyValue = e("TextLabel", {
								BackgroundTransparency = 1,
								Font = Enum.Font.Cartoon,
								Position = UDim2.fromOffset(16, 22),
								Size = UDim2.new(0.5, -10, 0, 26),
								Text = string.format(
									"%s D",
									formatNumber((props.captainLog and props.captainLog.totalCollectable) or 0)
								),
								TextColor3 = PALETTE.Gold,
								TextSize = 28,
								TextStrokeTransparency = 0.56,
								TextXAlignment = Enum.TextXAlignment.Left,
								ZIndex = 9,
							}),
							PlacedLabel = e("TextLabel", {
								AnchorPoint = Vector2.new(1, 0),
								BackgroundTransparency = 1,
								Font = Enum.Font.GothamBold,
								Position = UDim2.new(1, -16, 10 / 58, 0),
								Size = UDim2.fromOffset(180, 14),
								Text = "Placed Brainrots",
								TextColor3 = PALETTE.Muted,
								TextSize = 11,
								TextXAlignment = Enum.TextXAlignment.Right,
								ZIndex = 9,
							}),
							PlacedValue = e("TextLabel", {
								AnchorPoint = Vector2.new(1, 0),
								BackgroundTransparency = 1,
								Font = Enum.Font.Cartoon,
								Position = UDim2.new(1, -16, 22 / 58, 0),
								Size = UDim2.fromOffset(180, 26),
								Text = tostring((props.captainLog and props.captainLog.placedCount) or 0),
								TextColor3 = activeAccent,
								TextSize = 28,
								TextStrokeTransparency = 0.56,
								TextXAlignment = Enum.TextXAlignment.Right,
								ZIndex = 9,
							}),
						}) or nil,
						TitleSummary = showingTitles and e("Frame", {
							BackgroundColor3 = Color3.fromRGB(16, 22, 37),
							BackgroundTransparency = 0.04,
							BorderSizePixel = 0,
							Position = UDim2.fromOffset(14, 14),
							Size = UDim2.new(1, -28, 0, 58),
							ZIndex = 8,
						}, {
							Corner = e("UICorner", {
								CornerRadius = UDim.new(0, 10),
							}),
							Stroke = e("UIStroke", {
								Color = Color3.fromRGB(72, 93, 134),
								Transparency = 0.12,
							}),
							UnlockedLabel = e("TextLabel", {
								BackgroundTransparency = 1,
								Font = Enum.Font.GothamBold,
								Position = UDim2.fromOffset(16, 10),
								Size = UDim2.new(0.5, 0, 0, 14),
								Text = "Unlocked Titles",
								TextColor3 = PALETTE.Muted,
								TextSize = 11,
								TextXAlignment = Enum.TextXAlignment.Left,
								ZIndex = 9,
							}),
							UnlockedValue = e("TextLabel", {
								BackgroundTransparency = 1,
								Font = Enum.Font.Cartoon,
								Position = UDim2.fromOffset(16, 22),
								Size = UDim2.new(0.5, -10, 0, 26),
								Text = string.format(
									"%d / %d",
									(props.titles and props.titles.unlockedCount) or 0,
									(props.titles and props.titles.totalCount) or 0
								),
								TextColor3 = PALETTE.Gold,
								TextSize = 28,
								TextStrokeTransparency = 0.56,
								TextXAlignment = Enum.TextXAlignment.Left,
								ZIndex = 9,
							}),
							BountyLabel = e("TextLabel", {
								AnchorPoint = Vector2.new(1, 0),
								BackgroundTransparency = 1,
								Font = Enum.Font.GothamBold,
								Position = UDim2.new(1, -16, 10 / 58, 0),
								Size = UDim2.fromOffset(180, 14),
								Text = "Bounty Rank",
								TextColor3 = PALETTE.Muted,
								TextSize = 11,
								TextXAlignment = Enum.TextXAlignment.Right,
								ZIndex = 9,
							}),
							BountyValue = e("TextLabel", {
								AnchorPoint = Vector2.new(1, 0),
								BackgroundTransparency = 1,
								Font = Enum.Font.Cartoon,
								Position = UDim2.new(1, -16, 22 / 58, 0),
								Size = UDim2.fromOffset(180, 26),
								Text = tostring((props.titles and props.titles.bountyRankLabel) or formatLeaderboardRank(props.titles and props.titles.bountyRank)),
								TextColor3 = activeAccent,
								TextSize = 28,
								TextStrokeTransparency = 0.56,
								TextXAlignment = Enum.TextXAlignment.Right,
								ZIndex = 9,
							}),
						}) or nil,
						Grid = showingInventory and e("ScrollingFrame", {
							AutomaticCanvasSize = Enum.AutomaticSize.Y,
							BackgroundTransparency = 1,
							BorderSizePixel = 0,
							CanvasSize = UDim2.new(),
							Position = UDim2.fromOffset(14, 14),
							ScrollBarImageColor3 = PALETTE.Cream,
							ScrollBarThickness = 7,
							Size = UDim2.new(1, -28, 1, -28),
							ZIndex = 8,
						}, gridChildren),
						LogList = showingCaptainLog and e("ScrollingFrame", {
							AutomaticCanvasSize = Enum.AutomaticSize.Y,
							BackgroundTransparency = 1,
							BorderSizePixel = 0,
							CanvasSize = UDim2.new(),
							Position = UDim2.fromOffset(14, 82),
							ScrollBarImageColor3 = PALETTE.Cream,
							ScrollBarThickness = 7,
							Size = UDim2.new(1, -28, 1, -96),
							ZIndex = 8,
						}, captainLogChildren) or nil,
						TitleList = showingTitles and e("ScrollingFrame", {
							AutomaticCanvasSize = Enum.AutomaticSize.Y,
							BackgroundTransparency = 1,
							BorderSizePixel = 0,
							CanvasSize = UDim2.new(),
							Position = UDim2.fromOffset(14, 82),
							ScrollBarImageColor3 = PALETTE.Cream,
							ScrollBarThickness = 7,
							Size = UDim2.new(1, -28, 1, -96),
							ZIndex = 8,
						}, titleChildren) or nil,
						Empty = (showingCaptainLog and #((props.captainLog and props.captainLog.entries) or {}) == 0
								or (showingTitles and #((props.titles and props.titles.entries) or {}) == 0)
								or (showingInventory and #(props.items or {}) == 0)) and e("TextLabel", {
							AnchorPoint = Vector2.new(0.5, 0.5),
							BackgroundTransparency = 1,
							Font = Enum.Font.Cartoon,
							Position = UDim2.new(0.5, 0, 0.52, 0),
							Size = UDim2.fromOffset(360, 26),
							Text = showingCaptainLog
									and (((props.captainLog and props.captainLog.totalCount) or 0) > 0
										and "No placed brainrots match that search."
										or "No brainrots are placed on your ship yet.")
								or (showingTitles
									and (((props.titles and props.titles.totalCount) or 0) > 0
										and "No titles match that search."
										or "No titles are registered yet.")
									or ((props.totalCount or 0) > 0
										and "No inventory items match that search."
										or "Nothing in this hold yet.")),
							TextColor3 = Color3.fromRGB(191, 198, 212),
							TextSize = 24,
							TextStrokeTransparency = 0.6,
							ZIndex = 8,
						}) or nil,
					}),
				}),
				FooterStrip = e("Frame", {
					BackgroundColor3 = Color3.fromRGB(10, 13, 22),
					BackgroundTransparency = 0.08,
					BorderSizePixel = 0,
					Position = UDim2.new(0, 286, 1, -86),
					Size = UDim2.new(1, -312, 0, 58),
					Visible = showingInventory,
					ZIndex = 7,
				}, {
					Corner = e("UICorner", {
						CornerRadius = UDim.new(0, 12),
					}),
					Stroke = e("UIStroke", {
						Color = Color3.fromRGB(52, 74, 117),
						Transparency = 0.12,
						Thickness = 1.2,
					}),
					Tabs = e("Frame", {
						BackgroundTransparency = 1,
						Position = UDim2.fromOffset(10, 7),
						Size = UDim2.new(1, -20, 1, -14),
						ZIndex = 8,
					}, footerChildren),
				}),
			}),
		}
	end

	children.InventoryModal = e(AnimatedInventoryModal, {
		isOpen = props.isOpen,
		panelChildren = modalPanelChildren,
		panelSize = UDim2.new(0.82, 0, 0.76, 0),
		openPosition = INVENTORY_MODAL_OPEN_POSITION,
		closedPosition = INVENTORY_MODAL_CLOSED_POSITION,
		backdropTransparency = INVENTORY_MODAL_BACKDROP_TRANSPARENCY,
	})

	local appChildren = {
		Main = e("ScreenGui", {
			Name = "ReactInventoryUi",
			DisplayOrder = 90,
			IgnoreGuiInset = true,
			ResetOnSpawn = false,
			ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		}, children),
	}

	if props.shipUpgradeModal then
		appChildren.ShipUpgradeModal = e(shipUpgradeModal, {
			modal = props.shipUpgradeModal,
			onDismiss = props.onDismissShipUpgradeModal,
		})
	end

	return e(React.Fragment, nil, appChildren)
end

return App
