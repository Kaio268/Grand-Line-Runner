local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Interaction = {}
local CurrencyUtil = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("CurrencyUtil"))
local CrewCatalog = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Crew"):WaitForChild("CrewCatalog"))
local activeContext = nil
local HORO_PROJECTION_CARRY_ATTRIBUTE = "HoroProjectionCarryProjectionId"
local TUTORIAL_CREW_MEMBER_ATTRIBUTE = "TutorialCrewMember"
local TUTORIAL_OWNER_ATTRIBUTE = "TutorialOwnerUserId"
local TUTORIAL_TOKEN_ATTRIBUTE = "TutorialToken"
local TUTORIAL_REWARD_NAME_ATTRIBUTE = "TutorialRewardName"
local CARRIED_MODEL_ATTRIBUTE = "CrewCarryHeld"
local CARRIED_CREW_MEMBER_ATTRIBUTE = "CarriedCrewMember"
local CARRIED_CREW_MEMBER_IMAGE_ATTRIBUTE = "CarriedCrewMemberImage"
local CREW_MEMBERS_WORLD_FOLDER_NAME = "CrewMembersWorld"
local CARRY_ASSEMBLY_WELD_NAME = "CrewCarryAssemblyWeld"
local CARRY_ATTACHMENT_WELD_NAME = "CrewCarryAttachmentWeld"
local CARRY_ROOT_REPAIR_DISTANCE = 2
local CARRY_PART_REPAIR_DISTANCE = 3
local warnedMissingHoverTemplate = false

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
	local displayName = normalizeCarriedAttribute(info and (info.DisplayName or info.CrewMemberName or info.Name))
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
	local conn = st and st.CarryPhysicsConn
	if conn then
		pcall(function()
			conn:Disconnect()
		end)
	end
	if st then
		st.CarryPhysicsConn = nil
	end
end

local maintainHeldCarry

local function startCarryPhysicsEnforcer(st, model, networkOwner)
	disconnectCarryPhysics(st)
	if maintainHeldCarry then
		maintainHeldCarry(st, model)
	else
		enforceHeldPhysics(model, networkOwner)
	end

	st.CarryPhysicsConn = RunService.Heartbeat:Connect(function()
		if not model.Parent or st.Held ~= true then
			disconnectCarryPhysics(st)
			return
		end

		if maintainHeldCarry then
			maintainHeldCarry(st, model)
		else
			enforceHeldPhysics(model, networkOwner)
		end
	end)
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

local function getTextTarget(root, name)
	local obj = root:FindFirstChild(name, true)
	if not obj then
		return nil
	end
	if obj:IsA("TextLabel") or obj:IsA("TextButton") or obj:IsA("TextBox") then
		return obj
	end
	return obj:FindFirstChildWhichIsA("TextLabel", true) or obj:FindFirstChildWhichIsA("TextButton", true) or obj:FindFirstChildWhichIsA("TextBox", true)
end

local function findHoverGui(primaryPart)
	local h = primaryPart:FindFirstChild("CrewMemberHover", true)
	if h and h:IsA("BillboardGui") then
		return h
	end
	return nil
end

local function ensureHoverGui(primaryPart)
	local h = findHoverGui(primaryPart)
	if h then
		return h
	end

	local rarities = ReplicatedStorage:FindFirstChild("Rarities")
	local template = rarities and rarities:FindFirstChild("CrewMemberHover")
	if not template or not template:IsA("BillboardGui") then
		if not warnedMissingHoverTemplate then
			warn("[CrewInteraction] Missing ReplicatedStorage.Rarities.CrewMemberHover canonical hover template.")
			warnedMissingHoverTemplate = true
		end
		return nil
	end

	local clone = template:Clone()
	clone.Name = "CrewMemberHover"
	clone.Adornee = primaryPart
	clone.Parent = primaryPart
	clone.Enabled = true
	return clone
end

local VariantOrder = { "Normal", "Golden", "Diamond" }
local VariantPrefix = {
	Normal = "",
	Golden = "Golden ",
	Diamond = "Diamond ",
}

do
	local ok, cfg = pcall(function()
		return CrewCatalog.GetVariantConfig()
	end)
	if ok and cfg and typeof(cfg) == "table" then
		if type(cfg.Order) == "table" then
			VariantOrder = cfg.Order
		end
		if type(cfg.Versions) == "table" then
			for k, v in pairs(cfg.Versions) do
				if typeof(v) == "table" then
					VariantPrefix[k] = tostring(v.Prefix or VariantPrefix[k] or "")
				end
			end
		end
	end
end

local function startsWith(s, pref)
	return s:sub(1, #pref) == pref
end

local function detectVariant(text)
	text = tostring(text or "")
	for _, v in ipairs(VariantOrder) do
		if v ~= "Normal" then
			local pref = tostring(VariantPrefix[v] or (v .. " "))
			if pref ~= "" and startsWith(text, pref) then
				return v
			end
			local alt = v .. " "
			if startsWith(text, alt) then
				return v
			end
		end
	end
	return "Normal"
end

local function stripVariantPrefix(text, variantKey)
	text = tostring(text or "")
	if not variantKey or variantKey == "Normal" then
		return text
	end
	local pref = tostring(VariantPrefix[variantKey] or (variantKey .. " "))
	if pref ~= "" and startsWith(text, pref) then
		local out = text:sub(#pref + 1)
		if out ~= "" then
			return out
		end
	end
	local alt = variantKey .. " "
	if startsWith(text, alt) then
		local out = text:sub(#alt + 1)
		if out ~= "" then
			return out
		end
	end
	return text
end

local function applyVariantLabel(hoverGui, variantKey, enabled)
	if not hoverGui then
		return
	end
	for _, d in ipairs(hoverGui:GetDescendants()) do
		if d:IsA("GuiObject") then
			for _, v in ipairs(VariantOrder) do
				if d.Name == v then
					d.Visible = enabled and (v == variantKey)
				end
			end
		end
	end
end

function Interaction.BuildHoverRefs(model, ensurePrimaryPart)
	local primary = ensurePrimaryPart(model)
	if not primary then
		return nil
	end
	local hover = ensureHoverGui(primary)
	if not hover then
		return nil
	end

	local income = getTextTarget(hover, "Income")
	local nameT = getTextTarget(hover, "Name")
	local rarityT = getTextTarget(hover, "Rarity")

	local timeLeftContainer = hover:FindFirstChild("TimeLeft", true)
	local timeT
	local timeImg
	if timeLeftContainer then
		timeT = getTextTarget(timeLeftContainer, "TextL")
		if not timeT then
			timeT = timeLeftContainer:FindFirstChildWhichIsA("TextLabel", true) or timeLeftContainer:FindFirstChildWhichIsA("TextButton", true) or timeLeftContainer:FindFirstChildWhichIsA("TextBox", true)
		end
		timeImg = timeLeftContainer:FindFirstChild("ImageLabel", true)
		if not timeImg then
			timeImg = timeLeftContainer:FindFirstChildWhichIsA("ImageLabel", true)
		end
	end
	if not timeT then
		timeT = getTextTarget(hover, "TextL") or getTextTarget(hover, "TimeLeft")
	end

	return {
		Gui = hover,
		Income = income,
		Name = nameT,
		Rarity = rarityT,
		Time = timeT,
		TimeImage = timeImg,
	}
end

local ReplicatedStorage2 = game:GetService("ReplicatedStorage")
local RarityTexts = ReplicatedStorage2:WaitForChild("Rarities"):WaitForChild("Texts")
local function clearRarityLabel(label)
	if label:IsA("TextLabel") then
		label.Text = ""
	end

	for _, child in ipairs(label:GetChildren()) do
		child:Destroy()
	end
end

local function applyRarityFromStorage(rarityLabel, rarityName)
	if not rarityLabel or rarityName == "" then
		return
	end

	clearRarityLabel(rarityLabel)

	local template = nil
	template = RarityTexts:FindFirstChild(rarityName)

	if not template then
		for _, obj in ipairs(RarityTexts:GetChildren()) do
			if obj:IsA("TextLabel") and obj.Name == rarityName then
				template = obj
				break
			end
		end
	end

	if not template or not template:IsA("TextLabel") then
		if rarityLabel:IsA("TextLabel") then
			rarityLabel.Text = rarityName
		end
		return
	end
	rarityLabel.Text = tostring(rarityName)

	for _, child in ipairs(template:GetChildren()) do
		child:Clone().Parent = rarityLabel
	end
end

function Interaction.SetHoverText(refs, entry, rarity, remaining, held)
	if not refs then
		return
	end

	local info = entry.Info
	local income = tonumber(info.Income) or 0

	local rawName = tostring(info.Name or info.DisplayName or entry.Id or "")
	local rawRarity = tostring(info.Rarity or rarity or "")

	local variantKey = detectVariant(rawName)
	if variantKey == "Normal" then
		variantKey = detectVariant(rawRarity)
	end

	local displayName = stripVariantPrefix(rawName, variantKey)
	local displayRarity = stripVariantPrefix(rawRarity, variantKey)

	if refs.Income then
		refs.Income.Text = tostring(income) .. CurrencyUtil.getPerSecondSuffix()
	end
	if refs.Name then
		refs.Name.Text = displayName
	end

	if refs.Rarity then
		applyRarityFromStorage(refs.Rarity, displayRarity)
	end

	if refs.Gui then
		refs.Gui.Enabled = not held
		applyVariantLabel(refs.Gui, variantKey, not held)
	end
	if refs.Time then
		refs.Time.Visible = not held
		if not held then
			refs.Time.Text = tostring(math.max(0, remaining)) .. "s"
		end
	end
	if refs.TimeImage then
		refs.TimeImage.Visible = not held
	end
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

local function isRagdollState(state)
	return state == Enum.HumanoidStateType.Ragdoll
		or state == Enum.HumanoidStateType.Physics
		or state == Enum.HumanoidStateType.FallingDown
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

local function dropHeldCrewMember(ctx, player, model, st, dropPosition)
	if not model or not model.Parent then
		return
	end
	if not st or not st.Held then
		return
	end

	local userId = player.UserId
	clearCarriedCrewMemberAttributes(player)
	player:SetAttribute(HORO_PROJECTION_CARRY_ATTRIBUTE, nil)

	ctx.HeldByUserId[userId] = nil
	disconnectDeath(ctx, userId)
	disconnectRagdoll(ctx, userId)
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
	st.LastUpdate = os.clock()
	setDropPhysics(model)
	scheduleDroppedCrewMemberSettle(ctx, model, st)

	if st.Prompt then
		st.Prompt.Enabled = true
	end

	Interaction.SetHoverText(st.HoverRefs, st.Entry, st.Rarity, math.ceil(st.Remaining), false)
end

local function carryCrewMemberOnPart(ctx, player, model, st, carrierPart)
	if not ctx or not player or not model or not model.Parent or not st or st.Held then
		return false
	end
	if not canPlayerCarryModel(player, model) then
		return false
	end
	if ctx.HeldByUserId[player.UserId] then
		return false
	end
	if player:GetAttribute("CarriedMajorRewardType") ~= nil then
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
	model:SetAttribute(CARRIED_MODEL_ATTRIBUTE, true)
	setCarryPhysics(model, true, player)
	setCarriedHumanoidState(model, st, true)
	ensureCarryAssemblyWelds(model, primary)

	local rotOnly = computeHeadRotOnly(attachPart)
	local top = attachPart.Position + Vector3.yAxis * (attachPart.Size.Y / 2)
	local pivotTarget = computePivotBottomOnPoint(model, top, rotOnly)
	model:PivotTo(pivotTarget)

	st.CarryRootLocalCFrame = attachPart.CFrame:ToObjectSpace(primary.CFrame)
	captureCarryPartOffsets(model, primary, st)
	createCarryAttachmentWeld(st, primary, attachPart)
	startCarryPhysicsEnforcer(st, model, player)
	model.Parent = ctx.CarriedFolder

	st.LastUpdate = os.clock()
	Interaction.SetHoverText(st.HoverRefs, st.Entry, st.Rarity, math.ceil(st.Remaining), true)

	ctx.HeldByUserId[player.UserId] = model
	player:SetAttribute(HORO_PROJECTION_CARRY_ATTRIBUTE, nil)

	setCarriedCrewMemberAttributes(player, resolveCanonicalCrewMemberData(model, st))

	disconnectDeath(ctx, player.UserId)
	disconnectRagdoll(ctx, player.UserId)

	ctx.DeathConnByUserId[player.UserId] = hum.Died:Connect(function()
		local heldModel = ctx.HeldByUserId[player.UserId]
		if not heldModel or not heldModel.Parent then
			return
		end
		if st.Model ~= heldModel then
			return
		end
		dropHeldCrewMember(ctx, player, heldModel, st)
	end)

	ctx.RagdollConnByUserId[player.UserId] = hum.StateChanged:Connect(function(_, newState)
		if not isRagdollState(newState) then
			return
		end

		local heldModel = ctx.HeldByUserId[player.UserId]
		if not heldModel or not heldModel.Parent then
			return
		end
		if st.Model ~= heldModel then
			return
		end

		dropHeldCrewMember(ctx, player, heldModel, st)
	end)

	return true
end

function Interaction.HasHeld(ctx, player)
	ctx = ctx or activeContext
	return ctx ~= nil and player ~= nil and ctx.HeldByUserId[player.UserId] ~= nil
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

function Interaction.DropHeldAtPosition(ctx, player, active, dropPosition)
	ctx = ctx or activeContext
	active = active or (ctx and ctx.Active)
	if not ctx or not active or not player then
		return false, "missing_context"
	end

	local model = ctx.HeldByUserId[player.UserId]
	if not model or not model.Parent then
		ctx.HeldByUserId[player.UserId] = nil
		return false, "no_held_crew_member"
	end

	local st = active[model]
	if not st then
		return false, "missing_state"
	end

	dropHeldCrewMember(ctx, player, model, st, dropPosition)
	return true
end

function Interaction.CollectHeld(ctx, player, active)
	active = active or (ctx and ctx.Active)
	local userId = player.UserId
	local model = ctx.HeldByUserId[userId]
	if not model or not model.Parent then
		ctx.HeldByUserId[userId] = nil
		disconnectDeath(ctx, userId)
		disconnectRagdoll(ctx, userId)  
		return nil
	end
	clearCarriedCrewMemberAttributes(player)
	player:SetAttribute(HORO_PROJECTION_CARRY_ATTRIBUTE, nil)

	local st = active[model]
	local crewMemberData = resolveCanonicalCrewMemberData(model, st)
	local storageName = resolveCrewMemberStorageName(model, st, crewMemberData)
	local isTutorialCrewMember = model:GetAttribute(TUTORIAL_CREW_MEMBER_ATTRIBUTE) == true
	local tutorialOwnerUserId = model:GetAttribute(TUTORIAL_OWNER_ATTRIBUTE)
	local tutorialToken = tostring(model:GetAttribute(TUTORIAL_TOKEN_ATTRIBUTE) or "")
	local tutorialRewardName = tostring(model:GetAttribute(TUTORIAL_REWARD_NAME_ATTRIBUTE) or "")

	ctx.HeldByUserId[userId] = nil
	disconnectDeath(ctx, userId)
	disconnectRagdoll(ctx, userId)
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

	if st then
		return {
			Name = storageName,
			CrewMemberId = crewMemberData and crewMemberData.CrewMemberId or nil,
			DisplayName = crewMemberData and crewMemberData.DisplayName or nil,
			Image = crewMemberData and crewMemberData.Image or nil,
			OriginData = st.OriginData,
			SlotIndex = st.SlotIndex,
			TutorialCrewMember = isTutorialCrewMember,
			TutorialOwnerUserId = tutorialOwnerUserId,
			TutorialToken = tutorialToken,
			TutorialRewardName = tutorialRewardName,
		}
	end

	return {
		Name = storageName,
		CrewMemberId = crewMemberData and crewMemberData.CrewMemberId or nil,
		DisplayName = crewMemberData and crewMemberData.DisplayName or nil,
		Image = crewMemberData and crewMemberData.Image or nil,
		TutorialCrewMember = isTutorialCrewMember,
		TutorialOwnerUserId = tutorialOwnerUserId,
		TutorialToken = tutorialToken,
		TutorialRewardName = tutorialRewardName,
	}
end

function Interaction.BindPrompt(ctx, model, st, ensurePrimaryPart)
	local primary = ensurePrimaryPart(model)
	if not primary then
		return nil
	end

	local prompt = ensurePrompt(primary)

	local rawName = tostring(st.Entry and st.Entry.Info and (st.Entry.Info.Name or st.Entry.Info.DisplayName) or st.Entry and st.Entry.Id or model.Name)
	local rawRarity = tostring(st.Entry and st.Entry.Info and st.Entry.Info.Rarity or st.Rarity or "")

	local variantKey = detectVariant(rawName)
	if variantKey == "Normal" then
		variantKey = detectVariant(rawRarity)
	end

	local displayName = stripVariantPrefix(rawName, variantKey)

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
		if ctx.HeldByUserId[player.UserId] then
			return
		end
		if player:GetAttribute("CarriedMajorRewardType") ~= nil then
			return
		end

		carryCrewMemberOnPart(ctx, player, model, st)
	end)

	return prompt
end

function Interaction.OnPlayerRemoving(ctx, plr, active)
	local userId = plr.UserId
	local m = ctx.HeldByUserId[userId]
	ctx.HeldByUserId[userId] = nil
	disconnectDeath(ctx, userId)
	disconnectRagdoll(ctx, userId) 

	if not m or not m.Parent then
		return
	end
	local st = active[m]
	if not st then
		return
	end

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
	st.LastUpdate = os.clock()
	setDropPhysics(m)
	scheduleDroppedCrewMemberSettle(ctx, m, st)

	if st.Prompt then
		st.Prompt.Enabled = true
	end
end

return Interaction
