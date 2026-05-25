local StartupState = {}

StartupState.Attributes = {
	LoadingScreenActive = "LoadingScreenActive",
	LoadingScreenComplete = "LoadingScreenComplete",
	LoadingStartedAt = "StartupLoadingStartedAt",
	ShellReady = "StartupShellReady",
	DataRequestSent = "StartupDataRequestSent",
	HudReady = "StartupHudReady",
	CharacterObserved = "StartupCharacterObserved",
	CriticalAssetsReady = "StartupCriticalAssetsReady",
	CriticalAssetsTimedOut = "StartupCriticalAssetsTimedOut",
	LoadingTimedOut = "StartupLoadingTimedOut",
	BackgroundPreloadComplete = "StartupBackgroundPreloadComplete",
}

function StartupState.SetPlayerGuiAttribute(player: Player, attributeName: string, value: any, timeoutSeconds: number?): boolean
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return false
	end

	local playerGui = player:FindFirstChildOfClass("PlayerGui")
	if not playerGui and timeoutSeconds and timeoutSeconds > 0 then
		playerGui = player:WaitForChild("PlayerGui", timeoutSeconds)
	end

	if not playerGui then
		return false
	end

	playerGui:SetAttribute(attributeName, value)
	return true
end

function StartupState.MarkDataRequestSent(player: Player): boolean
	return StartupState.SetPlayerGuiAttribute(player, StartupState.Attributes.DataRequestSent, true, 2)
end

function StartupState.MarkHudReady(player: Player): boolean
	return StartupState.SetPlayerGuiAttribute(player, StartupState.Attributes.HudReady, true, 2)
end

return table.freeze(StartupState)
