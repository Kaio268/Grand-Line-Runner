local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextChatService = game:GetService("TextChatService")

local ANNOUNCE_EVENT_NAME = "DevProductAnnouncement"

local event = ReplicatedStorage:WaitForChild(ANNOUNCE_EVENT_NAME)
local shorten = require(ReplicatedStorage.Modules.Shorten)

local function getDefaultChannel(): TextChannel?
	local channelsFolder = TextChatService:WaitForChild("TextChannels")

	local channel = channelsFolder:FindFirstChild("RBXGeneral")
		or channelsFolder:FindFirstChild("All")

	if not channel then
		for _, c in ipairs(channelsFolder:GetChildren()) do
			if c:IsA("TextChannel") then
				channel = c
				break
			end
		end
	end

	return channel
end

local channel = getDefaultChannel()

local function escapeRichText(str: string): string
	str = string.gsub(str, "&", "&amp;")
	str = string.gsub(str, "<", "&lt;")
	str = string.gsub(str, ">", "&gt;")
	return str
end

event.OnClientEvent:Connect(function(data)
	if typeof(data) ~= "table" then return end

	local username = data.Username or ("Player " .. tostring(data.UserId))
	local productName = data.ProductName or ("Product " .. tostring(data.ProductId))
	local price = tonumber(data.PriceInRobux) or 0

	local pricetext = shorten.roundNumber(price)

	username = escapeRichText(username)
	productName = escapeRichText(productName)

	local coloredName = string.format('<font color="rgb(78, 217, 255)">@%s</font>', username)
	local coloredProductName = string.format('<font color="rgb(255, 241, 161)">%s</font>', productName)
	local coloredPrice = string.format('<font color="rgb(45, 255, 41)">%s</font>', pricetext)

	local message = string.format('%s just bought %s for %s', coloredName, coloredProductName, coloredPrice)

	if channel then
		channel:DisplaySystemMessage(message)
	else
		warn("DevProductAnnouncement: i")
	end
end)
