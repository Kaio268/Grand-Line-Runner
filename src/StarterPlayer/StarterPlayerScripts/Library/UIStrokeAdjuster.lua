--!strict

--[=[
	Explicit opt-in UIStroke scaling helper.

	ScreenGui roots can be registered to scale UIStroke thickness by viewport
	size. BillboardGui roots can be registered to scale UIStroke thickness by
	viewport size and distance from the camera. Nothing is auto-tagged on
	require.
]=]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local RuntimeScheduler = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("RuntimeScheduler"))

local STUDIO_VIEWPORT_SIZE = Vector2.new(1920, 1080)
local UPDATE_DELAY = 1
local DEFAULT_BILLBOARD_DISTANCE = 15
local ORIGINAL_THICKNESS_ATTRIBUTE = "OriginalThickness"
local BILLBOARD_SCHEDULER_TASK_ID = "UIStrokeAdjuster:BillboardDistance"

type ConnectionList = { RBXScriptConnection }

type RootRecord<T> = {
	Root: T,
	Strokes: { UIStroke },
	Connections: ConnectionList,
}

type RegistrationHandle = {
	Disconnect: (self: RegistrationHandle) -> (),
	IsConnected: (self: RegistrationHandle) -> boolean,
}

type UIStrokeAdjuster = {
	RegisterScreenGui: (self: UIStrokeAdjuster, screenGui: ScreenGui) -> RegistrationHandle?,
	UnregisterScreenGui: (self: UIStrokeAdjuster, screenGui: ScreenGui) -> (),
	RegisterBillboardGui: (self: UIStrokeAdjuster, billboardGui: BillboardGui) -> RegistrationHandle?,
	UnregisterBillboardGui: (self: UIStrokeAdjuster, billboardGui: BillboardGui) -> (),
	TagScreenGui: (self: UIStrokeAdjuster, screenGui: ScreenGui) -> RegistrationHandle?,
	TagBillboardGui: (self: UIStrokeAdjuster, billboardGui: BillboardGui) -> RegistrationHandle?,
}

local UIStrokeAdjuster = {} :: UIStrokeAdjuster

local screenRecords: { [ScreenGui]: RootRecord<ScreenGui> } = {}
local billboardRecords: { [BillboardGui]: RootRecord<BillboardGui> } = {}
local viewportConnection: RBXScriptConnection? = nil
local billboardSchedulerHandle: any = nil

local function getCamera(): Camera?
	return Workspace.CurrentCamera
end

local function getBox(vector: Vector2): number
	return math.min(vector.X, vector.Y)
end

local function getScreenRatio(): number
	local camera = getCamera()
	if not camera then
		return 1
	end

	return getBox(camera.ViewportSize) / getBox(STUDIO_VIEWPORT_SIZE)
end

local function disconnectAll(connections: ConnectionList)
	for _, connection in ipairs(connections) do
		connection:Disconnect()
	end
	table.clear(connections)
end

local function hasAnyScreenRecord(): boolean
	return next(screenRecords) ~= nil
end

local function hasAnyBillboardRecord(): boolean
	return next(billboardRecords) ~= nil
end

local function ensureOriginalThickness(uiStroke: UIStroke)
	if uiStroke:GetAttribute(ORIGINAL_THICKNESS_ATTRIBUTE) == nil then
		uiStroke:SetAttribute(ORIGINAL_THICKNESS_ATTRIBUTE, uiStroke.Thickness)
	end
end

local function appendStroke(record, uiStroke: UIStroke)
	ensureOriginalThickness(uiStroke)
	record.Strokes[#record.Strokes + 1] = uiStroke
end

local function collectStrokes(root: Instance, record)
	if root:IsA("UIStroke") then
		appendStroke(record, root)
	end

	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant:IsA("UIStroke") then
			appendStroke(record, descendant)
		end
	end
end

local function updateScreenRecord(record: RootRecord<ScreenGui>)
	local ratio = getScreenRatio()
	for index = #record.Strokes, 1, -1 do
		local uiStroke = record.Strokes[index]
		if not uiStroke:IsDescendantOf(record.Root) then
			table.remove(record.Strokes, index)
			continue
		end

		local originalThickness = tonumber(uiStroke:GetAttribute(ORIGINAL_THICKNESS_ATTRIBUTE))
		if originalThickness then
			uiStroke.Thickness = originalThickness * ratio
		end
	end
end

local function updateScreenRecords()
	for _, record in pairs(screenRecords) do
		if record.Root.Parent == nil then
			UIStrokeAdjuster:UnregisterScreenGui(record.Root)
		else
			updateScreenRecord(record)
		end
	end
end

local function ensureViewportConnection()
	if viewportConnection or not hasAnyScreenRecord() then
		return
	end

	local camera = getCamera()
	if camera then
		viewportConnection = camera:GetPropertyChangedSignal("ViewportSize"):Connect(updateScreenRecords)
	end
end

local function disconnectViewportIfIdle()
	if hasAnyScreenRecord() then
		return
	end

	if viewportConnection then
		viewportConnection:Disconnect()
		viewportConnection = nil
	end
end

local function rebindViewportConnection()
	if viewportConnection then
		viewportConnection:Disconnect()
		viewportConnection = nil
	end
	ensureViewportConnection()
end

local function getInstancePosition(instance: Instance): Vector3?
	if instance:IsA("BasePart") then
		return instance.Position
	elseif instance:IsA("Model") then
		return instance:GetPivot().Position
	end

	return nil
end

local function updateBillboardRecord(record: RootRecord<BillboardGui>)
	local billboardGui = record.Root
	local camera = getCamera()
	if not camera then
		return
	end

	local adornee = billboardGui.Adornee
	local origin = if adornee then getInstancePosition(adornee) else nil
	if not origin and billboardGui.Parent then
		origin = getInstancePosition(billboardGui.Parent)
	end
	if not origin then
		return
	end

	local magnitude = (camera.CFrame.Position - origin).Magnitude
	if magnitude <= 0.001 then
		return
	end

	local maxDistance = billboardGui.MaxDistance
	if maxDistance > 0 and magnitude > maxDistance then
		return
	end

	local distanceRatio = ((tonumber(billboardGui:GetAttribute("Distance")) or DEFAULT_BILLBOARD_DISTANCE) / magnitude)
	local screenRatio = getScreenRatio()
	for index = #record.Strokes, 1, -1 do
		local uiStroke = record.Strokes[index]
		if not uiStroke:IsDescendantOf(billboardGui) then
			table.remove(record.Strokes, index)
			continue
		end

		local originalThickness = tonumber(uiStroke:GetAttribute(ORIGINAL_THICKNESS_ATTRIBUTE))
		if originalThickness then
			uiStroke.Thickness = originalThickness * distanceRatio * screenRatio
		end
	end
end

local function updateBillboardRecords()
	if not hasAnyBillboardRecord() then
		return false
	end

	for _, record in pairs(billboardRecords) do
		if record.Root.Parent == nil then
			UIStrokeAdjuster:UnregisterBillboardGui(record.Root)
		else
			updateBillboardRecord(record)
		end
	end

	return hasAnyBillboardRecord()
end

local function ensureBillboardScheduler()
	if not hasAnyBillboardRecord() then
		return
	end

	if billboardSchedulerHandle and billboardSchedulerHandle:IsConnected() then
		return
	end

	billboardSchedulerHandle = RuntimeScheduler.GetDefault():Schedule({
		Id = BILLBOARD_SCHEDULER_TASK_ID,
		Phase = "Heartbeat",
		Interval = UPDATE_DELAY,
		Priority = -25,
		Callback = function()
			return updateBillboardRecords()
		end,
		OnStop = function()
			billboardSchedulerHandle = nil
		end,
	})
end

local function stopBillboardSchedulerIfIdle()
	if hasAnyBillboardRecord() then
		return
	end

	if billboardSchedulerHandle and billboardSchedulerHandle:IsConnected() then
		billboardSchedulerHandle:Disconnect("idle")
	end
	billboardSchedulerHandle = nil
end

local function makeHandle(unregisterCallback: () -> ()): RegistrationHandle
	local connected = true
	local handle = {} :: RegistrationHandle

	function handle:Disconnect()
		if not connected then
			return
		end
		connected = false
		unregisterCallback()
	end

	function handle:IsConnected(): boolean
		return connected
	end

	return handle
end

function UIStrokeAdjuster:RegisterScreenGui(screenGui: ScreenGui): RegistrationHandle?
	if not screenGui:IsA("ScreenGui") then
		return nil
	end

	if screenRecords[screenGui] then
		return makeHandle(function()
			UIStrokeAdjuster:UnregisterScreenGui(screenGui)
		end)
	end

	local record: RootRecord<ScreenGui> = {
		Root = screenGui,
		Strokes = {},
		Connections = {},
	}
	screenRecords[screenGui] = record

	collectStrokes(screenGui, record)
	updateScreenRecord(record)

	record.Connections[#record.Connections + 1] = screenGui.DescendantAdded:Connect(function(descendant)
		if descendant:IsA("UIStroke") then
			appendStroke(record, descendant)
			updateScreenRecord(record)
		end
	end)
	record.Connections[#record.Connections + 1] = screenGui.Destroying:Connect(function()
		UIStrokeAdjuster:UnregisterScreenGui(screenGui)
	end)
	record.Connections[#record.Connections + 1] = screenGui.AncestryChanged:Connect(function(_, parent)
		if parent == nil then
			UIStrokeAdjuster:UnregisterScreenGui(screenGui)
		end
	end)

	ensureViewportConnection()

	return makeHandle(function()
		UIStrokeAdjuster:UnregisterScreenGui(screenGui)
	end)
end

function UIStrokeAdjuster:UnregisterScreenGui(screenGui: ScreenGui)
	local record = screenRecords[screenGui]
	if not record then
		return
	end

	disconnectAll(record.Connections)
	screenRecords[screenGui] = nil
	disconnectViewportIfIdle()
end

function UIStrokeAdjuster:RegisterBillboardGui(billboardGui: BillboardGui): RegistrationHandle?
	if not billboardGui:IsA("BillboardGui") then
		return nil
	end

	if billboardRecords[billboardGui] then
		return makeHandle(function()
			UIStrokeAdjuster:UnregisterBillboardGui(billboardGui)
		end)
	end

	local record: RootRecord<BillboardGui> = {
		Root = billboardGui,
		Strokes = {},
		Connections = {},
	}
	billboardRecords[billboardGui] = record

	collectStrokes(billboardGui, record)
	updateBillboardRecord(record)

	record.Connections[#record.Connections + 1] = billboardGui.DescendantAdded:Connect(function(descendant)
		if descendant:IsA("UIStroke") then
			appendStroke(record, descendant)
			updateBillboardRecord(record)
		end
	end)
	record.Connections[#record.Connections + 1] = billboardGui.Destroying:Connect(function()
		UIStrokeAdjuster:UnregisterBillboardGui(billboardGui)
	end)
	record.Connections[#record.Connections + 1] = billboardGui.AncestryChanged:Connect(function(_, parent)
		if parent == nil then
			UIStrokeAdjuster:UnregisterBillboardGui(billboardGui)
		end
	end)

	ensureBillboardScheduler()

	return makeHandle(function()
		UIStrokeAdjuster:UnregisterBillboardGui(billboardGui)
	end)
end

function UIStrokeAdjuster:UnregisterBillboardGui(billboardGui: BillboardGui)
	local record = billboardRecords[billboardGui]
	if not record then
		return
	end

	disconnectAll(record.Connections)
	billboardRecords[billboardGui] = nil
	stopBillboardSchedulerIfIdle()
end

function UIStrokeAdjuster:TagScreenGui(screenGui: ScreenGui): RegistrationHandle?
	return self:RegisterScreenGui(screenGui)
end

function UIStrokeAdjuster:TagBillboardGui(billboardGui: BillboardGui): RegistrationHandle?
	return self:RegisterBillboardGui(billboardGui)
end

Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
	if hasAnyScreenRecord() then
		rebindViewportConnection()
		updateScreenRecords()
	end
	if hasAnyBillboardRecord() then
		updateBillboardRecords()
	end
end)

return UIStrokeAdjuster
