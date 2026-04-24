local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local Configs = Modules:WaitForChild("Configs")
local MapResolver = require(Modules:WaitForChild("MapResolver"))
local ServerMods = Modules:WaitForChild("Server"):WaitForChild("Brainrot")

local SpawnerConfig = require(Configs:WaitForChild("BrainrotSpawnSettings"))
local SpawnPartsCfg = require(Configs:WaitForChild("SpawnParts"))
local Registry = require(ServerMods:WaitForChild("Registry"))
local Placement = require(ServerMods:WaitForChild("Placement"))
local Interaction = require(ServerMods:WaitForChild("Interaction"))

local entries, maxTier, globalMaxFoot = Registry.Build()
local STARTUP_TRACE = RunService:IsStudio()
local VALID_RARITY_NAMES = SpawnPartsCfg.RarityTier or {}

if STARTUP_TRACE then
	print("[SPAWN TRACE] startup awaiting MapResolver refs required=MapRoot,HitBox hitBoxRequired=true")
end

local resolvedMapRefs = MapResolver.WaitForRefs(
	{ "MapRoot", "HitBox" },
	nil,
	{
		warn = true,
		context = "SpawnBrainrots",
	}
)
local map = resolvedMapRefs.MapRoot
local legacySpawnFolder = resolvedMapRefs.SpawnFolder
local hitBox = resolvedMapRefs.HitBox
local biomesRoot = resolvedMapRefs.Biomes or (map and map:FindFirstChild("Biomes"))

if STARTUP_TRACE then
	print(string.format(
		"[SPAWN TRACE] startup refsReady hitBoxRequired=true hitBoxNil=%s spawnSetupContinues=%s map=%s biomesRoot=%s legacySpawnFolder=%s hitBox=%s",
		tostring(hitBox == nil),
		tostring(hitBox ~= nil),
		map and map:GetFullName() or "<nil>",
		biomesRoot and biomesRoot:GetFullName() or "<nil>",
		legacySpawnFolder and legacySpawnFolder:GetFullName() or "<nil>",
		hitBox and hitBox:GetFullName() or "<nil>"
	))
end

local ctx = Interaction.NewContext(map)
local AddBrainrot = require(script.Parent.Parent.Modules.AddBrainrot)
local QuestSignals = require(ServerScriptService.Modules:WaitForChild("GrandLineRushQuestSignals"))

local rng = Random.new()
local DEBUG_TRACE = RunService:IsStudio()
local loggedHitBoxTouchByPlayer = {}
local spawnWarnThrottleByKey = {}

local function formatVector3(value)
	if typeof(value) ~= "Vector3" then
		return tostring(value)
	end

	return string.format("(%.2f, %.2f, %.2f)", value.X, value.Y, value.Z)
end

local function formatInstancePath(instance)
	if not instance then
		return "<nil>"
	end

	return instance:GetFullName()
end

local function mapTrace(message, ...)
	if not DEBUG_TRACE then
		return
	end

	print(string.format("[MAP TRACE] " .. message, ...))
end

local function spawnTrace(message, ...)
	if not DEBUG_TRACE then
		return
	end

	print(string.format("[SPAWN TRACE] " .. message, ...))
end

local function spawnWarn(message, ...)
	if not DEBUG_TRACE then
		return
	end

	warn(string.format("[SPAWN WARN] " .. message, ...))
end

local function spawnWarnThrottled(key, message, ...)
	if not DEBUG_TRACE then
		return
	end

	local now = os.clock()
	local last = spawnWarnThrottleByKey[key]
	if last and (now - last) < 5 then
		return
	end

	spawnWarnThrottleByKey[key] = now
	warn(string.format("[SPAWN WARN] " .. message, ...))
end

local function spawnError(message, ...)
	if not DEBUG_TRACE then
		return
	end

	warn(string.format("[SPAWN ERROR] " .. message, ...))
end

local function zoneTrace(message, ...)
	if not DEBUG_TRACE then
		return
	end

	print(string.format("[ZONE TRACE] " .. message, ...))
end

local function runTrace(message, ...)
	if not DEBUG_TRACE then
		return
	end

	print(string.format("[RUN TRACE] " .. message, ...))
end

local ServerLuck = workspace:WaitForChild("ServerLuck")
local CurrentEvent = workspace:WaitForChild("CurrentEvent")

local RUSH_TRIM_SECONDS = 3

local ServerEvents = ReplicatedStorage:FindFirstChild("ServerEvents")
if not ServerEvents then
	ServerEvents = Instance.new("Folder")
	ServerEvents.Name = "ServerEvents"
	ServerEvents.Parent = ReplicatedStorage
end

local LikeGoalSpawnSecret = ServerEvents:FindFirstChild("LikeGoalSpawnSecret")
if not LikeGoalSpawnSecret then
	LikeGoalSpawnSecret = Instance.new("BindableEvent")
	LikeGoalSpawnSecret.Name = "LikeGoalSpawnSecret"
	LikeGoalSpawnSecret.Parent = ServerEvents
end

mapTrace(
	"SpawnBrainrots requestedMap=%s activeMap=%s mapPath=%s biomesRoot=%s legacySpawnFolder=%s hitBox=%s hitBoxPos=%s",
	tostring(resolvedMapRefs.RequestedMapName),
	tostring(resolvedMapRefs.ActiveMapName),
	formatInstancePath(map),
	formatInstancePath(biomesRoot),
	formatInstancePath(legacySpawnFolder),
	formatInstancePath(hitBox),
	formatVector3(hitBox and hitBox.Position or nil)
)
zoneTrace(
	"brainrotHitBox activeMap=%s mapPath=%s boundary=%s boundaryPos=%s boundarySize=%s",
	tostring(resolvedMapRefs.ActiveMapName),
	formatInstancePath(map),
	formatInstancePath(hitBox),
	formatVector3(hitBox and hitBox.Position or nil),
	formatVector3(hitBox and hitBox.Size or nil)
)
spawnTrace(
	"startup map=%s biomesRoot=%s usingBiomePads=%s legacySpawnFolder=%s acceptedRarities=%s brainrotsWorld=%s carried=%s dropped=%s",
	formatInstancePath(map),
	formatInstancePath(biomesRoot),
	tostring(biomesRoot ~= nil),
	formatInstancePath(legacySpawnFolder),
	table.concat((function()
		local names = {}
		for rarityName in pairs(VALID_RARITY_NAMES) do
			names[#names + 1] = tostring(rarityName)
		end
		table.sort(names)
		return names
	end)(), ", "),
	formatInstancePath(map:FindFirstChild("BrainrotsWorld")),
	formatInstancePath(ctx and ctx.CarriedFolder),
	formatInstancePath(ctx and ctx.DroppedFolder)
)

local function shallowCopy(t)
	local n = {}
	for k, v in pairs(t) do
		n[k] = v
	end
	return n
end

local function normalizeEventName(s)
	s = tostring(s or "")
	s = s:lower()
	s = s:gsub("%s+", "")
	s = s:gsub("_", "")
	return s
end

local function getForcedVariantKey()
	local ev = normalizeEventName(CurrentEvent.Value)
	if ev == "goldenrush" then
		return "Golden"
	end
	if ev == "diamondrush" or ev == "diamonddrush" then
		return "Diamond"
	end
	return nil
end

local function getPlayerPositions()
	local positions = {}
	for _, plr in ipairs(Players:GetPlayers()) do
		local ch = plr.Character
		if ch then
			local hrp = ch:FindFirstChild("HumanoidRootPart")
			if hrp then
				positions[#positions + 1] = hrp.Position
			end
		end
	end
	return positions
end

local function anyPlayerNearPart(spawnPart, positions, radius)
	local r2 = radius * radius
	local p = spawnPart.Position
	for i = 1, #positions do
		local d = positions[i] - p
		if d.X * d.X + d.Y * d.Y + d.Z * d.Z <= r2 then
			return true
		end
	end
	return false
end

local function getServerLuckMult()
	local v = tonumber(ServerLuck.Value) or 1
	if v < 1 then v = 1 end
	return v
end

local function weightForEntry(entry, partTier, serverLuckMult, chanceCap)
	local base = tonumber(entry.Info.Chance) or 0
	if base <= 0 then
		return 0
	end

	chanceCap = tonumber(chanceCap) or 100
	if base > chanceCap then
		return 0
	end

	serverLuckMult = tonumber(serverLuckMult) or 1
	if serverLuckMult <= 1 or maxTier <= 1 then
		return base
	end

	local LEGEND_TIER = tonumber((SpawnPartsCfg.RarityTier or {}).Legendary) or 5
	if (entry.Tier or 1) < LEGEND_TIER then
		return base
	end

	local partBias = math.clamp((partTier or 1) / maxTier, 0, 1)
	local denom = math.max(1, (maxTier - LEGEND_TIER))
	local highBias = math.clamp(((entry.Tier or 1) - LEGEND_TIER) / denom, 0, 1)
	local exponent = math.clamp(partBias * (0.35 + 0.65 * highBias), 0, 1)

	return base * math.exp(math.log(serverLuckMult) * exponent)
end

local function chooseForPart(partTier, serverLuckMult, chanceCap)
	local total = 0
	local eligible = {}

	for i = 1, #entries do
		local w = weightForEntry(entries[i], partTier, serverLuckMult, chanceCap)
		if w > 0 then
			total += w
			eligible[#eligible + 1] = entries[i]
		end
	end

	if #eligible == 0 then
		return entries[rng:NextInteger(1, #entries)]
	end

	if total <= 0 then
		return eligible[rng:NextInteger(1, #eligible)]
	end

	local pick = rng:NextNumber() * total
	local acc = 0

	for i = 1, #eligible do
		acc += weightForEntry(eligible[i], partTier, serverLuckMult, chanceCap)
		if pick <= acc then
			return eligible[i]
		end
	end

	return eligible[#eligible]
end

local function tryPlayIdle(model, animId)
	animId = tonumber(animId)
	if not animId or animId == 0 then
		return
	end
	local controller = model:FindFirstChildOfClass("Humanoid") or model:FindFirstChildOfClass("AnimationController")
	if not controller then
		return
	end
	local animator = controller:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = controller
	end
	local anim = Instance.new("Animation")
	anim.AnimationId = "rbxassetid://" .. tostring(animId)
	pcall(function()
		local track = animator:LoadAnimation(anim)
		track.Looped = true
		track:Play()
	end)
end

local partDataList = {}
local partDataByPart = {}

local function setupSpawnPart(spawnPart)
	local ok, err = xpcall(function()
		if partDataByPart[spawnPart] then
			return
		end

		if not spawnPart:IsA("BasePart") then
			spawnWarnThrottled(
				"setup_non_part_" .. formatInstancePath(spawnPart),
				"setupSpawnPart skipped reason=not_basepart instance=%s class=%s",
				formatInstancePath(spawnPart),
				tostring(spawnPart.ClassName)
			)
			return
		end

		local rarityName = spawnPart.Name
		if VALID_RARITY_NAMES[rarityName] == nil then
			spawnWarnThrottled(
				"setup_invalid_rarity_" .. formatInstancePath(spawnPart),
				"setupSpawnPart skipped reason=invalid_rarity_name part=%s name=%s class=%s",
				formatInstancePath(spawnPart),
				tostring(rarityName),
				tostring(spawnPart.ClassName)
			)
			return
		end

		local partTier = tonumber((SpawnPartsCfg.RarityTier or {})[rarityName]) or 1
		local chanceCap = tonumber((SpawnPartsCfg.LuckMult or {})[rarityName])
			or tonumber(SpawnPartsCfg.DefaultLuckMult)
			or 100

		local container = spawnPart:FindFirstChild("Brainrots")
		if not container then
			container = Instance.new("Folder")
			container.Name = "Brainrots"
			container.Parent = spawnPart
		end

		local spacing = (math.max(4, globalMaxFoot) * 1.2)

		local data = {
			Part = spawnPart,
			Name = rarityName,
			Tier = partTier,
			ChanceCap = chanceCap,
			Container = container,
			Spacing = spacing,
			SlotOccupied = {},
			SlotCooldown = {},
			SlotOffsets = {},
		}

		partDataByPart[spawnPart] = data
		partDataList[#partDataList + 1] = data

		spawnTrace(
			"setupSpawnPart part=%s rarity=%s pos=%s size=%s container=%s",
			formatInstancePath(spawnPart),
			tostring(rarityName),
			formatVector3(spawnPart.Position),
			formatVector3(spawnPart.Size),
			formatInstancePath(container)
		)
	end, debug.traceback)

	if not ok then
		spawnError(
			"setupSpawnPart failed instance=%s error=%s",
			formatInstancePath(spawnPart),
			tostring(err)
		)
	end
end

local function getBiomeScanRoot(biomeContainer)
	if not biomeContainer then
		return nil, nil
	end

	local innerBiome = biomeContainer:FindFirstChild(biomeContainer.Name)
	if innerBiome then
		return innerBiome, innerBiome
	end

	return biomeContainer, nil
end

local function processBiomeContainer(biomeContainer)
	local ok, err = xpcall(function()
		if not biomeContainer then
			return
		end

		local scanRoot, innerBiome = getBiomeScanRoot(biomeContainer)

		spawnTrace(
			"processBiome biome=%s scanRoot=%s innerBiome=%s",
			formatInstancePath(biomeContainer),
			formatInstancePath(scanRoot),
			formatInstancePath(innerBiome)
		)

		if scanRoot:IsA("BasePart") then
			setupSpawnPart(scanRoot)
		end

		for _, descendant in ipairs(scanRoot:GetDescendants()) do
			if descendant:IsA("BasePart") then
				setupSpawnPart(descendant)
			end
		end
	end, debug.traceback)

	if not ok then
		spawnError(
			"processBiome failed biome=%s error=%s",
			formatInstancePath(biomeContainer),
			tostring(err)
		)
	end
end

if not biomesRoot then
	spawnError(
		"spawnPadDiscovery failed reason=missing_biomes_root map=%s legacySpawnFolder=%s",
		formatInstancePath(map),
		formatInstancePath(legacySpawnFolder)
	)
else
	spawnTrace(
		"biomesRoot ready root=%s topLevelBiomeCount=%s",
		formatInstancePath(biomesRoot),
		tostring(#biomesRoot:GetChildren())
	)

	for _, biomeContainer in ipairs(biomesRoot:GetChildren()) do
		processBiomeContainer(biomeContainer)
	end

	biomesRoot.ChildAdded:Connect(function(child)
		task.defer(function()
			spawnTrace("biomesRoot childAdded biome=%s", formatInstancePath(child))
			processBiomeContainer(child)
		end)
	end)

	biomesRoot.DescendantAdded:Connect(function(descendant)
		task.defer(function()
			if descendant:IsA("BasePart") then
				setupSpawnPart(descendant)
			end
		end)
	end)
end

local active = {}
ctx.Active = active

local function expireBrainrot(model, st)
	if active[model] ~= st then
		return
	end
	if st.Held then
		return
	end

	if st.OriginData and st.SlotIndex then
		local od = st.OriginData
		local si = st.SlotIndex
		if od.SlotOccupied and od.SlotOccupied[si] == model then
			od.SlotOccupied[si] = nil
		end
		if od.SlotOffsets then
			od.SlotOffsets[si] = nil
		end
	end

	active[model] = nil
	pcall(function()
		model:Destroy()
	end)
end

local function rushTrimExistingOnce()
	for model, st in pairs(active) do
		if model and model.Parent and not st.Held then
			local newRemain = math.min(st.Remaining or 0, RUSH_TRIM_SECONDS)
			st.Remaining = newRemain
			st.LastUpdate = os.clock()
			st.LastShown = -1

			task.delay(RUSH_TRIM_SECONDS, function()
				expireBrainrot(model, st)
			end)
		end
	end
end

local lastForced = nil
local function onEventChanged()
	local forced = getForcedVariantKey()
	if forced and forced ~= lastForced then
		rushTrimExistingOnce()
	end
	lastForced = forced
end

CurrentEvent:GetPropertyChangedSignal("Value"):Connect(onEventChanged)
onEventChanged()

Players.PlayerRemoving:Connect(function(plr)
	Interaction.OnPlayerRemoving(ctx, plr, active)
end)

local hitDebounce = {}

hitBox.Touched:Connect(function(hit)
	if not hit or hit.Name ~= "HumanoidRootPart" then
		return
	end
	local char = hit.Parent
	if not char then
		return
	end
	local plr = Players:GetPlayerFromCharacter(char)
	if not plr then
		return
	end

	zoneTrace(
		"brainrotBoundaryTouched player=%s boundary=%s boundaryPos=%s activeMap=%s mapPath=%s",
		plr.Name,
		formatInstancePath(hitBox),
		formatVector3(hitBox.Position),
		tostring(resolvedMapRefs.ActiveMapName),
		formatInstancePath(map)
	)

	if not loggedHitBoxTouchByPlayer[plr.UserId] then
		loggedHitBoxTouchByPlayer[plr.UserId] = true
		spawnTrace(
			"hitBoxTouched player=%s hitBox=%s hitBoxPos=%s",
			plr.Name,
			formatInstancePath(hitBox),
			formatVector3(hitBox.Position)
		)
	end

	local now = os.clock()
	local last = hitDebounce[plr.UserId]
	if last and (now - last) < 0.35 then
		return
	end
	hitDebounce[plr.UserId] = now

	local info = Interaction.CollectHeld(ctx, plr, active)
	if info and info.Name then
		runTrace(
			"brainrotTurnIn player=%s boundary=%s activeMap=%s reward=%s slotIndex=%s origin=%s action=AddBrainrot",
			plr.Name,
			formatInstancePath(hitBox),
			tostring(resolvedMapRefs.ActiveMapName),
			tostring(info.Name),
			tostring(info.SlotIndex),
			tostring(info.OriginData ~= nil)
		)
		AddBrainrot:AddBrainrot(plr, info.Name, 1)
		QuestSignals.Record(plr, "ExtractCrew", 1, {
			Source = "SpawnBrainrots",
			CrewName = tostring(info.Name),
			ActiveMap = tostring(resolvedMapRefs.ActiveMapName or ""),
		})
		if info.OriginData and info.SlotIndex then
			local od = info.OriginData
			local si = info.SlotIndex
			if od.SlotOccupied and od.SlotOccupied[si] then
				od.SlotOccupied[si] = nil
			end
			if od.SlotOffsets then
				od.SlotOffsets[si] = nil
			end
			if od.SlotCooldown then
				od.SlotCooldown[si] = os.clock() + rng:NextNumber(4, 6)
			end
		end
	else
		runTrace(
			"brainrotTurnInSkipped player=%s boundary=%s activeMap=%s reason=no_held_brainrot",
			plr.Name,
			formatInstancePath(hitBox),
			tostring(resolvedMapRefs.ActiveMapName)
		)
	end
end)

local function registerActive(model, entry, originData, slotIndex)
	local tl = tonumber(entry.Info.TimeLeft) or 0
	if tl <= 0 then
		tl = 30
	end

	local hoverRefs = Interaction.BuildHoverRefs(model, Placement.EnsurePrimaryPart)

	local st = {
		Model = model,
		Entry = entry,
		Rarity = entry.Rarity,
		Remaining = tl,
		LastUpdate = os.clock(),
		LastShown = -1,
		HoverRefs = hoverRefs,
		Held = false,
		HolderUserId = nil,
		Prompt = nil,
		Weld = nil,
		OriginData = originData,
		SlotIndex = slotIndex,
	}

	active[model] = st
	Interaction.SetHoverText(hoverRefs, entry, entry.Rarity, tl, false)
	st.Prompt = Interaction.BindPrompt(ctx, model, st, Placement.EnsurePrimaryPart)

	return st
end

local function occupiedCount(data)
	local c = 0
	for i = 1, SpawnerConfig.MaxPerPart do
		if data.SlotOccupied[i] then
			c += 1
		end
	end
	return c
end

local function findFreeSlotRandom(data, now)
	local candidates = {}
	for i = 1, SpawnerConfig.MaxPerPart do
		if not data.SlotOccupied[i] then
			local cd = data.SlotCooldown[i]
			if not cd or cd <= now then
				candidates[#candidates + 1] = i
			end
		end
	end
	if #candidates == 0 then
		return nil
	end
	return candidates[rng:NextInteger(1, #candidates)]
end

local function pickRandomOffset(data, halfX, halfZ)
	local dist = data.Spacing
	local dist2 = dist * dist
	for _ = 1, 80 do
		local x = rng:NextNumber(-halfX, halfX)
		local z = rng:NextNumber(-halfZ, halfZ)
		local ok = true
		for i = 1, SpawnerConfig.MaxPerPart do
			if data.SlotOccupied[i] then
				local o = data.SlotOffsets[i]
				if o then
					local dx = x - o.X
					local dz = z - o.Y
					if (dx * dx + dz * dz) < dist2 then
						ok = false
						break
					end
				end
			end
		end
		if ok then
			return Vector2.new(x, z)
		end
	end
	return Vector2.new(rng:NextNumber(-halfX, halfX), rng:NextNumber(-halfZ, halfZ))
end

local function getSameNameSpawnPartPaths(rarityName)
	local paths = {}

	for i = 1, #partDataList do
		local data = partDataList[i]
		if data and data.Part and data.Name == rarityName then
			paths[#paths + 1] = formatInstancePath(data.Part)
		end
	end

	table.sort(paths)
	return paths
end

local function spawnOne(data)
	local ok, result = xpcall(function()
		local now = os.clock()
		local occupied = occupiedCount(data)
		if occupied >= SpawnerConfig.MaxPerPart then
			spawnWarnThrottled(
				"spawn_skip_max_" .. formatInstancePath(data.Part),
				"spawnOne skipped reason=max_per_part spawnPart=%s occupied=%s max=%s",
				formatInstancePath(data.Part),
				tostring(occupied),
				tostring(SpawnerConfig.MaxPerPart)
			)
			return false
		end

		local freeIndex = findFreeSlotRandom(data, now)
		if not freeIndex then
			spawnWarnThrottled(
				"spawn_skip_no_slot_" .. formatInstancePath(data.Part),
				"spawnOne skipped reason=no_free_slot spawnPart=%s occupied=%s cooldowns_active=true",
				formatInstancePath(data.Part),
				tostring(occupied)
			)
			return false
		end

		local baseEntry = chooseForPart(data.Tier, getServerLuckMult(), data.ChanceCap)
		if not baseEntry then
			spawnWarnThrottled(
				"spawn_skip_no_entry_" .. formatInstancePath(data.Part),
				"spawnOne skipped reason=no_base_entry spawnPart=%s rarity=%s tier=%s chanceCap=%s",
				formatInstancePath(data.Part),
				tostring(data.Name),
				tostring(data.Tier),
				tostring(data.ChanceCap)
			)
			return false
		end

		local forcedVariant = getForcedVariantKey()
		local variantKey = forcedVariant or Registry.RollVariant(rng)

		local template, usedVariant = Registry.GetTemplateWithFallback(baseEntry.Id, variantKey)
		if not template then
			spawnWarnThrottled(
				"spawn_skip_no_template_" .. tostring(baseEntry.Id) .. "_" .. tostring(variantKey),
				"spawnOne skipped reason=no_template spawnPart=%s rarity=%s brainrot=%s requestedVariant=%s",
				formatInstancePath(data.Part),
				tostring(baseEntry.Rarity),
				tostring(baseEntry.Id),
				tostring(variantKey)
			)
			return false
		end
		variantKey = usedVariant

		local finalId = Registry.MakeVariantId(baseEntry.Id, variantKey)
		local finalInfo = Registry.GetOrBuildVariantInfo(baseEntry.Id, variantKey)
		if not finalInfo then
			spawnWarnThrottled(
				"spawn_skip_no_info_" .. tostring(finalId),
				"spawnOne skipped reason=no_final_info spawnPart=%s rarity=%s brainrot=%s variant=%s",
				formatInstancePath(data.Part),
				tostring(baseEntry.Rarity),
				tostring(baseEntry.Id),
				tostring(variantKey)
			)
			return false
		end

		if forcedVariant then
			local copied = shallowCopy(finalInfo)
			copied.TimeLeft = baseEntry.Info.TimeLeft
			finalInfo = copied
		end

		local rarityLabel = tostring(baseEntry.Rarity or "Common")
		if variantKey ~= "Normal" then
			rarityLabel = variantKey .. " " .. rarityLabel
		end

		local entry = {
			Id = finalId,
			Info = finalInfo,
			Template = template,
			Rarity = rarityLabel,
			Tier = baseEntry.Tier,
			Foot = baseEntry.Foot,
			BaseId = baseEntry.Id,
			Variant = variantKey,
		}

		local clone = template:Clone()
		clone.Name = finalId
		clone.Parent = data.Container

		Placement.EnsurePrimaryPart(clone)
		Placement.AnchorModel(clone)

		local scaleVal = Instance.new("NumberValue")
		scaleVal.Value = SpawnerConfig.InitialScale
		scaleVal.Parent = clone

		pcall(function()
			clone:ScaleTo(scaleVal.Value)
		end)

		local _, initSize = clone:GetBoundingBox()
		local s0 = math.max(0.001, scaleVal.Value)
		local finalSize = initSize / s0

		local effX = data.Part.Size.X * 0.9
		local effZ = data.Part.Size.Z * 0.9
		local halfX = math.max(0, (effX / 2) - (finalSize.X / 2))
		local halfZ = math.max(0, (effZ / 2) - (finalSize.Z / 2))

		local offsetXZ = pickRandomOffset(data, halfX, halfZ)
		local yaw = rng:NextNumber(0, math.pi * 2)

		data.SlotOffsets[freeIndex] = offsetXZ
		Placement.AlignModelOnPartUpright(clone, data.Part, offsetXZ, yaw)
		data.SlotOccupied[freeIndex] = clone

		local pivotPosition = clone:GetPivot().Position
		local matchingCandidatePaths = getSameNameSpawnPartPaths(data.Name)
		spawnTrace(
			"spawnOne spawnPadRarity=%s chosenRarity=%s brainrot=%s variant=%s candidateCount=%s candidates=%s chosenSpawnPart=%s chosenSpawnPartPos=%s finalParent=%s finalPivot=%s offset=%s",
			tostring(data.Name),
			tostring(rarityLabel),
			tostring(baseEntry.Id),
			tostring(variantKey),
			tostring(#matchingCandidatePaths),
			table.concat(matchingCandidatePaths, " | "),
			formatInstancePath(data.Part),
			formatVector3(data.Part.Position),
			formatInstancePath(clone.Parent),
			formatVector3(pivotPosition),
			formatVector3(Vector3.new(offsetXZ.X, 0, offsetXZ.Y))
		)

		local conn
		conn = scaleVal.Changed:Connect(function(v)
			if not clone.Parent then
				if conn then
					conn:Disconnect()
				end
				return
			end
			local s = tonumber(v)
			if s then
				pcall(function()
					clone:ScaleTo(s)
				end)
				Placement.AlignModelOnPartUpright(clone, data.Part, offsetXZ, yaw)
			end
		end)

		local tween = TweenService:Create(
			scaleVal,
			TweenInfo.new(SpawnerConfig.TweenTime, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
			{ Value = 1 }
		)

		tween:Play()

		tween.Completed:Connect(function()
			if conn then
				conn:Disconnect()
			end
			if scaleVal.Parent then
				scaleVal:Destroy()
			end
			if clone.Parent then
				Placement.AlignModelOnPartUpright(clone, data.Part, offsetXZ, yaw)
				local settledPosition = clone:GetPivot().Position
				spawnTrace(
					"spawnOne completed rarity=%s brainrot=%s finalParent=%s finalPosition=%s",
					tostring(rarityLabel),
					tostring(clone.Name),
					formatInstancePath(clone.Parent),
					formatVector3(settledPosition)
				)
				tryPlayIdle(clone, entry.Info.IdleAnim)
				registerActive(clone, entry, data, freeIndex)
			else
				data.SlotOccupied[freeIndex] = nil
				data.SlotOffsets[freeIndex] = nil
				spawnWarnThrottled(
					"spawn_completed_missing_clone_" .. tostring(finalId),
					"spawnOne skipped reason=clone_missing_before_register spawnPart=%s brainrot=%s",
					formatInstancePath(data.Part),
					tostring(finalId)
				)
			end
		end)

		return true
	end, debug.traceback)

	if not ok then
		spawnError(
			"spawnOne failed spawnPart=%s error=%s",
			formatInstancePath(data and data.Part),
			tostring(result)
		)
		return false
	end

	return result
end

local function despawnAllInData(data)
	for i = 1, SpawnerConfig.MaxPerPart do
		local m = data.SlotOccupied[i]
		if m and m.Parent == data.Container then
			active[m] = nil
			data.SlotOccupied[i] = nil
			data.SlotOffsets[i] = nil
			pcall(function()
				m:Destroy()
			end)
		end
	end
end

local function buildSecretPool()
	local pool = {}
	for i = 1, #entries do
		local e = entries[i]
		local r = tostring(e.Rarity or ""):lower()
		local id = tostring(e.Id or ""):lower()

		if r:find("secret") or id:find("secret") then
			pool[#pool + 1] = e
		end
	end
	return pool
end

local secretEntries = buildSecretPool()

local function pickRandomPartData()
	if #partDataList == 0 then
		return nil
	end
	return partDataList[rng:NextInteger(1, #partDataList)]
end

local function spawnRandomSecretIgnoreLimits()
	local data = pickRandomPartData()
	if not data or not data.Part or not data.Part.Parent then
		spawnWarn("likeGoal skipped reason=no_spawn_parts")
		return
	end

	local baseEntry
	if #secretEntries > 0 then
		baseEntry = secretEntries[rng:NextInteger(1, #secretEntries)]
	else
		spawnWarn("likeGoal no_secret_entries fallback=random_entry")
		baseEntry = entries[rng:NextInteger(1, #entries)]
	end

	local variantKey = "Normal"

	local template, usedVariant = Registry.GetTemplateWithFallback(baseEntry.Id, variantKey)
	if not template then
		spawnWarn("likeGoal skipped reason=missing_template brainrot=%s", tostring(baseEntry.Id))
		return
	end
	variantKey = usedVariant or variantKey

	local finalId = Registry.MakeVariantId(baseEntry.Id, variantKey)
	local finalInfo = Registry.GetOrBuildVariantInfo(baseEntry.Id, variantKey) or baseEntry.Info
	if not finalInfo then
		spawnWarn(
			"likeGoal skipped reason=missing_variant_info brainrot=%s variant=%s",
			tostring(baseEntry.Id),
			tostring(variantKey)
		)
		return
	end

	local entry = {
		Id = finalId,
		Info = finalInfo,
		Template = template,
		Rarity = "Secret",
		Tier = baseEntry.Tier,
		Foot = baseEntry.Foot,
		BaseId = baseEntry.Id,
		Variant = variantKey,
	}

	local clone = template:Clone()
	clone.Name = finalId
	clone.Parent = data.Container

	Placement.EnsurePrimaryPart(clone)
	Placement.AnchorModel(clone)

	local _, modelSize = clone:GetBoundingBox()

	local effX = data.Part.Size.X * 0.9
	local effZ = data.Part.Size.Z * 0.9
	local halfX = math.max(0, (effX / 2) - (modelSize.X / 2))
	local halfZ = math.max(0, (effZ / 2) - (modelSize.Z / 2))

	local offsetXZ = Vector2.new(
		rng:NextNumber(-halfX, halfX),
		rng:NextNumber(-halfZ, halfZ)
	)

	local yaw = rng:NextNumber(0, math.pi * 2)

	Placement.AlignModelOnPartUpright(clone, data.Part, offsetXZ, yaw)
	tryPlayIdle(clone, entry.Info.IdleAnim)
	registerActive(clone, entry, nil, nil)

	spawnTrace(
		"likeGoalSpawn rarity=%s brainrot=%s chosenSpawnPart=%s chosenSpawnPartPos=%s finalParent=%s finalPosition=%s",
		"Secret",
		tostring(finalId),
		formatInstancePath(data.Part),
		formatVector3(data.Part.Position),
		formatInstancePath(clone.Parent),
		formatVector3(clone:GetPivot().Position)
	)
end


local rrIndex = 0

while true do
	local positions = getPlayerPositions()
	local now = os.clock()

	for model, st in pairs(active) do
		if not model.Parent then
			if st.OriginData and st.SlotIndex then
				local od = st.OriginData
				local si = st.SlotIndex
				if od.SlotOccupied and od.SlotOccupied[si] == model then
					od.SlotOccupied[si] = nil
				end
				if od.SlotOffsets then
					od.SlotOffsets[si] = nil
				end
			end
			active[model] = nil
		else
			if st.Held then
				st.LastUpdate = now
				Interaction.SetHoverText(st.HoverRefs, st.Entry, st.Rarity, math.ceil(st.Remaining), true)
			else
				local dt = now - (st.LastUpdate or now)
				st.LastUpdate = now
				st.Remaining = (st.Remaining or 0) - dt

				local remainingInt = math.ceil(st.Remaining)
				if remainingInt < 0 then
					remainingInt = 0
				end

				if remainingInt ~= st.LastShown then
					st.LastShown = remainingInt
					Interaction.SetHoverText(st.HoverRefs, st.Entry, st.Rarity, remainingInt, false)
				end

				if st.Remaining <= 0 then
					if st.OriginData and st.SlotIndex then
						local od = st.OriginData
						local si = st.SlotIndex
						if od.SlotOccupied and od.SlotOccupied[si] == model then
							od.SlotOccupied[si] = nil
						end
						if od.SlotOffsets then
							od.SlotOffsets[si] = nil
						end
					end
					active[model] = nil
					pcall(function()
						model:Destroy()
					end)
				end
			end
		end
	end


	local ops = 0
	local n = #partDataList

	if n > 0 then
		for _ = 1, n do
			rrIndex += 1
			if rrIndex > n then
				rrIndex = 1
			end

			local data = partDataList[rrIndex]
			if data and data.Part and data.Part.Parent then
				local near = anyPlayerNearPart(data.Part, positions, SpawnerConfig.PlayerSpawnRadius)
				if not near then
					if SpawnerConfig.DespawnWhenNoPlayers then
						despawnAllInData(data)
					end
				else
					local did = spawnOne(data)
					if did then
						ops += 1
						if ops >= SpawnerConfig.MaxSpawnOperationsPerTick then
							break
						end
					end
				end
			end
		end
	end
 

  
	task.wait(SpawnerConfig.TickInterval)
end

local LIKEGOAL_COOLDOWN = 30 
local pendingSecretSpawns = 0
local processingSecretQueue = false
local nextSecretAllowedAt = 0


local function processSecretQueue()
	if processingSecretQueue then return end
	processingSecretQueue = true


	task.spawn(function()
		while pendingSecretSpawns > 0 do
			local now = os.clock()


			if now < nextSecretAllowedAt then
				task.wait(nextSecretAllowedAt - now)
			end


			pendingSecretSpawns -= 1
			spawnRandomSecretIgnoreLimits()


			nextSecretAllowedAt = os.clock() + LIKEGOAL_COOLDOWN
		end


		processingSecretQueue = false
	end)
end


LikeGoalSpawnSecret.Event:Connect(function(count)
	count = 1


	pendingSecretSpawns += count
	processSecretQueue()
end)
