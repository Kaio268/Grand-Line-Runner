local ReplicatedStorage = game:GetService("ReplicatedStorage")

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local remote = remotes:WaitForChild("StandUpgradeRemote")

local previewRemote = remotes:FindFirstChild("StandUpgradePreviewRemote")
if previewRemote and not previewRemote:IsA("RemoteFunction") then
	previewRemote:Destroy()
	previewRemote = nil
end
if not previewRemote then
	previewRemote = Instance.new("RemoteFunction")
	previewRemote.Name = "StandUpgradePreviewRemote"
	previewRemote.Parent = remotes
end

local resultRemote = remotes:FindFirstChild("StandUpgradeStepResultRemote")
if resultRemote and not resultRemote:IsA("RemoteEvent") then
	resultRemote:Destroy()
	resultRemote = nil
end
if not resultRemote then
	resultRemote = Instance.new("RemoteEvent")
	resultRemote.Name = "StandUpgradeStepResultRemote"
	resultRemote.Parent = remotes
end

local BrainrotFoodProgression = require(game.ServerScriptService.Modules:WaitForChild("BrainrotFoodProgression"))
local BrainrotInstanceService = require(game.ServerScriptService.Modules:WaitForChild("BrainrotInstanceService"))
local GrandLineRushVerticalSliceService = require(game.ServerScriptService.Modules:WaitForChild("GrandLineRushVerticalSliceService"))
local DataManager = require(game.ServerScriptService.Data:WaitForChild("DataManager"))
local PopUpModule = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("PopUpModule"))

local SUCCESS_COLOR = Color3.fromRGB(92, 230, 126)
local INFO_COLOR = Color3.fromRGB(111, 188, 255)
local ERROR_COLOR = Color3.fromRGB(255, 94, 94)
local STROKE_COLOR = Color3.fromRGB(0, 0, 0)

local function pushResourceState(player)
	if GrandLineRushVerticalSliceService and typeof(GrandLineRushVerticalSliceService.PushState) == "function" then
		GrandLineRushVerticalSliceService.PushState(player)
	end
end

local function sendPopup(player, text, color, isError)
	PopUpModule:Server_SendPopUp(player, text, color or INFO_COLOR, STROKE_COLOR, 3, isError == true)
end

local function getStandName(payload)
	if typeof(payload) == "table" then
		return tostring(payload.StandName or "")
	end
	if typeof(payload) == "string" then
		return payload
	end
	return ""
end

local function buildFailurePayload(standName, errorCode, message, progress, step)
	return {
		Ok = false,
		StandName = standName,
		Error = errorCode,
		Message = message,
		Progress = progress,
		Step = step,
	}
end

local function getFailureMessage(errorCode)
	if errorCode == "brainrot_max_level" then
		return "This brainrot is already max level."
	end
	if errorCode == "not_enough_food" then
		return "Not enough food to upgrade this brainrot."
	end
	if errorCode == "step_changed" then
		return "The next food changed. Please confirm the new step."
	end
	if errorCode == "missing_brainrot" then
		return "Brainrot progress could not be loaded."
	end
	return "Unable to use food on this brainrot right now."
end

local function updateStandGui(player, standName, progress)
	if not progress then
		return
	end

	local playerGui = player:FindFirstChild("PlayerGui")
	if not playerGui then
		return
	end

	local standGui = playerGui:FindFirstChild(standName)
	if not standGui or not standGui:FindFirstChild("LevelUp") or not standGui.LevelUp:FindFirstChild("Main") then
		return
	end

	local main = standGui.LevelUp.Main
	local price = main:FindFirstChild("Price", true)
	local upgrade = main:FindFirstChild("Upgarde", true) or main:FindFirstChild("Upgrade", true)

	if upgrade and (upgrade:IsA("TextLabel") or upgrade:IsA("TextButton") or upgrade:IsA("TextBox")) then
		upgrade.Text = "Current Level: " .. tostring(progress.Level)
	end

	if price and (price:IsA("TextLabel") or price:IsA("TextButton") or price:IsA("TextBox")) then
		if progress.Level >= progress.MaxLevel then
			price.Text = "Max Level"
		else
			local text = string.format("XP: %d / %d", math.max(0, progress.CurrentXP), math.max(0, progress.NextLevelXP))
			if BrainrotFoodProgression.GetTotalFoodCount(player) > 0 then
				text ..= " | Auto-feed"
			else
				text ..= " | No Food"
			end
			price.Text = text
		end
	end
end

local function resolveUpgradeContext(player, standName)
	if standName == "" then
		return false, buildFailurePayload("", "invalid_stand", "Stand could not be identified.")
	end

	local brainrotName = DataManager:GetValue(player, "IncomeBrainrots." .. standName .. ".BrainrotName")
	if typeof(brainrotName) ~= "string" or brainrotName == "" then
		return false, buildFailurePayload(standName, "missing_brainrot", "Place a brainrot on this stand first.")
	end

	local brainrotInstanceId = BrainrotInstanceService.GetStandInstanceId(player, standName)
	if brainrotInstanceId == "" then
		brainrotInstanceId = BrainrotInstanceService.EnsureStandInstance(player, standName, brainrotName) or ""
	end

	local progressTarget = brainrotInstanceId ~= "" and brainrotInstanceId or brainrotName
	local progress = BrainrotFoodProgression.GetProgress(player, progressTarget)
	if not progress then
		return false, buildFailurePayload(standName, "missing_brainrot", "Brainrot progress could not be loaded.")
	end

	return true, {
		StandName = standName,
		BrainrotName = brainrotName,
		BrainrotInstanceId = brainrotInstanceId,
		ProgressTarget = progressTarget,
		Progress = progress,
	}
end

local function syncStandStateForProgress(player, fallbackStandName, progress)
	local playerGui = player:FindFirstChild("PlayerGui")
	local standsLevels = player:FindFirstChild("StandsLevels")
	local targetInstanceId = tostring(progress.InstanceId or "")
	local updatedAnyStand = false

	if playerGui then
		for _, gui in ipairs(playerGui:GetChildren()) do
			if gui:IsA("SurfaceGui") and tonumber(gui.Name) then
				local guiStandName = gui.Name
				local guiBrainrotInstanceId = BrainrotInstanceService.GetStandInstanceId(player, guiStandName)
				if guiBrainrotInstanceId == targetInstanceId then
					local standLevel = standsLevels and standsLevels:FindFirstChild(guiStandName)
					if standLevel and standLevel:IsA("NumberValue") then
						standLevel.Value = progress.Level
					end
					DataManager:SetValue(player, "StandsLevels." .. guiStandName, progress.Level)
					updateStandGui(player, guiStandName, progress)
					updatedAnyStand = true
				end
			end
		end
	end

	if not updatedAnyStand then
		local standLevel = standsLevels and standsLevels:FindFirstChild(fallbackStandName)
		if standLevel and standLevel:IsA("NumberValue") then
			standLevel.Value = progress.Level
		end
		DataManager:SetValue(player, "StandsLevels." .. fallbackStandName, progress.Level)
		updateStandGui(player, fallbackStandName, progress)
	end
end

previewRemote.OnServerInvoke = function(player, standNameInput)
	local standName = getStandName(standNameInput)
	local ok, context = resolveUpgradeContext(player, standName)
	if not ok then
		return context
	end

	local previewOk, preview = BrainrotFoodProgression.GetNextAutoFeedStep(player, context.ProgressTarget)
	if not previewOk then
		local progress = preview and preview.Progress or context.Progress
		return buildFailurePayload(
			standName,
			preview and preview.Error or "preview_failed",
			getFailureMessage(preview and preview.Error or nil),
			progress,
			preview and preview.Step or nil
		)
	end

	return {
		Ok = true,
		StandName = standName,
		Progress = preview.Progress,
		Step = preview.Step,
	}
end

remote.OnServerEvent:Connect(function(player, payload)
	local standName = getStandName(payload)
	if standName == "" then
		return
	end

	local expectedFoodKey = ""
	if typeof(payload) == "table" then
		expectedFoodKey = tostring(payload.ExpectedFoodKey or "")
	end

	local ok, context = resolveUpgradeContext(player, standName)
	if not ok then
		if context.Message then
			sendPopup(player, context.Message, ERROR_COLOR, true)
		end
		resultRemote:FireClient(player, context)
		return
	end

	local success, result = BrainrotFoodProgression.ApplyAutoFeedStep(
		player,
		context.ProgressTarget,
		expectedFoodKey ~= "" and expectedFoodKey or nil
	)

	local progress = success and result and result.Progress or BrainrotFoodProgression.GetProgress(player, context.ProgressTarget)
	if not progress then
		return
	end

	if not success then
		pushResourceState(player)

		local failurePayload = buildFailurePayload(
			standName,
			result and result.Error or "upgrade_failed",
			getFailureMessage(result and result.Error or nil),
			progress,
			result and result.Step or nil
		)

		sendPopup(player, failurePayload.Message, ERROR_COLOR, true)
		updateStandGui(player, standName, progress)
		resultRemote:FireClient(player, failurePayload)
		return
	end

	local appliedStep = result.AppliedStep
	local appliedFoodName = tostring(appliedStep.FoodDisplayName or BrainrotFoodProgression.GetFoodDisplayName(appliedStep.FoodKey))

	pushResourceState(player)
	sendPopup(
		player,
		string.format("Used %dx %s (+%d XP).", appliedStep.AmountUsed, appliedFoodName, appliedStep.XPGained),
		SUCCESS_COLOR,
		false
	)

	syncStandStateForProgress(player, standName, progress)

	local continuePreview = nil
	if progress.Level < progress.MaxLevel then
		local nextPreviewOk, nextPreview = BrainrotFoodProgression.GetNextAutoFeedStep(player, context.ProgressTarget)
		if nextPreviewOk then
			continuePreview = nextPreview.Step
			if continuePreview and tostring(continuePreview.FoodKey) ~= tostring(appliedStep.FoodKey) then
				sendPopup(
					player,
					string.format("%s used up. Switching to %s.", appliedFoodName, tostring(continuePreview.FoodDisplayName or continuePreview.FoodKey)),
					INFO_COLOR,
					false
				)
			end
		end
	end

	if result.LevelUps > 0 then
		sendPopup(
			player,
			string.format("Upgrade complete. Current Level: %d (+%d level).", progress.Level, result.LevelUps),
			SUCCESS_COLOR,
			false
		)
	else
		sendPopup(
			player,
			string.format("Current XP: %d / %d.", progress.CurrentXP, progress.NextLevelXP),
			INFO_COLOR,
			false
		)

		if not continuePreview and progress.Level < progress.MaxLevel then
			sendPopup(
				player,
				string.format("Out of food. Current XP: %d / %d.", progress.CurrentXP, progress.NextLevelXP),
				INFO_COLOR,
				false
			)
		end
	end

	resultRemote:FireClient(player, {
		Ok = true,
		StandName = standName,
		AppliedStep = appliedStep,
		Progress = progress,
		LevelUps = result.LevelUps,
		ContinuePreview = continuePreview,
	})
end)
