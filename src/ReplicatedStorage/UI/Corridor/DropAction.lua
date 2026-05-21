local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local React = require(Packages:WaitForChild("React"))
local Responsive = require(script.Parent.Parent:WaitForChild("Responsive"))
local PreviewViewport = require(script.Parent.Parent:WaitForChild("Index"):WaitForChild("Components"):WaitForChild("PreviewViewport"))
local IndexTheme = require(script.Parent.Parent:WaitForChild("Index"):WaitForChild("Theme"))
local ChestVisuals = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("GrandLineRushChestVisuals"))
local CrewCatalog = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Crew"):WaitForChild("CrewCatalog"))
local CrewPreviewImages = require(
	ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Crew"):WaitForChild("CrewPreviewImages")
)

local e = React.createElement
local CREW_PREVIEW_ASSET_ROOT_NAME = "One Piece Characters"
local BUTTON_BOTTOM_OFFSET = 156
local BUTTON_HEIGHT = 78
local BUTTON_MAX_SIZE = Vector2.new(372, BUTTON_HEIGHT)
local BUTTON_MIN_SIZE = Vector2.new(268, 68)
local IN_HAND_BOTTOM_OFFSET = 318
local IN_HAND_HEIGHT = 136
local IN_HAND_MAX_SIZE = Vector2.new(388, IN_HAND_HEIGHT)
local IN_HAND_MIN_SIZE = Vector2.new(286, 122)
local IN_HAND_PREVIEW_ASPECT_RATIO = 1.22
local CREW_RARITY_ORDER = {
	"Omega",
	"Secret",
	"Godly",
	"Mythic",
	"Mythical",
	"Legendary",
	"Epic",
	"Rare",
	"Uncommon",
	"Common",
}
local CREW_RARITY_ALIASES = {
	Mythical = "Mythic",
}

local PALETTE = {
	Ink = Color3.fromRGB(9, 9, 11),
	Glass = Color3.fromRGB(29, 28, 33),
	GlassDeep = Color3.fromRGB(15, 15, 18),
	Border = Color3.fromRGB(218, 230, 238),
	Highlight = Color3.fromRGB(245, 249, 252),
	Text = Color3.fromRGB(230, 234, 241),
	MutedText = Color3.fromRGB(176, 177, 187),
	Gold = Color3.fromRGB(218, 177, 91),
	Ready = Color3.fromRGB(106, 255, 138),
	Icon = Color3.fromRGB(166, 180, 190),
	IconDark = Color3.fromRGB(56, 63, 72),
	IconLight = Color3.fromRGB(210, 221, 228),
}

local warnedMissingCrewPreview = {}

local function isCompactViewport()
	return Responsive.isCompact()
end

local function useButtonState(enabled)
	local hovered, setHovered = React.useState(false)
	local pressed, setPressed = React.useState(false)

	React.useEffect(function()
		if not enabled then
			setHovered(false)
			setPressed(false)
		end

		return function()
			setHovered(false)
			setPressed(false)
		end
	end, { enabled })

	local handlers = {}
	if enabled then
		handlers[React.Event.MouseEnter] = function()
			setHovered(true)
		end
		handlers[React.Event.MouseLeave] = function()
			setHovered(false)
			setPressed(false)
		end
		handlers[React.Event.MouseButton1Down] = function()
			setPressed(true)
		end
		handlers[React.Event.MouseButton1Up] = function()
			setPressed(false)
		end
	end

	return hovered, pressed, handlers
end

local function getDisplayName(crewmate)
	if typeof(crewmate) ~= "table" then
		return "Crewmate"
	end

	local displayName = crewmate.DisplayName or crewmate.Name or crewmate.CrewName
	if typeof(displayName) == "string" and displayName ~= "" then
		return displayName
	end

	return "Crewmate"
end

local function getInHandItemType(item)
	if typeof(item) ~= "table" then
		return ""
	end

	local itemType = item.ItemType or item.PreviewKind or item.RewardType or item.rewardType
	if typeof(itemType) == "string" then
		return itemType
	end

	return ""
end

local function isChestItem(item)
	local itemType = getInHandItemType(item)
	return itemType == "Chest" or itemType == "ExtractionChest"
end

local function getChestPreviewName(item)
	if typeof(item) ~= "table" then
		return nil
	end

	local previewName = item.PreviewName or item.previewName or item.Tier or item.tier or item.DisplayName
	if typeof(previewName) == "string" and previewName ~= "" then
		local inventoryName = string.match(previewName, "^(.-)%s+Chest$")
		if typeof(inventoryName) == "string" and inventoryName ~= "" then
			return inventoryName
		end

		return previewName
	end

	return nil
end

local function getInHandDisplayName(item)
	if not isChestItem(item) then
		return getDisplayName(item)
	end

	local displayName = item.DisplayName or item.displayName or item.Name or item.name
	if typeof(displayName) == "string" and displayName ~= "" then
		return displayName
	end

	local tierName = item.Tier or item.tier
	if typeof(tierName) == "string" and tierName ~= "" then
		return tierName .. " Chest"
	end

	return "Chest"
end

local function getCrewmateModelName(crewmate)
	if typeof(crewmate) ~= "table" then
		return nil
	end

	local modelPreview = crewmate.ModelPreview or crewmate.modelPreview
	local modelName = crewmate.ModelName or crewmate.modelName
	if typeof(modelPreview) == "table" and typeof(modelPreview.ModelName) == "string" and modelPreview.ModelName ~= "" then
		modelName = modelPreview.ModelName
	end
	if typeof(modelName) == "string" and modelName ~= "" then
		return modelName
	end

	return nil
end

local function getCrewmateId(crewmate)
	if typeof(crewmate) ~= "table" then
		return nil
	end

	local crewMemberId = crewmate.CrewMemberId or crewmate.crewMemberId or crewmate.Id or crewmate.id
	if typeof(crewMemberId) == "string" and crewMemberId ~= "" then
		return crewMemberId
	end

	return getDisplayName(crewmate)
end

local function normalizeCrewRarity(rarity)
	local value = tostring(rarity or "")
	if value == "" then
		return ""
	end

	if IndexTheme.RarityStyles[value] ~= nil then
		return value
	end

	for _, rarityName in ipairs(CREW_RARITY_ORDER) do
		if value == rarityName or string.sub(value, -#rarityName) == rarityName then
			return CREW_RARITY_ALIASES[rarityName] or rarityName
		end
	end

	return CREW_RARITY_ALIASES[value] or value
end

local function getCrewmateRarity(crewmate)
	if typeof(crewmate) ~= "table" then
		return ""
	end

	local rarity = crewmate.Rarity or crewmate.rarity or crewmate.CanonicalRarity or crewmate.canonicalRarity
	if typeof(rarity) == "string" and rarity ~= "" then
		return normalizeCrewRarity(rarity)
	end

	local crewMemberId = getCrewmateId(crewmate)
	local _, crewInfo = CrewCatalog.ResolveCanonicalCrewMemberId(crewMemberId)
	if crewInfo then
		return normalizeCrewRarity(crewInfo.Rarity or "Common")
	end

	return "Common"
end

local function getCrewmateRarityStyle(crewmate)
	return IndexTheme.getRarityStyle(getCrewmateRarity(crewmate))
end

local function getStaticCrewPreviewImage(crewmate, modelName)
	return CrewPreviewImages.Resolve({
		CrewMemberId = getCrewmateId(crewmate),
		DisplayName = getDisplayName(crewmate),
		ModelName = modelName,
		Metadata = crewmate,
		RealCharacterName = crewmate and (crewmate.RealCharacterName or crewmate.realCharacterName),
	})
end

local function findCrewPreviewModel(modelName)
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local root = assets and assets:FindFirstChild(CREW_PREVIEW_ASSET_ROOT_NAME)
	if not root or typeof(modelName) ~= "string" or modelName == "" then
		return nil
	end

	local direct = root:FindFirstChild(modelName)
	if direct and direct:IsA("Model") then
		return direct
	end

	local descendant = root:FindFirstChild(modelName, true)
	if descendant and descendant:IsA("Model") then
		return descendant
	end

	return nil
end

local function warnMissingCrewPreview(crewmate, modelName)
	local crewMemberId = tostring(getCrewmateId(crewmate) or "unknown")
	local modelNameText = tostring(modelName or "")
	local key = crewMemberId .. "::" .. modelNameText
	if warnedMissingCrewPreview[key] then
		return
	end
	warnedMissingCrewPreview[key] = true

	warn(
		string.format(
			"[DropAction] Missing canonical CrewMember preview model. CrewMemberId=%s ModelName=%s",
			crewMemberId,
			if modelNameText ~= "" then modelNameText else "<missing>"
		)
	)
end

local function mergeProps(baseProps, extraProps)
	local merged = table.clone(baseProps)
	for key, value in pairs(extraProps or {}) do
		merged[key] = value
	end
	return merged
end

local function trashIcon(props)
	local zIndex = props.zIndex or 1
	local strokeThickness = props.strokeThickness or 3
	local iconTransparency = props.transparency or 0.12
	local strokeTransparency = props.strokeTransparency or 0.34

	return e("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		Position = props.position or UDim2.fromScale(0.5, 0.5),
		Size = props.size or UDim2.fromOffset(70, 58),
		ZIndex = zIndex,
	}, {
		Handle = e("Frame", {
			AnchorPoint = Vector2.new(0.5, 0),
			BackgroundColor3 = PALETTE.Icon,
			BackgroundTransparency = iconTransparency,
			BorderSizePixel = 0,
			Position = UDim2.new(0.5, 0, 0, 4),
			Size = UDim2.fromOffset(28, 10),
			ZIndex = zIndex + 2,
		}, {
			Corner = e("UICorner", {
				CornerRadius = UDim.new(0, 6),
			}),
			Stroke = e("UIStroke", {
				Color = PALETTE.IconDark,
				Thickness = strokeThickness,
				Transparency = strokeTransparency,
			}),
		}),
		Lid = e("Frame", {
			AnchorPoint = Vector2.new(0.5, 0),
			BackgroundColor3 = PALETTE.Icon,
			BackgroundTransparency = iconTransparency,
			BorderSizePixel = 0,
			Position = UDim2.new(0.5, 0, 0, 17),
			Size = UDim2.fromOffset(50, 8),
			ZIndex = zIndex + 3,
		}, {
			Corner = e("UICorner", {
				CornerRadius = UDim.new(0, 4),
			}),
			Stroke = e("UIStroke", {
				Color = PALETTE.IconDark,
				Thickness = strokeThickness,
				Transparency = strokeTransparency,
			}),
		}),
		Body = e("Frame", {
			AnchorPoint = Vector2.new(0.5, 0),
			BackgroundColor3 = PALETTE.Icon,
			BackgroundTransparency = iconTransparency,
			BorderSizePixel = 0,
			Position = UDim2.new(0.5, 0, 0, 24),
			Size = UDim2.fromOffset(40, 31),
			ZIndex = zIndex + 1,
		}, {
			Corner = e("UICorner", {
				CornerRadius = UDim.new(0, 6),
			}),
			Stroke = e("UIStroke", {
				Color = PALETTE.IconDark,
				Thickness = strokeThickness,
				Transparency = strokeTransparency,
			}),
			Gradient = e("UIGradient", {
				Rotation = 90,
				Color = ColorSequence.new({
					ColorSequenceKeypoint.new(0, PALETTE.IconLight),
					ColorSequenceKeypoint.new(1, PALETTE.Icon),
				}),
			}),
			Slot1 = e("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				BackgroundColor3 = PALETTE.IconDark,
				BackgroundTransparency = math.min(iconTransparency + 0.08, 1),
				BorderSizePixel = 0,
				Position = UDim2.fromScale(0.34, 0.52),
				Size = UDim2.fromOffset(3, 19),
				ZIndex = zIndex + 4,
			}, {
				Corner = e("UICorner", {
					CornerRadius = UDim.new(0, 2),
				}),
			}),
			Slot2 = e("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				BackgroundColor3 = PALETTE.IconDark,
				BackgroundTransparency = math.min(iconTransparency + 0.08, 1),
				BorderSizePixel = 0,
				Position = UDim2.fromScale(0.5, 0.52),
				Size = UDim2.fromOffset(3, 21),
				ZIndex = zIndex + 4,
			}, {
				Corner = e("UICorner", {
					CornerRadius = UDim.new(0, 2),
				}),
			}),
			Slot3 = e("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				BackgroundColor3 = PALETTE.IconDark,
				BackgroundTransparency = math.min(iconTransparency + 0.08, 1),
				BorderSizePixel = 0,
				Position = UDim2.fromScale(0.66, 0.52),
				Size = UDim2.fromOffset(3, 19),
				ZIndex = zIndex + 4,
			}, {
				Corner = e("UICorner", {
					CornerRadius = UDim.new(0, 2),
				}),
			}),
		}),
	})
end

local function chestIcon(props)
	local woodColor, metalColor = ChestVisuals.GetTierColors(props.tierName)
	local accent = props.accentColor or metalColor
	local size = props.size or UDim2.fromScale(1, 1)
	local position = props.position or UDim2.fromScale(0.5, 0.5)
	local anchorPoint = props.anchorPoint or Vector2.new(0.5, 0.5)
	local zIndex = props.zIndex or 1

	return e("Frame", {
		AnchorPoint = anchorPoint,
		BackgroundTransparency = 1,
		Position = position,
		Size = size,
		ZIndex = zIndex,
	}, {
		Shadow = e("Frame", {
			AnchorPoint = Vector2.new(0.5, 1),
			BackgroundColor3 = Color3.fromRGB(6, 8, 14),
			BackgroundTransparency = 0.48,
			BorderSizePixel = 0,
			Position = UDim2.fromScale(0.5, 0.96),
			Size = UDim2.fromScale(0.68, 0.1),
			ZIndex = zIndex,
		}, {
			Corner = e("UICorner", {
				CornerRadius = UDim.new(1, 0),
			}),
		}),
		Body = e("Frame", {
			AnchorPoint = Vector2.new(0.5, 1),
			BackgroundColor3 = woodColor,
			BorderSizePixel = 0,
			Position = UDim2.fromScale(0.5, 0.83),
			Size = UDim2.fromScale(0.74, 0.42),
			ZIndex = zIndex + 1,
		}, {
			Corner = e("UICorner", {
				CornerRadius = UDim.new(0.16, 0),
			}),
			Stroke = e("UIStroke", {
				Color = accent:Lerp(Color3.fromRGB(255, 255, 255), 0.18),
				Thickness = 1,
				Transparency = 0.3,
			}),
			Gradient = e("UIGradient", {
				Rotation = 90,
				Color = ColorSequence.new({
					ColorSequenceKeypoint.new(0, woodColor:Lerp(Color3.fromRGB(255, 255, 255), 0.1)),
					ColorSequenceKeypoint.new(1, woodColor:Lerp(Color3.fromRGB(0, 0, 0), 0.2)),
				}),
			}),
		}),
		Lid = e("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = woodColor:Lerp(Color3.fromRGB(255, 255, 255), 0.08),
			BorderSizePixel = 0,
			Position = UDim2.fromScale(0.5, 0.37),
			Rotation = -6,
			Size = UDim2.fromScale(0.8, 0.28),
			ZIndex = zIndex + 2,
		}, {
			Corner = e("UICorner", {
				CornerRadius = UDim.new(0.2, 0),
			}),
			Stroke = e("UIStroke", {
				Color = accent:Lerp(Color3.fromRGB(255, 255, 255), 0.22),
				Thickness = 1,
				Transparency = 0.24,
			}),
			Gradient = e("UIGradient", {
				Rotation = 90,
				Color = ColorSequence.new({
					ColorSequenceKeypoint.new(0, woodColor:Lerp(Color3.fromRGB(255, 255, 255), 0.16)),
					ColorSequenceKeypoint.new(1, woodColor:Lerp(Color3.fromRGB(0, 0, 0), 0.12)),
				}),
			}),
		}),
		Band = e("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = metalColor,
			BorderSizePixel = 0,
			Position = UDim2.fromScale(0.5, 0.52),
			Size = UDim2.fromScale(0.14, 0.56),
			ZIndex = zIndex + 3,
		}, {
			Corner = e("UICorner", {
				CornerRadius = UDim.new(0.18, 0),
			}),
			Stroke = e("UIStroke", {
				Color = metalColor:Lerp(Color3.fromRGB(255, 255, 255), 0.24),
				Thickness = 1,
				Transparency = 0.18,
			}),
		}),
		TrimLeft = e("Frame", {
			AnchorPoint = Vector2.new(0, 0.5),
			BackgroundColor3 = metalColor,
			BorderSizePixel = 0,
			Position = UDim2.fromScale(0.13, 0.6),
			Size = UDim2.fromScale(0.09, 0.32),
			ZIndex = zIndex + 2,
		}, {
			Corner = e("UICorner", {
				CornerRadius = UDim.new(0.18, 0),
			}),
		}),
		TrimRight = e("Frame", {
			AnchorPoint = Vector2.new(1, 0.5),
			BackgroundColor3 = metalColor,
			BorderSizePixel = 0,
			Position = UDim2.fromScale(0.87, 0.6),
			Size = UDim2.fromScale(0.09, 0.32),
			ZIndex = zIndex + 2,
		}, {
			Corner = e("UICorner", {
				CornerRadius = UDim.new(0.18, 0),
			}),
		}),
		Latch = e("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = accent:Lerp(Color3.fromRGB(255, 255, 255), 0.08),
			BorderSizePixel = 0,
			Position = UDim2.fromScale(0.5, 0.58),
			Size = UDim2.fromScale(0.18, 0.16),
			ZIndex = zIndex + 4,
		}, {
			Corner = e("UICorner", {
				CornerRadius = UDim.new(0.28, 0),
			}),
			Stroke = e("UIStroke", {
				Color = Color3.fromRGB(255, 244, 210),
				Thickness = 1,
				Transparency = 0.26,
			}),
		}),
		Highlight = e("Frame", {
			AnchorPoint = Vector2.new(0.5, 0),
			BackgroundColor3 = Color3.fromRGB(255, 255, 255),
			BackgroundTransparency = 0.72,
			BorderSizePixel = 0,
			Position = UDim2.fromScale(0.48, 0.18),
			Rotation = -18,
			Size = UDim2.fromScale(0.12, 0.24),
			ZIndex = zIndex + 5,
		}, {
			Corner = e("UICorner", {
				CornerRadius = UDim.new(1, 0),
			}),
		}),
	})
end

local function lockIcon(props)
	local zIndex = props.zIndex or 1

	return e("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		Position = UDim2.fromScale(0.5, 0.42),
		Size = UDim2.fromOffset(40, 44),
		ZIndex = zIndex,
	}, {
		Shackle = e("Frame", {
			AnchorPoint = Vector2.new(0.5, 0),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Position = UDim2.fromScale(0.5, 0),
			Size = UDim2.fromOffset(28, 26),
			ZIndex = zIndex + 1,
		}, {
			Stroke = e("UIStroke", {
				Color = PALETTE.IconLight,
				Thickness = 5,
				Transparency = 0.08,
			}),
			Corner = e("UICorner", {
				CornerRadius = UDim.new(0, 14),
			}),
		}),
		Body = e("Frame", {
			AnchorPoint = Vector2.new(0.5, 1),
			BackgroundColor3 = PALETTE.IconLight,
			BorderSizePixel = 0,
			Position = UDim2.fromScale(0.5, 1),
			Size = UDim2.fromOffset(34, 28),
			ZIndex = zIndex + 2,
		}, {
			Corner = e("UICorner", {
				CornerRadius = UDim.new(0, 7),
			}),
			Gradient = e("UIGradient", {
				Rotation = 90,
				Color = ColorSequence.new({
					ColorSequenceKeypoint.new(0, PALETTE.IconLight),
					ColorSequenceKeypoint.new(1, PALETTE.Icon),
				}),
			}),
			Stroke = e("UIStroke", {
				Color = PALETTE.IconDark,
				Thickness = 2,
				Transparency = 0.22,
			}),
			Keyhole = e("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				BackgroundColor3 = PALETTE.Ink,
				BorderSizePixel = 0,
				Position = UDim2.fromScale(0.5, 0.56),
				Size = UDim2.fromOffset(6, 12),
				ZIndex = zIndex + 3,
			}, {
				Corner = e("UICorner", {
					CornerRadius = UDim.new(0, 3),
				}),
			}),
		}),
	})
end

local function getCarrySlotKey(slot)
	if typeof(slot) ~= "table" or slot.Occupied ~= true then
		return nil
	end

	local carryId = slot.CarryId
	if typeof(carryId) == "string" and carryId ~= "" then
		return carryId
	end

	return tostring(slot.SlotIndex or "")
end

local function findFirstOccupiedSlot(slots)
	if typeof(slots) ~= "table" then
		return nil
	end

	for _, slot in ipairs(slots) do
		if typeof(slot) == "table" and slot.Occupied == true then
			return slot
		end
	end

	return nil
end

local function findCarrySlotByKey(slots, slotKey)
	if typeof(slots) ~= "table" or typeof(slotKey) ~= "string" or slotKey == "" then
		return nil
	end

	for _, slot in ipairs(slots) do
		if getCarrySlotKey(slot) == slotKey then
			return slot
		end
	end

	return nil
end

local function inHandSlot(props)
	local zIndex = props.zIndex or 1
	local slot = if typeof(props.slot) == "table" then props.slot else nil
	local locked = props.locked == true or (slot and slot.Locked == true)
	local occupied = locked ~= true and ((slot and slot.Occupied == true) or props.item ~= nil or props.crewmate ~= nil)
	local selected = props.selected == true
	local canSelect = occupied and typeof(props.onSelect) == "function"
	local slotNumber = tostring((slot and slot.SlotIndex) or props.slotNumber or 1)
	local item = if slot and typeof(slot.Item) == "table" then slot.Item else props.item or props.crewmate
	local itemIsChest = occupied and isChestItem(item)
	local displayName = if occupied then getInHandDisplayName(item) else "Empty"
	local crewRarity = if occupied and not itemIsChest then getCrewmateRarity(item) else ""
	local crewRarityStyle = if crewRarity ~= "" then getCrewmateRarityStyle(item) else nil
	local crewRarityColor = if crewRarityStyle and typeof(crewRarityStyle.textColor) == "Color3" then crewRarityStyle.textColor else PALETTE.Ready
	local showCrewRarity = occupied and not itemIsChest and crewRarity ~= ""
	local previewBottomInset = if showCrewRarity then 30 else 18
	local chestPreviewName = if itemIsChest then getChestPreviewName(item) else nil
	local modelName = if itemIsChest or not occupied then nil else getCrewmateModelName(item)
	local staticPreviewImage = if occupied and not itemIsChest then getStaticCrewPreviewImage(item, modelName) else ""
	local hasStaticPreview = staticPreviewImage ~= ""
	local hasChestPreview = itemIsChest and chestPreviewName ~= nil
	local hasPreviewModel = occupied and (
		hasChestPreview
		or hasStaticPreview
		or (modelName ~= nil and findCrewPreviewModel(modelName) ~= nil)
	)

	if occupied and not itemIsChest and not hasPreviewModel then
		warnMissingCrewPreview(item, modelName)
	end

	local strokeColor = if locked then PALETTE.Border elseif occupied then PALETTE.Gold else PALETTE.Border
	local strokeTransparency = if selected then 0.08 elseif locked then 0.68 elseif occupied then 0.24 else 0.58

	return e("TextButton", {
		Active = canSelect,
		AutoButtonColor = false,
		BackgroundColor3 = PALETTE.Ink,
		BackgroundTransparency = if locked then 0.18 elseif occupied then 0.08 else 0.14,
		BorderSizePixel = 0,
		LayoutOrder = props.layoutOrder or props.slotNumber or 1,
		Size = UDim2.new(1 / 3, -6, 1, 0),
		Text = "",
		ZIndex = zIndex,
		[React.Event.Activated] = function()
			if canSelect then
				props.onSelect(slot)
			end
		end,
	}, {
		Corner = e("UICorner", {
			CornerRadius = UDim.new(0, 8),
		}),
		Gradient = e("UIGradient", {
			Rotation = 90,
			Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, if locked or not occupied then PALETTE.Glass else PALETTE.GlassDeep),
				ColorSequenceKeypoint.new(1, PALETTE.Ink),
			}),
		}),
		Stroke = e("UIStroke", {
			Color = strokeColor,
			Thickness = if selected then 2.25 elseif occupied then 1.75 else 1.25,
			Transparency = strokeTransparency,
		}),
		NumberBadge = e("Frame", {
			BackgroundColor3 = PALETTE.GlassDeep,
			BackgroundTransparency = 0.06,
			BorderSizePixel = 0,
			Position = UDim2.fromOffset(6, 5),
			Size = UDim2.fromOffset(20, 20),
			ZIndex = zIndex + 3,
		}, {
			Corner = e("UICorner", {
				CornerRadius = UDim.new(1, 0),
			}),
			Stroke = e("UIStroke", {
				Color = strokeColor,
				Thickness = 1,
				Transparency = if occupied then 0.22 else 0.72,
			}),
			Label = e("TextLabel", {
				BackgroundTransparency = 1,
				Font = Enum.Font.GothamBlack,
				Size = UDim2.fromScale(1, 1),
				Text = slotNumber,
				TextColor3 = PALETTE.Text,
				TextSize = 12,
				TextStrokeColor3 = PALETTE.Ink,
				TextStrokeTransparency = 0.45,
				ZIndex = zIndex + 4,
			}),
		}),
		Portrait = if locked
			then e(lockIcon, {
				zIndex = zIndex + 2,
			})
			elseif not occupied
				then e("TextLabel", {
					AnchorPoint = Vector2.new(0.5, 0.5),
					BackgroundTransparency = 1,
					Font = Enum.Font.GothamBlack,
					Position = UDim2.fromScale(0.5, 0.43),
					Size = UDim2.new(1, -18, 0, 34),
					Text = "+",
					TextColor3 = PALETTE.MutedText,
					TextSize = 26,
					TextStrokeColor3 = PALETTE.Ink,
					TextStrokeTransparency = 0.5,
					ZIndex = zIndex + 2,
				})
			elseif hasChestPreview
				then e("Frame", {
					AnchorPoint = Vector2.new(0.5, 0),
					BackgroundTransparency = 1,
					Position = UDim2.new(0.5, 0, 0, 4),
					Size = UDim2.new(1, -12, 1, -previewBottomInset),
					ZIndex = zIndex + 2,
				}, {
					Aspect = e("UIAspectRatioConstraint", {
						AspectRatio = IN_HAND_PREVIEW_ASPECT_RATIO,
						DominantAxis = Enum.DominantAxis.Width,
					}),
					Preview = e(chestIcon, {
						position = UDim2.fromScale(0.5, 0.5),
						size = UDim2.fromScale(1, 1),
						tierName = chestPreviewName,
						zIndex = zIndex + 2,
					}),
				})
			elseif hasPreviewModel
				then e("Frame", {
					AnchorPoint = Vector2.new(0.5, 0),
					BackgroundTransparency = 1,
					Position = UDim2.new(0.5, 0, 0, 4),
					Size = UDim2.new(1, -12, 1, -previewBottomInset),
					ZIndex = zIndex + 2,
				}, {
					Aspect = e("UIAspectRatioConstraint", {
						AspectRatio = IN_HAND_PREVIEW_ASPECT_RATIO,
						DominantAxis = Enum.DominantAxis.Width,
					}),
					Preview = e(PreviewViewport, {
						anchorPoint = Vector2.new(0.5, 0.5),
						fieldOfView = 34,
						position = UDim2.fromScale(0.5, 0.54),
						previewKind = "CrewMember",
						previewName = modelName or getCrewmateId(item) or displayName,
						scaleType = Enum.ScaleType.Fit,
						size = UDim2.fromScale(1, 1),
						zIndex = zIndex + 2,
					}),
				})
				else e("TextLabel", {
					AnchorPoint = Vector2.new(0.5, 0.5),
					BackgroundTransparency = 1,
					Font = Enum.Font.GothamBlack,
					Position = UDim2.fromScale(0.5, 0.43),
					Size = UDim2.new(1, -18, 0, 34),
					Text = "?",
					TextColor3 = PALETTE.MutedText,
					TextSize = 32,
					TextStrokeColor3 = PALETTE.Ink,
					TextStrokeTransparency = 0.45,
					ZIndex = zIndex + 2,
				}),
		Name = e("TextLabel", {
			AnchorPoint = Vector2.new(0.5, 1),
			BackgroundTransparency = 1,
			Font = Enum.Font.GothamBold,
			Position = if showCrewRarity then UDim2.new(0.5, 0, 1, -15) else UDim2.new(0.5, 0, 1, -3),
			Size = UDim2.new(1, -12, 0, if showCrewRarity then 12 else 13),
			Text = if locked then "Locked" else displayName,
			TextColor3 = if showCrewRarity then crewRarityColor elseif occupied then PALETTE.Ready else PALETTE.MutedText,
			TextSize = if showCrewRarity then 10 else 11,
			TextStrokeColor3 = PALETTE.Ink,
			TextStrokeTransparency = 0.46,
			TextTruncate = Enum.TextTruncate.AtEnd,
			TextXAlignment = Enum.TextXAlignment.Center,
			TextYAlignment = Enum.TextYAlignment.Center,
			ZIndex = zIndex + 3,
		}),
		Rarity = if showCrewRarity
			then e("TextLabel", {
				AnchorPoint = Vector2.new(0.5, 1),
				BackgroundTransparency = 1,
				Font = Enum.Font.GothamBold,
				Position = UDim2.new(0.5, 0, 1, -3),
				Size = UDim2.new(1, -12, 0, 10),
				Text = crewRarity,
				TextColor3 = crewRarityColor,
				TextSize = 9,
				TextStrokeColor3 = PALETTE.Ink,
				TextStrokeTransparency = 0.48,
				TextTruncate = Enum.TextTruncate.AtEnd,
				TextXAlignment = Enum.TextXAlignment.Center,
				TextYAlignment = Enum.TextYAlignment.Center,
				ZIndex = zIndex + 3,
			})
			else nil,
	})
end

local function inHandCrewHud(props)
	local compact = isCompactViewport()
	local item = props.item or props.crewmate
	local slots = if typeof(props.slots) == "table" then props.slots else nil
	local selectedSlotKey = props.selectedSlotKey
	local slotChildren = {
		Layout = e("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			Padding = UDim.new(0, 8),
			SortOrder = Enum.SortOrder.LayoutOrder,
			VerticalAlignment = Enum.VerticalAlignment.Center,
		}),
	}

	for slotIndex = 1, 3 do
		local slot = slots and slots[slotIndex] or nil
		local slotKey = getCarrySlotKey(slot)
		slotChildren["Slot" .. tostring(slotIndex)] = e(inHandSlot, {
			item = if slots == nil and slotIndex == 1 then item else nil,
			layoutOrder = slotIndex,
			locked = if slots == nil then slotIndex > 1 else nil,
			onSelect = props.onSelectSlot,
			selected = slotKey ~= nil and selectedSlotKey == slotKey,
			slot = slot,
			slotNumber = slotIndex,
			zIndex = 44,
		})
	end

	return e("Frame", {
		Active = false,
		AnchorPoint = Vector2.new(1, 1),
		BackgroundColor3 = PALETTE.Glass,
		BackgroundTransparency = 0.14,
		BorderSizePixel = 0,
		ClipsDescendants = false,
		Position = UDim2.new(1, compact and -140 or -24, 1, compact and -226 or -IN_HAND_BOTTOM_OFFSET),
		Size = compact and UDim2.new(0.26, 0, 0, 104) or UDim2.new(0.32, 0, 0, IN_HAND_HEIGHT),
		ZIndex = 42,
	}, {
		Scale = e("UIScale", {
			Scale = compact and 0.78 or 1,
		}),
		SizeLimit = e("UISizeConstraint", {
			MaxSize = compact and Vector2.new(310, 104) or IN_HAND_MAX_SIZE,
			MinSize = compact and Vector2.new(230, 94) or IN_HAND_MIN_SIZE,
		}),
		Corner = e("UICorner", {
			CornerRadius = UDim.new(0, 8),
		}),
		Gradient = e("UIGradient", {
			Rotation = 90,
			Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, PALETTE.Glass),
				ColorSequenceKeypoint.new(1, PALETTE.GlassDeep),
			}),
		}),
		Stroke = e("UIStroke", {
			Color = PALETTE.Gold,
			Thickness = 1.5,
			Transparency = 0.3,
		}),
		HeaderTab = e("Frame", {
			AnchorPoint = Vector2.new(0.5, 1),
			BackgroundColor3 = PALETTE.GlassDeep,
			BorderSizePixel = 0,
			Position = UDim2.new(0.5, 0, 0, 4),
			Size = UDim2.fromOffset(96, 22),
			ZIndex = 48,
		}, {
			Corner = e("UICorner", {
				CornerRadius = UDim.new(0, 6),
			}),
			Stroke = e("UIStroke", {
				Color = PALETTE.Gold,
				Thickness = 1,
				Transparency = 0.34,
			}),
			Label = e("TextLabel", {
				BackgroundTransparency = 1,
				Font = Enum.Font.GothamBlack,
				Size = UDim2.fromScale(1, 1),
				Text = "IN HAND",
				TextColor3 = PALETTE.Text,
				TextSize = 12,
				TextStrokeColor3 = PALETTE.Ink,
				TextStrokeTransparency = 0.45,
				ZIndex = 49,
			}),
		}),
		Slots = e("Frame", {
			Active = false,
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(10, 20),
			Size = UDim2.new(1, -20, 1, -28),
			ZIndex = 43,
		}, slotChildren),
	})
end

local function DropAction(props)
	local visible = props.visible == true
	local compact = isCompactViewport()
	local carriedItem = props.carriedItem or props.carriedCrewMember
	local carriedSlots = props.carriedSlots
	local selectedSlotKey, setSelectedSlotKey = React.useState(nil)
	local selectedSlot = findCarrySlotByKey(carriedSlots, selectedSlotKey) or findFirstOccupiedSlot(carriedSlots)
	local activeSlotKey = getCarrySlotKey(selectedSlot)
	local showInHandHud = props.showInHandHud == true and (
		typeof(carriedSlots) == "table" or typeof(carriedItem) == "table"
	)
	local canDrop = visible and props.isPending ~= true and props.disabled ~= true
	local hovered, pressed, handlers = useButtonState(canDrop)
	local buttonRef = React.useRef(nil)
	local scale = 1
	if hovered then
		scale += 0.025
	end
	if pressed or props.isPending == true then
		scale -= 0.055
	end
	local reward = props.reward
	local metaText = "ITEM"
	if typeof(reward) == "table" and typeof(reward.RewardType) == "string" and reward.RewardType ~= "" then
		metaText = string.upper(reward.RewardType)
	end
	local panelTransparency = if pressed or props.isPending == true then 0.32 elseif hovered then 0.4 else 0.5
	local strokeTransparency = if hovered then 0.58 else 0.74

	React.useEffect(function()
		local button = buttonRef.current
		if not visible or not button then
			return nil
		end

		CollectionService:AddTag(button, "NoAnim")

		return function()
			if button.Parent then
				CollectionService:RemoveTag(button, "NoAnim")
			end
		end
	end, { visible })

	React.useEffect(function()
		if activeSlotKey ~= selectedSlotKey then
			setSelectedSlotKey(activeSlotKey)
		end
	end, { activeSlotKey, selectedSlotKey })

	if not visible and not showInHandHud then
		return nil
	end

	local buttonProps = mergeProps({
		AnchorPoint = Vector2.new(0.5, 1),
		AutoButtonColor = false,
		BackgroundColor3 = PALETTE.Glass,
		BackgroundTransparency = panelTransparency,
		BorderSizePixel = 0,
		ClipsDescendants = true,
		Position = UDim2.new(0.5, 0, 1, compact and -118 or -BUTTON_BOTTOM_OFFSET),
		ref = buttonRef,
		Size = compact and UDim2.new(0.34, 0, 0, 58) or UDim2.new(0.45, 0, 0, BUTTON_HEIGHT),
		Text = "",
		ZIndex = 50,
		[React.Event.Activated] = function()
			if canDrop and props.onDrop then
				props.onDrop(selectedSlot)
			end
		end,
	}, handlers)

	return e("ScreenGui", {
		DisplayOrder = 155,
		IgnoreGuiInset = true,
		key = "ReactCorridorDropAction",
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}, {
		CorridorInHandHud = if showInHandHud
			then e(inHandCrewHud, {
				item = carriedItem,
				onSelectSlot = function(slot)
					local slotKey = getCarrySlotKey(slot)
					if slotKey ~= nil then
						setSelectedSlotKey(slotKey)
					end
				end,
				selectedSlotKey = activeSlotKey,
				slots = carriedSlots,
			})
			else nil,
		CorridorDropButton = if visible
			then e("TextButton", buttonProps, {
			Scale = e("UIScale", {
				Scale = scale,
			}),
			SizeLimit = e("UISizeConstraint", {
				MaxSize = compact and Vector2.new(286, 58) or BUTTON_MAX_SIZE,
				MinSize = compact and Vector2.new(220, 54) or BUTTON_MIN_SIZE,
			}),
			Corner = e("UICorner", {
				CornerRadius = UDim.new(0, 8),
			}),
			Gradient = e("UIGradient", {
				Rotation = 90,
				Color = ColorSequence.new({
					ColorSequenceKeypoint.new(0, PALETTE.Glass),
					ColorSequenceKeypoint.new(1, PALETTE.GlassDeep),
				}),
			}),
			Stroke = e("UIStroke", {
				Color = PALETTE.Border,
				Thickness = hovered and 2 or 1.5,
				Transparency = strokeTransparency,
			}),
			TopStripe = e("Frame", {
				BackgroundColor3 = PALETTE.Highlight,
				BackgroundTransparency = hovered and 0.78 or 0.88,
				BorderSizePixel = 0,
				Position = UDim2.fromOffset(9, 7),
				Size = UDim2.new(1, -18, 0, 4),
				ZIndex = 51,
			}, {
				Corner = e("UICorner", {
					CornerRadius = UDim.new(0, 3),
				}),
			}),
			BottomEdge = e("Frame", {
				AnchorPoint = Vector2.new(0, 1),
				BackgroundColor3 = PALETTE.Ink,
				BackgroundTransparency = pressed and 0.52 or 0.7,
				BorderSizePixel = 0,
				Position = UDim2.fromScale(0, 1),
				Size = UDim2.new(1, 0, 0, 7),
				ZIndex = 51,
			}),
			RightRail = e("Frame", {
				AnchorPoint = Vector2.new(1, 0),
				BackgroundColor3 = PALETTE.Border,
				BackgroundTransparency = hovered and 0.72 or 0.86,
				BorderSizePixel = 0,
				Position = UDim2.new(1, -10, 0, 18),
				Size = UDim2.new(0, 4, 1, -36),
				ZIndex = 52,
			}, {
				Corner = e("UICorner", {
					CornerRadius = UDim.new(0, 3),
				}),
			}),
			IconWell = e("Frame", {
				AnchorPoint = Vector2.new(0, 0.5),
				BackgroundColor3 = PALETTE.Ink,
				BackgroundTransparency = 0.36,
				BorderSizePixel = 0,
				Position = UDim2.new(0, 18, 0.5, 0),
				Size = UDim2.fromOffset(76, 60),
				ZIndex = 52,
			}, {
				Corner = e("UICorner", {
					CornerRadius = UDim.new(0, 8),
				}),
				Gradient = e("UIGradient", {
					Rotation = 90,
					Color = ColorSequence.new({
						ColorSequenceKeypoint.new(0, PALETTE.Glass),
						ColorSequenceKeypoint.new(1, PALETTE.Ink),
					}),
				}),
				Stroke = e("UIStroke", {
					Color = PALETTE.Border,
					Thickness = 1.5,
					Transparency = if hovered then 0.62 else 0.78,
				}),
				Icon = e(trashIcon, {
					position = UDim2.fromScale(0.5, 0.5),
					size = UDim2.fromOffset(70, 58),
					transparency = 0.18,
					strokeTransparency = 0.46,
					zIndex = 54,
				}),
			}),
			Meta = e("TextLabel", {
				BackgroundTransparency = 1,
				Font = Enum.Font.GothamBold,
				Position = UDim2.fromOffset(112, 15),
				Size = UDim2.new(1, -148, 0, 16),
				Text = metaText,
				TextColor3 = PALETTE.MutedText,
				TextSize = 12,
				TextStrokeTransparency = 1,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextYAlignment = Enum.TextYAlignment.Center,
				ZIndex = 52,
			}),
			Label = e("TextLabel", {
				AnchorPoint = Vector2.new(0, 0.5),
				BackgroundTransparency = 1,
				Font = Enum.Font.GothamBlack,
				Position = UDim2.new(0, 110, 0.5, 12),
				Size = UDim2.new(1, -148, 0, 40),
				Text = "DROP",
				TextColor3 = PALETTE.Text,
				TextStrokeColor3 = PALETTE.GlassDeep,
				TextStrokeTransparency = 0.48,
				TextSize = 36,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextYAlignment = Enum.TextYAlignment.Center,
				ZIndex = 52,
			}),
		})
			else nil,
	})
end

return DropAction
