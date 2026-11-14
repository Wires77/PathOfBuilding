-- Resolve plain copied values only when the complete affix assignment is unique.
local I={}
function I.inferRange(template,line)
	local pattern,ranges,at="",{},1
	local function escape(text) return text:gsub("([^%w])","%%%1") end
	for first,low,high,last in template:gmatch("()%((%-?%d+%.?%d*)%-(%-?%d+%.?%d*)%)()") do
		pattern=pattern..escape(template:sub(at,first-1)).."(%-?%d+%.?%d*)";at=last;ranges[#ranges+1]={tonumber(low),tonumber(high)}
	end
	pattern="^"..pattern..escape(template:sub(at)).."$"
	if #ranges == 0 then return template == line and {} or nil end
	local values={line:match(pattern)};if #values ~= #ranges then return nil end
	local result={}
	for i,bounds in ipairs(ranges) do
		local value=tonumber(values[i]);local low,high=math.min(unpack(bounds)),math.max(unpack(bounds))
		if not value or value < low or value > high then return nil end
		result[i]=bounds[1] == bounds[2] and 0.5 or (value-bounds[1])/(bounds[2]-bounds[1])
	end
	return result
end
function I.resolve(M,model,state)
	local rows={}
	for _,line in ipairs(model.item.explicitModLines) do rows[#rows+1]={text=itemLib.applyRange(line.line,line.range or 0.5),crafted=line.crafted or false,fractured=line.fractured or false,prefix=line.prefix,suffix=line.suffix} end
	local used={}
	for _,entry in ipairs(state.affixes) do for _,text in ipairs(M.rolledLines(M.entryMod(model,entry),entry.range)) do
		local found
		for i,row in ipairs(rows) do if not used[i] and row.text == text and row.crafted == (entry.crafted or false) and row.fractured == (entry.fractured or false) then found=i;break end end
		assert(found,"A native modifier identity does not match the imported values")
		used[found]=true
	end end
	local candidates,seen={},{ }
	local function consider(id,crafted,legacy,description330)
		local key=id..(legacy and ":legacy" or description330 and ":description330" or ":current");if seen[key] then return end;seen[key]=true
		local mod=legacy and model.legacyLightRadius[id] or description330 and model.descriptions330[id] or model.byId[id];if not mod or #mod == 0 then return end
		local indices,ranges,fractured={},{},nil
		for _,template in ipairs(mod) do
			local found,values
			for i,row in ipairs(rows) do if not used[i] and row.crafted == crafted and (fractured == nil or fractured == row.fractured) and (not row.prefix or mod.type == "Prefix") and (not row.suffix or mod.type == "Suffix") then
				local already=false;for _,index in ipairs(indices) do if index == i then already=true end end
				local inferred=not already and I.inferRange(template,row.text)
				if inferred then
					found,values=i,inferred;break
				end
			end end
			if not found then return end
			indices[#indices+1]=found;fractured=rows[found].fractured
			for _,value in ipairs(values) do ranges[#ranges+1]=value end
		end
		if legacy then for _,candidate in ipairs(candidates) do if candidate.entry.id==id and not candidate.entry.legacyLightRadius and table.concat(candidate.indices,",")==table.concat(indices,",") then return end end end
		candidates[#candidates+1]={indices=indices,entry={id=id,range=#ranges == 0 and 0.5 or #ranges == 1 and ranges[1] or ranges,crafted=crafted or nil,fractured=fractured or nil,legacyLightRadius=legacy or nil,description330=description330 or nil}}
	end
	for _,entry in ipairs(model.mods) do consider(entry.id,false) end
	for id in pairs(model.legacyAbyss or {}) do consider(id,false) end
	for id in pairs(model.unveiledJewels or {}) do consider(id,false) end
	for _,entry in ipairs(model.mods) do if model.legacyLightRadius[entry.id] then consider(entry.id,false,true) end end
	for _,entry in ipairs(model.essences) do consider(entry.modId,false) end
	for _,entry in ipairs(model.essences) do if model.descriptions330[entry.modId] then consider(entry.modId,false,false,true) end end
	for _,entry in ipairs(model.bench) do consider(entry.id,true) end
	for _,list in ipairs({data.veiledMods,data.beastCraft}) do for id,mod in pairs(list) do
		if (mod.type == "Prefix" or mod.type == "Suffix") and mod.level <= model.item.itemLevel and model.item:GetModSpawnWeight(mod) > 0 then model.byId[id]=mod;consider(id,false) end
	end end
	local metadata=require("Modules.CraftingAdvanced").data().mods
	local function groups(id) return metadata[id] and metadata[id].groups or {model.byId[id].group} end
	local occupied,counts={},{Prefix=0,Suffix=0}
	for _,entry in ipairs(state.affixes) do counts[model.byId[entry.id].type]=counts[model.byId[entry.id].type]+1;for _,group in ipairs(groups(entry.id)) do occupied[group]=true end end
	local caps=M.capacities(model,state);local selected,solutions={},{};local visits=0
	local function search()
		visits=visits+1;assert(visits <= 10000,"Import has too many ambiguous modifier assignments; use advanced copy text")
		if #solutions > 1 then return end
		local first;for i=1,#rows do if not used[i] then first=i;break end end
		if not first then solutions[#solutions+1]=copyTable(selected);return end
		for _,candidate in ipairs(candidates) do
			local contains,legal=false,true;local entry=candidate.entry;local kind=model.byId[entry.id].type
			for _,i in ipairs(candidate.indices) do if used[i] then legal=false end;if i == first then contains=true end end
			if counts[kind] >= caps[kind] then legal=false end
			for _,group in ipairs(groups(entry.id)) do if occupied[group] then legal=false end end
			if contains and legal then
				for _,i in ipairs(candidate.indices) do used[i]=true end
				for _,group in ipairs(groups(entry.id)) do occupied[group]=true end
				counts[kind]=counts[kind]+1;selected[#selected+1]=entry
				search()
				table.remove(selected);counts[kind]=counts[kind]-1
				for _,group in ipairs(groups(entry.id)) do occupied[group]=nil end
				for _,i in ipairs(candidate.indices) do used[i]=nil end
				if #solutions > 1 then return end
			end
		end
	end
	search()
	assert(#solutions == 1,#solutions == 0 and "Imported values do not resolve to legal affixes at this item level; use advanced copy text or a blank base with a structured starting state" or "Imported values match several modifier identities; use advanced copy text or a blank base with a structured starting state")
	for _,entry in ipairs(solutions[1]) do state.affixes[#state.affixes+1]=entry end
	return state
end
return I
