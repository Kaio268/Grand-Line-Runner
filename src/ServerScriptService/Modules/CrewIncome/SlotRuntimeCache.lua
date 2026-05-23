local Module = {}

function Module.Install(ctx)
	local CAPTAIN_RUNTIME_GUI_ATTRIBUTE = ctx.CAPTAIN_RUNTIME_GUI_ATTRIBUTE
	local CAPTAIN_RUNTIME_GUI_NAME = ctx.CAPTAIN_RUNTIME_GUI_NAME
	local CAPTAIN_RUNTIME_GUI_SLOT_ATTRIBUTE = ctx.CAPTAIN_RUNTIME_GUI_SLOT_ATTRIBUTE
	local CAPTAIN_SLOT_KEY = ctx.CAPTAIN_SLOT_KEY
	local ShipRuntimeService = ctx.ShipRuntimeService
	local ShipSlotGuiIdentity = ctx.ShipSlotGuiIdentity
	local ShipSlotService = ctx.ShipSlotService
	local slotRuntimeByStand = ctx.slotRuntimeByStand

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

	local SLOT_LEVEL_UI_REFRESH_INTERVAL_SECONDS = 5

	local function isLiveInstance(instance)
		return typeof(instance) == "Instance" and instance.Parent ~= nil
	end

	local function resolveSlotHandle(standModel)
		local handle = standModel and standModel:FindFirstChild("Handle", true)
		return if handle and handle:IsA("BasePart") then handle else nil
	end

	local function resolveSlotLevelUpPart(standModel)
		local part = standModel and standModel:FindFirstChild("LevelUp", true)
		return if part and part:IsA("BasePart") then part else nil
	end

	local function resolvePlayerLevelUpSurfaceGui(player, slotKey, levelUpPart, allowPartFallback)
		if player and player:IsA("Player") then
			local playerGui = player:FindFirstChild("PlayerGui")
			if playerGui then
				if slotKey == CAPTAIN_SLOT_KEY then
					local captainGui = playerGui:FindFirstChild(CAPTAIN_RUNTIME_GUI_NAME)
					if
						captainGui
						and captainGui:IsA("SurfaceGui")
						and captainGui:GetAttribute(CAPTAIN_RUNTIME_GUI_ATTRIBUTE) == true
						and tostring(captainGui:GetAttribute(CAPTAIN_RUNTIME_GUI_SLOT_ATTRIBUTE) or CAPTAIN_SLOT_KEY) == CAPTAIN_SLOT_KEY
					then
						return captainGui
					end

					for _, child in ipairs(playerGui:GetChildren()) do
						if
							child:IsA("SurfaceGui")
							and child:GetAttribute(CAPTAIN_RUNTIME_GUI_ATTRIBUTE) == true
							and tostring(child:GetAttribute(CAPTAIN_RUNTIME_GUI_SLOT_ATTRIBUTE) or CAPTAIN_SLOT_KEY) == CAPTAIN_SLOT_KEY
						then
							return child
						end
					end

					return nil
				end

				local legacyGui = playerGui:FindFirstChild(slotKey)
				if legacyGui and legacyGui:IsA("SurfaceGui") then
					return legacyGui
				end

				local runtimeGuiName = ShipSlotGuiIdentity.GetRuntimeGuiName(slotKey)
				local runtimeGui = runtimeGuiName and playerGui:FindFirstChild(runtimeGuiName)
				if runtimeGui and runtimeGui:IsA("SurfaceGui") then
					return runtimeGui
				end

				for _, child in ipairs(playerGui:GetChildren()) do
					if child:IsA("SurfaceGui") and ShipSlotGuiIdentity.GetSlotKeyFromGui(child) == slotKey then
						return child
					end
				end
			end
		end

		if allowPartFallback and levelUpPart then
			return levelUpPart:FindFirstChildWhichIsA("SurfaceGui", true) or levelUpPart:FindFirstChild("SurfaceGui")
		end

		return nil
	end

	local function resolveLevelUpRefs(cache)
		local surfaceGui = cache.LevelUpSurfaceGui
		if not isLiveInstance(surfaceGui) or not surfaceGui:IsA("SurfaceGui") then
			return
		end

		local root = surfaceGui:FindFirstChild("LevelUp")
		if root and not root:IsA("GuiObject") then
			root = nil
		end

		local container = root or surfaceGui
		local main = container:FindFirstChild("Main", true) or container
		cache.LevelUpRoot = root
		cache.LevelUpMain = main
		cache.LevelUpPrice = getTextTarget(main, "Price")
		cache.LevelUpUpgrade = getTextTarget(main, "Upgarde") or getTextTarget(main, "Upgrade")
	end

	local function disconnectSlotRuntime(cache)
		if not cache or typeof(cache.Connections) ~= "table" then
			return
		end

		for _, connection in pairs(cache.Connections) do
			if connection and connection.Connected then
				connection:Disconnect()
			end
		end
		table.clear(cache.Connections)
		cache.PromptTriggeredConnection = nil
		cache.ZoneTouchedConnection = nil
	end

	local function resetSlotRenderState(cache)
		if cache then
			cache.LastMoneyText = nil
			cache.LastPromptActionText = nil
			cache.LastPromptObjectText = nil
			cache.LastLevelVisible = nil
			cache.LastLevelRootVisible = nil
			cache.LastLevelPriceText = nil
			cache.LastLevelUpgradeText = nil
			cache.LastLevelProgressKey = nil
			cache.NextLevelUiRefreshAt = 0
			cache.NextLevelUpLookupAt = nil
		end
	end

	local function cleanupSlotRuntime(standModel)
		local cache = slotRuntimeByStand[standModel]
		if not cache then
			return
		end

		disconnectSlotRuntime(cache)
		slotRuntimeByStand[standModel] = nil
	end

	local function buildSlotRuntime(player, plot, standModel)
		local slotKey = if ShipSlotService.IsCaptainSlotName(standModel.Name)
			then CAPTAIN_SLOT_KEY
			else tostring(standModel.Name)
		local handle = resolveSlotHandle(standModel)
		local levelUpPart = resolveSlotLevelUpPart(standModel)
		local allowLevelUpPartFallback = not ShipRuntimeService.IsActiveShip(standModel.Parent)
		local cache = {
			Player = player,
			Plot = plot,
			StandModel = standModel,
			SlotKey = slotKey,
			Handle = handle,
			Prompt = handle and handle:FindFirstChildOfClass("ProximityPrompt") or nil,
			ClaimHitBox = ShipSlotService.GetClaimHitBox(standModel),
			MoneyLabel = ShipSlotService.GetClaimMoneyLabel(standModel),
			LevelUpPart = levelUpPart,
			LevelUpSurfaceGui = resolvePlayerLevelUpSurfaceGui(player, slotKey, levelUpPart, allowLevelUpPartFallback),
			Connections = {},
			NextLevelUiRefreshAt = 0,
		}

		resolveLevelUpRefs(cache)
		slotRuntimeByStand[standModel] = cache
		return cache
	end

	local function getSlotRuntime(player, plot, standModel)
		if typeof(standModel) ~= "Instance" or not standModel:IsA("Model") then
			return nil
		end

		local cache = slotRuntimeByStand[standModel]
		if
			cache
			and cache.Player == player
			and cache.StandModel == standModel
			and standModel.Parent ~= nil
		then
			if plot and cache.Plot == nil then
				cache.Plot = plot
			end
			return cache
		end

		if cache then
			cleanupSlotRuntime(standModel)
		end

		return buildSlotRuntime(player, plot or standModel.Parent, standModel)
	end

	local function getExistingSlotRuntime(standModel)
		return slotRuntimeByStand[standModel]
	end

	local function isLiveSlotDescendant(cache, instance)
		return cache
			and isLiveInstance(cache.StandModel)
			and isLiveInstance(instance)
			and instance:IsDescendantOf(cache.StandModel)
	end

	local function refreshSlotRuntimeRefs(cache)
		if not cache or not isLiveInstance(cache.StandModel) then
			return
		end

		local standModel = cache.StandModel
		if not isLiveSlotDescendant(cache, cache.Handle) then
			cache.Handle = resolveSlotHandle(standModel)
		end
		if cache.Handle and not isLiveSlotDescendant(cache, cache.Prompt) then
			cache.Prompt = cache.Handle:FindFirstChildOfClass("ProximityPrompt")
		end
		if not isLiveSlotDescendant(cache, cache.ClaimHitBox) then
			cache.ClaimHitBox = ShipSlotService.GetClaimHitBox(standModel)
		end
		if not isLiveSlotDescendant(cache, cache.MoneyLabel) then
			cache.MoneyLabel = ShipSlotService.GetClaimMoneyLabel(standModel)
			cache.LastMoneyText = nil
		end
		if not isLiveSlotDescendant(cache, cache.LevelUpPart) then
			cache.LevelUpPart = resolveSlotLevelUpPart(standModel)
		end
	end

	local function cleanupPlayerSlotRuntime(player)
		for standModel, cache in pairs(slotRuntimeByStand) do
			if cache.Player == player then
				cleanupSlotRuntime(standModel)
			end
		end
	end

	local function setTextIfChanged(cache, fieldName, label, text)
		if not cache then
			return
		end

		if not label or not label.Parent then
			return
		end

		text = tostring(text or "")
		if cache[fieldName] == text and label.Text == text then
			return
		end

		label.TextWrapped = true
		label.Text = text
		cache[fieldName] = text
	end

	local function setCachedLevelUpVisible(cache, visible)
		if not cache then
			return
		end

		local surfaceGui = cache.LevelUpSurfaceGui
		if surfaceGui and surfaceGui.Parent and (cache.LastLevelVisible ~= visible or surfaceGui.Enabled ~= visible) then
			surfaceGui.Enabled = visible
			cache.LastLevelVisible = visible
		end

		local root = cache.LevelUpRoot
		if root and root.Parent and (cache.LastLevelRootVisible ~= visible or root.Visible ~= visible) then
			root.Visible = visible
			cache.LastLevelRootVisible = visible
		end

		local clickDetector = cache.ClickDetector
		if clickDetector and clickDetector.Parent then
			local maxDistance = if visible then 15 else 0
			if clickDetector.MaxActivationDistance ~= maxDistance then
				clickDetector.MaxActivationDistance = maxDistance
			end
		end
	end

	local VariantOrder = { "Normal", "Golden", "Diamond" }
	local VariantPrefix = {
		Normal = "",
		Golden = "Golden ",
		Diamond = "Diamond ",
	}

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

	local function setAttributeIfChanged(instance, attributeName, value)
		if instance:GetAttribute(attributeName) ~= value then
			instance:SetAttribute(attributeName, value)
		end
	end

	local function getLevelUpPart(standModel)
		local cache = getExistingSlotRuntime(standModel)
		if cache and isLiveInstance(cache.LevelUpPart) then
			return cache.LevelUpPart
		end

		return resolveSlotLevelUpPart(standModel)
	end

	local function getLevelUpGuiRoot(standModel, player, cache)
		cache = cache or getSlotRuntime(player, standModel.Parent, standModel)
		if not cache or not isLiveInstance(cache.LevelUpPart) then
			return nil, nil, nil
		end

		if not isLiveInstance(cache.LevelUpSurfaceGui) then
			local now = os.clock()
			if cache.NextLevelUpLookupAt and now < cache.NextLevelUpLookupAt then
				return cache.LevelUpPart, nil, nil
			end
			cache.NextLevelUpLookupAt = now + SLOT_LEVEL_UI_REFRESH_INTERVAL_SECONDS
			local allowPartFallback = not ShipRuntimeService.IsActiveShip(standModel.Parent)
			cache.LevelUpSurfaceGui = resolvePlayerLevelUpSurfaceGui(player, cache.SlotKey, cache.LevelUpPart, allowPartFallback)
			resolveLevelUpRefs(cache)
			if cache.LevelUpSurfaceGui then
				cache.NextLevelUpLookupAt = nil
			end
		end

		if not cache.LevelUpSurfaceGui or not cache.LevelUpSurfaceGui:IsA("SurfaceGui") then
			return cache.LevelUpPart, nil, nil
		end

		return cache.LevelUpPart, cache.LevelUpSurfaceGui, cache.LevelUpRoot
	end

	local function getLevelUpRefs(standModel, player, cache)
		cache = cache or getSlotRuntime(player, standModel.Parent, standModel)
		local part, sg = getLevelUpGuiRoot(standModel, player, cache)
		if not part or not sg or not cache then
			return nil
		end

		return {
			Part = part,
			SurfaceGui = sg,
			Root = cache.LevelUpRoot,
			Main = cache.LevelUpMain,
			Price = cache.LevelUpPrice,
			Upgrade = cache.LevelUpUpgrade,
		}
	end

	local function ensureLevelUpClickDetector(standModel)
		local part = getLevelUpPart(standModel)
		if not part then
			return nil
		end
		local cd = part:FindFirstChildOfClass("ClickDetector")
		if not cd then
			cd = Instance.new("ClickDetector")
			cd.MaxActivationDistance = 15
			cd.Parent = part
		end
		return cd
	end


	ctx.buildSlotRuntime = buildSlotRuntime
	ctx.cleanupPlayerSlotRuntime = cleanupPlayerSlotRuntime
	ctx.cleanupSlotRuntime = cleanupSlotRuntime
	ctx.detectVariant = detectVariant
	ctx.disconnectSlotRuntime = disconnectSlotRuntime
	ctx.ensureLevelUpClickDetector = ensureLevelUpClickDetector
	ctx.getExistingSlotRuntime = getExistingSlotRuntime
	ctx.getLevelUpGuiRoot = getLevelUpGuiRoot
	ctx.getLevelUpPart = getLevelUpPart
	ctx.getLevelUpRefs = getLevelUpRefs
	ctx.getSlotRuntime = getSlotRuntime
	ctx.getTextTarget = getTextTarget
	ctx.isLiveInstance = isLiveInstance
	ctx.isLiveSlotDescendant = isLiveSlotDescendant
	ctx.refreshSlotRuntimeRefs = refreshSlotRuntimeRefs
	ctx.resetSlotRenderState = resetSlotRenderState
	ctx.resolveLevelUpRefs = resolveLevelUpRefs
	ctx.resolvePlayerLevelUpSurfaceGui = resolvePlayerLevelUpSurfaceGui
	ctx.resolveSlotHandle = resolveSlotHandle
	ctx.resolveSlotLevelUpPart = resolveSlotLevelUpPart
	ctx.setAttributeIfChanged = setAttributeIfChanged
	ctx.setCachedLevelUpVisible = setCachedLevelUpVisible
	ctx.setTextIfChanged = setTextIfChanged
	ctx.SLOT_LEVEL_UI_REFRESH_INTERVAL_SECONDS = SLOT_LEVEL_UI_REFRESH_INTERVAL_SECONDS
	ctx.startsWith = startsWith
	ctx.stripVariantPrefix = stripVariantPrefix
	ctx.VariantOrder = VariantOrder
	ctx.VariantPrefix = VariantPrefix
end

return Module
