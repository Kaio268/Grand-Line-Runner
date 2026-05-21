local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local StudioAssetResolver = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("StudioAssetResolver"))
local HazardDebugConstants = require(
	ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Debug"):WaitForChild("HazardDebugConstants")
)

local WaveHazardVisuals = {}

local REGULAR_WAVE_ASSET_NAME = "Regular Wave"
local FROZEN_WAVE_ASSET_NAME = "Frozen Wave"
local HITBOX_NAME = "WaveHitbox"
local VISUAL_NAME = "WaveVisual"
local FROZEN_VISUAL_NAME = "FrozenWaveVisual"
local USES_ASSET_VISUALS_ATTRIBUTE = "UsesWaveAssetVisuals"
local CLIENT_VISUALS_ONLY_ATTRIBUTE = "ClientWaveVisualsOnly"
local VISUAL_ASSET_NAME_ATTRIBUTE = "WaveVisualAssetName"
local ACTIVE_VISUAL_ASSET_ATTRIBUTE = "ActiveWaveVisualAssetName"
local PREPARED_VISUAL_ATTRIBUTE = "WaveVisualPrepared"
local PREPARED_VISUALS_ATTRIBUTE = "WaveVisualsPrepared"
local ORIGINAL_TRANSPARENCY_ATTRIBUTE = "WaveVisualOriginalTransparency"
local ORIGINAL_ENABLED_ATTRIBUTE = "WaveVisualOriginalEnabled"
local MIN_PART_SIZE = 0.001
local ASSET_TEMPLATE_ROTATION = CFrame.Angles(0, math.rad(180), 0)
local VISUAL_BOUNDS_DIAGNOSTIC_ATTRIBUTE = "WaveVisualBoundsDebug"
local VISUAL_BOUNDS_DRIFT_WARN_RATIO = 1.05
local waveAssetCache = {}
local waveAssetMeasurementCache = {}
local warningKeys = {}

local function markHazardHitboxPart(part)
	if not part or not part:IsA("BasePart") then
		return
	end

	CollectionService:AddTag(part, HazardDebugConstants.HitboxTag)
	part:SetAttribute(HazardDebugConstants.DebugHitboxAttribute, true)
	part:SetAttribute(HazardDebugConstants.HazardHitboxAttribute, true)
	part:SetAttribute(HazardDebugConstants.HazardClassAttribute, "major")
	part:SetAttribute(HazardDebugConstants.HazardTypeAttribute, "Wave")
end

local function warnOnce(key, message, ...)
	if warningKeys[key] then
		return
	end

	warningKeys[key] = true
	warn(string.format("[WaveHazardVisuals] " .. message, ...))
end

local function findFirstChildRecursive(parent, name)
	if not parent then
		return nil
	end

	local direct = parent:FindFirstChild(name)
	if direct then
		return direct
	end

	return parent:FindFirstChild(name, true)
end

local function getWaveAssetsFolder()
	local wavesFolder = StudioAssetResolver.ResolveAsset("Waves", {
		Context = "WaveHazardVisuals",
		Required = true,
	})
	if wavesFolder and wavesFolder:IsA("Folder") then
		return wavesFolder
	end

	return nil
end

local function getWaveAsset(assetName, options)
	options = if typeof(options) == "table" then options else {}
	local cachedAsset = waveAssetCache[assetName]
	if cachedAsset and cachedAsset.Parent then
		return cachedAsset
	elseif cachedAsset then
		waveAssetCache[assetName] = nil
	end

	local wavesFolder = getWaveAssetsFolder()
	local asset = findFirstChildRecursive(wavesFolder, assetName)
	if asset and (asset:IsA("Model") or asset:IsA("BasePart")) then
		waveAssetCache[assetName] = asset
		return asset
	end

	if options.WarnIfMissing == true then
		warnOnce(
			"missing_asset_" .. tostring(assetName) .. "_" .. tostring(options.Context or "unknown"),
			"Missing wave visual asset '%s' for %s. Expected it under ReplicatedStorage.Assets.Hazards.Waves.",
			tostring(assetName),
			tostring(options.Context or "unknown")
		)
	end

	return nil
end

local function getWaveAssetSourceSize(asset)
	if not asset then
		return nil
	end

	local cacheKey = asset:GetFullName()
	local cachedMeasurement = waveAssetMeasurementCache[cacheKey]
	if cachedMeasurement and cachedMeasurement.Asset == asset and asset.Parent then
		return cachedMeasurement.Size
	elseif cachedMeasurement then
		waveAssetMeasurementCache[cacheKey] = nil
	end

	local sourceSize = nil
	if asset:IsA("BasePart") then
		sourceSize = asset.Size
	else
		local _, measuredSize = asset:GetBoundingBox()
		sourceSize = measuredSize
	end

	if sourceSize then
		waveAssetMeasurementCache[cacheKey] = {
			Asset = asset,
			Size = sourceSize,
		}
	end

	return sourceSize
end

local function forEachBasePart(root, callback)
	if not root then
		return
	end

	if root:IsA("BasePart") then
		callback(root)
		return
	end

	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant:IsA("BasePart") then
			callback(descendant)
		end
	end
end

local function forEachSelfAndDescendant(root, callback)
	if not root then
		return
	end

	callback(root)

	for _, descendant in ipairs(root:GetDescendants()) do
		callback(descendant)
	end
end

local function ensureModelPrimaryPart(model)
	if not model:IsA("Model") then
		return nil
	end

	if model.PrimaryPart and model.PrimaryPart.Parent then
		return model.PrimaryPart
	end

	local primaryPart = model:FindFirstChildWhichIsA("BasePart", true)
	if primaryPart then
		pcall(function()
			model.PrimaryPart = primaryPart
		end)
	end

	return primaryPart
end

local function getPivot(instance)
	if instance:IsA("Model") then
		return instance:GetPivot()
	end

	return instance.CFrame
end

local function translateCFrame(cframeValue, offset)
	local rotation = cframeValue - cframeValue.Position
	return CFrame.new(cframeValue.Position + offset) * rotation
end

local function getBouncedLateralOffsetInRange(rawOffset, minOffset, maxOffset)
	local lower = tonumber(minOffset) or 0
	local upper = tonumber(maxOffset) or lower
	if upper < lower then
		lower, upper = upper, lower
	end

	local span = upper - lower
	if span <= 1e-4 then
		return lower
	end

	local cycle = span * 2
	local shifted = ((tonumber(rawOffset) or lower) - lower) % cycle

	if shifted <= span then
		return lower + shifted
	end

	return upper - (shifted - span)
end

local function getBouncedLateralOffset(rawOffset, maxDrift)
	local limit = math.max(0, tonumber(maxDrift) or 0)
	if limit <= 1e-4 then
		return 0
	end

	return getBouncedLateralOffsetInRange(rawOffset, -limit, limit)
end

local function findHitboxRoot(root)
	if not root then
		return nil
	end

	if (root:IsA("Model") or root:IsA("BasePart")) and root.Name == HITBOX_NAME then
		return root
	end

	local directHitbox = root:FindFirstChild(HITBOX_NAME)
	if directHitbox and (directHitbox:IsA("Model") or directHitbox:IsA("BasePart")) then
		return directHitbox
	end

	local descendantHitbox = root:FindFirstChild(HITBOX_NAME, true)
	if descendantHitbox and (descendantHitbox:IsA("Model") or descendantHitbox:IsA("BasePart")) then
		return descendantHitbox
	end

	return nil
end

local function configureHitboxPart(part)
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = true
	part.CanQuery = true
	part.Transparency = 1
	part.AssemblyLinearVelocity = Vector3.zero
	part.AssemblyAngularVelocity = Vector3.zero
	pcall(function()
		part.Massless = true
	end)

	if part:IsA("MeshPart") then
		pcall(function()
			part.CollisionFidelity = Enum.CollisionFidelity.Box
		end)
	end

	markHazardHitboxPart(part)
end

local function configureFrozenHitboxPart(part)
	part.Anchored = true
	part.CanCollide = true
	part.CanTouch = false
	part.CanQuery = true
	part.Transparency = 1
	part.AssemblyLinearVelocity = Vector3.zero
	part.AssemblyAngularVelocity = Vector3.zero
	pcall(function()
		part.Massless = true
	end)

	if part:IsA("MeshPart") then
		pcall(function()
			part.CollisionFidelity = Enum.CollisionFidelity.Box
		end)
	end

	markHazardHitboxPart(part)
end

local function configureVisualPart(part)
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = false
	part.AssemblyLinearVelocity = Vector3.zero
	part.AssemblyAngularVelocity = Vector3.zero
	pcall(function()
		part.Massless = true
	end)

	if part:IsA("MeshPart") then
		pcall(function()
			part.DoubleSided = true
		end)
		pcall(function()
			part.RenderFidelity = Enum.RenderFidelity.Precise
		end)
	end
end

local function clampSize(value)
	return math.max(MIN_PART_SIZE, value)
end

local function getWaveShapeScale(sourceSize, targetSize)
	local scaleY = if sourceSize.Y > MIN_PART_SIZE then targetSize.Y / sourceSize.Y else nil
	local scaleZ = if sourceSize.Z > MIN_PART_SIZE then targetSize.Z / sourceSize.Z else nil

	if scaleY and scaleZ then
		return math.min(scaleY, scaleZ)
	end

	if scaleY then
		return scaleY
	end

	if scaleZ then
		return scaleZ
	end

	if sourceSize.X > MIN_PART_SIZE then
		return targetSize.X / sourceSize.X
	end

	return 1
end

local function getBoundsSizeInFrame(root, boundsFrame)
	local minX, minY, minZ = math.huge, math.huge, math.huge
	local maxX, maxY, maxZ = -math.huge, -math.huge, -math.huge
	local hasBounds = false

	forEachBasePart(root, function(part)
		local halfSize = part.Size * 0.5

		for _, xSign in ipairs({ -1, 1 }) do
			for _, ySign in ipairs({ -1, 1 }) do
				for _, zSign in ipairs({ -1, 1 }) do
					local worldCorner = part.CFrame:PointToWorldSpace(Vector3.new(
						halfSize.X * xSign,
						halfSize.Y * ySign,
						halfSize.Z * zSign
					))
					local localCorner = boundsFrame:PointToObjectSpace(worldCorner)

					minX = math.min(minX, localCorner.X)
					minY = math.min(minY, localCorner.Y)
					minZ = math.min(minZ, localCorner.Z)
					maxX = math.max(maxX, localCorner.X)
					maxY = math.max(maxY, localCorner.Y)
					maxZ = math.max(maxZ, localCorner.Z)
					hasBounds = true
				end
			end
		end
	end)

	if not hasBounds then
		return nil
	end

	return Vector3.new(
		clampSize(maxX - minX),
		clampSize(maxY - minY),
		clampSize(maxZ - minZ)
	)
end

local function scaleBasePartToBox(part, targetCFrame, targetSize, configurePart)
	configurePart(part)
	part.Size = Vector3.new(
		clampSize(targetSize.X),
		clampSize(targetSize.Y),
		clampSize(targetSize.Z)
	)
	part.CFrame = targetCFrame
end

local function scaleModelToBox(model, targetCFrame, targetSize, configurePart)
	local sourceCFrame, sourceSize = model:GetBoundingBox()
	local scaleX = if sourceSize.X > MIN_PART_SIZE then targetSize.X / sourceSize.X else 1
	local scaleY = if sourceSize.Y > MIN_PART_SIZE then targetSize.Y / sourceSize.Y else 1
	local scaleZ = if sourceSize.Z > MIN_PART_SIZE then targetSize.Z / sourceSize.Z else 1

	forEachBasePart(model, function(part)
		local relative = sourceCFrame:ToObjectSpace(part.CFrame)
		local relativePosition = relative.Position
		local relativeRotation = relative - relativePosition

		configurePart(part)
		part.Size = Vector3.new(
			clampSize(part.Size.X * scaleX),
			clampSize(part.Size.Y * scaleY),
			clampSize(part.Size.Z * scaleZ)
		)
		part.CFrame = targetCFrame
			* CFrame.new(
				relativePosition.X * scaleX,
				relativePosition.Y * scaleY,
				relativePosition.Z * scaleZ
			)
			* relativeRotation
	end)

	ensureModelPrimaryPart(model)
end

local function getTargetBox(root)
	local hitbox = findHitboxRoot(root)
	if hitbox then
		if hitbox:IsA("BasePart") then
			return hitbox.CFrame, hitbox.Size, hitbox
		end

		local boxCFrame, boxSize = hitbox:GetBoundingBox()
		return boxCFrame, boxSize, hitbox
	end

	if root:IsA("BasePart") then
		return root.CFrame, root.Size, root
	end

	if root:IsA("Model") then
		local boxCFrame, boxSize = root:GetBoundingBox()
		return boxCFrame, boxSize, nil
	end

	return nil, nil, nil
end

local function getVisualTargetBox(root)
	if root:IsA("Model") and root:GetAttribute(USES_ASSET_VISUALS_ATTRIBUTE) == true then
		local hitbox = findHitboxRoot(root)
		local targetCFrame = root:GetPivot() * ASSET_TEMPLATE_ROTATION
		if hitbox then
			local targetSize = getBoundsSizeInFrame(hitbox, targetCFrame)
			if targetSize then
				return targetCFrame, targetSize
			end
		end

		local targetSize = getBoundsSizeInFrame(root, targetCFrame)
		if targetSize then
			return targetCFrame, targetSize
		end
	end

	return getTargetBox(root)
end

local function getVisualNameForAsset(assetName)
	if assetName == FROZEN_WAVE_ASSET_NAME then
		return FROZEN_VISUAL_NAME
	end

	return VISUAL_NAME
end

local function rememberVisualState(visual)
	forEachSelfAndDescendant(visual, function(item)
		if item:IsA("BasePart") or item:IsA("Decal") or item:IsA("Texture") then
			if item:GetAttribute(ORIGINAL_TRANSPARENCY_ATTRIBUTE) == nil then
				item:SetAttribute(ORIGINAL_TRANSPARENCY_ATTRIBUTE, item.Transparency)
			end
		elseif item:IsA("ParticleEmitter")
			or item:IsA("Trail")
			or item:IsA("Beam")
			or item:IsA("Smoke")
			or item:IsA("Fire")
			or item:IsA("Sparkles") then
			if item:GetAttribute(ORIGINAL_ENABLED_ATTRIBUTE) == nil then
				item:SetAttribute(ORIGINAL_ENABLED_ATTRIBUTE, item.Enabled)
			end
		end
	end)
end

local function setVisualVisible(visual, isVisible)
	if not visual then
		return
	end

	rememberVisualState(visual)

	forEachSelfAndDescendant(visual, function(item)
		if item:IsA("BasePart") or item:IsA("Decal") or item:IsA("Texture") then
			if isVisible then
				local originalTransparency = item:GetAttribute(ORIGINAL_TRANSPARENCY_ATTRIBUTE)
				item.Transparency = if typeof(originalTransparency) == "number" then originalTransparency else 0
			else
				item.Transparency = 1
			end
		elseif item:IsA("ParticleEmitter")
			or item:IsA("Trail")
			or item:IsA("Beam")
			or item:IsA("Smoke")
			or item:IsA("Fire")
			or item:IsA("Sparkles") then
			if isVisible then
				local originalEnabled = item:GetAttribute(ORIGINAL_ENABLED_ATTRIBUTE)
				item.Enabled = if typeof(originalEnabled) == "boolean" then originalEnabled else true
			else
				item.Enabled = false
			end
		end
	end)
end

local function createVisual(root, assetName, options)
	local asset = getWaveAsset(assetName, options)
	if not asset then
		return nil
	end

	local targetCFrame, targetSize = getVisualTargetBox(root)
	if not targetCFrame or not targetSize then
		return nil
	end

	local visual = asset:Clone()
	visual.Name = getVisualNameForAsset(assetName)
	visual:SetAttribute(VISUAL_ASSET_NAME_ATTRIBUTE, assetName)

	if visual:IsA("BasePart") then
		scaleBasePartToBox(visual, targetCFrame, targetSize, configureVisualPart)
	else
		scaleModelToBox(visual, targetCFrame, targetSize, configureVisualPart)
	end

	visual.Parent = root
	WaveHazardVisuals.ConfigureVisualRoot(visual)
	rememberVisualState(visual)
	visual:SetAttribute(PREPARED_VISUAL_ATTRIBUTE, true)
	return visual
end

local function ensureVisual(root, assetName, options)
	if not root then
		return nil
	end

	local visualName = getVisualNameForAsset(assetName)
	local visual = root:FindFirstChild(visualName)
	if visual then
		visual:SetAttribute(VISUAL_ASSET_NAME_ATTRIBUTE, assetName)
		WaveHazardVisuals.ConfigureVisualRoot(visual)
		rememberVisualState(visual)
		visual:SetAttribute(PREPARED_VISUAL_ATTRIBUTE, true)
		return visual
	end

	return createVisual(root, assetName, options)
end

local function shouldRunVisualBoundsDiagnostic()
	return RunService:IsStudio() and game:GetAttribute(VISUAL_BOUNDS_DIAGNOSTIC_ATTRIBUTE) == true
end

local function getAxisDriftRatio(a, b)
	local first = math.max(MIN_PART_SIZE, tonumber(a) or 0)
	local second = math.max(MIN_PART_SIZE, tonumber(b) or 0)
	return math.max(first / second, second / first)
end

local function warnIfVisualBoundsDrift(root, visual, assetName)
	if not shouldRunVisualBoundsDiagnostic() then
		return
	end

	local targetCFrame, targetSize = getVisualTargetBox(root)
	if not targetCFrame or not targetSize then
		return
	end

	local visualSize = getBoundsSizeInFrame(visual, targetCFrame)
	if not visualSize then
		return
	end

	local driftRatio = math.max(
		getAxisDriftRatio(visualSize.X, targetSize.X),
		getAxisDriftRatio(visualSize.Y, targetSize.Y),
		getAxisDriftRatio(visualSize.Z, targetSize.Z)
	)
	if driftRatio <= VISUAL_BOUNDS_DRIFT_WARN_RATIO then
		return
	end

	warnOnce(
		"visual_bounds_drift_" .. tostring(assetName),
		"Prepared wave visual bounds differ from WaveHitbox target asset=%s visual=%s target=%s root=%s.",
		tostring(assetName),
		tostring(visualSize),
		tostring(targetSize),
		root:GetFullName()
	)
end

local function findVisual(root, assetName)
	if not root then
		return nil
	end

	return root:FindFirstChild(getVisualNameForAsset(assetName))
end

local function createProxyHitbox(targetCFrame, targetSize)
	local hitbox = Instance.new("Part")
	hitbox.Name = HITBOX_NAME
	hitbox.Size = Vector3.new(
		clampSize(targetSize.X),
		clampSize(targetSize.Y),
		clampSize(targetSize.Z)
	)
	hitbox.CFrame = targetCFrame
	hitbox.CastShadow = false
	hitbox.Material = Enum.Material.SmoothPlastic
	hitbox.Color = Color3.fromRGB(0, 170, 255)
	pcall(function()
		hitbox.TopSurface = Enum.SurfaceType.Smooth
		hitbox.BottomSurface = Enum.SurfaceType.Smooth
	end)
	configureHitboxPart(hitbox)
	return hitbox
end

local function getProxyHitboxBox(template)
	local targetCFrame, targetSize = getTargetBox(template)
	targetCFrame = targetCFrame or getPivot(template)
	targetSize = targetSize or Vector3.new(20, 8, 8)

	local regularAsset = getWaveAsset(REGULAR_WAVE_ASSET_NAME)
	if regularAsset then
		local sourceSize = getWaveAssetSourceSize(regularAsset)
		if sourceSize then
			local scale = getWaveShapeScale(sourceSize, targetSize)
			targetCFrame = targetCFrame * ASSET_TEMPLATE_ROTATION
			targetSize = Vector3.new(
				clampSize(sourceSize.X * scale),
				clampSize(sourceSize.Y * scale),
				clampSize(sourceSize.Z * scale)
			)
		end
	end

	return targetCFrame, targetSize
end

local function getSanitizedBaseWaveVisualScale(config)
	if typeof(config) ~= "table" then
		return nil, "missing_config"
	end

	local visualScale = tonumber(config.BaseVisualScale)
	if not visualScale then
		return nil, "missing_base_visual_scale"
	end

	if visualScale <= 0 then
		return nil, "invalid_base_visual_scale"
	end

	return math.max(MIN_PART_SIZE, visualScale), nil
end

local function getConfiguredProxyHitboxBox(config)
	local visualScale, reason = getSanitizedBaseWaveVisualScale(config)
	if not visualScale then
		return nil, nil, reason
	end

	local regularAsset = getWaveAsset(REGULAR_WAVE_ASSET_NAME, {
		Context = "configured wave hitbox",
		WarnIfMissing = true,
	})
	local sourceSize = getWaveAssetSourceSize(regularAsset)
	if not sourceSize then
		return nil, nil, "missing_regular_wave_bounds"
	end

	local pivotOffset = if typeof(config.PivotOffset) == "Vector3" then config.PivotOffset else Vector3.zero
	local orientation = if typeof(config.Orientation) == "CFrame" then config.Orientation else ASSET_TEMPLATE_ROTATION
	local targetCFrame = CFrame.new(pivotOffset) * orientation
	local targetSize = Vector3.new(
		clampSize(sourceSize.X * visualScale),
		clampSize(sourceSize.Y * visualScale),
		clampSize(sourceSize.Z * visualScale)
	)

	return targetCFrame, targetSize, nil
end

local function createGeneratedWaveHazard(name, targetCFrame, targetSize, worldPivot)
	local model = Instance.new("Model")
	model.Name = tostring(name or "Wave")
	model:SetAttribute(USES_ASSET_VISUALS_ATTRIBUTE, true)
	model:SetAttribute(CLIENT_VISUALS_ONLY_ATTRIBUTE, true)
	model:SetAttribute(ACTIVE_VISUAL_ASSET_ATTRIBUTE, REGULAR_WAVE_ASSET_NAME)

	local hitbox = createProxyHitbox(targetCFrame, targetSize)
	hitbox.Parent = model
	model.WorldPivot = worldPivot or CFrame.new()
	return model, true
end

function WaveHazardVisuals.GetRegularWaveAsset()
	return getWaveAsset(REGULAR_WAVE_ASSET_NAME)
end

function WaveHazardVisuals.GetFrozenWaveAsset()
	return getWaveAsset(FROZEN_WAVE_ASSET_NAME)
end

function WaveHazardVisuals.ValidateWaveAssets(context)
	context = tostring(context or "unknown")
	getWaveAsset(REGULAR_WAVE_ASSET_NAME, {
		Context = context,
		WarnIfMissing = true,
	})
	getWaveAsset(FROZEN_WAVE_ASSET_NAME, {
		Context = context,
		WarnIfMissing = true,
	})
end

function WaveHazardVisuals.ComputeTimelineCFrame(
	startCFrame,
	endCFrame,
	activeSeconds,
	speed,
	distance,
	lateralDirection,
	initialLateralOffset,
	lateralVelocity,
	maxDrift,
	minLateralOffset,
	maxLateralOffset
)
	if typeof(startCFrame) ~= "CFrame" or typeof(endCFrame) ~= "CFrame" then
		return nil, 0
	end

	local travelDistance = tonumber(distance) or (endCFrame.Position - startCFrame.Position).Magnitude
	travelDistance = math.max(travelDistance, 1e-4)

	local moveSpeed = math.max(0, tonumber(speed) or 0)
	local elapsed = math.max(0, tonumber(activeSeconds) or 0)
	local alpha = math.clamp((elapsed * moveSpeed) / travelDistance, 0, 1)
	local currentCFrame = startCFrame:Lerp(endCFrame, alpha)

	local driftVelocity = tonumber(lateralVelocity) or 0
	local hasLateralRange = typeof(minLateralOffset) == "number"
		and typeof(maxLateralOffset) == "number"

	local driftLimit = math.max(0, tonumber(maxDrift) or 0)
	local shouldApplyLegacyDrift = driftLimit > 1e-4 and math.abs(driftVelocity) > 1e-4
	if (hasLateralRange or shouldApplyLegacyDrift) and typeof(lateralDirection) == "Vector3" then
		local lateralMagnitude = lateralDirection.Magnitude
		if lateralMagnitude > 1e-4 then
			local rawOffset = (tonumber(initialLateralOffset) or 0) + driftVelocity * elapsed
			local lateralOffset
			if hasLateralRange then
				lateralOffset = getBouncedLateralOffsetInRange(rawOffset, minLateralOffset, maxLateralOffset)
			else
				lateralOffset = getBouncedLateralOffset(rawOffset, driftLimit)
			end
			currentCFrame = translateCFrame(currentCFrame, lateralDirection.Unit * lateralOffset)
		end
	end

	return currentCFrame, alpha
end

function WaveHazardVisuals.GetHitboxParts(root)
	local hitbox = findHitboxRoot(root)
	local parts = {}

	if hitbox then
		forEachBasePart(hitbox, function(part)
			parts[#parts + 1] = part
		end)
		return parts
	end

	if root and root:IsA("BasePart") then
		return { root }
	end

	return parts
end

function WaveHazardVisuals.ConfigureVisualRoot(root)
	local configuredCount = 0

	forEachBasePart(root, function(part)
		configureVisualPart(part)
		configuredCount += 1
	end)

	return configuredCount
end

function WaveHazardVisuals.SetHitboxFrozen(root, isFrozen)
	local configuredCount = 0
	local configurePart = if isFrozen == true then configureFrozenHitboxPart else configureHitboxPart

	for _, part in ipairs(WaveHazardVisuals.GetHitboxParts(root)) do
		configurePart(part)
		configuredCount += 1
	end

	return configuredCount
end

function WaveHazardVisuals.PrepareVisual(root, assetName, options)
	options = if typeof(options) == "table" then options else {}

	local visual = ensureVisual(root, assetName, options)
	if not visual then
		return nil
	end

	if typeof(options.Visible) == "boolean" then
		setVisualVisible(visual, options.Visible)
	end

	warnIfVisualBoundsDrift(root, visual, assetName)
	return visual
end

function WaveHazardVisuals.PrepareVisuals(root, assetNames, options)
	options = if typeof(options) == "table" then options else {}
	local preparedVisuals = {}

	if not root or typeof(assetNames) ~= "table" then
		return false, preparedVisuals
	end

	local activeAssetName = options.ActiveAssetName
	local shouldApplyVisibility = typeof(activeAssetName) == "string" and activeAssetName ~= ""
	local activeVisual = nil
	local allPrepared = true
	local preparedCount = 0

	for _, assetName in ipairs(assetNames) do
		if typeof(assetName) == "string" and assetName ~= "" then
			local visual = ensureVisual(root, assetName, options)
			if visual then
				preparedVisuals[assetName] = visual
				preparedCount += 1
				warnIfVisualBoundsDrift(root, visual, assetName)

				if assetName == activeAssetName then
					activeVisual = visual
				end
			else
				allPrepared = false
			end
		end
	end

	if shouldApplyVisibility and activeVisual then
		for assetName, visual in pairs(preparedVisuals) do
			setVisualVisible(visual, assetName == activeAssetName)
		end
	end

	local prepared = allPrepared and preparedCount > 0
	root:SetAttribute(PREPARED_VISUALS_ATTRIBUTE, prepared)
	return prepared, preparedVisuals
end

function WaveHazardVisuals.ApplyVisual(root, assetName)
	if not root then
		return false
	end

	local activeVisual = ensureVisual(root, assetName)
	if not activeVisual then
		return false
	end

	local inactiveAssetName = if assetName == FROZEN_WAVE_ASSET_NAME then REGULAR_WAVE_ASSET_NAME else FROZEN_WAVE_ASSET_NAME
	local inactiveVisual = findVisual(root, inactiveAssetName)

	setVisualVisible(activeVisual, true)
	if inactiveVisual and inactiveVisual ~= activeVisual then
		setVisualVisible(inactiveVisual, false)
	end

	root:SetAttribute(ACTIVE_VISUAL_ASSET_ATTRIBUTE, assetName)
	return true
end

function WaveHazardVisuals.CreateHazardFromTemplate(template)
	local targetCFrame, targetSize = getProxyHitboxBox(template)
	return createGeneratedWaveHazard(template.Name, targetCFrame, targetSize, getPivot(template))
end

function WaveHazardVisuals.CreateHazardFromConfig(config)
	config = if typeof(config) == "table" then config else {}
	local targetCFrame, targetSize, reason = getConfiguredProxyHitboxBox(config)
	if not targetCFrame or not targetSize then
		return nil, false, reason or "invalid_config"
	end

	return createGeneratedWaveHazard(config.Name, targetCFrame, targetSize, CFrame.new())
end

function WaveHazardVisuals.SetFrozen(root, isFrozen)
	if not root then
		return false
	end

	root:SetAttribute("Frozen", isFrozen == true)
	WaveHazardVisuals.SetHitboxFrozen(root, isFrozen == true)
	local assetName = if isFrozen then FROZEN_WAVE_ASSET_NAME else REGULAR_WAVE_ASSET_NAME
	if root:GetAttribute(CLIENT_VISUALS_ONLY_ATTRIBUTE) == true then
		root:SetAttribute(ACTIVE_VISUAL_ASSET_ATTRIBUTE, assetName)
		return true
	end

	return WaveHazardVisuals.ApplyVisual(root, assetName)
end

return WaveHazardVisuals
