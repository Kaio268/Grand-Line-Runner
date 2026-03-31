local MeraVfxFacade = {}

local FLAME_BURST_METHODS = {
	"PlayFireBurstStartup",
	"PlayFlameBurst",
}

local FLAME_DASH_METHODS = {
	"PlayFlameDashStartup",
	"PlayFlameDashEffect",
	"PlayFlameDashBurst",
	"StartFlameDashHead",
	"StartFlameDashPart",
	"UpdateFlameDashHead",
	"UpdateFlameDashPart",
	"StopFlameDashHead",
	"StopFlameDashPart",
	"LogFlameDashCleanup",
	"StartFlameDashTrail",
	"UpdateFlameDashTrail",
	"StopFlameDashTrail",
}

function MeraVfxFacade.Create(deps)
	local flameBurstApi = deps.FlameBurstApi
	local flameDashApi = deps.FlameDashApi
	local logInfo = deps.LogInfo
	local logWarn = deps.LogWarn
	local logVerify = deps.LogVerify
	local stopEffectState = deps.StopEffectState
	local enableVerificationLogs = deps.EnableVerificationLogs == true

	local publicApi = {}

	local function logDelegatedApiReadiness(apiName, apiTable, methodNames)
		local missingMethods = {}
		for _, methodName in ipairs(methodNames) do
			if type(apiTable) ~= "table" or typeof(apiTable[methodName]) ~= "function" then
				missingMethods[#missingMethods + 1] = tostring(methodName)
			end
		end

		if #missingMethods > 0 then
			logWarn(
				"client facade api=%s missing methods=%s",
				tostring(apiName),
				table.concat(missingMethods, ",")
			)
			return
		end

		if enableVerificationLogs then
			logVerify(
				"client facade api=%s ready methods=%d",
				tostring(apiName),
				#methodNames
			)
		end
	end

	local function resolveDelegatedApiMethod(apiTable, methodName)
		local method = type(apiTable) == "table" and apiTable[methodName] or nil
		if typeof(method) ~= "function" then
			logWarn("client facade missing delegated method=%s", tostring(methodName))
			return nil
		end

		return method
	end

	local function callDelegatedApi(apiTable, methodName, ...)
		local method = resolveDelegatedApiMethod(apiTable, methodName)
		if not method then
			return nil
		end

		if enableVerificationLogs then
			logVerify("call method=%s", tostring(methodName))
		end

		local results = table.pack(pcall(method, ...))
		if results[1] ~= true then
			logWarn("client facade method=%s failed detail=%s", tostring(methodName), tostring(results[2]))
			return nil
		end

		if enableVerificationLogs then
			logVerify("return method=%s", tostring(methodName))
		end

		return table.unpack(results, 2, results.n)
	end

	logDelegatedApiReadiness("FlameBurst", flameBurstApi, FLAME_BURST_METHODS)
	logDelegatedApiReadiness("FlameDash", flameDashApi, FLAME_DASH_METHODS)

	publicApi._EmitFlameDashTrailStamp = flameDashApi.EmitFlameDashTrailStamp
	publicApi._CleanupTrailStampsImmediately = flameDashApi.CleanupTrailStampsImmediately
	publicApi._FadeTrailStamp = flameDashApi.FadeTrailStamp
	publicApi._BeginOrderedTrailFade = flameDashApi.BeginOrderedTrailFade
	publicApi._ResolveFlameDashStageCandidates = flameDashApi.ResolveFlameDashStageCandidates
	publicApi._StartAttachedFlameDashRole = flameDashApi.StartAttachedFlameDashRole

	function publicApi.LogRemovedPlaceholder(moveName)
		logInfo("removed placeholder VFX move=%s", tostring(moveName))
	end

	function publicApi.StopRuntimeState(state, options)
		return stopEffectState(state, options)
	end

	function publicApi.PlayFireBurstStartup(options)
		return callDelegatedApi(flameBurstApi, "PlayFireBurstStartup", options)
	end

	function publicApi.PlayFlameBurst(options)
		return callDelegatedApi(flameBurstApi, "PlayFlameBurst", options)
	end

	function publicApi.PlayFireBurst(options)
		return publicApi.PlayFlameBurst(options)
	end

	function publicApi.PlayFlameDashStartup(options)
		return callDelegatedApi(flameDashApi, "PlayFlameDashStartup", options)
	end

	function publicApi.PlayFlameDashEffect(options)
		return callDelegatedApi(flameDashApi, "PlayFlameDashEffect", options)
	end

	function publicApi.PlayFlameDashBurst(options)
		return callDelegatedApi(flameDashApi, "PlayFlameDashBurst", options)
	end

	function publicApi.StartFlameDashHead(options)
		return callDelegatedApi(flameDashApi, "StartFlameDashHead", options)
	end

	function publicApi.StartFlameDashPart(options)
		return callDelegatedApi(flameDashApi, "StartFlameDashPart", options)
	end

	function publicApi.UpdateFlameDashHead(state, options)
		return callDelegatedApi(flameDashApi, "UpdateFlameDashHead", state, options)
	end

	function publicApi.UpdateFlameDashPart(state, options)
		return callDelegatedApi(flameDashApi, "UpdateFlameDashPart", state, options)
	end

	function publicApi.StopFlameDashHead(state, options)
		return callDelegatedApi(flameDashApi, "StopFlameDashHead", state, options)
	end

	function publicApi.StopFlameDashPart(state, options)
		return callDelegatedApi(flameDashApi, "StopFlameDashPart", state, options)
	end

	function publicApi.LogFlameDashCleanup(options)
		return callDelegatedApi(flameDashApi, "LogFlameDashCleanup", options)
	end

	function publicApi.StartFlameDashTrail(options)
		return callDelegatedApi(flameDashApi, "StartFlameDashTrail", options)
	end

	function publicApi.UpdateFlameDashTrail(state, options)
		return callDelegatedApi(flameDashApi, "UpdateFlameDashTrail", state, options)
	end

	function publicApi.StopFlameDashTrail(state, options)
		return callDelegatedApi(flameDashApi, "StopFlameDashTrail", state, options)
	end

	return publicApi
end

return MeraVfxFacade
