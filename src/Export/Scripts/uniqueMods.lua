if not table.containsId then
	dofile("Scripts/mods.lua")
end

LoadModule("../Data/Global.lua")
local catalystTags = {
	["attack"] = true,
	["speed"] = true,
	["life"] = true,
	["mana"] = true,
	["resource"] = true,
	["caster"] = true,
	["attribute"] = true,
	["physical"] = true,
	["chaos"] = true,
	["resistance"] = true,
	["defences"] = true,
	["elemental_damage"] = true,
	["critical"] = true,
}

local function findMod(possibleMods, name)
	local gggMod
	if possibleMods then
		gggMod = possibleMods[1]
		for _, modName in ipairs(possibleMods) do
			if modName:lower():match(name) then
				gggMod = modName
			end
		end
		return gggMod
	end
end

local modTextMap = LoadModule("../Data/Uniques/Special/ModTextMap.lua")
local uniqueMods = LoadModule("../Data/Uniques/Special/Uniques.lua")
for _, name in pairs({ "body" }) do
	local uniques = LoadModule("../Data/Uniques/"..name..".lua")
	local uniquesSpecial = LoadModule("../Data/Uniques/Special/"..name..".lua") or {}
	local specialOut = io.open("../Data/Uniques/Special/"..name..".lua", "w")
	local uniqueOut = io.open("../Data/Uniques/"..name..".lua", "w")
	-- Construct special unique table
	local newUniquesSpecial = {}
	for _, uniqueText in ipairs(uniques) do
		local lineCount = 1
		local uniqueName
		for line in uniqueText:gmatch("[^\r\n]+") do
			if line ~= "[[" and line ~= "]]" then
				if lineCount == 1 then
					uniqueName = line
					newUniquesSpecial[uniqueName] = {}
					newUniquesSpecial[uniqueName][lineCount] = { line = line, modText = line }
				else
					local variants = line:match("{[vV]ariant:([%d,]+)}")
					local fractured = line:match("({fractured})") or ""
					local modText = line:gsub("{.+}", ""):gsub("{.+}", "")
					newUniquesSpecial[uniqueName][lineCount] = { line = line, modText = modText, variants = variants, fractured = fractured }
				end
				lineCount = lineCount + 1
			end
		end
		newUniquesSpecial[uniqueName].length = lineCount
	end

	-- Compare new unique table to other special one
	for uniqueName, unique in pairs(newUniquesSpecial) do
		if uniquesSpecial[uniqueName] and uniquesSpecial[uniqueName].length == unique.length then
			for lineNo, lineTable in pairs(unique) do
				if uniqueMods[uniquesSpecial[uniqueName][lineNo].modName][1] == lineTable.modText then
					-- We're good, they still match!
				else
					-- This doesn't handle reordering of the lines

					-- Did the mod value change?  Update the text
					local foundMod = false
					for _, modName in ipairs(ModTextMap[lineTable.modText]) do
						if modName == uniquesSpecial[uniqueName][lineNo].modName then
							foundMod = true
							lineTable.modName = modName
							lineTable.modText = uniqueMods[uniquesSpecial[uniqueName][lineNo].modName][1]
						end
					end
					-- new mod, need to find it again
					if not foundMod then
						lineTable.modName = findMod(ModTextMap[lineTable.modText], name)
					end
				end
			end
		elseif uniquesSpecial[uniqueName] and uniquesSpecial[uniqueName].length > unique.length then
			-- mod removed, unlikely, but possible
		elseif uniquesSpecial[uniqueName] and uniquesSpecial[uniqueName].length < unique.length then
			-- Added new lines/variants
		else
			-- new unique, find and add all mods
			for lineNo, lineTable in ipairs(unique) do
				lineTable.modName = findMod(modTextMap[lineTable.modText], name)
			end
		end
	end

	-- Print mods to both locations
	specialOut:write("return {\n")
	uniqueOut:write("return {\n")

	local newUniquesSpecialSorted = {}
	for uniqueName in pairs(newUniquesSpecial) do
		table.insert(newUniquesSpecialSorted, uniqueName)
	end
	table.sort(newUniquesSpecialSorted)
	for _, uniqueName in pairs(newUniquesSpecialSorted) do
		local unique = newUniquesSpecial[uniqueName]
		specialOut:write("\t[\""..uniqueName.."\"] = {\n")
		specialOut:write("\t\tlength = " .. tostring(unique.length) .. ",\n")
		uniqueOut:write("[[\n")
		for lineNo, uniqueLineTable in ipairs(unique) do
			specialOut:write("\t\t[" .. lineNo .. "] = { modText = \"" .. uniqueLineTable.modText .. "\", variants = \"" .. (uniqueLineTable.variants or "nil") .. "\", fractured = \"" .. (uniqueLineTable.fractured or "") .. "\", modName = \"" .. (uniqueLineTable.modName or "") .. "\" },\n")
			uniqueOut:write(uniqueLineTable.fractured or "")
			if uniqueLineTable.variants then
				uniqueOut:write("{variant:" .. uniqueLineTable.variants .. "}")
			end
			local tags = {}
			if isValueInArray({"belt", "amulet", "ring"}, name) then
				for _, tag in ipairs(uniqueMods[uniqueLineTable.modName].modTags) do
					if catalystTags[tag] then
						table.insert(tags, tag)
					end
				end
			end
			if tags[1] then
				uniqueOut:write("{tags:" .. table.concat(tags, ",") .. "}")
			end
			uniqueOut:write(uniqueLineTable.modText, "\n")
		end
		specialOut:write("\t},\n")
		uniqueOut:write("]],")
	end
	specialOut:write("}")
	uniqueOut:write("}")

--[[	for line in io.lines("../Data/Uniques/"..name..".lua") do
		local specName, specVal = line:match("^([%a ]+): (.+)$")
		if not specName and line ~= "]]--[[,[[" then
			local variants = line:match("{[vV]ariant:([%d,]+)}")
			local fractured = line:match("({fractured})") or ""
			local modText = line:gsub("{.+}", ""):gsub("{.+}", "")
			local possibleMods = modTextMap[modText]
			local gggMod
			if possibleMods then
				gggMod = possibleMods[1]
				for _, modName in ipairs(possibleMods) do
					if modName:lower():match(name) then
						gggMod = modName
					end
				end
				out:write(fractured)
				if variants then
					out:write("{variant:" .. variants .. "}")
				end
				out:write(gggMod, "\n")
			else
				out:write(line, "\n")
			end
		else
			out:write(line, "\n")
		end
	end]]
	specialOut:close()
	uniqueOut:close()
end

print("Unique mods exported.")
