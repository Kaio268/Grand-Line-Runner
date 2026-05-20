local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local UiFolder = ReplicatedStorage:WaitForChild("UI")

local React = require(Packages:WaitForChild("React"))
local ReactRoblox = require(Packages:WaitForChild("ReactRoblox"))
local WantedBoardApp = require(UiFolder:WaitForChild("WantedBoard"):WaitForChild("WantedBoardApp"))

local BOARD_MODEL_NAME = "Bounty Leaderboard_V3"
local POSTER_PLANE_NAME = "PosterGuiPlane"
local SURFACE_GUI_NAME = "SurfaceGui"
local HOST_NAME = "ReactWantedBoardHost"
local REMOTES_FOLDER_NAME = "Remotes"
local STATE_EVENT_NAME = "BountyLeaderboardState"
local SNAPSHOT_REQUEST_NAME = "BountyLeaderboardSnapshotRequest"
local DEFAULT_PIXELS_PER_STUD = 72
local FACE_NORMALS = {
	[Enum.NormalId.Front] = Vector3.new(0, 0, -1),
	[Enum.NormalId.Back] = Vector3.new(0, 0, 1),
	[Enum.NormalId.Right] = Vector3.new(1, 0, 0),
	[Enum.NormalId.Left] = Vector3.new(-1, 0, 0),
	[Enum.NormalId.Top] = Vector3.new(0, 1, 0),
	[Enum.NormalId.Bottom] = Vector3.new(0, -1, 0),
}

local destroyed = false
local currentEntries = {}
local root = nil
local surfaceGui = nil
local posterPlane = nil

local function getVisibleFace(part)
	local camera = Workspace.CurrentCamera
	if not camera or not part or not part:IsA("BasePart") then
		return Enum.NormalId.Front
	end

	local toCamera = (camera.CFrame.Position - part.Position).Unit
	local bestFace = Enum.NormalId.Front
	local bestDot = -math.huge

	for face, localNormal in pairs(FACE_NORMALS) do
		local worldNormal = part.CFrame:VectorToWorldSpace(localNormal)
		local dot = worldNormal:Dot(toCamera)
		if dot > bestDot then
			bestDot = dot
			bestFace = face
		end
	end

	return bestFace
end

local function configureSurface(gui, part)
	gui.Adornee = part
	gui.AlwaysOnTop = true
	gui.Brightness = 2
	gui.Face = getVisibleFace(part)
	gui.LightInfluence = 0
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = math.max(tonumber(gui.PixelsPerStud) or 0, DEFAULT_PIXELS_PER_STUD)
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Enabled = true
end

local function findSurfaceGui()
	local board = Workspace:WaitForChild(BOARD_MODEL_NAME, 30)
	if not board then
		warn("[BountyLeaderboard] Missing Workspace." .. BOARD_MODEL_NAME)
		return nil
	end

	local foundPosterPlane = board:WaitForChild(POSTER_PLANE_NAME, 30)
	if not foundPosterPlane then
		warn("[BountyLeaderboard] Missing " .. BOARD_MODEL_NAME .. "." .. POSTER_PLANE_NAME)
		return nil
	end

	if not foundPosterPlane:IsA("BasePart") then
		warn("[BountyLeaderboard] PosterGuiPlane must be a BasePart")
		return nil
	end

	posterPlane = foundPosterPlane
	local gui = foundPosterPlane:WaitForChild(SURFACE_GUI_NAME, 30)
	if not gui or not gui:IsA("SurfaceGui") then
		warn("[BountyLeaderboard] PosterGuiPlane.SurfaceGui is missing or not a SurfaceGui")
		return nil
	end

	return gui
end

local function render()
	if not root then
		return
	end

	root:render(React.createElement(WantedBoardApp, {
		entries = currentEntries,
	}))
end

local function mount()
	surfaceGui = findSurfaceGui()
	if not surfaceGui or destroyed then
		return
	end

	configureSurface(surfaceGui, posterPlane)

	local oldHost = surfaceGui:FindFirstChild(HOST_NAME)
	if oldHost then
		oldHost:Destroy()
	end

	root = ReactRoblox.createRoot(surfaceGui)
	render()
end

mount()

local remotesFolder = ReplicatedStorage:WaitForChild(REMOTES_FOLDER_NAME, 30)
local stateEvent = remotesFolder and remotesFolder:WaitForChild(STATE_EVENT_NAME, 30)
local snapshotRequest = remotesFolder and remotesFolder:WaitForChild(SNAPSHOT_REQUEST_NAME, 30)

if snapshotRequest and snapshotRequest:IsA("RemoteFunction") then
	task.spawn(function()
		local ok, snapshot = pcall(function()
			return snapshotRequest:InvokeServer()
		end)
		if ok and typeof(snapshot) == "table" and not destroyed then
			currentEntries = snapshot
			render()
		end
	end)
end

local stateConnection = nil
if stateEvent and stateEvent:IsA("RemoteEvent") then
	stateConnection = stateEvent.OnClientEvent:Connect(function(snapshot)
		if typeof(snapshot) ~= "table" then
			return
		end
		currentEntries = snapshot
		render()
	end)
end

script.Destroying:Connect(function()
	destroyed = true
	if stateConnection then
		stateConnection:Disconnect()
	end
	if root then
		root:unmount()
	end
	if surfaceGui then
		local host = surfaceGui:FindFirstChild(HOST_NAME)
		if host then
			host:Destroy()
		end
	end
end)
