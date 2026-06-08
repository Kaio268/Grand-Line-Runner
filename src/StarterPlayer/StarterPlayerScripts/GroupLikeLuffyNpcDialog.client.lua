local GroupService = game:GetService("GroupService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local Modules = ReplicatedStorage:WaitForChild("Modules")
local DialogModule = require(ReplicatedStorage:WaitForChild("DialogModule"))
local MapResolver = require(Modules:WaitForChild("MapResolver"))
local PopUpModule = require(Modules:WaitForChild("PopUpModule"))
local SocialGroups = require(Modules:WaitForChild("Configs"):WaitForChild("SocialGroups"))

local GROUP_ID = SocialGroups.GroupLikeRewardGroupId
local REMOTE_NAME = "GroupLikeRewardRequest"
local SUCCESS_COLOR = Color3.fromRGB(98, 255, 124)
local ERROR_COLOR = Color3.fromRGB(255, 104, 104)
local POPUP_STROKE = Color3.fromRGB(0, 0, 0)

local refs = MapResolver.WaitForRefs(
	{ "GroupLikeLuffyNpc" },
	nil,
	{
		warn = true,
		context = "GroupLikeLuffyNpcDialog",
	}
)
local npc = refs.GroupLikeLuffyNpc
if not npc then
	return
end

local function popup(text, isError)
	PopUpModule:Local_SendPopUp(
		text,
		if isError then ERROR_COLOR else SUCCESS_COLOR,
		POPUP_STROKE,
		3,
		isError == true
	)
end

local function getModelPrimaryPart(model)
	if model.PrimaryPart and model.PrimaryPart:IsA("BasePart") then
		return model.PrimaryPart
	end

	local humanoidRootPart = model:FindFirstChild("HumanoidRootPart")
	if humanoidRootPart and humanoidRootPart:IsA("BasePart") then
		model.PrimaryPart = humanoidRootPart
		return humanoidRootPart
	end

	local basePart = model:FindFirstChildWhichIsA("BasePart", true)
	if basePart then
		model.PrimaryPart = basePart
	end
	return basePart
end

local function waitForNpcPrompt(model, timeoutSeconds)
	local deadline = os.clock() + (timeoutSeconds or 20)
	while model.Parent and os.clock() <= deadline do
		local prompt = model:FindFirstChildWhichIsA("ProximityPrompt", true)
		if prompt then
			return prompt
		end
		task.wait(0.1)
	end
	return nil
end

local function waitForNpcGui(model, timeoutSeconds)
	local deadline = os.clock() + (timeoutSeconds or 20)
	while model.Parent and os.clock() <= deadline do
		local primaryPart = getModelPrimaryPart(model)
		local gui = primaryPart and primaryPart:FindFirstChild("gui")
		if gui and gui:IsA("BillboardGui") then
			return gui
		end
		task.wait(0.1)
	end
	return nil
end

local function waitForRequestRemote(timeoutSeconds)
	local remotes = ReplicatedStorage:WaitForChild("Remotes", timeoutSeconds or 20)
	if not remotes then
		return nil
	end

	local remote = remotes:WaitForChild(REMOTE_NAME, timeoutSeconds or 20)
	if remote and remote:IsA("RemoteFunction") then
		return remote
	end

	return nil
end

local prompt = waitForNpcPrompt(npc)
if not prompt then
	warn("[GroupLikeLuffyNpcDialog] Luffy prompt is unavailable.")
	return
end
prompt.ObjectText = "Talk to Luffy"
prompt.ActionText = "Talk"

if not waitForNpcGui(npc) then
	warn("[GroupLikeLuffyNpcDialog] Luffy overhead gui is unavailable.")
	return
end

local requestRemote = waitForRequestRemote()
if not requestRemote then
	warn("[GroupLikeLuffyNpcDialog] Group-like reward remote is unavailable.")
	return
end

local dialogObject = DialogModule.new("Luffy", npc, prompt)
dialogObject:addDialog(
	"Like the game, join our Roblox group, then claim your reward: 100 Gold Chests.",
	{ "I liked and joined - claim", "Join Group", "Not now" }
)
dialogObject:addDialog("You already claimed the 100 Gold Chests. Thanks for supporting the game.", { "Thanks" })

local claimBusy = false

local function invokeReward(actionName)
	local ok, response = pcall(function()
		return requestRemote:InvokeServer(actionName)
	end)
	if ok and typeof(response) == "table" then
		return response
	end
	return {
		ok = false,
		message = "Reward service is unavailable.",
		error = "invoke_failed",
	}
end

local function promptGroupJoin()
	local ok, statusOrError = pcall(function()
		return GroupService:PromptJoinAsync(GROUP_ID)
	end)
	if not ok then
		warn("[GroupLikeLuffyNpcDialog] Group join prompt failed:", statusOrError)
		popup("Group join prompt failed.", true)
		return
	end

	if statusOrError == Enum.GroupMembershipStatus.Joined then
		popup("Thanks for joining! Talk to Luffy again to claim.", false)
	elseif statusOrError == Enum.GroupMembershipStatus.AlreadyMember then
		popup("You are in the group. Claim when ready.", false)
	else
		popup("Join the group, then talk to Luffy again.", false)
	end
end

prompt.Triggered:Connect(function(triggeringPlayer)
	if triggeringPlayer and triggeringPlayer ~= player then
		return
	end

	local response = invokeReward("GetState")
	if response.ok == true and response.state and response.state.claimed == true then
		dialogObject:triggerDialog(player, 2)
	else
		dialogObject:triggerDialog(player, 1)
	end
end)

dialogObject.responded:Connect(function(responseNum, dialogNum)
	if dialogNum == 2 then
		dialogObject:hideGui("See you on the seas.")
		return
	end

	if dialogNum ~= 1 then
		return
	end

	if responseNum == 3 then
		dialogObject:hideGui("Come back when you're ready.")
		return
	elseif responseNum == 2 then
		dialogObject:hideGui("Join the group, then talk to me again.")
		promptGroupJoin()
		return
	end

	if claimBusy then
		return
	end

	claimBusy = true
	local response = invokeReward("Claim")
	claimBusy = false

	if response.ok == true then
		dialogObject:hideGui("The chests are yours. Thanks for the support!")
		return
	end

	local errorCode = tostring(response.error or "")
	local message = tostring(response.message or "Reward claim failed.")
	if errorCode == "already_claimed" then
		dialogObject:hideGui("You already claimed this reward.")
	elseif errorCode == "not_in_group" or errorCode == "group_check_failed" then
		dialogObject:hideGui("Join the group first, then talk to me again.")
	else
		dialogObject:hideGui("Not yet.")
	end
	if errorCode == "invoke_failed" or errorCode == "remote_guard_rejected" or errorCode == "busy" then
		popup(message, true)
	end
end)
