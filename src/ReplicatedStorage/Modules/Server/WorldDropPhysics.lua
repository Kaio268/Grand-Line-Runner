local Workspace = game:GetService("Workspace")

local WorldDropPhysics = {}

local DEFAULT_START_HEIGHT = 6
local DEFAULT_SETTLE_TIMEOUT = 2.5
local DEFAULT_SETTLE_INTERVAL = 0.08
local DEFAULT_NEAR_GROUND_DISTANCE = 1.2
local DEFAULT_NEAR_GROUND_RAY_DISTANCE = 12
local DEFAULT_GROUND_RAY_HEIGHT = 6
local DEFAULT_GROUND_RAY_DISTANCE = 300

local function forEachPart(object, callback)
	if not object or typeof(callback) ~= "function" then
		return
	end

	if object:IsA("BasePart") then
		callback(object)
		return
	end

	for _, descendant in ipairs(object:GetDescendants()) do
		if descendant:IsA("BasePart") then
			callback(descendant)
		end
	end
end

local function getRootPart(object)
	if not object then
		return nil
	end

	if object:IsA("BasePart") then
		return object
	end

	if object:IsA("Model") then
		if object.PrimaryPart then
			return object.PrimaryPart
		end

		local part = object:FindFirstChildWhichIsA("BasePart", true)
		if part then
			pcall(function()
				object.PrimaryPart = part
			end)
			return object.PrimaryPart or part
		end
	end

	return nil
end

local function getBoundingBox(object)
	if object and object:IsA("Model") then
		return object:GetBoundingBox()
	end

	if object and object:IsA("BasePart") then
		return object.CFrame, object.Size
	end

	return CFrame.new(), Vector3.new(2, 2, 2)
end

local function getPivot(object)
	if object and object:IsA("Model") then
		return object:GetPivot()
	end

	if object and object:IsA("BasePart") then
		return object.CFrame
	end

	return CFrame.new()
end

local function setCFrame(object, cframe)
	if not object or typeof(cframe) ~= "CFrame" then
		return
	end

	if object:IsA("Model") then
		object:PivotTo(cframe)
	elseif object:IsA("BasePart") then
		object.CFrame = cframe
	end
end

local function getFlatRotationFromCFrame(cframe)
	if typeof(cframe) ~= "CFrame" then
		return CFrame.new()
	end

	local lookVector = cframe.LookVector
	local direction = Vector3.new(lookVector.X, 0, lookVector.Z)
	if direction.Magnitude < 1e-4 then
		direction = Vector3.new(0, 0, -1)
	else
		direction = direction.Unit
	end

	local rotation = CFrame.lookAt(Vector3.zero, direction, Vector3.yAxis)
	return rotation - rotation.Position
end

local function isPartWithinObject(part, object)
	if not part or not object then
		return false
	end

	if object:IsA("BasePart") then
		return part == object or part:IsDescendantOf(object)
	end

	return part:IsDescendantOf(object)
end

local function isHumanoidModel(model)
	return model and model:IsA("Model") and model:FindFirstChildOfClass("Humanoid") ~= nil
end

local function isValidGroundResult(result, selfObject, options)
	if not result or not result.Instance or not result.Instance:IsA("BasePart") then
		return false
	end

	local hitPart = result.Instance
	if isPartWithinObject(hitPart, selfObject) then
		return false
	end
	if options.RejectHumanoidModels ~= false then
		local hitModel = hitPart:FindFirstAncestorOfClass("Model")
		if isHumanoidModel(hitModel) then
			return false
		end
	end
	return hitPart.CanCollide == true
end

local function buildIgnoreList(object, extraIgnore)
	local ignore = {}
	if typeof(object) == "Instance" then
		ignore[#ignore + 1] = object
	end

	if typeof(extraIgnore) == "table" then
		for _, instance in ipairs(extraIgnore) do
			if typeof(instance) == "Instance" then
				ignore[#ignore + 1] = instance
			end
		end
	end
	return ignore
end

local function trace(options, message, ...)
	if typeof(options.Trace) ~= "function" then
		return
	end

	options.Trace(message, ...)
end

local function canContinue(object, shouldContinue)
	if not object or not object.Parent then
		return false
	end
	if typeof(shouldContinue) ~= "function" then
		return true
	end

	local ok, result = pcall(shouldContinue)
	return ok and result ~= false
end

local function describeCancel(options)
	if typeof(options.DescribeCancel) == "function" then
		return tostring(options.DescribeCancel())
	end
	return "cancelled"
end

local function appendCandidate(candidates, position)
	if typeof(position) ~= "Vector3" then
		return
	end

	for _, existing in ipairs(candidates) do
		if (existing - position).Magnitude < 0.05 then
			return
		end
	end

	candidates[#candidates + 1] = position
end

local function getGroundAtPosition(position, object, options)
	if typeof(position) ~= "Vector3" then
		return nil, nil
	end

	local rayHeight = tonumber(options.GroundRayHeight) or DEFAULT_GROUND_RAY_HEIGHT
	local rayDistance = tonumber(options.GroundRayDistance) or DEFAULT_GROUND_RAY_DISTANCE
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = buildIgnoreList(object, options.ExtraIgnore)
	params.IgnoreWater = true

	local result = Workspace:Raycast(position + Vector3.new(0, rayHeight, 0), Vector3.new(0, -rayDistance, 0), params)
	if isValidGroundResult(result, object, options) then
		return result.Position, result
	end
	return nil, result
end

local function resolveSettleGround(object, options)
	local candidates = {}
	appendCandidate(candidates, getPivot(object).Position)
	appendCandidate(candidates, options.DropPosition)
	appendCandidate(candidates, options.StartFallBasePosition)
	appendCandidate(candidates, options.StartPosition)

	local firstRejectedResult = nil
	for index, candidate in ipairs(candidates) do
		local ground, result = getGroundAtPosition(candidate, object, options)
		if ground then
			return ground, result, candidate, index
		end
		firstRejectedResult = firstRejectedResult or result
	end

	return nil, firstRejectedResult, nil, nil
end

function WorldDropPhysics.ForEachPart(object, callback)
	return forEachPart(object, callback)
end

function WorldDropPhysics.GetRootPart(object)
	return getRootPart(object)
end

function WorldDropPhysics.GetPivot(object)
	return getPivot(object)
end

function WorldDropPhysics.SetCFrame(object, cframe)
	return setCFrame(object, cframe)
end

function WorldDropPhysics.GetBoundingBox(object)
	return getBoundingBox(object)
end

function WorldDropPhysics.GetFlatRotation(cframe)
	return getFlatRotationFromCFrame(cframe)
end

function WorldDropPhysics.ComputePivotBottomOnPoint(object, point, rotationOnly)
	local boxCF, boxSize = getBoundingBox(object)
	local offset = getPivot(object):ToObjectSpace(boxCF)
	local desiredBoxCF = CFrame.new(point + Vector3.yAxis * (boxSize.Y / 2)) * (rotationOnly or CFrame.new())
	return desiredBoxCF * offset:Inverse()
end

function WorldDropPhysics.PlaceAtDropStart(object, basePosition, options)
	options = if typeof(options) == "table" then options else {}
	if typeof(basePosition) ~= "Vector3" then
		return nil
	end

	local startHeight = tonumber(options.StartHeight) or DEFAULT_START_HEIGHT
	local rotationOnly = options.RotationOnly
	if typeof(rotationOnly) ~= "CFrame" then
		rotationOnly = getFlatRotationFromCFrame(getPivot(object))
	end
	local startPosition = basePosition + Vector3.new(0, startHeight, 0)
	local pivotStart = WorldDropPhysics.ComputePivotBottomOnPoint(object, startPosition, rotationOnly)
	setCFrame(object, pivotStart)
	return pivotStart, startPosition
end

function WorldDropPhysics.ApplyDropPhysics(object, options)
	options = if typeof(options) == "table" then options else {}
	local rootPart = options.RootPart
	if not (rootPart and rootPart:IsA("BasePart")) then
		rootPart = getRootPart(object)
	end

	forEachPart(object, function(part)
		part.Anchored = false
		part.CanCollide = true
		part.CanTouch = true
		part.CanQuery = true
		part.Massless = false
		part.AssemblyLinearVelocity = Vector3.zero
		part.AssemblyAngularVelocity = Vector3.zero
		pcall(function()
			part:SetNetworkOwner(nil)
		end)

		if typeof(options.ConfigurePart) == "function" then
			options.ConfigurePart(part, part == rootPart, rootPart)
		end
	end)
end

function WorldDropPhysics.AnchorAll(object)
	forEachPart(object, function(part)
		part.Anchored = true
		part.AssemblyLinearVelocity = Vector3.zero
		part.AssemblyAngularVelocity = Vector3.zero
	end)
end

function WorldDropPhysics.SettleToGround(object, shouldContinue, options)
	options = if typeof(options) == "table" then options else {}
	local reasonCode = tostring(options.ReasonCode or "Unknown")
	local carryId = tostring(options.CarryId or "")
	local objectName = tostring(object and object.Name or "<nil>")

	trace(
		options,
		"begin reason=%s carryId=%s model=%s start=%s",
		reasonCode,
		carryId,
		objectName,
		tostring(object and getPivot(object).Position or "")
	)

	if not canContinue(object, shouldContinue) then
		trace(
			options,
			"exitBeforeLoop reason=%s carryId=%s model=%s state=%s",
			reasonCode,
			carryId,
			objectName,
			describeCancel(options)
		)
		return "cancelled"
	end

	local primary = getRootPart(object)
	local timeoutSeconds = tonumber(options.SettleTimeout) or DEFAULT_SETTLE_TIMEOUT
	local intervalSeconds = tonumber(options.SettleInterval) or DEFAULT_SETTLE_INTERVAL
	local nearGroundDistance = tonumber(options.NearGroundDistance) or DEFAULT_NEAR_GROUND_DISTANCE
	local nearGroundRayDistance = tonumber(options.NearGroundRayDistance) or DEFAULT_NEAR_GROUND_RAY_DISTANCE
	local startedAt = os.clock()
	while object.Parent and os.clock() - startedAt < timeoutSeconds do
		if not canContinue(object, shouldContinue) then
			trace(
				options,
				"exitDuringLoop reason=%s carryId=%s model=%s state=%s elapsed=%.2f",
				reasonCode,
				carryId,
				objectName,
				describeCancel(options),
				os.clock() - startedAt
			)
			return "cancelled"
		end

		task.wait(intervalSeconds)
		if not primary or not primary.Parent then
			primary = getRootPart(object)
		end
		if primary then
			local params = RaycastParams.new()
			params.FilterType = Enum.RaycastFilterType.Exclude
			params.FilterDescendantsInstances = buildIgnoreList(object, options.ExtraIgnore)
			params.IgnoreWater = true

			local origin = primary.Position
			local result = Workspace:Raycast(origin, Vector3.new(0, -nearGroundRayDistance, 0), params)
			if result and isValidGroundResult(result, object, options) and (origin.Y - result.Position.Y) <= nearGroundDistance then
				break
			end
		end
	end

	if object.Parent and os.clock() - startedAt >= timeoutSeconds then
		trace(
			options,
			"timeoutFallback reason=%s carryId=%s model=%s pivot=%s",
			reasonCode,
			carryId,
			objectName,
			tostring(getPivot(object).Position)
		)
	end
	if not object.Parent then
		trace(
			options,
			"exitBeforeAnchor reason=%s carryId=%s model=%s state=model_unparented",
			reasonCode,
			carryId,
			objectName
		)
		return "cancelled"
	end
	if not canContinue(object, shouldContinue) then
		trace(
			options,
			"exitBeforeAnchor reason=%s carryId=%s model=%s state=%s",
			reasonCode,
			carryId,
			objectName,
			describeCancel(options)
		)
		return "cancelled"
	end

	local ground, result, candidate, candidateIndex = resolveSettleGround(object, options)
	if not ground then
		trace(
			options,
			"settleNoGround reason=%s carryId=%s model=%s pivot=%s rejectedHit=%s",
			reasonCode,
			carryId,
			objectName,
			tostring(getPivot(object).Position),
			tostring(result and result.Instance and result.Instance:GetFullName() or "")
		)
		return "no_ground"
	end

	local pivotTarget = WorldDropPhysics.ComputePivotBottomOnPoint(
		object,
		ground,
		getFlatRotationFromCFrame(getPivot(object))
	)
	setCFrame(object, pivotTarget)
	if not canContinue(object, shouldContinue) then
		trace(
			options,
			"exitAfterPivot reason=%s carryId=%s model=%s state=%s pivot=%s",
			reasonCode,
			carryId,
			objectName,
			describeCancel(options),
			tostring(getPivot(object).Position)
		)
		return "cancelled"
	end

	if options.AnchorAfterSettle == true then
		WorldDropPhysics.AnchorAll(object)
		trace(
			options,
			"anchorComplete reason=%s carryId=%s model=%s finalPivot=%s ground=%s candidate=%s candidateIndex=%s hit=%s",
			reasonCode,
			carryId,
			objectName,
			tostring(getPivot(object).Position),
			tostring(ground),
			tostring(candidate),
			tostring(candidateIndex or ""),
			tostring(result and result.Instance and result.Instance:GetFullName() or "")
		)
		return "anchored"
	end

	trace(
		options,
		"settleComplete reason=%s carryId=%s model=%s finalPivot=%s ground=%s candidate=%s candidateIndex=%s hit=%s",
		reasonCode,
		carryId,
		objectName,
		tostring(getPivot(object).Position),
		tostring(ground),
		tostring(candidate),
		tostring(candidateIndex or ""),
		tostring(result and result.Instance and result.Instance:GetFullName() or "")
	)
	return "settled"
end

return WorldDropPhysics
