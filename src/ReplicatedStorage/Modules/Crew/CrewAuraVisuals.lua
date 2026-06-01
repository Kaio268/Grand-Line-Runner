local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CrewCatalog = require(script.Parent:WaitForChild("CrewCatalog"))

local CrewAuraVisuals = {}

local AURA_ROOT_NAME = "Auras"
local AURA_CLONE_NAME = "CrewVariantAura"
local AURA_WELD_NAME = "CrewVariantAuraWeld"
local AURA_TARGET_PRIORITY = {
	"HumanoidRootPart",
	"Torso",
	"UpperTorso",
	"LowerTorso",
}

local SUPPORTED_VARIANTS = {
	Golden = true,
	Diamond = true,
}

local function getAssetsRoot()
	return ReplicatedStorage:FindFirstChild("Assets")
end

local function getAuraRoot()
	local assets = getAssetsRoot()
	return assets and assets:FindFirstChild(AURA_ROOT_NAME) or nil
end

local function normalizeVariant(variant)
	local text = tostring(variant or "")
	if text == "" then
		return "Normal"
	end

	local lower = string.lower(text)
	if lower == "gold" or lower == "golden" then
		return "Golden"
	elseif lower == "diamond" then
		return "Diamond"
	elseif lower == "normal" then
		return "Normal"
	end

	local variantConfig = CrewCatalog.GetVariantConfig()
	for _, variantKey in ipairs(variantConfig.Order or {}) do
		if text == variantKey then
			return variantKey
		end
	end

	return text
end

local function readOption(options, key)
	if typeof(options) ~= "table" then
		return nil
	end
	local value = options[key]
	if value ~= nil then
		return value
	end
	local lowerKey = string.lower(string.sub(key, 1, 1)) .. string.sub(key, 2)
	return options[lowerKey]
end

local function resolveVariant(options)
	options = if typeof(options) == "table" then options else {}

	local explicitVariant = readOption(options, "Variant")
	if explicitVariant ~= nil then
		local normalized = normalizeVariant(explicitVariant)
		if normalized ~= "" then
			return normalized
		end
	end

	local info = readOption(options, "Info")
	if typeof(info) == "table" and info.Variant ~= nil then
		local normalized = normalizeVariant(info.Variant)
		if normalized ~= "" then
			return normalized
		end
	end

	local crewMemberId = tostring(
		readOption(options, "CrewMemberId")
			or (typeof(info) == "table" and (info.CrewMemberId or info.Id or info.BaseId))
			or readOption(options, "ModelName")
			or ""
	)
	if crewMemberId ~= "" then
		local displayInfo = CrewCatalog.GetDisplayInfo(crewMemberId, options)
		return normalizeVariant(displayInfo.Variant)
	end

	return "Normal"
end

local function getAuraAsset(variant)
	local auraRoot = getAuraRoot()
	if not auraRoot then
		return nil
	end
	return auraRoot:FindFirstChild(variant)
end

function CrewAuraVisuals.GetAuraForVariant(variant)
	local normalized = normalizeVariant(variant)
	if not SUPPORTED_VARIANTS[normalized] then
		return nil, normalized
	end
	return getAuraAsset(normalized), normalized
end

local function getCloneSource(auraAsset)
	if not auraAsset then
		return nil
	end

	local fx = auraAsset:FindFirstChild("FX")
	if fx then
		return fx
	end

	if auraAsset:IsA("BasePart") or auraAsset:IsA("Attachment") or auraAsset:IsA("Model") or auraAsset:IsA("Folder") then
		return auraAsset
	end

	return nil
end

local function findTargetPart(root)
	if typeof(root) ~= "Instance" then
		return nil
	end

	if root:IsA("BasePart") then
		return root
	end

	if root:IsA("Tool") then
		local handle = root:FindFirstChild("Handle")
		if handle and handle:IsA("BasePart") then
			return handle
		end
	end

	for _, partName in ipairs(AURA_TARGET_PRIORITY) do
		local part = root:FindFirstChild(partName, true)
		if part and part:IsA("BasePart") then
			return part
		end
	end

	if root:IsA("Model") and root.PrimaryPart and root.PrimaryPart:IsA("BasePart") then
		return root.PrimaryPart
	end

	return root:FindFirstChildWhichIsA("BasePart", true)
end

local function getPivot(instance)
	if instance:IsA("BasePart") then
		return instance.CFrame
	elseif instance:IsA("Model") then
		return instance:GetPivot()
	end

	local part = instance:FindFirstChildWhichIsA("BasePart", true)
	return part and part.CFrame or nil
end

local function findReferencePart(auraAsset)
	local reference = auraAsset and auraAsset:FindFirstChild("R6")
	if not reference then
		return nil
	end

	for _, partName in ipairs(AURA_TARGET_PRIORITY) do
		local part = reference:FindFirstChild(partName, true)
		if part and part:IsA("BasePart") then
			return part
		end
	end

	if reference:IsA("Model") and reference.PrimaryPart and reference.PrimaryPart:IsA("BasePart") then
		return reference.PrimaryPart
	end

	return reference:FindFirstChildWhichIsA("BasePart", true)
end

local function getSourceOffset(auraAsset, source)
	local referencePart = findReferencePart(auraAsset)
	local sourcePivot = getPivot(source)
	if referencePart and sourcePivot then
		return referencePart.CFrame:ToObjectSpace(sourcePivot)
	end
	return CFrame.new()
end

local function stripUnsafeDescendants(root)
	if root:IsA("BaseScript") or root:IsA("ModuleScript") or root:IsA("Sound") then
		root:Destroy()
		return
	end

	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant:IsA("BaseScript") or descendant:IsA("ModuleScript") or descendant:IsA("Sound") then
			descendant:Destroy()
		end
	end
end

local function normalizeAuraTree(root)
	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.Anchored = false
			descendant.CanCollide = false
			descendant.CanTouch = false
			descendant.CanQuery = false
			descendant.Massless = true
			descendant.CastShadow = false
			descendant.AssemblyLinearVelocity = Vector3.zero
			descendant.AssemblyAngularVelocity = Vector3.zero
			descendant.TopSurface = Enum.SurfaceType.Smooth
			descendant.BottomSurface = Enum.SurfaceType.Smooth
		end
	end

	if root:IsA("BasePart") then
		root.Anchored = false
		root.CanCollide = false
		root.CanTouch = false
		root.CanQuery = false
		root.Massless = true
		root.CastShadow = false
		root.AssemblyLinearVelocity = Vector3.zero
		root.AssemblyAngularVelocity = Vector3.zero
		root.TopSurface = Enum.SurfaceType.Smooth
		root.BottomSurface = Enum.SurfaceType.Smooth
	end
end

local function pivotCloneToTarget(clone, targetPart, offset)
	local targetCFrame = targetPart.CFrame * offset
	pcall(function()
		if clone:IsA("BasePart") then
			clone.CFrame = targetCFrame
		elseif clone:IsA("Model") then
			clone:PivotTo(targetCFrame)
		else
			local part = clone:FindFirstChildWhichIsA("BasePart", true)
			if part then
				part.CFrame = targetCFrame
			end
		end
	end)
end

local function weldAuraParts(clone, targetPart)
	local welded = false

	local function weldPart(part)
		if part == targetPart then
			return
		end

		local weld = part:FindFirstChild(AURA_WELD_NAME)
		if weld and not weld:IsA("WeldConstraint") then
			weld:Destroy()
			weld = nil
		end
		if not weld then
			weld = Instance.new("WeldConstraint")
			weld.Name = AURA_WELD_NAME
			weld.Parent = part
		end
		weld.Part0 = targetPart
		weld.Part1 = part
		weld.Enabled = true
		welded = true
	end

	if clone:IsA("BasePart") then
		weldPart(clone)
	else
		for _, descendant in ipairs(clone:GetDescendants()) do
			if descendant:IsA("BasePart") then
				weldPart(descendant)
			end
		end
	end

	return welded
end

function CrewAuraVisuals.Remove(root)
	if typeof(root) ~= "Instance" then
		return
	end

	for _, child in ipairs(root:GetChildren()) do
		if child.Name == AURA_CLONE_NAME then
			child:Destroy()
		end
	end
end

function CrewAuraVisuals.Apply(root, options)
	if typeof(root) ~= "Instance" then
		return nil, "invalid_root"
	end

	options = if typeof(options) == "table" then options else {}
	local variant = resolveVariant(options)
	if not SUPPORTED_VARIANTS[variant] then
		CrewAuraVisuals.Remove(root)
		return nil, "normal_variant"
	end

	local auraAsset = getAuraAsset(variant)
	local source = getCloneSource(auraAsset)
	if not source then
		CrewAuraVisuals.Remove(root)
		return nil, "missing_aura_asset"
	end

	local targetPart = findTargetPart(root)
	if not targetPart then
		CrewAuraVisuals.Remove(root)
		return nil, "missing_target_part"
	end

	CrewAuraVisuals.Remove(root)

	local clone = source:Clone()
	clone.Name = AURA_CLONE_NAME
	stripUnsafeDescendants(clone)
	normalizeAuraTree(clone)
	clone.Parent = root
	pivotCloneToTarget(clone, targetPart, getSourceOffset(auraAsset, source))
	weldAuraParts(clone, targetPart)

	clone:SetAttribute("CrewAuraVariant", variant)
	clone:SetAttribute("CrewAuraTarget", targetPart.Name)
	return clone, "ok"
end

function CrewAuraVisuals.Refresh(root, options)
	return CrewAuraVisuals.Apply(root, options)
end

return CrewAuraVisuals
