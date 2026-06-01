local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Interaction = {}
local Modules = ReplicatedStorage:WaitForChild("Modules")
local CarriedRewardVisuals = require(Modules:WaitForChild("CarriedRewardVisuals"))
local CrewCatalog = require(Modules:WaitForChild("Crew"):WaitForChild("CrewCatalog"))
local CrewOverhead = require(Modules:WaitForChild("Crew"):WaitForChild("CrewOverhead"))
local activeContext = nil
local carrySlotAdapter = nil
local HORO_PROJECTION_CARRY_ATTRIBUTE = "HoroProjectionCarryProjectionId"
local TUTORIAL_CREW_MEMBER_ATTRIBUTE = "TutorialCrewMember"
local TUTORIAL_OWNER_ATTRIBUTE = "TutorialOwnerUserId"
local TUTORIAL_TOKEN_ATTRIBUTE = "TutorialToken"
local TUTORIAL_REWARD_NAME_ATTRIBUTE = "TutorialRewardName"
local CARRIED_MODEL_ATTRIBUTE = "CrewCarryHeld"
local CARRIED_CREW_MEMBER_ATTRIBUTE = "CarriedCrewMember"
local CARRIED_CREW_MEMBER_IMAGE_ATTRIBUTE = "CarriedCrewMemberImage"
local OVERHEAD_ATTRIBUTES = CrewOverhead.Attribute
local CREW_MEMBERS_WORLD_FOLDER_NAME = "CrewMembersWorld"
local CARRY_ASSEMBLY_WELD_NAME = "CrewCarryAssemblyWeld"
local CARRY_ATTACHMENT_WELD_NAME = "CrewCarryAttachmentWeld"
local CARRY_ROOT_REPAIR_DISTANCE = 2
local CARRY_PART_REPAIR_DISTANCE = 3
local CARRY_MAINTENANCE_INTERVAL = 0.2
local CARRY_VISUAL_SPACING = CarriedRewardVisuals.DefaultSpacing
local carryMaintenanceEntries = {}
local carryMaintenanceConnection = nil
local carryMaintenanceElapsed = 0

local function normalizeCarriedAttribute(value)
	if typeof(value) == "string" and value ~= "" then
		return value
	end
	if value ~= nil and typeof(value) ~= "string" then
		return tostring(value)
	end
	return nil
end

local function clearCarriedCrewMemberAttributes(player)
	player:SetAttribute(CARRIED_CREW_MEMBER_ATTRIBUTE, nil)
	player:SetAttribute(CARRIED_CREW_MEMBER_IMAGE_ATTRIBUTE, nil)
end

local function setCarriedCrewMemberAttributes(player, crewMemberData)
	local carriedName = normalizeCarriedAttribute(crewMemberData and (crewMemberData.DisplayName or crewMemberData.CrewMemberId))
	if not carriedName then
		clearCarriedCrewMemberAttributes(player)
		return
	end

	player:SetAttribute(CARRIED_CREW_MEMBER_ATTRIBUTE, carriedName)

	local carriedImage = normalizeCarriedAttribute(crewMemberData and crewMemberData.Image)
	player:SetAttribute(CARRIED_CREW_MEMBER_IMAGE_ATTRIBUTE, carriedImage)
end

function Interaction.SetCarrySlotAdapter(adapter)
	carrySlotAdapter = if typeof(adapter) == "table" then adapter else nil
end

local function getCrewMemberInfoFromState(st)
	local entry = st and st.Entry
	local info = entry and entry.Info
	if typeof(info) == "table" then
		return info
	end
	if entry and entry.Id then
		return CrewCatalog.GetInfoById(entry.Id)
	end
	return nil
end

local function resolveCanonicalCrewMemberData(model, st)
	local info = getCrewMemberInfoFromState(st)
	if not info and model then
		local modelCrewMemberId = normalizeCarriedAttribute(model:GetAttribute("CrewMemberId"))
		if modelCrewMemberId then
			info = CrewCatalog.GetInfoById(modelCrewMemberId)
		end
	end

	local crewMemberId = normalizeCarriedAttribute(info and info.CrewMemberId)
		or normalizeCarriedAttribute(model and model:GetAttribute("CrewMemberId"))
	local displayInfo = CrewCatalog.GetDisplayInfo(crewMemberId, info)
	local displayName = normalizeCarriedAttribute(displayInfo.DisplayName)
		or normalizeCarriedAttribute(info and (info.DisplayName or info.CrewMemberName or info.Name))
		or normalizeCarriedAttribute(model and model:GetAttribute("CrewMemberDisplayName"))
		or crewMemberId

	if not displayName then
		return nil
	end

	return {
		CrewMemberId = crewMemberId or displayName,
		DisplayName = displayName,
		Image = normalizeCarriedAttribute(info and info.Render)
			or normalizeCarriedAttribute(model and model:GetAttribute("CrewMemberImage")),
	}
end

local function resolveCrewMemberStorageName(model, st, crewMemberData)
	return normalizeCarriedAttribute(crewMemberData and crewMemberData.CrewMemberId)
		or normalizeCarriedAttribute(st and st.Entry and st.Entry.Id)
		or normalizeCarriedAttribute(model and model:GetAttribute("CrewMemberId"))
		or normalizeCarriedAttribute(model and model.Name)
end

function Interaction.GetCarriedCrewMemberName(player)
	if not player then
		return nil
	end

	return normalizeCarriedAttribute(player:GetAttribute(CARRIED_CREW_MEMBER_ATTRIBUTE))
end

function Interaction.ClearCarriedCrewMemberAttributes(player)
	if player then
		clearCarriedCrewMemberAttributes(player)
	end
end

local function canPlayerCarryModel(player, model)
	if not player or not model then
		return false
	end

	local isTutorialCrewMember = model:GetAttribute(TUTORIAL_CREW_MEMBER_ATTRIBUTE) == true
	local tutorialOwnerUserId = model:GetAttribute(TUTORIAL_OWNER_ATTRIBUTE)
	if isTutorialCrewMember then
		return typeof(tutorialOwnerUserId) == "number" and tutorialOwnerUserId == player.UserId
	end

	if typeof(tutorialOwnerUserId) == "number" and tutorialOwnerUserId ~= player.UserId then
		return false
	end

	return true
end

local function forEachPart(model, fn)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			fn(d)
		end
	end
end

local function setNetworkOwner(part, owner)
	if part.Anchored then
		return
	end

	pcall(function()
		part:SetNetworkOwner(owner)
	end)
end

local function setCarryPhysics(model, held, networkOwner)
	forEachPart(model, function(p)
		p.Anchored = not held
		p.CanCollide = not held
		p.CanTouch = not held
		p.CanQuery = not held
		p.Massless = held
		p.AssemblyLinearVelocity = Vector3.zero
		p.AssemblyAngularVelocity = Vector3.zero
		if held then
			setNetworkOwner(p, networkOwner)
		else
			setNetworkOwner(p, nil)
		end
	end)
end

local function enforceHeldPhysics(model, networkOwner)
	forEachPart(model, function(p)
		p.Anchored = false
		p.CanCollide = false
		p.CanTouch = false
		p.CanQuery = false
		p.Massless = true
		setNetworkOwner(p, networkOwner)
	end)
end

local function setCarriedHumanoidState(model, st, held)
	if held then
		st.CarryHumanoidState = st.CarryHumanoidState or {}
		for _, descendant in ipairs(model:GetDescendants()) do
			if descendant:IsA("Humanoid") then
				if st.CarryHumanoidState[descendant] == nil then
					st.CarryHumanoidState[descendant] = {
						PlatformStand = descendant.PlatformStand,
						AutoRotate = descendant.AutoRotate,
						Sit = descendant.Sit,
					}
				end

				descendant.PlatformStand = true
				descendant.AutoRotate = false
				descendant.Sit = false
				pcall(function()
					descendant:ChangeState(Enum.HumanoidStateType.Physics)
				end)
			end
		end
		return
	end

	local saved = st and st.CarryHumanoidState
	if not saved then
		return
	end

	for humanoid, state in pairs(saved) do
		if humanoid and humanoid.Parent and humanoid:IsA("Humanoid") then
			humanoid.PlatformStand = state.PlatformStand == true
			humanoid.AutoRotate = state.AutoRotate ~= false
			humanoid.Sit = state.Sit == true
		end
	end
	st.CarryHumanoidState = nil
end

local function disconnectCarryPhysics(st)
	if st then
		carryMaintenanceEntries[st] = nil
		st.CarryPhysicsRegistered = nil
	end

	local legacyConn = st and st.CarryPhysicsConn
	if legacyConn then
		pcall(function()
			legacyConn:Disconnect()
		end)
	end
	if st then
		st.CarryPhysicsConn = nil
	end

	if next(carryMaintenanceEntries) == nil and carryMaintenanceConnection ~= nil then
		pcall(function()
			carryMaintenanceConnection:Disconnect()
		end)
		carryMaintenanceConnection = nil
		carryMaintenanceElapsed = 0
	end
end

local maintainHeldCarry

local function stepCarryMaintenance()
	for st, entry in pairs(carryMaintenanceEntries) do
		local model = entry.Model
		if not model or not model.Parent or st.Held ~= true then
			carryMaintenanceEntries[st] = nil
			st.CarryPhysicsRegistered = nil
		elseif maintainHeldCarry then
			maintainHeldCarry(st, model)
		else
			enforceHeldPhysics(model, entry.NetworkOwner)
		end
	end

	if next(carryMaintenanceEntries) == nil and carryMaintenanceConnection ~= nil then
		pcall(function()
			carryMaintenanceConnection:Disconnect()
		end)
		carryMaintenanceConnection = nil
		carryMaintenanceElapsed = 0
	end
end

local function ensureCarryMaintenanceLoop()
	if carryMaintenanceConnection ~= nil then
		return
	end

	carryMaintenanceElapsed = 0
	carryMaintenanceConnection = RunService.Heartbeat:Connect(function(deltaTime)
		carryMaintenanceElapsed += tonumber(deltaTime) or 0
		if carryMaintenanceElapsed < CARRY_MAINTENANCE_INTERVAL then
			return
		end

		carryMaintenanceElapsed = 0
		stepCarryMaintenance()
	end)
end

local function startCarryPhysicsEnforcer(st, model, networkOwner)
	disconnectCarryPhysics(st)
	if maintainHeldCarry then
		maintainHeldCarry(st, model)
	else
		enforceHeldPhysics(model, networkOwner)
	end

	carryMaintenanceEntries[st] = {
		Model = model,
		NetworkOwner = networkOwner,
	}
	st.CarryPhysicsRegistered = true
	ensureCarryMaintenanceLoop()
end

local function setDropPhysics(model)
	forEachPart(model, function(p)
		p.Anchored = false
		p.CanCollide = true
		p.CanTouch = true
		p.CanQuery = true
		p.Massless = false
		p.AssemblyLinearVelocity = Vector3.zero
		p.AssemblyAngularVelocity = Vector3.zero
		setNetworkOwner(p, nil)
	end)
end

local function anchorAll(model)
	forEachPart(model, function(p)
		p.Anchored = true
		p.AssemblyLinearVelocity = Vector3.zero
		p.AssemblyAngularVelocity = Vector3.zero
	end)
end

local function findModelPart(model)
	if not model or not model:IsA("Model") then
		return nil
	end

	for _, partName in ipairs({ "HumanoidRootPart", "Torso", "UpperTorso", "LowerTorso", "Head" }) do
		local namedPart = model:FindFirstChild(partName, true)
		if namedPart and namedPart:IsA("BasePart") then
			return namedPart
		end
	end

	if model.PrimaryPart and model.PrimaryPart:IsA("BasePart") then
		return model.PrimaryPart
	end

	return model:FindFirstChildWhichIsA("BasePart", true)
end

local function ensureCarryAssemblyWelds(model, rootPart)
	if not rootPart or not rootPart:IsA("BasePart") then
		return false
	end

	local weldedParts = {}
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("WeldConstraint") and descendant.Name == CARRY_ASSEMBLY_WELD_NAME then
			local part = descendant.Part1
			if descendant.Part0 ~= rootPart or not part or part == rootPart or not part:IsDescendantOf(model) or weldedParts[part] then
				descendant:Destroy()
			else
				weldedParts[part] = true
			end
		end
	end

	forEachPart(model, function(part)
		if part ~= rootPart and not weldedParts[part] then
			local weld = Instance.new("WeldConstraint")
			weld.Name = CARRY_ASSEMBLY_WELD_NAME
			weld.Part0 = rootPart
			weld.Part1 = part
			weld.Parent = rootPart
		end
	end)

	return true
end

local function destroyCarryAttachmentWeld(st)
	if st and st.Weld then
		pcall(function()
			st.Weld:Destroy()
		end)
	end
	if st then
		st.Weld = nil
	end
end

local function isCarryAttachmentWeldValid(st, rootPart, attachPart)
	local weld = st and st.Weld
	return weld ~= nil
		and weld.Parent ~= nil
		and weld:IsA("WeldConstraint")
		and weld.Part0 == rootPart
		and weld.Part1 == attachPart
end

local function createCarryAttachmentWeld(st, rootPart, attachPart)
	destroyCarryAttachmentWeld(st)

	local weld = Instance.new("WeldConstraint")
	weld.Name = CARRY_ATTACHMENT_WELD_NAME
	weld.Part0 = rootPart
	weld.Part1 = attachPart
	weld.Parent = rootPart
	st.Weld = weld
	return weld
end

local function captureCarryPartOffsets(model, rootPart, st)
	local offsets = {}
	forEachPart(model, function(part)
		offsets[part] = rootPart.CFrame:ToObjectSpace(part.CFrame)
	end)
	st.CarryPartOffsets = offsets
end

local function restoreCarryPartOffsets(model, rootPart, st, force)
	local offsets = st.CarryPartOffsets
	if typeof(offsets) ~= "table" then
		captureCarryPartOffsets(model, rootPart, st)
		offsets = st.CarryPartOffsets
	end

	forEachPart(model, function(part)
		if part == rootPart then
			return
		end

		local offset = offsets[part]
		if typeof(offset) ~= "CFrame" then
			offsets[part] = rootPart.CFrame:ToObjectSpace(part.CFrame)
			return
		end

		local expected = rootPart.CFrame * offset
		if force or (part.Position - expected.Position).Magnitude > CARRY_PART_REPAIR_DISTANCE then
			part.CFrame = expected
			part.AssemblyLinearVelocity = Vector3.zero
			part.AssemblyAngularVelocity = Vector3.zero
		end
	end)
end

local function clearCarryMaintenanceState(st)
	if not st then
		return
	end

	st.CarryRootPart = nil
	st.CarryAttachPart = nil
	st.CarryOwner = nil
	st.CarryRootLocalCFrame = nil
	st.CarryPartOffsets = nil
end

maintainHeldCarry = function(st, model)
	if not st or not model or not model.Parent or st.Held ~= true then
		return false
	end

	local rootPart = st.CarryRootPart
	if not rootPart or not rootPart.Parent or not rootPart:IsDescendantOf(model) then
		rootPart = findModelPart(model)
		st.CarryRootPart = rootPart
	end
	if not rootPart then
		return false
	end

	local owner = st.CarryOwner
	local attachPart = st.CarryAttachPart
	if not attachPart or not attachPart.Parent then
		local char = owner and owner.Character
		attachPart = char and char:FindFirstChild("Head")
		st.CarryAttachPart = attachPart
	end
	if not attachPart or not attachPart.Parent then
		return false
	end

	if model:GetAttribute(CARRIED_MODEL_ATTRIBUTE) ~= true then
		model:SetAttribute(CARRIED_MODEL_ATTRIBUTE, true)
	end

	enforceHeldPhysics(model, owner)
	setCarriedHumanoidState(model, st, true)

	local rootDrifted = false
	local rootLocalCFrame = st.CarryRootLocalCFrame
	if typeof(rootLocalCFrame) == "CFrame" then
		local expectedRootCFrame = attachPart.CFrame * rootLocalCFrame
		rootDrifted = (rootPart.Position - expectedRootCFrame.Position).Magnitude > CARRY_ROOT_REPAIR_DISTANCE
		if rootDrifted then
			destroyCarryAttachmentWeld(st)
			rootPart.CFrame = expectedRootCFrame
			rootPart.AssemblyLinearVelocity = Vector3.zero
			rootPart.AssemblyAngularVelocity = Vector3.zero
		end
	else
		st.CarryRootLocalCFrame = attachPart.CFrame:ToObjectSpace(rootPart.CFrame)
	end

	restoreCarryPartOffsets(model, rootPart, st, rootDrifted)
	ensureCarryAssemblyWelds(model, rootPart)

	if rootDrifted or not isCarryAttachmentWeldValid(st, rootPart, attachPart) then
		createCarryAttachmentWeld(st, rootPart, attachPart)
	end

	return true
end

local function ensurePrompt(primary)
	local p = primary:FindFirstChildOfClass("ProximityPrompt")
	if not p then
		p = Instance.new("ProximityPrompt")
		p.Parent = primary
	end
	p.RequiresLineOfSight = false
	p.HoldDuration = 0.7
	p.MaxActivationDistance = 12
	p.Style = Enum.ProximityPromptStyle.Custom
	return p
end

local function computeHeadRotOnly(head)
	local lv = head.CFrame.LookVector
	local dir = Vector3.new(lv.X, 0, lv.Z)
	if dir.Magnitude < 1e-4 then
		dir = Vector3.new(0, 0, -1)
	else
		dir = dir.Unit
	end
	local rot = CFrame.lookAt(Vector3.zero, dir, Vector3.yAxis)
	return rot - rot.Position
end

local function getGroundPosition(pos, ignore)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore or {}
	local origin = pos + Vector3.new(0, 6, 0)
	local result = workspace:Raycast(origin, Vector3.new(0, -300, 0), params)
	if result then
		return result.Position
	end
	return pos
end

local function computePivotBottomOnPoint(model, point, rotOnly)
	local boxCF, boxSize = model:GetBoundingBox()
	local offset = model:GetPivot():ToObjectSpace(boxCF)
	local up = Vector3.yAxis
	local desiredBoxCF = CFrame.new(point + up * (boxSize.Y / 2)) * rotOnly
	return desiredBoxCF * offset:Inverse()
end

local function settleToGroundThenAnchor(model, shouldContinue)
	local function canContinue()
		if typeof(shouldContinue) ~= "function" then
			return true
		end

		local ok, result = pcall(shouldContinue)
		return ok and result ~= false
	end

	if not canContinue() then
		return
	end

	local primary = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
	local t0 = os.clock()
	while model.Parent and os.clock() - t0 < 2.5 do
		if not canContinue() then
			return
		end

		task.wait(0.08)
		if not primary or not primary.Parent then
			primary = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
		end
		if primary then
			local origin = primary.Position
			local params = RaycastParams.new()
			params.FilterType = Enum.RaycastFilterType.Exclude
			params.FilterDescendantsInstances = { model }
			local r = workspace:Raycast(origin, Vector3.new(0, -12, 0), params)
			if r and (origin.Y - r.Position.Y) <= 1.2 then
				break
			end
		end
	end
	if not model.Parent or not canContinue() then
		return
	end
	local rot = model:GetPivot()
	local lv = rot.LookVector
	local dir = Vector3.new(lv.X, 0, lv.Z)
	if dir.Magnitude < 1e-4 then
		dir = Vector3.new(0, 0, -1)
	else
		dir = dir.Unit
	end
	local rotOnly = CFrame.lookAt(Vector3.zero, dir, Vector3.yAxis)
	rotOnly = rotOnly - rotOnly.Position
	local ground = getGroundPosition(model:GetPivot().Position, { model })
	local pivotTarget = computePivotBottomOnPoint(model, ground, rotOnly)
	model:PivotTo(pivotTarget)
	if not canContinue() then
		return
	end
	anchorAll(model)
end

local function scheduleDroppedCrewMemberSettle(ctx, model, st)
	if not ctx or not model or not st then
		return
	end

	st.DropSettleToken = (tonumber(st.DropSettleToken) or 0) + 1
	local settleToken = st.DropSettleToken
	task.spawn(function()
		settleToGroundThenAnchor(model, function()
			return model.Parent == ctx.DroppedFolder and st.Held ~= true and st.DropSettleToken == settleToken
		end)
	end)
end

local function isForcedCarryDropState(state)
	return state == Enum.HumanoidStateType.Ragdoll
		or state == Enum.HumanoidStateType.Physics
end

function Interaction.NewContext(map)
	local worldFolder = map:FindFirstChild(CREW_MEMBERS_WORLD_FOLDER_NAME) or Instance.new("Folder")
	worldFolder.Name = CREW_MEMBERS_WORLD_FOLDER_NAME
	worldFolder.Parent = map

	local carriedFolder = worldFolder:FindFirstChild("Carried") or Instance.new("Folder")
	carriedFolder.Name = "Carried"
	carriedFolder.Parent = worldFolder

	local droppedFolder = worldFolder:FindFirstChild("Dropped") or Instance.new("Folder")
	droppedFolder.Name = "Dropped"
	droppedFolder.Parent = worldFolder

	local context = {
		CarriedFolder = carriedFolder,
		DroppedFolder = droppedFolder,
		HeldByUserId = {},
		HeldByCarryId = {},
		HeldCarryIdsByUserId = {},
		DeathConnByUserId = {},
		RagdollConnByUserId = {},
	}
	activeContext = context
	return context
end

function Interaction.GetActiveContext()
	return activeContext
end

local function disconnectDeath(ctx, userId)
	local c = ctx.DeathConnByUserId[userId]
	ctx.DeathConnByUserId[userId] = nil
	if c then
		pcall(function()
			c:Disconnect()
		end)
	end
end

local function disconnectRagdoll(ctx, userId)
	local c = ctx.RagdollConnByUserId[userId]
	ctx.RagdollConnByUserId[userId] = nil
	if c then
		pcall(function()
			c:Disconnect()
		end)
	end
end

local function getHeldCarryIdList(ctx, userId)
	local list = ctx.HeldCarryIdsByUserId[userId]
	if typeof(list) ~= "table" then
		list = {}
		ctx.HeldCarryIdsByUserId[userId] = list
	end
	return list
end

local function setFirstHeldModel(ctx, userId)
	local list = getHeldCarryIdList(ctx, userId)
	ctx.HeldByUserId[userId] = nil
	for _, carryId in ipairs(list) do
		local model = ctx.HeldByCarryId[carryId]
		if model and model.Parent then
			ctx.HeldByUserId[userId] = model
			return model
		end
	end
	return nil
end

local function addHeldModel(ctx, userId, carryId, model)
	if typeof(carryId) ~= "string" or carryId == "" then
		return
	end

	local list = getHeldCarryIdList(ctx, userId)
	for _, existingCarryId in ipairs(list) do
		if existingCarryId == carryId then
			ctx.HeldByCarryId[carryId] = model
			setFirstHeldModel(ctx, userId)
			return
		end
	end

	list[#list + 1] = carryId
	ctx.HeldByCarryId[carryId] = model
	if not ctx.HeldByUserId[userId] then
		ctx.HeldByUserId[userId] = model
	end
end

local function removeHeldModel(ctx, userId, carryId, model)
	if typeof(carryId) == "string" and carryId ~= "" then
		ctx.HeldByCarryId[carryId] = nil
		local list = getHeldCarryIdList(ctx, userId)
		for index = #list, 1, -1 do
			if list[index] == carryId then
				table.remove(list, index)
			end
		end
	end

	if ctx.HeldByUserId[userId] == model then
		setFirstHeldModel(ctx, userId)
	end
end

local function findHeldModel(ctx, player, active, slotIndexOrCarryId)
	local userId = player.UserId
	active = active or (ctx and ctx.Active)
	if typeof(slotIndexOrCarryId) == "string" and slotIndexOrCarryId ~= "" then
		local model = ctx.HeldByCarryId[slotIndexOrCarryId]
		if model and model.Parent then
			return model, active and active[model]
		end
	end

	for _, carryId in ipairs(getHeldCarryIdList(ctx, userId)) do
		local model = ctx.HeldByCarryId[carryId]
		local st = active and active[model]
		if model and model.Parent and st then
			if slotIndexOrCarryId == nil or st.CarrySlotIndex == slotIndexOrCarryId or tostring(st.CarrySlotIndex) == tostring(slotIndexOrCarryId) then
				return model, st
			end
		end
	end

	local model = ctx.HeldByUserId[userId]
	if model and model.Parent then
		return model, active and active[model]
	end

	return nil, nil
end

local function canReserveCarrySlot(player)
	if carrySlotAdapter and typeof(carrySlotAdapter.CanCarryMore) == "function" then
		return carrySlotAdapter.CanCarryMore(player) == true
	end

	return player:GetAttribute("CarriedMajorRewardType") == nil
end

local function reserveCrewCarrySlot(player, model, st, crewMemberData)
	if carrySlotAdapter and typeof(carrySlotAdapter.AddCrewMember) == "function" then
		local info = getCrewMemberInfoFromState(st)
		local carryData = {
			CrewMemberId = crewMemberData and crewMemberData.CrewMemberId or nil,
			DisplayName = crewMemberData and crewMemberData.DisplayName or nil,
			Image = crewMemberData and crewMemberData.Image or nil,
			CrewName = resolveCrewMemberStorageName(model, st, crewMemberData),
			CrewStorageName = resolveCrewMemberStorageName(model, st, crewMemberData),
			Rarity = info and info.Rarity or st and st.Rarity or nil,
			CanonicalRarity = info and info.Rarity or nil,
			Variant = info and info.Variant or nil,
			Physical = true,
		}

		if model and model:GetAttribute(TUTORIAL_CREW_MEMBER_ATTRIBUTE) == true then
			carryData.TutorialCrewMember = true
			carryData.TutorialReward = true
			carryData.TutorialToken = tostring(model:GetAttribute(TUTORIAL_TOKEN_ATTRIBUTE) or "")
			carryData.TutorialRewardName = tostring(model:GetAttribute(TUTORIAL_REWARD_NAME_ATTRIBUTE) or "")

			local tutorialOwnerUserId = model:GetAttribute(TUTORIAL_OWNER_ATTRIBUTE)
			if typeof(tutorialOwnerUserId) == "number" then
				carryData.TutorialOwnerUserId = tutorialOwnerUserId
			end
		end

		return carrySlotAdapter.AddCrewMember(player, carryData)
	end

	return {
		SlotIndex = 1,
		CarryId = tostring(player.UserId) .. ":legacy_crew",
	}, nil
end

local function removeCrewCarrySlot(player, slotIndexOrCarryId)
	if carrySlotAdapter and typeof(carrySlotAdapter.RemoveCarryItem) == "function" then
		carrySlotAdapter.RemoveCarryItem(player, slotIndexOrCarryId)
	end
end

local function getCarryVisualItems(ctx, player, active)
	if carrySlotAdapter and typeof(carrySlotAdapter.GetCarrySlots) == "function" then
		local slots = carrySlotAdapter.GetCarrySlots(player)
		if typeof(slots) == "table" then
			return slots
		end
	end

	local items = {}
	active = active or (ctx and ctx.Active)
	if not ctx or not player then
		return items
	end

	for _, carryId in ipairs(getHeldCarryIdList(ctx, player.UserId)) do
		local model = ctx.HeldByCarryId[carryId]
		local st = active and active[model]
		if model and model.Parent and st and st.Held == true then
			items[#items + 1] = {
				SlotIndex = st.CarrySlotIndex,
				CarryId = st.CarryId,
				CarryOrder = st.CarryOrder,
				Occupied = true,
			}
		end
	end

	return items
end

local function getCarryVisualOffset(ctx, player, active, st)
	local items = getCarryVisualItems(ctx, player, active)
	return CarriedRewardVisuals.GetOffsetForItem(items, {
		SlotIndex = st and st.CarrySlotIndex,
		CarryId = st and st.CarryId,
		CarryOrder = st and st.CarryOrder,
		Occupied = true,
	}, CARRY_VISUAL_SPACING)
end

local function positionHeldCrewMember(ctx, player, active, model, st, attachPart)
	if not model or not model.Parent or not st or st.Held ~= true then
		return false
	end

	local rootPart = st.CarryRootPart
	if not rootPart or not rootPart.Parent or not rootPart:IsDescendantOf(model) then
		rootPart = findModelPart(model)
		st.CarryRootPart = rootPart
	end
	if not rootPart then
		return false
	end

	if not attachPart or not attachPart:IsA("BasePart") or not attachPart.Parent then
		local char = player and player.Character
		attachPart = char and char:FindFirstChild("Head")
	end
	if not attachPart or not attachPart:IsA("BasePart") then
		return false
	end

	st.CarryAttachPart = attachPart

	local rotOnly = computeHeadRotOnly(attachPart)
	local lateralOffset = attachPart.CFrame.RightVector * getCarryVisualOffset(ctx, player, active, st)
	local top = attachPart.Position + Vector3.yAxis * (attachPart.Size.Y / 2) + lateralOffset
	local pivotTarget = computePivotBottomOnPoint(model, top, rotOnly)

	destroyCarryAttachmentWeld(st)
	model:PivotTo(pivotTarget)
	rootPart.AssemblyLinearVelocity = Vector3.zero
	rootPart.AssemblyAngularVelocity = Vector3.zero
	st.CarryRootLocalCFrame = attachPart.CFrame:ToObjectSpace(rootPart.CFrame)
	captureCarryPartOffsets(model, rootPart, st)
	createCarryAttachmentWeld(st, rootPart, attachPart)
	return true
end

local function refreshHeldCarryLayout(ctx, player, active)
	ctx = ctx or activeContext
	active = active or (ctx and ctx.Active)
	if not ctx or not active or not player then
		return false
	end

	local refreshedAny = false
	for _, carryId in ipairs(getHeldCarryIdList(ctx, player.UserId)) do
		local model = ctx.HeldByCarryId[carryId]
		local st = active[model]
		if model and model.Parent and st and st.Held == true then
			local attachPart = st.CarryAttachPart
			if positionHeldCrewMember(ctx, player, active, model, st, attachPart) then
				refreshedAny = true
			end
		end
	end

	return refreshedAny
end

local function dropHeldCrewMember(ctx, player, model, st, dropPosition, options)
	if not model or not model.Parent then
		return
	end
	if not st or not st.Held then
		return
	end

	options = if typeof(options) == "table" then options else {}
	local userId = player.UserId
	if options.SkipCarrySlotRemove ~= true then
		removeCrewCarrySlot(player, st.CarryId or st.CarrySlotIndex)
	end
	clearCarriedCrewMemberAttributes(player)
	player:SetAttribute(HORO_PROJECTION_CARRY_ATTRIBUTE, nil)

	removeHeldModel(ctx, userId, st.CarryId, model)
	refreshHeldCarryLayout(ctx, player)
	if not ctx.HeldByUserId[userId] then
		disconnectDeath(ctx, userId)
		disconnectRagdoll(ctx, userId)
	end
	disconnectCarryPhysics(st)
	setCarriedHumanoidState(model, st, false)

	destroyCarryAttachmentWeld(st)
	clearCarryMaintenanceState(st)

	model:SetAttribute(CARRIED_MODEL_ATTRIBUTE, nil)
	model.Parent = ctx.DroppedFolder

	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	local dropPos = if typeof(dropPosition) == "Vector3"
		then dropPosition
		else (hrp and hrp.Position or model:GetPivot().Position)

	local rot = model:GetPivot()
	local lv = rot.LookVector
	local dir = Vector3.new(lv.X, 0, lv.Z)
	if dir.Magnitude < 1e-4 then
		dir = Vector3.new(0, 0, -1)
	else
		dir = dir.Unit
	end
	local rotOnly2 = CFrame.lookAt(Vector3.zero, dir, Vector3.yAxis)
	rotOnly2 = rotOnly2 - rotOnly2.Position

	local startFallPos = dropPos + Vector3.new(0, 6, 0)
	local pivotStart = computePivotBottomOnPoint(model, startFallPos, rotOnly2)
	model:PivotTo(pivotStart)

	st.Held = false
	st.HolderUserId = nil
	st.CarryId = nil
	st.CarrySlotIndex = nil
	st.CarryOrder = nil
	st.LastUpdate = os.clock()
	if tostring(model:GetAttribute(OVERHEAD_ATTRIBUTES.Kind) or "") == CrewOverhead.Kind.Spawned then
		if tonumber(model:GetAttribute(OVERHEAD_ATTRIBUTES.DespawnSeconds)) == nil then
			model:SetAttribute(
				OVERHEAD_ATTRIBUTES.DespawnSeconds,
				math.max(0, tonumber(st.Remaining) or 0)
			)
		end
		model:SetAttribute(
			OVERHEAD_ATTRIBUTES.ExpiresAt,
			workspace:GetServerTimeNow() + math.max(0, tonumber(st.Remaining) or 0)
		)
	end
	setDropPhysics(model)
	scheduleDroppedCrewMemberSettle(ctx, model, st)

	if st.Prompt then
		st.Prompt.Enabled = true
	end

end

local function carryCrewMemberOnPart(ctx, player, model, st, carrierPart)
	if not ctx or not player or not model or not model.Parent or not st or st.Held then
		return false
	end
	if not canPlayerCarryModel(player, model) then
		return false
	end
	if not canReserveCarrySlot(player) then
		return false
	end

	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local attachPart = carrierPart
	if not attachPart or not attachPart:IsA("BasePart") then
		attachPart = char and char:FindFirstChild("Head")
	end
	if not attachPart or not hum or hum.Health <= 0 then
		return false
	end

	local primary = findModelPart(model)
	if not primary then
		return false
	end

	local crewMemberData = resolveCanonicalCrewMemberData(model, st)
	local carrySlot, reserveReason = reserveCrewCarrySlot(player, model, st, crewMemberData)
	if not carrySlot then
		return false, reserveReason
	end
	local carryId = tostring(carrySlot.CarryId or "")
	if carryId == "" then
		removeCrewCarrySlot(player, carrySlot.SlotIndex)
		return false
	end

	if st.Prompt then
		st.Prompt.Enabled = false
	end

	st.DropSettleToken = (tonumber(st.DropSettleToken) or 0) + 1
	destroyCarryAttachmentWeld(st)
	clearCarryMaintenanceState(st)
	st.Held = true
	st.HolderUserId = player.UserId
	st.CarryRootPart = primary
	st.CarryAttachPart = attachPart
	st.CarryOwner = player
	st.CarryId = carryId
	st.CarrySlotIndex = carrySlot.SlotIndex
	st.CarryOrder = carrySlot.CarryOrder
	model:SetAttribute(CARRIED_MODEL_ATTRIBUTE, true)
	setCarryPhysics(model, true, player)
	setCarriedHumanoidState(model, st, true)
	ensureCarryAssemblyWelds(model, primary)

	positionHeldCrewMember(ctx, player, ctx.Active, model, st, attachPart)
	startCarryPhysicsEnforcer(st, model, player)
	model.Parent = ctx.CarriedFolder

	st.LastUpdate = os.clock()
	addHeldModel(ctx, player.UserId, carryId, model)
	refreshHeldCarryLayout(ctx, player)
	player:SetAttribute(HORO_PROJECTION_CARRY_ATTRIBUTE, nil)

	setCarriedCrewMemberAttributes(player, crewMemberData)

	disconnectDeath(ctx, player.UserId)
	disconnectRagdoll(ctx, player.UserId)

	ctx.DeathConnByUserId[player.UserId] = hum.Died:Connect(function()
		local heldCarryIds = table.clone(getHeldCarryIdList(ctx, player.UserId))
		for _, heldCarryId in ipairs(heldCarryIds) do
			local heldModel = ctx.HeldByCarryId[heldCarryId]
			local heldState = ctx.Active and ctx.Active[heldModel]
			if heldModel and heldModel.Parent and heldState then
				dropHeldCrewMember(ctx, player, heldModel, heldState)
			end
		end
	end)

	ctx.RagdollConnByUserId[player.UserId] = hum.StateChanged:Connect(function(_, newState)
		if not isForcedCarryDropState(newState) then
			return
		end

		local heldCarryIds = table.clone(getHeldCarryIdList(ctx, player.UserId))
		for _, heldCarryId in ipairs(heldCarryIds) do
			local heldModel = ctx.HeldByCarryId[heldCarryId]
			local heldState = ctx.Active and ctx.Active[heldModel]
			if heldModel and heldModel.Parent and heldState then
				dropHeldCrewMember(ctx, player, heldModel, heldState)
			end
		end
	end)

	return true
end

function Interaction.HasHeld(ctx, player)
	ctx = ctx or activeContext
	return ctx ~= nil
		and player ~= nil
		and (
			ctx.HeldByUserId[player.UserId] ~= nil
			or #getHeldCarryIdList(ctx, player.UserId) > 0
		)
end

function Interaction.GetHeldCount(ctx, player)
	ctx = ctx or activeContext
	if not ctx or not player then
		return 0
	end

	local count = 0
	for _, carryId in ipairs(getHeldCarryIdList(ctx, player.UserId)) do
		local model = ctx.HeldByCarryId[carryId]
		if model and model.Parent then
			count += 1
		end
	end
	if count == 0 and ctx.HeldByUserId[player.UserId] then
		count = 1
	end
	return count
end

function Interaction.TryCarryNearPosition(ctx, player, active, worldPosition, carrierPart, maxDistance)
	ctx = ctx or activeContext
	active = active or (ctx and ctx.Active)
	if not ctx or not active or not player or typeof(worldPosition) ~= "Vector3" then
		return false, "missing_context"
	end

	local searchRadius = math.max(0, tonumber(maxDistance) or 0)
	if searchRadius <= 0 then
		return false, "invalid_radius"
	end

	local bestModel = nil
	local bestState = nil
	local bestDistance = searchRadius
	for model, st in pairs(active) do
		if model and model.Parent and st and not st.Held and canPlayerCarryModel(player, model) then
			local primary = findModelPart(model)
			if primary then
				local distance = (primary.Position - worldPosition).Magnitude
				if distance <= bestDistance then
					bestDistance = distance
					bestModel = model
					bestState = st
				end
			end
		end
	end

	if not bestModel or not bestState then
		return false, "no_crew_member_in_range"
	end

	if carryCrewMemberOnPart(ctx, player, bestModel, bestState, carrierPart) then
		local crewMemberData = resolveCanonicalCrewMemberData(bestModel, bestState)
		return true, {
			Kind = "CrewMember",
			Name = tostring((crewMemberData and crewMemberData.DisplayName) or ""),
			CrewMemberId = crewMemberData and crewMemberData.CrewMemberId or nil,
			LegacyId = crewMemberData and crewMemberData.LegacyId or nil,
			Distance = bestDistance,
		}
	end

	return false, "carry_failed"
end

function Interaction.DropHeldAtPosition(ctx, player, active, dropPosition, slotIndexOrCarryId, options)
	ctx = ctx or activeContext
	active = active or (ctx and ctx.Active)
	if not ctx or not active or not player then
		return false, "missing_context"
	end

	local model, st = findHeldModel(ctx, player, active, slotIndexOrCarryId)
	if not model or not model.Parent then
		setFirstHeldModel(ctx, player.UserId)
		return false, "no_held_crew_member"
	end

	if not st then
		return false, "missing_state"
	end

	dropHeldCrewMember(ctx, player, model, st, dropPosition, options)
	return true
end

local function buildHeldInfo(model, st)
	local crewMemberData = resolveCanonicalCrewMemberData(model, st)
	local storageName = resolveCrewMemberStorageName(model, st, crewMemberData)
	local isTutorialCrewMember = model:GetAttribute(TUTORIAL_CREW_MEMBER_ATTRIBUTE) == true
	local tutorialOwnerUserId = model:GetAttribute(TUTORIAL_OWNER_ATTRIBUTE)
	local tutorialToken = tostring(model:GetAttribute(TUTORIAL_TOKEN_ATTRIBUTE) or "")
	local tutorialRewardName = tostring(model:GetAttribute(TUTORIAL_REWARD_NAME_ATTRIBUTE) or "")

	local info = {
		Model = model,
		Name = storageName,
		CrewMemberId = crewMemberData and crewMemberData.CrewMemberId or nil,
		DisplayName = crewMemberData and crewMemberData.DisplayName or nil,
		Image = crewMemberData and crewMemberData.Image or nil,
		TutorialCrewMember = isTutorialCrewMember,
		TutorialOwnerUserId = tutorialOwnerUserId,
		TutorialToken = tutorialToken,
		TutorialRewardName = tutorialRewardName,
	}

	if st then
		info.OriginData = st.OriginData
		info.SlotIndex = st.SlotIndex
		info.CarrySlotIndex = st.CarrySlotIndex
		info.CarryId = st.CarryId
		info.CarryOrder = st.CarryOrder
	end

	return info
end

function Interaction.CollectHeld(ctx, player, active, slotIndexOrCarryId, options)
	active = active or (ctx and ctx.Active)
	local userId = player.UserId
	local model, st = findHeldModel(ctx, player, active, slotIndexOrCarryId)
	if not model or not model.Parent then
		setFirstHeldModel(ctx, userId)
		disconnectDeath(ctx, userId)
		disconnectRagdoll(ctx, userId)  
		return nil
	end
	options = if typeof(options) == "table" then options else {}
	local collectedInfo = buildHeldInfo(model, st)
	if options.SkipCarrySlotRemove ~= true then
		removeCrewCarrySlot(player, st and (st.CarryId or st.CarrySlotIndex) or slotIndexOrCarryId)
	end
	clearCarriedCrewMemberAttributes(player)
	player:SetAttribute(HORO_PROJECTION_CARRY_ATTRIBUTE, nil)

	removeHeldModel(ctx, userId, st and st.CarryId or nil, model)
	refreshHeldCarryLayout(ctx, player, active)
	if not ctx.HeldByUserId[userId] then
		disconnectDeath(ctx, userId)
		disconnectRagdoll(ctx, userId)
	end
	disconnectCarryPhysics(st)
	if st then
		setCarriedHumanoidState(model, st, false)
		destroyCarryAttachmentWeld(st)
		clearCarryMaintenanceState(st)
	end

	active[model] = nil
	pcall(function()
		model:SetAttribute(CARRIED_MODEL_ATTRIBUTE, nil)
		model:Destroy()
	end)

	return collectedInfo
end

function Interaction.RefreshHeldCarryLayout(ctx, player, active)
	return refreshHeldCarryLayout(ctx, player, active)
end

function Interaction.PeekAllHeld(ctx, player, active)
	ctx = ctx or activeContext
	active = active or (ctx and ctx.Active)
	if not ctx or not active or not player then
		return {}
	end

	local results = {}
	local carryIds = table.clone(getHeldCarryIdList(ctx, player.UserId))
	if #carryIds == 0 and ctx.HeldByUserId[player.UserId] then
		local model, st = findHeldModel(ctx, player, active, nil)
		if model and model.Parent then
			results[#results + 1] = buildHeldInfo(model, st)
		end
		return results
	end

	for _, carryId in ipairs(carryIds) do
		local model, st = findHeldModel(ctx, player, active, carryId)
		if model and model.Parent then
			results[#results + 1] = buildHeldInfo(model, st)
		end
	end

	return results
end

function Interaction.CollectAllHeld(ctx, player, active, options)
	ctx = ctx or activeContext
	active = active or (ctx and ctx.Active)
	if not ctx or not active or not player then
		return {}
	end

	local results = {}
	local carryIds = table.clone(getHeldCarryIdList(ctx, player.UserId))
	if #carryIds == 0 and ctx.HeldByUserId[player.UserId] then
		local info = Interaction.CollectHeld(ctx, player, active, nil, options)
		if info then
			results[#results + 1] = info
		end
		return results
	end

	for _, carryId in ipairs(carryIds) do
		local info = Interaction.CollectHeld(ctx, player, active, carryId, options)
		if info then
			results[#results + 1] = info
		end
	end

	return results
end

function Interaction.ForgetHeldCarryItem(ctx, player, active, slotIndexOrCarryId)
	return Interaction.CollectHeld(ctx, player, active, slotIndexOrCarryId, {
		SkipCarrySlotRemove = true,
	})
end

function Interaction.BindPrompt(ctx, model, st, ensurePrimaryPart)
	local primary = ensurePrimaryPart(model)
	if not primary then
		return nil
	end

	local prompt = ensurePrompt(primary)

	local rawName = tostring(st.Entry and st.Entry.Info and (st.Entry.Info.Name or st.Entry.Info.DisplayName) or st.Entry and st.Entry.Id or model.Name)
	local crewMemberId = tostring(st.Entry and (st.Entry.Id or (st.Entry.Info and st.Entry.Info.CrewMemberId)) or model.Name)
	local displayInfo = CrewCatalog.GetDisplayInfo(crewMemberId, st.Entry and st.Entry.Info)
	local displayName = tostring(displayInfo.DisplayName or rawName)

	prompt.ActionText = displayName
	prompt.ObjectText = "Hold to Get"
	prompt.Enabled = true

	prompt.Triggered:Connect(function(player)
		if not model.Parent then
			return
		end
		if not canPlayerCarryModel(player, model) then
			return
		end
		if st.Held then
			return
		end
		if not prompt.Enabled then
			return
		end
		if not canReserveCarrySlot(player) then
			return
		end

		carryCrewMemberOnPart(ctx, player, model, st)
	end)

	return prompt
end

function Interaction.OnPlayerRemoving(ctx, plr, active)
	local userId = plr.UserId
	local legacyFirst = ctx.HeldByUserId[userId]
	local carryIds = table.clone(getHeldCarryIdList(ctx, userId))
	if #carryIds == 0 and legacyFirst then
		carryIds = { "__legacy_first" }
	end
	ctx.HeldByUserId[userId] = nil
	disconnectDeath(ctx, userId)
	disconnectRagdoll(ctx, userId) 

	for _, carryId in ipairs(carryIds) do
		local m = if carryId == "__legacy_first" then legacyFirst else ctx.HeldByCarryId[carryId]
		if carryId ~= "__legacy_first" then
			ctx.HeldByCarryId[carryId] = nil
		end
		if m and m.Parent then
			local st = active[m]
			if st then
				disconnectCarryPhysics(st)
				setCarriedHumanoidState(m, st, false)
				destroyCarryAttachmentWeld(st)
				clearCarryMaintenanceState(st)

				m:SetAttribute(CARRIED_MODEL_ATTRIBUTE, nil)
				m.Parent = ctx.DroppedFolder
				clearCarriedCrewMemberAttributes(plr)
				plr:SetAttribute(HORO_PROJECTION_CARRY_ATTRIBUTE, nil)

				local pos = m:GetPivot().Position + Vector3.new(0, 6, 0)
				local rot = m:GetPivot()
				local lv = rot.LookVector
				local dir = Vector3.new(lv.X, 0, lv.Z)
				if dir.Magnitude < 1e-4 then
					dir = Vector3.new(0, 0, -1)
				else
					dir = dir.Unit
				end
				local rotOnly = CFrame.lookAt(Vector3.zero, dir, Vector3.yAxis)
				rotOnly = rotOnly - rotOnly.Position
				local pivotStart = computePivotBottomOnPoint(m, pos, rotOnly)
				m:PivotTo(pivotStart)

				st.Held = false
				st.HolderUserId = nil
				st.CarryId = nil
				st.CarrySlotIndex = nil
				st.CarryOrder = nil
				st.LastUpdate = os.clock()
				setDropPhysics(m)
				scheduleDroppedCrewMemberSettle(ctx, m, st)

				if st.Prompt then
					st.Prompt.Enabled = true
				end
			end
		end
	end

	ctx.HeldCarryIdsByUserId[userId] = nil
end

return Interaction
