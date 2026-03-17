local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Interaction = {}
local CurrencyUtil = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("CurrencyUtil"))

local function forEachPart(model, fn)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			fn(d)
		end
	end
end

local function setCarryPhysics(model, held)
	forEachPart(model, function(p)
		p.Anchored = not held
		p.CanCollide = not held
		p.Massless = held
		p.AssemblyLinearVelocity = Vector3.zero
		p.AssemblyAngularVelocity = Vector3.zero
	end)
end

local function setDropPhysics(model)
	forEachPart(model, function(p)
		p.Anchored = false
		p.CanCollide = true
		p.Massless = false
		p.AssemblyLinearVelocity = Vector3.zero
		p.AssemblyAngularVelocity = Vector3.zero
	end)
end

local function anchorAll(model)
	forEachPart(model, function(p)
		p.Anchored = true
		p.AssemblyLinearVelocity = Vector3.zero
		p.AssemblyAngularVelocity = Vector3.zero
	end)
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
	local h = primaryPart:FindFirstChild("BrainrotHover", true)
	if h and h:IsA("BillboardGui") then
		return h
	end
	h = primaryPart:FindFirstChild("BrainortHover", true)
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
	local template = rarities and rarities:FindFirstChild("BrainrotHover")
	if not template or not template:IsA("BillboardGui") then
		return nil
	end

	local clone = template:Clone()
	clone.Name = "BrainrotHover"
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
		return require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("BrainrotVariants"))
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
	params.FilterType = Enum.RaycastFilterType.Blacklist
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

local function settleToGroundThenAnchor(model)
	local primary = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
	local t0 = os.clock()
	while model.Parent and os.clock() - t0 < 2.5 do
		task.wait(0.08)
		if not primary or not primary.Parent then
			primary = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
		end
		if primary then
			local origin = primary.Position
			local params = RaycastParams.new()
			params.FilterType = Enum.RaycastFilterType.Blacklist
			params.FilterDescendantsInstances = { model }
			local r = workspace:Raycast(origin, Vector3.new(0, -12, 0), params)
			if r and (origin.Y - r.Position.Y) <= 1.2 then
				break
			end
		end
	end
	if not model.Parent then
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
	anchorAll(model)
end

local function isRagdollState(state)
	return state == Enum.HumanoidStateType.Ragdoll
		or state == Enum.HumanoidStateType.Physics
		or state == Enum.HumanoidStateType.FallingDown
end

function Interaction.NewContext(map)
	local worldFolder = map:FindFirstChild("BrainrotsWorld") or Instance.new("Folder")
	worldFolder.Name = "BrainrotsWorld"
	worldFolder.Parent = map

	local carriedFolder = worldFolder:FindFirstChild("Carried") or Instance.new("Folder")
	carriedFolder.Name = "Carried"
	carriedFolder.Parent = worldFolder

	local droppedFolder = worldFolder:FindFirstChild("Dropped") or Instance.new("Folder")
	droppedFolder.Name = "Dropped"
	droppedFolder.Parent = worldFolder

	return {
		CarriedFolder = carriedFolder,
		DroppedFolder = droppedFolder,
		HeldByUserId = {},
		DeathConnByUserId = {},
		RagdollConnByUserId = {},
	}
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

local function dropHeldBrainrot(ctx, player, model, st)
	if not model or not model.Parent then
		return
	end
	if not st or not st.Held then
		return
	end

	local userId = player.UserId
	player:SetAttribute("CarriedBrainrot", nil)
	player:SetAttribute("CarriedBrainrotImage", nil)

	ctx.HeldByUserId[userId] = nil
	disconnectDeath(ctx, userId)
	disconnectRagdoll(ctx, userId)

	if st.Weld then
		pcall(function()
			st.Weld:Destroy()
		end)
	end
	st.Weld = nil

	model.Parent = ctx.DroppedFolder

	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	local dropPos = hrp and hrp.Position or model:GetPivot().Position

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

	setDropPhysics(model)
	task.spawn(function()
		settleToGroundThenAnchor(model)
	end)

	st.Held = false
	st.HolderUserId = nil
	st.LastUpdate = os.clock()

	if st.Prompt then
		st.Prompt.Enabled = true
	end

	Interaction.SetHoverText(st.HoverRefs, st.Entry, st.Rarity, math.ceil(st.Remaining), false)
end

function Interaction.CollectHeld(ctx, player, active)
	local userId = player.UserId
	local model = ctx.HeldByUserId[userId]
	if not model or not model.Parent then
		ctx.HeldByUserId[userId] = nil
		disconnectDeath(ctx, userId)
		disconnectRagdoll(ctx, userId)  
		return nil
	end
	player:SetAttribute("CarriedBrainrot", nil)
	player:SetAttribute("CarriedBrainrotImage", nil)

	local st = active[model]
	local brainrotName = model.Name
	if st and st.Entry then
		brainrotName = tostring(st.Entry.Id or brainrotName)
	end

	ctx.HeldByUserId[userId] = nil
	disconnectDeath(ctx, userId)
	disconnectRagdoll(ctx, userId)

	active[model] = nil
	pcall(function()
		model:Destroy()
	end)

	if st then
		return {
			Name = brainrotName,
			OriginData = st.OriginData,
			SlotIndex = st.SlotIndex,
		}
	end

	return { Name = brainrotName }
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

		local char = player.Character
		if not char then
			return
		end
		local head = char:FindFirstChild("Head")
		local hum = char:FindFirstChildOfClass("Humanoid")
		if not head or not hum or hum.Health <= 0 then
			return
		end

		prompt.Enabled = false

		setCarryPhysics(model, true)
		model.Parent = ctx.CarriedFolder

		local rotOnly = computeHeadRotOnly(head)
		local top = head.Position + Vector3.yAxis * (head.Size.Y / 2)
		local pivotTarget = computePivotBottomOnPoint(model, top, rotOnly)
		model:PivotTo(pivotTarget)

		local weld = Instance.new("WeldConstraint")
		weld.Part0 = primary
		weld.Part1 = head
		weld.Parent = primary
		st.Weld = weld

		st.Held = true
		st.HolderUserId = player.UserId
		st.LastUpdate = os.clock()
		Interaction.SetHoverText(st.HoverRefs, st.Entry, st.Rarity, math.ceil(st.Remaining), true)

		ctx.HeldByUserId[player.UserId] = model
		player:SetAttribute("CarriedBrainrot", tostring(model.Name))

		local render = ""
		if st and st.Entry and st.Entry.Info and st.Entry.Info.Render then
			render = tostring(st.Entry.Info.Render)
		end

		if render ~= "" then
			player:SetAttribute("CarriedBrainrotImage", render)
		else
			player:SetAttribute("CarriedBrainrotImage", nil)
		end

		disconnectDeath(ctx, player.UserId)
		disconnectRagdoll(ctx, player.UserId)

		ctx.DeathConnByUserId[player.UserId] = hum.Died:Connect(function()
			local m = ctx.HeldByUserId[player.UserId]
			if not m or not m.Parent then
				return
			end
			if st.Model ~= m then
				return
			end
			dropHeldBrainrot(ctx, player, m, st)
		end)

		ctx.RagdollConnByUserId[player.UserId] = hum.StateChanged:Connect(function(_, newState)
			if not isRagdollState(newState) then
				return
			end

			local m = ctx.HeldByUserId[player.UserId]
			if not m or not m.Parent then
				return
			end
			if st.Model ~= m then
				return
			end

			dropHeldBrainrot(ctx, player, m, st)
		end)
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

	if st.Weld then
		pcall(function()
			st.Weld:Destroy()
		end)
	end
	st.Weld = nil

	m.Parent = ctx.DroppedFolder
	plr:SetAttribute("CarriedBrainrot", nil)
	plr:SetAttribute("CarriedBrainrotImage", nil)

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

	setDropPhysics(m)
	task.spawn(function()
		settleToGroundThenAnchor(m)
	end)

	st.Held = false
	st.HolderUserId = nil
	st.LastUpdate = os.clock()

	if st.Prompt then
		st.Prompt.Enabled = true
	end
end

return Interaction
