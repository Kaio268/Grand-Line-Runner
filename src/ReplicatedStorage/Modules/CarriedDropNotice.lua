local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local CarriedDropNotice = {}

CarriedDropNotice.RemoteName = "GrandLineRushCarryDropNotice"
CarriedDropNotice.RemotesFolderName = "Remotes"
CarriedDropNotice.Title = "Carried Reward"
CarriedDropNotice.Duration = 1.4

local REASON_MESSAGES = {
	PlayerDrop = "Dropped: selected by player",
	HitEffect = "Dropped carried items: hit by hazard",
	["HumanoidState:Ragdoll"] = "Dropped: ragdolled",
	["HumanoidState:Physics"] = "Dropped: physics state",
	HoroProjection = "Dropped carried items: Horo effect",
	PlayerDeath = "Dropped carried items: death",
	AFKTeleport = "Dropped carried items: AFK cleanup",
	ExtractionCleanup = "Dropped carried items: extraction cleanup",
	CrewTurnIn = "Dropped carried items: extraction cleanup",
	TutorialCleanup = "Dropped: tutorial cleanup",
	StaleCarryState = "Dropped: stale carry state",
	Unknown = "Dropped: unknown reason",
	PlayerRemoving = "Dropped: player leaving",
}

local function getOrCreateRemotesFolder()
	local remotes = ReplicatedStorage:FindFirstChild(CarriedDropNotice.RemotesFolderName)
	if remotes and remotes:IsA("Folder") then
		return remotes
	end

	if remotes then
		remotes:Destroy()
	end

	remotes = Instance.new("Folder")
	remotes.Name = CarriedDropNotice.RemotesFolderName
	remotes.Parent = ReplicatedStorage
	return remotes
end

local function getOrCreateRemote()
	local remotes = getOrCreateRemotesFolder()
	local remote = remotes:FindFirstChild(CarriedDropNotice.RemoteName)
	if remote and remote:IsA("RemoteEvent") then
		return remote
	end

	if remote then
		remote:Destroy()
	end

	remote = Instance.new("RemoteEvent")
	remote.Name = CarriedDropNotice.RemoteName
	remote.Parent = remotes
	return remote
end

function CarriedDropNotice.NormalizeReason(reasonCode)
	local normalized = tostring(reasonCode or "")
	if normalized == "" or REASON_MESSAGES[normalized] == nil then
		return "Unknown"
	end
	return normalized
end

function CarriedDropNotice.GetMessage(reasonCode)
	return REASON_MESSAGES[CarriedDropNotice.NormalizeReason(reasonCode)] or REASON_MESSAGES.Unknown
end

function CarriedDropNotice.BuildPayload(payload)
	payload = if typeof(payload) == "table" then payload else {}
	local reasonCode = CarriedDropNotice.NormalizeReason(payload.ReasonCode or payload.Reason)
	local count = tonumber(payload.Count) or 1
	count = math.max(1, math.floor(count))

	return {
		ReasonCode = reasonCode,
		Text = tostring(payload.Text or CarriedDropNotice.GetMessage(reasonCode)),
		Title = tostring(payload.Title or CarriedDropNotice.Title),
		Duration = tonumber(payload.Duration) or CarriedDropNotice.Duration,
		Count = count,
		SuppressToast = payload.SuppressToast == true or reasonCode == "PlayerRemoving",
		Source = payload.Source,
		Action = payload.Action,
		ItemType = payload.ItemType,
		DisplayName = payload.DisplayName,
		CarryId = payload.CarryId,
		SlotIndex = payload.SlotIndex,
		Context = payload.Context,
	}
end

function CarriedDropNotice.GetRemote(timeoutSeconds)
	local remotes = ReplicatedStorage:FindFirstChild(CarriedDropNotice.RemotesFolderName)
		or ReplicatedStorage:WaitForChild(CarriedDropNotice.RemotesFolderName, timeoutSeconds)
	if not remotes or not remotes:IsA("Folder") then
		return nil
	end

	local remote = remotes:FindFirstChild(CarriedDropNotice.RemoteName)
		or remotes:WaitForChild(CarriedDropNotice.RemoteName, timeoutSeconds)
	if remote and remote:IsA("RemoteEvent") then
		return remote
	end
	return nil
end

function CarriedDropNotice.EnsureRemote()
	if not RunService:IsServer() then
		return CarriedDropNotice.GetRemote(0)
	end

	return getOrCreateRemote()
end

function CarriedDropNotice.Notify(player, payload)
	local notice = CarriedDropNotice.BuildPayload(payload)
	local playerName = if player and player.Name then player.Name else "<nil>"
	if RunService:IsStudio() then
		print(string.format(
			"[CarriedDropNotice] player=%s reason=%s count=%d text=%s source=%s carryId=%s slot=%s",
			playerName,
			notice.ReasonCode,
			notice.Count,
			notice.Text,
			tostring(notice.Source or notice.Action or ""),
			tostring(notice.CarryId or ""),
			tostring(notice.SlotIndex or "")
		))
	end

	if notice.SuppressToast == true or not RunService:IsServer() then
		return notice
	end
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return notice
	end

	getOrCreateRemote():FireClient(player, notice)
	return notice
end

if RunService:IsServer() then
	CarriedDropNotice.EnsureRemote()
end

return CarriedDropNotice
