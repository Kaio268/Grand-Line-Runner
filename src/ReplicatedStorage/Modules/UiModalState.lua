local Players = game:GetService("Players")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local UiModalState = {}

local GAMEPLAY_MODAL_OPEN_ATTRIBUTE = "GameplayModalOpen"
local SUPPRESSED_GUI_NAMES = {
	HUD = true,
}

local openKeys = {}
local initialized = false

local function hasOpenModal()
	return next(openKeys) ~= nil
end

local function setSuppressedGuiState(screenGui, isSuppressed)
	if not screenGui or not screenGui:IsA("ScreenGui") then
		return
	end

	if isSuppressed then
		if screenGui:GetAttribute("UiModalSuppressed") ~= true then
			screenGui:SetAttribute("UiModalPreviousEnabled", screenGui.Enabled)
		end

		screenGui:SetAttribute("UiModalSuppressed", true)
		screenGui.Enabled = false
		return
	end

	if screenGui:GetAttribute("UiModalSuppressed") == true then
		local previousEnabled = screenGui:GetAttribute("UiModalPreviousEnabled")
		if typeof(previousEnabled) == "boolean" then
			screenGui.Enabled = previousEnabled
		else
			screenGui.Enabled = true
		end
	end

	screenGui:SetAttribute("UiModalSuppressed", nil)
	screenGui:SetAttribute("UiModalPreviousEnabled", nil)
end

local function applyState()
	local isOpen = hasOpenModal()
	playerGui:SetAttribute(GAMEPLAY_MODAL_OPEN_ATTRIBUTE, isOpen)

	for guiName in pairs(SUPPRESSED_GUI_NAMES) do
		setSuppressedGuiState(playerGui:FindFirstChild(guiName), isOpen)
	end
end

local function ensureInitialized()
	if initialized then
		return
	end

	initialized = true
	playerGui.ChildAdded:Connect(function(child)
		if SUPPRESSED_GUI_NAMES[child.Name] then
			task.defer(applyState)
		end
	end)

	applyState()
end

function UiModalState.SetOpen(key, isOpen)
	if typeof(key) ~= "string" or key == "" then
		return
	end

	ensureInitialized()

	if isOpen then
		openKeys[key] = true
	else
		openKeys[key] = nil
	end

	applyState()
end

function UiModalState.IsOpen()
	ensureInitialized()
	return playerGui:GetAttribute(GAMEPLAY_MODAL_OPEN_ATTRIBUTE) == true
end

function UiModalState.GetAttributeName()
	return GAMEPLAY_MODAL_OPEN_ATTRIBUTE
end

return UiModalState
