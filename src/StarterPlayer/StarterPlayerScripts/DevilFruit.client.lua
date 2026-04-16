local ReplicatedStorage = game:GetService("ReplicatedStorage")

local controller = require(
	ReplicatedStorage:WaitForChild("Modules"):WaitForChild("DevilFruits"):WaitForChild("Client"):WaitForChild("DevilFruitClientController")
)

controller.Start()
