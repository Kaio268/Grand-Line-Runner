local CrewMembers = {}

CrewMembers.RarityOrder = {
	"Common",
	"Uncommon",
	"Rare",
	"Epic",
	"Legendary",
	"Mythic",
	"Godly",
	"Secret",
}

CrewMembers.ArcOrder = {
	"Foosha Village",
	"Arlong Park",
	"Drum Island",
	"Alabasta",
	"Water 7",
	"Thriller Bark",
	"Sabaody",
	"Dressrosa",
}

CrewMembers.ArcRarity = {
	["Foosha Village"] = "Common",
	["Arlong Park"] = "Uncommon",
	["Drum Island"] = "Rare",
	Alabasta = "Epic",
	["Water 7"] = "Legendary",
	["Thriller Bark"] = "Mythic",
	Sabaody = "Godly",
	Dressrosa = "Secret",
}

-- LegacyId is the current saved-data/reward key. Keep it until the profile
-- Migration keeps old storage isolated while active systems use canonical Crew data.
CrewMembers.Entries = {
	{
		CrewMemberId = "Mask Dancer",
		DisplayName = "Mask Dancer",
		RealCharacterName = "Bon Clay",
		Arc = "Foosha Village",
		Rarity = "Common",
		ModelName = "Bon Clay",
		ModelNameVerified = true,
		LegacyId = "Lirili Larila",
	},
	{
		CrewMemberId = "Clown Captain",
		DisplayName = "Clown Captain",
		RealCharacterName = "Buggy",
		Arc = "Foosha Village",
		Rarity = "Common",
		ModelName = "Buggy",
		ModelNameVerified = true,
		LegacyId = "Boneca Ambalabu",
	},
	{
		CrewMemberId = "Metal Glutton",
		DisplayName = "Metal Glutton",
		RealCharacterName = "Wapol",
		Arc = "Foosha Village",
		Rarity = "Common",
		ModelName = "Wapol",
		ModelNameVerified = true,
		LegacyId = "Tun Tun Sahur",
	},
	{
		CrewMemberId = "Pink Marine",
		DisplayName = "Pink Marine",
		RealCharacterName = "Coby",
		Arc = "Foosha Village",
		Rarity = "Common",
		ModelName = "Coby",
		ModelNameVerified = true,
		LegacyId = "Tim Cheese",
	},

	{
		CrewMemberId = "Storm Cartographer",
		DisplayName = "Storm Cartographer",
		RealCharacterName = "Nami",
		Arc = "Arlong Park",
		Rarity = "Uncommon",
		ModelName = "Nami",
		ModelNameVerified = true,
		LegacyId = "Trulimero Trulicina",
	},
	{
		CrewMemberId = "Iron Shipwright",
		DisplayName = "Iron Shipwright",
		RealCharacterName = "Franky",
		Arc = "Arlong Park",
		Rarity = "Uncommon",
		ModelName = "Franky",
		ModelNameVerified = true,
		LegacyId = "Svinina Bombardino",
	},
	{
		CrewMemberId = "Soul Fiddler",
		DisplayName = "Soul Fiddler",
		RealCharacterName = "Brook",
		Arc = "Arlong Park",
		Rarity = "Uncommon",
		ModelName = "Brook",
		ModelNameVerified = false,
		MissingModel = true,
		LegacyId = "Gangster Footera",
	},
	{
		CrewMemberId = "Sawtooth Captain",
		DisplayName = "Sawtooth Captain",
		RealCharacterName = "Arlong",
		Arc = "Arlong Park",
		Rarity = "Uncommon",
		ModelName = "Arlong",
		ModelNameVerified = true,
		LegacyId = "Burbaloni Loliloli",
	},

	{
		CrewMemberId = "Straw Prophet",
		DisplayName = "Straw Prophet",
		RealCharacterName = "Hawkins",
		Arc = "Drum Island",
		Rarity = "Rare",
		ModelName = "Hawkins",
		ModelNameVerified = true,
		LegacyId = "Pipi Potato",
	},
	{
		CrewMemberId = "Dino Marine",
		DisplayName = "Dino Marine",
		RealCharacterName = "X Drake",
		Arc = "Drum Island",
		Rarity = "Rare",
		ModelName = "XDrake",
		ModelNameVerified = true,
		LegacyId = "Brr Brr Patapim",
	},
	{
		CrewMemberId = "Fortress Don",
		DisplayName = "Fortress Don",
		RealCharacterName = "Bege",
		Arc = "Drum Island",
		Rarity = "Rare",
		ModelName = "Bege",
		ModelNameVerified = true,
		LegacyId = "Trippi Troppi Troppa Trippa",
	},
	{
		CrewMemberId = "Bloom Scholar",
		DisplayName = "Bloom Scholar",
		RealCharacterName = "Robin",
		Arc = "Drum Island",
		Rarity = "Rare",
		ModelName = "Robin",
		ModelNameVerified = true,
		LegacyId = "Tatatata Sahur",
	},

	{
		CrewMemberId = "Barrier Punk",
		DisplayName = "Barrier Punk",
		RealCharacterName = "Bartolomeo",
		Arc = "Alabasta",
		Rarity = "Epic",
		ModelName = "Bartolomeo",
		ModelNameVerified = true,
		LegacyId = "Cappuccino Assassino",
	},
	{
		CrewMemberId = "Flint Kicker",
		DisplayName = "Flint Kicker",
		RealCharacterName = "Sanji",
		Arc = "Alabasta",
		Rarity = "Epic",
		ModelName = "Sanji",
		ModelNameVerified = true,
		LegacyId = "Chimpanzini Bananini",
	},
	{
		CrewMemberId = "Blade Ronin",
		DisplayName = "Blade Ronin",
		RealCharacterName = "Zoro",
		Arc = "Alabasta",
		Rarity = "Epic",
		ModelName = "Zoro",
		ModelNameVerified = true,
		LegacyId = "Fluri Flura",
	},
	{
		CrewMemberId = "Sand Tyrant",
		DisplayName = "Sand Tyrant",
		RealCharacterName = "Crocodile",
		Arc = "Alabasta",
		Rarity = "Epic",
		ModelName = "Crocodile",
		ModelNameVerified = true,
		LegacyId = "Bandito Bobrito",
	},

	{
		CrewMemberId = "Ember Fist",
		DisplayName = "Ember Fist",
		RealCharacterName = "Ace",
		Arc = "Water 7",
		Rarity = "Legendary",
		ModelName = "Ace",
		ModelNameVerified = true,
		LegacyId = "Frigo Camelo",
	},
	{
		CrewMemberId = "Leopard Agent",
		DisplayName = "Leopard Agent",
		RealCharacterName = "Rob Lucci",
		Arc = "Water 7",
		Rarity = "Legendary",
		ModelName = "Lucci",
		ModelNameVerified = true,
		LegacyId = "Rhino Toasterino",
	},
	{
		CrewMemberId = "Surgeon Rogue",
		DisplayName = "Surgeon Rogue",
		RealCharacterName = "Law",
		Arc = "Water 7",
		Rarity = "Legendary",
		ModelName = "Law",
		ModelNameVerified = true,
		LegacyId = "Madung",
	},
	{
		CrewMemberId = "Rubber Captain",
		DisplayName = "Rubber Captain",
		RealCharacterName = "Luffy",
		Arc = "Water 7",
		Rarity = "Legendary",
		ModelName = "Luffy",
		ModelNameVerified = true,
		LegacyId = "Garamararam",
	},

	{
		CrewMemberId = "Shadow Baron",
		DisplayName = "Shadow Baron",
		RealCharacterName = "Moria",
		Arc = "Thriller Bark",
		Rarity = "Mythic",
		ModelName = "Moria",
		ModelNameVerified = true,
		LegacyId = "Bombombini Gusini",
	},
	{
		CrewMemberId = "Ghost Samurai",
		DisplayName = "Ghost Samurai",
		RealCharacterName = "Ryuma",
		Arc = "Thriller Bark",
		Rarity = "Mythic",
		ModelName = "Ryuma",
		ModelNameVerified = true,
		LegacyId = "Bombardiro Crocodilo",
	},
	{
		CrewMemberId = "Venom Warden",
		DisplayName = "Venom Warden",
		RealCharacterName = "Magellan",
		Arc = "Thriller Bark",
		Rarity = "Mythic",
		ModelName = "Magellan",
		ModelNameVerified = true,
		LegacyId = "Elefanto Cocofanto",
	},
	{
		CrewMemberId = "Tide Monk",
		DisplayName = "Tide Monk",
		RealCharacterName = "Jimbe",
		Arc = "Thriller Bark",
		Rarity = "Mythic",
		ModelName = "Jimbei",
		ModelNameVerified = true,
		LegacyId = "Orangutini Ananassini",
	},

	{
		CrewMemberId = "Puppet King",
		DisplayName = "Puppet King",
		RealCharacterName = "Doflamingo",
		Arc = "Sabaody",
		Rarity = "Godly",
		ModelName = "Doflamingo",
		ModelNameVerified = true,
		LegacyId = "Agarrini La Pallini",
	},
	{
		CrewMemberId = "Candy Duke",
		DisplayName = "Candy Duke",
		RealCharacterName = "Perospero",
		Arc = "Sabaody",
		Rarity = "Godly",
		ModelName = "Persopero",
		ModelNameVerified = true,
		LegacyId = "Tralalero Tralala",
	},
	{
		CrewMemberId = "Juice Duchess",
		DisplayName = "Juice Duchess",
		RealCharacterName = "Smoothie",
		Arc = "Sabaody",
		Rarity = "Godly",
		ModelName = "Smoothie",
		ModelNameVerified = true,
		LegacyId = "La Vacca Saturno Saturnita",
	},
	{
		CrewMemberId = "Diamond Bruiser",
		DisplayName = "Diamond Bruiser",
		RealCharacterName = "Jozu",
		Arc = "Sabaody",
		Rarity = "Godly",
		ModelName = "Jozu",
		ModelNameVerified = true,
		LegacyId = "Girafa Celestre",
	},

	{
		CrewMemberId = "Azure Phoenix",
		DisplayName = "Azure Phoenix",
		RealCharacterName = "Marco",
		Arc = "Dressrosa",
		Rarity = "Secret",
		ModelName = "Marco",
		ModelNameVerified = true,
		LegacyId = "Chicleteira Bicicleteira",
	},
	{
		CrewMemberId = "Frost Admiral",
		DisplayName = "Frost Admiral",
		RealCharacterName = "Aokiji",
		Arc = "Dressrosa",
		Rarity = "Secret",
		ModelName = "Aokiji",
		ModelNameVerified = true,
		LegacyId = "Karkerkar Kurkur",
	},
	{
		CrewMemberId = "Hawkblade Lord",
		DisplayName = "Hawkblade Lord",
		RealCharacterName = "Mihawk",
		Arc = "Dressrosa",
		Rarity = "Secret",
		ModelName = "Mihawk",
		ModelNameVerified = true,
		LegacyId = "Job Job Job Sahur",
	},
	{
		CrewMemberId = "Plague Engineer",
		DisplayName = "Plague Engineer",
		RealCharacterName = "Queen",
		Arc = "Dressrosa",
		Rarity = "Secret",
		ModelName = "Queen",
		ModelNameVerified = true,
		LegacyId = "Esok Sekolah",
	},
}

local CREW_MEMBER_RENDER_PLACEHOLDER = "rbxasset://textures/ui/GuiImagePlaceholder.png"

-- TODO(CrewVisuals): Replace this placeholder with final CrewMember portrait assets.
-- The retired portrait table was copied from legacy storage entries and must not
-- be used as active CrewMember UI identity.
local function applyPlaceholderRenderAssets(entry)
	entry.Render = CREW_MEMBER_RENDER_PLACEHOLDER
	entry.GoldenRender = CREW_MEMBER_RENDER_PLACEHOLDER
	entry.DiamondRender = CREW_MEMBER_RENDER_PLACEHOLDER
	entry.RenderStatus = "NeedsCanonicalPortrait"
end

local balanceByCrewMemberId = {
	["Mask Dancer"] = { Income = 3, Chance = 90, TimeLeft = 30 },
	["Clown Captain"] = { Income = 5, Chance = 80, TimeLeft = 30 },
	["Metal Glutton"] = { Income = 7, Chance = 70, TimeLeft = 30 },
	["Pink Marine"] = { Income = 10, Chance = 60, TimeLeft = 30 },
	["Storm Cartographer"] = { Income = 12, Chance = 50, TimeLeft = 30 },
	["Iron Shipwright"] = { Income = 16, Chance = 40, TimeLeft = 30 },
	["Soul Fiddler"] = { Income = 22, Chance = 35, TimeLeft = 30 },
	["Sawtooth Captain"] = { Income = 28, Chance = 30, TimeLeft = 30 },
	["Straw Prophet"] = { Income = 35, Chance = 20, TimeLeft = 30 },
	["Dino Marine"] = { Income = 45, Chance = 10, TimeLeft = 30 },
	["Fortress Don"] = { Income = 60, Chance = 6, TimeLeft = 30 },
	["Bloom Scholar"] = { Income = 80, Chance = 4, TimeLeft = 30 },
	["Barrier Punk"] = { Income = 80, Chance = 1, TimeLeft = 30 },
	["Flint Kicker"] = { Income = 100, Chance = 0.5, TimeLeft = 30 },
	["Blade Ronin"] = { Income = 125, Chance = 0.3, TimeLeft = 30, IdleAnim = 118039584385174 },
	["Sand Tyrant"] = { Income = 150, Chance = 0.2, TimeLeft = 30, IdleAnim = 117547701048403 },
	["Ember Fist"] = { Income = 160, Chance = 0.08, TimeLeft = 30 },
	["Leopard Agent"] = { Income = 200, Chance = 0, TimeLeft = 30, IdleAnim = 127346267024570 },
	["Surgeon Rogue"] = { Income = 250, Chance = 0.06, TimeLeft = 30, IdleAnim = 94961421589870 },
	["Rubber Captain"] = { Income = 300, Chance = 0.04, TimeLeft = 30, IdleAnim = 133580320249648 },
	["Shadow Baron"] = { Income = 300, Chance = 0.008, TimeLeft = 30, IdleAnim = 107083179404237 },
	["Ghost Samurai"] = { Income = 425, Chance = 0.006, TimeLeft = 30, IdleAnim = 87293090021637 },
	["Venom Warden"] = { Income = 550, Chance = 0.004, TimeLeft = 30, IdleAnim = 74472556819311 },
	["Tide Monk"] = { Income = 700, Chance = 0.002, TimeLeft = 30, IdleAnim = 118452385523676 },
	["Puppet King"] = { Income = 800, Chance = 0.0008, TimeLeft = 30, IdleAnim = 136583127735891 },
	["Candy Duke"] = { Income = 1200, Chance = 0.0006, TimeLeft = 30, IdleAnim = 101871119253345 },
	["Juice Duchess"] = { Income = 1700, Chance = 0.0004, TimeLeft = 30, IdleAnim = 122355075926841 },
	["Diamond Bruiser"] = { Income = 2500, Chance = 0.0002, TimeLeft = 30, IdleAnim = 137649236058689 },
	["Azure Phoenix"] = { Income = 2500, Chance = 0.00008, TimeLeft = 30, IdleAnim = 92396455480331 },
	["Frost Admiral"] = { Income = 4000, Chance = 0.00006, TimeLeft = 30, IdleAnim = 133443053475641 },
	["Hawkblade Lord"] = { Income = 6000, Chance = 0.00004, TimeLeft = 30, IdleAnim = 127160575917998 },
	["Plague Engineer"] = { Income = 8000, Chance = 0.00002, TimeLeft = 30 },
}

local byCrewMemberId = {}
local byDisplayName = {}
local byLegacyId = {}
local byRealCharacterName = {}

for index, entry in ipairs(CrewMembers.Entries) do
	entry.Order = index
	applyPlaceholderRenderAssets(entry)
	local balance = balanceByCrewMemberId[tostring(entry.CrewMemberId)]
	if balance then
		entry.Income = balance.Income
		entry.Chance = balance.Chance
		entry.TimeLeft = balance.TimeLeft
		entry.IdleAnim = balance.IdleAnim
	end
	byCrewMemberId[tostring(entry.CrewMemberId)] = entry
	byDisplayName[tostring(entry.DisplayName)] = entry
	byLegacyId[tostring(entry.LegacyId)] = entry
	byRealCharacterName[tostring(entry.RealCharacterName)] = entry
end

local function cloneEntry(entry)
	return if entry then table.clone(entry) else nil
end

function CrewMembers.GetEntries()
	local entries = {}
	for index, entry in ipairs(CrewMembers.Entries) do
		entries[index] = table.clone(entry)
	end
	return entries
end

function CrewMembers.GetByCrewMemberId(crewMemberId)
	return cloneEntry(byCrewMemberId[tostring(crewMemberId or "")])
end

function CrewMembers.GetByDisplayName(displayName)
	return cloneEntry(byDisplayName[tostring(displayName or "")])
end

function CrewMembers.GetByLegacyId(legacyId)
	return cloneEntry(byLegacyId[tostring(legacyId or "")])
end

function CrewMembers.GetByRealCharacterName(realCharacterName)
	return cloneEntry(byRealCharacterName[tostring(realCharacterName or "")])
end

function CrewMembers.GetLegacyIdMappings()
	local mappings = {}
	for _, entry in ipairs(CrewMembers.Entries) do
		mappings[tostring(entry.LegacyId)] = {
			CrewMemberId = entry.CrewMemberId,
			DisplayName = entry.DisplayName,
			CrewMemberName = entry.DisplayName,
			RealCharacterName = entry.RealCharacterName,
			Arc = entry.Arc,
			Rarity = entry.Rarity,
			ModelName = entry.ModelName,
			ModelNameVerified = entry.ModelNameVerified == true,
			MissingModel = entry.MissingModel == true,
			Render = entry.Render,
			GoldenRender = entry.GoldenRender,
			DiamondRender = entry.DiamondRender,
			RenderStatus = entry.RenderStatus,
			Income = entry.Income,
			Chance = entry.Chance,
			TimeLeft = entry.TimeLeft,
			IdleAnim = entry.IdleAnim,
			Order = entry.Order,
		}
	end
	return mappings
end

return CrewMembers
