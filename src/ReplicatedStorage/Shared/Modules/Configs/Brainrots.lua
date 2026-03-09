
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Configs = ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Configs")
local VariantCfg = require(Configs:WaitForChild("BrainrotVariants"))

local Brainrots = {
	["Lirili Larila"] = {
		Income = 3,
		Chance = 90,
		Render = "rbxassetid://113359564101598",
		GoldenRender = "rbxassetid://127849691403975",
		DiamondRender = "rbxassetid://106911194271422",
		Rarity = "Common",
		TimeLeft = 30,
		IdleAnim = 81355594772429,
	},

	["Boneca Ambalabu"] = {
		Income = 5,
		Chance = 80,
		Render = "rbxassetid://134503604439304",
		GoldenRender = "rbxassetid://77917447336793",
		DiamondRender = "rbxassetid://138594877929939",
		Rarity = "Common",
		TimeLeft = 30,
		IdleAnim = 124667521402664,
	},

	["Tun Tun Sahur"] = {
		Income = 7,
		Chance = 70,
		Render = "rbxassetid://119707747274960",
		GoldenRender = "rbxassetid://112218277171505",
		DiamondRender = "rbxassetid://133744920704526",
		Rarity = "Common",
		TimeLeft = 30,
		IdleAnim = 90536498752484,
	},

	["Tim Cheese"] = {
		Income = 10,
		Chance = 60,
		Render = "rbxassetid://106164466952557",
		GoldenRender = "rbxassetid://137139986090836",
		DiamondRender = "rbxassetid://111507570681189",
		Rarity = "Common",
		TimeLeft = 30,
		IdleAnim = 121692489909418,
	},

	["Pipi Kiwi"] = {
		Income = 12,
		Chance = 55,
		Render = "rbxassetid://118716885310401",
		GoldenRender = "rbxassetid://110918948837746",
		DiamondRender = "rbxassetid://82129224962904",
		Rarity = "Common",
		TimeLeft = 30,
		IdleAnim = 101531100958187,
	},

	["Trulimero Trulicina"] = {
		Income = 15,
		Chance = 50,
		Render = "rbxassetid://81846076403042",
		GoldenRender = "rbxassetid://100457431166789",
		DiamondRender = "rbxassetid://140082227752846",
		Rarity = "Uncommon",
		TimeLeft = 30,
		IdleAnim = 107803805940614,
	},

	["Svinina Bombardino"] = {
		Income = 20,
		Chance = 40,
		Render = "rbxassetid://76807285357114",
		GoldenRender = "rbxassetid://123528379096154",
		DiamondRender = "rbxassetid://101161807977859",
		Rarity = "Uncommon",
		TimeLeft = 30,
		IdleAnim = 88464588642501,
	},

	["Gangster Footera"] = {
		Income = 25,
		Chance = 35,
		Render = "rbxassetid://82505170440216",
		GoldenRender = "rbxassetid://82045781617249",
		DiamondRender = "rbxassetid://116944449743705",
		Rarity = "Uncommon",
		TimeLeft = 30,
		IdleAnim = 136631925337185,
	},

	["Burbaloni Loliloli"] = {
		Income = 30,
		Chance = 30,
		Render = "rbxassetid://115680449428508",
		GoldenRender = "rbxassetid://138121629255718",
		DiamondRender = "rbxassetid://72209560185597",
		Rarity = "Uncommon",
		TimeLeft = 30,
		IdleAnim = 133787706688058,
	},

	["Trippi Troppi"] = {
		Income = 40,
		Chance = 25,
		Render = "rbxassetid://120167651348615",
		GoldenRender = "rbxassetid://119271151179142",
		DiamondRender = "rbxassetid://89065774149616",
		Rarity = "Uncommon",
		TimeLeft = 30,
		IdleAnim = 110853770469931,
	},

	["Pipi Potato"] = {
		Income = 50,
		Chance = 20,
		Render = "rbxassetid://85937549631628",
		GoldenRender = "rbxassetid://87413472638786",
		DiamondRender = "rbxassetid://132307117255416",
		Rarity = "Rare",
		TimeLeft = 30,
		IdleAnim = 135996778242052,
	},

	["Brr Brr Patapim"] = {
		Income = 65,
		Chance = 10,
		Render = "rbxassetid://83861648183356",
		GoldenRender = "rbxassetid://103156500072920",
		DiamondRender = "rbxassetid://121430162160287",
		Rarity = "Rare",
		TimeLeft = 30,
		IdleAnim = 108530253041260,
	},

	["Trippi Troppi Troppa Trippa"] = {
		Income = 75,
		Chance = 6,
		Render = "rbxassetid://137997941015143",
		GoldenRender = "rbxassetid://119230749493437",
		DiamondRender = "rbxassetid://106459496438102",
		Rarity = "Rare",
		TimeLeft = 30,
		IdleAnim = 109497771446379,
	},

	["Tatatata Sahur"] = {
		Income = 90,
		Chance = 4,
		Render = "rbxassetid://118611364659465",
		GoldenRender = "rbxassetid://105112399660731",
		DiamondRender = "rbxassetid://106532370053521",
		Rarity = "Rare",
		TimeLeft = 30,
		IdleAnim = 84372816639111,
	},

	["Balerina Capucina"] = {
		Income = 100,
		Chance = 2,
		Render = "rbxassetid://113452691198946",
		GoldenRender = "rbxassetid://84139465602810",
		DiamondRender = "rbxassetid://110834200561877",
		Rarity = "Rare",
		TimeLeft = 30,
		IdleAnim = 71272992279195,
	},

	["Cappuccino Assassino"] = {
		Income = 115,
		Chance = 1,
		Render = "rbxassetid://135359147722128",
		GoldenRender = "rbxassetid://132907471961427",
		DiamondRender = "rbxassetid://120234498876005",
		Rarity = "Epic",
		TimeLeft = 30,
		IdleAnim = 94395632772482,
	},

	["Chimpanzini Bananini"] = {
		Income = 135,
		Chance = .5,
		Render = "rbxassetid://99695290210184",
		GoldenRender = "rbxassetid://130846274532725",
		DiamondRender = "rbxassetid://79454672643438",
		Rarity = "Epic",
		TimeLeft = 30,
		IdleAnim = 123310159832096,
	},

	["Fluri Flura"] = {
		Income = 150,
		Chance = .3,
		Render = "rbxassetid://79454672643438",
		GoldenRender = "rbxassetid://74879169321056",
		DiamondRender = "rbxassetid://130846274532725",
		Rarity = "Epic",
		TimeLeft = 30,
		IdleAnim = 118039584385174,
	},

	["Bandito Bobrito"] = {
		Income = 175,
		Chance = .2,
		Render = "rbxassetid://129647247812910",
		GoldenRender = "rbxassetid://127947627017762",
		DiamondRender = "rbxassetid://82093530016130",
		Rarity = "Epic",
		TimeLeft = 30,
		IdleAnim = 117547701048403,
	},

	["Cacto Hipopotamo"] = {
		Income = 200,
		Chance = .1,
		Render = "rbxassetid://99254929230141",
		GoldenRender = "rbxassetid://95353382357108",
		DiamondRender = "rbxassetid://100509047066447",
		Rarity = "Epic",
		TimeLeft = 30,
		IdleAnim = 76932620078527,
	},

	["Frigo Camelo"] = {
		Income = 250,
		Chance = .08,
		Render = "rbxassetid://84916034746691",
		GoldenRender = "rbxassetid://83084181563201",
		DiamondRender = "rbxassetid://110365261580512",
		Rarity = "Legendary",
		TimeLeft = 30,
		IdleAnim = 74441559824851,
	},

	["Rhino Toasterino"] = {
		Income = 275,
		Chance = 0,
		Render = "rbxassetid://92244593874593",
		GoldenRender = "rbxassetid://97217210321370",
		DiamondRender = "rbxassetid://96114900929144",
		Rarity = "Legendary",
		TimeLeft = 30,
		IdleAnim = 127346267024570,
	},
	
	["Madung"] = {
		Income = 300,
		Chance = .06,
		Render = "rbxassetid://125533014184518",
		GoldenRender = "rbxassetid://135252803037006",
		DiamondRender = "rbxassetid://94785922253148",
		Rarity = "Legendary",
		TimeLeft = 30,
		IdleAnim = 94961421589870,
	},

	["Garamararam"] = {
		Income = 375,
		Chance = .04,
		Render = "rbxassetid://108703341949092",
		GoldenRender = "rbxassetid://124273331351420",
		DiamondRender = "rbxassetid://114997423483274",
		Rarity = "Legendary",
		TimeLeft = 30,
		IdleAnim = 133580320249648,
	},

	["Mateo"] = {
		Income = 450,
		Chance = .02,
		Render = "rbxassetid://140265986209493",
		GoldenRender = "rbxassetid://99255537031464",
		DiamondRender = "rbxassetid://99057092436221",
		Rarity = "Legendary",
		TimeLeft = 30,
		IdleAnim = 129228798313554,
	},

	["Odin Din Din Dun"] = {
		Income = 550,
		Chance = .01,
		Render = "rbxassetid://98768075657134",
		GoldenRender = "rbxassetid://86992492689934",
		DiamondRender = "rbxassetid://116278341568148",
		Rarity = "Legendary",
		TimeLeft = 30,
		IdleAnim = 100351929024911,
	},

	["Bombombini Gusini"] = {
		Income = 700,
		Chance = .008,
		Render = "rbxassetid://107435965140828",
		GoldenRender = "rbxassetid://86672178006180",
		DiamondRender = "rbxassetid://104932578691282",
		Rarity = "Mythic",
		TimeLeft = 30,
		IdleAnim = 107083179404237,
	},

	["Bombardiro Crocodilo"] = {
		Income = 850,
		Chance = 0.006,
		Render = "rbxassetid://108324428541699",
		GoldenRender = "rbxassetid://100929972400451",
		DiamondRender = "rbxassetid://136841298026755",
		Rarity = "Mythic",
		TimeLeft = 30,
		IdleAnim = 87293090021637,
	},

	["Elefanto Cocofanto"] = {
		Income = 1000,
		Chance = 0.004,
		Render = "rbxassetid://86909203109036",
		GoldenRender = "rbxassetid://108585961469642",
		DiamondRender = "rbxassetid://110057885067239",
		Rarity = "Mythic",
		TimeLeft = 30,
		IdleAnim = 74472556819311,
	},

	["Orangutini Ananassini"] = {
		Income = 1250,
		Chance = 0.002,
		Render = "rbxassetid://112159737210505",
		GoldenRender = "rbxassetid://96440504348209",
		DiamondRender = "rbxassetid://94070528536305",
		Rarity = "Mythic",
		TimeLeft = 30,
		IdleAnim = 118452385523676,
	},

	["Pandaccini Bananini"] = {
		Income = 1500,
		Chance = 0.001,
		Render = "rbxassetid://131613335203696",
		GoldenRender = "rbxassetid://110615700303995",
		DiamondRender = "rbxassetid://107914772044165",
		Rarity = "Mythic",
		TimeLeft = 30,
		IdleAnim = 107487395289679,
	},
	
	["Tirilikalika Tirilikalako"] = {
		Income = 1750,
		Chance = 0,
		Render = "rbxassetid://136792506025468",
		GoldenRender = "rbxassetid://108887125216794",
		DiamondRender = "rbxassetid://129104123866092",
		Rarity = "Mythic",
		TimeLeft = 30,
		IdleAnim = 107487395289679,
	},

	["Agarrini La Pallini"] = {
		Income = 2000,
		Chance = 0.0008,
		Render = "rbxassetid://91289329731476",
		GoldenRender = "rbxassetid://126050999350639",
		DiamondRender = "rbxassetid://77959523881137",
		Rarity = "Godly",
		TimeLeft = 30,
		IdleAnim = 136583127735891,
	},

	["Tralalero Tralala"] = {
		Income = 3000,
		Chance = 0.0006,
		Render = "rbxassetid://71779364798595",
		GoldenRender = "rbxassetid://133113791623036",
		DiamondRender = "rbxassetid://71183543987473",
		Rarity = "Godly",
		TimeLeft = 30,
		IdleAnim = 101871119253345,
	},

	["La Vacca Saturno Saturnita"] = {
		Income = 4500,
		Chance = 0.0004,
		Render = "rbxassetid://89671349580383",
		GoldenRender = "rbxassetid://78817828402627",
		DiamondRender = "rbxassetid://134526117508604",
		Rarity = "Godly",
		TimeLeft = 30,
		IdleAnim = 122355075926841,
	},

	["Girafa Celestre"] = {
		Income = 6000,
		Chance = 0.0002,
		Render = "rbxassetid://103885571542512",
		GoldenRender = "rbxassetid://109499101905662",
		DiamondRender = "rbxassetid://101839579355541",
		Rarity = "Godly",
		TimeLeft = 30,
		IdleAnim = 137649236058689,
	},

	["Balerino Lololo"] = {
		Income = 8000,
		Chance = 0.0001,
		Render = "rbxassetid://117458660073799",
		GoldenRender = "rbxassetid://85955897226432",
		DiamondRender = "rbxassetid://137454072402550",
		Rarity = "Godly",
		TimeLeft = 30,
		IdleAnim = 116059065001662,
	},

	["Chicleteira Bicicleteira"] = {
		Income = 10000,
		Chance = 0.00008,
		Render = "rbxassetid://118835152678916",
		GoldenRender = "rbxassetid://110260216608540",
		DiamondRender = "rbxassetid://93181390663953",
		Rarity = "Secret",
		TimeLeft = 30,
		IdleAnim = 92396455480331,
	},

	["Karkerkar Kurkur"] = {
		Income = 17500,
		Chance = 0.00006,
		Render = "rbxassetid://91270417698202",
		GoldenRender = "rbxassetid://88525353243901",
		DiamondRender = "rbxassetid://123211873982447",
		Rarity = "Secret",
		TimeLeft = 30,
		IdleAnim = 133443053475641,
	},

	["Job Job Job Sahur"] = {
		Income = 25000,
		Chance = 0.00004,
		Render = "rbxassetid://72005639048029",
		GoldenRender = "rbxassetid://97923090745093",
		DiamondRender = "rbxassetid://87561083239103",
		Rarity = "Secret",
		TimeLeft = 30,
		IdleAnim = 127160575917998,
	},

	["Esok Sekolah"] = {
		Income = 35000,
		Chance = 0.00002,
		Render = "rbxassetid://86150342413370",
		GoldenRender = "rbxassetid://121799955223138",
		DiamondRender = "rbxassetid://88041363117409",
		Rarity = "Secret",
		TimeLeft = 30,
		IdleAnim = 136874323814262,
	},

	["67"] = {
		Income = 50000,
		Chance = 0.00001,
		Render = "rbxassetid://105758401535541",
		GoldenRender = "rbxassetid://106470395784924",
		DiamondRender = "rbxassetid://83375715484261",
		Rarity = "Secret",
		TimeLeft = 30,
		IdleAnim = 83385351136928,
	},
	
	["Pakrahmatmatina"] = {
		Income = 60000,
		Chance = 0,
		Render = "rbxassetid://128133062366102",
		GoldenRender = "rbxassetid://92198224071156",
		DiamondRender = "rbxassetid://73737191215593",
		Rarity = "Secret",
		TimeLeft = 30,
		IdleAnim = 114236988459381,
	},

	["Pot Hotspot"] = {
		Income = 75000,
		Chance = 0,
		Render = "rbxassetid://104255768072595",
		GoldenRender = "rbxassetid://130775457750560",
		DiamondRender = "rbxassetid://130775457750560",
		Rarity = "Secret",
		TimeLeft = 30,
		IdleAnim = 75833323913041,
	},
	
	["Dragon Cannelloni"] = {
		Income = 250000,
		Chance = 0.0000002,
		Render = "rbxassetid://120758817583025",
		GoldenRender = "rbxassetid://109633755477038",
		DiamondRender = "rbxassetid://103587577672648",
		Rarity = "Omega",
		TimeLeft = 30,
		IdleAnim = 128154830648014,
	},
}

for id, info in pairs(Brainrots) do
	if type(info) == "table" and not info.IsVariant then
		info.GoldenRender = info.GoldenRender or info.Render
		info.DiamondRender = info.DiamondRender or info.Render
	end
end

local function shallowCopy(t)
	local c = {}
	for k, v in pairs(t) do
		c[k] = v
	end
	return c
end

local baseIds = {}
for id, info in pairs(Brainrots) do
	if type(info) == "table" and not info.IsVariant then
		table.insert(baseIds, id)
	end
end

for _, variantKey in ipairs(VariantCfg.Order or {}) do
	if variantKey ~= "Normal" then
		local v = (VariantCfg.Versions or {})[variantKey]
		if v then
			local prefix = tostring(v.Prefix or (variantKey .. " "))
			local mult = tonumber(v.IncomeMult) or 1

			for _, baseId in ipairs(baseIds) do
				local baseInfo = Brainrots[baseId]
				if baseInfo and type(baseInfo) == "table" then
					local newId = prefix .. baseId
					if Brainrots[newId] == nil then
						local newInfo = shallowCopy(baseInfo)
						newInfo.IsVariant = true
						newInfo.BaseId = baseId
						newInfo.Variant = variantKey
						newInfo.DisplayName = newId

						local income = tonumber(baseInfo.Income) or 0
						newInfo.Income = math.floor(income * mult + 0.5)

						if variantKey == "Golden" then
							newInfo.Render = baseInfo.GoldenRender or baseInfo.Render
						elseif variantKey == "Diamond" then
							newInfo.Render = baseInfo.DiamondRender or baseInfo.Render
						end

						Brainrots[newId] = newInfo
					end
				end
			end
		end
	end
end

return Brainrots
