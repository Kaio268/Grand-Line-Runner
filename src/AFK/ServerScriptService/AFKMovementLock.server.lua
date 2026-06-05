local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")

local DataEnvironment = require(ServerScriptService:WaitForChild("Data"):WaitForChild("DataEnvironment"))

local LOCKED_WALK_SPEED = 0
local LOCKED_JUMP_POWER = 0
local LOCKED_JUMP_HEIGHT = 0

local placeInfo = DataEnvironment.ResolvePlace(game.PlaceId)
if placeInfo.PlaceRole ~= DataEnvironment.PlaceRoles.AFK then
	warn(string.format(
		"[AFKMovementLock] Expected AFK role but running in %s/%s place %s; movement lock disabled.",
		tostring(placeInfo.Environment),
		tostring(placeInfo.PlaceRole),
		tostring(game.PlaceId)
	))
	return
end

local characterConnectionsByPlayer = {}
local playerConnectionsByPlayer = {}

local function disconnectAll(connections)
	if connections == nil then
		return
	end
	for _, connection in ipairs(connections) do
		connection:Disconnect()
	end
	table.clear(connections)
end

local function zeroRootVelocity(character)
	local root = character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		root.AssemblyLinearVelocity = Vector3.zero
		root.AssemblyAngularVelocity = Vector3.zero
	end
end

local function applyHumanoidLock(humanoid)
	if humanoid.WalkSpeed ~= LOCKED_WALK_SPEED then
		humanoid.WalkSpeed = LOCKED_WALK_SPEED
	end
	if humanoid.JumpPower ~= LOCKED_JUMP_POWER then
		humanoid.JumpPower = LOCKED_JUMP_POWER
	end
	if humanoid.JumpHeight ~= LOCKED_JUMP_HEIGHT then
		humanoid.JumpHeight = LOCKED_JUMP_HEIGHT
	end
	if humanoid.AutoRotate ~= false then
		humanoid.AutoRotate = false
	end
	humanoid.Jump = false
	pcall(function()
		humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
	end)
end

local function connectHumanoidLock(player, humanoid)
	local connections = characterConnectionsByPlayer[player]
	if connections == nil then
		return
	end

	applyHumanoidLock(humanoid)
	local function reapply()
		applyHumanoidLock(humanoid)
	end

	table.insert(connections, humanoid:GetPropertyChangedSignal("WalkSpeed"):Connect(reapply))
	table.insert(connections, humanoid:GetPropertyChangedSignal("JumpPower"):Connect(reapply))
	table.insert(connections, humanoid:GetPropertyChangedSignal("JumpHeight"):Connect(reapply))
	table.insert(connections, humanoid:GetPropertyChangedSignal("AutoRotate"):Connect(reapply))
	table.insert(connections, humanoid:GetPropertyChangedSignal("Jump"):Connect(reapply))
end

local function lockCharacter(player, character)
	disconnectAll(characterConnectionsByPlayer[player])
	characterConnectionsByPlayer[player] = {}

	zeroRootVelocity(character)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		connectHumanoidLock(player, humanoid)
	end

	table.insert(characterConnectionsByPlayer[player], character.DescendantAdded:Connect(function(descendant)
		if descendant:IsA("Humanoid") then
			connectHumanoidLock(player, descendant)
		elseif descendant.Name == "HumanoidRootPart" and descendant:IsA("BasePart") then
			zeroRootVelocity(character)
		end
	end))
end

local function watchPlayer(player)
	disconnectAll(playerConnectionsByPlayer[player])
	playerConnectionsByPlayer[player] = {}

	table.insert(playerConnectionsByPlayer[player], player.CharacterAdded:Connect(function(character)
		lockCharacter(player, character)
	end))

	if player.Character then
		lockCharacter(player, player.Character)
	end
end

local function cleanupPlayer(player)
	disconnectAll(characterConnectionsByPlayer[player])
	disconnectAll(playerConnectionsByPlayer[player])
	characterConnectionsByPlayer[player] = nil
	playerConnectionsByPlayer[player] = nil
end

Players.PlayerAdded:Connect(watchPlayer)
Players.PlayerRemoving:Connect(cleanupPlayer)

for _, player in ipairs(Players:GetPlayers()) do
	watchPlayer(player)
end
