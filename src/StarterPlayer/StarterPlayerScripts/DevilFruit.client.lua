local ReplicatedStorage = game:GetService("ReplicatedStorage")

local fruitHoldPresentation = require(
	ReplicatedStorage:WaitForChild("Modules"):WaitForChild("DevilFruits"):WaitForChild("Client"):WaitForChild("FruitHoldPresentation")
)
local controller = require(
	ReplicatedStorage:WaitForChild("Modules"):WaitForChild("DevilFruits"):WaitForChild("Client"):WaitForChild("DevilFruitClientController")
)

fruitHoldPresentation.Start()
controller.Start()
