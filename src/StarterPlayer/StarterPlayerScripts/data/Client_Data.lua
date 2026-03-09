--// Requires
local ReplicaClient = require(script.Parent.Parent.ReplicaClient)

--// Variables
local Player = game.Players.LocalPlayer

--// Main
local Data = {}
Data.__index = Data; self = setmetatable({}, Data)

Data.PlayerData = {}
Data.IsReady = false

function Data.WaitUntilReady()
	while not self.IsReady do
		task.wait()
	end
	
	return
end

function Data:GetData()
	return Data.PlayerData
end

function debugger(path: {string})
	local pointer = Data.PlayerData
	for i = 1, #path - 1 do
		pointer = pointer[path[i]]
	end
	
	warn(`[DataScript]: DEBUGGER VALUE: `, pointer[path[#path]])
end

function Data:Update(action : string, path : {string}, value : any)
	if action == "Set" then
		local pointer = Data.PlayerData
		for i = 1, #path - 1 do
			pointer = pointer[path[i]]
		end
		
		pointer[path[#path]] = value
		--debugger(path)
	end
end
function Data.New(token : string)
	ReplicaClient.RequestData()
	
	ReplicaClient.OnNew(token, function(replica)
		if replica.Tags.UserId and replica.Tags.UserId == Player.UserId then
			Data.PlayerData = replica.Data
			Data.IsReady = true
			
			replica:OnChange(function(action, path, v1, v2)
				self:Update(action, path, v1)
			end)
		end
	end)
end



return Data