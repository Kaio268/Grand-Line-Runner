local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local React = require(Packages:WaitForChild("React"))

local IndexTheme = require(script.Parent.Parent:WaitForChild("Index"):WaitForChild("Theme"))

local e = React.createElement

local TEXT = Color3.fromRGB(255, 243, 210)
local MUTED = Color3.fromRGB(232, 205, 148)
local GOLD = Color3.fromRGB(255, 207, 82)
local PAPER_DARK = Color3.fromRGB(31, 22, 14)
local SHADOW = Color3.fromRGB(0, 0, 0)

local thumbnailCache = {}

local function formatBounty(value)
	local number = math.max(0, math.floor((tonumber(value) or 0) + 0.5))
	local text = tostring(number)

	while true do
		local nextText, count = text:gsub("^(-?%d+)(%d%d%d)", "%1,%2")
		text = nextText
		if count == 0 then
			break
		end
	end

	return text .. " Bounty"
end

local function getDisplayName(entry)
	local displayName = tostring(entry.displayName or "")
	if displayName ~= "" then
		return displayName
	end

	return tostring(entry.name or "Wanted")
end

local function textBacking(position, size, children)
	return e("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundColor3 = PAPER_DARK,
		BackgroundTransparency = 0.28,
		BorderSizePixel = 0,
		Position = position,
		Size = size,
	}, {
		Corner = e("UICorner", {
			CornerRadius = UDim.new(0.18, 0),
		}),
		Content = children,
	})
end

local function textLabel(text, color, textSize)
	return e("TextLabel", {
		BackgroundTransparency = 1,
		Font = IndexTheme.Fonts.Display,
		Size = UDim2.fromScale(1, 1),
		Text = text,
		TextColor3 = color,
		TextScaled = true,
		TextSize = textSize,
		TextStrokeColor3 = SHADOW,
		TextStrokeTransparency = 0.08,
		TextTruncate = Enum.TextTruncate.AtEnd,
		TextWrapped = true,
	})
end

local function WantedPoster(props)
	local entry = props.entry
	local userId = entry and tonumber(entry.userId)
	local rank = entry and tonumber(entry.rank)
	local thumbnail, setThumbnail = React.useState(if userId and thumbnailCache[userId] then thumbnailCache[userId] else "")

	React.useEffect(function()
		if not userId then
			setThumbnail("")
			return nil
		end

		local cached = thumbnailCache[userId]
		if cached then
			setThumbnail(cached)
			return nil
		end

		local cancelled = false
		task.spawn(function()
			local ok, image = pcall(
				Players.GetUserThumbnailAsync,
				Players,
				userId,
				Enum.ThumbnailType.HeadShot,
				Enum.ThumbnailSize.Size150x150
			)
			if ok and typeof(image) == "string" and not cancelled then
				thumbnailCache[userId] = image
				setThumbnail(image)
			end
		end)

		return function()
			cancelled = true
		end
	end, { userId })

	if not entry then
		return e("Frame", {
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
		}, {
			Placeholder = textBacking(UDim2.fromScale(0.5, 0.42), UDim2.fromScale(0.74, 0.18), textLabel("No Bounty", MUTED, 18)),
		})
	end

	return e("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
	}, {
		Rank = e("Frame", {
			BackgroundColor3 = PAPER_DARK,
			BackgroundTransparency = 0.16,
			BorderSizePixel = 0,
			Position = UDim2.fromScale(0.04, 0.03),
			Size = UDim2.fromScale(0.24, 0.15),
		}, {
			Corner = e("UICorner", {
				CornerRadius = UDim.new(0.35, 0),
			}),
			Stroke = e("UIStroke", {
				Color = GOLD,
				Thickness = 1.5,
				Transparency = 0.18,
			}),
			Label = textLabel("#" .. tostring(rank or "?"), SHADOW, 18),
		}),

		Avatar = e("ImageLabel", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = Color3.fromRGB(88, 58, 30),
			BackgroundTransparency = if thumbnail == "" then 0.45 else 1,
			Image = thumbnail,
			Position = UDim2.fromScale(0.5, 0.39),
			ScaleType = Enum.ScaleType.Fit,
			Size = UDim2.fromScale(0.48, 0.42),
		}, {
			Aspect = e("UIAspectRatioConstraint", {
				AspectRatio = 1,
			}),
			Corner = e("UICorner", {
				CornerRadius = UDim.new(1, 0),
			}),
			Stroke = e("UIStroke", {
				Color = GOLD,
				Thickness = 2,
				Transparency = 0.28,
			}),
		}),

		Name = textBacking(
			UDim2.fromScale(0.5, 0.64),
			UDim2.fromScale(0.86, 0.15),
			textLabel(getDisplayName(entry), TEXT, 20)
		),

		Bounty = textBacking(
			UDim2.fromScale(0.5, 0.81),
			UDim2.fromScale(0.82, 0.13),
			textLabel(formatBounty(entry.bounty), GOLD, 18)
		),
	})
end

return WantedPoster
