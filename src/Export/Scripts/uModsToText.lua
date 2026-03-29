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

-- local shadowOut = {}

-- function shadowOut:Init(filename, mode)
-- 	self.out = io.open(filename, mode)
-- 	self.numFoulbornVariants = 0
-- 	self.foulbornVariantTbl = { }
-- end

-- function shadowOut:write(...)
-- 	for idx = 1, self.numFoulbornVariants do
-- 		table.insert(self.foulbornVariantTbl[idx], ...)
-- 	end
-- 	self.out:write(...)
-- end

-- function shadowOut:flush()

-- end

-- function shadowOut:close()
-- 	self.out:close()
-- end



for _, name in ipairs(itemTypes) do
	local out = io.open("../Data/Uniques/"..name..".lua", "w")
	local statOrder = {}
	local postModLines = {}
	local modLines = 0
	local implicits
	local uniqueName
	local numFoulbornVariants = 0
	local nextOrder = 100000
	for line in io.lines("Uniques/"..name..".lua") do
		if implicits then -- remove 1 downs to 0
			implicits = implicits - 1
		end
		local specName, specVal = line:match("^([%a ]+): (.+)$")
		if line:match("]],") then -- start new unique
			writeMods(out, statOrder)
			for _, line in ipairs(postModLines) do
				out:write(line, "\n")
			end
			out:write(line, "\n")
			uniqueName = nil
			numFoulbornVariants = 0
			statOrder = { }
			postModLines = { }
			modLines = 0
			nextOrder = 100000
		elseif not specName then
			if uniqueName == nil then
				uniqueName = line:match('(.+)')
				numFoulbornVariants = foulbornMap[uniqueName] and #foulbornMap[uniqueName] or 0
			end
			local prefix = ""
			local variantString = line:match("({variant:[%d,]+})")
			local fractured = line:match("({fractured})") or ""
			local modName, legacy = line:gsub("{.+}", ""):match("^([%a%d_]+)([%[%]-,%d]*)")
			local mod = uniqueMods[modName] or modVeiled[modName]
			if mod then
				modLines = modLines + 1
				for i = 1, numFoulbornVariants do
					local variant = foulbornMap[uniqueName][i]
					local isModInVariant = variant.explicits["explicit.stat_" .. mod.tradeHash]
					if not isModInVariant then
						mod = foulbornMods[variant.mutated]
						break
					end
				end
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
				for i, line in ipairs(legacyMod or mod) do
					local order = math.floor(mod.statOrder[i])
					if statOrder[order] then
						table.insert(statOrder[order], prefix..line)
					else
						statOrder[order] = { prefix..line }
					end
				end
			else
				if modLines > 0 or implicits then -- treat as post line e.g. mirrored, or unresolved text mod
					table.insert(postModLines, line)
				else
					out:write(line, "\n")
				end
			end
		else -- spec line
			if specName == "Implicits" then
				implicits = tonumber(specVal)
			else
				out:write(line, "\n")
			end
		end
		if implicits and implicits == 0 then
			local lines = 0
			for _, l in pairs(statOrder) do
				lines = lines + #l
			end
			out:write("Implicits: "..lines, "\n")
			writeMods(out, statOrder)
			implicits = nil
			statOrder = { }
			modLines = 0
		end
	end
	out:close()
end

print("Unique text updated.")
