local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CrewAssetAudit = {}

local ASSETS_FOLDER_NAME = "Assets"
local CREW_CHARACTERS_FOLDER_NAME = "One Piece Characters"
local MAX_PRINT_ITEMS = 25

local warned = {}

local function warnOnce(key, message)
	if warned[key] then
		return
	end
	warned[key] = true
	warn(message)
end

local function append(list, value)
	list[#list + 1] = value
end

local function sortStrings(list)
	table.sort(list, function(a, b)
		return tostring(a) < tostring(b)
	end)
end

local function sortByPath(list)
	table.sort(list, function(a, b)
		return tostring(a.Path) < tostring(b.Path)
	end)
end

local function getRelativePath(instance, root)
	local names = {}
	local current = instance

	while current and current ~= root do
		table.insert(names, 1, current.Name)
		current = current.Parent
	end

	return table.concat(names, ".")
end

local function countModelDescendants(model)
	local basePartCount = 0
	local anchoredBasePartCount = 0
	local scriptCount = 0

	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") then
			basePartCount += 1
			if descendant.Anchored then
				anchoredBasePartCount += 1
			end
		elseif descendant:IsA("BaseScript") then
			scriptCount += 1
		end
	end

	return basePartCount, anchoredBasePartCount, scriptCount
end

local function inspectModel(model, folder, isDirectChild)
	local basePartCount, anchoredBasePartCount, scriptCount = countModelDescendants(model)
	local reasons = {}

	if model.Archivable == false then
		append(reasons, "ArchivableFalse")
	end
	if basePartCount == 0 then
		append(reasons, "NoBasePart")
	end
	if model.PrimaryPart == nil then
		append(reasons, "MissingPrimaryPart")
	end
	if scriptCount > 0 then
		append(reasons, "ContainsScriptDescendants")
	end

	return {
		Name = model.Name,
		Path = getRelativePath(model, folder),
		FullPath = model:GetFullName(),
		IsDirectChild = isDirectChild,
		Archivable = model.Archivable,
		PrimaryPartName = model.PrimaryPart and model.PrimaryPart.Name or nil,
		BasePartCount = basePartCount,
		AnchoredBasePartCount = anchoredBasePartCount,
		UnanchoredBasePartCount = basePartCount - anchoredBasePartCount,
		ScriptDescendantCount = scriptCount,
		UnsafeReasons = reasons,
	}
end

local function collectDuplicateNames(modelDetails)
	local byName = {}
	for _, detail in ipairs(modelDetails) do
		byName[detail.Name] = byName[detail.Name] or {}
		append(byName[detail.Name], detail.Path)
	end

	local duplicates = {}
	for name, paths in pairs(byName) do
		if #paths > 1 then
			sortStrings(paths)
			append(duplicates, {
				Name = name,
				Paths = paths,
			})
		end
	end

	table.sort(duplicates, function(a, b)
		return tostring(a.Name) < tostring(b.Name)
	end)

	return duplicates, byName
end

local function summarizeReport(report)
	return string.format(
		"folderExists=%s directModels=%d nestedModels=%d duplicateNames=%d nonModelChildren=%d missingPrimaryPart=%d noBasePart=%d unsafeForCloning=%d",
		tostring(report.FolderExists),
		#report.DirectModelNames,
		#report.NestedModels,
		#report.DuplicateModelNames,
		#report.NonModelChildren,
		#report.ModelsMissingPrimaryPart,
		#report.ModelsWithNoBasePart,
		#report.ModelsUnsafeForToolOrStandCloning
	)
end

local function printList(label, list, formatter)
	print(string.format("[CrewAssetAudit] %s (%d)", label, #list))
	for index, value in ipairs(list) do
		if index > MAX_PRINT_ITEMS then
			print(string.format("[CrewAssetAudit] ... %d more", #list - MAX_PRINT_ITEMS))
			break
		end
		print("[CrewAssetAudit] - " .. formatter(value))
	end
end

function CrewAssetAudit.GetExpectedFolder()
	local assets = ReplicatedStorage:FindFirstChild(ASSETS_FOLDER_NAME)
	return assets and assets:FindFirstChild(CREW_CHARACTERS_FOLDER_NAME) or nil
end

function CrewAssetAudit.Run(options)
	options = options or {}
	local shouldWarn = options.Warn ~= false
	local folder = CrewAssetAudit.GetExpectedFolder()

	local report = {
		FolderExists = folder ~= nil,
		FolderPath = folder and folder:GetFullName() or "ReplicatedStorage.Assets.One Piece Characters",
		DirectModelNames = {},
		DirectModels = {},
		NestedModelNames = {},
		NestedModels = {},
		AllModels = {},
		ModelNamesByName = {},
		DuplicateModelNames = {},
		NonModelChildren = {},
		ModelsMissingPrimaryPart = {},
		ModelsWithNoBasePart = {},
		ModelsUnsafeForToolOrStandCloning = {},
		Summary = nil,
	}

	if not folder then
		report.Summary = summarizeReport(report)
		if shouldWarn then
			warnOnce(
				"missing_one_piece_characters",
				"[CrewAssetAudit] ReplicatedStorage.Assets.One Piece Characters is missing. Real crewmate model rollout is not ready; resolver fallback remains required."
			)
		end
		return report
	end

	for _, child in ipairs(folder:GetChildren()) do
		if child:IsA("Model") then
			append(report.DirectModelNames, child.Name)
		else
			append(report.NonModelChildren, {
				Name = child.Name,
				ClassName = child.ClassName,
				Path = getRelativePath(child, folder),
				FullPath = child:GetFullName(),
			})
		end
	end

	for _, descendant in ipairs(folder:GetDescendants()) do
		if descendant:IsA("Model") then
			local isDirectChild = descendant.Parent == folder
			local detail = inspectModel(descendant, folder, isDirectChild)
			append(report.AllModels, detail)

			if isDirectChild then
				append(report.DirectModels, detail)
			else
				append(report.NestedModelNames, descendant.Name)
				append(report.NestedModels, detail)
			end

			if detail.PrimaryPartName == nil then
				append(report.ModelsMissingPrimaryPart, detail)
			end
			if detail.BasePartCount == 0 then
				append(report.ModelsWithNoBasePart, detail)
			end
			if #detail.UnsafeReasons > 0 then
				append(report.ModelsUnsafeForToolOrStandCloning, detail)
			end
		end
	end

	sortStrings(report.DirectModelNames)
	sortStrings(report.NestedModelNames)
	sortByPath(report.DirectModels)
	sortByPath(report.NestedModels)
	sortByPath(report.AllModels)
	sortByPath(report.NonModelChildren)
	sortByPath(report.ModelsMissingPrimaryPart)
	sortByPath(report.ModelsWithNoBasePart)
	sortByPath(report.ModelsUnsafeForToolOrStandCloning)

	report.DuplicateModelNames, report.ModelNamesByName = collectDuplicateNames(report.AllModels)
	report.Summary = summarizeReport(report)

	return report
end

function CrewAssetAudit.PrintReport(options)
	local report = CrewAssetAudit.Run(options)
	print("[CrewAssetAudit] " .. report.Summary)

	if not report.FolderExists then
		print("[CrewAssetAudit] Expected folder: " .. tostring(report.FolderPath))
		return report
	end

	printList("direct child models", report.DirectModels, function(value)
		return string.format("%s path=%s", tostring(value.Name), tostring(value.Path))
	end)
	printList("nested models", report.NestedModels, function(value)
		return string.format("%s path=%s", tostring(value.Name), tostring(value.Path))
	end)
	printList("duplicate model names", report.DuplicateModelNames, function(value)
		return string.format("%s paths=%s", tostring(value.Name), table.concat(value.Paths, ", "))
	end)
	printList("non-Model direct children", report.NonModelChildren, function(value)
		return string.format("%s class=%s path=%s", tostring(value.Name), tostring(value.ClassName), tostring(value.Path))
	end)
	printList("models missing PrimaryPart", report.ModelsMissingPrimaryPart, function(value)
		return string.format("%s path=%s", tostring(value.Name), tostring(value.Path))
	end)
	printList("models with no BasePart", report.ModelsWithNoBasePart, function(value)
		return string.format("%s path=%s", tostring(value.Name), tostring(value.Path))
	end)
	printList("models potentially unsafe for tool/stand cloning", report.ModelsUnsafeForToolOrStandCloning, function(value)
		return string.format("%s path=%s reasons=%s", tostring(value.Name), tostring(value.Path), table.concat(value.UnsafeReasons, ", "))
	end)

	return report
end

return CrewAssetAudit
