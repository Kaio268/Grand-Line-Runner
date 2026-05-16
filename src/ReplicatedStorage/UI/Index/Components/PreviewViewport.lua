local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local React = require(Packages:WaitForChild("React"))

local Modules = ReplicatedStorage:WaitForChild("Modules")
local DevilFruitAssets = require(Modules:WaitForChild("DevilFruits"):WaitForChild("Assets"))
local CrewPreviewImages = require(Modules:WaitForChild("Crew"):WaitForChild("CrewPreviewImages"))

local e = React.createElement
local CREW_PREVIEW_ASSET_ROOT_NAME = "One Piece Characters"
local CREW_PREVIEW_ROTATION = CFrame.Angles(math.rad(-12), math.rad(208), 0)
local DEBUG_PREVIEW_VIEWPORT = false
local DEBUG_LOG_LABEL = "INDEX_PREVIEW_DEBUG"
local MAX_DEBUG_SAMPLE_PARTS = 12
local R6_BASE_BODY_PART_NAMES = {
	Head = true,
	HumanoidRootPart = true,
	["Left Arm"] = true,
	["Left Leg"] = true,
	["Right Arm"] = true,
	["Right Leg"] = true,
	Torso = true,
}
local OUTFIT_MESH_NAME_TOKENS = {
	"arm",
	"body",
	"cape",
	"chest",
	"cloak",
	"coat",
	"dress",
	"jacket",
	"leg",
	"outfit",
	"pants",
	"robe",
	"shell",
	"shirt",
	"torso",
}
local PREVIEW_TEXTURE_FALLBACK_MESH_IDS = {
	["rbxassetid://134340562190607"] = true, -- Wapol shell
	["rbxassetid://76188112058780"] = true, -- XDrake shell
}

local debugMountCounter = 0

local function formatVector3(value)
	if typeof(value) ~= "Vector3" then
		return tostring(value)
	end

	return string.format("(%.2f, %.2f, %.2f)", value.X, value.Y, value.Z)
end

local function getFullNameSafe(instance)
	if typeof(instance) ~= "Instance" then
		return tostring(instance)
	end

	local ok, result = pcall(function()
		return instance:GetFullName()
	end)

	return if ok then result else tostring(instance)
end

local function debugLog(message)
	if DEBUG_PREVIEW_VIEWPORT then
		warn(string.format("[%s] %s", DEBUG_LOG_LABEL, message))
	end
end

local function collectPreviewDebugStats(previewModel)
	local stats = {
		accessories = 0,
		anchoredParts = 0,
		baseParts = 0,
		decals = 0,
		localHiddenParts = 0,
		meshParts = 0,
		sampleParts = {},
		textures = 0,
		transparentParts = 0,
		visibleParts = 0,
	}

	for _, descendant in ipairs(previewModel:GetDescendants()) do
		if descendant:IsA("Accessory") then
			stats.accessories += 1
		elseif descendant:IsA("Decal") then
			stats.decals += 1
		elseif descendant:IsA("Texture") then
			stats.textures += 1
		elseif descendant:IsA("BasePart") then
			stats.baseParts += 1
			if descendant:IsA("MeshPart") then
				stats.meshParts += 1
			end
			if descendant.Anchored then
				stats.anchoredParts += 1
			end
			if descendant.Transparency >= 1 then
				stats.transparentParts += 1
			else
				stats.visibleParts += 1
			end
			if descendant.LocalTransparencyModifier >= 1 then
				stats.localHiddenParts += 1
			end
			if #stats.sampleParts < MAX_DEBUG_SAMPLE_PARTS then
				stats.sampleParts[#stats.sampleParts + 1] = string.format(
					"%s|T=%.2f|LTM=%.2f|A=%s|Size=%s",
					descendant.Name,
					descendant.Transparency,
					descendant.LocalTransparencyModifier,
					tostring(descendant.Anchored),
					formatVector3(descendant.Size)
				)
			end
		end
	end

	return stats
end

local function formatSampleParts(stats)
	if #stats.sampleParts == 0 then
		return "<none>"
	end

	return table.concat(stats.sampleParts, "; ")
end

local function clearChildren(instance)
	for _, child in ipairs(instance:GetChildren()) do
		child:Destroy()
	end
end

local function setPreviewPartRenderDefaults(part)
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.Massless = true
	part.LocalTransparencyModifier = 0
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
end

local function setPreviewPartDefaults(part)
	part.Anchored = true
	setPreviewPartRenderDefaults(part)
end

local function hasAssetReference(value)
	return typeof(value) == "string" and value ~= "" and value ~= "rbxassetid://0"
end

local function hasAncestorOfClass(instance, className)
	local current = instance.Parent
	while current do
		if current:IsA(className) then
			return true
		end
		current = current.Parent
	end

	return false
end

local function meshPartHasTextureId(meshPart)
	return hasAssetReference(meshPart.TextureID)
end

local function meshPartNameSuggestsOutfitLayer(meshPart)
	local haystack = string.lower(meshPart.Name)
	local parent = meshPart.Parent
	if parent then
		haystack ..= " " .. string.lower(parent.Name)
	end

	for _, token in ipairs(OUTFIT_MESH_NAME_TOKENS) do
		if string.find(haystack, token, 1, true) then
			return true
		end
	end

	return false
end

local function hasMeshOutfitLayers(previewModel)
	local nonAccessoryMeshParts = 0
	local texturedNonAccessoryMeshParts = 0

	for _, descendant in ipairs(previewModel:GetDescendants()) do
		if descendant:IsA("MeshPart")
			and descendant.Transparency < 1
			and descendant.LocalTransparencyModifier < 1
			and not hasAncestorOfClass(descendant, "Accessory")
		then
			nonAccessoryMeshParts += 1
			if meshPartHasTextureId(descendant) then
				texturedNonAccessoryMeshParts += 1
			end
			if meshPartNameSuggestsOutfitLayer(descendant)
				or texturedNonAccessoryMeshParts >= 2
				or (nonAccessoryMeshParts >= 3 and texturedNonAccessoryMeshParts >= 1)
			then
				return true
			end
		end
	end

	return false
end

local function hidePlainR6BodyPartsForMeshOutfits(previewModel)
	if not hasMeshOutfitLayers(previewModel) then
		return
	end

	for _, descendant in ipairs(previewModel:GetDescendants()) do
		if descendant:IsA("Part") and R6_BASE_BODY_PART_NAMES[descendant.Name] then
			descendant.Transparency = 1
			descendant.LocalTransparencyModifier = 1
		end
	end
end

local function applyMeshTexturePreviewFallbacks(previewModel)
	for _, descendant in ipairs(previewModel:GetDescendants()) do
		if descendant:IsA("MeshPart") and PREVIEW_TEXTURE_FALLBACK_MESH_IDS[descendant.MeshId] then
			for _, child in ipairs(descendant:GetChildren()) do
				if child:IsA("SurfaceAppearance") then
					child:Destroy()
				end
			end
		end
	end
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

	applyMeshTexturePreviewFallbacks(previewModel)
end

local function cloneCrewPreviewModel(modelName)
	local template = findCrewPreviewModel(modelName)
	if not template then
		if DEBUG_PREVIEW_VIEWPORT then
			debugLog(string.format(
				"crew_template_missing modelName=%s assetRoot=%s",
				tostring(modelName),
				getFullNameSafe(getCrewPreviewAssetRoot())
			))
		end
		return nil
	end

	if DEBUG_PREVIEW_VIEWPORT then
		debugLog(string.format("crew_template_found modelName=%s template=%s", tostring(modelName), getFullNameSafe(template)))
	end

	local ok, clone = pcall(function()
		return template:Clone()
	end)
	if not ok or typeof(clone) ~= "Instance" then
		if DEBUG_PREVIEW_VIEWPORT then
			debugLog(string.format(
				"crew_clone_failed modelName=%s ok=%s cloneType=%s",
				tostring(modelName),
				tostring(ok),
				typeof(clone)
			))
		end
		return nil
	end

	sanitizeCrewPreviewClone(clone)
	return clone
end

local function positionPreviewModel(previewModel, previewKind, previewName)
	local rotation = CFrame.Angles(math.rad(-12), math.rad(28), 0)
	if previewKind == "CrewMember" then
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

	if previewKind == "CrewMember" then
		hidePlainR6BodyPartsForMeshOutfits(previewModel)
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

local function ViewportPreviewModel(props)
	local viewportRef = React.useRef(nil)

	React.useEffect(function()
		local viewport = viewportRef.current
		if not viewport then
			return nil
		end

		if DEBUG_PREVIEW_VIEWPORT then
			debugMountCounter += 1
		end
		local mountId = debugMountCounter
		if DEBUG_PREVIEW_VIEWPORT then
			debugLog(string.format(
				"mount_start id=%d kind=%s name=%s viewport=%s absoluteSize=%s",
				mountId,
				tostring(props.previewKind),
				tostring(props.previewName),
				getFullNameSafe(viewport),
				formatVector3(viewport.AbsoluteSize)
			))
		end

		clearChildren(viewport)

		local previewModel
		if props.previewKind == "DevilFruit" then
			previewModel = DevilFruitAssets.ClonePreviewWorldModel(props.previewName)
		elseif props.previewKind == "CrewMember" then
			previewModel = cloneCrewPreviewModel(props.previewName)
		end

		if not previewModel then
			if DEBUG_PREVIEW_VIEWPORT then
				debugLog(string.format(
					"preview_model_missing id=%d kind=%s name=%s",
					mountId,
					tostring(props.previewKind),
					tostring(props.previewName)
				))
			end
			return function()
				if viewport.Parent then
					if DEBUG_PREVIEW_VIEWPORT then
						debugLog(string.format(
							"cleanup_missing_model id=%d kind=%s name=%s",
							mountId,
							tostring(props.previewKind),
							tostring(props.previewName)
						))
					end
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

		if DEBUG_PREVIEW_VIEWPORT then
			local stats = collectPreviewDebugStats(previewModel)
			debugLog(string.format(
				"mounted id=%d kind=%s name=%s model=%s worldModel=%s baseParts=%d visibleParts=%d transparentParts=%d localHiddenParts=%d anchoredParts=%d meshParts=%d accessories=%d decals=%d textures=%d boundsCenter=%s boundsSize=%s maxSize=%.2f cameraPos=%s cameraLookAt=%s samples=%s",
				mountId,
				tostring(props.previewKind),
				tostring(props.previewName),
				getFullNameSafe(previewModel),
				getFullNameSafe(worldModel),
				stats.baseParts,
				stats.visibleParts,
				stats.transparentParts,
				stats.localHiddenParts,
				stats.anchoredParts,
				stats.meshParts,
				stats.accessories,
				stats.decals,
				stats.textures,
				formatVector3(boxCF.Position),
				formatVector3(boxSize),
				maxSize,
				formatVector3(camera.CFrame.Position),
				formatVector3(boxCF.Position),
				formatSampleParts(stats)
			))
		end

		return function()
			if viewport.Parent then
				if DEBUG_PREVIEW_VIEWPORT then
					debugLog(string.format(
						"cleanup id=%d kind=%s name=%s viewportChildrenBefore=%d",
						mountId,
						tostring(props.previewKind),
						tostring(props.previewName),
						#viewport:GetChildren()
					))
				end
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

local function staticCrewPreviewImage(image, props)
	props = props or {}
	return e("ImageLabel", {
		AnchorPoint = props.anchorPoint or Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Image = image,
		ImageColor3 = props.tintColor or Color3.new(1, 1, 1),
		ImageTransparency = props.tintTransparency or 0,
		Position = props.position or UDim2.fromScale(0.5, 0.5),
		ScaleType = props.scaleType or Enum.ScaleType.Crop,
		Size = props.size or UDim2.fromScale(1, 1),
		ZIndex = props.zIndex,
	})
end

local function PreviewViewport(props)
	if tostring(props.previewKind or "") == "CrewMember" then
		local staticPreviewImage = CrewPreviewImages.Resolve(props.previewName)
		if staticPreviewImage ~= "" then
			return staticCrewPreviewImage(staticPreviewImage, props)
		end
	end

	return e(ViewportPreviewModel, props)
end

return PreviewViewport
