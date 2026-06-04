local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local packages = ReplicatedStorage:WaitForChild("Packages")
local modules = ReplicatedStorage:WaitForChild("Modules")

local React = require(packages:WaitForChild("React"))
local ReactRoblox = require(packages:WaitForChild("ReactRoblox"))
local CurrencyUtil = require(modules:WaitForChild("CurrencyUtil"))
local EconomyConfig = require(modules:WaitForChild("Configs"):WaitForChild("GrandLineRushEconomy"))
local PopUpModule = require(modules:WaitForChild("PopUpModule"))
local RewardIconResolver = require(modules:WaitForChild("RewardIconResolver"))
local SettingsAudioController = require(modules:WaitForChild("SettingsAudioController"))
local UiModalState = require(modules:WaitForChild("UiModalState"))

local e = React.createElement

local afkRewardsConfig = if EconomyConfig.Chests and typeof(EconomyConfig.Chests.AFKGoldRewards) == "table"
	then EconomyConfig.Chests.AFKGoldRewards
	else {}
local afkRemoteConfig = if typeof(afkRewardsConfig.Remotes) == "table" then afkRewardsConfig.Remotes else {}

local STATE_EVENT_NAME = tostring(afkRemoteConfig.StateEventName or "AFKGoldChestState")
local STATE_REQUEST_NAME = tostring(afkRemoteConfig.StateRequestName or "AFKGoldChestStateRequest")
local EXIT_REQUEST_NAME = tostring(afkRemoteConfig.ExitRequestName or "AFKGoldChestExitRequest")
local UI_HEARTBEAT_EVENT_NAME = tostring(afkRemoteConfig.UiHeartbeatEventName or "AFKGoldChestUiHeartbeat")
local INCOME_METADATA_REQUEST_NAME = "IncomeStatusDisplayMetadataRequest"
local MODAL_STATE_KEY = "AFKWorld"
local TEMP_AUDIO_MUTE_KEY = "RayleighTraining"

local DISPLAY_ORDER = 610
local INCOME_REFRESH_SECONDS = 20
local GOLD = Color3.fromRGB(255, 199, 82)
local GOLD_BRIGHT = Color3.fromRGB(255, 231, 145)
local ORANGE = Color3.fromRGB(255, 139, 64)
local GREEN = Color3.fromRGB(88, 224, 158)
local CYAN = Color3.fromRGB(111, 211, 255)
local ROSE = Color3.fromRGB(255, 118, 142)
local PANEL = Color3.fromRGB(22, 24, 30)
local PANEL_DARK = Color3.fromRGB(13, 15, 20)
local CARD = Color3.fromRGB(31, 33, 39)
local CARD_ALT = Color3.fromRGB(35, 38, 42)
local TEXT = Color3.fromRGB(255, 249, 229)
local MUTED = Color3.fromRGB(205, 202, 190)
local POPUP_STROKE = Color3.fromRGB(66, 42, 4)
local CHEST_ICON = "rbxassetid://88825249018556"
local BELI_ICON = "rbxassetid://76300573750363"
local FRUIT_ICON = "rbxassetid://122583196938184"
local PREMIUM_ICON = "rbxasset://textures/ui/common/robux_small.png"
local BACKGROUND_IMAGE = "rbxassetid://105877304453866"

local stateEvent = nil
local stateRequest = nil
local exitRequest = nil
local uiHeartbeatEvent = nil
local incomeMetadataRequest = nil
local currentState = nil
local stateReceivedAt = 0
local incomeSummary = {
	ready = false,
	status = "loading",
	incomePerSecond = 0,
	claimReady = 0,
	placedCount = 0,
}
local incomeRefreshInFlight = false
local nextIncomeRefreshAt = 0
local recentEvents = {}
local renderQueued = false
local wasSessionActive = false
local wasCapReached = false
local sessionEffectsActive = false
local silentExitInFlight = false
local destroyed = false
local timerLoopRunning = false
local heartbeatLoopRunning = false
local controls = nil
local controlsLocked = false
local connections = {}
local render
local startTimerLoop
local startHeartbeatLoop

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "AFKWorldGui"
screenGui.DisplayOrder = DISPLAY_ORDER
screenGui.IgnoreGuiInset = true
screenGui.ResetOnSpawn = false
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.Parent = playerGui

local root = ReactRoblox.createRoot(screenGui)

local function getPlayerControls()
	if controls ~= nil then
		return controls
	end

	local playerScripts = player:FindFirstChild("PlayerScripts")
	local playerModule = playerScripts and playerScripts:FindFirstChild("PlayerModule")
	if not playerModule or not playerModule:IsA("ModuleScript") then
		return nil
	end

	local ok, playerModuleApi = pcall(require, playerModule)
	if ok and typeof(playerModuleApi) == "table" and typeof(playerModuleApi.GetControls) == "function" then
		local controlsOk, playerControls = pcall(function()
			return playerModuleApi:GetControls()
		end)
		if controlsOk then
			controls = playerControls
		end
	end
	return controls
end

local function setMovementLocked(locked)
	if controlsLocked == locked then
		return
	end

	local playerControls = getPlayerControls()
	if playerControls == nil then
		return
	end

	local ok = pcall(function()
		if locked then
			playerControls:Disable()
		else
			playerControls:Enable()
		end
	end)
	if ok then
		controlsLocked = locked
	end
end

local function applySessionEffects(active)
	active = active == true
	if sessionEffectsActive == active then
		if active and controlsLocked ~= true then
			setMovementLocked(true)
		end
		return
	end

	sessionEffectsActive = active
	if sessionEffectsActive then
		SettingsAudioController.SetTemporaryMute(TEMP_AUDIO_MUTE_KEY, true, {
			Music = true,
		})
		setMovementLocked(true)
	else
		SettingsAudioController.SetTemporaryMute(TEMP_AUDIO_MUTE_KEY, false)
		setMovementLocked(false)
	end
end

local function commaNumber(value)
	local number = math.floor(math.max(0, tonumber(value) or 0) + 0.5)
	local text = tostring(number)
	while true do
		local nextText, replacements = string.gsub(text, "^(-?%d+)(%d%d%d)", "%1,%2")
		text = nextText
		if replacements == 0 then
			break
		end
	end
	return text
end

local function formatDuration(seconds)
	seconds = math.max(0, math.ceil(tonumber(seconds) or 0))
	local hours = math.floor(seconds / 3600)
	local minutes = math.floor((seconds % 3600) / 60)
	local remainingSeconds = seconds % 60
	if hours > 0 then
		return string.format("%d:%02d:%02d", hours, minutes, remainingSeconds)
	end
	return string.format("%02d:%02d", minutes, remainingSeconds)
end

local function readChildValue(parent, childName)
	local child = parent and parent:FindFirstChild(childName)
	if child and child:IsA("ValueBase") then
		return child.Value
	end
	return nil
end

local function readNumberValue(parent, childName, fallback)
	return math.max(0, math.floor(tonumber(readChildValue(parent, childName)) or tonumber(fallback) or 0))
end

local function readProtectionSummary()
	local protectionFolder = player:FindFirstChild("CrewProtection")
	local totalStatsFolder = player:FindFirstChild("TotalStats")
	local timePlayed = readNumberValue(totalStatsFolder, "TimePlayed", 0)
	local shieldTokens = readNumberValue(protectionFolder, "ShieldTokens", 0)
	local fleetShieldTokens = readNumberValue(protectionFolder, "FleetShieldTokens", 0)
	local permanentSlots = readNumberValue(protectionFolder, "PermanentSlotsOwned", 0)
	local fleetShieldFolder = protectionFolder and protectionFolder:FindFirstChild("FleetShield")
	local fleetEnabled = readChildValue(fleetShieldFolder, "Enabled") ~= false
	local fleetExpiresAt = tonumber(readChildValue(fleetShieldFolder, "ExpiresAtPlayTime")) or 0
	local pausedRemaining = readNumberValue(fleetShieldFolder, "PausedRemainingSeconds", 0)
	local remaining = if fleetEnabled then math.max(0, math.floor(fleetExpiresAt - timePlayed)) else 0

	if remaining > 0 then
		return string.format("Fleet Shield: Active %s  |  Crew Shields: %d  |  Fleet Tokens: %d", formatDuration(remaining), shieldTokens, fleetShieldTokens)
	end
	if pausedRemaining > 0 then
		return string.format("Fleet Shield: Paused %s  |  Crew Shields: %d  |  Fleet Tokens: %d", formatDuration(pausedRemaining), shieldTokens, fleetShieldTokens)
	end
	return string.format(
		"Fleet Shield: Off  |  Crew Shields: %d  |  Fleet Tokens: %d  |  Permanent Slots: %d",
		shieldTokens,
		fleetShieldTokens,
		permanentSlots
	)
end

local function getRemainingSeconds()
	if typeof(currentState) ~= "table" then
		return 0
	end

	local baseRemaining = math.max(0, tonumber(currentState.SecondsUntilNext) or 0)
	local elapsed = math.max(0, os.clock() - stateReceivedAt)
	return math.max(0, baseRemaining - elapsed)
end

local function addEvent(text)
	text = tostring(text or "")
	if text == "" then
		return
	end

	table.insert(recentEvents, 1, text)
	while #recentEvents > 5 do
		table.remove(recentEvents)
	end
end

local function getGoldPityText(state)
	local progress = typeof(state) == "table" and state.FruitPityProgress or nil
	local legendary = typeof(progress) == "table" and progress.Legendary or nil
	local mythic = typeof(progress) == "table" and progress.Mythic or nil
	local legendaryFailed = math.max(0, math.floor(tonumber(legendary and legendary.FailedOpens) or 0))
	local legendaryHard = math.max(1, math.floor(tonumber(legendary and legendary.HardPity) or 250))
	local mythicFailed = math.max(0, math.floor(tonumber(mythic and mythic.FailedOpens) or 0))
	local mythicHard = math.max(1, math.floor(tonumber(mythic and mythic.HardPity) or 1500))

	return string.format(
		"Legendary Fruit Pity: %s/%s\nMythic Fruit Pity: %s/%s",
		commaNumber(legendaryFailed),
		commaNumber(legendaryHard),
		commaNumber(mythicFailed),
		commaNumber(mythicHard)
	)
end

local function requestIncomeSummary(force)
	if incomeMetadataRequest == nil or incomeRefreshInFlight == true then
		return
	end
	if force ~= true and os.clock() < nextIncomeRefreshAt then
		return
	end

	incomeRefreshInFlight = true
	nextIncomeRefreshAt = os.clock() + INCOME_REFRESH_SECONDS

	task.spawn(function()
		local ok, response = pcall(function()
			return incomeMetadataRequest:InvokeServer("afk_world")
		end)
		incomeRefreshInFlight = false

		if ok and typeof(response) == "table" and response.Ready == true and typeof(response.IncomeSnapshot) == "table" then
			local captainLog = response.IncomeSnapshot.CaptainLog
			if typeof(captainLog) == "table" then
				local placedCount = math.max(0, math.floor(tonumber(captainLog.PlacedCount or captainLog.TotalCount) or 0))
				incomeSummary = {
					ready = true,
					status = if placedCount > 0 then "ready" else "empty",
					incomePerSecond = math.max(0, tonumber(captainLog.TotalIncomePerSecond) or 0),
					claimReady = math.max(0, tonumber(captainLog.TotalClaimReadyAmount) or 0),
					placedCount = placedCount,
				}
			else
				incomeSummary = {
					ready = false,
					status = "unavailable",
					incomePerSecond = 0,
					claimReady = 0,
					placedCount = 0,
				}
			end
		else
			incomeSummary = {
				ready = false,
				status = "unavailable",
				incomePerSecond = 0,
				claimReady = 0,
				placedCount = 0,
			}
		end
		render()
	end)
end

local function statCard(props)
	return e("Frame", {
		BackgroundColor3 = props.backgroundColor or CARD,
		BorderSizePixel = 0,
		LayoutOrder = props.layoutOrder or 0,
		Size = UDim2.fromOffset(250, 106),
	}, {
		Corner = e("UICorner", {
			CornerRadius = UDim.new(0, 8),
		}),
		Stroke = e("UIStroke", {
			Color = props.accent or GOLD,
			Thickness = 1,
			Transparency = 0.42,
		}),
		Padding = e("UIPadding", {
			PaddingBottom = UDim.new(0, 12),
			PaddingLeft = UDim.new(0, 14),
			PaddingRight = UDim.new(0, 14),
			PaddingTop = UDim.new(0, 12),
		}),
		Title = e("TextLabel", {
			BackgroundTransparency = 1,
			Font = Enum.Font.GothamMedium,
			Size = UDim2.new(1, -40, 0, 22),
			Text = tostring(props.title or ""),
			TextColor3 = MUTED,
			TextSize = 13,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Center,
		}),
		Icon = if props.icon
			then e("ImageLabel", {
				AnchorPoint = Vector2.new(1, 0),
				BackgroundTransparency = 1,
				Image = tostring(props.icon),
				ImageColor3 = props.iconColor or Color3.fromRGB(255, 255, 255),
				Position = UDim2.fromScale(1, 0),
				ScaleType = Enum.ScaleType.Fit,
				Size = UDim2.fromOffset(28, 28),
			})
			else nil,
		Badge = if props.badge
			then e("TextLabel", {
				AnchorPoint = Vector2.new(1, 0),
				BackgroundColor3 = props.accent or GOLD,
				BorderSizePixel = 0,
				Font = Enum.Font.GothamBlack,
				Position = UDim2.fromScale(1, 0),
				Size = UDim2.fromOffset(44, 24),
				Text = tostring(props.badge),
				TextColor3 = PANEL_DARK,
				TextSize = 10,
			}, {
				Corner = e("UICorner", {
					CornerRadius = UDim.new(0, 6),
				}),
			})
			else nil,
		Value = e("TextLabel", {
			BackgroundTransparency = 1,
			Font = Enum.Font.GothamBold,
			Position = UDim2.fromOffset(0, 29),
			Size = UDim2.new(1, 0, 0, 34),
			Text = tostring(props.value or ""),
			TextColor3 = props.valueColor or TEXT,
			TextScaled = true,
			TextSize = 24,
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Center,
		}, {
			SizeLimit = e("UITextSizeConstraint", {
				MaxTextSize = 24,
				MinTextSize = 12,
			}),
		}),
		Detail = e("TextLabel", {
			BackgroundTransparency = 1,
			Font = Enum.Font.Gotham,
			Position = UDim2.fromOffset(0, 67),
			Size = UDim2.new(1, 0, 0, 26),
			Text = tostring(props.detail or ""),
			TextColor3 = MUTED,
			TextSize = 12,
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Top,
		}),
	})
end

local function wideCard(props)
	local content = props.children
	if content ~= nil then
		content = e("Frame", {
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(0, 25),
			Size = UDim2.new(1, 0, 1, -27),
		}, content)
	else
		content = e("TextLabel", {
			BackgroundTransparency = 1,
			Font = Enum.Font.GothamBold,
			Position = UDim2.fromOffset(0, 25),
			Size = UDim2.new(1, 0, 1, -27),
			Text = tostring(props.body or ""),
			TextColor3 = props.bodyColor or TEXT,
			TextSize = props.bodyTextSize or 15,
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Top,
		})
	end

	return e("Frame", {
		BackgroundColor3 = props.backgroundColor or CARD_ALT,
		BorderSizePixel = 0,
		LayoutOrder = props.layoutOrder or 0,
		Size = UDim2.new(1, 0, 0, props.height or 74),
	}, {
		Corner = e("UICorner", {
			CornerRadius = UDim.new(0, 8),
		}),
		Stroke = e("UIStroke", {
			Color = props.accent or GOLD,
			Thickness = 1,
			Transparency = 0.5,
		}),
		Padding = e("UIPadding", {
			PaddingBottom = UDim.new(0, 12),
			PaddingLeft = UDim.new(0, 14),
			PaddingRight = UDim.new(0, 14),
			PaddingTop = UDim.new(0, 12),
		}),
		Title = e("TextLabel", {
			BackgroundTransparency = 1,
			Font = Enum.Font.GothamMedium,
			Size = UDim2.new(1, if props.icon then -34 else 0, 0, 20),
			Text = tostring(props.title or ""),
			TextColor3 = MUTED,
			TextSize = 13,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Center,
		}),
		Icon = if props.icon
			then e("ImageLabel", {
				AnchorPoint = Vector2.new(1, 0),
				BackgroundTransparency = 1,
				Image = tostring(props.icon),
				Position = UDim2.fromScale(1, 0),
				ScaleType = Enum.ScaleType.Fit,
				Size = UDim2.fromOffset(26, 26),
			})
			else nil,
		Content = content,
	})
end

local function eventsList(events)
	local children = {
		Layout = e("UIListLayout", {
			Padding = UDim.new(0, 6),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	}

	if #events == 0 then
		children.Empty = e("TextLabel", {
			BackgroundTransparency = 1,
			Font = Enum.Font.Gotham,
			LayoutOrder = 1,
			Size = UDim2.new(1, 0, 0, 20),
			Text = "Session events will appear here.",
			TextColor3 = MUTED,
			TextSize = 12,
			TextXAlignment = Enum.TextXAlignment.Left,
		})
	else
		for index, text in ipairs(events) do
			children["Event" .. tostring(index)] = e("TextLabel", {
				BackgroundTransparency = 1,
				Font = Enum.Font.Gotham,
				LayoutOrder = index,
				Size = UDim2.new(1, 0, 0, 20),
				Text = tostring(text),
				TextColor3 = if index == 1 then GOLD_BRIGHT else MUTED,
				TextSize = 12,
				TextTruncate = Enum.TextTruncate.AtEnd,
				TextXAlignment = Enum.TextXAlignment.Left,
			})
		end
	end

	return e("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 134),
	}, children)
end

local function AFKWorldScreen(props)
	if props.visible ~= true then
		return nil
	end

	local state = props.state or {}
	local earnedToday = math.max(0, math.floor(tonumber(state.EarnedToday) or 0))
	local dailyCap = math.max(1, math.floor(tonumber(state.DailyCap) or 1))
	local capReached = state.CapReached == true
	local eligible = state.Eligible == true
	local timerText = if capReached then "--:--" else formatDuration(props.remainingSeconds)
	local timerDetail = if capReached
		then "Daily AFK Gold Chest limit reached."
		elseif eligible
			then "Progress runs while you remain on your active ship."
			else "Return to your active ship area to resume progress."
	local premiumText = if state.IsPremium == true then "Premium Active" else "Standard"
	local premiumDetail = if state.IsPremium == true then "1 Gold Chest every 30 minutes." else "1 Gold Chest every 60 minutes."
	local goldCount = math.max(0, math.floor(tonumber(state.GoldChestCount) or 0))
	local beliAmount = math.max(0, tonumber(state.Beli) or 0)
	local income = props.incomeSummary or {}
	local fallbackIncomeStatus = if income.ready == true then "ready" else "loading"
	local incomeStatus = tostring(income.status or fallbackIncomeStatus)
	local incomeText = if income.ready == true
		then CurrencyUtil.formatCurrencyPerSecond(income.incomePerSecond)
		elseif incomeStatus == "unavailable"
			then "Unavailable"
		else "Loading..."
	local claimText = if income.ready == true
		then CurrencyUtil.formatAmount(income.claimReady)
		elseif incomeStatus == "unavailable"
			then "Unavailable"
		else "Loading..."
	local incomeDetail = if income.ready == true and incomeStatus == "empty"
		then "No placed crewmates are earning right now."
		else string.format("Claim-ready: %s  |  Placed: %s", claimText, commaNumber(income.placedCount or 0))
	local protectionText = props.protectionSummary or "Fleet Shield: Loading..."

	return e("Frame", {
		BackgroundColor3 = Color3.fromRGB(0, 0, 0),
		BackgroundTransparency = 0.28,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 80,
	}, {
		BackgroundImage = e("ImageLabel", {
			BackgroundTransparency = 1,
			Image = BACKGROUND_IMAGE,
			ImageColor3 = Color3.fromRGB(120, 134, 142),
			ImageTransparency = 0.18,
			ScaleType = Enum.ScaleType.Crop,
			Size = UDim2.fromScale(1, 1),
			ZIndex = 80,
		}),
		Shade = e("Frame", {
			BackgroundColor3 = Color3.fromRGB(4, 9, 15),
			BackgroundTransparency = 0.18,
			BorderSizePixel = 0,
			Size = UDim2.fromScale(1, 1),
			ZIndex = 80,
		}),
		Panel = e("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = PANEL,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(1, 1),
			ZIndex = 81,
		}, {
			Padding = e("UIPadding", {
				PaddingBottom = UDim.new(0, 24),
				PaddingLeft = UDim.new(0, 24),
				PaddingRight = UDim.new(0, 24),
				PaddingTop = UDim.new(0, 24),
			}),
			Title = e("TextLabel", {
				BackgroundTransparency = 1,
				Font = Enum.Font.GothamBlack,
				Size = UDim2.new(1, -170, 0, 44),
				Text = "RAYLEIGH TRAINING",
				TextColor3 = GOLD_BRIGHT,
				TextSize = 34,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextYAlignment = Enum.TextYAlignment.Center,
			}),
			Subtitle = e("TextLabel", {
				BackgroundTransparency = 1,
				Font = Enum.Font.Gotham,
				Position = UDim2.fromOffset(1, 46),
				Size = UDim2.new(1, -170, 0, 24),
				Text = "Gold chest training runs only while this screen is active.",
				TextColor3 = MUTED,
				TextSize = 14,
				TextTruncate = Enum.TextTruncate.AtEnd,
				TextXAlignment = Enum.TextXAlignment.Left,
			}),
			Leave = e("TextButton", {
				AnchorPoint = Vector2.new(1, 0),
				AutoButtonColor = true,
				BackgroundColor3 = Color3.fromRGB(120, 42, 40),
				BorderSizePixel = 0,
				Font = Enum.Font.GothamBold,
				Position = UDim2.new(1, 0, 0, 5),
				Size = UDim2.fromOffset(154, 38),
				Text = "Leave Training",
				TextColor3 = TEXT,
				TextSize = 13,
				TextWrapped = true,
				[React.Event.Activated] = props.onLeave,
			}, {
				Corner = e("UICorner", {
					CornerRadius = UDim.new(0, 8),
				}),
				Stroke = e("UIStroke", {
					Color = ROSE,
					Thickness = 1,
					Transparency = 0.25,
				}),
			}),
			Scroll = e("ScrollingFrame", {
				Active = true,
				AutomaticCanvasSize = Enum.AutomaticSize.Y,
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				CanvasSize = UDim2.fromOffset(0, 0),
				Position = UDim2.fromOffset(0, 86),
				ScrollBarImageColor3 = GOLD,
				ScrollBarThickness = 6,
				Size = UDim2.new(1, 0, 1, -86),
			}, {
				Layout = e("UIListLayout", {
					Padding = UDim.new(0, 12),
					SortOrder = Enum.SortOrder.LayoutOrder,
				}),
				Grid = e("Frame", {
					AutomaticSize = Enum.AutomaticSize.Y,
					BackgroundTransparency = 1,
					LayoutOrder = 1,
					Size = UDim2.new(1, -8, 0, 0),
				}, {
					GridLayout = e("UIGridLayout", {
						CellPadding = UDim2.fromOffset(12, 12),
						CellSize = UDim2.new(0.5, -6, 0, 106),
						FillDirectionMaxCells = 2,
						SortOrder = Enum.SortOrder.LayoutOrder,
					}),
					Timer = e(statCard, {
						accent = if capReached then ROSE else GOLD,
						detail = timerDetail,
						icon = CHEST_ICON,
						layoutOrder = 1,
						title = if state.IsPremium == true then "Premium: Next Gold Chest In" else "Next Gold Chest In",
						value = timerText,
						valueColor = if capReached then ROSE else GOLD_BRIGHT,
					}),
					Cap = e(statCard, {
						accent = CYAN,
						detail = if capReached then "Daily limit reached." else "Resets on the next UTC day.",
						badge = "CAP",
						layoutOrder = 2,
						title = "AFK Gold Chests Today",
						value = string.format("%s/%s", commaNumber(earnedToday), commaNumber(dailyCap)),
						valueColor = if capReached then ROSE else CYAN,
					}),
					Premium = e(statCard, {
						accent = if state.IsPremium == true then GOLD else MUTED,
						detail = premiumDetail,
						icon = PREMIUM_ICON,
						layoutOrder = 3,
						title = "Membership",
						value = premiumText,
						valueColor = if state.IsPremium == true then GOLD_BRIGHT else TEXT,
					}),
					Gold = e(statCard, {
						accent = GOLD,
						detail = "Normal Gold chests. Pity advances when opened.",
						icon = CHEST_ICON,
						layoutOrder = 4,
						title = "Gold Chests",
						value = commaNumber(goldCount),
						valueColor = GOLD_BRIGHT,
					}),
					Beli = e(statCard, {
						accent = GREEN,
						detail = "Current Beli balance.",
						icon = BELI_ICON,
						layoutOrder = 5,
						title = "Beli",
						value = CurrencyUtil.formatAmount(beliAmount),
						valueColor = GREEN,
					}),
					Income = e(statCard, {
						accent = ORANGE,
						badge = "SHIP",
						detail = incomeDetail,
						layoutOrder = 6,
						title = "Ship Income",
						value = incomeText,
						valueColor = ORANGE,
					}),
				}),
				Pity = e(wideCard, {
					accent = GOLD,
					body = getGoldPityText(state),
					bodyColor = GOLD_BRIGHT,
					bodyTextSize = 14,
					height = 82,
					icon = FRUIT_ICON,
					layoutOrder = 2,
					title = "Gold Chest Devil Fruit Pity",
				}),
				Protection = e(wideCard, {
					accent = CYAN,
					body = protectionText,
					bodyTextSize = 13,
					height = 74,
					layoutOrder = 3,
					title = "Protection",
				}),
				Events = e(wideCard, {
					accent = GREEN,
					body = "",
					height = 180,
					layoutOrder = 4,
					title = "Recent AFK Session Events",
				}, {
					EventsList = eventsList(props.events or {}),
				}),
			}),
		}),
	})
end

render = function()
	if destroyed == true then
		return
	end
	if renderQueued == true then
		return
	end

	renderQueued = true
	task.defer(function()
		renderQueued = false
		local visible = typeof(currentState) == "table" and currentState.SessionActive == true
		UiModalState.SetOpen(MODAL_STATE_KEY, visible)
		applySessionEffects(visible)
		if visible then
			requestIncomeSummary(false)
			startTimerLoop()
			startHeartbeatLoop()
		end

		root:render(e(AFKWorldScreen, {
			events = recentEvents,
			incomeSummary = incomeSummary,
			onLeave = function()
				if exitRequest == nil then
					PopUpModule:Local_SendPopUp("Training exit is unavailable.", ROSE, POPUP_STROKE, 3, false)
					return
				end

				local ok, response = pcall(function()
					return exitRequest:InvokeServer()
				end)
				if ok and typeof(response) == "table" then
					if typeof(response.State) == "table" then
						currentState = response.State
						stateReceivedAt = os.clock()
						wasSessionActive = response.State.SessionActive == true
						wasCapReached = response.State.CapReached == true
					end
					local message = tostring(response.message or "")
					if message ~= "" then
						PopUpModule:Local_SendPopUp(message, response.ok == true and GOLD_BRIGHT or ROSE, POPUP_STROKE, 3, false)
					end
					addEvent("Session ended.")
					render()
				else
					PopUpModule:Local_SendPopUp("Unable to leave Rayleigh Training right now.", ROSE, POPUP_STROKE, 3, false)
				end
			end,
			protectionSummary = readProtectionSummary(),
			remainingSeconds = getRemainingSeconds(),
			state = currentState,
			visible = visible,
		}))
	end)
end

local function applyState(state)
	if typeof(state) ~= "table" then
		return
	end

	local sessionActive = state.SessionActive == true
	local capReached = state.CapReached == true
	if sessionActive and wasSessionActive ~= true then
		table.clear(recentEvents)
		addEvent("Session started.")
		requestIncomeSummary(true)
	elseif sessionActive and capReached and wasCapReached ~= true then
		addEvent("Daily cap reached.")
	end

	currentState = state
	stateReceivedAt = os.clock()
	wasSessionActive = sessionActive
	wasCapReached = capReached
	render()
end

local function showReward(payload)
	if typeof(payload) ~= "table" then
		return
	end

	local message = tostring(payload.Message or "")
	if message == "" then
		message = if payload.IsPremium == true
			then "Premium AFK Reward: +1 Gold Chest"
			else "AFK Reward: +1 Gold Chest"
	end

	addEvent(message)
	local rewardTier = tostring(payload.RewardTier or "Gold")
	local rewardName = rewardTier .. " Chest"
	PopUpModule:Local_ShowReward({
		{ "1x " .. rewardName, RewardIconResolver.GetIcon(rewardName) },
	})
	PopUpModule:Local_SendPopUp(message, GOLD_BRIGHT, POPUP_STROKE, 3, false)

	if typeof(payload.State) == "table" then
		applyState(payload.State)
	else
		render()
	end
end

local function waitForRemote(parent, name, className, timeoutSeconds)
	local found = parent:FindFirstChild(name)
	if found and found:IsA(className) then
		return found
	end

	found = parent:WaitForChild(name, timeoutSeconds)
	if found and found:IsA(className) then
		return found
	end

	return nil
end

local function requestInitialState()
	if not stateRequest then
		return
	end

	local ok, state = pcall(function()
		return stateRequest:InvokeServer()
	end)
	if ok then
		applyState(state)
	end
end

local function getCurrentSessionToken()
	if screenGui.Parent == nil or screenGui.Enabled ~= true then
		return nil
	end
	if typeof(currentState) ~= "table" or currentState.SessionActive ~= true then
		return nil
	end
	local token = currentState.SessionToken
	if typeof(token) == "string" and token ~= "" then
		return token
	end
	return nil
end

local function hasActiveSession()
	return typeof(currentState) == "table" and currentState.SessionActive == true
end

local function requestSessionExitSilently()
	if silentExitInFlight == true or exitRequest == nil or hasActiveSession() ~= true then
		return
	end

	silentExitInFlight = true
	task.spawn(function()
		local ok, response = pcall(function()
			return exitRequest:InvokeServer()
		end)
		silentExitInFlight = false

		if ok and typeof(response) == "table" and typeof(response.State) == "table" then
			currentState = response.State
			stateReceivedAt = os.clock()
			wasSessionActive = response.State.SessionActive == true
			wasCapReached = response.State.CapReached == true
			render()
		end
	end)
end

local function isVisible()
	return destroyed ~= true and typeof(currentState) == "table" and currentState.SessionActive == true
end

function startTimerLoop()
	if timerLoopRunning == true or isVisible() ~= true then
		return
	end

	timerLoopRunning = true
	task.spawn(function()
		while destroyed ~= true and isVisible() == true do
			render()
			task.wait(1)
		end
		timerLoopRunning = false
	end)
end

function startHeartbeatLoop()
	if heartbeatLoopRunning == true or isVisible() ~= true then
		return
	end

	heartbeatLoopRunning = true
	task.spawn(function()
		while destroyed ~= true and isVisible() == true do
			local interval = 5
			local token = getCurrentSessionToken()
			if token ~= nil and uiHeartbeatEvent ~= nil then
				uiHeartbeatEvent:FireServer(token)
				interval = math.max(2, math.floor(tonumber(currentState.UiHeartbeatIntervalSeconds) or interval))
			end
			task.wait(interval)
		end
		heartbeatLoopRunning = false
	end)
end

local function cleanup()
	if destroyed == true then
		return
	end

	destroyed = true
	requestSessionExitSilently()
	UiModalState.SetOpen(MODAL_STATE_KEY, false)
	applySessionEffects(false)

	for _, connection in ipairs(connections) do
		if connection and connection.Connected then
			connection:Disconnect()
		end
	end
	table.clear(connections)

	pcall(function()
		root:unmount()
	end)
end

local remotes = ReplicatedStorage:WaitForChild("Remotes", 20)
if remotes then
	stateEvent = waitForRemote(remotes, STATE_EVENT_NAME, "RemoteEvent", 20)
	stateRequest = waitForRemote(remotes, STATE_REQUEST_NAME, "RemoteFunction", 20)
	exitRequest = waitForRemote(remotes, EXIT_REQUEST_NAME, "RemoteFunction", 20)
	uiHeartbeatEvent = waitForRemote(remotes, UI_HEARTBEAT_EVENT_NAME, "RemoteEvent", 20)
end

incomeMetadataRequest = waitForRemote(ReplicatedStorage, INCOME_METADATA_REQUEST_NAME, "RemoteFunction", 5)
if incomeMetadataRequest == nil and remotes then
	incomeMetadataRequest = waitForRemote(remotes, INCOME_METADATA_REQUEST_NAME, "RemoteFunction", 2)
end
if incomeMetadataRequest == nil then
	incomeSummary = {
		ready = false,
		status = "unavailable",
		incomePerSecond = 0,
		claimReady = 0,
		placedCount = 0,
	}
end

if stateEvent then
	table.insert(connections, stateEvent.OnClientEvent:Connect(function(action, payload)
		if action == "State" then
			applyState(payload)
		elseif action == "Reward" then
			showReward(payload)
		end
	end))
end

requestInitialState()

table.insert(connections, player.CharacterAdded:Connect(function()
	task.defer(function()
		if typeof(currentState) == "table" and currentState.SessionActive == true then
			controls = nil
			controlsLocked = false
			setMovementLocked(true)
		end
	end)
end))

table.insert(connections, screenGui.Destroying:Connect(cleanup))

table.insert(connections, script.Destroying:Connect(cleanup))

table.insert(connections, screenGui:GetPropertyChangedSignal("Enabled"):Connect(function()
	if screenGui.Enabled ~= true then
		requestSessionExitSilently()
	end
end))
