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
local StandUpgradePromptScreen = require(uiFolder:WaitForChild("Crew"):WaitForChild("StandUpgradePromptScreen"))

local remote = remotes:WaitForChild("CrewMemberStandUpgradeRemote", 15)
local previewRemote = remotes:WaitForChild("CrewMemberStandUpgradePreviewRemote", 15)
local resultRemote = remotes:WaitForChild("CrewMemberStandUpgradeStepResultRemote", 15)

local POPUP_ERROR = Color3.fromRGB(255, 94, 94)
local POPUP_INFO = Color3.fromRGB(111, 188, 255)
local POPUP_STROKE = Color3.fromRGB(0, 0, 0)
local MODAL_STATE_KEY = "StandUpgradePrompt"

local rootContainer = Instance.new("Folder")
rootContainer.Name = "ReactStandUpgradePromptRoot"

local root = ReactRoblox.createRoot(rootContainer)
local connections = {}
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

local function disconnectGui(name)
	local connection = connections[name]
	if connection then
		connection:Disconnect()
		connections[name] = nil
	end
end

local function bindGui(gui)
	if not gui:IsA("SurfaceGui") or tonumber(gui.Name) == nil then
		return
	end

	disconnectGui(gui.Name)
	local button = gui:FindFirstChildWhichIsA("TextButton", true)
	if button then
		connections[gui.Name] = button.MouseButton1Click:Connect(function()
			if not awaitingResultStandName then
				requestPreview(gui.Name, nil)
			end
		end)
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
	if gui and gui:IsA("SurfaceGui") and tonumber(gui.Name) ~= nil then
		disconnectGui(gui.Name)
	end
end)

for _, gui in ipairs(playerGui:GetChildren()) do
	bindGui(gui)
end

render()

script.Destroying:Connect(function()
	destroyed = true
	hidePrompt()
	for _, connection in pairs(connections) do
		connection:Disconnect()
	end
	table.clear(connections)
	root:unmount()
end)
