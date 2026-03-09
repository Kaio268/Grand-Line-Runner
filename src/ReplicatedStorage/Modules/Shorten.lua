local MoneyLib = {}

MoneyLib.Suffixes = {"K", "M", "B", "T", "Qd", "Qn", "Sx", "Sp", "Oc", "No", "De", "UDe", "DDe", "TDe", "QtDe", "QnDe", "SxDe", "SpDe", "OcDe", "NoDe", "Vg", "UVg", "DVg", "TVg", "QtVg", "QnVg", "SxVg", "SpVg", "OcVg", "NoVg", "Tg", "UTg", "DTg", "TTg", "QdTg", "QnTg", "SxTg", "SpTg", "OcTg", "NoTg", "qg", "Uqg", "Dqg", "Tqg", "Qdqg", "Qnqg", "Sxqg", "Spqg", "Ocqg", "Noqg", "Qg", "UQg", "DQg", "TQg", "QdQg", "QnQg", "SxQg", "SpQg", "OcQg", "NoQg", "sg", "Usg", "Dsg", "Tsg", "Qdsg", "Qnsg", "Sxsg", "Spsg", "Ocsg", "Nosg", "Sg", "USg", "DSg", "TSg", "QdSg", "QnSg", "SxSg", "SpSg", "OcSg", "NoSg", "Og", "UOg", "DOg", "TOg", "QdOg", "QnOg", "SxOg", "SpOg", "OcOg", "NoOg", "Ng", "UNg", "DNg", "TNg", "QdNg", "QnNg", "SxNg", "SpNg", "OcNg", "NoNg", "Ce", 
}                       

local function shorten(Input)
	local Negative = Input < 0
	Input = math.abs(Input)

	local Paired = false
	for i,v in pairs(MoneyLib.Suffixes) do
		if not (Input >= 10^(3*i)) then
			Input = Input / 10^(3*(i-1))
			local isComplex = (string.find(tostring(Input),".") and string.sub(tostring(Input),4,4) ~= ".")
			Input = string.sub(tostring(Input),1,(isComplex and 4) or 3) .. (MoneyLib.Suffixes[i-1] or "")
			Paired = true
			break
		end
	end
	if not Paired then
		local Rounded = math.floor(Input)
		Input = tostring(Rounded)
	end

	if Negative then
		return "-"..Input
	end
	return Input
end

MoneyLib.timeSuffix = function(n)
	local years   = math.floor(n / 31536000)
	local days    = math.floor((n % 31536000) / 86400)
	local hours   = math.floor((n % 86400) / 3600)
	local minutes = math.floor(n / 60 % 60)
	local seconds = math.floor(n % 60)

	if n >= 31536000 then
		return ("%2iY"):format(years)

	elseif n >= 86400 then
		return ("%iD %02iH %02iM"):format(days, hours, minutes)

	else
		return ("%02i:%02i:%02i"):format(hours, minutes, seconds)
	end
end

MoneyLib.timeSuffixTwo = function(n: number)
	local minutes = math.floor(n/60%60)
	local seconds = math.floor(n%60)

	if n < 86400 then
		return ("%02i:%02i"):format(minutes,seconds)
	end
end

MoneyLib.timeSuffix3 = function(n)
	local YEAR    = 31536000
	local DAY     = 86400
	local HOUR    = 3600

	local function pluralWord(count, singular, plural)
		if count == 1 then
			return singular
		else
			return plural or (singular .. "")
		end
	end

	if n >= YEAR then
		local years = math.floor(n / YEAR)

		if years < 10 then
			return years .. " " .. pluralWord(years, "year")
		elseif years < 100 then
			local dec = math.floor(years / 10)
			return dec .. " " .. pluralWord(dec, "decade")
		elseif years < 1000 then
			local cen = math.floor(years / 100)
			return cen .. " " .. pluralWord(cen, "century", "centuries")
		else
			local mil = math.floor(years / 1000)
			return mil .. " " .. pluralWord(mil, "millennium", "millennia")
		end

	else
		local days = math.floor(n / DAY)
		if days > 0 then
			local hours = math.floor((n % DAY) / HOUR)
			return days .. " " .. pluralWord(days, "d") .. " " ..
				hours .. " " .. pluralWord(hours, "h")
		else
			local hours   = math.floor(n / HOUR)
			local minutes = math.floor((n % HOUR) / 60)
			local seconds = math.floor(n % 60)
			local parts = {}

			if hours > 0 then
				table.insert(parts, hours .. " " .. pluralWord(hours, "h"))
			end
			if minutes > 0 then
				table.insert(parts, minutes .. " " .. pluralWord(minutes, "m"))
			end
			if seconds > 0 or #parts == 0 then
				table.insert(parts, seconds .. " " .. pluralWord(seconds, "s"))
			end

			return table.concat(parts, " ")
		end
	end
end

MoneyLib.roundNumber = function(Input)
	if Input == nil then
		return "0"
	end
	local Negative = Input < 0
	if Negative then
		return shorten(math.abs(Input))
	end 
	return shorten(Input)    
end

MoneyLib.withCommas = function(n)
	if type(n) == "number" and math.abs(n) >= 1e9 then
		return MoneyLib.roundNumber(n)
	end

	local s = tostring(n)
	local sign, int, frac = s:match("^(-?)(%d+)(%.%d+)?$")
	if not int then return tostring(n) end

	int = int:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	int = int:gsub("^,", "")

	return sign .. int .. (frac or "")
end


return MoneyLib
