local ServerScriptService = game:GetService("ServerScriptService")

local BountyRankService = require(ServerScriptService:WaitForChild("Modules"):WaitForChild("BountyRankService"))

local BOARD_MODEL_NAME = "BountyLeaderboard"
local LEADERBOARD_PLANE_NAME = "LeaderboardGuiPlane"
local SURFACE_GUI_NAME = "LeaderboardSurfaceGui"
local POSTERS_FRAME_NAME = "PostersFrame"
local MAX_ENTRIES = 10
local RERENDER_SECONDS = 30
local DEFAULT_SILHOUETTE_IMAGE = "rbxassetid://114486835434518"

local warnedMissingBoard = false

local function normalizeBounty(value)
	return math.max(0, math.floor((tonumber(value) or 0) + 0.5))
end

local function formatNumber(value)
	local bounty = normalizeBounty(value)
	local compactTiers = {
		{threshold = 1_000_000_000_000, suffix = "T"},
		{threshold = 1_000_000_000, suffix = "B"},
		{threshold = 1_000_000, suffix = "M"},
	}

	for _, tier in ipairs(compactTiers) do
		if bounty >= tier.threshold then
			return string.format("%.2f%s", bounty / tier.threshold, tier.suffix)
		end
	end

	local formatted = tostring(bounty)

	while true do
		local replaced, count = formatted:gsub("^(-?%d+)(%d%d%d)", "%1,%2")
		formatted = replaced
		if count == 0 then
			break
		end
	end

	return formatted
end

local function shortenName(name, maxLength)
	local text = tostring(name or "")
	if #text > maxLength then
		return string.sub(text, 1, maxLength - 3) .. "..."
	end

	return text
end

local function getPostersFrame()
	local board = workspace:FindFirstChild(BOARD_MODEL_NAME)
	if not board then
		if not warnedMissingBoard then
			warn("[BountyLeaderboard] Missing Workspace." .. BOARD_MODEL_NAME)
			warnedMissingBoard = true
		end
		return nil
	end

	local plane = board:FindFirstChild(LEADERBOARD_PLANE_NAME)
	local surfaceGui = plane and plane:FindFirstChild(SURFACE_GUI_NAME)
	local postersFrame = surfaceGui and surfaceGui:FindFirstChild(POSTERS_FRAME_NAME)
	if not postersFrame then
		if not warnedMissingBoard then
			warn("[BountyLeaderboard] Missing authored poster UI under Workspace." .. BOARD_MODEL_NAME)
			warnedMissingBoard = true
		end
		return nil
	end

	warnedMissingBoard = false
	return postersFrame
end

local function setTextDeep(parent, objectName, textValue)
	local object = parent and parent:FindFirstChild(objectName, true)
	if object and object:IsA("TextLabel") then
		object.Text = textValue
	end
end

local function setImageDeep(parent, objectName, imageValue)
	local object = parent and parent:FindFirstChild(objectName, true)
	if object and object:IsA("ImageLabel") then
		object.Image = imageValue
	end
end

local function getPosterName(index)
	return string.format("Poster%02d", index)
end

local function getThumbnailForUserId(userId)
	if not userId or userId <= 0 then
		return DEFAULT_SILHOUETTE_IMAGE
	end

	return "rbxthumb://type=AvatarHeadShot&id=" .. tostring(userId) .. "&w=180&h=180"
end

local function renderRows(rows)
	local postersFrame = getPostersFrame()
	if not postersFrame then
		return
	end

	for index = 1, MAX_ENTRIES do
		local poster = postersFrame:FindFirstChild(getPosterName(index))
		local entry = rows[index]

		if poster then
			setTextDeep(poster, "RankText", "#" .. tostring(index))

			if entry then
				local displayName = tostring(entry.displayName or "")
				local username = tostring(entry.name or "")
				local visibleName = if displayName ~= "" then displayName else username

				setTextDeep(poster, "NameText", shortenName(visibleName, 18))
				setTextDeep(poster, "BountyText", formatNumber(entry.bounty))
				setImageDeep(poster, "AvatarImage", getThumbnailForUserId(tonumber(entry.userId)))
			else
				setTextDeep(poster, "NameText", "WANTED")
				setTextDeep(poster, "BountyText", "???")
				setImageDeep(poster, "AvatarImage", DEFAULT_SILHOUETTE_IMAGE)
			end
		else
			warn("[BountyLeaderboard] Missing poster: " .. getPosterName(index))
		end
	end
end

local function renderFromService()
	renderRows(BountyRankService.GetDisplayRows(MAX_ENTRIES))
end

BountyRankService.Start()
renderRows({})
renderFromService()

BountyRankService.Changed:Connect(renderFromService)

task.spawn(function()
	while true do
		task.wait(RERENDER_SECONDS)
		renderFromService()
	end
end)
