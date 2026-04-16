local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local VfxCommon = require(
	Modules:WaitForChild("DevilFruits")
		:WaitForChild("Mera")
		:WaitForChild("Shared")
		:WaitForChild("Vfx")
		:WaitForChild("VfxCommon")
)

local GomuVfxController = {}
GomuVfxController.__index = GomuVfxController

local DEFAULT_DIRECTION = Vector3.new(0, 0, -1)
local VFX_ANCHOR_SIZE = Vector3.new(0.25, 0.25, 0.25)

local function getGomuAssetRoot()
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local vfx = assets and assets:FindFirstChild("VFX")
	local gomu = vfx and vfx:FindFirstChild("Gomu")
	return gomu and gomu:FindFirstChild("GomuBomb")
end

local function eachDescendantOfType(root, className, callback)
	if not root then
		return
	end

	if root:IsA(className) then
		callback(root)
	end

	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant:IsA(className) then
			callback(descendant)
		end
	end
end

local function getInstancePivotCFrame(instance)
	if not instance then
		return nil
	end

	if instance:IsA("Model") then
		local ok, pivot = pcall(function()
			return instance:GetPivot()
		end)
		if ok then
			return pivot
		end
	end

	if instance:IsA("BasePart") then
		return instance.CFrame
	end

	for _, descendant in ipairs(instance:GetDescendants()) do
		if descendant:IsA("BasePart") then
			return descendant.CFrame
		end
	end

	return nil
end

local function positionClone(clone, targetCFrame)
	if typeof(clone) ~= "Instance" or typeof(targetCFrame) ~= "CFrame" then
		return nil
	end

	local pivotCFrame = getInstancePivotCFrame(clone)
	if pivotCFrame then
		local delta = targetCFrame * pivotCFrame:Inverse()
		local movedAnyPart = false

		eachDescendantOfType(clone, "BasePart", function(part)
			part.CFrame = delta * part.CFrame
			part.Anchored = true
			part.CanCollide = false
			part.CanTouch = false
			part.CanQuery = false
			part.Massless = true
			movedAnyPart = true
		end)

		return movedAnyPart and clone or nil
	end

	local anchor = Instance.new("Part")
	anchor.Name = "GomuVfxAnchor"
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanTouch = false
	anchor.CanQuery = false
	anchor.CastShadow = false
	anchor.Transparency = 1
	anchor.Size = VFX_ANCHOR_SIZE
	anchor.CFrame = targetCFrame
	anchor.Parent = Workspace

	return anchor
end

local function resolveDirection(direction)
	local candidate = typeof(direction) == "Vector3" and Vector3.new(direction.X, 0, direction.Z) or DEFAULT_DIRECTION
	if candidate.Magnitude <= 0.01 then
		return DEFAULT_DIRECTION
	end
	return candidate.Unit
end

function GomuVfxController.new()
	return setmetatable({}, GomuVfxController)
end

function GomuVfxController:PlayBomb(position, direction)
	print("[GomuVfxController] PlayBomb called", position, direction)

	if typeof(position) ~= "Vector3" then
		warn("[GomuVfxController] position is not a Vector3")
		return false
	end

	local effectRoot = getGomuAssetRoot()
	print("[GomuVfxController] effectRoot", effectRoot, effectRoot and effectRoot.ClassName)

	if not effectRoot then
		warn("[GomuVfxController] Missing asset: ReplicatedStorage.Assets.VFX.Gomu.GomuBomb")
		return false
	end

	local facingDirection = resolveDirection(direction)
	local spawnPosition = position + Vector3.new(0, 3, 0)
	local targetCFrame = CFrame.lookAt(spawnPosition, spawnPosition + facingDirection, Vector3.yAxis)

	local clone = effectRoot:Clone()
	if not clone then
		warn("[GomuVfxController] Clone failed")
		return false
	end

	print("[GomuVfxController] clone created", clone, clone.ClassName)

	clone.Parent = Workspace

	local cleanupRoot = positionClone(clone, targetCFrame)
	if not cleanupRoot then
		clone:Destroy()
		warn("[GomuVfxController] Position failed")
		return false
	end

	for _, obj in ipairs(clone:GetDescendants()) do
		if obj:IsA("BasePart") then
			obj.Anchored = true
			obj.CanCollide = false
			obj.CanTouch = false
			obj.CanQuery = false
			obj.Massless = true
		elseif obj:IsA("ParticleEmitter") then
			obj.Enabled = true
			obj:Emit(25)
			print("[GomuVfxController] emitted from", obj:GetFullName())
		end
	end

	task.delay(3, function()
		if cleanupRoot and cleanupRoot.Parent then
			cleanupRoot:Destroy()
		end
	end)

	return true
end

function GomuVfxController:HandleCharacterRemoving()
end

function GomuVfxController:HandlePlayerRemoving()
end

return GomuVfxController