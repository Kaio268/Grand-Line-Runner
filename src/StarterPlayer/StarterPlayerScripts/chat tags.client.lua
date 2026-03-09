local Players = game:GetService("Players")
local TextChatService = game:GetService("TextChatService")
local RunService = game:GetService("RunService")

local Config = {
	GROUP_ID = 17179624,
	ANIMATION_FPS = 30,

	GroupStyle = {
		gradient = { colors = { Color3.fromRGB(255, 255, 255), Color3.fromRGB(167, 227, 255) } },
		bold = true,
		brackets = true,
		spaceAfter = true,
		animated = false,
		speed = 0.25,
	},

	VIPStyle = {
		gradient = {
			colors = {
				Color3.fromRGB(255, 236, 139),
				Color3.fromRGB(255, 215, 0),
				Color3.fromRGB(255, 140, 0),
				Color3.fromRGB(255, 215, 0),
			},
		},
		bold = true,
		brackets = true,
		spaceAfter = true,
		animated = true,
		speed = 1.5,
	},
}

local function hex(c: Color3): string
	local r = math.clamp(math.floor(c.R * 255 + 0.5), 0, 255)
	local g = math.clamp(math.floor(c.G * 255 + 0.5), 0, 255)
	local b = math.clamp(math.floor(c.B * 255 + 0.5), 0, 255)
	return string.format("#%02X%02X%02X", r, g, b)
end

local function lerpColor(a: Color3, b: Color3, t: number): Color3
	return Color3.new(a.R + (b.R - a.R) * t, a.G + (b.G - a.G) * t, a.B + (b.B - a.B) * t)
end

local function colorAt(stops: { Color3 }, t: number): Color3
	if #stops == 0 then return Color3.new(1, 1, 1) end
	if #stops == 1 then return stops[1] end
	local segs = #stops - 1
	local pos = t * segs
	local i = math.clamp(math.floor(pos) + 1, 1, segs)
	local lt = math.clamp(pos - (i - 1), 0, 1)
	return lerpColor(stops[i], stops[i + 1], lt)
end

local function graphemes(s: string): { string }
	local out = {}
	for first, last in utf8.graphemes(s) do
		table.insert(out, string.sub(s, first, last))
	end
	return out
end

export type TagStyle = {
	color: Color3?,
	gradient: { colors: { Color3 } }?,
	bold: boolean?,
	brackets: boolean?,
	spaceAfter: boolean?,
	animated: boolean?,
	speed: number?,
}

local function buildStyledTag(text: string, style: TagStyle?, timeNow: number): string
	style = style or {}
	local useBrackets = (style.brackets ~= false)
	local makeBold = (style.bold ~= false)
	local spaceAfter = (style.spaceAfter ~= false)

	local inner = useBrackets and ("[" .. text .. "]") or text

	if style.color and not style.gradient then
		local tag = string.format('<font color="%s">%s</font>', hex(style.color), inner)
		if makeBold then tag = "<b>" .. tag .. "</b>" end
		return tag .. (spaceAfter and " " or "")
	end

	local gradient = style.gradient
	if gradient and gradient.colors and #gradient.colors > 0 then
		local chars = graphemes(inner)
		local n = #chars
		if n == 0 then return "" end

		local speed = (style.animated and (style.speed or 0.25)) or 0
		local phase = (speed > 0) and (timeNow * speed % 1) or 0

		local buff = table.create(n)
		for i, ch in ipairs(chars) do
			local t = (n == 1) and 0 or (i - 1) / (n - 1)
			local charOffset = (i - 1) * 0.1
			t = (t + phase + charOffset) % 1
			local c = colorAt(gradient.colors, t)
			buff[i] = string.format('<font color="%s">%s</font>', hex(c), ch)
		end

		local tag = table.concat(buff)
		if makeBold then tag = "<b>" .. tag .. "</b>" end
		return tag .. (spaceAfter and " " or "")
	end

	local tag = inner
	if makeBold then tag = "<b>" .. tag .. "</b>" end
	return tag .. (spaceAfter and " " or "")
end

local TagManager = {}
TagManager.__index = TagManager

function TagManager.new()
	return setmetatable({
		_defs = {},
		_staticCache = {},
		GroupStyle = Config.GroupStyle,
	}, TagManager)
end

function TagManager:AddTag(name: string, style: TagStyle?, condition: (Player) -> boolean)
	table.insert(self._defs, { name = name, style = style or {}, condition = condition })
	self._staticCache = {}
end

function TagManager:Invalidate(player: Player?)
	if player then
		self._staticCache[player.UserId] = nil
	else
		self._staticCache = {}
	end
end

function TagManager:_groupTag(player: Player, timeNow: number): (string?, boolean)
	local ok, inGroup = pcall(function()
		return player:IsInGroup(Config.GROUP_ID)
	end)
	if not ok or not inGroup then return nil, false end

	local role = "Member"
	pcall(function()
		role = player:GetRoleInGroup(Config.GROUP_ID) or "Member"
	end)
	if not role or role == "" or role == "Guest" then return nil, false end

	local style = self.GroupStyle
	local animated = style and style.animated and (style.gradient ~= nil)
	return buildStyledTag(role, style, timeNow), animated
end

function TagManager:GetPrefix(player: Player, timeNow: number): (string, boolean)
	if not player then return "", false end

	local parts = {}
	local hasAnimated = false

	local g, anim = self:_groupTag(player, timeNow)
	if g then
		table.insert(parts, g)
		if anim then hasAnimated = true end
	end

	for _, def in ipairs(self._defs) do
		local ok, show = pcall(def.condition, player)
		if ok and show then
			local isAnimated = def.style and def.style.animated and def.style.gradient ~= nil
			if isAnimated then hasAnimated = true end
			table.insert(parts, buildStyledTag(def.name, def.style, timeNow))
		end
	end

	if not hasAnimated then
		local cached = self._staticCache[player.UserId]
		if cached then return cached, false end
		local prefix = table.concat(parts, "")
		self._staticCache[player.UserId] = prefix
		return prefix, false
	end

	return table.concat(parts, ""), true
end

local Tags = TagManager.new()

Tags:AddTag("VIP", Config.VIPStyle, function(plr: Player)
	local passes = plr:FindFirstChild("Passes")
	if not passes then return false end
	local vip = passes:FindFirstChild("VIP")
	return vip and vip:IsA("BoolValue") and vip.Value == true or false
end)

local function bindVIP(player: Player)
	local passes = player:FindFirstChild("Passes") or player:WaitForChild("Passes")
	if not passes or not passes:IsA("Folder") then return end

	local vip = passes:FindFirstChild("VIP") or passes:WaitForChild("VIP")
	if vip and vip:IsA("BoolValue") then
		vip:GetPropertyChangedSignal("Value"):Connect(function()
			Tags:Invalidate(player)
		end)
	end

	passes.ChildAdded:Connect(function(c)
		if c.Name == "VIP" and c:IsA("BoolValue") then
			c:GetPropertyChangedSignal("Value"):Connect(function()
				Tags:Invalidate(player)
			end)
			Tags:Invalidate(player)
		end
	end)
end

local function attachPlayerWatchers(player: Player)
	player.AttributeChanged:Connect(function()
		Tags:Invalidate(player)
	end)

	task.spawn(function()
		bindVIP(player)
		Tags:Invalidate(player)
	end)

	player.ChildAdded:Connect(function(c)
		if c.Name == "Passes" then
			task.spawn(function()
				bindVIP(player)
				Tags:Invalidate(player)
			end)
		end
	end)
end

for _, plr in ipairs(Players:GetPlayers()) do
	attachPlayerWatchers(plr)
end

Players.PlayerAdded:Connect(attachPlayerWatchers)
Players.PlayerRemoving:Connect(function(plr)
	Tags._staticCache[plr.UserId] = nil
end)

local AnimationSystem = {}
AnimationSystem.activeMessages = {}
AnimationSystem.lastUpdateTime = 0

function AnimationSystem:RegisterMessage(messageProperties: TextChatMessageProperties, speaker: Player)
	local _, hasAnimated = Tags:GetPrefix(speaker, os.clock())
	if hasAnimated then
		self.activeMessages[messageProperties] = { speaker = speaker }
	end
end

function AnimationSystem:Update()
	local now = os.clock()
	if now - self.lastUpdateTime < (1 / Config.ANIMATION_FPS) then return end
	self.lastUpdateTime = now

	for properties, data in pairs(self.activeMessages) do
		if data.speaker and data.speaker.Parent then
			local prefix, hasAnimated = Tags:GetPrefix(data.speaker, now)
			if hasAnimated then
				local displayName = data.speaker.DisplayName or data.speaker.Name
				properties.PrefixText = prefix .. displayName
			else
				self.activeMessages[properties] = nil
			end
		else
			self.activeMessages[properties] = nil
		end
	end
end

RunService.Heartbeat:Connect(function()
	AnimationSystem:Update()
end)

TextChatService.OnIncomingMessage = function(message: TextChatMessage)
	if not message.TextSource then return nil end

	local props = Instance.new("TextChatMessageProperties")
	local speaker = Players:GetPlayerByUserId(message.TextSource.UserId)
	local now = os.clock()

	if speaker then
		local displayName = speaker.DisplayName or speaker.Name
		local prefix, hasAnimated = Tags:GetPrefix(speaker, now)
		props.PrefixText = prefix .. displayName
		if hasAnimated then
			AnimationSystem:RegisterMessage(props, speaker)
		end
	else
		props.PrefixText = message.TextSource.Name
	end

	return props
end
