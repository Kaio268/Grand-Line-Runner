local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DevilFruits = ReplicatedStorage:WaitForChild("Modules"):WaitForChild("DevilFruits")
local AnimationLoadDiagnostics = require(DevilFruits:WaitForChild("AnimationLoadDiagnostics"))
local DiagnosticLogLimiter = require(DevilFruits:WaitForChild("DiagnosticLogLimiter"))

local CrewIdleAnimator = {}

local SOURCE_LABEL = "ReplicatedStorage.Modules.Crew.CrewIdleAnimator"
local INFO_COOLDOWN = 2
local WARN_COOLDOWN = 8
local DEBUG_COOLDOWN = 0.5
local DEFAULT_GENDER = "Male"
local DEFAULT_MIN_INTERVAL = 18
local DEFAULT_MAX_INTERVAL = 35
local DEFAULT_INITIAL_DELAY_MIN = 0.4
local DEFAULT_INITIAL_DELAY_MAX = 3.5
local DEFAULT_FADE_TIME = 0.35
local ACCESSORY_WELD_NAME = "CrewIdleAccessoryWeld"
local MAX_DEBUG_PART_NAMES = 8
local MAX_DEBUG_ACCESSORY_AUDIT_LINES = 8

local IDLE_SETS = {
	Male = {
		"rbxassetid://76663378713870",
		"rbxassetid://128935181904934",
	},
	Female = {
		"rbxassetid://124766120413950",
		"rbxassetid://116934561146050",
	},
}

local GENDER_ALIASES = {
	f = "Female",
	female = "Female",
	girl = "Female",
	m = "Male",
	male = "Male",
	man = "Male",
	woman = "Female",
}

local ACCESSORY_NAME_TOKENS = {
	"accessory",
	"bang",
	"beard",
	"cap",
	"crown",
	"face",
	"glasses",
	"goggle",
	"hair",
	"handle",
	"hat",
	"helmet",
	"horn",
	"mask",
	"moustache",
	"mustache",
	"prop",
	"wig",
}

local HEAD_ACCESSORY_NAME_TOKENS = {
	"bang",
	"beard",
	"cap",
	"crown",
	"face",
	"glasses",
	"goggle",
	"hair",
	"hat",
	"helmet",
	"horn",
	"mask",
	"moustache",
	"mustache",
	"wig",
}

local ACCESSORY_ATTACHMENT_NAMES = {
	FaceCenterAttachment = true,
	FaceFrontAttachment = true,
	HairAttachment = true,
	HatAttachment = true,
}

local activeByModel = setmetatable({}, { __mode = "k" })
local animationByAssetId = {}
local rng = Random.new()
local CrewCatalog

local function isDebugEnabled()
	return ReplicatedStorage:GetAttribute("CrewIdleAnimationDebug") == true
end

local function getCrewCatalog()
	if CrewCatalog == nil then
		CrewCatalog = require(script.Parent:WaitForChild("CrewCatalog"))
	end
	return CrewCatalog
end

local function logInfo(message, ...)
	if not isDebugEnabled() then
		return
	end

	if not DiagnosticLogLimiter.ShouldEmit("CrewIdleAnimator:INFO", DiagnosticLogLimiter.BuildKey(message, ...), INFO_COOLDOWN) then
		return
	end

	print(string.format("[CREW IDLE] " .. message, ...))
end

local function logWarn(message, ...)
	if not isDebugEnabled() then
		return
	end

	if not DiagnosticLogLimiter.ShouldEmit("CrewIdleAnimator:WARN", DiagnosticLogLimiter.BuildKey(message, ...), WARN_COOLDOWN) then
		return
	end

	warn(string.format("[CREW IDLE][WARN] " .. message, ...))
end

local function logDebug(message, ...)
	if not isDebugEnabled() then
		return
	end

	if not DiagnosticLogLimiter.ShouldEmit("CrewIdleAnimator:DEBUG", DiagnosticLogLimiter.BuildKey(message, ...), DEBUG_COOLDOWN) then
		return
	end

	print(string.format("[CREW IDLE][DEBUG] " .. message, ...))
end

local function normalizeGender(value)
	local raw = tostring(value or "")
	if raw == "Male" or raw == "Female" then
		return raw
	end

	local alias = GENDER_ALIASES[string.lower(raw)]
	return alias
end

local function normalizeAssetId(value)
	local text = tostring(value or "")
	if text == "" then
		return ""
	end
	if string.find(text, "rbxassetid://", 1, true) == 1 then
		return text
	end

	local numeric = tonumber(text)
	if numeric ~= nil and numeric > 0 then
		return "rbxassetid://" .. tostring(math.floor(numeric))
	end

	return text
end

local function getAnimation(assetId)
	local normalizedAssetId = normalizeAssetId(assetId)
	if normalizedAssetId == "" then
		return nil
	end

	local animation = animationByAssetId[normalizedAssetId]
	if animation then
		return animation
	end

	animation = Instance.new("Animation")
	animation.Name = "CrewIdleAnimation"
	animation.AnimationId = normalizedAssetId
	animationByAssetId[normalizedAssetId] = animation
	return animation
end

local function getController(model)
	if typeof(model) ~= "Instance" then
		return nil
	end

	local humanoid = model:FindFirstChildOfClass("Humanoid") or model:FindFirstChildWhichIsA("Humanoid", true)
	if humanoid then
		return humanoid
	end

	local controller = model:FindFirstChildOfClass("AnimationController")
		or model:FindFirstChildWhichIsA("AnimationController", true)
	if controller then
		return controller
	end

	controller = Instance.new("AnimationController")
	controller.Name = "CrewIdleAnimationController"
	controller.Parent = model
	return controller
end

local function getAnimator(controller)
	if typeof(controller) ~= "Instance" then
		return nil
	end

	local animator = controller:FindFirstChildOfClass("Animator") or controller:FindFirstChild("Animator")
	if animator and animator:IsA("Animator") then
		return animator
	end

	animator = Instance.new("Animator")
	animator.Parent = controller
	return animator
end

local function getPartLabel(part)
	if typeof(part) ~= "Instance" or not part:IsA("BasePart") then
		return "<none>"
	end

	return part:GetFullName()
end

local function getHumanoidRigType(controller)
	if typeof(controller) ~= "Instance" or not controller:IsA("Humanoid") then
		return "None"
	end

	local ok, rigType = pcall(function()
		return controller.RigType
	end)
	if ok and typeof(rigType) == "EnumItem" then
		return rigType.Name
	end

	return "Unknown"
end

local function addPartEdge(adjacency, partA, partB)
	if not (partA and partA:IsA("BasePart") and partB and partB:IsA("BasePart")) then
		return
	end

	adjacency[partA] = adjacency[partA] or {}
	adjacency[partB] = adjacency[partB] or {}
	table.insert(adjacency[partA], partB)
	table.insert(adjacency[partB], partA)
end

local function addJointReference(diagnostics, joint, partA, partB)
	if not (
		typeof(diagnostics) == "table"
		and typeof(joint) == "Instance"
		and partA
		and partA:IsA("BasePart")
		and partB
		and partB:IsA("BasePart")
	) then
		return
	end

	diagnostics.JointsByPart[partA] = diagnostics.JointsByPart[partA] or {}
	diagnostics.JointsByPart[partB] = diagnostics.JointsByPart[partB] or {}
	table.insert(diagnostics.JointsByPart[partA], {
		Joint = joint,
		OtherPart = partB,
	})
	table.insert(diagnostics.JointsByPart[partB], {
		Joint = joint,
		OtherPart = partA,
	})
end

local function hasAncestorOfClass(instance, className, stopAncestor)
	local current = instance.Parent
	while current and current ~= stopAncestor do
		if current:IsA(className) then
			return true
		end
		current = current.Parent
	end

	return false
end

local function hasNameToken(instance, tokens, stopAncestor)
	local current = instance
	while current and current ~= stopAncestor do
		local name = string.lower(tostring(current.Name or ""))
		for _, token in ipairs(tokens) do
			if string.find(name, token, 1, true) then
				return true
			end
		end
		current = current.Parent
	end

	return false
end

local function hasAccessoryNameHint(part, model)
	return hasNameToken(part, ACCESSORY_NAME_TOKENS, model)
end

local function hasHeadAccessoryNameHint(part, model)
	return hasNameToken(part, HEAD_ACCESSORY_NAME_TOKENS, model)
end

local function isHeadPart(part)
	return typeof(part) == "Instance"
		and part:IsA("BasePart")
		and string.find(string.lower(tostring(part.Name or "")), "head", 1, true) ~= nil
end

local function isRootPart(part, diagnostics)
	return typeof(part) == "Instance" and part:IsA("BasePart") and part == diagnostics.RootPart
end

local function isTorsoPart(part)
	if typeof(part) ~= "Instance" or not part:IsA("BasePart") then
		return false
	end

	local name = string.lower(tostring(part.Name or ""))
	return string.find(name, "torso", 1, true) ~= nil
end

local function getBodyRegion(part, diagnostics)
	if typeof(part) ~= "Instance" or not part:IsA("BasePart") then
		return "none"
	end
	if isHeadPart(part) then
		return "head"
	end
	if isRootPart(part, diagnostics) then
		return "root"
	end
	if isTorsoPart(part) then
		return "torso"
	end
	if diagnostics.MotorRigParts[part] then
		return "body"
	end

	return "decor"
end

local function isBetterBodyAttachment(candidate, existing)
	if not existing then
		return true
	end

	return isHeadPart(candidate.Part) and not isHeadPart(existing.Part)
end

local function buildBodyAttachmentMap(motorRigParts)
	local attachmentByName = {}
	for part in pairs(motorRigParts) do
		for _, child in ipairs(part:GetDescendants()) do
			if child:IsA("Attachment") then
				local attachmentName = tostring(child.Name or "")
				if attachmentName ~= "" then
					local entry = {
						Attachment = child,
						Part = part,
					}
					if isBetterBodyAttachment(entry, attachmentByName[attachmentName]) then
						attachmentByName[attachmentName] = entry
					end
				end
			end
		end
	end

	return attachmentByName
end

local function findHeadPart(motorRigParts)
	for part in pairs(motorRigParts) do
		if tostring(part.Name or "") == "Head" then
			return part
		end
	end
	for part in pairs(motorRigParts) do
		if isHeadPart(part) then
			return part
		end
	end

	return nil
end

local function findMatchingBodyAttachment(part, bodyAttachmentByName)
	for _, child in ipairs(part:GetDescendants()) do
		if child:IsA("Attachment") then
			local attachmentName = tostring(child.Name or "")
			local bodyEntry = bodyAttachmentByName[attachmentName]
			if bodyEntry and bodyEntry.Part and bodyEntry.Part ~= part then
				return bodyEntry.Part, bodyEntry.Attachment, child
			end
		end
	end

	return nil, nil, nil
end

local function hasAccessoryAttachment(part)
	for _, child in ipairs(part:GetDescendants()) do
		if child:IsA("Attachment") and ACCESSORY_ATTACHMENT_NAMES[tostring(child.Name or "")] == true then
			return true
		end
	end

	return false
end

local function findRootPart(model)
	local rootPart = model:FindFirstChild("HumanoidRootPart", true)
	if rootPart and rootPart:IsA("BasePart") then
		return rootPart
	end

	if model.PrimaryPart and model.PrimaryPart:IsA("BasePart") then
		return model.PrimaryPart
	end

	return model:FindFirstChildWhichIsA("BasePart", true)
end

local function collectRigDiagnostics(model, controller)
	local diagnostics = {
		Adjacency = {},
		AnchoredPartCount = 0,
		BasePartCount = 0,
		ConnectedPartCount = 0,
		ControllerType = if typeof(controller) == "Instance" then controller.ClassName else "None",
		HumanoidRigType = getHumanoidRigType(controller),
		Motor6DCount = 0,
		MotorRigParts = {},
		RootPart = findRootPart(model),
		ScriptCount = 0,
		JointsByPart = {},
		AccessoryCandidateCount = 0,
		AccessoryConnectedCount = 0,
		AccessorySkippedCount = 0,
		AccessorySkippedParts = {},
		AccessoryAuditLines = {},
		AccessoryRetargetedCount = 0,
		AccessoryWrongTargetCount = 0,
		AccessoryWeldedCount = 0,
	}

	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") then
			diagnostics.BasePartCount += 1
			if descendant.Anchored then
				diagnostics.AnchoredPartCount += 1
			end
		elseif descendant:IsA("BaseScript") then
			diagnostics.ScriptCount += 1
		elseif descendant:IsA("Motor6D") then
			diagnostics.Motor6DCount += 1
			local part0 = descendant.Part0
			local part1 = descendant.Part1
			if part0 and part0:IsA("BasePart") then
				diagnostics.MotorRigParts[part0] = true
			end
			if part1 and part1:IsA("BasePart") then
				diagnostics.MotorRigParts[part1] = true
			end
			addPartEdge(diagnostics.Adjacency, part0, part1)
			addJointReference(diagnostics, descendant, part0, part1)
		elseif descendant:IsA("JointInstance") or descendant:IsA("WeldConstraint") then
			addPartEdge(diagnostics.Adjacency, descendant.Part0, descendant.Part1)
			addJointReference(diagnostics, descendant, descendant.Part0, descendant.Part1)
		end
	end

	return diagnostics
end

local function formatPartNames(parts)
	if #parts == 0 then
		return "<none>"
	end

	local names = {}
	for index, part in ipairs(parts) do
		if index > MAX_DEBUG_PART_NAMES then
			names[#names + 1] = string.format("...%d more", #parts - MAX_DEBUG_PART_NAMES)
			break
		end
		names[#names + 1] = getPartLabel(part)
	end
	return table.concat(names, " | ")
end

local function chooseAnimationRoot(diagnostics)
	local rootPart = diagnostics.RootPart
	if rootPart and diagnostics.MotorRigParts[rootPart] then
		return rootPart
	end

	for part in pairs(diagnostics.MotorRigParts) do
		return part
	end

	return rootPart
end

local function collectConnectedAnimatedParts(diagnostics)
	local connectedParts = {}
	local queue = {}

	local function enqueue(part)
		if part and part:IsA("BasePart") and not connectedParts[part] then
			connectedParts[part] = true
			table.insert(queue, part)
		end
	end

	for part in pairs(diagnostics.MotorRigParts) do
		enqueue(part)
	end

	local cursor = 1
	while cursor <= #queue do
		local part = queue[cursor]
		cursor += 1
		for _, neighbor in ipairs(diagnostics.Adjacency[part] or {}) do
			enqueue(neighbor)
		end
	end

	local count = 0
	for _ in pairs(connectedParts) do
		count += 1
	end
	diagnostics.ConnectedPartCount = count

	return connectedParts
end

local function collectAccessoryCandidates(model, diagnostics, bodyAttachmentByName)
	local candidates = {}
	local headPart = findHeadPart(diagnostics.MotorRigParts)
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") and descendant ~= diagnostics.RootPart and not diagnostics.MotorRigParts[descendant] then
			local matchPart, bodyAttachment, accessoryAttachment = findMatchingBodyAttachment(descendant, bodyAttachmentByName)
			local reason = nil
			if hasAncestorOfClass(descendant, "Accessory", model) then
				reason = "accessory_instance"
			elseif hasAccessoryNameHint(descendant, model) then
				reason = "name_hint"
			elseif matchPart then
				reason = "attachment_match"
			end

			if not matchPart and headPart and (hasHeadAccessoryNameHint(descendant, model) or hasAccessoryAttachment(descendant)) then
				matchPart = headPart
				reason = reason or "head_accessory_hint"
			end

			if reason then
				candidates[descendant] = {
					AccessoryAttachment = accessoryAttachment,
					BodyAttachment = bodyAttachment,
					MatchPart = matchPart,
					Reason = reason,
					Status = "pending",
				}
			end
		end
	end

	return candidates
end

local function countDictionaryValues(dictionary)
	local count = 0
	for _ in pairs(dictionary) do
		count += 1
	end
	return count
end

local function findExistingCrewIdleAccessoryWeld(part, targetPart)
	for _, child in ipairs(part:GetChildren()) do
		if child.Name == ACCESSORY_WELD_NAME and child:IsA("JointInstance") then
			local part0 = child.Part0
			local part1 = child.Part1
			if (part0 == targetPart and part1 == part) or (part0 == part and part1 == targetPart) then
				return child
			end
		end
	end

	return nil
end

local function pruneMissingJointReferences(diagnostics, part)
	local refs = diagnostics.JointsByPart[part]
	if not refs then
		return
	end

	local cursor = #refs
	while cursor >= 1 do
		local ref = refs[cursor]
		if typeof(ref.Joint) ~= "Instance" or ref.Joint.Parent == nil then
			table.remove(refs, cursor)
		end
		cursor -= 1
	end
end

local function isDirectlyJoinedToTarget(diagnostics, part, targetPart)
	pruneMissingJointReferences(diagnostics, part)
	for _, ref in ipairs(diagnostics.JointsByPart[part] or {}) do
		if ref.OtherPart == targetPart then
			return true
		end
	end

	return false
end

local function isSafeAccessoryJoint(joint, part, model)
	if typeof(joint) ~= "Instance" then
		return false
	end
	if joint.Name == ACCESSORY_WELD_NAME or joint.Name == "AccessoryWeld" then
		return true
	end
	if hasAncestorOfClass(joint, "Accessory", model) then
		return true
	end
	if hasAccessoryNameHint(joint, model) then
		return true
	end
	if hasAccessoryNameHint(part, model) and joint.Parent == part then
		return true
	end

	return false
end

local function collectWrongTargetAccessoryJoints(model, diagnostics, part, targetPart)
	local safeJoints = {}
	local unsafeJoints = {}
	pruneMissingJointReferences(diagnostics, part)
	for _, ref in ipairs(diagnostics.JointsByPart[part] or {}) do
		if ref.OtherPart ~= targetPart then
			local targetRegion = getBodyRegion(ref.OtherPart, diagnostics)
			local repairableTarget = targetRegion == "root" or targetRegion == "torso" or targetRegion == "body"
			if isSafeAccessoryJoint(ref.Joint, part, model) and repairableTarget then
				safeJoints[#safeJoints + 1] = ref.Joint
			else
				unsafeJoints[#unsafeJoints + 1] = ref.Joint
			end
		end
	end

	return safeJoints, unsafeJoints
end

local function clearInvalidCrewIdleAccessoryWelds(part, targetPart)
	for _, child in ipairs(part:GetChildren()) do
		if child.Name == ACCESSORY_WELD_NAME and child:IsA("JointInstance") then
			local part0 = child.Part0
			local part1 = child.Part1
			local valid = (part0 == targetPart and part1 == part) or (part0 == part and part1 == targetPart)
			if not valid then
				child:Destroy()
			end
		end
	end
end

local function createAccessoryWeld(part, targetPart)
	if not (part and targetPart and part:IsA("BasePart") and targetPart:IsA("BasePart")) then
		return false, nil
	end

	clearInvalidCrewIdleAccessoryWelds(part, targetPart)
	local existing = findExistingCrewIdleAccessoryWeld(part, targetPart)
	if existing then
		return true, existing
	end

	local weld = Instance.new("Weld")
	weld.Name = ACCESSORY_WELD_NAME
	weld.Part0 = targetPart
	weld.Part1 = part
	weld.C0 = targetPart.CFrame:ToObjectSpace(part.CFrame)
	weld.C1 = CFrame.new()
	weld.Parent = part
	return true, weld
end

local function formatAttachmentNames(part)
	local names = {}
	for _, descendant in ipairs(part:GetDescendants()) do
		if descendant:IsA("Attachment") then
			names[#names + 1] = tostring(descendant.Name or "")
		end
	end
	table.sort(names)

	if #names == 0 then
		return "-"
	end
	if #names > 4 then
		names[5] = string.format("+%d", #names - 4)
		while #names > 5 do
			table.remove(names)
		end
	end

	return table.concat(names, ",")
end

local function formatJointTargets(diagnostics, part)
	local parts = {}
	pruneMissingJointReferences(diagnostics, part)
	for _, ref in ipairs(diagnostics.JointsByPart[part] or {}) do
		if #parts >= 4 then
			parts[#parts + 1] = "..."
			break
		end
		local joint = ref.Joint
		local target = ref.OtherPart
		parts[#parts + 1] = string.format(
			"%s:%s(%s)",
			tostring(joint and joint.Name or "?"),
			tostring(target and target.Name or "?"),
			getBodyRegion(target, diagnostics)
		)
	end

	if #parts == 0 then
		return "-"
	end

	return table.concat(parts, ",")
end

local function getParentLabel(instance)
	local parent = instance and instance.Parent
	if not parent then
		return "<none>"
	end

	return parent:GetFullName()
end

local function buildAccessoryAuditLine(part, candidate, diagnostics, connectedParts)
	return string.format(
		"%s class=%s parent=%s anchored=%s reason=%s status=%s target=%s(%s) connected=%s attachments=%s joints=%s",
		getPartLabel(part),
		tostring(part.ClassName),
		getParentLabel(part),
		tostring(part.Anchored),
		tostring(candidate.Reason or "-"),
		tostring(candidate.Status or "-"),
		getPartLabel(candidate.MatchPart),
		getBodyRegion(candidate.MatchPart, diagnostics),
		tostring(connectedParts[part] == true),
		formatAttachmentNames(part),
		formatJointTargets(diagnostics, part)
	)
end

local function extendConnectedPartsWithAccessories(model, diagnostics, connectedParts)
	local bodyAttachmentByName = buildBodyAttachmentMap(diagnostics.MotorRigParts)
	local candidates = collectAccessoryCandidates(model, diagnostics, bodyAttachmentByName)
	local weldedCount = 0
	local retargetedCount = 0
	local wrongTargetCount = 0

	for part, candidate in pairs(candidates) do
		local targetPart = candidate.MatchPart
		if targetPart and connectedParts[targetPart] then
			if connectedParts[part] then
				if isDirectlyJoinedToTarget(diagnostics, part, targetPart) then
					candidate.Status = "connected"
				else
					local safeJoints, unsafeJoints = collectWrongTargetAccessoryJoints(model, diagnostics, part, targetPart)
					if #safeJoints > 0 then
						for _, joint in ipairs(safeJoints) do
							joint:Destroy()
						end
						local welded, weld = createAccessoryWeld(part, targetPart)
						if welded then
							addPartEdge(diagnostics.Adjacency, targetPart, part)
							addJointReference(diagnostics, weld, targetPart, part)
							retargetedCount += 1
							candidate.Status = "retargeted"
						else
							candidate.Status = "repair_failed"
						end
					elseif #unsafeJoints > 0 then
						wrongTargetCount += 1
						candidate.Status = "wrong_target_unsafe"
					else
						candidate.Status = "connected_indirect"
					end
				end
			else
				local welded, weld = createAccessoryWeld(part, targetPart)
				if welded then
					addPartEdge(diagnostics.Adjacency, targetPart, part)
					addJointReference(diagnostics, weld, targetPart, part)
					weldedCount += 1
					candidate.Status = "welded"
				else
					candidate.Status = "weld_failed"
				end
			end
		elseif targetPart then
			candidate.Status = "target_not_animated"
		else
			candidate.Status = "missing_target"
		end
	end

	if weldedCount > 0 or retargetedCount > 0 then
		connectedParts = collectConnectedAnimatedParts(diagnostics)
	end

	local connectedCandidateCount = 0
	local skippedParts = {}
	for part, candidate in pairs(candidates) do
		if connectedParts[part] then
			connectedCandidateCount += 1
		else
			if candidate.Status == "pending" then
				candidate.Status = "skipped"
			end
			skippedParts[#skippedParts + 1] = part
		end
	end
	table.sort(skippedParts, function(a, b)
		return getPartLabel(a) < getPartLabel(b)
	end)

	diagnostics.AccessoryCandidateCount = countDictionaryValues(candidates)
	diagnostics.AccessoryConnectedCount = connectedCandidateCount
	diagnostics.AccessorySkippedCount = #skippedParts
	diagnostics.AccessorySkippedParts = skippedParts
	diagnostics.AccessoryRetargetedCount = retargetedCount
	diagnostics.AccessoryWrongTargetCount = wrongTargetCount
	diagnostics.AccessoryWeldedCount = weldedCount
	for part, candidate in pairs(candidates) do
		diagnostics.AccessoryAuditLines[#diagnostics.AccessoryAuditLines + 1] =
			buildAccessoryAuditLine(part, candidate, diagnostics, connectedParts)
	end
	table.sort(diagnostics.AccessoryAuditLines)

	return connectedParts
end

local function setAnimatedPartPhysics(part, anchored)
	part.Anchored = anchored
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.Massless = true
	part.AssemblyLinearVelocity = Vector3.zero
	part.AssemblyAngularVelocity = Vector3.zero
end

local function prepareRigForAnimation(model, controller, source)
	local diagnostics = collectRigDiagnostics(model, controller)
	local connectedParts = nil
	if diagnostics.Motor6DCount > 0 then
		connectedParts = collectConnectedAnimatedParts(diagnostics)
		connectedParts = extendConnectedPartsWithAccessories(model, diagnostics, connectedParts)
	end

	logDebug(
		"rig source=%s model=%s controller=%s rigType=%s baseParts=%d anchoredParts=%d motor6D=%d connectedParts=%d root=%s scripts=%d accessoryCandidates=%d accessoryConnected=%d accessoryWelded=%d accessoryRetargeted=%d accessoryWrongTarget=%d accessorySkipped=%d",
		tostring(source),
		model:GetFullName(),
		tostring(diagnostics.ControllerType),
		tostring(diagnostics.HumanoidRigType),
		diagnostics.BasePartCount,
		diagnostics.AnchoredPartCount,
		diagnostics.Motor6DCount,
		diagnostics.ConnectedPartCount,
		getPartLabel(diagnostics.RootPart),
		diagnostics.ScriptCount,
		diagnostics.AccessoryCandidateCount,
		diagnostics.AccessoryConnectedCount,
		diagnostics.AccessoryWeldedCount,
		diagnostics.AccessoryRetargetedCount,
		diagnostics.AccessoryWrongTargetCount,
		diagnostics.AccessorySkippedCount
	)
	for index, line in ipairs(diagnostics.AccessoryAuditLines) do
		if index > MAX_DEBUG_ACCESSORY_AUDIT_LINES then
			logDebug(
				"rig accessory audit source=%s model=%s parts=...%d more",
				tostring(source),
				model:GetFullName(),
				#diagnostics.AccessoryAuditLines - MAX_DEBUG_ACCESSORY_AUDIT_LINES
			)
			break
		end
		logDebug("rig accessory audit source=%s model=%s part=%s", tostring(source), model:GetFullName(), line)
	end
	if diagnostics.AccessorySkippedCount > 0 then
		logDebug(
			"rig accessories skipped source=%s model=%s parts=%s",
			tostring(source),
			model:GetFullName(),
			formatPartNames(diagnostics.AccessorySkippedParts)
		)
	end

	if diagnostics.Motor6DCount <= 0 then
		logDebug("rig static source=%s model=%s detail=no_motor6d_no_unanchor", tostring(source), model:GetFullName())
		return diagnostics
	end

	local animationRoot = chooseAnimationRoot(diagnostics)
	local unanchoredCount = 0
	local anchoredCount = 0

	for part in pairs(connectedParts) do
		local anchored = part == animationRoot
		setAnimatedPartPhysics(part, anchored)
		if anchored then
			anchoredCount += 1
		else
			unanchoredCount += 1
		end
	end

	if diagnostics.RootPart and not connectedParts[diagnostics.RootPart] then
		setAnimatedPartPhysics(diagnostics.RootPart, true)
		anchoredCount += 1
	end

	logDebug(
		"rig prepared source=%s model=%s animationRoot=%s unanchored=%d anchored=%d connectedParts=%d",
		tostring(source),
		model:GetFullName(),
		getPartLabel(animationRoot),
		unanchoredCount,
		anchoredCount,
		diagnostics.ConnectedPartCount
	)

	return diagnostics
end

local function resolveAnimationPriority(options)
	if typeof(options.Priority) == "EnumItem" and options.Priority.EnumType == Enum.AnimationPriority then
		return options.Priority
	end

	if isDebugEnabled() then
		local priorityName = tostring(options.DebugPriority or ReplicatedStorage:GetAttribute("CrewIdleAnimationDebugPriority") or "")
		for _, priority in ipairs(Enum.AnimationPriority:GetEnumItems()) do
			if priority.Name == priorityName then
				return priority
			end
		end

		if options.DebugForceAction == true or ReplicatedStorage:GetAttribute("CrewIdleAnimationForceAction") == true then
			return Enum.AnimationPriority.Action
		end
	end

	return Enum.AnimationPriority.Idle
end

local function randomBetween(minValue, maxValue)
	local minNumber = tonumber(minValue) or 0
	local maxNumber = tonumber(maxValue) or minNumber
	if maxNumber < minNumber then
		maxNumber = minNumber
	end
	if maxNumber == minNumber then
		return minNumber
	end
	return rng:NextNumber(minNumber, maxNumber)
end

local function isActive(controller)
	return typeof(controller) == "table"
		and controller.Running == true
		and typeof(controller.Model) == "Instance"
		and controller.Model.Parent ~= nil
		and activeByModel[controller.Model] == controller
end

local function stopTrack(track, fadeTime)
	if typeof(track) ~= "Instance" or not track:IsA("AnimationTrack") then
		return
	end

	pcall(function()
		track:Stop(math.max(0, tonumber(fadeTime) or 0))
	end)
end

local function getTrackNumberProperty(track, propertyName)
	local ok, value = pcall(function()
		return track[propertyName]
	end)
	if ok then
		return tonumber(value) or 0
	end

	return 0
end

local function getTrackBoolProperty(track, propertyName)
	local ok, value = pcall(function()
		return track[propertyName]
	end)
	return ok and value == true
end

local function getTrackPriorityName(track)
	local ok, priority = pcall(function()
		return track.Priority
	end)
	if ok and typeof(priority) == "EnumItem" then
		return priority.Name
	end

	return "Unknown"
end

local function logTrackPlayback(controller, track, phase)
	if not isDebugEnabled() or typeof(track) ~= "Instance" then
		return
	end

	local animationId = AnimationLoadDiagnostics.GetTrackAnimationId(track) or "<unknown>"
	logDebug(
		"track %s source=%s model=%s asset=%s playing=%s length=%.3f priority=%s weight=%.3f",
		tostring(phase),
		tostring(controller.Source),
		controller.Model:GetFullName(),
		tostring(animationId),
		tostring(getTrackBoolProperty(track, "IsPlaying")),
		getTrackNumberProperty(track, "Length"),
		getTrackPriorityName(track),
		getTrackNumberProperty(track, "WeightCurrent")
	)
end

local function playTrack(controller, trackIndex, phase)
	if not isActive(controller) then
		return
	end

	local track = controller.Tracks[trackIndex]
	if not track then
		return
	end
	if controller.CurrentTrack == track and track.IsPlaying then
		return
	end

	local previousTrack = controller.CurrentTrack
	controller.CurrentTrack = track
	pcall(function()
		track:Play(controller.FadeTime, 1, 1)
	end)
	logTrackPlayback(controller, track, phase or "play")
	task.delay(0.12, function()
		if isActive(controller) and controller.CurrentTrack == track then
			logTrackPlayback(controller, track, (phase or "play") .. "_settled")
		end
	end)
	if previousTrack and previousTrack ~= track then
		stopTrack(previousTrack, controller.FadeTime)
	end
end

local function runIdleLoop(controller)
	if not isActive(controller) then
		return
	end

	local trackCount = #controller.Tracks
	if trackCount <= 0 then
		return
	end

	local trackIndex = if trackCount > 1 then rng:NextInteger(1, trackCount) else 1
	playTrack(controller, trackIndex, "initial")
	if trackCount == 1 then
		while isActive(controller) do
			task.wait(controller.MaxInterval)
		end
		return
	end

	while isActive(controller) do
		task.wait(randomBetween(controller.MinInterval, controller.MaxInterval))
		if not isActive(controller) then
			return
		end
		trackIndex = (trackIndex % trackCount) + 1
		playTrack(controller, trackIndex, "alternate")
	end
end

function CrewIdleAnimator.GetIdleSet(gender)
	local normalizedGender = normalizeGender(gender) or DEFAULT_GENDER
	local source = IDLE_SETS[normalizedGender]
	if not source then
		return nil
	end

	return table.clone(source)
end

function CrewIdleAnimator.GetGenderForCrew(crewMemberIdOrInfo, metadata)
	metadata = if typeof(metadata) == "table" then metadata else {}
	local gender = normalizeGender(metadata.Gender or metadata.gender)
	if gender then
		return gender
	end

	local crewMemberId = ""
	local info = nil
	if typeof(crewMemberIdOrInfo) == "table" then
		info = crewMemberIdOrInfo
		gender = normalizeGender(info.Gender or info.gender)
		if gender then
			return gender
		end
		crewMemberId = tostring(info.CrewMemberId or info.Id or info.BaseId or info.ModelName or "")
	else
		crewMemberId = tostring(crewMemberIdOrInfo or "")
	end

	if crewMemberId == "" then
		crewMemberId = tostring(metadata.CrewMemberId or metadata.crewMemberId or metadata.ModelName or metadata.modelName or "")
	end
	if crewMemberId == "" then
		return nil
	end

	local catalog = getCrewCatalog()
	local resolvedInfo = nil
	local ok = pcall(function()
		local _, foundInfo = catalog.ResolveCanonicalCrewMemberId(crewMemberId)
		resolvedInfo = foundInfo
	end)
	if ok and typeof(resolvedInfo) == "table" then
		gender = normalizeGender(resolvedInfo.Gender or resolvedInfo.gender)
		if gender then
			return gender
		end
	end

	ok = pcall(function()
		resolvedInfo = catalog.FindInfoByName(crewMemberId)
	end)
	if ok and typeof(resolvedInfo) == "table" then
		gender = normalizeGender(resolvedInfo.Gender or resolvedInfo.gender)
		if gender then
			return gender
		end
	end

	return nil
end

function CrewIdleAnimator.Stop(modelOrController, fadeTime, reason)
	local controller = modelOrController
	if typeof(modelOrController) == "Instance" then
		controller = activeByModel[modelOrController]
	end
	if typeof(controller) ~= "table" then
		return
	end

	local stopReason = tostring(reason or "manual")
	logDebug(
		"stop source=%s model=%s reason=%s currentTrack=%s tracks=%d",
		tostring(controller.Source or SOURCE_LABEL),
		typeof(controller.Model) == "Instance" and controller.Model:GetFullName() or "<missing>",
		stopReason,
		tostring(controller.CurrentTrack ~= nil),
		#(controller.Tracks or {})
	)

	controller.Running = false
	local model = controller.Model
	if typeof(model) == "Instance" and activeByModel[model] == controller then
		activeByModel[model] = nil
	end

	if controller.AncestryConnection then
		controller.AncestryConnection:Disconnect()
		controller.AncestryConnection = nil
	end

	for _, track in ipairs(controller.Tracks or {}) do
		stopTrack(track, fadeTime or controller.FadeTime)
		pcall(function()
			track:Destroy()
		end)
	end
	table.clear(controller.Tracks or {})
	controller.CurrentTrack = nil
end

function CrewIdleAnimator.PrepareStatic(model)
	if typeof(model) ~= "Instance" or not model:IsA("Model") then
		return false, "invalid_model"
	end

	CrewIdleAnimator.Stop(model, 0, "static_lod")

	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("Animator") or descendant:IsA("AnimationController") then
			descendant:Destroy()
		elseif descendant:IsA("Humanoid") then
			descendant.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
			descendant.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
			descendant.NameDisplayDistance = 0
			descendant.HealthDisplayDistance = 0
			descendant.AutoRotate = false
			pcall(function()
				descendant.EvaluateStateMachine = false
			end)
			pcall(function()
				descendant.PlatformStand = true
			end)
		elseif descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = false
			descendant.CanTouch = false
			descendant.CanQuery = false
			descendant.AssemblyLinearVelocity = Vector3.zero
			descendant.AssemblyAngularVelocity = Vector3.zero
		end
	end

	return true, "ok"
end

function CrewIdleAnimator.Start(model, options)
	if typeof(model) ~= "Instance" or not model:IsA("Model") then
		return nil, "invalid_model"
	end
	options = if typeof(options) == "table" then options else {}

	CrewIdleAnimator.Stop(model, 0, "restart")

	local gender = normalizeGender(options.Gender or options.gender)
		or CrewIdleAnimator.GetGenderForCrew(options.CrewMemberId or options.Info or options.ModelName, options)
		or DEFAULT_GENDER
	local idleSet = CrewIdleAnimator.GetIdleSet(gender)
	if not idleSet or #idleSet == 0 then
		return nil, "missing_idle_set"
	end

	local controllerInstance = getController(model)
	local animator = getAnimator(controllerInstance)
	if not animator then
		logWarn("start failed source=%s model=%s detail=animator_missing", tostring(options.Source or "unknown"), model:GetFullName())
		return nil, "animator_missing"
	end

	local source = tostring(options.Source or SOURCE_LABEL)
	prepareRigForAnimation(model, controllerInstance, source)
	local priority = resolveAnimationPriority(options)
	local controller = {
		Model = model,
		Running = true,
		Gender = gender,
		Tracks = {},
		FadeTime = math.max(0, tonumber(options.FadeTime) or DEFAULT_FADE_TIME),
		MinInterval = math.max(1, tonumber(options.MinInterval) or DEFAULT_MIN_INTERVAL),
		MaxInterval = math.max(1, tonumber(options.MaxInterval) or DEFAULT_MAX_INTERVAL),
		InitialDelayMin = math.max(0, tonumber(options.InitialDelayMin) or DEFAULT_INITIAL_DELAY_MIN),
		InitialDelayMax = math.max(0, tonumber(options.InitialDelayMax) or DEFAULT_INITIAL_DELAY_MAX),
		Source = source,
	}
	activeByModel[model] = controller

	for _, animationId in ipairs(idleSet) do
		local animation = getAnimation(animationId)
		if animation then
			local track, failure = AnimationLoadDiagnostics.LoadTrack(animator, animation, controller.Source)
			if track then
				track.Priority = priority
				track.Looped = true
				table.insert(controller.Tracks, track)
			elseif failure ~= "permission_denied" then
				logWarn(
					"track load skipped source=%s model=%s gender=%s animationId=%s detail=%s",
					controller.Source,
					model:GetFullName(),
					gender,
					tostring(animationId),
					tostring(failure)
				)
			end
		end
	end

	if #controller.Tracks == 0 then
		CrewIdleAnimator.Stop(controller, 0, "no_tracks")
		return nil, "no_tracks"
	end

	controller.AncestryConnection = model.AncestryChanged:Connect(function()
		if model.Parent == nil or not model:IsDescendantOf(game) then
			CrewIdleAnimator.Stop(controller, nil, "model_removed")
		end
	end)

	task.spawn(runIdleLoop, controller)
	logInfo(
		"start source=%s model=%s gender=%s tracks=%d priority=%s",
		controller.Source,
		model:GetFullName(),
		gender,
		#controller.Tracks,
		priority.Name
	)
	return controller
end

return CrewIdleAnimator
