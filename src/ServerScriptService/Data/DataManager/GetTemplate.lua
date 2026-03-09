local TemplateTable = {}

function RecursiveSearch(Table : {}, PreviousContainer : Folder)
	if not PreviousContainer:IsA("Folder") then
		return
	end

	for _, Element in pairs(PreviousContainer:GetChildren()) do
		if Element:IsA("Folder") then
			Table[tostring(Element.Name)] = {}
			RecursiveSearch(Table[tostring(Element.Name)], Element)
		else
			if Element:IsA("NumberValue") or Element:IsA("StringValue") or Element:IsA("BoolValue") or Element:IsA("IntValue") then
				Table[tostring(Element.Name)] = Element.Value
			else
				warn("[DataManager]: Something went wrong during processing template")
			end
		end
	end
end

if script.Parent:FindFirstChild("Data") then
	RecursiveSearch(TemplateTable, script.Parent.Data)
end


return TemplateTable
