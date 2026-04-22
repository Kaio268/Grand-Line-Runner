local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Registry = require(script.Parent:WaitForChild("Registry"))

local DevilFruitOptionalEffects = {}

local DEFAULT_DIRECTION = Vector3.new(0, 0, -1)
local DEFAULT_EMIT_COUNT = 20
local DEFAULT_VISUAL_LIFETIME = 2
local TRANSIENT_DISABLE_DELAY = 0.2
local EFFECT_ANCHOR_NAME = "DevilFruitOptionalEffectAnchor"
local MIN_VISUAL_SCALE = 0.05
local MAX_VISUAL_SCALE = 12
local POSITION_FIELD_CANDIDATES = {
	"EffectPosition",
	"OriginPosition",
	"MinePosition",
	"ImpactPosition",
	"StartPosition",
	"EndPosition",
	"Position",
}
local DIRECTION_FIELD_CANDIDATES = {
	"VisualDirection",
	"Direction",
}
local VISUAL_ROOT_CANDIDATES = {
	{
		Segments = { "Assets", "VFX" },
	},
	{
		Segments = { "Particles", "DevilFruits" },
	},
}
local SOUND_ROOT_CANDIDATES = {
	{
		Segments = { "Assets", "Sounds" },
	},
	{
		Segments = { "Sounds", "DevilFruits" },
	},
}

local function appendUnique(target, seen, value)
	if typeof(value) ~= "string" or value == "" or seen[value] then
		return
	end

	seen[value] = true
	target[#target + 1] = value
end

local function normalizeName(name)
	if typeof(name) ~= "string" then
		return nil
	end

	local normalized = string.lower(name:gsub("[%W_]+", ""))
	if normalized == "" then
		return nil
	end

	return normalized
end

local function formatAbilityDisplayName(abilityName)
	return tostring(abilityName):gsub("(%l)(%u)", "%1 %2")
end

local function eachSelfAndDescendants(root, callback)
	if not root then
		return
	end

	callback(root)
	for _, descendant in ipairs(root:GetDescendants()) do
		callback(descendant)
	end
end

local function resolvePlayerRootPart(targetPlayer)
	if not targetPlayer or not targetPlayer:IsA("Player") then
		return nil
	end

	local character = targetPlayer.Character
	if not character then
		return nil
	end

	return character:FindFirstChild("HumanoidRootPart")
end

local function resolveFieldVector(payload, fieldCandidates)
	if typeof(payload) ~= "table" then
		return nil
	end

	for _, fieldName in ipairs(fieldCandidates) do
		local value = payload[fieldName]
		if typeof(value) == "Vector3" then
			return value
		end
	end

	return nil
end

local function resolveEffectPosition(rootPart, payload)
	local position = resolveFieldVector(payload, POSITION_FIELD_CANDIDATES)
	if typeof(position) == "Vector3" then
		return position
	end

	return rootPart and rootPart.Position or nil
end

local function resolveEffectDirection(rootPart, payload)
	local direction = resolveFieldVector(payload, DIRECTION_FIELD_CANDIDATES)
	if typeof(direction) == "Vector3" then
		local planarDirection = Vector3.new(direction.X, 0, direction.Z)
		if planarDirection.Magnitude > 0.01 then
			return planarDirection.Unit
		end
	end

	if rootPart then
		local lookVector = rootPart.CFrame.LookVector
		local planarLook = Vector3.new(lookVector.X, 0, lookVector.Z)
		if planarLook.Magnitude > 0.01 then
			return planarLook.Unit
		end
	end

	return DEFAULT_DIRECTION
end

local function getRootNode(segments)
	local node = ReplicatedStorage
	for _, segment in ipairs(segments or {}) do
		if not node then
			return nil
		end

		node = node:FindFirstChild(segment)
	end

	return node
end

local function findMatchingChild(parent, candidates)
	if not parent then
		return nil
	end

	for _, candidate in ipairs(candidates or {}) do
		local direct = parent:FindFirstChild(candidate)
		if direct then
			return direct
		end
	end

	local normalizedCandidates = {}
	for _, candidate in ipairs(candidates or {}) do
		local normalized = normalizeName(candidate)
		if normalized then
			normalizedCandidates[normalized] = true
		end
	end

	if next(normalizedCandidates) == nil then
		return nil
	end

	for _, child in ipairs(parent:GetChildren()) do
		local normalizedChildName = normalizeName(child.Name)
		if normalizedChildName and normalizedCandidates[normalizedChildName] then
			return child
		end
	end

	return nil
end

local function buildFruitFolderCandidates(fruitIdentifier)
	local fruitEntry = Registry.ResolveFruitEntry(fruitIdentifier)
	local candidates = {}
	local seen = {}

	appendUnique(candidates, seen, fruitEntry and fruitEntry.AssetFolder)
	appendUnique(candidates, seen, fruitEntry and fruitEntry.FruitKey)
	appendUnique(candidates, seen, fruitEntry and fruitEntry.Id)
	appendUnique(candidates, seen, fruitEntry and fruitEntry.DisplayName)
	appendUnique(candidates, seen, fruitEntry and fruitEntry.Config and fruitEntry.Config.AbilityModule)
	appendUnique(candidates, seen, typeof(fruitIdentifier) == "string" and fruitIdentifier or nil)

	return candidates
end

local function buildAbilityCandidates(fruitIdentifier, abilityName)
	local abilityEntry = Registry.GetAbility(fruitIdentifier, abilityName)
	local candidates = {}
	local seen = {}

	appendUnique(candidates, seen, typeof(abilityName) == "string" and abilityName or nil)
	appendUnique(candidates, seen, abilityEntry and abilityEntry.DisplayName)
	appendUnique(candidates, seen, typeof(abilityName) == "string" and formatAbilityDisplayName(abilityName) or nil)

	return candidates
end

local function resolveTemplate(rootCandidates, fruitIdentifier, abilityName)
	local fruitCandidates = buildFruitFolderCandidates(fruitIdentifier)
	local abilityCandidates = buildAbilityCandidates(fruitIdentifier, abilityName)
	if #fruitCandidates == 0 or #abilityCandidates == 0 then
		return nil
	end

	for _, rootCandidate in ipairs(rootCandidates) do
		local rootNode = getRootNode(rootCandidate.Segments)
		if rootNode then
			local fruitFolder = findMatchingChild(rootNode, fruitCandidates)
			local abilityTemplate = fruitFolder and findMatchingChild(fruitFolder, abilityCandidates)
			if abilityTemplate then
				return abilityTemplate
			end
		end
	end

	return nil
end

local function createEffectAnchor(position, direction)
	if typeof(position) ~= "Vector3" then
		return nil
	end

	local resolvedDirection = typeof(direction) == "Vector3" and direction or DEFAULT_DIRECTION
	local anchor = Instance.new("Part")
	anchor.Name = EFFECT_ANCHOR_NAME
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanTouch = false
	anchor.CanQuery = false
	anchor.Massless = true
	anchor.Transparency = 1
	anchor.Size = Vector3.new(0.2, 0.2, 0.2)
	anchor.CFrame = CFrame.lookAt(position, position + resolvedDirection)
	anchor.Parent = Workspace
	return anchor
end

local function setBasePartDefaults(part)
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.Massless = true
end

local function setInstanceDefaults(root)
	eachSelfAndDescendants(root, function(item)
		if item:IsA("BasePart") then
			setBasePartDefaults(item)
		end
	end)
end

local function setTransientVisualsEnabled(root, enabled)
	eachSelfAndDescendants(root, function(item)
		if item:IsA("Trail") or item:IsA("Beam") then
			item.Enabled = enabled
		elseif item:IsA("PointLight") or item:IsA("SpotLight") or item:IsA("SurfaceLight") then
			item.Enabled = enabled
		end
	end)
end

local function emitParticles(root)
	eachSelfAndDescendants(root, function(item)
		if item:IsA("ParticleEmitter") then
			item:Emit(tonumber(item:GetAttribute("EmitCount")) or DEFAULT_EMIT_COUNT)
		end
	end)
end

local function getReferencePosition(root)
	if root:IsA("BasePart") then
		return root.Position
	end

	if root:IsA("Model") then
		local ok, pivot = pcall(function()
			return root:GetPivot()
		end)
		if ok then
			return pivot.Position
		end
	end

	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant:IsA("BasePart") then
			return descendant.Position
		end
	end

	return nil
end

local function scaleNumberSequence(sequence, scale)
	if typeof(sequence) ~= "NumberSequence" or typeof(scale) ~= "number" then
		return sequence
	end

	local scaledKeypoints = table.create(#sequence.Keypoints)
	for index, keypoint in ipairs(sequence.Keypoints) do
		scaledKeypoints[index] = NumberSequenceKeypoint.new(
			keypoint.Time,
			keypoint.Value * scale,
			keypoint.Envelope * scale
		)
	end

	return NumberSequence.new(scaledKeypoints)
end

local function scaleNumberRange(range, scale)
	if typeof(range) ~= "NumberRange" or typeof(scale) ~= "number" then
		return range
	end

	return NumberRange.new(range.Min * scale, range.Max * scale)
end

local function resolveVisualScale(fruitIdentifier, abilityName, payload)
	if typeof(payload) ~= "table" then
		return 1
	end

	local explicitScale = tonumber(payload.VisualScale)
	if explicitScale and explicitScale > 0 then
		return math.clamp(explicitScale, MIN_VISUAL_SCALE, MAX_VISUAL_SCALE)
	end

	local visualRadius = tonumber(payload.VisualRadius) or tonumber(payload.Radius)
	if not visualRadius or visualRadius <= 0 then
		return 1
	end

	local abilityEntry = Registry.GetAbility(fruitIdentifier, abilityName)
	local baseRadius = tonumber(abilityEntry and abilityEntry.Config and abilityEntry.Config.VisualBaseRadius)
	if not baseRadius or baseRadius <= 0 then
		return 1
	end

	return math.clamp(visualRadius / baseRadius, MIN_VISUAL_SCALE, MAX_VISUAL_SCALE)
end

local function scaleBasePartAroundOrigin(part, scale, originPosition)
	if typeof(scale) ~= "number" or typeof(originPosition) ~= "Vector3" then
		return
	end

	local rotation = part.CFrame - part.Position
	local scaledPosition = originPosition + ((part.Position - originPosition) * scale)
	part.Size = part.Size * scale
	part.CFrame = CFrame.new(scaledPosition) * rotation
end

local function scaleVisualClone(clone, scale)
	if typeof(scale) ~= "number" or math.abs(scale - 1) <= 0.001 then
		return
	end

	local originPosition = getReferencePosition(clone)
	eachSelfAndDescendants(clone, function(item)
		if item:IsA("BasePart") then
			scaleBasePartAroundOrigin(item, scale, originPosition)
		elseif item:IsA("Attachment") then
			item.Position = item.Position * scale
		elseif item:IsA("ParticleEmitter") then
			item.Size = scaleNumberSequence(item.Size, scale)
			item.Speed = scaleNumberRange(item.Speed, scale)
			item.Acceleration = item.Acceleration * scale
			item.Drag = item.Drag * scale
		elseif item:IsA("Beam") then
			item.Width0 *= scale
			item.Width1 *= scale
			item.CurveSize0 *= scale
			item.CurveSize1 *= scale
		elseif item:IsA("Trail") then
			item.WidthScale = scaleNumberSequence(item.WidthScale, scale)
		elseif item:IsA("PointLight") or item:IsA("SpotLight") or item:IsA("SurfaceLight") then
			item.Range *= scale
		elseif item:IsA("Smoke") then
			item.Size *= scale
			item.RiseVelocity *= scale
		elseif item:IsA("Fire") then
			item.Size *= scale
			item.Heat *= scale
		end
	end)
end

local function moveInstanceToPosition(root, position)
	if typeof(position) ~= "Vector3" then
		return false
	end

	local referencePosition = getReferencePosition(root)
	if typeof(referencePosition) ~= "Vector3" then
		return false
	end

	local delta = position - referencePosition
	eachSelfAndDescendants(root, function(item)
		if item:IsA("BasePart") then
			item.CFrame = item.CFrame + delta
		end
	end)

	return true
end

local function getVisualLifetime(payload)
	local explicitLifetime = typeof(payload) == "table" and payload.VisualLifetime or nil
	if typeof(explicitLifetime) == "number" and explicitLifetime > 0 then
		return explicitLifetime
	end

	return DEFAULT_VISUAL_LIFETIME
end

local function playAttachmentVisual(rootPart, template, payload, effectScale)
	local parent = rootPart
	local anchor = nil
	local effectPosition = resolveEffectPosition(rootPart, payload)
	if typeof(effectPosition) == "Vector3" and (not rootPart or (effectPosition - rootPart.Position).Magnitude > 1) then
		anchor = createEffectAnchor(effectPosition, resolveEffectDirection(rootPart, payload))
		parent = anchor
	end

	if not parent then
		return false
	end

	local clone = template:Clone()
	scaleVisualClone(clone, effectScale)
	clone.Parent = parent
	emitParticles(clone)
	setTransientVisualsEnabled(clone, true)

	task.delay(TRANSIENT_DISABLE_DELAY, function()
		if clone and clone.Parent then
			setTransientVisualsEnabled(clone, false)
		end
	end)

	Debris:AddItem(anchor or clone, getVisualLifetime(payload))
	return true
end

local function playParticleEmitterVisual(rootPart, template, payload, effectScale)
	local parent = rootPart
	local anchor = nil
	local effectPosition = resolveEffectPosition(rootPart, payload)
	if typeof(effectPosition) == "Vector3" and (not rootPart or (effectPosition - rootPart.Position).Magnitude > 1) then
		anchor = createEffectAnchor(effectPosition, resolveEffectDirection(rootPart, payload))
		parent = anchor
	end

	if not parent then
		return false
	end

	local clone = template:Clone()
	scaleVisualClone(clone, effectScale)
	clone.Parent = parent
	clone:Emit(tonumber(clone:GetAttribute("EmitCount")) or DEFAULT_EMIT_COUNT)
	Debris:AddItem(anchor or clone, getVisualLifetime(payload))
	return true
end

local function playWorldVisual(rootPart, template, payload, effectScale)
	local clone = template:Clone()
	scaleVisualClone(clone, effectScale)
	setInstanceDefaults(clone)
	clone.Parent = Workspace

	local effectPosition = resolveEffectPosition(rootPart, payload)
	if typeof(effectPosition) == "Vector3" then
		moveInstanceToPosition(clone, effectPosition)
	end

	emitParticles(clone)
	setTransientVisualsEnabled(clone, true)
	task.delay(TRANSIENT_DISABLE_DELAY, function()
		if clone and clone.Parent then
			setTransientVisualsEnabled(clone, false)
		end
	end)

	Debris:AddItem(clone, getVisualLifetime(payload))
	return true
end

local function playVisualTemplate(rootPart, template, payload, effectScale)
	if not template then
		return false
	end

	if template:IsA("Folder") then
		local playedAny = false
		for _, child in ipairs(template:GetChildren()) do
			if child:IsA("Sound") then
				continue
			end

			playedAny = playVisualTemplate(rootPart, child, payload, effectScale) or playedAny
		end
		return playedAny
	end

	if template:IsA("ParticleEmitter") then
		return playParticleEmitterVisual(rootPart, template, payload, effectScale)
	end

	if template:IsA("Attachment") then
		return playAttachmentVisual(rootPart, template, payload, effectScale)
	end

	if template:IsA("BasePart") or template:IsA("Model") then
		return playWorldVisual(rootPart, template, payload, effectScale)
	end

	return false
end

local function playSoundTemplate(rootPart, template)
	if not rootPart or not template then
		return false
	end

	if template:IsA("Folder") then
		local playedAny = false
		for _, child in ipairs(template:GetChildren()) do
			playedAny = playSoundTemplate(rootPart, child) or playedAny
		end
		return playedAny
	end

	if not template:IsA("Sound") then
		return false
	end

	local soundClone = template:Clone()
	soundClone.Parent = rootPart
	soundClone:Play()

	soundClone.Ended:Connect(function()
		if soundClone.Parent then
			soundClone:Destroy()
		end
	end)

	Debris:AddItem(soundClone, math.max(soundClone.TimeLength + 1, 5))
	return true
end

function DevilFruitOptionalEffects.ResolveVisualTemplate(fruitIdentifier, abilityName)
	return resolveTemplate(VISUAL_ROOT_CANDIDATES, fruitIdentifier, abilityName)
end

function DevilFruitOptionalEffects.ResolveSoundTemplate(fruitIdentifier, abilityName)
	return resolveTemplate(SOUND_ROOT_CANDIDATES, fruitIdentifier, abilityName)
end

function DevilFruitOptionalEffects.Play(targetPlayer, fruitIdentifier, abilityName, payload)
	local rootPart = resolvePlayerRootPart(targetPlayer)
	local visualTemplate = DevilFruitOptionalEffects.ResolveVisualTemplate(fruitIdentifier, abilityName)
	local soundTemplate = DevilFruitOptionalEffects.ResolveSoundTemplate(fruitIdentifier, abilityName)
	local effectScale = resolveVisualScale(fruitIdentifier, abilityName, payload)

	local visualPlayed = playVisualTemplate(rootPart, visualTemplate, payload, effectScale)
	local soundPlayed = playSoundTemplate(rootPart, soundTemplate)

	return visualPlayed or soundPlayed
end

return DevilFruitOptionalEffects
