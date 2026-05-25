local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local packages = ReplicatedStorage:WaitForChild("Packages")
local modules = ReplicatedStorage:WaitForChild("Modules")
local uiFolder = ReplicatedStorage:WaitForChild("UI")

local React = require(packages:WaitForChild("React"))
local ReactRoblox = require(packages:WaitForChild("ReactRoblox"))
local UiModalState = require(modules:WaitForChild("UiModalState"))
local PopUpModule = require(modules:WaitForChild("PopUpModule"))
local ShipSlotGuiIdentity = require(modules:WaitForChild("ShipSlotGuiIdentity"))
local StandUpgradePromptScreen = require(uiFolder:WaitForChild("Crew"):WaitForChild("StandUpgradePromptScreen"))
local ShipSlotLevelPanelBinder = require(script.Parent:WaitForChild("UI"):WaitForChild("ShipSlotLevelPanelBinder"))

local remote = remotes:WaitForChild("CrewMemberStandUpgradeRemote", 15)
local previewRemote = remotes:WaitForChild("CrewMemberStandUpgradePreviewRemote", 15)
local resultRemote = remotes:WaitForChild("CrewMemberStandUpgradeStepResultRemote", 15)

local POPUP_ERROR = Color3.fromRGB(255, 94, 94)
local POPUP_INFO = Color3.fromRGB(111, 188, 255)
local POPUP_STROKE = Color3.fromRGB(0, 0, 0)
local MODAL_STATE_KEY = "StandUpgradePrompt"
local CAPTAIN_SLOT_KEY = "Captain"
local CAPTAIN_RUNTIME_GUI_ATTRIBUTE = "ShipCaptainSlotRuntimeGui"
local CAPTAIN_RUNTIME_GUI_SLOT_ATTRIBUTE = "ShipCaptainSlotKey"

local rootContainer = Instance.new("Folder")
rootContainer.Name = "ReactStandUpgradePromptRoot"

local root = ReactRoblox.createRoot(rootContainer)
local connectionsByGui = {}
local levelPanelHandlesByGui = {}
local guiBySlotKey = {}
local slotKeyByGui = {}
local pendingPreview
local awaitingResultStandName
local scheduledPromptId = 0
local approvedFoodSessions = {}
local destroyed = false
local renderQueued = false

local function clearApprovedFoodSession(standName)
	if typeof(standName) == "string" and standName ~= "" then
		approvedFoodSessions[standName] = nil
	end
end

local function getApprovedFoodSession(standName, instanceId)
	local session = approvedFoodSessions[standName]
	if not session then
		return nil
	end

	if tostring(session.InstanceId or "") ~= tostring(instanceId or "") then
		approvedFoodSessions[standName] = nil
		return nil
	end

	return session
end

local function setApprovedFoodSession(standName, instanceId, foodKey, foodDisplayName)
	if typeof(standName) ~= "string" or standName == "" then
		return
	end

	approvedFoodSessions[standName] = {
		FoodDisplayName = tostring(foodDisplayName or foodKey or ""),
		FoodKey = tostring(foodKey or ""),
		InstanceId = tostring(instanceId or ""),
	}
end

local function sendLocalPopup(text, color, isError)
	PopUpModule:Local_SendPopUp(text, color or POPUP_INFO, POPUP_STROKE, 3, isError == true)
end

local function hidePrompt()
	pendingPreview = nil
	UiModalState.SetOpen(MODAL_STATE_KEY, false)
end

local function buildPromptCopy()
	if not pendingPreview then
		return "", "", ""
	end

	local step = pendingPreview.Step or {}
	local foodDisplayName = tostring(step.FoodDisplayName or step.FoodKey or "Food")
	local amountUsed = math.max(0, math.floor(tonumber(step.AmountUsed) or 0))
	local xpGained = math.max(0, math.floor(tonumber(step.XPGained) or 0))
	local priorFoodDisplayName = pendingPreview.PriorFoodDisplayName
	local hasPriorFood = typeof(priorFoodDisplayName) == "string" and priorFoodDisplayName ~= ""

	if hasPriorFood then
		return string.format("Use %s next?", foodDisplayName), table.concat({
			string.format("%s has run out.", priorFoodDisplayName),
			string.format("The next food is %s.", foodDisplayName),
			"",
			string.format("%dx %s will be consumed for +%d XP.", amountUsed, foodDisplayName, xpGained),
		}, "\n"), string.format("Use %s", foodDisplayName)
	end

	return string.format("Use %s?", foodDisplayName), table.concat({
		string.format("Are you sure you want to use %s to upgrade this crewmate?", foodDisplayName),
		"",
		string.format("%dx %s will be consumed for +%d XP.", amountUsed, foodDisplayName, xpGained),
	}, "\n"), string.format("Use %s", foodDisplayName)
end

local function render()
	local title, body, confirmText = buildPromptCopy()
	root:render(ReactRoblox.createPortal(React.createElement(StandUpgradePromptScreen, {
		body = body,
		confirmText = confirmText,
		onCancel = function()
			if pendingPreview then
				clearApprovedFoodSession(pendingPreview.StandName)
			end
			hidePrompt()
			render()
		end,
		onConfirm = function()
			if not pendingPreview or awaitingResultStandName then
				return
			end

			local preview = pendingPreview
			awaitingResultStandName = preview.StandName
			setApprovedFoodSession(
				preview.StandName,
				preview.InstanceId,
				preview.Step.FoodKey,
				preview.Step.FoodDisplayName
			)
			hidePrompt()
			render()
			remote:FireServer({
				ExpectedFoodKey = preview.Step.FoodKey,
				StandName = preview.StandName,
			})
		end,
		title = title,
		visible = pendingPreview ~= nil,
	}), playerGui))
end

local function scheduleRender()
	if renderQueued or destroyed then
		return
	end

	renderQueued = true
	task.defer(function()
		renderQueued = false
		if not destroyed then
			render()
		end
	end)
end

local function showPreviewPrompt(standName, step, priorFoodDisplayName)
	if typeof(standName) ~= "string" or standName == "" or typeof(step) ~= "table" then
		return
	end

	pendingPreview = {
		InstanceId = tostring(step.InstanceId or ""),
		PriorFoodDisplayName = priorFoodDisplayName,
		StandName = standName,
		Step = step,
	}
	UiModalState.SetOpen(MODAL_STATE_KEY, true)
	scheduleRender()
end

local function scheduleNextPrompt(standName, step, priorFoodDisplayName)
	scheduledPromptId += 1
	local promptId = scheduledPromptId

	task.delay(0.15, function()
		if scheduledPromptId == promptId then
			showPreviewPrompt(standName, step, priorFoodDisplayName)
		end
	end)
end

local function requestPreview(standName, priorFoodDisplayName)
	if typeof(standName) ~= "string" or standName == "" then
		return
	end

	scheduledPromptId += 1

	local ok, response = pcall(function()
		return previewRemote:InvokeServer(standName)
	end)
	if not ok then
		sendLocalPopup("Unable to preview the next food step right now.", POPUP_ERROR, true)
		return
	end

	if typeof(response) ~= "table" or response.Ok ~= true or typeof(response.Step) ~= "table" then
		sendLocalPopup(
			tostring(response and response.Message or "Unable to preview the next food step right now."),
			POPUP_ERROR,
			true
		)
		return
	end

	local instanceId = tostring(response.Progress and response.Progress.InstanceId or "")
	local approvedSession = getApprovedFoodSession(standName, instanceId)
	if approvedSession and tostring(approvedSession.FoodKey or "") == tostring(response.Step.FoodKey or "") then
		awaitingResultStandName = standName
		remote:FireServer({
			ExpectedFoodKey = response.Step.FoodKey,
			StandName = standName,
		})
		return
	end

	response.Step.InstanceId = instanceId
	showPreviewPrompt(standName, response.Step, priorFoodDisplayName)
end

local function disconnectGui(gui)
	local connection = connectionsByGui[gui]
	if connection then
		connection:Disconnect()
		connectionsByGui[gui] = nil
	end

	local levelPanelHandle = levelPanelHandlesByGui[gui]
	if levelPanelHandle then
		levelPanelHandle:Destroy()
		levelPanelHandlesByGui[gui] = nil
	end

	local slotKey = slotKeyByGui[gui]
	if slotKey and guiBySlotKey[slotKey] == gui then
		guiBySlotKey[slotKey] = nil
	end

	slotKeyByGui[gui] = nil
end

local function getUpgradeSlotKeyFromGui(gui)
	local slotKey = ShipSlotGuiIdentity.GetSlotKeyFromGui(gui)
	if slotKey then
		return slotKey
	end

	if
		gui
		and gui:IsA("SurfaceGui")
		and gui:GetAttribute(CAPTAIN_RUNTIME_GUI_ATTRIBUTE) == true
		and tostring(gui:GetAttribute(CAPTAIN_RUNTIME_GUI_SLOT_ATTRIBUTE) or CAPTAIN_SLOT_KEY) == CAPTAIN_SLOT_KEY
	then
		return CAPTAIN_SLOT_KEY
	end

	return nil
end

local function bindGui(gui)
	local slotKey = getUpgradeSlotKeyFromGui(gui)
	if not slotKey then
		return
	end

	if connectionsByGui[gui] then
		return
	end
	if levelPanelHandlesByGui[gui] then
		return
	end

	local existingGui = guiBySlotKey[slotKey]
	if existingGui and existingGui ~= gui then
		disconnectGui(existingGui)
	end

	local function activatePanel()
		if not awaitingResultStandName then
			requestPreview(slotKey, nil)
		end
	end

	local mountOk, levelPanelHandle = pcall(function()
		return ShipSlotLevelPanelBinder.Mount(gui, activatePanel)
	end)
	if mountOk and levelPanelHandle then
		guiBySlotKey[slotKey] = gui
		slotKeyByGui[gui] = slotKey
		levelPanelHandlesByGui[gui] = levelPanelHandle
		return
	end
	if not mountOk then
		warn(("[StandsMenager] Failed to mount ship slot level panel for %s: %s"):format(
			gui:GetFullName(),
			tostring(levelPanelHandle)
		))
	end

	local button = gui:FindFirstChildWhichIsA("TextButton", true)
	if button then
		guiBySlotKey[slotKey] = gui
		slotKeyByGui[gui] = slotKey
		connectionsByGui[gui] = button.MouseButton1Click:Connect(activatePanel)
	end
end

resultRemote.OnClientEvent:Connect(function(payload)
	if typeof(payload) ~= "table" then
		return
	end

	local standName = tostring(payload.StandName or "")
	if standName ~= "" and awaitingResultStandName ~= standName then
		return
	end

	awaitingResultStandName = nil
	if payload.Ok == true then
		local continuePreview = payload.ContinuePreview
		local appliedStep = payload.AppliedStep
		local instanceId = tostring(payload.Progress and payload.Progress.InstanceId or "")

		if appliedStep then
			setApprovedFoodSession(standName, instanceId, appliedStep.FoodKey, appliedStep.FoodDisplayName)
		end

		if typeof(continuePreview) == "table" then
			continuePreview.InstanceId = instanceId
			local approvedSession = getApprovedFoodSession(standName, instanceId)
			local approvedFoodKey = approvedSession and tostring(approvedSession.FoodKey or "") or ""
			local nextFoodKey = tostring(continuePreview.FoodKey or "")
			if approvedFoodKey ~= "" and approvedFoodKey ~= nextFoodKey then
				local priorFoodDisplayName = appliedStep and tostring(appliedStep.FoodDisplayName or appliedStep.FoodKey or "") or ""
				scheduleNextPrompt(standName, continuePreview, priorFoodDisplayName)
			end
		else
			clearApprovedFoodSession(standName)
		end
		return
	end

	if payload.Error == "step_changed" and typeof(payload.Step) == "table" then
		clearApprovedFoodSession(standName)
		scheduleNextPrompt(standName, payload.Step, nil)
		return
	end

	clearApprovedFoodSession(standName)
end)

playerGui.ChildAdded:Connect(bindGui)
playerGui.ChildRemoved:Connect(function(gui)
	if gui and gui:IsA("SurfaceGui") then
		disconnectGui(gui)
	end
end)

for _, gui in ipairs(playerGui:GetChildren()) do
	bindGui(gui)
end

render()

script.Destroying:Connect(function()
	destroyed = true
	hidePrompt()
	for _, connection in pairs(connectionsByGui) do
		connection:Disconnect()
	end
	for _, levelPanelHandle in pairs(levelPanelHandlesByGui) do
		levelPanelHandle:Destroy()
	end
	table.clear(connectionsByGui)
	table.clear(levelPanelHandlesByGui)
	table.clear(guiBySlotKey)
	table.clear(slotKeyByGui)
	root:unmount()
end)
