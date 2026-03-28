local MeraServerFruit = {}

function MeraServerFruit.GetLegacyHandler()
	return require(script.Parent.Parent.Parent:WaitForChild("Mera"))
end

return MeraServerFruit
