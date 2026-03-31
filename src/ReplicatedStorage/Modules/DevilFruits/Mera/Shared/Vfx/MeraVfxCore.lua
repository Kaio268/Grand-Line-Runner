local MeraVfxCore = {}

function MeraVfxCore.Create(deps)
	local Config = deps.Config
	local DiagnosticLogLimiter = deps.DiagnosticLogLimiter
	local ReplicatedStorage = deps.ReplicatedStorage
	local RunService = deps.RunService
	local Workspace = deps.Workspace

	local infoEnabled = RunService:IsStudio() and Config.Debug.EnableInfoLogsInStudio ~= false
	local debugEnabled = RunService:IsStudio() and Config.Debug.EnableVerboseDebugLogs == true
	local verifyEnabled = RunService:IsStudio() and Config.Debug.EnableClientVerificationLogs == true
	local infoCooldown = Config.Logging.InfoCooldown
	local warnCooldown = Config.Logging.WarnCooldown
	local rootSegments = Config.Shared.RootSegments
	local workspaceDebugSegments = Config.Shared.WorkspaceFlameDashDebugSegments
	local useWorkspaceFlameDashDebug = Config.Debug.UseWorkspaceFlameDashDebugSource == true
	local flameDashStartupCandidates = Config.FlameDash.StartupChildCandidates
	local flameDashHeadAssetCandidates = Config.FlameDash.HeadAssetCandidates

	local function logInfo(message, ...)
		if not infoEnabled then
			return
		end

		if not DiagnosticLogLimiter.ShouldEmit("MeraVfx:INFO", DiagnosticLogLimiter.BuildKey(message, ...), infoCooldown) then
			return
		end

		print(string.format("[MERA VFX] " .. message, ...))
	end

	local function logWarn(message, ...)
		if not DiagnosticLogLimiter.ShouldEmit("MeraVfx:WARN", DiagnosticLogLimiter.BuildKey(message, ...), warnCooldown) then
			return
		end

		warn(string.format("[MERA VFX][WARN] " .. message, ...))
	end

	local function logDebug(message, ...)
		if not debugEnabled then
			return
		end

		print(string.format("[MERA VFX][DEBUG] " .. message, ...))
	end

	local function logVerify(message, ...)
		if not verifyEnabled then
			return
		end

		if not DiagnosticLogLimiter.ShouldEmit("MeraVfx:VERIFY", DiagnosticLogLimiter.BuildKey(message, ...), infoCooldown) then
			return
		end

		print(string.format("[MERA VFX][VERIFY] " .. message, ...))
	end

	local function getPrimaryCandidateName(value)
		if type(value) == "table" then
			return value[1] or ""
		end

		return tostring(value or "")
	end

	local function buildPathLabel(effectName, childName)
		local segments = { "ReplicatedStorage" }
		for _, segment in ipairs(rootSegments) do
			segments[#segments + 1] = segment
		end

		local effectSegment = getPrimaryCandidateName(effectName)
		local childSegment = getPrimaryCandidateName(childName)
		if effectSegment ~= "" then
			segments[#segments + 1] = effectSegment
		end
		if childSegment ~= "" then
			segments[#segments + 1] = childSegment
		end

		return table.concat(segments, "/")
	end

	local function createSharedEmitMetrics()
		return {
			Activated = 0,
			ParticleEmitters = 0,
			EmittedParticles = 0,
			Beams = 0,
			Trails = 0,
			LegacyEffects = 0,
			Lights = 0,
			Sounds = 0,
			MeshEmitModels = 0,
		}
	end

	local function mergeSharedEmitMetrics(target, source)
		if type(target) ~= "table" or type(source) ~= "table" then
			return target
		end

		for key, value in pairs(source) do
			if type(value) == "number" then
				target[key] = (tonumber(target[key]) or 0) + value
			end
		end

		return target
	end

	local function getFlameDashRoleLogLabel(roleName)
		local normalizedRole = string.lower(tostring(roleName or ""))
		if normalizedRole == Config.FlameDash.HeadRole then
			return "dash"
		end
		if normalizedRole == Config.FlameDash.PartRole or normalizedRole == Config.FlameDash.TrailRole then
			return "part"
		end

		return normalizedRole ~= "" and normalizedRole or "unknown"
	end

	local function normalizeNameForLookup(value)
		return (string.lower(tostring(value or "")):gsub("[%s%p_]+", ""))
	end

	local function findFirstMatchingChild(parent, candidateNames)
		if typeof(parent) ~= "Instance" then
			return nil, nil
		end

		local candidates = type(candidateNames) == "table" and candidateNames or { candidateNames }
		for _, candidateName in ipairs(candidates) do
			if typeof(candidateName) == "string" and candidateName ~= "" then
				local child = parent:FindFirstChild(candidateName)
				if child then
					return child, candidateName
				end
			end
		end

		return nil, nil
	end

	local function findFirstNamedDescendant(root, targetName)
		if typeof(root) ~= "Instance" or typeof(targetName) ~= "string" or targetName == "" then
			return nil
		end

		local directChild = root:FindFirstChild(targetName)
		if directChild then
			return directChild
		end

		local normalizedTargetName = normalizeNameForLookup(targetName)
		for _, item in ipairs(root:GetDescendants()) do
			if normalizeNameForLookup(item.Name) == normalizedTargetName then
				return item
			end
		end

		return nil
	end

	local function candidateSetsOverlap(leftCandidates, rightCandidates)
		local leftList = type(leftCandidates) == "table" and leftCandidates or { leftCandidates }
		local rightList = type(rightCandidates) == "table" and rightCandidates or { rightCandidates }

		for _, leftCandidate in ipairs(leftList) do
			local normalizedLeft = normalizeNameForLookup(leftCandidate)
			if normalizedLeft ~= "" then
				for _, rightCandidate in ipairs(rightList) do
					if normalizedLeft == normalizeNameForLookup(rightCandidate) then
						return true
					end
				end
			end
		end

		return false
	end

	local function buildWorkspaceFlameDashDebugPath(childName)
		local segments = { "Workspace" }
		for _, segment in ipairs(workspaceDebugSegments) do
			segments[#segments + 1] = segment
		end

		local childSegment = getPrimaryCandidateName(childName)
		if childSegment ~= "" then
			segments[#segments + 1] = childSegment
		end

		return table.concat(segments, "/")
	end

	local function tryGetWorkspaceMeraFlameDashDebugSource(childCandidates)
		if not useWorkspaceFlameDashDebug then
			return nil, nil, nil
		end

		if not candidateSetsOverlap(childCandidates, flameDashStartupCandidates)
			and not candidateSetsOverlap(childCandidates, flameDashHeadAssetCandidates)
		then
			return nil, nil, nil
		end

		local requestedPath = buildWorkspaceFlameDashDebugPath(childCandidates)
		local current = Workspace
		for _, segment in ipairs(workspaceDebugSegments) do
			current = current:FindFirstChild(segment)
			if not current then
				return nil, requestedPath, nil
			end
		end

		local availableChildren = {}
		for _, child in ipairs(current:GetChildren()) do
			availableChildren[#availableChildren + 1] = child.Name
		end
		table.sort(availableChildren)
		local availableChildrenLabel = #availableChildren > 0 and table.concat(availableChildren, ",") or "<empty>"

		local source, selectedChildName = findFirstMatchingChild(current, childCandidates)
		if not source then
			return nil, requestedPath, availableChildrenLabel
		end

		return source, buildWorkspaceFlameDashDebugPath(selectedChildName), availableChildrenLabel
	end

	local function formatVector3(value)
		if typeof(value) ~= "Vector3" then
			return tostring(value)
		end

		return string.format("(%.2f, %.2f, %.2f)", value.X, value.Y, value.Z)
	end

	local function formatRotationDegrees(value)
		if typeof(value) ~= "CFrame" then
			return tostring(value)
		end

		local x, y, z = value:ToOrientation()
		return string.format("(%.1f, %.1f, %.1f)", math.deg(x), math.deg(y), math.deg(z))
	end

	return {
		LogInfo = logInfo,
		LogWarn = logWarn,
		LogDebug = logDebug,
		LogVerify = logVerify,
		GetPrimaryCandidateName = getPrimaryCandidateName,
		BuildPathLabel = buildPathLabel,
		CreateSharedEmitMetrics = createSharedEmitMetrics,
		MergeSharedEmitMetrics = mergeSharedEmitMetrics,
		GetFlameDashRoleLogLabel = getFlameDashRoleLogLabel,
		NormalizeNameForLookup = normalizeNameForLookup,
		FindFirstMatchingChild = findFirstMatchingChild,
		FindFirstNamedDescendant = findFirstNamedDescendant,
		CandidateSetsOverlap = candidateSetsOverlap,
		BuildWorkspaceFlameDashDebugPath = buildWorkspaceFlameDashDebugPath,
		TryGetWorkspaceMeraFlameDashDebugSource = tryGetWorkspaceMeraFlameDashDebugSource,
		FormatVector3 = formatVector3,
		FormatRotationDegrees = formatRotationDegrees,
	}
end

return MeraVfxCore
