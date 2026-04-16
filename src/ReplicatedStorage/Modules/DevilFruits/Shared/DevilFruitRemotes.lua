local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local DevilFruitRemotes = {}

DevilFruitRemotes.RemotesFolderName = "Remotes"
DevilFruitRemotes.RequestRemoteName = "DevilFruitAbilityRequest"
DevilFruitRemotes.StateRemoteName = "DevilFruitAbilityState"
DevilFruitRemotes.EffectRemoteName = "DevilFruitAbilityEffect"
DevilFruitRemotes.RuntimeIdAttributeName = "DevilFruitRemoteRuntimeId"

local function safeGetDebugId(instance)
	if typeof(instance) ~= "Instance" then
		return "<invalid>"
	end

	local ok, debugId = pcall(function()
		return instance:GetDebugId()
	end)
	if ok and typeof(debugId) == "string" and debugId ~= "" then
		return debugId
	end

	return "<unavailable>"
end

local function ensureRuntimeId(instance)
	if typeof(instance) ~= "Instance" then
		return "<invalid>"
	end

	local existingRuntimeId = instance:GetAttribute(DevilFruitRemotes.RuntimeIdAttributeName)
	if typeof(existingRuntimeId) == "string" and existingRuntimeId ~= "" then
		return existingRuntimeId
	end

	if not RunService:IsServer() then
		return "<pending>"
	end

	local runtimeId = HttpService:GenerateGUID(false)
	instance:SetAttribute(DevilFruitRemotes.RuntimeIdAttributeName, runtimeId)
	return runtimeId
end

local function ensureFolder(parent, childName)
	local child = parent:FindFirstChild(childName)
	if child then
		if not child:IsA("Folder") then
			error(string.format(
				"[DevilFruitRemotes] Expected %s to be a Folder, got %s",
				child:GetFullName(),
				child.ClassName
			))
		end

		return child
	end

	if not RunService:IsServer() then
		child = parent:WaitForChild(childName, 15)
		if child and child:IsA("Folder") then
			return child
		end

		error(string.format("[DevilFruitRemotes] Timed out waiting for Folder %s.%s", parent:GetFullName(), childName))
	end

	child = Instance.new("Folder")
	child.Name = childName
	child.Parent = parent
	return child
end

local function ensureRemoteEvent(parent, childName)
	local child = parent:FindFirstChild(childName)
	if child then
		if not child:IsA("RemoteEvent") then
			error(string.format(
				"[DevilFruitRemotes] Expected %s to be a RemoteEvent, got %s",
				child:GetFullName(),
				child.ClassName
			))
		end

		ensureRuntimeId(child)
		return child
	end

	if not RunService:IsServer() then
		child = parent:WaitForChild(childName, 15)
		if child and child:IsA("RemoteEvent") then
			return child
		end

		error(string.format("[DevilFruitRemotes] Timed out waiting for RemoteEvent %s.%s", parent:GetFullName(), childName))
	end

	child = Instance.new("RemoteEvent")
	child.Name = childName
	child.Parent = parent
	ensureRuntimeId(child)
	return child
end

function DevilFruitRemotes.DescribeInstance(instance)
	if typeof(instance) ~= "Instance" then
		return {
			Name = tostring(instance),
			Path = tostring(instance),
			RuntimeId = "<invalid>",
			DebugId = "<invalid>",
			Object = tostring(instance),
		}
	end

	return {
		Name = instance.Name,
		Path = instance:GetFullName(),
		RuntimeId = ensureRuntimeId(instance),
		DebugId = safeGetDebugId(instance),
		Object = tostring(instance),
	}
end

function DevilFruitRemotes.GetBundle()
	local remotesFolder = ensureFolder(ReplicatedStorage, DevilFruitRemotes.RemotesFolderName)

	return {
		Folder = remotesFolder,
		Request = ensureRemoteEvent(remotesFolder, DevilFruitRemotes.RequestRemoteName),
		State = ensureRemoteEvent(remotesFolder, DevilFruitRemotes.StateRemoteName),
		Effect = ensureRemoteEvent(remotesFolder, DevilFruitRemotes.EffectRemoteName),
	}
end

return DevilFruitRemotes
