local StarterGui = game:GetService("StarterGui")

local function disableCoreGui(coreGuiType)
	pcall(function()
		StarterGui:SetCoreGuiEnabled(coreGuiType, false)
	end)
end

disableCoreGui(Enum.CoreGuiType.Backpack)

disableCoreGui(Enum.CoreGuiType.EmotesMenu)

