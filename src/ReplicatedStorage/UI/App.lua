local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local React = require(Packages:WaitForChild("React"))

local Modules = ReplicatedStorage:WaitForChild("Modules")
local DevilFruitAssets = require(Modules:WaitForChild("DevilFruits"):WaitForChild("Assets"))
local CrewPreviewImages = require(Modules:WaitForChild("Crew"):WaitForChild("CrewPreviewImages"))
local CurrencyUtil = require(Modules:WaitForChild("CurrencyUtil"))
local IndexCard = require(script.Parent:WaitForChild("Index"):WaitForChild("Components"):WaitForChild("IndexCard"))
local SharedPreviewViewport = require(script.Parent:WaitForChild("Index"):WaitForChild("Components"):WaitForChild("PreviewViewport"))
local Responsive = require(script.Parent:WaitForChild("Responsive"))

local e = React.createElement
local CREW_PREVIEW_ASSET_ROOT_NAME = "One Piece Characters"
local CREW_PREVIEW_ROTATION = CFrame.Angles(math.rad(-12), math.rad(208), 0)
local INVENTORY_MODAL_OPEN_POSITION = UDim2.fromScale(0.5, 0.49)
local INVENTORY_MODAL_CLOSED_POSITION = UDim2.fromScale(0.5, 10)
local INVENTORY_MODAL_OPEN_TIME = 0.16
local INVENTORY_MODAL_CLOSE_TIME = 0.16
local INVENTORY_MODAL_BACKDROP_TRANSPARENCY = 0.28

local function isMobileViewport()
	return Responsive.isMobile()
end

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

local INVENTORY_UI = {
	PrimaryBg = Color3.fromRGB(30, 42, 56),
	SecondaryBg = Color3.fromRGB(36, 52, 71),
	HeaderBg = Color3.fromRGB(16, 35, 59),
	SectionBg = Color3.fromRGB(27, 46, 68),
	SectionHover = Color3.fromRGB(46, 74, 99),
	MenuOverlay = Color3.fromRGB(15, 27, 42),
	GoldBase = Color3.fromRGB(212, 175, 55),
	GoldHighlight = Color3.fromRGB(242, 209, 107),
	GoldShadow = Color3.fromRGB(140, 107, 31),
	ButtonIdle = Color3.fromRGB(7, 22, 41),
	ButtonIdleBottom = Color3.fromRGB(4, 16, 31),
	ButtonActive = Color3.fromRGB(58, 47, 18),
	ButtonActiveBottom = Color3.fromRGB(33, 25, 10),
	TextMain = Color3.fromRGB(230, 230, 230),
	TextMuted = Color3.fromRGB(184, 193, 204),
}
local INVENTORY_BACKGROUND_IMAGE = "rbxassetid://131358437063076"

local function formatNumber(value)
	return CurrencyUtil.formatCompactNumber(value)
end

local function formatRateNumber(value)
	return CurrencyUtil.formatCurrencyPerSecond(tonumber(value) or 0)
end

local function formatLeaderboardRank(rank)
	local numericRank = tonumber(rank)
	if numericRank and numericRank >= 1 then
		return "#" .. tostring(math.floor(numericRank + 0.5))
	end

	return "Unranked"
end

local function formatDuration(seconds)
	local totalSeconds = math.max(0, math.floor(tonumber(seconds) or 0))
	local hours = math.floor(totalSeconds / 3600)
	local minutes = math.floor((totalSeconds % 3600) / 60)
	if hours > 0 then
		return string.format("%dh %02dm", hours, minutes)
	end
	return string.format("%dm", minutes)
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
		createPreviewPart(
			model,
			Vector3.new(0.9, 0.9, 0.9),
			Color3.fromRGB(214, 67, 52),
			CFrame.new(0, 0, 0),
			Enum.PartType.Ball
		)
		createPreviewPart(
			model,
			Vector3.new(0.12, 0.35, 0.12),
			Color3.fromRGB(86, 53, 31),
			CFrame.new(0, 0.5, 0),
			Enum.PartType.Cylinder,
			Enum.Material.Wood
		)
		createPreviewPart(
			model,
			Vector3.new(0.35, 0.12, 0.2),
			Color3.fromRGB(80, 170, 72),
			CFrame.new(0.18, 0.42, 0),
			Enum.PartType.Block,
			Enum.Material.Grass
		)
	elseif resourceKey == "Rice" then
		createPreviewPart(
			model,
			Vector3.new(1.0, 0.35, 1.0),
			Color3.fromRGB(171, 106, 57),
			CFrame.new(0, -0.18, 0),
			Enum.PartType.Cylinder,
			Enum.Material.Wood
		)
		createPreviewPart(
			model,
			Vector3.new(0.82, 0.28, 0.82),
			Color3.fromRGB(242, 240, 223),
			CFrame.new(0, 0.08, 0),
			Enum.PartType.Cylinder,
			Enum.Material.Sand
		)
	elseif resourceKey == "Meat" then
		createPreviewPart(
			model,
			Vector3.new(1.0, 0.7, 0.7),
			Color3.fromRGB(160, 64, 56),
			CFrame.new(0, 0, 0),
			Enum.PartType.Block
		)
		createPreviewPart(
			model,
			Vector3.new(0.22, 0.22, 0.9),
			Color3.fromRGB(231, 220, 208),
			CFrame.new(-0.6, 0, 0),
			Enum.PartType.Cylinder
		)
	elseif resourceKey == "SeaBeastMeat" then
		createPreviewPart(
			model,
			Vector3.new(1.05, 0.78, 0.74),
			Color3.fromRGB(105, 41, 56),
			CFrame.new(0, 0, 0),
			Enum.PartType.Block
		)
		createPreviewPart(
			model,
			Vector3.new(0.18, 0.82, 0.7),
			Color3.fromRGB(76, 186, 199),
			CFrame.new(0.52, 0, 0),
			Enum.PartType.Block,
			Enum.Material.Neon
		)
	elseif resourceKey == "Iron" then
		createPreviewPart(
			model,
			Vector3.new(0.95, 0.28, 0.55),
			Color3.fromRGB(180, 186, 196),
			CFrame.new(0, -0.08, 0),
			Enum.PartType.Block,
			Enum.Material.Metal
		)
		createPreviewPart(
			model,
			Vector3.new(0.8, 0.2, 0.45),
			Color3.fromRGB(150, 157, 168),
			CFrame.new(0.08, 0.16, 0.02),
			Enum.PartType.Block,
			Enum.Material.Metal
		)
	elseif resourceKey == "AncientTimber" then
		createPreviewPart(
			model,
			Vector3.new(1.0, 0.24, 0.32),
			Color3.fromRGB(112, 83, 55),
			CFrame.new(0, -0.12, 0),
			Enum.PartType.Block,
			Enum.Material.WoodPlanks
		)
		createPreviewPart(
			model,
			Vector3.new(0.92, 0.24, 0.32),
			Color3.fromRGB(128, 97, 65),
			CFrame.new(0.08, 0.14, 0.08),
			Enum.PartType.Block,
			Enum.Material.WoodPlanks
		)
		createPreviewPart(
			model,
			Vector3.new(0.16, 0.34, 0.16),
			Color3.fromRGB(110, 186, 136),
			CFrame.new(-0.3, 0.2, 0),
			Enum.PartType.Cylinder,
			Enum.Material.Neon
		)
	else
		createPreviewPart(
			model,
			Vector3.new(1.0, 0.25, 0.26),
			Color3.fromRGB(147, 103, 67),
			CFrame.new(0, -0.12, 0),
			Enum.PartType.Block,
			Enum.Material.WoodPlanks
		)
		createPreviewPart(
			model,
			Vector3.new(0.92, 0.25, 0.26),
			Color3.fromRGB(171, 121, 79),
			CFrame.new(0.06, 0.12, 0.06),
			Enum.PartType.Block,
			Enum.Material.WoodPlanks
		)
	end

	return model
end

local function buildInventoryIconModel()
	local model = Instance.new("Model")
	model.Name = "InventoryIcon"

	createPreviewPart(
		model,
		Vector3.new(0.95, 0.75, 0.46),
		Color3.fromRGB(204, 96, 42),
		CFrame.new(0, 0, 0),
		Enum.PartType.Block,
		Enum.Material.SmoothPlastic
	)
	createPreviewPart(
		model,
		Vector3.new(0.65, 0.2, 0.12),
		Color3.fromRGB(85, 49, 31),
		CFrame.new(0, 0.44, 0),
		Enum.PartType.Block,
		Enum.Material.Wood
	)
	createPreviewPart(
		model,
		Vector3.new(0.3, 0.28, 0.1),
		Color3.fromRGB(238, 203, 95),
		CFrame.new(0, -0.06, 0.24),
		Enum.PartType.Block,
		Enum.Material.Neon
	)

	return model
end

local function getCrewPreviewAssetRoot()
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	return assets and assets:FindFirstChild(CREW_PREVIEW_ASSET_ROOT_NAME) or nil
end

local function findCrewPreviewModel(modelName)
	local root = getCrewPreviewAssetRoot()
	local name = tostring(modelName or "")
	if not root or name == "" then
		return nil
	end

	local direct = root:FindFirstChild(name)
	if direct and direct:IsA("Model") then
		return direct
	end

	local descendant = root:FindFirstChild(name, true)
	if descendant and descendant:IsA("Model") then
		return descendant
	end

	return nil
end

local function sanitizeCrewPreviewClone(previewModel)
	for _, descendant in ipairs(previewModel:GetDescendants()) do
		if descendant:IsA("BasePart") then
			setPreviewPartDefaults(descendant)
		elseif descendant:IsA("BaseScript") or descendant:IsA("ModuleScript") or descendant:IsA("Sound") then
			descendant:Destroy()
		elseif
			descendant:IsA("ParticleEmitter")
			or descendant:IsA("Trail")
			or descendant:IsA("Beam")
			or descendant:IsA("PointLight")
			or descendant:IsA("SpotLight")
			or descendant:IsA("SurfaceLight")
		then
			descendant.Enabled = false
		end
	end
end

local function cloneCrewPreviewModel(modelName)
	local template = findCrewPreviewModel(modelName)
	if not template then
		return nil
	end

	local ok, clone = pcall(function()
		return template:Clone()
	end)
	if not ok or typeof(clone) ~= "Instance" then
		return nil
	end

	sanitizeCrewPreviewClone(clone)
	return clone
end

local function positionPreviewModel(previewModel, previewKind, previewName)
	local rotation = CFrame.Angles(math.rad(-12), math.rad(28), 0)
	if previewKind == "Resource" then
		rotation = CFrame.Angles(math.rad(-8), math.rad(26), 0)
	elseif previewKind == "Inventory" then
		rotation = CFrame.Angles(math.rad(-14), math.rad(-26), 0)
	elseif previewKind == "CrewMember" then
		rotation = CREW_PREVIEW_ROTATION
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
		elseif props.previewKind == "CrewMember" then
			previewModel = cloneCrewPreviewModel(props.previewName)
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
		camera.CFrame =
			CFrame.lookAt(boxCF.Position + Vector3.new(maxSize * 0.92, maxSize * 0.38, maxSize * 1.7), boxCF.Position)
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

local function isCrewPreviewItem(item)
	return item
		and (
			tostring(item.kind or "") == "CrewMember"
			or tostring(item.previewKind or "") == "CrewMember"
			or tostring(item.crewMemberName or "") ~= ""
		)
end

local function getStaticCrewPreviewImage(item)
	if not item then
		return ""
	end

	if isCrewPreviewItem(item) then
		local staticPreviewImage = CrewPreviewImages.Resolve(item)
		if staticPreviewImage ~= "" then
			return staticPreviewImage
		end
	end

	return CrewPreviewImages.ResolveStaticImage(item.image)
end

local function staticCrewPreviewImage(image, props)
	props = props or {}
	return e("ImageLabel", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		Image = image,
		Position = props.position or UDim2.fromScale(0.5, 0.5),
		ScaleType = props.scaleType or Enum.ScaleType.Crop,
		Size = props.size or UDim2.fromScale(1, 1),
		ZIndex = props.zIndex,
	})
end

local function staticPreviewSlotContent(image, props)
	props = props or {}
	local hovered = props.hovered == true
	local shadowColor = Color3.fromRGB(4, 8, 14)
	local overlayTransparency = if hovered then 0.78 else 0.84
	local zIndex = props.zIndex or 1

	return e("Frame", {
		Active = false,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ClipsDescendants = true,
		Position = UDim2.fromScale(0, 0),
		Size = UDim2.fromScale(1, 1),
		ZIndex = zIndex,
	}, {
		Corner = e("UICorner", {
			CornerRadius = UDim.new(0, props.cornerRadius or 13),
		}),
		Image = e("ImageLabel", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundTransparency = 1,
			Image = image,
			Position = UDim2.fromScale(0.5, 0.5),
			ScaleType = props.scaleType or Enum.ScaleType.Crop,
			Size = UDim2.fromScale(1, 1),
			ZIndex = zIndex,
		}, {
			Corner = e("UICorner", {
				CornerRadius = UDim.new(0, props.cornerRadius or 13),
			}),
		}),
		Wash = e("Frame", {
			BackgroundColor3 = shadowColor,
			BackgroundTransparency = overlayTransparency,
			BorderSizePixel = 0,
			Size = UDim2.fromScale(1, 1),
			ZIndex = zIndex + 1,
		}, {
			Corner = e("UICorner", {
				CornerRadius = UDim.new(0, props.cornerRadius or 13),
			}),
		}),
	})
end

local function renderItemPreview(item, props)
	local position = props.position
	local size = props.size
	local zIndex = props.zIndex
	local fallbackFont = props.fallbackFont or Enum.Font.GothamBold
	local fallbackTextSize = props.fallbackTextSize or 20
	local fallbackTextColor = props.fallbackTextColor or PALETTE.Text
	local fallbackSize = props.fallbackSize or UDim2.new(1, -12, 1, -12)
	local hasViewportPreview = item
		and item.previewKind ~= nil
		and tostring(item.previewKind) ~= ""
		and item.previewName ~= nil
		and tostring(item.previewName) ~= ""

	local staticPreviewImage = getStaticCrewPreviewImage(item)
	if staticPreviewImage ~= "" then
		return staticCrewPreviewImage(staticPreviewImage, {
			zIndex = zIndex,
		})
	end

	if hasViewportPreview and item.previewKind == "CrewMember" then
		return e(PreviewViewport, {
			previewKind = item.previewKind,
			previewName = item.previewName,
			position = position,
			size = size,
			zIndex = zIndex,
			fieldOfView = props.fieldOfView or 34,
		})
	end

	if hasViewportPreview and item.previewKind == "Chest" then
		return e(SharedPreviewViewport, {
			previewKind = item.previewKind,
			previewName = item.previewName,
			position = position,
			size = size,
			zIndex = zIndex,
			fieldOfView = props.fieldOfView or 34,
		})
	end

	if item and item.image and item.image ~= "" then
		return e("ImageLabel", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundTransparency = 1,
			Image = item.image,
			Position = position,
			Size = size,
			ScaleType = Enum.ScaleType.Fit,
			ZIndex = zIndex,
		})
	end

	if hasViewportPreview then
		return e(PreviewViewport, {
			previewKind = item.previewKind,
			previewName = item.previewName,
			position = position,
			size = size,
			zIndex = zIndex,
			fieldOfView = props.fieldOfView or 34,
		})
	end

	return e("TextLabel", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		Font = fallbackFont,
		Position = position,
		Size = fallbackSize,
		Text = item and (item.fallbackText or initials(item.displayName)) or "",
		TextColor3 = fallbackTextColor,
		TextSize = fallbackTextSize,
		TextWrapped = props.fallbackTextWrapped == true,
		ZIndex = zIndex,
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
	local merged = table.clone(baseProps)
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

		local tweenInfo =
			TweenInfo.new(props.openTime or INVENTORY_MODAL_OPEN_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

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

		local tweenInfo =
			TweenInfo.new(props.closeTime or INVENTORY_MODAL_CLOSE_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.In)

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

	local contentScale = math.clamp(tonumber(props.contentScale) or 1, 0.5, 1)
	local renderedPanelChildren = panelChildren
	if contentScale < 1 then
		local scaledChildren = {
			ContentScale = e("UIScale", {
				Scale = contentScale,
			}),
		}

		for key, value in pairs(cachedPanelChildren) do
			scaledChildren[key] = value
		end

		renderedPanelChildren = {
			Scale = panelChildren.Scale,
			ContentHost = e("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				ClipsDescendants = false,
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromScale(1 / contentScale, 1 / contentScale),
				ZIndex = 5,
			}, scaledChildren),
		}
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
			BackgroundTransparency = props.isOpen
					and (props.backdropTransparency or INVENTORY_MODAL_BACKDROP_TRANSPARENCY)
				or 1,
			BorderSizePixel = 0,
			Size = UDim2.fromScale(1, 1),
			ZIndex = 4,
		}),
		Panel = e("Frame", {
			ref = panelRef,
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundTransparency = 1,
			Position = props.isOpen and (props.openPosition or INVENTORY_MODAL_OPEN_POSITION)
				or (props.closedPosition or INVENTORY_MODAL_CLOSED_POSITION),
			Size = props.panelSize or UDim2.fromScale(0.82, 0.76),
			ZIndex = 5,
		}, renderedPanelChildren),
	})
end

local function hotbarSlot(props)
	local slot = props.slot or {}
	local item = slot.item
	local accent = item and item.accentColor or Color3.fromRGB(76, 96, 132)
	local lockedSlot = item and item.lockedSlot == true
	local emptySlot = item and item.emptySlot == true
	local interactive = item ~= nil and item.interactive ~= false and props.onActivated ~= nil
	local hovered, pressed, handlers, hoverRef = useInteractiveState(interactive)
	local zIndexBase = props.zIndexBase or 0
	local slotSize = math.max(46, math.floor(tonumber(props.slotSize) or 64))
	local hoverZIndexOffset = hovered and 12 or 0
	local slotBaseColor = item and accent:Lerp(Color3.fromRGB(20, 28, 44), 0.78) or Color3.fromRGB(13, 19, 31)
	local slotTopColor = item and accent:Lerp(Color3.fromRGB(28, 39, 61), 0.84) or Color3.fromRGB(18, 26, 41)
	local slotBottomColor = item and accent:Lerp(Color3.fromRGB(12, 17, 30), 0.92) or Color3.fromRGB(10, 14, 24)
	local staticPreviewImage = getStaticCrewPreviewImage(item)
	local hasStaticPreview = staticPreviewImage ~= ""
	local compactSlot = slotSize <= 40

	local slotProps = mergeProps({
		BackgroundColor3 = slotBaseColor,
		BackgroundTransparency = item and (emptySlot and 0.58 or 0.3) or 0.76,
		BorderSizePixel = 0,
		ClipsDescendants = true,
		LayoutOrder = props.layoutOrder or 0,
		ref = hoverRef,
		Size = UDim2.fromOffset(slotSize, slotSize),
		ZIndex = zIndexBase + 1 + hoverZIndexOffset,
	}, handlers)

	if interactive then
		slotProps.AutoButtonColor = false
		slotProps.Text = ""
		slotProps[React.Event.Activated] = function()
			props.onActivated(item)
		end
	end

	local previewChild = nil
	if not hasStaticPreview then
		previewChild = renderItemPreview(item, {
			position = UDim2.fromScale(0.5, 0.52),
			size = UDim2.fromOffset(compactSlot and 22 or 40, compactSlot and 22 or 40),
			zIndex = zIndexBase + 3 + hoverZIndexOffset,
			fallbackFont = Enum.Font.GothamMedium,
			fallbackTextColor = PALETTE.Muted,
			fallbackTextSize = 10,
			fallbackSize = UDim2.new(1, -12, 0, 18),
		})
	end

	return e(interactive and "TextButton" or "Frame", slotProps, {
		Scale = e("UIScale", {
			Scale = (hovered and 1.03 or 1) - (pressed and 0.018 or 0),
		}),
		Corner = e("UICorner", {
			CornerRadius = UDim.new(0, 16),
		}),
		Stroke = e("UIStroke", {
			Color = accent,
			Transparency = item and (hovered and 0.08 or (lockedSlot and 0.28 or 0.18)) or 0.7,
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
			ClipsDescendants = true,
			Position = UDim2.fromOffset(4, 4),
			Size = UDim2.new(1, -8, 1, -8),
			ZIndex = zIndexBase + 1 + hoverZIndexOffset,
		}, {
			Corner = e("UICorner", {
				CornerRadius = UDim.new(0, 13),
			}),
			StaticPreview = hasStaticPreview and staticPreviewSlotContent(staticPreviewImage, {
				cornerRadius = 13,
				hovered = hovered,
				zIndex = zIndexBase + 2 + hoverZIndexOffset,
			}) or nil,
		}),
		KeyLabel = slot.slotLabel ~= nil and e("TextLabel", {
			AutomaticSize = Enum.AutomaticSize.XY,
			BackgroundColor3 = Color3.fromRGB(6, 10, 18),
			BackgroundTransparency = hovered and 0.08 or 0.16,
			Position = UDim2.fromOffset(6, 6),
			Font = Enum.Font.GothamBold,
			Text = tostring(slot.slotLabel),
			TextColor3 = item and (lockedSlot and Color3.fromRGB(230, 236, 245) or PALETTE.Cream) or PALETTE.Steel,
			TextSize = compactSlot and 7 or 10,
			ZIndex = zIndexBase + 5 + hoverZIndexOffset,
		}, {
			Corner = e("UICorner", {
				CornerRadius = UDim.new(0, 999),
			}),
			Padding = e("UIPadding", {
				PaddingTop = UDim.new(0, compactSlot and 1 or 3),
				PaddingBottom = UDim.new(0, compactSlot and 1 or 3),
				PaddingLeft = UDim.new(0, compactSlot and 4 or 7),
				PaddingRight = UDim.new(0, compactSlot and 4 or 7),
			}),
		}) or nil,
		Preview = previewChild,
		Count = item and not lockedSlot and (item.quantity or 0) > 1 and e("TextLabel", {
			AnchorPoint = Vector2.new(1, 1),
			AutomaticSize = Enum.AutomaticSize.XY,
			BackgroundColor3 = Color3.fromRGB(6, 10, 18),
			BackgroundTransparency = hovered and 0.08 or 0.16,
			Position = UDim2.new(1, -6, 1, -6),
			Font = Enum.Font.GothamBold,
			Text = tostring(item.quantity),
			TextColor3 = PALETTE.Cream,
			TextSize = 10,
			ZIndex = zIndexBase + 5 + hoverZIndexOffset,
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

local function inventoryToggleButton(props)
	local layout = props.toggleLayout or {}
	local position = layout.position or UDim2.new(1, -26, 1, -24)
	local size = layout.size or UDim2.fromOffset(154, 54)
	local compact = layout.compact == true
	local hovered, pressed, handlers, hoverRef = useInteractiveState(props.onToggle ~= nil)
	local zIndexBase = props.zIndexBase or 0
	local iconPosition = compact and UDim2.fromScale(0.5, 0.5) or UDim2.fromScale(0.5, 0.44)
	local iconSize = compact and UDim2.fromOffset(46, 46) or UDim2.fromOffset(34, 34)
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

	return e(
		"TextButton",
		mergeProps({
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
		}, handlers),
		{
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
				Position = UDim2.new(0.5, 0, 0, 2),
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
				Size = UDim2.new(1, -4, 0, compact and 13 or 16),
				Text = "Inventory",
				TextColor3 = PALETTE.Cream,
				TextSize = compact and 9 or 13,
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
		}
	)
end

local function modeTab(props)
	local active = props.active == true
	local hovered, pressed, handlers, hoverRef = useInteractiveState(props.onActivated ~= nil)
	local heldHover = hovered
	local heldActive = active and not hovered
	local heldScale = heldHover and 1.02 or (heldActive and 1.008 or 1)
	local fillTop = active and INVENTORY_UI.ButtonActive or INVENTORY_UI.ButtonIdle
	local fillBottom = active and INVENTORY_UI.ButtonActiveBottom or INVENTORY_UI.ButtonIdleBottom
	local textColor = active and INVENTORY_UI.GoldHighlight or INVENTORY_UI.TextMain

	local buttonProps = mergeProps({
		AutoButtonColor = false,
		BackgroundColor3 = fillTop,
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
			Color = INVENTORY_UI.GoldHighlight,
			Transparency = active and 0.01 or (hovered and 0.02 or 0.05),
			Thickness = active and 2 or 1.75,
		}),
		Glow = e("UIStroke", {
			Color = INVENTORY_UI.GoldBase,
			Transparency = active and 0.82 or (hovered and 0.86 or 0.9),
			Thickness = active and 2.6 or 2.3,
		}),
		Gradient = e("UIGradient", {
			Rotation = 90,
			Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, fillTop),
				ColorSequenceKeypoint.new(1, fillBottom),
			}),
		}),
		Label = e("TextLabel", {
			BackgroundTransparency = 1,
			Font = Enum.Font.GothamBold,
			Size = UDim2.new(1, -16, 1, 0),
			Position = UDim2.fromOffset(8, -1),
			Text = props.label or "",
			TextColor3 = textColor,
			TextSize = 18,
			TextStrokeTransparency = 0.7,
			TextStrokeColor3 = INVENTORY_UI.MenuOverlay,
			TextWrapped = true,
			ZIndex = 2,
		}),
	})
end

local function ledgerLine(props)
	local multiLine = props.multiLine == true
	local compact = props.compact == true
	local valueWidthScale = multiLine and 1 or math.clamp(props.valueWidthScale or 0.42, 0.24, 0.7)
	local labelWidthScale = multiLine and 1 or (1 - valueWidthScale)
	local rowHeight = if compact then (multiLine and 34 or 21) else (multiLine and 44 or 28)
	local labelTextSize = if compact then 13 else 18
	local valueTextSize = props.valueTextSize or if compact then (multiLine and 12 or 13) else (multiLine and 15 or 18)

	return e("Frame", {
		BackgroundTransparency = 1,
		LayoutOrder = props.layoutOrder or 0,
		Size = UDim2.new(1, 0, 0, rowHeight),
	}, {
		Label = e("TextLabel", {
			BackgroundTransparency = 1,
			Font = Enum.Font.Cartoon,
			Position = UDim2.fromOffset(0, -1),
			Size = multiLine and UDim2.new(1, 0, 0, compact and 13 or 16) or UDim2.fromScale(labelWidthScale, 1),
			Text = props.label or "",
			TextColor3 = PALETTE.Cream,
			TextSize = labelTextSize,
			TextStrokeTransparency = 0.6,
			TextXAlignment = Enum.TextXAlignment.Left,
		}),
		Value = e("TextLabel", {
			AnchorPoint = multiLine and Vector2.new(0, 0) or Vector2.new(1, 0),
			BackgroundTransparency = 1,
			Font = Enum.Font.GothamBold,
			Position = multiLine and UDim2.fromOffset(0, compact and 14 or 18) or UDim2.new(1, 0, 0, compact and 2 or 3),
			Size = multiLine and UDim2.new(1, 0, 0, compact and 18 or 22) or UDim2.fromScale(valueWidthScale, 1),
			Text = props.value or "",
			TextColor3 = props.valueColor3 or PALETTE.Cyan,
			TextSize = valueTextSize,
			TextStrokeTransparency = 0.8,
			TextTruncate = props.valueTruncate or Enum.TextTruncate.AtEnd,
			TextWrapped = multiLine,
			TextXAlignment = multiLine and Enum.TextXAlignment.Left or Enum.TextXAlignment.Right,
			TextYAlignment = multiLine and Enum.TextYAlignment.Top or Enum.TextYAlignment.Center,
		}),
	})
end

local function categoryMenuTab(props)
	local active = props.active == true
	local accent = props.accentColor or PALETTE.Orange
	local hovered, _, handlers, hoverRef = useInteractiveState(props.onActivated ~= nil, false)
	local fillTop = active and INVENTORY_UI.ButtonActive or INVENTORY_UI.ButtonIdle
	local fillBottom = active and INVENTORY_UI.ButtonActiveBottom or INVENTORY_UI.ButtonIdleBottom

	if hovered and not active then
		fillTop = INVENTORY_UI.SectionHover
		fillBottom = INVENTORY_UI.SecondaryBg
	end

	local buttonProps = mergeProps({
		AutoButtonColor = false,
		BackgroundColor3 = fillTop,
		BorderSizePixel = 0,
		ClipsDescendants = true,
		LayoutOrder = props.layoutOrder or 0,
		ref = hoverRef,
		Size = props.size or UDim2.fromOffset(154, 34),
		Text = "",
		[React.Event.Activated] = props.onActivated,
	}, handlers)

	return e("TextButton", buttonProps, {
		Corner = e("UICorner", {
			CornerRadius = UDim.new(0, 11),
		}),
		Stroke = e("UIStroke", {
			Color = INVENTORY_UI.GoldHighlight,
			Transparency = active and 0.02 or (hovered and 0.08 or 0.18),
			Thickness = 1.2,
		}),
		Gradient = e("UIGradient", {
			Rotation = 90,
			Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, fillTop),
				ColorSequenceKeypoint.new(1, fillBottom),
			}),
		}),
		Label = e("TextLabel", {
			BackgroundTransparency = 1,
			Font = Enum.Font.GothamBold,
			Position = UDim2.fromOffset(14, -1),
			Size = UDim2.new(1, -52, 1, 0),
			Text = props.label or "",
			TextColor3 = active and INVENTORY_UI.GoldHighlight
				or (hovered and INVENTORY_UI.GoldBase or INVENTORY_UI.TextMain),
			TextSize = 16,
			TextStrokeTransparency = 0.75,
			TextXAlignment = Enum.TextXAlignment.Left,
		}),
		Count = e("TextLabel", {
			AnchorPoint = Vector2.new(1, 0.5),
			AutomaticSize = Enum.AutomaticSize.XY,
			BackgroundColor3 = INVENTORY_UI.MenuOverlay,
			BackgroundTransparency = 0.08,
			Position = UDim2.new(1, -10, 0.5, 0),
			Font = Enum.Font.GothamBold,
			Text = tostring(props.count or 0),
			TextColor3 = active and accent or (hovered and INVENTORY_UI.GoldBase or INVENTORY_UI.TextMuted),
			TextSize = 11,
		}, {
			Corner = e("UICorner", {
				CornerRadius = UDim.new(0, 999),
			}),
			Stroke = e("UIStroke", {
				Color = INVENTORY_UI.GoldHighlight,
				Transparency = 0.24,
				Thickness = 1,
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
				Color = INVENTORY_UI.GoldHighlight,
				Thickness = 2,
			}),
			Corner = e("UICorner", {
				CornerRadius = UDim.new(1, 0),
			}),
		}),
		Handle = e("Frame", {
			AnchorPoint = Vector2.new(0.5, 0),
			BackgroundColor3 = INVENTORY_UI.GoldHighlight,
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

local function lockGlyph(accent, zIndex)
	accent = accent or PALETTE.Steel
	zIndex = zIndex or 3

	return e("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(44, 52),
		ZIndex = zIndex,
	}, {
		Shackle = e("Frame", {
			AnchorPoint = Vector2.new(0.5, 0),
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(22, 1),
			Size = UDim2.fromOffset(28, 30),
			ZIndex = zIndex,
		}, {
			Stroke = e("UIStroke", {
				Color = accent,
				Thickness = 5,
				Transparency = 0.04,
			}),
			Corner = e("UICorner", {
				CornerRadius = UDim.new(0, 14),
			}),
		}),
		Body = e("Frame", {
			AnchorPoint = Vector2.new(0.5, 1),
			BackgroundColor3 = accent,
			BackgroundTransparency = 0.02,
			BorderSizePixel = 0,
			Position = UDim2.new(0.5, 0, 1, -3),
			Size = UDim2.fromOffset(38, 31),
			ZIndex = zIndex + 1,
		}, {
			Corner = e("UICorner", {
				CornerRadius = UDim.new(0, 8),
			}),
			Keyhole = e("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				BackgroundColor3 = Color3.fromRGB(22, 26, 34),
				BorderSizePixel = 0,
				Position = UDim2.fromScale(0.5, 0.54),
				Size = UDim2.fromOffset(8, 15),
				ZIndex = zIndex + 2,
			}, {
				Corner = e("UICorner", {
					CornerRadius = UDim.new(0, 999),
				}),
			}),
		}),
	})
end

local function manifestTile(props)
	local item = props.item or {}
	local accent = item.accentColor or PALETTE.Cyan
	local isEquipped = item.isEquipped == true
	local isLockedSlot = item.lockedSlot == true
	local isEmptySlot = item.emptySlot == true
	local interactive = item.interactive == true
	local hovered, pressed, handlers, hoverRef = useInteractiveState(interactive)
	local heldHover = hovered
	local heldEquipped = isEquipped and not hovered
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

	local previewChild = if isLockedSlot
		then lockGlyph(accent, 3)
		else renderItemPreview(item, {
			position = UDim2.fromScale(0.5, 0.5),
			size = UDim2.fromOffset(74, 74),
			zIndex = 3,
			fallbackFont = Enum.Font.GothamBold,
			fallbackTextColor = PALETTE.Cream,
			fallbackTextSize = isEmptySlot and 34 or 20,
			fallbackSize = UDim2.new(1, -10, 1, -10),
		})

	return e("TextButton", tileProps, {
		Scale = e("UIScale", {
			Scale = heldScale - (pressed and 0.018 or 0),
		}),
		Corner = e("UICorner", {
			CornerRadius = UDim.new(0, 10),
		}),
		Stroke = e("UIStroke", {
			Color = isEquipped and PALETTE.Cream or accent,
			Transparency = hovered and 0 or (isEquipped and 0.02 or 0.12),
			Thickness = hovered and 2.4 or (isEquipped and 2.5 or 1.8),
		}),
		Glow = e("UIStroke", {
			Color = accent,
			Transparency = hovered and 0.66 or (isEquipped and 0.72 or 0.92),
			Thickness = hovered and 4 or (isEquipped and 4.8 or 3.4),
		}),
		Gradient = e("UIGradient", {
			Rotation = 90,
			Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, isEquipped and accent:Lerp(tileBaseTop, 0.7) or tileBaseTop),
				ColorSequenceKeypoint.new(1, isEquipped and accent:Lerp(tileBaseBottom, 0.64) or tileBaseBottom),
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
			ClipsDescendants = true,
			Position = UDim2.fromOffset(10, 12),
			Size = UDim2.new(1, -20, 0, 84),
			ZIndex = 2,
		}, {
			Corner = e("UICorner", {
				CornerRadius = UDim.new(0, 7),
			}),
			Stroke = e("UIStroke", {
				Color = accent,
				Transparency = hovered and 0.18 or (isEquipped and 0.08 or 0.38),
				Thickness = hovered and 1.2 or (isEquipped and 1.6 or 1),
			}),
			HoverWash = e("Frame", {
				BackgroundColor3 = accent,
				BackgroundTransparency = hovered and 0.74 or (isEquipped and 0.78 or 0.88),
				BorderSizePixel = 0,
				Size = UDim2.fromScale(1, 1),
				ZIndex = 1,
			}, {
				Corner = e("UICorner", {
					CornerRadius = UDim.new(0, 7),
				}),
			}),
			EquippedRibbon = isEquipped and e("Frame", {
				AnchorPoint = Vector2.new(0.5, 1),
				BackgroundColor3 = accent,
				BackgroundTransparency = 0.02,
				BorderSizePixel = 0,
				Position = UDim2.new(0.5, 0, 1, -6),
				Size = UDim2.new(1, -16, 0, 18),
				ZIndex = 4,
			}, {
				Corner = e("UICorner", {
					CornerRadius = UDim.new(0, 999),
				}),
				Stroke = e("UIStroke", {
					Color = PALETTE.Cream,
					Transparency = 0.16,
					Thickness = 1.1,
				}),
				Label = e("TextLabel", {
					BackgroundTransparency = 1,
					Size = UDim2.fromScale(1, 1),
					Font = Enum.Font.GothamBold,
					Text = "IN HAND",
					TextColor3 = PALETTE.Text,
					TextSize = 9,
					ZIndex = 5,
				}),
			}) or nil,
			Preview = previewChild,
		}),
		EquippedCorner = isEquipped and e("TextLabel", {
			AnchorPoint = Vector2.new(1, 0),
			AutomaticSize = Enum.AutomaticSize.XY,
			BackgroundColor3 = PALETTE.Cream,
			BackgroundTransparency = 0.02,
			Position = UDim2.new(1, -8, 0, 8),
			Font = Enum.Font.GothamBold,
			Text = "EQUIPPED",
			TextColor3 = Color3.fromRGB(14, 21, 22),
			TextSize = 9,
			ZIndex = 5,
		}, {
			Corner = e("UICorner", {
				CornerRadius = UDim.new(0, 999),
			}),
			Padding = e("UIPadding", {
				PaddingTop = UDim.new(0, 3),
				PaddingBottom = UDim.new(0, 3),
				PaddingLeft = UDim.new(0, 8),
				PaddingRight = UDim.new(0, 8),
			}),
		}) or nil,
		Name = e("TextLabel", {
			BackgroundTransparency = 1,
			Font = Enum.Font.GothamBold,
			Position = UDim2.fromOffset(10, 101),
			Size = UDim2.new(1, -20, 0, 20),
			Text = item.displayName or "",
			TextColor3 = (isEquipped and PALETTE.Text)
				or (isLockedSlot and Color3.fromRGB(224, 229, 238))
				or PALETTE.Cream,
			TextSize = 12,
			TextTruncate = Enum.TextTruncate.AtEnd,
			TextWrapped = false,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 3,
		}),
		Status = (isEquipped or isLockedSlot or isEmptySlot) and e("TextLabel", {
			BackgroundTransparency = 1,
			Font = Enum.Font.GothamBold,
			Position = UDim2.fromOffset(10, 118),
			Size = UDim2.new(1, -54, 0, 12),
			Text = isEquipped and "Currently in your hand"
				or (isLockedSlot and tostring(item.footer or "Locked"))
				or "Available",
			TextColor3 = isLockedSlot and PALETTE.Gold or accent:Lerp(PALETTE.Cream, 0.35),
			TextSize = 8,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 4,
		}) or nil,
		Quantity = (not isLockedSlot and not isEmptySlot) and e("TextLabel", {
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
		}) or nil,
	})
end

local function crewInventoryIndexTile(props)
	local item = props.item or {}
	local quantity = math.max(1, math.floor(tonumber(item.quantity) or 1))
	local unit = {
		discovered = true,
		itemKind = "CrewMember",
		name = item.name,
		displayName = item.displayName,
		rarity = item.subtitle,
		image = item.image,
		staticPreviewImage = item.staticPreviewImage,
		previewKind = item.previewKind,
		previewName = item.previewName,
		crewModelName = item.previewName,
	}

	return e("Frame", {
		BackgroundTransparency = 1,
		LayoutOrder = props.layoutOrder or 0,
		Size = UDim2.fromScale(1, 1),
	}, {
		Card = e(IndexCard, {
			unit = unit,
			layoutOrder = props.layoutOrder,
			renderPreview = true,
			onActivated = item.interactive ~= false and props.onActivated ~= nil and function()
				props.onActivated(item)
			end or nil,
		}),
		Quantity = e("TextLabel", {
			AnchorPoint = Vector2.new(1, 0),
			AutomaticSize = Enum.AutomaticSize.XY,
			BackgroundColor3 = Color3.fromRGB(25, 36, 50),
			BackgroundTransparency = 0.04,
			Font = Enum.Font.GothamBold,
			Position = UDim2.new(1, -10, 0, 10),
			Text = "x" .. tostring(quantity),
			TextColor3 = PALETTE.Cream,
			TextSize = 12,
			TextStrokeTransparency = 0.72,
			ZIndex = 8,
		}, {
			Corner = e("UICorner", {
				CornerRadius = UDim.new(1, 0),
			}),
			Stroke = e("UIStroke", {
				Color = item.accentColor or PALETTE.Cyan,
				Transparency = 0.14,
				Thickness = 1,
			}),
			Padding = e("UIPadding", {
				PaddingTop = UDim.new(0, 4),
				PaddingBottom = UDim.new(0, 4),
				PaddingLeft = UDim.new(0, 8),
				PaddingRight = UDim.new(0, 8),
			}),
		}),
		Equipped = item.isEquipped == true and e("TextLabel", {
			AnchorPoint = Vector2.new(0.5, 0),
			AutomaticSize = Enum.AutomaticSize.XY,
			BackgroundColor3 = PALETTE.Cream,
			BackgroundTransparency = 0.02,
			Font = Enum.Font.GothamBold,
			Position = UDim2.new(0.5, 0, 0, 10),
			Text = "IN HAND",
			TextColor3 = Color3.fromRGB(14, 21, 22),
			TextSize = 10,
			ZIndex = 8,
		}, {
			Corner = e("UICorner", {
				CornerRadius = UDim.new(1, 0),
			}),
			Padding = e("UIPadding", {
				PaddingTop = UDim.new(0, 4),
				PaddingBottom = UDim.new(0, 4),
				PaddingLeft = UDim.new(0, 10),
				PaddingRight = UDim.new(0, 10),
			}),
		}) or nil,
	})
end

local function chestOpenQuantityPrompt(props)
	local maxAmount = math.max(1, math.floor(tonumber(props.maxAmount) or 1))
	local amount = math.clamp(math.floor(tonumber(props.amount) or 1), 1, maxAmount)
	local progress = if maxAmount <= 1 then 1 else (amount - 1) / (maxAmount - 1)
	local mobile = isMobileViewport()
	local panelHeight = mobile and 230 or 278
	local panelMaxSize = mobile and Vector2.new(360, panelHeight) or Vector2.new(430, panelHeight)
	local titleY = mobile and 16 or 24
	local amountY = mobile and 54 or 76
	local presetY = mobile and 88 or 114
	local trackY = mobile and 124 or 154
	local buttonY = mobile and 176 or 214
	local buttonHeight = mobile and 34 or 42
	local trackRef = React.useRef(nil)
	local draggingRef = React.useRef(false)
	local changedConnectionRef = React.useRef(nil)
	local endedConnectionRef = React.useRef(nil)
	local knobHovered, setKnobHovered = React.useState(false)
	local dropRatesHovered, setDropRatesHovered = React.useState(false)

	local function disconnectDragConnections()
		if changedConnectionRef.current then
			changedConnectionRef.current:Disconnect()
			changedConnectionRef.current = nil
		end
		if endedConnectionRef.current then
			endedConnectionRef.current:Disconnect()
			endedConnectionRef.current = nil
		end
	end

	local function setAmountFromScreenX(screenX)
		local track = trackRef.current
		if not track or maxAmount <= 1 then
			return
		end
		local width = track.AbsoluteSize.X
		if width <= 0 then
			return
		end
		local normalized = math.clamp((screenX - track.AbsolutePosition.X) / width, 0, 1)
		local nextAmount = math.clamp(math.floor((normalized * (maxAmount - 1)) + 1.5), 1, maxAmount)
		if props.onAmountChanged then
			props.onAmountChanged(nextAmount)
		end
	end

	local function endDrag()
		draggingRef.current = false
		disconnectDragConnections()
	end

	local function beginDrag(_, input)
		local inputType = input and input.UserInputType
		if inputType ~= Enum.UserInputType.MouseButton1 and inputType ~= Enum.UserInputType.Touch then
			return
		end

		draggingRef.current = true
		setAmountFromScreenX(input.Position.X)
		disconnectDragConnections()
		changedConnectionRef.current = UserInputService.InputChanged:Connect(function(changedInput)
			if not draggingRef.current then
				return
			end
			if
				changedInput.UserInputType == Enum.UserInputType.MouseMovement
				or changedInput.UserInputType == Enum.UserInputType.Touch
			then
				setAmountFromScreenX(changedInput.Position.X)
			end
		end)
		endedConnectionRef.current = UserInputService.InputEnded:Connect(function(endedInput)
			if
				endedInput.UserInputType == Enum.UserInputType.MouseButton1
				or endedInput.UserInputType == Enum.UserInputType.Touch
			then
				endDrag()
			end
		end)
	end

	React.useEffect(function()
		return function()
			endDrag()
		end
	end, {})

	local function buildPresetButtons()
		local presetChildren = {
			Layout = e("UIListLayout", {
				FillDirection = Enum.FillDirection.Horizontal,
				HorizontalAlignment = Enum.HorizontalAlignment.Center,
				Padding = UDim.new(0, mobile and 6 or 8),
				SortOrder = Enum.SortOrder.LayoutOrder,
				VerticalAlignment = Enum.VerticalAlignment.Center,
			}),
		}
		local presets = {
			{ label = "1", value = 1 },
			{ label = "3", value = 3 },
			{ label = "10", value = 10 },
			{ label = "Max", value = maxAmount, alwaysEnabled = true },
		}

		for index, preset in ipairs(presets) do
			local clampedValue = math.clamp(preset.value, 1, maxAmount)
			local enabled = preset.alwaysEnabled == true or preset.value <= maxAmount
			local selected = enabled and amount == clampedValue
			presetChildren["Preset" .. tostring(index)] = e("TextButton", {
				AutoButtonColor = enabled,
				BackgroundColor3 = if selected then INVENTORY_UI.GoldHighlight else INVENTORY_UI.ButtonIdle,
				BackgroundTransparency = if enabled then 0 else 0.45,
				BorderSizePixel = 0,
				Font = Enum.Font.GothamBold,
				LayoutOrder = index,
				Size = UDim2.new(0.25, mobile and -6 or -8, 1, 0),
				Text = preset.label,
				TextColor3 = if selected then PALETTE.Ink else INVENTORY_UI.TextMain,
				TextSize = mobile and 12 or 14,
				ZIndex = 32,
				[React.Event.Activated] = function()
					if enabled and props.onAmountChanged then
						props.onAmountChanged(clampedValue)
					end
				end,
			}, {
				Corner = e("UICorner", { CornerRadius = UDim.new(0, 9) }),
				Stroke = e("UIStroke", {
					Color = INVENTORY_UI.GoldHighlight,
					Transparency = selected and 0.08 or 0.42,
					Thickness = 1,
				}),
			})
		end

		return e("Frame", {
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(32, presetY),
			Size = UDim2.new(1, -64, 0, mobile and 26 or 30),
			ZIndex = 32,
		}, presetChildren)
	end

	return e("Frame", {
		BackgroundColor3 = INVENTORY_UI.MenuOverlay,
		BackgroundTransparency = 0.08,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 30,
	}, {
		Shade = e("Frame", {
			BackgroundColor3 = PALETTE.Ink,
			BackgroundTransparency = 0.26,
			BorderSizePixel = 0,
			Size = UDim2.fromScale(1, 1),
			ZIndex = 30,
		}),
		Panel = e("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = INVENTORY_UI.SectionBg,
			BorderSizePixel = 0,
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.new(1, -24, 0, panelHeight),
			ZIndex = 31,
		}, {
			SizeConstraint = e("UISizeConstraint", {
				MaxSize = panelMaxSize,
			}),
			Corner = e("UICorner", { CornerRadius = UDim.new(0, 14) }),
			Stroke = e("UIStroke", {
				Color = INVENTORY_UI.GoldHighlight,
				Thickness = 1.5,
				Transparency = 0.08,
			}),
			Title = e("TextLabel", {
				BackgroundTransparency = 1,
				Font = Enum.Font.GothamBold,
				Position = UDim2.fromOffset(20, titleY),
				Size = UDim2.new(1, -48, 0, 34),
				Text = string.format("Open %s", tostring(props.displayName or "Chests")),
				TextColor3 = INVENTORY_UI.TextMain,
				TextSize = mobile and 20 or 26,
				TextXAlignment = Enum.TextXAlignment.Center,
				ZIndex = 32,
			}),
			Amount = e("TextLabel", {
				BackgroundTransparency = 1,
				Font = Enum.Font.GothamBold,
				Position = UDim2.fromOffset(20, amountY),
				Size = UDim2.new(1, -48, 0, 30),
				Text = string.format("%d / %d", amount, maxAmount),
				TextColor3 = INVENTORY_UI.GoldHighlight,
				TextSize = mobile and 20 or 24,
				TextXAlignment = Enum.TextXAlignment.Center,
				ZIndex = 32,
			}),
			Presets = buildPresetButtons(),
			Track = e("Frame", {
				ref = trackRef,
				BackgroundColor3 = INVENTORY_UI.ButtonIdle,
				BorderSizePixel = 0,
				Position = UDim2.fromOffset(32, trackY),
				Size = UDim2.new(1, -64, 0, mobile and 14 or 18),
				ZIndex = 32,
			}, {
				Corner = e("UICorner", { CornerRadius = UDim.new(1, 0) }),
				Fill = e("Frame", {
					BackgroundColor3 = INVENTORY_UI.GoldHighlight,
					BorderSizePixel = 0,
					Size = UDim2.fromScale(progress, 1),
					ZIndex = 33,
				}, {
					Corner = e("UICorner", { CornerRadius = UDim.new(1, 0) }),
				}),
				Hitbox = e("TextButton", {
					AutoButtonColor = false,
					BackgroundTransparency = 1,
					BorderSizePixel = 0,
					Position = UDim2.fromOffset(0, -10),
					Size = UDim2.new(1, 0, 1, 20),
					Text = "",
					ZIndex = 34,
					[React.Event.InputBegan] = beginDrag,
				}),
				Knob = e("TextButton", {
					AnchorPoint = Vector2.new(0.5, 0.5),
					AutoButtonColor = false,
					BackgroundColor3 = INVENTORY_UI.GoldHighlight,
					BorderSizePixel = 0,
					Position = UDim2.fromScale(progress, 0.5),
					Size = UDim2.fromOffset(if knobHovered then 28 else 24, if knobHovered then 28 else 24),
					Text = "",
					ZIndex = 35,
					[React.Event.MouseEnter] = function()
						setKnobHovered(true)
					end,
					[React.Event.MouseLeave] = function()
						setKnobHovered(false)
					end,
					[React.Event.InputBegan] = beginDrag,
				}, {
					Corner = e("UICorner", { CornerRadius = UDim.new(1, 0) }),
				}),
			}),
			DropRates = e("TextButton", {
				AutoButtonColor = false,
				BackgroundColor3 = INVENTORY_UI.ButtonIdle,
				BorderSizePixel = 0,
				Font = Enum.Font.GothamBold,
					Position = UDim2.fromOffset(20, buttonY),
					Size = UDim2.new(0.32, -15, 0, buttonHeight),
					Text = "Drop Rates",
				TextColor3 = INVENTORY_UI.GoldHighlight,
					TextSize = mobile and 12 or 15,
				ZIndex = 32,
				[React.Event.MouseEnter] = function()
					setDropRatesHovered(true)
				end,
				[React.Event.MouseLeave] = function()
					setDropRatesHovered(false)
				end,
				[React.Event.Activated] = props.onShowDropRates,
			}, {
				Corner = e("UICorner", { CornerRadius = UDim.new(0, 10) }),
				Stroke = e("UIStroke", {
					Color = INVENTORY_UI.GoldHighlight,
					Transparency = 0.18,
					Thickness = 1,
				}),
			}),
			DropRatesTooltip = dropRatesHovered and e("Frame", {
				AnchorPoint = Vector2.new(0, 1),
				BackgroundColor3 = INVENTORY_UI.ButtonIdle,
				BorderSizePixel = 0,
				Position = UDim2.fromOffset(24, buttonY - 8),
				Size = UDim2.fromOffset(210, 34),
				ZIndex = 36,
			}, {
				Corner = e("UICorner", { CornerRadius = UDim.new(0, 8) }),
				Stroke = e("UIStroke", {
					Color = INVENTORY_UI.GoldHighlight,
					Transparency = 0.28,
					Thickness = 1,
				}),
				Text = e("TextLabel", {
					BackgroundTransparency = 1,
					Font = Enum.Font.Gotham,
					Size = UDim2.fromScale(1, 1),
					Text = "View rewards and rarity chances",
					TextColor3 = INVENTORY_UI.TextMain,
					TextSize = 12,
					ZIndex = 37,
				}),
			}) or nil,
			Open = e("TextButton", {
				AutoButtonColor = false,
				BackgroundColor3 = INVENTORY_UI.GoldBase,
				BorderSizePixel = 0,
				Font = Enum.Font.GothamBold,
				Position = UDim2.new(0.32, 10, 0, buttonY),
				Size = UDim2.new(0.34, -16, 0, buttonHeight),
				Text = string.format("Open %d", amount),
				TextColor3 = PALETTE.Ink,
				TextSize = mobile and 13 or 16,
				ZIndex = 32,
				[React.Event.Activated] = props.onConfirm,
			}, {
				Corner = e("UICorner", { CornerRadius = UDim.new(0, 10) }),
			}),
			Cancel = e("TextButton", {
				AutoButtonColor = false,
				BackgroundColor3 = INVENTORY_UI.ButtonIdle,
				BorderSizePixel = 0,
				Font = Enum.Font.GothamBold,
				Position = UDim2.new(0.66, 4, 0, buttonY),
				Size = UDim2.new(0.34, -24, 0, buttonHeight),
				Text = "Cancel",
				TextColor3 = INVENTORY_UI.TextMain,
				TextSize = mobile and 13 or 16,
				ZIndex = 32,
				[React.Event.Activated] = props.onDismiss,
			}, {
				Corner = e("UICorner", { CornerRadius = UDim.new(0, 10) }),
				Stroke = e("UIStroke", {
					Color = INVENTORY_UI.GoldHighlight,
					Transparency = 0.35,
					Thickness = 1,
				}),
			}),
		}),
	})
end

local DROP_RATE_COLORS = {
	Common = Color3.fromRGB(194, 204, 220),
	Rare = Color3.fromRGB(112, 189, 255),
	Legendary = INVENTORY_UI.GoldHighlight,
	Mythic = Color3.fromRGB(240, 130, 255),
}

local function formatDropChance(chance)
	if chance == nil then
		return ""
	end

	local percent = math.max(0, tonumber(chance) or 0) * 100
	if percent >= 10 or percent % 1 == 0 then
		return string.format("%d%%", math.floor(percent + 0.5))
	elseif percent >= 1 then
		return string.format("%.1f%%", percent)
	end

	return string.format("%.2f%%", percent)
end

local function dropRateRow(row, order, compact)
	local amountSuffix = if row.amountText and row.amountText ~= "" then string.format(" x%s", row.amountText) else ""
	local nameColor = DROP_RATE_COLORS[row.rarity] or INVENTORY_UI.TextMain
	return e("Frame", {
		BackgroundColor3 = INVENTORY_UI.ButtonIdle,
		BackgroundTransparency = 0.16,
		BorderSizePixel = 0,
		LayoutOrder = order,
		Size = UDim2.new(1, 0, 0, compact and 28 or 34),
		ZIndex = 43,
	}, {
		Corner = e("UICorner", { CornerRadius = UDim.new(0, 8) }),
		Name = e("TextLabel", {
			BackgroundTransparency = 1,
			Font = Enum.Font.GothamMedium,
			Position = UDim2.fromOffset(12, 0),
			Size = UDim2.new(1, -108, 1, 0),
			Text = tostring(row.name or "Unknown") .. amountSuffix,
			TextColor3 = nameColor,
			TextSize = compact and 12 or 14,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 44,
		}),
		Chance = e("TextLabel", {
			AnchorPoint = Vector2.new(1, 0),
			BackgroundTransparency = 1,
			Font = Enum.Font.GothamBold,
			Position = UDim2.new(1, -12, 0, 0),
			Size = UDim2.fromOffset(88, compact and 28 or 34),
			Text = formatDropChance(row.chance),
			TextColor3 = INVENTORY_UI.GoldHighlight,
			TextSize = compact and 12 or 14,
			TextXAlignment = Enum.TextXAlignment.Right,
			ZIndex = 44,
		}),
	})
end

local function chestDropRatesPrompt(props)
	local sections = props.sections or {}
	local mobile = isMobileViewport()
	local children = {
		ListLayout = e("UIListLayout", {
			Padding = UDim.new(0, mobile and 8 or 12),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	}
	local layoutOrder = 0
	for sectionIndex, section in ipairs(sections) do
		layoutOrder += 1
		local sectionChildren = {
			ListLayout = e("UIListLayout", {
				Padding = UDim.new(0, mobile and 4 or 6),
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),
			Title = e("TextLabel", {
				BackgroundTransparency = 1,
				Font = Enum.Font.GothamBold,
				LayoutOrder = 1,
				Size = UDim2.new(1, 0, 0, mobile and 18 or 22),
				Text = tostring(section.title or "Drops"),
				TextColor3 = INVENTORY_UI.GoldHighlight,
				TextSize = mobile and 13 or 16,
				TextXAlignment = Enum.TextXAlignment.Left,
				ZIndex = 43,
			}),
			Note = section.note and e("TextLabel", {
				BackgroundTransparency = 1,
				Font = Enum.Font.Gotham,
				LayoutOrder = 2,
				Size = UDim2.new(1, 0, 0, mobile and 24 or 30),
				Text = tostring(section.note),
				TextColor3 = INVENTORY_UI.TextMuted,
				TextSize = mobile and 10 or 12,
				TextWrapped = true,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextYAlignment = Enum.TextYAlignment.Top,
				ZIndex = 43,
			}) or nil,
		}
		for rowIndex, row in ipairs(section.rows or {}) do
			sectionChildren["Row" .. tostring(rowIndex)] = dropRateRow(row, rowIndex + 2, mobile)
		end
		children["Section" .. tostring(sectionIndex)] = e("Frame", {
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
			LayoutOrder = layoutOrder,
			Size = UDim2.new(1, -8, 0, 0),
			ZIndex = 42,
		}, sectionChildren)
	end

	return e("Frame", {
		BackgroundColor3 = INVENTORY_UI.MenuOverlay,
		BackgroundTransparency = 0.08,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 40,
	}, {
		Shade = e("Frame", {
			BackgroundColor3 = PALETTE.Ink,
			BackgroundTransparency = 0.2,
			BorderSizePixel = 0,
			Size = UDim2.fromScale(1, 1),
			ZIndex = 40,
		}),
		Panel = e("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = INVENTORY_UI.SectionBg,
			BorderSizePixel = 0,
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.new(1, -24, 1, -24),
			ZIndex = 41,
		}, {
			SizeConstraint = e("UISizeConstraint", {
				MaxSize = mobile and Vector2.new(390, 330) or Vector2.new(520, 430),
			}),
			Corner = e("UICorner", { CornerRadius = UDim.new(0, 14) }),
			Stroke = e("UIStroke", {
				Color = INVENTORY_UI.GoldHighlight,
				Thickness = 1.5,
				Transparency = 0.08,
			}),
			Title = e("TextLabel", {
				BackgroundTransparency = 1,
				Font = Enum.Font.GothamBold,
				Position = UDim2.fromOffset(mobile and 16 or 22, mobile and 14 or 18),
				Size = UDim2.new(1, mobile and -62 or -74, 0, mobile and 24 or 28),
				Text = string.format("%s Drop Rates", tostring(props.chestName or "Chest")),
				TextColor3 = INVENTORY_UI.TextMain,
				TextSize = mobile and 18 or 24,
				TextXAlignment = Enum.TextXAlignment.Left,
				ZIndex = 42,
			}),
			Subtitle = e("TextLabel", {
				BackgroundTransparency = 1,
				Font = Enum.Font.Gotham,
				Position = UDim2.fromOffset(mobile and 16 or 22, mobile and 38 or 48),
				Size = UDim2.new(1, mobile and -32 or -44, 0, mobile and 18 or 20),
				Text = "Possible rewards and their chances",
				TextColor3 = INVENTORY_UI.TextMuted,
				TextSize = mobile and 11 or 13,
				TextXAlignment = Enum.TextXAlignment.Left,
				ZIndex = 42,
			}),
			Close = e("TextButton", {
				AnchorPoint = Vector2.new(1, 0),
				AutoButtonColor = false,
				BackgroundColor3 = INVENTORY_UI.ButtonIdle,
				BorderSizePixel = 0,
				Font = Enum.Font.GothamBold,
				Position = UDim2.new(1, mobile and -14 or -18, 0, mobile and 14 or 18),
				Size = UDim2.fromOffset(mobile and 30 or 34, mobile and 30 or 34),
				Text = "X",
				TextColor3 = INVENTORY_UI.GoldHighlight,
				TextSize = 16,
				ZIndex = 42,
				[React.Event.Activated] = props.onDismiss,
			}, {
				Corner = e("UICorner", { CornerRadius = UDim.new(0, 9) }),
			}),
			Scroll = e("ScrollingFrame", {
				AutomaticCanvasSize = Enum.AutomaticSize.Y,
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				CanvasSize = UDim2.new(),
				Position = UDim2.fromOffset(mobile and 16 or 22, mobile and 68 or 84),
				ScrollBarImageColor3 = INVENTORY_UI.GoldHighlight,
				ScrollBarThickness = 5,
				Size = UDim2.new(1, mobile and -32 or -44, 1, mobile and -86 or -106),
				ZIndex = 42,
			}, children),
		}),
	})
end

local function footerCategoryCell(props)
	local accent = props.accentColor or PALETTE.Sea

	return e("Frame", {
		BackgroundTransparency = 1,
		ClipsDescendants = true,
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
	local hasViewportPreview = entry.previewKind ~= nil
		and tostring(entry.previewKind) ~= ""
		and entry.previewName ~= nil
		and tostring(entry.previewName) ~= ""
	local staticPreviewImage = getStaticCrewPreviewImage(entry)

	local previewChild
	if staticPreviewImage ~= "" then
		previewChild = staticCrewPreviewImage(staticPreviewImage, {
			position = UDim2.fromScale(0.5, 0.5),
			size = UDim2.fromScale(1, 1),
			zIndex = 3,
		})
	elseif hasViewportPreview then
		previewChild = e(PreviewViewport, {
			previewKind = entry.previewKind,
			previewName = entry.previewName,
			position = UDim2.fromScale(0.5, 0.5),
			size = UDim2.fromOffset(70, 70),
			zIndex = 3,
			fieldOfView = 34,
		})
	elseif entry.image and entry.image ~= "" then
		previewChild = e("ImageLabel", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundTransparency = 1,
			Image = entry.image,
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(64, 64),
			ScaleType = Enum.ScaleType.Fit,
			ZIndex = 3,
		})
	else
		previewChild = e("TextLabel", {
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
	end

	return e("Frame", {
		BackgroundColor3 = Color3.fromRGB(16, 22, 35),
		BackgroundTransparency = 0.02,
		BorderSizePixel = 0,
		LayoutOrder = props.layoutOrder or 0,
		Size = UDim2.new(1, -6, 0, 88),
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
			ClipsDescendants = true,
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
			Text = string.format(
				"%s  |  %s",
				tostring(entry.subtitle or "Crewmate"),
				tostring(entry.standName or "Stand")
			),
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
				"Bounty: %s  |  %s ready",
				formatNumber(entry.bounty or 0),
				CurrencyUtil.formatCurrency(entry.collectable or 0)
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
			Text = formatRateNumber(entry.incomePerTick or 0),
			TextColor3 = PALETTE.Cream,
			TextSize = 24,
			TextStrokeTransparency = 0.58,
			TextXAlignment = Enum.TextXAlignment.Right,
			ZIndex = 3,
		}),
	})
end

local function crewProtectionActionButton(props)
	local enabled = props.enabled == true
	local accent = props.accentColor or PALETTE.Sea
	local hovered, pressed, handlers, hoverRef = useInteractiveState(enabled)
	local fill = if enabled then accent else (props.disabledColor or Color3.fromRGB(54, 62, 78))
	local textColor = if enabled then PALETTE.Ink else (props.disabledTextColor or Color3.fromRGB(214, 220, 232))

	return e("TextButton", mergeProps({
		AnchorPoint = props.anchorPoint or Vector2.new(0, 0),
		AutoButtonColor = false,
		BackgroundColor3 = fill,
		BackgroundTransparency = enabled and 0.02 or 0.28,
		BorderSizePixel = 0,
		Position = props.position or UDim2.new(),
		ref = hoverRef,
		Size = props.size or UDim2.fromOffset(112, 30),
		Text = tostring(props.text or ""),
		TextColor3 = textColor,
		TextSize = props.textSize or 11,
		TextWrapped = true,
		Font = Enum.Font.GothamBold,
		ZIndex = props.zIndex or 4,
		[React.Event.Activated] = if enabled then props.onActivated else nil,
	}, handlers), {
		Scale = e("UIScale", {
			Scale = (hovered and 1.02 or 1) - (pressed and 0.018 or 0),
		}),
		Corner = e("UICorner", {
			CornerRadius = UDim.new(0, 9),
		}),
		Stroke = e("UIStroke", {
			Color = enabled and PALETTE.Cream or Color3.fromRGB(105, 118, 141),
			Transparency = enabled and 0.78 or 0.44,
			Thickness = 1,
		}),
	})
end

local function crewManagementRow(props)
	local entry = props.entry or {}
	local protection = entry.protection or {}
	local pending = props.pending == true
	local accent = entry.accentColor or PALETTE.Sea
	local protectionKey = tostring(protection.key or "none")
	local permanent = protectionKey == "permanent"
	local statusAccent = if permanent
		then PALETTE.Violet:Lerp(PALETTE.Gold, 0.34)
		elseif protectionKey == "crew"
			then PALETTE.Green
		elseif protectionKey == "fleet"
			then PALETTE.Cyan
		else PALETTE.Steel
	local statusText = tostring(protection.statusLabel or protection.label or "Not Protected")
	local detailText = tostring(protection.detailLabel or protection.detail or "")
	if detailText == "" and (protectionKey == "crew" or protectionKey == "fleet") then
		local remaining = tonumber(protection.remainingSeconds) or 0
		if remaining > 0 then
			detailText = string.format("%s remaining", formatDuration(remaining))
		end
	elseif detailText == "" and permanent then
		detailText = "CANNOT BE STOLEN  |  Permanent Slot"
	end

	local hasViewportPreview = entry.previewKind ~= nil
		and tostring(entry.previewKind) ~= ""
		and entry.previewName ~= nil
		and tostring(entry.previewName) ~= ""
	local staticPreviewImage = getStaticCrewPreviewImage(entry)
	local previewChild
	if staticPreviewImage ~= "" then
		previewChild = staticCrewPreviewImage(staticPreviewImage, {
			position = UDim2.fromScale(0.5, 0.5),
			size = UDim2.fromScale(1, 1),
			zIndex = 3,
		})
	elseif hasViewportPreview then
		previewChild = e(PreviewViewport, {
			previewKind = entry.previewKind,
			previewName = entry.previewName,
			position = UDim2.fromScale(0.5, 0.5),
			size = UDim2.fromOffset(76, 76),
			zIndex = 3,
			fieldOfView = 34,
		})
	else
		previewChild = e("TextLabel", {
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
	end

	local crewEnabled = entry.canApplyCrewShield == true and not pending
	local permanentEnabled = entry.canApplyPermanentSlot == true and not pending
	local crewButtonText = if pending then "Working..." else tostring(entry.crewShieldButtonText or "Apply Shield")
	local permanentButtonText = if pending then "Working..." else tostring(entry.permanentButtonText or "Apply Permanent")

	return e("Frame", {
		BackgroundColor3 = permanent and Color3.fromRGB(35, 24, 58) or Color3.fromRGB(16, 22, 35),
		BackgroundTransparency = permanent and 0 or 0.02,
		BorderSizePixel = 0,
		LayoutOrder = props.layoutOrder or 0,
		Size = UDim2.new(1, -6, 0, 132),
	}, {
		Corner = e("UICorner", {
			CornerRadius = UDim.new(0, 12),
		}),
		Stroke = e("UIStroke", {
			Color = permanent and statusAccent or accent,
			Transparency = permanent and 0.02 or 0.16,
			Thickness = permanent and 2.35 or 1.35,
		}),
		Glow = e("UIStroke", {
			Color = statusAccent,
			Transparency = permanent and 0.74 or 0.93,
			Thickness = permanent and 4 or 2,
		}),
		Accent = e("Frame", {
			BackgroundColor3 = permanent and statusAccent or accent,
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
			ClipsDescendants = true,
			Position = UDim2.fromOffset(16, 14),
			Size = UDim2.fromOffset(76, 78),
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
			Position = UDim2.fromOffset(106, 10),
			Size = UDim2.new(1, -390, 0, 28),
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
			Position = UDim2.fromOffset(108, 38),
			Size = UDim2.new(1, -410, 0, 18),
			Text = string.format("%s  |  %s", tostring(entry.subtitle or "Crewmate"), tostring(entry.standName or "Owned")),
			TextColor3 = Color3.fromRGB(181, 191, 210),
			TextSize = 12,
			TextTruncate = Enum.TextTruncate.AtEnd,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 3,
		}),
		Footer = e("TextLabel", {
			BackgroundTransparency = 1,
			Font = Enum.Font.GothamBold,
			Position = UDim2.fromOffset(108, 58),
			Size = UDim2.new(1, -410, 0, 16),
			Text = string.format(
				"Bounty: %s  |  %s",
				formatNumber(entry.bounty or 0),
				if entry.isPlaced then (CurrencyUtil.formatCurrency(entry.collectable or 0) .. " ready") else "not placed"
			),
			TextColor3 = accent,
			TextSize = 12,
			TextTruncate = Enum.TextTruncate.AtEnd,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 3,
		}),
		StatusBadge = e("Frame", {
			BackgroundColor3 = statusAccent,
			BackgroundTransparency = protectionKey == "none" and 0.54 or 0.04,
			BorderSizePixel = 0,
			Position = UDim2.fromOffset(108, 80),
			Size = UDim2.fromOffset(permanent and 248 or 194, 28),
			ZIndex = 3,
		}, {
			Corner = e("UICorner", {
				CornerRadius = UDim.new(0, 999),
			}),
			Stroke = e("UIStroke", {
				Color = permanent and PALETTE.Gold or statusAccent,
				Transparency = permanent and 0.16 or 0.42,
				Thickness = 1,
			}),
			Label = e("TextLabel", {
				BackgroundTransparency = 1,
				Font = Enum.Font.GothamBold,
				Position = UDim2.fromOffset(10, 0),
				Size = UDim2.new(1, -20, 1, 0),
				Text = statusText,
				TextColor3 = protectionKey == "none" and PALETTE.Cream or PALETTE.Ink,
				TextSize = permanent and 13 or 12,
				TextTruncate = Enum.TextTruncate.AtEnd,
				TextXAlignment = Enum.TextXAlignment.Left,
				ZIndex = 4,
			}),
		}),
		StatusDetail = detailText ~= "" and e("TextLabel", {
			BackgroundTransparency = 1,
			Font = permanent and Enum.Font.GothamBold or Enum.Font.Gotham,
			Position = UDim2.fromOffset(108, 108),
			Size = UDim2.new(1, -430, 0, 18),
			Text = detailText,
			TextColor3 = permanent and PALETTE.Gold or INVENTORY_UI.TextMuted,
			TextSize = permanent and 12 or 11,
			TextTruncate = Enum.TextTruncate.AtEnd,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 3,
		}) or nil,
		IncomeLabel = e("TextLabel", {
			AnchorPoint = Vector2.new(1, 0),
			BackgroundTransparency = 1,
			Font = Enum.Font.GothamBold,
			Position = UDim2.new(1, -18, 0, 14),
			Size = UDim2.fromOffset(160, 14),
			Text = if entry.isPlaced then "Making" else "Status",
			TextColor3 = PALETTE.Muted,
			TextSize = 11,
			TextXAlignment = Enum.TextXAlignment.Right,
			ZIndex = 3,
		}),
		IncomeValue = e("TextLabel", {
			AnchorPoint = Vector2.new(1, 0),
			BackgroundTransparency = 1,
			Font = Enum.Font.Cartoon,
			Position = UDim2.new(1, -18, 0, 31),
			Size = UDim2.fromOffset(190, 30),
			Text = if entry.isPlaced then formatRateNumber(entry.incomePerTick or 0) else "Owned",
			TextColor3 = PALETTE.Cream,
			TextSize = 24,
			TextStrokeTransparency = 0.58,
			TextXAlignment = Enum.TextXAlignment.Right,
			ZIndex = 3,
		}),
		CrewShieldButton = e(crewProtectionActionButton, {
			anchorPoint = Vector2.new(1, 0),
			position = UDim2.new(1, -166, 0, 88),
			size = UDim2.fromOffset(140, 32),
			text = crewButtonText,
			accentColor = PALETTE.Green,
			disabledColor = Color3.fromRGB(64, 72, 88),
			textSize = 10,
			enabled = crewEnabled,
			zIndex = 4,
			onActivated = function()
				if props.onApplyCrewShield then
					props.onApplyCrewShield(entry)
				end
			end,
		}),
		PermanentButton = e(crewProtectionActionButton, {
			anchorPoint = Vector2.new(1, 0),
			position = UDim2.new(1, -18, 0, 88),
			size = UDim2.fromOffset(140, 32),
			text = permanentButtonText,
			accentColor = PALETTE.Violet:Lerp(PALETTE.Gold, 0.34),
			disabledColor = Color3.fromRGB(64, 72, 88),
			textSize = 10,
			enabled = permanentEnabled,
			zIndex = 4,
			onActivated = function()
				if props.onApplyPermanentSlot then
					props.onApplyPermanentSlot(entry)
				end
			end,
		}),
	})
end

local function crewManagementSummary(props)
	local data = props.data or {}
	local resources = data.resources or {}
	local fleetShield = data.fleetShield or {}
	local feedback = data.feedback
	local pending = data.pending == true
	local active = fleetShield.active == true
	local defaultStatusText = if active then "ACTIVE" else "OFF"
	local defaultRemainingText = if active then formatDuration(fleetShield.remainingSeconds or 0) else "Not Running"
	local defaultFleetButtonText = if active then "TURN OFF" else "NO FLEET SHIELDS"
	local defaultFleetActionName = if active then "PauseFleetShield" else "ActivateFleetShield"
	local statusText = string.upper(tostring(fleetShield.statusLabel or defaultStatusText))
	local statusColor = if active then PALETTE.Green else PALETTE.Rose
	local remainingText = tostring(fleetShield.remainingLabel or defaultRemainingText)
	local fleetButtonText = if pending then "WORKING..." else tostring(fleetShield.buttonText or defaultFleetButtonText)
	local fleetButtonEnabled = pending ~= true and (
		fleetShield.buttonEnabled == true
		or active
		or math.max(0, tonumber(resources.fleetShields) or 0) > 0
	)
	local fleetActionName = tostring(fleetShield.actionName or defaultFleetActionName)
	local children = {
		Corner = e("UICorner", {
			CornerRadius = UDim.new(0, 10),
		}),
		Stroke = e("UIStroke", {
			Color = Color3.fromRGB(72, 93, 134),
			Transparency = 0.12,
		}),
		Title = e("TextLabel", {
			BackgroundTransparency = 1,
			Font = Enum.Font.GothamBold,
			Position = UDim2.fromOffset(16, 10),
			Size = UDim2.new(1, -250, 0, 14),
			Text = "Crew Protection Tools",
			TextColor3 = PALETTE.Muted,
			TextSize = 11,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 9,
		}),
		FleetTitle = e("TextLabel", {
			BackgroundTransparency = 1,
			Font = Enum.Font.Cartoon,
			Position = UDim2.fromOffset(16, 62),
			Size = UDim2.fromOffset(142, 25),
			Text = "Fleet Shield",
			TextColor3 = PALETTE.Cyan,
			TextSize = 24,
			TextStrokeTransparency = 0.56,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 9,
		}),
		FleetStatus = e("Frame", {
			BackgroundColor3 = statusColor,
			BackgroundTransparency = active and 0.04 or 0.12,
			BorderSizePixel = 0,
			Position = UDim2.fromOffset(166, 61),
			Size = UDim2.fromOffset(96, 28),
			ZIndex = 9,
		}, {
			Corner = e("UICorner", {
				CornerRadius = UDim.new(0, 999),
			}),
			Stroke = e("UIStroke", {
				Color = active and PALETTE.Cream or PALETTE.Rose,
				Transparency = active and 0.72 or 0.34,
				Thickness = 1,
			}),
			Label = e("TextLabel", {
				BackgroundTransparency = 1,
				Font = Enum.Font.GothamBold,
				Position = UDim2.fromOffset(10, 0),
				Size = UDim2.new(1, -20, 1, 0),
				Text = statusText,
				TextColor3 = PALETTE.Ink,
				TextSize = 13,
				TextXAlignment = Enum.TextXAlignment.Center,
				ZIndex = 10,
			}),
		}),
		Remaining = e("TextLabel", {
			BackgroundTransparency = 1,
			Font = Enum.Font.GothamBold,
			Position = UDim2.fromOffset(16, 91),
			Size = UDim2.new(1, -260, 0, 16),
			Text = "Remaining Time: " .. remainingText,
			TextColor3 = active and PALETTE.Green or INVENTORY_UI.TextMuted,
			TextSize = 12,
			TextTruncate = Enum.TextTruncate.AtEnd,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 9,
		}),
		FleetHelper = e("TextLabel", {
			BackgroundTransparency = 1,
			Font = Enum.Font.GothamBold,
			Position = UDim2.fromOffset(16, 110),
			Size = UDim2.new(1, -260, 0, 14),
			Text = tostring(fleetShield.helperText or "Protects ALL placed crewmates"),
			TextColor3 = PALETTE.Cyan,
			TextSize = 11,
			TextTruncate = Enum.TextTruncate.AtEnd,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 9,
		}),
		FleetButton = e(crewProtectionActionButton, {
			anchorPoint = Vector2.new(1, 0),
			position = UDim2.new(1, -16, 0, 72),
			size = UDim2.fromOffset(184, 34),
			text = fleetButtonText,
			accentColor = if active then PALETTE.Rose else PALETTE.Cyan,
			disabledColor = Color3.fromRGB(68, 74, 88),
			enabled = fleetButtonEnabled,
			zIndex = 10,
			onActivated = function()
				if props.onFleetShieldAction then
					props.onFleetShieldAction(fleetActionName)
				end
			end,
		}),
	}

	local chipData = {
		{ label = "Crew Shields", value = resources.crewShields or 0, color = PALETTE.Green },
		{ label = "Fleet Shields", value = resources.fleetShields or 0, color = PALETTE.Cyan },
		{ label = "Permanent Slots", value = resources.permanentSlots or 0, color = PALETTE.Violet:Lerp(PALETTE.Gold, 0.34) },
	}
	for index, chip in ipairs(chipData) do
		children["Chip" .. tostring(index)] = e("Frame", {
			BackgroundColor3 = INVENTORY_UI.ButtonIdle,
			BackgroundTransparency = 0.1,
			BorderSizePixel = 0,
			Position = UDim2.fromOffset(16 + ((index - 1) * 150), 28),
			Size = UDim2.fromOffset(138, 24),
			ZIndex = 9,
		}, {
			Corner = e("UICorner", {
				CornerRadius = UDim.new(0, 999),
			}),
			Stroke = e("UIStroke", {
				Color = chip.color,
				Transparency = 0.38,
				Thickness = 1,
			}),
			Label = e("TextLabel", {
				BackgroundTransparency = 1,
				Font = Enum.Font.GothamBold,
				Position = UDim2.fromOffset(10, 0),
				Size = UDim2.new(1, -48, 1, 0),
				Text = chip.label,
				TextColor3 = PALETTE.Cream,
				TextSize = 10,
				TextTruncate = Enum.TextTruncate.AtEnd,
				TextXAlignment = Enum.TextXAlignment.Left,
				ZIndex = 10,
			}),
			Value = e("TextLabel", {
				AnchorPoint = Vector2.new(1, 0),
				BackgroundTransparency = 1,
				Font = Enum.Font.GothamBold,
				Position = UDim2.new(1, -10, 0, 0),
				Size = UDim2.fromOffset(34, 24),
				Text = tostring(chip.value or 0),
				TextColor3 = chip.color,
				TextSize = 12,
				TextXAlignment = Enum.TextXAlignment.Right,
				ZIndex = 10,
			}),
		})
	end

	if typeof(feedback) == "table" and tostring(feedback.message or "") ~= "" then
		children.Feedback = e("TextLabel", {
			AnchorPoint = Vector2.new(1, 0),
			BackgroundTransparency = 1,
			Font = Enum.Font.GothamBold,
			Position = UDim2.new(1, -16, 0, 28),
			Size = UDim2.fromOffset(220, 18),
			Text = tostring(feedback.message),
			TextColor3 = feedback.ok == true and PALETTE.Green or PALETTE.Rose,
			TextSize = 10,
			TextTruncate = Enum.TextTruncate.AtEnd,
			TextXAlignment = Enum.TextXAlignment.Right,
			ZIndex = 10,
		})
	end

	return e("Frame", {
		BackgroundColor3 = Color3.fromRGB(16, 22, 37),
		BackgroundTransparency = 0.04,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(14, 14),
		Size = UDim2.new(1, -28, 0, 128),
		ZIndex = 8,
	}, children)
end

local function titleRegistryRow(props)
	local entry = props.entry or {}
	local unlocked = entry.unlocked == true
	local isEquipped = entry.isEquipped == true
	local canToggleEquipped = isEquipped or unlocked
	local actionLabel = if isEquipped then "Unequip" elseif unlocked then "Equip" else nil
	local requirementText = tostring(entry.requirementText or "")
	local showEquipButton = actionLabel ~= nil
	local accent = entry.accentColor or (unlocked and PALETTE.Gold or PALETTE.Steel)
	local surfaceColor = entry.surfaceColor or Color3.fromRGB(16, 22, 35)
	local surfaceColor2 = entry.surfaceColor2 or Color3.fromRGB(10, 15, 25)
	local sealColor = entry.sealColor or accent:Lerp(Color3.fromRGB(52, 57, 74), unlocked and 0.62 or 0.82)
	local stateFill = unlocked and (entry.stateColor or accent) or Color3.fromRGB(44, 51, 67)
	local stateTextColor = unlocked and PALETTE.Ink or PALETTE.Cream
	local badgeText = string.upper(if isEquipped then "Equipped" elseif unlocked then "Unlocked" else "Locked")

	return e("Frame", {
		BackgroundColor3 = surfaceColor,
		BackgroundTransparency = 0.02,
		BorderSizePixel = 0,
		LayoutOrder = props.layoutOrder or 0,
		Size = UDim2.new(1, -6, 0, 104),
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
			Text = badgeText,
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
		Requirement = requirementText ~= "" and e("TextLabel", {
			BackgroundTransparency = 1,
			Font = Enum.Font.GothamMedium,
			Position = UDim2.fromOffset(106, 76),
			Size = UDim2.new(1, -176, 0, 16),
			Text = "Requirement: " .. requirementText,
			TextColor3 = unlocked and PALETTE.Cream or PALETTE.Muted,
			TextSize = 11,
			TextTruncate = Enum.TextTruncate.AtEnd,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 3,
		}) or nil,
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
		Action = showEquipButton and e("TextButton", {
			AnchorPoint = Vector2.new(1, 0.5),
			AutoButtonColor = false,
			BackgroundColor3 = isEquipped and Color3.fromRGB(44, 54, 72) or accent,
			BackgroundTransparency = canToggleEquipped and 0.02 or 0.28,
			BorderSizePixel = 0,
			Position = UDim2.new(1, -18, 0.5, 0),
			Size = UDim2.fromOffset(104, 34),
			Text = actionLabel,
			TextColor3 = isEquipped and PALETTE.Cream or Color3.fromRGB(14, 21, 22),
			TextSize = 16,
			Font = Enum.Font.GothamBold,
			ZIndex = 3,
			[React.Event.Activated] = function()
				if canToggleEquipped and props.onToggleTitle then
					props.onToggleTitle(entry)
				end
			end,
		}, {
			Corner = e("UICorner", {
				CornerRadius = UDim.new(0, 10),
			}),
			Stroke = e("UIStroke", {
				Color = accent,
				Transparency = isEquipped and 0.08 or 0.72,
				Thickness = isEquipped and 1.2 or 1,
			}),
		}) or nil,
	})
end

local function shipUpgradeModal(props)
	local modal = props.modal or {}
	local lines = modal.Lines or modal.lines or {}
	local accent = modal.IsError and PALETTE.Rose or (modal.IsMaxLevel and PALETTE.Gold or PALETTE.Green)
	local mobile = isMobileViewport()
	local listChildren = {
		List = e("UIListLayout", {
			FillDirection = Enum.FillDirection.Vertical,
			Padding = UDim.new(0, mobile and 6 or 8),
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
			Size = UDim2.fromScale(1, 0),
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
				PaddingTop = UDim.new(0, mobile and 8 or 10),
				PaddingBottom = UDim.new(0, mobile and 8 or 10),
				PaddingLeft = UDim.new(0, mobile and 12 or 14),
				PaddingRight = UDim.new(0, mobile and 12 or 14),
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
				TextSize = mobile and 13 or 16,
				TextWrapped = true,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextYAlignment = Enum.TextYAlignment.Top,
				ZIndex = 85,
			}),
		})
	end

	return e("ScreenGui", {
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
				Size = UDim2.fromOffset(mobile and 356 or 500, 0),
				ZIndex = 80,
			}, {
				SizeConstraint = e("UISizeConstraint", {
					MaxSize = mobile and Vector2.new(380, 520) or Vector2.new(540, 720),
					MinSize = mobile and Vector2.new(280, 0) or Vector2.new(440, 0),
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
					PaddingTop = UDim.new(0, mobile and 14 or 18),
					PaddingBottom = UDim.new(0, mobile and 14 or 18),
					PaddingLeft = UDim.new(0, mobile and 14 or 18),
					PaddingRight = UDim.new(0, mobile and 14 or 18),
				}),
				List = e("UIListLayout", {
					FillDirection = Enum.FillDirection.Vertical,
					Padding = UDim.new(0, mobile and 8 or 12),
					SortOrder = Enum.SortOrder.LayoutOrder,
				}),
				Eyebrow = e("TextLabel", {
					BackgroundTransparency = 1,
					Font = Enum.Font.GothamBold,
					LayoutOrder = 1,
					Size = UDim2.new(1, 0, 0, 16),
					Text = tostring(modal.AccentText or "Ship Upgrade Complete"),
					TextColor3 = accent,
					TextSize = mobile and 10 or 12,
					TextXAlignment = Enum.TextXAlignment.Left,
					ZIndex = 81,
				}),
				Title = e("TextLabel", {
					AutomaticSize = Enum.AutomaticSize.Y,
					BackgroundTransparency = 1,
					Font = Enum.Font.Cartoon,
					LayoutOrder = 2,
					Size = UDim2.fromScale(1, 0),
					Text = tostring(modal.Title or "Ship upgraded"),
					TextColor3 = PALETTE.Cream,
					TextSize = mobile and 26 or 34,
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
					Size = UDim2.fromScale(1, 0),
					ZIndex = 81,
				}, listChildren),
				ActionRow = e("Frame", {
					BackgroundTransparency = 1,
					LayoutOrder = 4,
					Size = UDim2.new(1, 0, 0, mobile and 38 or 44),
					ZIndex = 81,
				}, {
					Okay = e("TextButton", {
						AnchorPoint = Vector2.new(1, 0),
						AutoButtonColor = false,
						BackgroundColor3 = accent,
						BorderSizePixel = 0,
						Position = UDim2.fromScale(1, 0),
						Size = UDim2.fromOffset(mobile and 112 or 136, mobile and 36 or 42),
						Text = "Okay",
						TextColor3 = Color3.fromRGB(14, 21, 22),
						TextSize = mobile and 15 or 18,
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
	local crewQuickSlotsUnlocked = summary.crewQuickSlotsUnlocked or 0
	local crewQuickSlotsMax = summary.crewQuickSlotsMax or crewQuickSlotsUnlocked
	local activeView = props.activeView or "Inventory"
	local showingCaptainLog = activeView == "CaptainLog"
	local showingCrewManagement = activeView == "CrewManagement"
	local showingTitles = activeView == "Titles"
	local showingInventory = activeView == "Inventory"
	local toggleLayout = props.toggleLayout or {}
	local dockToggleLeft = toggleLayout.dock == "hotbarLeft"
	local dockToggleSlot = toggleLayout.dock == "hotbarSlot"
	local mobileLayout = toggleLayout.mobile == true
	local toggleSlotIndex = math.max(1, math.floor(tonumber(toggleLayout.slotIndex) or 5))
	local toggleWidth = dockToggleLeft and ((toggleLayout.size and toggleLayout.size.X.Offset) or 74) or 0
	local toggleGap = dockToggleLeft and (mobileLayout and 7 or 20) or 0
	local hotbarSlotCount = math.max(1, #(props.hotbarSlots or {}))
	local hotbarSlotWidth = mobileLayout and 50 or 64
	local hotbarSlotGap = mobileLayout and 5 or 10
	local hotbarWidth = hotbarSlotCount * hotbarSlotWidth + math.max(0, hotbarSlotCount - 1) * hotbarSlotGap
	local bottomBarWidth = dockToggleLeft and (toggleWidth + toggleGap + hotbarWidth) or hotbarWidth
	local toggleSlotX = math.max(0, (toggleSlotIndex - 1) * (hotbarSlotWidth + hotbarSlotGap))
	local resolvedTogglePosition = dockToggleLeft and UDim2.fromOffset(0, mobileLayout and 4 or 20)
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
	elseif showingCrewManagement then
		activeAccent = PALETTE.Violet:Lerp(PALETTE.Gold, 0.28)
	elseif showingTitles then
		activeAccent = PALETTE.Gold
	end

	local captainLogData = props.captainLog or {}
	local crewManagementData = props.crewManagement or {}
	local captainLogFilteredCount = math.max(0, math.floor(tonumber(captainLogData.filteredCount) or 0))
	local captainLogTotalCount = math.max(0, math.floor(tonumber(captainLogData.totalCount) or 0))
	local captainLogQuery = tostring(props.query or ""):gsub("^%s+", ""):gsub("%s+$", "")
	local captainLogHasFilter = captainLogQuery ~= ""
	local captainLogPlural = if captainLogTotalCount == 1 then "crewmate" else "crewmates"
	local captainLogInfoText
	if captainLogHasFilter then
		captainLogInfoText = string.format(
			"Showing %d of %d placed crewmates; totals include all slots",
			captainLogFilteredCount,
			captainLogTotalCount
		)
	else
		captainLogInfoText = string.format(
			"%d placed %s; totals include all slots",
			captainLogTotalCount,
			captainLogPlural
		)
	end
	local crewManagementFilteredCount = math.max(0, math.floor(tonumber(crewManagementData.filteredCount) or 0))
	local crewManagementTotalCount = math.max(0, math.floor(tonumber(crewManagementData.totalCount) or 0))
	local crewManagementQuery = tostring(props.query or ""):gsub("^%s+", ""):gsub("%s+$", "")
	local crewManagementInfoText = if crewManagementQuery ~= ""
		then string.format("Showing %d of %d crewmates", crewManagementFilteredCount, crewManagementTotalCount)
		else string.format("%d crewmates ready for crew tools", crewManagementTotalCount)

	local children = {
		BottomBar = e("Frame", {
			AnchorPoint = Vector2.new(0.5, 1),
			BackgroundTransparency = 1,
			ClipsDescendants = false,
			Position = UDim2.new(0.5, mobileLayout and 28 or 0, 1, mobileLayout and -10 or -20),
			Size = UDim2.fromOffset(bottomBarWidth, mobileLayout and 66 or 104),
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
				ClipsDescendants = false,
				Position = UDim2.fromOffset(hotbarOffsetX, 0),
				Size = UDim2.fromOffset(hotbarWidth, mobileLayout and 64 or 96),
				ZIndex = bottomBarZIndex,
			}, {
				Label = not mobileLayout and e("TextLabel", {
					BackgroundTransparency = 1,
					Font = Enum.Font.GothamBold,
					Position = UDim2.fromOffset(0, 0),
					Size = UDim2.new(1, 0, 0, 14),
					Text = string.format("Quick Equip Slots: %d / %d", crewQuickSlotsUnlocked, crewQuickSlotsMax),
					TextColor3 = PALETTE.Steel,
					TextSize = 11,
					TextXAlignment = Enum.TextXAlignment.Left,
					ZIndex = bottomBarZIndex + 1,
				}) or nil,
				Scroller = e(
					"ScrollingFrame",
					{
						AutomaticCanvasSize = Enum.AutomaticSize.X,
						BackgroundTransparency = 1,
						BorderSizePixel = 0,
						CanvasSize = UDim2.new(),
						ClipsDescendants = false,
						Position = UDim2.fromOffset(0, mobileLayout and 4 or 18),
						ScrollBarImageTransparency = 1,
						ScrollBarThickness = 0,
						ScrollingDirection = Enum.ScrollingDirection.X,
						Size = UDim2.new(1, 0, 0, mobileLayout and 58 or 78),
						ZIndex = bottomBarZIndex + 1,
					},
					(function()
						local slotChildren = {
							List = e("UIListLayout", {
								FillDirection = Enum.FillDirection.Horizontal,
								Padding = UDim.new(0, hotbarSlotGap),
								SortOrder = Enum.SortOrder.LayoutOrder,
								VerticalAlignment = Enum.VerticalAlignment.Center,
							}),
							Padding = e("UIPadding", {
								PaddingBottom = UDim.new(0, 7),
								PaddingTop = UDim.new(0, 7),
							}),
						}

						for index, slot in ipairs(props.hotbarSlots or {}) do
							slotChildren["Slot" .. tostring(index)] = e(hotbarSlot, {
								slot = slot,
								layoutOrder = index,
								slotSize = hotbarSlotWidth,
								zIndexBase = bottomBarZIndex,
								onActivated = props.onActivateItem,
							})
						end

						return slotChildren
					end)()
				),
			}),
		}),
	}
	local modalPanelChildren = nil

	if props.isOpen then
		local showingCrewInventoryCategory = showingInventory and tostring(props.activeCategory or "") == "CrewMembers"
		local gridChildren = {
			Grid = e("UIGridLayout", {
				CellPadding = UDim2.fromOffset(10, 10),
				CellSize = showingCrewInventoryCategory and UDim2.fromOffset(150, 171)
					or UDim2.fromOffset(128, 136),
				FillDirectionMaxCells = showingCrewInventoryCategory and 5 or 6,
				HorizontalAlignment = Enum.HorizontalAlignment.Left,
				SortOrder = Enum.SortOrder.LayoutOrder,
				VerticalAlignment = Enum.VerticalAlignment.Top,
			}),
		}

		for index, item in ipairs(props.items or {}) do
			local tileComponent = if showingCrewInventoryCategory and tostring(item.kind or "") == "CrewMember"
				then crewInventoryIndexTile
				else manifestTile
			gridChildren["Item" .. tostring(index)] = e(tileComponent, {
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
			{
				key = "CaptainLog",
				label = "Captain's Log",
				fillColor3 = PALETTE.Orange,
				size = UDim2.fromOffset(152, 38),
			},
			{
				key = "CrewManagement",
				label = "Crew Management",
				fillColor3 = PALETTE.Violet,
				size = UDim2.fromOffset(178, 38),
			},
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
				Padding = UDim.new(0, mobileLayout and 1 or 3),
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
					valueTextSize = 11,
					valueWidthScale = 0.34,
				},
			}
		else
			ledgerEntries = {
				{ label = "Total Bounty", value = formatNumber(summary.bounty or 0), valueColor3 = PALETTE.Gold },
				{
					label = "Ship Crew Bounty",
					value = formatNumber(summary.crewBounty or 0),
					valueColor3 = PALETTE.Orange,
				},
				{
					label = "Extraction Bounty",
					value = formatNumber(summary.extractionBounty or 0),
					valueColor3 = PALETTE.Green,
				},
				{
					label = "Beli",
					value = formatNumber(summary.beli or summary.doubloons or 0) .. " Beli",
					valueColor3 = PALETTE.Gold,
				},
				{
					label = "Quick Equip Slots",
					value = string.format("%d / %d", crewQuickSlotsUnlocked, crewQuickSlotsMax),
					valueColor3 = PALETTE.Sea,
				},
				{
					label = "Crewmate Storage",
					value = string.format("%d / %d", summary.crewStorageUsed or 0, summary.crewStorageSlots or 40),
					valueColor3 = Color3.fromRGB(93, 203, 200),
				},
				{ label = "Rebirths", value = tostring(summary.rebirths or 0), valueColor3 = PALETTE.Sea },
				{ label = "Multiplier", value = tostring(summary.multiplier or "1.00x"), valueColor3 = PALETTE.Cyan },
				{ label = "Unopened Chests", value = tostring(summary.chests or 0), valueColor3 = PALETTE.Green },
				{
					label = "Mythic Keys",
					value = formatNumber(summary.mythicKeys or 0),
					valueColor3 = Color3.fromRGB(255, 101, 134),
				},
			}
		end

		for index, entry in ipairs(ledgerEntries) do
			ledgerChildren["Entry" .. tostring(index)] = e(ledgerLine, {
				layoutOrder = index,
				label = entry.label,
				value = entry.value,
				valueColor3 = entry.valueColor3,
				multiLine = entry.multiLine,
				compact = mobileLayout,
			})
		end

		local captainLogChildren = {
			List = e("UIListLayout", {
				FillDirection = Enum.FillDirection.Vertical,
				Padding = UDim.new(0, 10),
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),
			Padding = e("UIPadding", {
				PaddingTop = UDim.new(0, 2),
				PaddingLeft = UDim.new(0, 4),
				PaddingRight = UDim.new(0, 4),
			}),
		}

		for index, entry in ipairs((props.captainLog and props.captainLog.entries) or {}) do
			local rowKey = tostring(entry.key or entry.standName or index)
			captainLogChildren["Row:" .. rowKey] = e(captainsLogRow, {
				entry = entry,
				layoutOrder = index,
			})
		end

		local crewManagementChildren = {
			List = e("UIListLayout", {
				FillDirection = Enum.FillDirection.Vertical,
				Padding = UDim.new(0, 10),
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),
			Padding = e("UIPadding", {
				PaddingBottom = UDim.new(0, 2),
				PaddingLeft = UDim.new(0, 4),
				PaddingRight = UDim.new(0, 4),
				PaddingTop = UDim.new(0, 2),
			}),
		}

		for index, entry in ipairs((props.crewManagement and props.crewManagement.entries) or {}) do
			local rowKey = tostring(entry.instanceId or entry.key or index)
			crewManagementChildren["Row:" .. rowKey] = e(crewManagementRow, {
				entry = entry,
				layoutOrder = index,
				pending = props.crewManagement and props.crewManagement.pending == true,
				onApplyCrewShield = props.onApplyCrewShield,
				onApplyPermanentSlot = props.onApplyPermanentSlot,
			})
		end

		local titleChildren = {
			List = e("UIListLayout", {
				FillDirection = Enum.FillDirection.Vertical,
				Padding = UDim.new(0, 10),
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),
			Padding = e("UIPadding", {
				PaddingTop = UDim.new(0, 2),
				PaddingLeft = UDim.new(0, 4),
				PaddingRight = UDim.new(0, 4),
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
				MinSize = Vector2.new(0, 0),
			}),
			Shell = e("Frame", {
				BackgroundColor3 = INVENTORY_UI.PrimaryBg,
				BorderSizePixel = 0,
				ClipsDescendants = true,
				Size = UDim2.fromScale(1, 1),
				ZIndex = 6,
			}, {
				BackgroundImage = e("ImageLabel", {
					BackgroundTransparency = 1,
					BorderSizePixel = 0,
					Image = INVENTORY_BACKGROUND_IMAGE,
					ImageTransparency = 0,
					ScaleType = Enum.ScaleType.Stretch,
					Size = UDim2.fromScale(1, 1),
					ZIndex = 5,
				}, {
					Corner = e("UICorner", {
						CornerRadius = UDim.new(0, 26),
					}),
				}),
				Corner = e("UICorner", {
					CornerRadius = UDim.new(0, 26),
				}),
				Stroke = e("UIStroke", {
					Color = INVENTORY_UI.GoldHighlight,
					Transparency = 0.04,
					Thickness = 2.2,
				}),
				Gradient = e("UIGradient", {
					Rotation = 90,
					Color = ColorSequence.new({
						ColorSequenceKeypoint.new(0, INVENTORY_UI.SecondaryBg),
						ColorSequenceKeypoint.new(0.45, INVENTORY_UI.PrimaryBg),
						ColorSequenceKeypoint.new(1, INVENTORY_UI.MenuOverlay),
					}),
				}),
				ImageOverlay = e("Frame", {
					BackgroundColor3 = INVENTORY_UI.MenuOverlay,
					BackgroundTransparency = 0.48,
					BorderSizePixel = 0,
					Size = UDim2.fromScale(1, 1),
					ZIndex = 6,
				}, {
					Corner = e("UICorner", {
						CornerRadius = UDim.new(0, 26),
					}),
				}),
				InnerGlow = e("Frame", {
					BackgroundColor3 = INVENTORY_UI.GoldBase,
					BackgroundTransparency = 0.98,
					BorderSizePixel = 0,
					Position = UDim2.fromOffset(12, 12),
					Size = UDim2.new(1, -24, 1, -24),
					ZIndex = 6,
				}, {
					Corner = e("UICorner", {
						CornerRadius = UDim.new(0, 22),
					}),
					Stroke = e("UIStroke", {
						Color = INVENTORY_UI.GoldBase,
						Transparency = 0.76,
					}),
				}),
				TopTabs = e("Frame", {
					AnchorPoint = Vector2.new(0, 0),
					BackgroundTransparency = 1,
					Position = UDim2.fromOffset(24, 16),
					Size = UDim2.fromOffset(606, 40),
					ZIndex = 8,
				}, topModeChildren),
				Close = e("TextButton", {
					AnchorPoint = Vector2.new(1, 0),
					AutoButtonColor = false,
					BackgroundColor3 = Color3.fromRGB(200, 0, 9),
					BorderSizePixel = 0,
					Position = UDim2.new(1, -32, 0, 16),
					Size = UDim2.fromOffset(38, 38),
					Text = "X",
					TextColor3 = Color3.fromRGB(255, 255, 255),
					TextSize = 18,
					Font = Enum.Font.Cartoon,
					ZIndex = 8,
					[React.Event.Activated] = props.onToggle,
				}, {
					Corner = e("UICorner", {
						CornerRadius = UDim.new(0, 12),
					}),
					Stroke = e("UIStroke", {
						Color = INVENTORY_UI.GoldHighlight,
						Transparency = 0.16,
					}),
				}),
				HeaderDivider = e("Frame", {
					BackgroundColor3 = INVENTORY_UI.GoldBase,
					BackgroundTransparency = 0.26,
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
					BackgroundColor3 = INVENTORY_UI.SectionBg,
					BackgroundTransparency = 0.18,
					BorderSizePixel = 0,
					Position = UDim2.fromOffset(26, 90),
					Size = UDim2.new(0, 240, 1, -116),
					ZIndex = 7,
				}, {
					Corner = e("UICorner", {
						CornerRadius = UDim.new(0, 10),
					}),
					Stroke = e("UIStroke", {
						Color = INVENTORY_UI.GoldHighlight,
						Transparency = 0.2,
						Thickness = 1.2,
					}),
					Gradient = e("UIGradient", {
						Rotation = 100,
						Color = ColorSequence.new({
							ColorSequenceKeypoint.new(0, INVENTORY_UI.SecondaryBg),
							ColorSequenceKeypoint.new(1, INVENTORY_UI.PrimaryBg),
						}),
					}),
					Title = e("TextLabel", {
						BackgroundTransparency = 1,
						Font = Enum.Font.Cartoon,
						Position = UDim2.fromOffset(16, mobileLayout and 10 or 14),
						Size = UDim2.new(1, -32, 0, mobileLayout and 24 or 28),
						Text = showingTitles and "Title Registry" or "Captain's Ledger",
						TextColor3 = PALETTE.Cream,
						TextSize = mobileLayout and 22 or 28,
						TextStrokeTransparency = 0.6,
						TextXAlignment = Enum.TextXAlignment.Left,
						ZIndex = 8,
					}),
					Subtitle = e("TextLabel", {
						BackgroundTransparency = 1,
						Font = Enum.Font.Gotham,
						Position = UDim2.fromOffset(16, mobileLayout and 36 or 44),
						Size = UDim2.new(1, -32, 0, mobileLayout and 24 or 30),
						Text = showingTitles and "Honor marks tied to your long-term feats and current bounty rank."
							or "Current haul and ship stores at a glance.",
						TextColor3 = INVENTORY_UI.TextMuted,
						TextSize = mobileLayout and 10 or 12,
						TextWrapped = true,
						TextXAlignment = Enum.TextXAlignment.Left,
						TextYAlignment = Enum.TextYAlignment.Top,
						ZIndex = 8,
					}),
					Divider = e("Frame", {
						BackgroundColor3 = INVENTORY_UI.GoldBase,
						BackgroundTransparency = 0.26,
						BorderSizePixel = 0,
						Position = UDim2.fromOffset(16, mobileLayout and 68 or 84),
						Size = UDim2.new(1, -32, 0, 2),
						ZIndex = 8,
					}, {
						Corner = e("UICorner", {
							CornerRadius = UDim.new(0, 999),
						}),
					}),
					Stats = e("Frame", {
						BackgroundTransparency = 1,
						Position = UDim2.fromOffset(16, mobileLayout and 80 or 102),
						Size = UDim2.new(1, -32, 1, mobileLayout and -88 or -118),
						ZIndex = 8,
					}, ledgerChildren),
				}),
				MainPanel = e("Frame", {
					BackgroundColor3 = INVENTORY_UI.SectionBg,
					BackgroundTransparency = 0.12,
					BorderSizePixel = 0,
					Position = UDim2.fromOffset(286, 90),
					Size = showingInventory and UDim2.new(1, -312, 1, -186) or UDim2.new(1, -312, 1, -116),
					ZIndex = 7,
				}, {
					Corner = e("UICorner", {
						CornerRadius = UDim.new(0, 12),
					}),
					Stroke = e("UIStroke", {
						Color = INVENTORY_UI.GoldHighlight,
						Transparency = 0.14,
						Thickness = 1.25,
					}),
					Gradient = e("UIGradient", {
						Rotation = 100,
						Color = ColorSequence.new({
							ColorSequenceKeypoint.new(0, INVENTORY_UI.SecondaryBg),
							ColorSequenceKeypoint.new(1, INVENTORY_UI.PrimaryBg),
						}),
					}),
					Eyebrow = e("TextLabel", {
						BackgroundTransparency = 1,
						Font = Enum.Font.GothamBold,
						Position = UDim2.fromOffset(18, 12),
						Size = UDim2.new(1, -320, 0, 14),
						Text = showingCaptainLog and "Ship Income Overview"
							or (showingCrewManagement and "Crew Tools" or (showingTitles and "Crew Honors" or "Captain's Hold")),
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
							or (
								showingCrewManagement and "Crew Management"
								or (showingTitles and "Titles" or (props.activeCategoryLabel or "Inventory"))
							),
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
						Text = showingCaptainLog and captainLogInfoText
							or (
								showingCrewManagement and crewManagementInfoText
								or (
									showingTitles and string.format(
										"%d of %d titles visible, %d unlocked",
										(props.titles and props.titles.filteredCount) or 0,
										(props.titles and props.titles.totalCount) or 0,
										(props.titles and props.titles.unlockedCount) or 0
									)
									or string.format(
										"%d shown of %d items ready to manage",
										props.filteredCount or 0,
										props.totalCount or 0
									)
								)
							),
						TextColor3 = INVENTORY_UI.TextMuted,
						TextSize = 12,
						TextXAlignment = Enum.TextXAlignment.Left,
						ZIndex = 8,
					}),
					SearchShell = e("Frame", {
						AnchorPoint = Vector2.new(1, 0),
						BackgroundColor3 = INVENTORY_UI.ButtonIdle,
						BorderSizePixel = 0,
						Position = UDim2.new(1, -18, 0, 16),
						Size = UDim2.fromOffset(236, 38),
						ZIndex = 8,
					}, {
						Corner = e("UICorner", {
							CornerRadius = UDim.new(0, 8),
						}),
						Stroke = e("UIStroke", {
							Color = INVENTORY_UI.GoldHighlight,
							Transparency = 0.2,
						}),
						Icon = searchGlyph(),
						Search = e("TextBox", {
							BackgroundTransparency = 1,
							BorderSizePixel = 0,
							ClearTextOnFocus = false,
							Font = Enum.Font.GothamBold,
							PlaceholderColor3 = Color3.fromRGB(133, 136, 144),
							PlaceholderText = showingCaptainLog and "Search placed crewmates..."
								or (
									showingCrewManagement and "Search crewmates..."
									or (showingTitles and "Search titles..." or "Search inventory...")
								),
							Position = UDim2.fromOffset(36, 0),
							Size = UDim2.new(1, -44, 1, 0),
							Text = props.query or "",
							TextColor3 = INVENTORY_UI.TextMain,
							TextSize = 13,
							TextXAlignment = Enum.TextXAlignment.Left,
							ZIndex = 8,
							[React.Change.Text] = function(box)
								props.onQueryChanged(box.Text)
							end,
						}),
					}),
					GridShell = e("Frame", {
						BackgroundColor3 = INVENTORY_UI.MenuOverlay,
						BackgroundTransparency = showingInventory and 0.2 or 0.34,
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
							Color = INVENTORY_UI.GoldHighlight,
							Transparency = 0.18,
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
								Text = "Total Ready to Collect",
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
								Text = CurrencyUtil.formatCurrency(
									(props.captainLog and props.captainLog.totalCollectable) or 0
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
								Text = "All Placed Crewmates",
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
								Text = tostring(
									(props.titles and props.titles.bountyRankLabel)
										or formatLeaderboardRank(props.titles and props.titles.bountyRank)
								),
								TextColor3 = activeAccent,
								TextSize = 28,
								TextStrokeTransparency = 0.56,
								TextXAlignment = Enum.TextXAlignment.Right,
								ZIndex = 9,
							}),
						}) or nil,
						CrewManagementSummary = showingCrewManagement and e(crewManagementSummary, {
							data = props.crewManagement,
							onFleetShieldAction = props.onFleetShieldAction,
						}) or nil,
						Grid = showingInventory and e("ScrollingFrame", {
							AutomaticCanvasSize = Enum.AutomaticSize.Y,
							BackgroundTransparency = 1,
							BorderSizePixel = 0,
							CanvasSize = UDim2.new(),
							Position = UDim2.fromOffset(14, 14),
							ScrollBarImageColor3 = INVENTORY_UI.GoldBase,
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
							ScrollBarImageColor3 = INVENTORY_UI.GoldBase,
							ScrollBarThickness = 7,
							Size = UDim2.new(1, -28, 1, -96),
							ZIndex = 8,
						}, captainLogChildren) or nil,
						CrewManagementList = showingCrewManagement and e("ScrollingFrame", {
							AutomaticCanvasSize = Enum.AutomaticSize.Y,
							BackgroundTransparency = 1,
							BorderSizePixel = 0,
							CanvasSize = UDim2.new(),
							Position = UDim2.fromOffset(14, 152),
							ScrollBarImageColor3 = INVENTORY_UI.GoldBase,
							ScrollBarThickness = 7,
							Size = UDim2.new(1, -28, 1, -166),
							ZIndex = 8,
						}, crewManagementChildren) or nil,
						TitleList = showingTitles and e("ScrollingFrame", {
							AutomaticCanvasSize = Enum.AutomaticSize.Y,
							BackgroundTransparency = 1,
							BorderSizePixel = 0,
							CanvasSize = UDim2.new(),
							Position = UDim2.fromOffset(14, 82),
							ScrollBarImageColor3 = INVENTORY_UI.GoldBase,
							ScrollBarThickness = 7,
							Size = UDim2.new(1, -28, 1, -96),
							ZIndex = 8,
						}, titleChildren) or nil,
						Empty = (
							showingCaptainLog and #((props.captainLog and props.captainLog.entries) or {}) == 0
							or (showingCrewManagement and #((props.crewManagement and props.crewManagement.entries) or {}) == 0)
							or (showingTitles and #((props.titles and props.titles.entries) or {}) == 0)
							or (showingInventory and #(props.items or {}) == 0)
						)
								and e("TextLabel", {
									AnchorPoint = Vector2.new(0.5, 0.5),
									BackgroundTransparency = 1,
									Font = Enum.Font.Cartoon,
									Position = UDim2.fromScale(0.5, 0.52),
									Size = UDim2.fromOffset(360, 26),
									Text = showingCaptainLog
											and (((props.captainLog and props.captainLog.totalCount) or 0) > 0 and "No placed crewmates match that search." or "No crewmates are placed on your ship yet.")
										or (
											showingCrewManagement
												and (((props.crewManagement and props.crewManagement.totalCount) or 0) > 0 and "No crewmates match that search." or "No crewmates are in your crew yet.")
											or (
												showingTitles
													and (((props.titles and props.titles.totalCount) or 0) > 0 and "No titles match that search." or "No titles are registered yet.")
												or (
													(props.totalCount or 0) > 0
														and "No inventory items match that search."
													or "Nothing in this hold yet."
												)
											)
										),
									TextColor3 = INVENTORY_UI.TextMuted,
									TextSize = 24,
									TextStrokeTransparency = 0.6,
									ZIndex = 8,
								})
							or nil,
					}),
				}),
				FooterStrip = e("Frame", {
					BackgroundColor3 = INVENTORY_UI.MenuOverlay,
					BackgroundTransparency = 0.18,
					BorderSizePixel = 0,
					ClipsDescendants = true,
					Position = UDim2.new(0, 286, 1, -86),
					Size = UDim2.new(1, -312, 0, 58),
					Visible = showingInventory,
					ZIndex = 7,
				}, {
					Corner = e("UICorner", {
						CornerRadius = UDim.new(0, 12),
					}),
					Stroke = e("UIStroke", {
						Color = INVENTORY_UI.GoldHighlight,
						Transparency = 0.18,
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

	local inventoryModal = e(AnimatedInventoryModal, {
		isOpen = props.isOpen,
		panelChildren = modalPanelChildren,
		panelSize = mobileLayout and UDim2.fromScale(0.74, 0.8) or UDim2.fromScale(0.82, 0.76),
		contentScale = mobileLayout and 0.62 or 1,
		openPosition = INVENTORY_MODAL_OPEN_POSITION,
		closedPosition = INVENTORY_MODAL_CLOSED_POSITION,
		backdropTransparency = INVENTORY_MODAL_BACKDROP_TRANSPARENCY,
	})

	local appChildren = {
		Main = e("ScreenGui", {
			DisplayOrder = 90,
			IgnoreGuiInset = true,
			ResetOnSpawn = false,
			ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		}, children),
		InventoryModal = e("ScreenGui", {
			DisplayOrder = 500,
			IgnoreGuiInset = true,
			ResetOnSpawn = false,
			ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		}, {
			Modal = inventoryModal,
		}),
	}

	if props.shipUpgradeModal then
		appChildren.ShipUpgradeModal = e(shipUpgradeModal, {
			modal = props.shipUpgradeModal,
			onDismiss = props.onDismissShipUpgradeModal,
		})
	end

	if props.chestOpenPrompt then
		appChildren.ChestOpenPrompt = e("ScreenGui", {
			DisplayOrder = 520,
			IgnoreGuiInset = true,
			ResetOnSpawn = false,
			ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		}, {
			Prompt = e(chestOpenQuantityPrompt, {
				displayName = props.chestOpenPrompt.displayName,
				amount = props.chestOpenPrompt.amount,
				maxAmount = props.chestOpenPrompt.maxAmount,
				onAmountChanged = props.onChestOpenAmountChanged,
				onConfirm = props.onConfirmChestOpen,
				onDismiss = props.onDismissChestOpen,
				onShowDropRates = props.onShowChestDropRates,
			}),
		})
	end

	if props.chestDropRatesPrompt then
		appChildren.ChestDropRatesPrompt = e("ScreenGui", {
			DisplayOrder = 530,
			IgnoreGuiInset = true,
			ResetOnSpawn = false,
			ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		}, {
			Prompt = e(chestDropRatesPrompt, {
				chestName = props.chestDropRatesPrompt.chestName,
				sections = props.chestDropRatesPrompt.sections,
				onDismiss = props.onDismissChestDropRates,
			}),
		})
	end

	return e(React.Fragment, nil, appChildren)
end

return App
