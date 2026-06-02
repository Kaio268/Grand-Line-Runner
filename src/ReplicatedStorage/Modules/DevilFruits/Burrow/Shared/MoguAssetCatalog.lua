local MoguAssetCatalog = {}

MoguAssetCatalog.VfxEffectCandidates = {
	Entry = {
		"Dig",
		"Start up",
		"Startup",
		"Start",
		"Burrow Entry",
		"BurrowEntry",
		"Entry Burst",
		"Dig Down",
		"Entry",
	},
	Trail = {
		"Burrow Trail",
		"BurrowTrail",
		"Trail Pulse",
		"Underground Trail",
		"Underground",
		"Trail",
		"Pulse",
		"Travel",
	},
	Resolve = {
		"Jump",
		"End",
		"Resolve",
		"Burrow Resolve",
		"BurrowResolve",
		"Resolve Burst",
		"Burrow Exit",
		"Surface",
		"Exit",
	},
}

MoguAssetCatalog.VfxKeywords = {
	Entry = { "burrow", "entry", "start", "startup", "dig", "down", "burst" },
	Trail = { "burrow", "trail", "pulse", "underground", "travel", "move" },
	Resolve = { "burrow", "resolve", "exit", "surface", "jump", "up", "burst", "end", "finish" },
}

local function appendUnique(target, seen, value)
	if typeof(value) ~= "string" or value == "" or seen[value] then
		return
	end

	seen[value] = true
	target[#target + 1] = value
end

function MoguAssetCatalog.BuildCandidateList(primaryName, fallbackNames)
	local candidates = {}
	local seen = {}

	appendUnique(candidates, seen, primaryName)
	for _, fallbackName in ipairs(fallbackNames or {}) do
		appendUnique(candidates, seen, fallbackName)
	end

	return candidates
end

function MoguAssetCatalog.NormalizeToken(value)
	local normalized = string.lower(tostring(value or ""))
	normalized = normalized:gsub("[%s%p_]+", "")
	return normalized
end

function MoguAssetCatalog.GetVfxCandidates(stageKey, configuredAssetName)
	return MoguAssetCatalog.BuildCandidateList(
		configuredAssetName,
		MoguAssetCatalog.VfxEffectCandidates[stageKey] or {}
	)
end

function MoguAssetCatalog.GetVfxKeywords(stageKey)
	return MoguAssetCatalog.VfxKeywords[stageKey] or {}
end

function MoguAssetCatalog.CollectSearchTokens(root, maxDescendants)
	local tokens = {}
	local seen = {}

	local function appendToken(value)
		local normalized = MoguAssetCatalog.NormalizeToken(value)
		if normalized == "" or seen[normalized] then
			return
		end

		seen[normalized] = true
		tokens[#tokens + 1] = normalized
	end

	if typeof(root) ~= "Instance" then
		return tokens
	end

	local current = root
	local ancestorDepth = 0
	while current and ancestorDepth < 4 do
		appendToken(current.Name)
		current = current.Parent
		ancestorDepth += 1
	end

	local descendantLimit = math.max(0, math.floor(tonumber(maxDescendants) or 24))
	local descendantCount = 0
	for _, descendant in ipairs(root:GetDescendants()) do
		appendToken(descendant.Name)
		descendantCount += 1
		if descendantCount >= descendantLimit then
			break
		end
	end

	return tokens
end

function MoguAssetCatalog.ScoreTokens(tokens, candidateNames, keywords)
	local bestCandidateScore = 0

	for index, candidateName in ipairs(candidateNames or {}) do
		local normalizedCandidate = MoguAssetCatalog.NormalizeToken(candidateName)
		if normalizedCandidate == "" then
			continue
		end

		local candidateBaseScore = math.max(12, 96 - ((index - 1) * 9))
		for _, token in ipairs(tokens or {}) do
			if token == normalizedCandidate then
				bestCandidateScore = math.max(bestCandidateScore, candidateBaseScore + 48)
			elseif string.find(token, normalizedCandidate, 1, true) or string.find(normalizedCandidate, token, 1, true) then
				bestCandidateScore = math.max(bestCandidateScore, candidateBaseScore + 20)
			end
		end
	end

	local keywordScore = 0
	for _, keyword in ipairs(keywords or {}) do
		local normalizedKeyword = MoguAssetCatalog.NormalizeToken(keyword)
		if normalizedKeyword == "" then
			continue
		end

		for _, token in ipairs(tokens or {}) do
			if string.find(token, normalizedKeyword, 1, true) then
				keywordScore += 7
				break
			end
		end
	end

	return bestCandidateScore + math.min(keywordScore, 28)
end

return MoguAssetCatalog
