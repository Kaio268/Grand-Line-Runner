local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local React = require(Packages:WaitForChild("React"))
local PreviewViewport = require(script.Parent.Parent:WaitForChild("Index"):WaitForChild("Components"):WaitForChild("PreviewViewport"))
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
local IN_HAND_HEIGHT = 106
local IN_HAND_MAX_SIZE = Vector2.new(388, IN_HAND_HEIGHT)
local IN_HAND_MIN_SIZE = Vector2.new(286, 92)

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

local function inHandSlot(props)
	local zIndex = props.zIndex or 1
	local locked = props.locked == true
	local slotNumber = tostring(props.slotNumber or 1)
	local crewmate = props.crewmate
	local displayName = getDisplayName(crewmate)
	local modelName = getCrewmateModelName(crewmate)
	local staticPreviewImage = getStaticCrewPreviewImage(crewmate, modelName)
	local hasStaticPreview = staticPreviewImage ~= ""
	local hasPreviewModel = hasStaticPreview or (modelName ~= nil and findCrewPreviewModel(modelName) ~= nil)

	if not locked and not hasPreviewModel then
		warnMissingCrewPreview(crewmate, modelName)
	end

	return e("Frame", {
		BackgroundColor3 = PALETTE.Ink,
		BackgroundTransparency = locked and 0.18 or 0.08,
		BorderSizePixel = 0,
		LayoutOrder = props.layoutOrder or props.slotNumber or 1,
		Size = UDim2.new(1 / 3, -8, 1, 0),
		ZIndex = zIndex,
	}, {
		Corner = e("UICorner", {
			CornerRadius = UDim.new(0, 8),
		}),
		Gradient = e("UIGradient", {
			Rotation = 90,
			Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, locked and PALETTE.Glass or PALETTE.GlassDeep),
				ColorSequenceKeypoint.new(1, PALETTE.Ink),
			}),
		}),
		Stroke = e("UIStroke", {
			Color = locked and PALETTE.Border or PALETTE.Gold,
			Thickness = locked and 1.25 or 1.75,
			Transparency = locked and 0.68 or 0.24,
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
				Color = locked and PALETTE.Border or PALETTE.Gold,
				Thickness = 1,
				Transparency = locked and 0.72 or 0.22,
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
			elseif hasPreviewModel
				then e(PreviewViewport, {
					anchorPoint = Vector2.new(0.5, 0),
					fieldOfView = 34,
					position = UDim2.new(0.5, 0, 0, 5),
					previewKind = "CrewMember",
					previewName = modelName or getCrewmateId(crewmate) or displayName,
					size = UDim2.new(1, -14, 1, -24),
					zIndex = zIndex + 2,
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
			Position = UDim2.new(0.5, 0, 1, -5),
			Size = UDim2.new(1, -12, 0, 16),
			Text = if locked then "Locked" else displayName,
			TextColor3 = if locked then PALETTE.MutedText else PALETTE.Ready,
			TextSize = 11,
			TextStrokeColor3 = PALETTE.Ink,
			TextStrokeTransparency = 0.46,
			TextTruncate = Enum.TextTruncate.AtEnd,
			TextXAlignment = Enum.TextXAlignment.Center,
			TextYAlignment = Enum.TextYAlignment.Center,
			ZIndex = zIndex + 3,
		}),
	})
end

local function inHandCrewHud(props)
	local crewmate = props.crewmate

	return e("Frame", {
		Active = false,
		AnchorPoint = Vector2.new(1, 1),
		BackgroundColor3 = PALETTE.Glass,
		BackgroundTransparency = 0.14,
		BorderSizePixel = 0,
		ClipsDescendants = false,
		Position = UDim2.new(1, -24, 1, -IN_HAND_BOTTOM_OFFSET),
		Size = UDim2.new(0.32, 0, 0, IN_HAND_HEIGHT),
		ZIndex = 42,
	}, {
		Scale = e("UIScale", {
			Scale = 1,
		}),
		SizeLimit = e("UISizeConstraint", {
			MaxSize = IN_HAND_MAX_SIZE,
			MinSize = IN_HAND_MIN_SIZE,
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
			Position = UDim2.fromOffset(12, 18),
			Size = UDim2.new(1, -24, 1, -30),
			ZIndex = 43,
		}, {
			Layout = e("UIListLayout", {
				FillDirection = Enum.FillDirection.Horizontal,
				HorizontalAlignment = Enum.HorizontalAlignment.Center,
				Padding = UDim.new(0, 10),
				SortOrder = Enum.SortOrder.LayoutOrder,
				VerticalAlignment = Enum.VerticalAlignment.Center,
			}),
			Slot1 = e(inHandSlot, {
				crewmate = crewmate,
				layoutOrder = 1,
				slotNumber = 1,
				zIndex = 44,
			}),
			Slot2 = e(inHandSlot, {
				layoutOrder = 2,
				locked = true,
				slotNumber = 2,
				zIndex = 44,
			}),
			Slot3 = e(inHandSlot, {
				layoutOrder = 3,
				locked = true,
				slotNumber = 3,
				zIndex = 44,
			}),
		}),
	})
end

local function DropAction(props)
	local visible = props.visible == true
	local showInHandHud = props.showInHandHud == true and typeof(props.carriedCrewMember) == "table"
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
		Position = UDim2.new(0.5, 0, 1, -BUTTON_BOTTOM_OFFSET),
		ref = buttonRef,
		Size = UDim2.new(0.45, 0, 0, BUTTON_HEIGHT),
		Text = "",
		ZIndex = 50,
		[React.Event.Activated] = function()
			if canDrop and props.onDrop then
				props.onDrop()
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
				crewmate = props.carriedCrewMember,
			})
			else nil,
		CorridorDropButton = if visible
			then e("TextButton", buttonProps, {
			Scale = e("UIScale", {
				Scale = scale,
			}),
			SizeLimit = e("UISizeConstraint", {
				MaxSize = BUTTON_MAX_SIZE,
				MinSize = BUTTON_MIN_SIZE,
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
