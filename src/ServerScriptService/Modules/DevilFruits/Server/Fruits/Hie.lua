local HieServerFruit = {}

function HieServerFruit.GetLegacyHandler()
	return require(script.Parent.Parent.Parent:WaitForChild("Hie"))
end

return HieServerFruit
