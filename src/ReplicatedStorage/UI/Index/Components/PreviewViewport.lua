local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local React = require(Packages:WaitForChild("React"))

local DevilFruitAssets = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("DevilFruits"):WaitForChild("Assets"))

local e = React.createElement

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

local function positionPreviewModel(previewModel, previewKind, previewName)
	local rotation = CFrame.Angles(math.rad(-12), math.rad(28), 0)
	if previewKind == "DevilFruit" and previewName == "Tori" then
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

local function applyTint(previewModel, tintColor, tintTransparency)
	for _, descendant in ipairs(previewModel:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.Color = tintColor
			descendant.Material = Enum.Material.SmoothPlastic
			descendant.Transparency = tintTransparency or 0
			descendant.Reflectance = 0
		elseif descendant:IsA("Decal") or descendant:IsA("Texture") then
			descendant.Transparency = 1
		elseif descendant:IsA("ParticleEmitter")
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
		end

		if not previewModel then
			return function()
				if viewport.Parent then
					clearChildren(viewport)
				end
			end
		end

		if props.tintColor then
			applyTint(previewModel, props.tintColor, props.tintTransparency)
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
	end, { props.previewKind, props.previewName, props.tintColor, props.tintTransparency, props.fieldOfView })

	return e("ViewportFrame", {
		ref = viewportRef,
		AnchorPoint = props.anchorPoint,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = props.position,
		Size = props.size or UDim2.fromScale(1, 1),
		Ambient = Color3.fromRGB(206, 196, 186),
		LightColor = Color3.fromRGB(255, 252, 246),
		LightDirection = Vector3.new(-1, -1, -1),
		ZIndex = props.zIndex,
	})
end

return PreviewViewport
