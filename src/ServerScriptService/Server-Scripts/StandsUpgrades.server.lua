local ReplicatedStorage = game:GetService("ReplicatedStorage")

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local CREW_MEMBER_STAND_UPGRADE_REMOTE_NAME = "CrewMemberStandUpgradeRemote"
local CREW_MEMBER_STAND_UPGRADE_PREVIEW_REMOTE_NAME = "CrewMemberStandUpgradePreviewRemote"
local CREW_MEMBER_STAND_UPGRADE_RESULT_REMOTE_NAME = "CrewMemberStandUpgradeStepResultRemote"

local function getOrCreateRemote(remoteName, className)
	local remote = remotes:FindFirstChild(remoteName)
	if remote and not remote:IsA(className) then
		remote:Destroy()
		remote = nil
	end
	if not remote then
		remote = Instance.new(className)
		remote.Name = remoteName
		remote.Parent = remotes
	end
	return remote
end

local crewMemberRemote = getOrCreateRemote(CREW_MEMBER_STAND_UPGRADE_REMOTE_NAME, "RemoteEvent")
local crewMemberPreviewRemote = getOrCreateRemote(CREW_MEMBER_STAND_UPGRADE_PREVIEW_REMOTE_NAME, "RemoteFunction")
local crewMemberResultRemote = getOrCreateRemote(CREW_MEMBER_STAND_UPGRADE_RESULT_REMOTE_NAME, "RemoteEvent")

local CrewFoodProgression = require(game.ServerScriptService.Modules:WaitForChild("CrewFoodProgression"))
local CrewInstanceService = require(game.ServerScriptService.Modules:WaitForChild("CrewInstanceService"))
local CrewMemberCanonicalReadGate = require(game.ServerScriptService.Modules:WaitForChild("CrewMemberCanonicalReadGate"))
local CrewStandIncomeAuthority = require(game.ServerScriptService.Modules:WaitForChild("CrewStandIncomeAuthority"))
local GrandLineRushVerticalSliceService = require(game.ServerScriptService.Modules:WaitForChild("GrandLineRushVerticalSliceService"))
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
		return "This Crewmate is already max level."
	end
	if errorCode == "not_enough_food" then
		return "Not enough food to upgrade this Crewmate."
	end
	if errorCode == "step_changed" then
		return "The next food changed. Please confirm the new step."
	end
	if errorCode == "missing_brainrot" then
		return "Crewmate progress could not be loaded."
	end
	return "Unable to use food on this Crewmate right now."
end

local function getCanonicalFoodStatusDisplayNameForPopup(player, context)
	local legacyIdentity = tostring(context and context.BrainrotName or "")
	if legacyIdentity == "" then
		return nil
	end

	local _, result = CrewMemberCanonicalReadGate.ResolveFoodStatusDisplayName(player, legacyIdentity, {
		Player = player,
	})
	if typeof(result) ~= "table" then
		return nil
	end
	if result.UsedCanonical ~= true or result.IsAuthoritative == true then
		return nil
	end
	if tostring(result.Path or "") ~= CrewMemberCanonicalReadGate.Paths.GameplayHelperFoodStatusDisplayName then
		return nil
	end

	local displayName = tostring(result.Value or "")
	if displayName == "" then
		return nil
	end
	return displayName
end

local function getFoodStatusReadAuthorityDisplayNameForPopup(player, context, progress, appliedStep)
	local legacyIdentity = tostring(context and context.BrainrotName or "")
	if legacyIdentity == "" then
		return nil
	end

	local _, result = CrewMemberCanonicalReadGate.ResolveFoodStatusReadAuthority(player, {
		StandName = tostring(context and context.StandName or ""),
		LegacyIdentity = legacyIdentity,
		InstanceId = tostring(context and context.BrainrotInstanceId or ""),
		Progress = progress,
		AppliedStep = appliedStep,
	}, {
		Player = player,
	})
	if typeof(result) ~= "table" then
		return nil
	end
	if result.UsedCanonical ~= true or result.IsMutationAuthority == true then
		return nil
	end
	if tostring(result.Path or "") ~= CrewMemberCanonicalReadGate.Paths.ReadAuthorityFoodStatus then
		return nil
	end

	local displayName = tostring(result.DisplayName or "")
	if displayName == "" then
		return nil
	end
	return displayName
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
			if CrewFoodProgression.GetTotalFoodCount(player) > 0 then
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

	local standData = CrewStandIncomeAuthority.GetStandData(player, standName)
	local brainrotName = standData and standData.BrainrotName
	if typeof(brainrotName) ~= "string" or brainrotName == "" then
		return false, buildFailurePayload(standName, "missing_brainrot", "Place a Crewmate on this stand first.")
	end

	local brainrotInstanceId = CrewInstanceService.GetStandInstanceId(player, standName)
	if brainrotInstanceId == "" then
		brainrotInstanceId = CrewInstanceService.EnsureStandInstance(player, standName, brainrotName) or ""
	end

	local progressTarget = brainrotInstanceId ~= "" and brainrotInstanceId or brainrotName
	local progress = CrewFoodProgression.GetProgress(player, progressTarget)
	if not progress then
		return false, buildFailurePayload(standName, "missing_brainrot", "Crewmate progress could not be loaded.")
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
	local targetInstanceId = tostring(progress.InstanceId or "")
	local updatedAnyStand = false

	if playerGui then
		for _, gui in ipairs(playerGui:GetChildren()) do
			if gui:IsA("SurfaceGui") and tonumber(gui.Name) then
				local guiStandName = gui.Name
				local guiBrainrotInstanceId = CrewInstanceService.GetStandInstanceId(player, guiStandName)
				if guiBrainrotInstanceId == targetInstanceId then
					CrewStandIncomeAuthority.SetStandLevel(player, guiStandName, progress.Level, "stand_upgrade_progress_sync")
					updateStandGui(player, guiStandName, progress)
					updatedAnyStand = true
				end
			end
		end
	end

	if not updatedAnyStand then
		CrewStandIncomeAuthority.SetStandLevel(player, fallbackStandName, progress.Level, "stand_upgrade_progress_sync")
		updateStandGui(player, fallbackStandName, progress)
	end
end

local function fireStepResult(player, payload)
	crewMemberResultRemote:FireClient(player, payload)
end

local function buildUpgradePreview(player, standNameInput)
	local standName = getStandName(standNameInput)
	local ok, context = resolveUpgradeContext(player, standName)
	if not ok then
		return context
	end

	local previewOk, preview = CrewFoodProgression.GetNextAutoFeedStep(player, context.ProgressTarget)
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

crewMemberPreviewRemote.OnServerInvoke = function(player, standNameInput)
	return buildUpgradePreview(player, standNameInput)
end

local function handleUpgradeRequest(player, payload)
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
		fireStepResult(player, context)
		return
	end

	local success, result = CrewFoodProgression.ApplyAutoFeedStep(
		player,
		context.ProgressTarget,
		expectedFoodKey ~= "" and expectedFoodKey or nil,
		{
			DeferShadowRefresh = true,
		}
	)

	local progress = success and result and result.Progress or CrewFoodProgression.GetProgress(player, context.ProgressTarget)
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
		fireStepResult(player, failurePayload)
		return
	end

	local appliedStep = result.AppliedStep
	local appliedFoodName = tostring(appliedStep.FoodDisplayName or CrewFoodProgression.GetFoodDisplayName(appliedStep.FoodKey))

	pushResourceState(player)
	syncStandStateForProgress(player, standName, progress)
	CrewFoodProgression.RefreshProgressionShadow(player, "food_progression")

	local foodStatusDisplayName = getFoodStatusReadAuthorityDisplayNameForPopup(player, context, progress, appliedStep)
		or getCanonicalFoodStatusDisplayNameForPopup(player, context)
	local foodUsedMessage = if foodStatusDisplayName ~= nil
		then string.format(
			"Used %dx %s on %s (+%d XP).",
			appliedStep.AmountUsed,
			appliedFoodName,
			foodStatusDisplayName,
			appliedStep.XPGained
		)
		else string.format("Used %dx %s (+%d XP).", appliedStep.AmountUsed, appliedFoodName, appliedStep.XPGained)
	sendPopup(player, foodUsedMessage, SUCCESS_COLOR, false)

	local continuePreview = nil
	if progress.Level < progress.MaxLevel then
		local nextPreviewOk, nextPreview = CrewFoodProgression.GetNextAutoFeedStep(player, context.ProgressTarget)
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

	fireStepResult(player, {
		Ok = true,
		StandName = standName,
		AppliedStep = appliedStep,
		Progress = progress,
		LevelUps = result.LevelUps,
		ContinuePreview = continuePreview,
	})
end

crewMemberRemote.OnServerEvent:Connect(function(player, payload)
	handleUpgradeRequest(player, payload)
end)
