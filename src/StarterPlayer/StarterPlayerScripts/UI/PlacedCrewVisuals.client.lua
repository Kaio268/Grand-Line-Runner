local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local localPlayer = Players.LocalPlayer
local Modules = ReplicatedStorage:WaitForChild("Modules")

local CrewAuraVisuals = require(Modules:WaitForChild("Crew"):WaitForChild("CrewAuraVisuals"))
local CrewIdleAnimator = require(Modules:WaitForChild("Crew"):WaitForChild("CrewIdleAnimator"))
local CrewOverhead = require(Modules:WaitForChild("Crew"):WaitForChild("CrewOverhead"))
local CrewRegistry = require(Modules:WaitForChild("Crew"):WaitForChild("CrewRegistry"))
local CurrencyUtil = require(Modules:WaitForChild("CurrencyUtil"))
local PlacedCrewState = require(Modules:WaitForChild("Crew"):WaitForChild("PlacedCrewState"))
local ShipVisuals = require(Modules:WaitForChild("Configs"):WaitForChild("ShipVisuals"))

local ATTR = PlacedCrewState.Attribute
local OVERHEAD_ATTR = CrewOverhead.Attribute
local CLIENT_VISUAL_ATTRIBUTE = "ClientPlacedCrewVisual"
local UPDATE_INTERVAL_SECONDS = 1
local FULL_DISTANCE = 180
local REDUCED_DISTANCE = 350
local MAX_FULL_VISUALS = 36
local MAX_REDUCED_VISUALS = 96
local FOCUS_REFRESH_DISTANCE = 18
local MAINTENANCE_REFRESH_INTERVAL_SECONDS = 3
local MONEY_LABEL_NEAR_DISTANCE = 240
local MONEY_LABEL_REFRESH_INTERVAL_SECONDS = 1.5
local REFRESH_BUDGET_SECONDS = 0.004
local REFRESH_MAX_STANDS_PER_FRAME = 6
local BUBBLE_NAME = "ClientPremiumCrewStealProtectionBubble"

local tracked = {}
local fullVisualCount = 0
local reducedVisualCount = 0
local refreshQueued = false
local refreshConnection = nil
local refreshQueue = {}
local refreshCursor = 1

local function normalizeName(name)
	return string.lower(tostring(name or "")):gsub("[^%w]", "")
end

local function findHandle(standModel)
	local handle = standModel and standModel:FindFirstChild("Handle")
	if handle and handle:IsA("BasePart") then
		return handle
	end

	handle = standModel and standModel:FindFirstChild("Handle", true)
	if handle and handle:IsA("BasePart") then
		return handle
	end

	return nil
end

local function findMoneyLabel(standModel)
	if not standModel then
		return nil
	end

	for _, descendant in ipairs(standModel:GetDescendants()) do
		if descendant:IsA("TextLabel") or descendant:IsA("TextButton") or descendant:IsA("TextBox") then
			local normalized = normalizeName(descendant.Name)
			if normalized == "money" or normalized == "beli" or normalized == "amount" then
				return descendant
			end
		end
	end

	return nil
end

local function getFocusPosition()
	local character = localPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root.Position
	end

	local camera = Workspace.CurrentCamera
	return camera and camera.CFrame.Position or Vector3.zero
end

local function resolveTemplate(standModel)
	local baseName = tostring(standModel:GetAttribute(ATTR.BaseName) or "")
	local variant = tostring(standModel:GetAttribute(ATTR.Variant) or "Normal")
	local canonicalName = tostring(standModel:GetAttribute(ATTR.CanonicalName) or "")
	local crewMemberName = tostring(standModel:GetAttribute(ATTR.CrewMemberName) or "")

	local template = nil
	if baseName ~= "" then
		template = CrewRegistry.GetTemplateWithFallback(baseName, variant)
	end
	if not template and canonicalName ~= "" then
		template = CrewRegistry.GetTemplateWithFallback(canonicalName, variant)
	end
	if not template and crewMemberName ~= "" then
		template = CrewRegistry.GetTemplateWithFallback(crewMemberName, variant)
	end

	return template
end

local function getVisualKey(standModel)
	return table.concat({
		tostring(standModel:GetAttribute(ATTR.CrewMemberInstanceId) or ""),
		tostring(standModel:GetAttribute(ATTR.CanonicalName) or standModel:GetAttribute(ATTR.CrewMemberName) or ""),
		tostring(standModel:GetAttribute(ATTR.BaseName) or ""),
		tostring(standModel:GetAttribute(ATTR.Variant) or "Normal"),
	}, "|")
end

local function ensurePrimaryPart(model)
	if model.PrimaryPart and model.PrimaryPart:IsA("BasePart") then
		return model.PrimaryPart
	end

	local primary = model:FindFirstChildWhichIsA("BasePart", true)
	if primary then
		pcall(function()
			model.PrimaryPart = primary
		end)
	end
	return primary
end

local function prepareLocalVisual(model)
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BaseScript") or descendant:IsA("ModuleScript") or descendant:IsA("Sound") then
			descendant:Destroy()
		elseif descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = false
			descendant.CanTouch = false
			descendant.CanQuery = false
			descendant.AssemblyLinearVelocity = Vector3.zero
			descendant.AssemblyAngularVelocity = Vector3.zero
		end
	end
	ensurePrimaryPart(model)
end

local function copyOverheadAttributes(standModel, clone)
	local displayName = tostring(standModel:GetAttribute(ATTR.DisplayName) or "Crewmate")
	local rarity = tostring(standModel:GetAttribute(ATTR.Rarity) or "Common")
	local variant = tostring(standModel:GetAttribute(ATTR.Variant) or "Normal")

	clone:SetAttribute(OVERHEAD_ATTR.Kind, CrewOverhead.Kind.Placed)
	clone:SetAttribute(OVERHEAD_ATTR.DisplayName, displayName)
	clone:SetAttribute(OVERHEAD_ATTR.Rarity, rarity)
	clone:SetAttribute(OVERHEAD_ATTR.Variant, variant)
	clone:SetAttribute(OVERHEAD_ATTR.IncomePerSecond, tonumber(standModel:GetAttribute(ATTR.IncomePerSecond)) or 0)
	clone:SetAttribute(OVERHEAD_ATTR.BeliBoosted, standModel:GetAttribute(ATTR.BeliBoosted) == true)
	clone:SetAttribute(OVERHEAD_ATTR.SlotBonusLabel, standModel:GetAttribute(ATTR.SlotBonusLabel))
	clone:SetAttribute(OVERHEAD_ATTR.SlotBonusPercent, tonumber(standModel:GetAttribute(ATTR.SlotBonusPercent)) or 0)
	clone:SetAttribute(OVERHEAD_ATTR.InstanceId, standModel:GetAttribute(ATTR.CrewMemberInstanceId))
	clone:SetAttribute(OVERHEAD_ATTR.ProtectionType, tostring(standModel:GetAttribute(ATTR.ProtectionType) or "none"))
	clone:SetAttribute(OVERHEAD_ATTR.ProtectionLabel, tostring(standModel:GetAttribute(ATTR.ProtectionLabel) or ""))
	clone:SetAttribute(OVERHEAD_ATTR.ProtectionDetail, tostring(standModel:GetAttribute(ATTR.ProtectionDetail) or ""))
end

local function destroyProtectionBubble(clone)
	local existing = clone and clone:FindFirstChild(BUBBLE_NAME)
	if existing then
		existing:Destroy()
	end
end

local function applyProtectionBubble(clone)
	local protectionType = tostring(clone:GetAttribute(OVERHEAD_ATTR.ProtectionType) or "none")
	if protectionType == "none" or protectionType == "" or protectionType == "permanent" then
		destroyProtectionBubble(clone)
		return
	end

	local existing = clone:FindFirstChild(BUBBLE_NAME)
	local bubble = if existing and existing:IsA("Part") then existing else nil
	if existing and not bubble then
		existing:Destroy()
	end

	local boxCFrame, boxSize = clone:GetBoundingBox()
	local diameter = math.max(boxSize.X, boxSize.Y, boxSize.Z, 3) + 1.2
	if not bubble then
		bubble = Instance.new("Part")
		bubble.Name = BUBBLE_NAME
		bubble.Shape = Enum.PartType.Ball
		bubble.Material = Enum.Material.ForceField
		bubble.Parent = clone
	end

	bubble.Color = if protectionType == "crew" then Color3.fromRGB(111, 230, 124) else Color3.fromRGB(85, 205, 255)
	bubble.Transparency = 0.58
	bubble.Anchored = true
	bubble.CanCollide = false
	bubble.CanTouch = false
	bubble.CanQuery = false
	bubble.CastShadow = false
	bubble.Size = Vector3.new(diameter, diameter, diameter)
	bubble.CFrame = boxCFrame
end

local function stopVisual(record)
	if record.Clone then
		CrewIdleAnimator.Stop(record.Clone, 0, "lod_removed")
		CollectionService:RemoveTag(record.Clone, CrewOverhead.Tag)
		record.Clone:Destroy()
	end
	record.Clone = nil
	record.Mode = nil
	record.VisualKey = nil
end

local function placeClone(standModel, clone)
	local handle = findHandle(standModel)
	if not handle then
		return false
	end

	local placementCFrame = PlacedCrewState.GetPlacementCFrame(
		clone,
		handle,
		tonumber(ShipVisuals.ShipCrewPlacementRotationOffsetDegrees) or 0
	)
	if placementCFrame then
		clone:PivotTo(placementCFrame)
		return true
	end
	return false
end

local function scheduleFullVisualEffects(record, standModel, clone)
	task.defer(function()
		if record.Clone ~= clone or record.Mode ~= "full" or not clone.Parent or not standModel.Parent then
			return
		end

		local crewId = tostring(standModel:GetAttribute(ATTR.CanonicalName) or standModel:GetAttribute(ATTR.CrewMemberName) or "")
		local variant = tostring(standModel:GetAttribute(ATTR.Variant) or "Normal")
		CrewAuraVisuals.Refresh(clone, {
			CrewMemberId = crewId,
			Variant = variant,
			Source = "ClientPlacedCrewVisual",
		})
		CrewIdleAnimator.Start(clone, {
			CrewMemberId = crewId,
			Source = "ClientPlacedCrewVisual",
		})
	end)
end

local function ensureVisual(record, mode)
	local standModel = record.StandModel
	if not standModel or standModel.Parent == nil then
		stopVisual(record)
		return
	end

	if mode == "hidden" then
		stopVisual(record)
		return
	end

	local visualKey = getVisualKey(standModel)
	if record.Clone and record.Mode == mode and record.VisualKey == visualKey then
		copyOverheadAttributes(standModel, record.Clone)
		placeClone(standModel, record.Clone)
		applyProtectionBubble(record.Clone)
		return
	end

	stopVisual(record)
	local template = resolveTemplate(standModel)
	if not template or not template:IsA("Model") then
		return
	end

	local clone = template:Clone()
	clone.Name = "PlacedCrewMember"
	clone:SetAttribute(CLIENT_VISUAL_ATTRIBUTE, true)
	prepareLocalVisual(clone)
	copyOverheadAttributes(standModel, clone)
	clone.Parent = standModel
	if not placeClone(standModel, clone) then
		clone:Destroy()
		return
	end

	applyProtectionBubble(clone)
	CollectionService:AddTag(clone, CrewOverhead.Tag)
	record.Clone = clone
	record.Mode = mode
	record.VisualKey = visualKey
	if mode == "full" then
		scheduleFullVisualEffects(record, standModel, clone)
	end
end

local function resolveMode(record, focusPosition)
	local standModel = record.StandModel
	if not standModel or standModel.Parent == nil or standModel:GetAttribute(ATTR.Active) ~= true then
		return "hidden"
	end

	if tonumber(standModel:GetAttribute(ATTR.OwnerUserId)) == localPlayer.UserId then
		return "full"
	end

	local handle = findHandle(standModel)
	if not handle then
		return "hidden"
	end

	local distance = (handle.Position - focusPosition).Magnitude
	if distance <= FULL_DISTANCE and fullVisualCount < MAX_FULL_VISUALS then
		fullVisualCount += 1
		return "full"
	end
	if distance <= REDUCED_DISTANCE and reducedVisualCount < MAX_REDUCED_VISUALS then
		reducedVisualCount += 1
		return "reduced"
	end

	return "hidden"
end

local function shouldRefreshMoneyLabel(record, standModel, mode, focusPosition)
	if mode == "hidden" then
		return false
	end

	local ownerUserId = tonumber(standModel:GetAttribute(ATTR.OwnerUserId)) or 0
	if ownerUserId == localPlayer.UserId then
		return true
	end

	local handle = findHandle(standModel)
	if not handle then
		return false
	end

	if (handle.Position - focusPosition).Magnitude > MONEY_LABEL_NEAR_DISTANCE then
		return false
	end

	local now = os.clock()
	local lastRefresh = tonumber(record.LastMoneyRefreshAt) or 0
	if now - lastRefresh >= MONEY_LABEL_REFRESH_INTERVAL_SECONDS then
		record.LastMoneyRefreshAt = now
		return true
	end

	local amountKey = table.concat({
		tostring(standModel:GetAttribute(ATTR.ClaimReadyAmount) or ""),
		tostring(standModel:GetAttribute(ATTR.ClaimIncomePerSecond) or ""),
		tostring(standModel:GetAttribute(ATTR.IncomeUpdatedAtUnix) or ""),
	}, "|")
	if amountKey ~= record.LastMoneyAmountKey then
		record.LastMoneyAmountKey = amountKey
		record.LastMoneyRefreshAt = now
		return true
	end

	return false
end

local function updateMoneyLabel(record, standModel, mode, focusPosition)
	if not standModel or standModel:GetAttribute(ATTR.Active) ~= true then
		return
	end
	if not shouldRefreshMoneyLabel(record, standModel, mode, focusPosition) then
		return
	end

	local label = findMoneyLabel(standModel)
	if not label then
		return
	end

	local baseAmount = math.max(0, tonumber(standModel:GetAttribute(ATTR.ClaimReadyAmount)) or 0)
	local incomePerSecond = math.max(0, tonumber(standModel:GetAttribute(ATTR.ClaimIncomePerSecond)) or 0)
	local updatedAtUnix = math.max(0, tonumber(standModel:GetAttribute(ATTR.IncomeUpdatedAtUnix)) or 0)
	local elapsed = if updatedAtUnix > 0 then math.max(0, Workspace:GetServerTimeNow() - updatedAtUnix) else 0
	local amount = baseAmount + (incomePerSecond * elapsed)
	local text = CurrencyUtil.formatIncomeCompactAmount(amount)
	if label.Text ~= text then
		label.TextWrapped = true
		label.Text = text
	end
end

local function getRecordPriority(record, focusPosition)
	local standModel = record.StandModel
	if not standModel or standModel.Parent == nil then
		return math.huge
	end

	local ownerUserId = tonumber(standModel:GetAttribute(ATTR.OwnerUserId)) or 0
	local isOwner = ownerUserId == localPlayer.UserId
	local isCaptain = standModel:GetAttribute(ATTR.IsCaptain) == true
	local handle = findHandle(standModel)
	local distance = if handle then (handle.Position - focusPosition).Magnitude else REDUCED_DISTANCE + 1000

	local priority = distance
	if isOwner then
		priority -= 10000
	end
	if isCaptain then
		priority -= 2000
	end
	return priority
end

local function clearRefreshConnection()
	if refreshConnection then
		refreshConnection:Disconnect()
		refreshConnection = nil
	end
end

local processRefreshQueue

local function finishRefreshQueue()
	refreshQueued = false
	refreshQueue = {}
	refreshCursor = 1
	clearRefreshConnection()
end

processRefreshQueue = function()
	local startedAt = os.clock()
	local processed = 0
	local focusPosition = getFocusPosition()

	while
		refreshCursor <= #refreshQueue
		and processed < REFRESH_MAX_STANDS_PER_FRAME
		and (os.clock() - startedAt) < REFRESH_BUDGET_SECONDS
	do
		local record = refreshQueue[refreshCursor]
		refreshCursor += 1
		processed += 1

		local standModel = record and record.StandModel
		if not standModel or standModel.Parent == nil then
			if record then
				stopVisual(record)
			end
			if standModel then
				tracked[standModel] = nil
			end
		else
			local mode = resolveMode(record, focusPosition)
			ensureVisual(record, mode)
			updateMoneyLabel(record, standModel, mode, focusPosition)
		end
	end

	if refreshCursor > #refreshQueue then
		finishRefreshQueue()
	end
end

local function ensureRefreshConnection()
	if refreshConnection then
		return
	end

	refreshConnection = RunService.Heartbeat:Connect(processRefreshQueue)
end

local function requestRefresh()
	if refreshQueued then
		return
	end

	refreshQueued = true
	refreshCursor = 1
	fullVisualCount = 0
	reducedVisualCount = 0
	local focusPosition = getFocusPosition()
	refreshQueue = {}
	for _, record in pairs(tracked) do
		refreshQueue[#refreshQueue + 1] = record
	end
	table.sort(refreshQueue, function(left, right)
		return getRecordPriority(left, focusPosition) < getRecordPriority(right, focusPosition)
	end)

	if #refreshQueue == 0 then
		finishRefreshQueue()
		return
	end

	ensureRefreshConnection()
end

local function disconnectRecord(record)
	for _, connection in ipairs(record.Connections) do
		connection:Disconnect()
	end
	table.clear(record.Connections)
	stopVisual(record)
end

local function trackStand(standModel)
	if tracked[standModel] or not standModel:IsA("Model") then
		return
	end

	local record = {
		StandModel = standModel,
		Connections = {},
		Clone = nil,
		Mode = nil,
		LastMoneyAmountKey = nil,
		LastMoneyRefreshAt = 0,
	}
	tracked[standModel] = record

	for _, attributeName in pairs(ATTR) do
		record.Connections[#record.Connections + 1] = standModel:GetAttributeChangedSignal(attributeName):Connect(function()
			requestRefresh()
		end)
	end
	record.Connections[#record.Connections + 1] = standModel.AncestryChanged:Connect(function(_, parent)
		if parent == nil then
			disconnectRecord(record)
			tracked[standModel] = nil
		end
	end)

	requestRefresh()
end

local function untrackStand(standModel)
	local record = tracked[standModel]
	if not record then
		return
	end

	disconnectRecord(record)
	tracked[standModel] = nil
end

for _, standModel in ipairs(CollectionService:GetTagged(PlacedCrewState.Tag)) do
	trackStand(standModel)
end

local addedConnection = CollectionService:GetInstanceAddedSignal(PlacedCrewState.Tag):Connect(trackStand)
local removedConnection = CollectionService:GetInstanceRemovedSignal(PlacedCrewState.Tag):Connect(untrackStand)

task.spawn(function()
	local lastFocusPosition = getFocusPosition()
	local lastMaintenanceRefreshAt = 0
	while true do
		task.wait(UPDATE_INTERVAL_SECONDS)
		local focusPosition = getFocusPosition()
		local moved = (focusPosition - lastFocusPosition).Magnitude >= FOCUS_REFRESH_DISTANCE
		local maintenanceDue = os.clock() - lastMaintenanceRefreshAt >= MAINTENANCE_REFRESH_INTERVAL_SECONDS
		if moved or maintenanceDue then
			lastFocusPosition = focusPosition
			lastMaintenanceRefreshAt = os.clock()
			requestRefresh()
		end
	end
end)

script.Destroying:Connect(function()
	addedConnection:Disconnect()
	removedConnection:Disconnect()
	clearRefreshConnection()
	for standModel, record in pairs(tracked) do
		disconnectRecord(record)
		tracked[standModel] = nil
	end
end)
