local CrewPreviewImages = {}

local CREW_MEMBER_RENDER_PLACEHOLDER = "rbxasset://textures/ui/GuiImagePlaceholder.png"

local METADATA_IMAGE_KEYS = {
	"StaticPreviewImage",
	"staticPreviewImage",
	"PreviewImage",
	"previewImage",
	"PreviewImageAsset",
	"previewImageAsset",
	"PreviewImageId",
	"previewImageId",
}

local FIELD_KEYS = {
	"CrewMemberId",
	"crewMemberId",
	"BaseCrewMemberId",
	"baseCrewMemberId",
	"CrewMemberName",
	"crewMemberName",
	"DisplayName",
	"displayName",
	"ModelName",
	"modelName",
	"PreviewName",
	"previewName",
	"RealCharacterName",
	"realCharacterName",
	"LegacyIdentity",
	"legacyIdentity",
	"Name",
	"name",
	"Id",
	"id",
}

local MODEL_PREVIEW_KEYS = {
	"ModelPreview",
	"modelPreview",
	"Preview",
	"preview",
}

local METADATA_SOURCE_KEYS = {
	"Metadata",
	"metadata",
	"DisplayMetadata",
	"displayMetadata",
	"Info",
	"info",
}

local VARIANT_PREFIXES = {
	"Golden ",
	"Diamond ",
}

local staticPreviewImageByLookupKey = {}
local staticPreviewImages = {}

local function normalizeImage(image)
	local imageText = tostring(image or "")
	if imageText == "" or imageText == CREW_MEMBER_RENDER_PLACEHOLDER then
		return ""
	end

	local numericAssetId = tonumber(imageText)
	if numericAssetId ~= nil then
		return "rbxassetid://" .. tostring(numericAssetId)
	end

	return imageText
end

local function normalizeLookupKey(value)
	local text = string.lower(tostring(value or ""))
	text = text:gsub("[%s_%-]+", "")
	return text
end

local function registerStaticPreview(image, aliases)
	local normalizedImage = normalizeImage(image)
	if normalizedImage == "" then
		return
	end

	staticPreviewImages[normalizedImage] = true

	for _, alias in ipairs(aliases) do
		local text = tostring(alias or "")
		if text ~= "" then
			staticPreviewImageByLookupKey[text] = normalizedImage
			staticPreviewImageByLookupKey[normalizeLookupKey(text)] = normalizedImage
		end
	end
end

registerStaticPreview("rbxassetid://100397390355149", {
	"Ember Fist",
	"Ace",
})

registerStaticPreview("rbxassetid://78291935006007", {
	"Venom Warden",
	"Magellan",
	"Magellon",
})

registerStaticPreview("rbxassetid://115287190180699", {
	"Metal Glutton",
	"Wapol",
})

registerStaticPreview("rbxassetid://78116055270213", {
	"Storm Cartographer",
	"Nami",
})

registerStaticPreview("rbxassetid://134951637512759", {
	"Iron Shipwright",
	"Franky",
})

registerStaticPreview("rbxassetid://123836331828429", {
	"Hawkblade Lord",
	"Mihawk",
})

registerStaticPreview("rbxthumb://type=Asset&id=87585297816571&w=420&h=420", {
	"Dino Marine",
	"XDrake",
	"X Drake",
	"X_Drake",
	"x drake",
})

registerStaticPreview("rbxassetid://86049312074858", {
	"Straw Prophet",
	"Hawkins",
})

registerStaticPreview("rbxassetid://120380137910449", {
	"Bloom Scholar",
	"Robin",
})

registerStaticPreview("rbxassetid://102257447334492", {
	"Barrier Punk",
	"Bartolomeo",
})

registerStaticPreview("rbxassetid://75586655035699", {
	"Diamond Bruiser",
	"Jozu",
})

registerStaticPreview("rbxassetid://109925942347680", {
	"Frost Admiral",
	"Aokiji",
})

registerStaticPreview("rbxassetid://102893211014509", {
	"Azure Phoenix",
	"Marco",
})

registerStaticPreview("rbxassetid://86877993232981", {
	"Tide Monk",
	"Jinbe",
	"Jimbe",
	"Jinbei",
	"Jimbei",
})

registerStaticPreview("rbxassetid://98090596650801", {
	"Mask Dancer",
	"Bon Clay",
})

registerStaticPreview("rbxassetid://130789190033029", {
	"Ghost Samurai",
	"Ryuma",
})

registerStaticPreview("rbxassetid://102634396468524", {
	"Rubber Captain",
	"Luffy",
})

registerStaticPreview("rbxassetid://111666514759594", {
	"Pink Marine",
	"Coby",
	"Koby",
	"Kobe",
})

local function readTableValue(source, key)
	if typeof(source) ~= "table" then
		return nil
	end

	return source[key]
end

local function readInstanceValue(source, key)
	if typeof(source) ~= "Instance" then
		return nil
	end

	local attributeValue = source:GetAttribute(key)
	if attributeValue ~= nil then
		return attributeValue
	end

	local child = source:FindFirstChild(key)
	if child and child:IsA("StringValue") then
		return child.Value
	end

	return nil
end

local function readSourceValue(source, key)
	return readTableValue(source, key) or readInstanceValue(source, key)
end

local function readMetadataImage(source)
	if typeof(source) ~= "table" and typeof(source) ~= "Instance" then
		return ""
	end

	for _, key in ipairs(METADATA_IMAGE_KEYS) do
		local image = normalizeImage(readSourceValue(source, key))
		if image ~= "" then
			return image
		end
	end

	return ""
end

local function pushCandidate(candidates, value)
	local text = tostring(value or "")
	if text == "" then
		return
	end

	candidates[#candidates + 1] = text

	for _, prefix in ipairs(VARIANT_PREFIXES) do
		if string.sub(text, 1, #prefix) == prefix then
			local baseText = string.sub(text, #prefix + 1)
			if baseText ~= "" then
				candidates[#candidates + 1] = baseText
			end
		end
	end
end

local function pushDescriptorCandidates(candidates, descriptor)
	if typeof(descriptor) ~= "table" and typeof(descriptor) ~= "Instance" then
		return
	end

	pushCandidate(candidates, readSourceValue(descriptor, "ModelName") or readSourceValue(descriptor, "modelName"))
	pushCandidate(candidates, readSourceValue(descriptor, "LegacyIdentity") or readSourceValue(descriptor, "legacyIdentity"))
	pushCandidate(candidates, readSourceValue(descriptor, "CrewMemberId") or readSourceValue(descriptor, "crewMemberId"))
end

local function collectCandidatesFromSource(candidates, source)
	if typeof(source) == "string" or typeof(source) == "number" then
		pushCandidate(candidates, source)
		return
	end

	if typeof(source) ~= "table" and typeof(source) ~= "Instance" then
		return
	end

	for _, key in ipairs(FIELD_KEYS) do
		pushCandidate(candidates, readSourceValue(source, key))
	end

	for _, key in ipairs(MODEL_PREVIEW_KEYS) do
		pushDescriptorCandidates(candidates, readSourceValue(source, key))
	end
end

local function resolveMetadataImageFromSource(source)
	local image = readMetadataImage(source)
	if image ~= "" then
		return image
	end

	if typeof(source) ~= "table" and typeof(source) ~= "Instance" then
		return ""
	end

	for _, key in ipairs(METADATA_SOURCE_KEYS) do
		image = readMetadataImage(readSourceValue(source, key))
		if image ~= "" then
			return image
		end
	end

	return ""
end

local function resolveCandidate(candidate)
	local text = tostring(candidate or "")
	if text == "" then
		return ""
	end

	return normalizeImage(staticPreviewImageByLookupKey[text] or staticPreviewImageByLookupKey[normalizeLookupKey(text)])
end

function CrewPreviewImages.Resolve(primary, secondary)
	local metadataImage = resolveMetadataImageFromSource(primary)
	if metadataImage ~= "" then
		return metadataImage
	end

	metadataImage = resolveMetadataImageFromSource(secondary)
	if metadataImage ~= "" then
		return metadataImage
	end

	local candidates = {}
	collectCandidatesFromSource(candidates, primary)
	collectCandidatesFromSource(candidates, secondary)

	for _, candidate in ipairs(candidates) do
		local image = resolveCandidate(candidate)
		if image ~= "" then
			return image
		end
	end

	return ""
end

function CrewPreviewImages.Has(primary, secondary)
	return CrewPreviewImages.Resolve(primary, secondary) ~= ""
end

function CrewPreviewImages.ResolveStaticImage(image)
	local normalizedImage = normalizeImage(image)
	if staticPreviewImages[normalizedImage] then
		return normalizedImage
	end

	return ""
end

return CrewPreviewImages
