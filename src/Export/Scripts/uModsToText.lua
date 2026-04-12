if not table.containsId then
	dofile("Scripts/mods.lua")
end
local catalystTags = {
	["elemental_damage"] = true,
	["caster"] = true,
	["attack"] = true,
	["defences"] = true,
	["resource"] = true,
	["resistance"] = true,
	["attribute"] = true,
	["physical_damage"] = true,
	["chaos_damage"] = true,
	["speed"] = true,
	["critical"] = true,
}
local itemTypes = {
	"axe",
	"bow",
	"claw",
	"dagger",
	"fishing",
	"mace",
	"staff",
	"sword",
	"wand",
	"helmet",
	"body",
	"gloves",
	"boots",
	"shield",
	"quiver",
	"amulet",
	"ring",
	"belt",
	"jewel",
	"flask",
	"tincture",
}
local function writeMods(out, statOrder)
	local orders = { }
	for order, _ in pairs(statOrder) do
		table.insert(orders, order)
	end
	table.sort(orders)
	for _, order in pairs(orders) do
		for _, line in ipairs(statOrder[order]) do
			out:write(line, "\n")
		end
	end
end

local uniqueMods = LoadModule("../Data/ModItemExclusive.lua")
local modVeiled = LoadModule("../Data/ModVeiled.lua")
local foulbornMap = LoadModule("../Data/ModFoulbornMap2.lua")
local foulbornMods = LoadModule("../Data/ModFoulborn.lua")


local function writeUniqueVariant(out, preModLines, modDataList, postModLines, variantIndex, uniqueName, numFoulbornVariants)
	-- Write pre-mod lines
	for _, line in ipairs(preModLines) do
		out:write(line, "\n")
	end
	
	-- Process and write mods for this variant
	local variantStatOrder = {}
	for _, modData in ipairs(modDataList) do
		local prefix = modData.prefix
		local mod = modData.mod
		local modName = modData.modName
		local legacyMod = modData.legacyMod
		
		-- Check if this mod needs replacement for this variant
		if numFoulbornVariants > 0 and variantIndex > 0 and variantIndex <= numFoulbornVariants then
			local variant = foulbornMap["Foulborn " ..uniqueName][variantIndex]
			local isModInVariant = variant.explicits["explicit.stat_" .. mod.tradeHash]
			if not isModInVariant then
				mod = foulbornMods[variant.mutated]
			end
		end
		
		-- Add mod lines with prefix
		for i, line in ipairs(legacyMod or mod) do
			local order = math.floor(mod.statOrder[i])
			if not variantStatOrder[order] then
				variantStatOrder[order] = {}
			end
			table.insert(variantStatOrder[order], prefix..line)
		end
	end
	
	writeMods(out, variantStatOrder)
	
	-- Write post-mod lines
	for _, line in ipairs(postModLines) do
		out:write(line, "\n")
	end
end

for _, name in ipairs(itemTypes) do
	local out = io.open("../Data/Uniques/"..name..".lua", "w")
	local modDataList = {}
	local postModLines = {}
	local preModLines = {}
	local modLines = 0
	local implicits
	local uniqueName
	local numFoulbornVariants = 0
	local nextOrder = 100000
	local inMods = false
	for line in io.lines("Uniques/"..name..".lua") do
		if implicits then -- remove 1 downs to 0
			implicits = implicits - 1
		end
		local specName, specVal = line:match("^([%a ]+): (.+)$")
		if line:match("]],") then -- start new unique
			-- Write all variants of the current unique
			writeUniqueVariant(out, preModLines, modDataList, postModLines, 0, uniqueName, 0)
			for i = 1, numFoulbornVariants do
				writeUniqueVariant(out, preModLines, modDataList, postModLines, i, uniqueName, numFoulbornVariants)
			end
			out:write(line, "\n")
			uniqueName = nil
			numFoulbornVariants = 0
			modDataList = {}
			postModLines = {}
			preModLines = {}
			modLines = 0
			inMods = false
			nextOrder = 100000
		elseif not specName then
			if uniqueName == nil then
				uniqueName = line:match('(.+)')
				numFoulbornVariants = foulbornMap["Foulborn " .. uniqueName] and #foulbornMap["Foulborn " .. uniqueName] or 0
			end
			local prefix = ""
			local variantString = line:match("({variant:[%d,]+})")
			local fractured = line:match("({fractured})") or ""
			local modName, legacy = line:gsub("{.+}", ""):match("^([%a%d_]+)([%[%]-,%d]*)")
			local mod = uniqueMods[modName] or modVeiled[modName]
			if mod then
				modLines = modLines + 1
				inMods = true
				
				if variantString then
					prefix = prefix ..variantString
				end

				local tags = {}
				if isValueInArray({"amulet", "ring", "belt"}, name) then
					for _, tag in ipairs(mod.modTags) do
						if catalystTags[tag] then
							table.insert(tags, tag)
						end
					end
				end
				if tags[1] then
					prefix = prefix.."{tags:"..table.concat(tags, ",").."}"
				end
				prefix = prefix..fractured
				local legacyMod
				if legacy ~= "" then
					local values = { }
					for range in legacy:gmatch("%b[]") do
						local min, max = range:match("%[([%d%.%-]+),([%d%.%-]+)%]")
						table.insert(values, { min = tonumber(min), max = tonumber(max) })
					end
					local mod = dat("Mods"):GetRow("Id", modName)
					if mod then
						local stats = { }
						for i = 1, 6 do
							if mod["Stat"..i] then
								stats[mod["Stat"..i].Id] = values[i]
							end
						end
						if mod.Type then
							stats.Type = mod.Type
						end
						legacyMod = describeStats(stats)
					else
						ConPrintf("Warning: Could not find mod data for legacy mod '%s' in %s", modName, name)
					end
				end
				
				-- Store mod data for later processing
				table.insert(modDataList, {
					prefix = prefix,
					mod = mod,
					modName = modName,
					legacyMod = legacyMod
				})
			else
				if modLines > 0 or implicits or inMods then -- treat as post line e.g. mirrored, or unresolved text mod
					table.insert(postModLines, line)
				else
					table.insert(preModLines, line)
				end
			end
		else -- spec line
			if specName == "Implicits" then
				implicits = tonumber(specVal)
			else
				if modLines > 0 or inMods then
					table.insert(postModLines, line)
				else
					table.insert(preModLines, line)
				end
			end
		end
		if implicits and implicits == 0 then
			local lines = 0
			for _, modData in ipairs(modDataList) do
				lines = lines + #(modData.legacyMod or modData.mod)
			end
			table.insert(preModLines, "Implicits: "..lines)
			-- Move modDataList to a separate implicits section
			writeUniqueVariant(out, preModLines, modDataList, {}, 0, uniqueName, 0)
			for i = 1, numFoulbornVariants do
				writeUniqueVariant(out, preModLines, modDataList, {}, i, uniqueName, numFoulbornVariants)
			end
			implicits = nil
			preModLines = {}
			modDataList = {}
			modLines = 0
			inMods = false
		end
	end
	out:close()
end

print("Unique text updated.")
