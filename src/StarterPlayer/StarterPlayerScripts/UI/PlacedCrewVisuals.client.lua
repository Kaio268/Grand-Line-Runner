local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local localPlayer = Players.LocalPlayer
local playerGui = localPlayer:WaitForChild("PlayerGui")
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
local CLIENT_LOD_MODE_ATTRIBUTE = "ClientPlacedCrewLodMode"
local CLIENT_OVERHEAD_ALLOWED_ATTRIBUTE = "ClientPlacedCrewAllowOverhead"
local CLIENT_LOD_OWNER_ATTRIBUTE = "ClientPlacedCrewIsOwner"
local CLIENT_LOD_DISTANCE_ATTRIBUTE = "ClientPlacedCrewDistance"
local UPDATE_INTERVAL_SECONDS = 1
local CLIENT_LOD = ShipVisuals.ClientLod or {}
local OWNER_LOD = CLIENT_LOD.Owner or {}
local NON_OWNER_LOD = CLIENT_LOD.NonOwner or {}
local OWNER_FULL_DISTANCE = math.max(0, tonumber(OWNER_LOD.FullCrewDistance) or 220)
local OWNER_REDUCED_DISTANCE = math.max(OWNER_FULL_DISTANCE, tonumber(OWNER_LOD.ReducedCrewDistance) or 460)
local OWNER_FULL_CAP = math.max(0, math.floor(tonumber(OWNER_LOD.FullCrewCap) or 14))
local NON_OWNER_FULL_DISTANCE = math.max(0, tonumber(NON_OWNER_LOD.FullCrewDistance) or 120)
local NON_OWNER_REDUCED_DISTANCE = math.max(NON_OWNER_FULL_DISTANCE, tonumber(NON_OWNER_LOD.ReducedCrewDistance) or 260)
local NON_OWNER_FULL_CAP = math.max(0, math.floor(tonumber(NON_OWNER_LOD.FullCrewCap) or 8))
local MAX_ANIMATED_CREW = math.max(0, math.floor(tonumber(CLIENT_LOD.AnimatedCrewCap) or 18))
local MAX_AURA_CREW = math.max(0, math.floor(tonumber(CLIENT_LOD.AuraCrewCap) or 10))
local MAX_REDUCED_VISUALS = math.max(0, math.floor(tonumber(CLIENT_LOD.ReducedCrewCap) or 64))
local MAX_OVERHEAD_CREW = math.max(0, math.floor(tonumber(CLIENT_LOD.VisibleCrewOverheadCap) or 24))
local RECENT_PRIORITY_SECONDS = math.max(0, tonumber(CLIENT_LOD.RecentCrewPrioritySeconds) or 8)
local FOCUS_REFRESH_DISTANCE = 18
local MAINTENANCE_REFRESH_INTERVAL_SECONDS = 3
local MONEY_LABEL_NEAR_DISTANCE = 240
local MONEY_LABEL_REFRESH_INTERVAL_SECONDS = 1.5
local REFRESH_BUDGET_SECONDS = 0.004
local REFRESH_MAX_STANDS_PER_FRAME = 6
local VISUAL_BUILD_BUDGET_SECONDS = 0.006
local VISUAL_BUILD_MAX_PER_FRAME = 3
local DIAGNOSTICS_INTERVAL_SECONDS = 2
local BUBBLE_NAME = "ClientPremiumCrewStealProtectionBubble"

local tracked = {}
local refreshBudget = nil
local refreshQueued = false
local refreshConnection = nil
local refreshQueue = {}
local refreshCursor = 1
local visualBuildQueue = {}
local visualBuildQueued = {}
local visualBuildConnection = nil
local diagnosticsFolder = nil
local lastDiagnosticsPublishAt = 0
local diagnostics = {}

local function normalizeName(name)
	return string.lower(tostring(name or "")):gsub("[^%w]", "")
end

local function resetDiagnostics()
	diagnostics = {
		AnimatedCrew = 0,
		AuraCrew = 0,
		FullCrew = 0,
		HiddenCrew = 0,
		NonOwnerFullCrew = 0,
		NonOwnerReducedCrew = 0,
		OwnerFullCrew = 0,
		OwnerReducedCrew = 0,
		OverheadEligibleCrew = 0,
		ReducedCrew = 0,
		TrackedCrew = 0,
		VisualBuildCacheHits = 0,
		VisualBuildCacheMisses = 0,
		VisualBuildQueued = 0,
		VisualBuildQueueSize = 0,
		VisualMaterialized = 0,
	}
end

local function incrementDiagnostic(name, amount)
	diagnostics[name] = (tonumber(diagnostics[name]) or 0) + (amount or 1)
end

local function diagnosticsEnabled()
	return game:GetAttribute("GTRPerformanceDebug") == true or game:GetAttribute("GTRPerformanceCountersEnabled") == true
end

local function getDiagnosticsFolder()
	if diagnosticsFolder and diagnosticsFolder.Parent then
		return diagnosticsFolder
	end

	diagnosticsFolder = Instance.new("Folder")
	diagnosticsFolder.Name = "ShipCrewLodDiagnostics"
	diagnosticsFolder.Parent = playerGui
	return diagnosticsFolder
end

local function publishDiagnostics(force)
	if not diagnosticsEnabled() then
		if diagnosticsFolder then
			diagnosticsFolder:Destroy()
			diagnosticsFolder = nil
		end
		return
	end

	local now = os.clock()
	if not force and now - lastDiagnosticsPublishAt < DIAGNOSTICS_INTERVAL_SECONDS then
		return
	end
	lastDiagnosticsPublishAt = now

	local folder = getDiagnosticsFolder()
	for key, value in pairs(diagnostics) do
		folder:SetAttribute(key, value)
	end
	folder:SetAttribute("LastPublishedAt", Workspace:GetServerTimeNow())
end

local function createRefreshBudget()
	return {
		Animated = 0,
		Aura = 0,
		NonOwnerFull = 0,
		Overhead = 0,
		OwnerFull = 0,
		Reduced = 0,
	}
end

resetDiagnostics()

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

local function isValidDescendantOf(instance, ancestor)
	return instance ~= nil and instance.Parent ~= nil and ancestor ~= nil and instance:IsDescendantOf(ancestor)
end

local function getCachedHandle(record, standModel)
	if typeof(record) == "table" then
		local cached = record.HandleCache
		if cached and cached:IsA("BasePart") and isValidDescendantOf(cached, standModel) then
			incrementDiagnostic("VisualBuildCacheHits")
			return cached
		end
	end

	local handle = findHandle(standModel)
	if typeof(record) == "table" then
		record.HandleCache = handle
		incrementDiagnostic("VisualBuildCacheMisses")
	end
	return handle
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

local function getCachedMoneyLabel(record, standModel)
	if typeof(record) == "table" then
		local cached = record.MoneyLabelCache
		if cached
			and (cached:IsA("TextLabel") or cached:IsA("TextButton") or cached:IsA("TextBox"))
			and isValidDescendantOf(cached, standModel)
		then
			incrementDiagnostic("VisualBuildCacheHits")
			return cached
		end
	end

	local label = findMoneyLabel(standModel)
	if typeof(record) == "table" then
		record.MoneyLabelCache = label
		incrementDiagnostic("VisualBuildCacheMisses")
	end
	return label
end

local function clearRecordCaches(record)
	if typeof(record) ~= "table" then
		return
	end
	record.HandleCache = nil
	record.MoneyLabelCache = nil
	record.PendingMode = nil
	record.PendingVisualKey = nil
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

local function disableStaticVisualEffects(model)
	for _, descendant in ipairs(model:GetDescendants()) do
		if
			descendant:IsA("ParticleEmitter")
			or descendant:IsA("Beam")
			or descendant:IsA("Trail")
			or descendant:IsA("Highlight")
			or descendant:IsA("LayerCollector")
		then
			descendant.Enabled = false
		elseif descendant:IsA("BasePart") then
			descendant.CastShadow = false
		end
	end
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
	record.EffectsKey = nil
	record.PendingMode = nil
	record.PendingVisualKey = nil
end

local function placeClone(record, standModel, clone)
	local handle = getCachedHandle(record, standModel)
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

local function setOverheadEligible(clone, allowed)
	clone:SetAttribute(CLIENT_OVERHEAD_ALLOWED_ATTRIBUTE, allowed == true)
	if allowed then
		if not CollectionService:HasTag(clone, CrewOverhead.Tag) then
			CollectionService:AddTag(clone, CrewOverhead.Tag)
		end
	else
		CollectionService:RemoveTag(clone, CrewOverhead.Tag)
	end
end

local function getEffectsKey(record, mode)
	local lod = record.Lod or {}
	return table.concat({
		tostring(mode or ""),
		tostring(lod.Animated == true),
		tostring(lod.AuraQuality or ""),
	}, "|")
end

local function applyVisualLod(record, standModel, clone, mode)
	local lod = record.Lod or {}
	clone:SetAttribute(CLIENT_LOD_MODE_ATTRIBUTE, mode)
	clone:SetAttribute(CLIENT_LOD_OWNER_ATTRIBUTE, lod.IsOwner == true)
	clone:SetAttribute(CLIENT_LOD_DISTANCE_ATTRIBUTE, math.floor((tonumber(lod.Distance) or 0) + 0.5))
	setOverheadEligible(clone, lod.AllowOverhead == true)

	local effectsKey = getEffectsKey(record, mode)
	if record.EffectsKey == effectsKey then
		return
	end
	record.EffectsKey = effectsKey

	if mode ~= "full" then
		CrewIdleAnimator.PrepareStatic(clone)
		CrewAuraVisuals.Remove(clone)
		disableStaticVisualEffects(clone)
		return
	end

	task.defer(function()
		if record.Clone ~= clone or record.Mode ~= "full" or not clone.Parent or not standModel.Parent then
			return
		end
		if record.EffectsKey ~= effectsKey then
			return
		end

		local crewId = tostring(standModel:GetAttribute(ATTR.CanonicalName) or standModel:GetAttribute(ATTR.CrewMemberName) or "")
		local variant = tostring(standModel:GetAttribute(ATTR.Variant) or "Normal")
		if lod.AuraQuality then
			CrewAuraVisuals.Refresh(clone, {
				CrewMemberId = crewId,
				Quality = lod.AuraQuality,
				Source = "ClientPlacedCrewVisual",
				Variant = variant,
			})
		else
			CrewAuraVisuals.Remove(clone)
		end
		if lod.Animated == true then
			CrewIdleAnimator.Start(clone, {
				CrewMemberId = crewId,
				Source = "ClientPlacedCrewVisual",
			})
		else
			CrewIdleAnimator.PrepareStatic(clone)
		end
	end)
end

local function ensureVisual(record, mode, allowMaterialize)
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
	if record.Clone and record.VisualKey == visualKey then
		copyOverheadAttributes(standModel, record.Clone)
		placeClone(record, standModel, record.Clone)
		applyProtectionBubble(record.Clone)
		record.Mode = mode
		record.PendingMode = nil
		record.PendingVisualKey = nil
		applyVisualLod(record, standModel, record.Clone, mode)
		return
	end

	stopVisual(record)
	if allowMaterialize ~= true then
		record.PendingMode = mode
		record.PendingVisualKey = visualKey
		return "queued"
	end

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
	if not placeClone(record, standModel, clone) then
		clone:Destroy()
		return
	end

	applyProtectionBubble(clone)
	record.Clone = clone
	record.Mode = mode
	record.VisualKey = visualKey
	record.EffectsKey = nil
	record.PendingMode = nil
	record.PendingVisualKey = nil
	incrementDiagnostic("VisualMaterialized")
	applyVisualLod(record, standModel, clone, mode)
end

local function isRecentlyImportant(record)
	return RECENT_PRIORITY_SECONDS > 0 and os.clock() - (tonumber(record.LastChangedAt) or 0) <= RECENT_PRIORITY_SECONDS
end

local function reserveOverheadBudget()
	if not refreshBudget or refreshBudget.Overhead >= MAX_OVERHEAD_CREW then
		return false
	end
	refreshBudget.Overhead += 1
	incrementDiagnostic("OverheadEligibleCrew")
	return true
end

local function reserveAuraBudget()
	if not refreshBudget or refreshBudget.Aura >= MAX_AURA_CREW then
		return false
	end
	refreshBudget.Aura += 1
	incrementDiagnostic("AuraCrew")
	return true
end

local function resolveMode(record, focusPosition)
	local standModel = record.StandModel
	record.Lod = nil
	incrementDiagnostic("TrackedCrew")
	if not standModel or standModel.Parent == nil or standModel:GetAttribute(ATTR.Active) ~= true then
		incrementDiagnostic("HiddenCrew")
		return "hidden"
	end

	local handle = getCachedHandle(record, standModel)
	if not handle then
		incrementDiagnostic("HiddenCrew")
		return "hidden"
	end

	local ownerUserId = tonumber(standModel:GetAttribute(ATTR.OwnerUserId)) or 0
	local isOwner = ownerUserId == localPlayer.UserId
	local isCaptain = standModel:GetAttribute(ATTR.IsCaptain) == true
	local recent = isRecentlyImportant(record)
	local distance = (handle.Position - focusPosition).Magnitude
	local fullDistance = if isOwner then OWNER_FULL_DISTANCE else NON_OWNER_FULL_DISTANCE
	local reducedDistance = if isOwner then OWNER_REDUCED_DISTANCE else NON_OWNER_REDUCED_DISTANCE
	local fullCap = if isOwner then OWNER_FULL_CAP else NON_OWNER_FULL_CAP
	local fullCountKey = if isOwner then "OwnerFull" else "NonOwnerFull"

	if distance > reducedDistance then
		incrementDiagnostic("HiddenCrew")
		return "hidden"
	end

	local canTryFull = distance <= fullDistance or isCaptain or recent
	local fullCount = if refreshBudget then refreshBudget[fullCountKey] else fullCap
	if
		canTryFull
		and fullCount < fullCap
		and refreshBudget
		and refreshBudget.Animated < MAX_ANIMATED_CREW
	then
		refreshBudget[fullCountKey] = fullCount + 1
		refreshBudget.Animated += 1
		incrementDiagnostic("AnimatedCrew")
		incrementDiagnostic("FullCrew")
		incrementDiagnostic(if isOwner then "OwnerFullCrew" else "NonOwnerFullCrew")

		local auraQuality = nil
		if reserveAuraBudget() then
			auraQuality = if isOwner then "Full" else "Medium"
		end
		record.Lod = {
			AllowOverhead = reserveOverheadBudget(),
			Animated = true,
			AuraQuality = auraQuality,
			Distance = distance,
			IsOwner = isOwner,
		}
		return "full"
	end

	if refreshBudget and refreshBudget.Reduced < MAX_REDUCED_VISUALS then
		refreshBudget.Reduced += 1
		incrementDiagnostic("ReducedCrew")
		incrementDiagnostic(if isOwner then "OwnerReducedCrew" else "NonOwnerReducedCrew")
		record.Lod = {
			AllowOverhead = false,
			Animated = false,
			AuraQuality = nil,
			Distance = distance,
			IsOwner = isOwner,
		}
		return "reduced"
	end

	incrementDiagnostic("HiddenCrew")
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

	local handle = getCachedHandle(record, standModel)
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

	local label = getCachedMoneyLabel(record, standModel)
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
	local handle = getCachedHandle(record, standModel)
	local distance = if handle then (handle.Position - focusPosition).Magnitude else OWNER_REDUCED_DISTANCE + 1000

	local priority = distance
	if isOwner then
		priority -= 10000
	end
	if isCaptain then
		priority -= 2000
	end
	if isRecentlyImportant(record) then
		priority -= 1200
	end
	return priority
end

local processVisualBuildQueue

local function clearVisualBuildConnection()
	if visualBuildConnection then
		visualBuildConnection:Disconnect()
		visualBuildConnection = nil
	end
end

local function ensureVisualBuildConnection()
	if visualBuildConnection then
		return
	end

	visualBuildConnection = RunService.Heartbeat:Connect(function()
		processVisualBuildQueue()
	end)
end

local function enqueueVisualBuild(record)
	if typeof(record) ~= "table" or visualBuildQueued[record] == true then
		return
	end

	visualBuildQueued[record] = true
	visualBuildQueue[#visualBuildQueue + 1] = record
	incrementDiagnostic("VisualBuildQueued")
	diagnostics.VisualBuildQueueSize = #visualBuildQueue
	ensureVisualBuildConnection()
end

processVisualBuildQueue = function()
	local startedAt = os.clock()
	local processed = 0
	while
		#visualBuildQueue > 0
		and processed < VISUAL_BUILD_MAX_PER_FRAME
		and (os.clock() - startedAt) < VISUAL_BUILD_BUDGET_SECONDS
	do
		local record = table.remove(visualBuildQueue, 1)
		visualBuildQueued[record] = nil
		processed += 1

		local standModel = record and record.StandModel
		if not standModel or standModel.Parent == nil then
			if record then
				stopVisual(record)
			end
		elseif record.PendingMode and record.PendingVisualKey then
			ensureVisual(record, record.PendingMode, true)
		end
	end

	diagnostics.VisualBuildQueueSize = #visualBuildQueue
	if #visualBuildQueue <= 0 then
		clearVisualBuildConnection()
	end
	publishDiagnostics(false)
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
	publishDiagnostics(false)
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
			local visualResult = ensureVisual(record, mode, false)
			if visualResult == "queued" then
				enqueueVisualBuild(record)
			end
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
	refreshBudget = createRefreshBudget()
	resetDiagnostics()
	diagnostics.VisualBuildQueueSize = #visualBuildQueue
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
	visualBuildQueued[record] = nil
	clearRecordCaches(record)
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
		LastChangedAt = os.clock(),
	}
	tracked[standModel] = record

	for _, attributeName in pairs(ATTR) do
		record.Connections[#record.Connections + 1] = standModel:GetAttributeChangedSignal(attributeName):Connect(function()
			record.LastChangedAt = os.clock()
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
	clearVisualBuildConnection()
	table.clear(visualBuildQueue)
	table.clear(visualBuildQueued)
	for standModel, record in pairs(tracked) do
		disconnectRecord(record)
		tracked[standModel] = nil
	end
end)
