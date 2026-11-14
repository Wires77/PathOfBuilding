-- Explain the current native modifier pool without estimating whole-recipe odds.
local sim=require("Modules.CraftingSimulator")
local metadata=require("Modules.CraftingAdvanced")
local M={}
function M.scope(mod) return (mod.type=="Corrupted" or mod.type=="Exarch" or mod.type=="Eater") and "implicit" or "explicit" end
local function has(list,value) for _,entry in ipairs(list or {}) do if entry==value then return true end end end
local function groups(model,id,mod)
	local entry=metadata.data().mods[id];local result=entry and entry.groups or {mod.group or id}
	if model.item.clusterJewel and sim.isClusterSpeedMod(model,id) then result=copyTable(result);result[#result+1]=sim.clusterSpeedGroup end
	return result
end
function M.catalog(model)
	if model.modifierCatalogue then return model.modifierCatalogue end
	local rows,seen={},{}
	local function add(id,mod,source,weight)
		if seen[id] or not mod then return end;seen[id]=true
		local meta=metadata.data().mods[id];local tags=meta and meta.implicit_tags or mod.modTags or mod.tags or {}
		rows[#rows+1]={id=id,mod=mod,text=table.concat(mod," / "),type=mod.type or "Special",level=mod.level or meta and meta.required_level or 0,groups=groups(model,id,mod),source=meta and meta.is_essence_only and "Essence" or source,baseWeight=weight,tags=tags}
	end
	for _,entry in ipairs(model.mods) do add(entry.id,entry.mod,"Natural",entry.weight) end
	for id,mod in pairs(model.item.affixes or {}) do if not seen[id] and (mod.type=="Prefix" or mod.type=="Suffix") and mod.weightKey and not (mod.affix or ""):find("Elevated",1,true) then
		local weight=model.item:GetModSpawnWeight(mod,model.extraTags);if weight>0 then model.byId[id]=mod;add(id,mod,"Natural",weight) end
	end end
	for _,entry in ipairs(model.influencePool or {}) do add(entry.id,entry.mod,"Influence",entry.weight) end
	for _,entry in ipairs(model.bench) do add(entry.id,entry.mod,"Bench") end
	for _,entry in ipairs(model.essences) do add(entry.modId,model.descriptions330[entry.modId] or model.byId[entry.modId],"Essence") end
	for id in pairs(model.special or {}) do add(id,model.byId[id],"Special") end
	local families={}
	for _,row in ipairs(rows) do if row.source=="Natural" or row.source=="Influence" then local key=row.type..":"..table.concat(row.groups,":")..":"..row.source;row.family=key;families[key]=families[key] or {};families[key][row.level]=true end end
	local ranks={};for key,levels in pairs(families) do local ordered={};for level in pairs(levels) do ordered[#ordered+1]=level end;table.sort(ordered,function(a,b) return a>b end);ranks[key]={};for rank,level in ipairs(ordered) do ranks[key][level]=rank end end
	for _,row in ipairs(rows) do row.tier=row.family and ranks[row.family][row.level] or nil end
	table.sort(rows,function(a,b) if a.source~=b.source then return a.source<b.source end;if a.type~=b.type then return a.type<b.type end;if a.text~=b.text then return a.text<b.text end;return a.id<b.id end)
	model.modifierCatalogue=rows;return rows
end
function M.inspect(model,state)
	model=sim.context(model,state);local eligible,total=sim.pool(model,state);local weights={};for _,entry in ipairs(eligible) do weights[entry.id]=entry.weight end
	local used,counts,flags={}, {Prefix=0,Suffix=0},sim.blockFlags(model,state)
	for key,value in pairs(state.rollBlock or {}) do flags[key]=value end
	for _,entry in ipairs(state.affixes) do local mod=assert(model.byId[entry.id]);counts[mod.type]=(counts[mod.type] or 0)+1
		for _,group in ipairs(groups(model,entry.id,mod)) do used[group]=table.concat(mod," / ") end
	end
	local caps=sim.capacities(model,state);local result={rows={},totalWeight=total,note="Draw chances describe one ordinary weighted affix selection in the captured state, not the selected currency or a complete recipe. Tier ranks compare applicable natural tiers in the same modifier group."}
	for _,row in ipairs(M.catalog(model)) do
		local reasons={};local weight=weights[row.id] or 0
		if row.level>model.item.itemLevel then reasons[#reasons+1]="Requires item level "..row.level end
		if counts[row.type] and counts[row.type]>=(caps[row.type] or 0) then reasons[#reasons+1]="No open "..row.type:lower().." slot" end
		for _,group in ipairs(row.groups) do if used[group] then reasons[#reasons+1]="Conflicts with "..used[group] end end
		if row.source=="Natural" or row.source=="Influence" then
			for _,tag in ipairs({"attack","caster"}) do if flags[tag] and has(row.tags,tag) then reasons[#reasons+1]="Cannot roll "..tag.." modifiers" end end
		end
		if weight==0 and #reasons==0 then reasons[1]=(row.source=="Natural" or row.source=="Influence") and "Not in the current base/influence pool" or row.source.." crafting source; outside the ordinary draw pool" end
		-- A positive engine weight is authoritative for this pool, including its special rules.
		if weight>0 then reasons={} end
		result.rows[#result.rows+1]={id=row.id,text=row.text,type=row.type,level=row.level,tier=row.tier,groups=row.groups,source=row.source,baseWeight=row.baseWeight,weight=weight,chance=total>0 and weight/total*100 or nil,reasons=reasons,tags=row.tags,eligible=weight>0}
	end
	return result
end
function M.filter(result,query,kind,source,availability,sort)
	local rows={};query=(query or ""):lower()
	for _,row in ipairs(result.rows) do if (not kind or kind=="All affixes" or kind==row.type) and (not source or source=="All sources" or source==row.source)
		and (availability~="Eligible draw" or row.eligible) and (availability~="Blocked / special" or not row.eligible)
		and (row.id.." "..row.text.." "..table.concat(row.groups," ").." "..table.concat(row.tags," ").." "..table.concat(row.reasons," ")):lower():find(query,1,true) then rows[#rows+1]=row end end
	table.sort(rows,function(a,b)
		if sort=="Chance" and a.weight~=b.weight then return a.weight>b.weight elseif sort=="Tier" and (a.tier or math.huge)~=(b.tier or math.huge) then return (a.tier or math.huge)<(b.tier or math.huge)
		elseif sort=="Item level" and a.level~=b.level then return a.level>b.level elseif sort=="Eligible first" and a.eligible~=b.eligible then return a.eligible end
		if sort=="Eligible first" then local ag,bg=table.concat(a.groups,":"),table.concat(b.groups,":");if ag~=bg then return ag<bg end
			if a.source~=b.source then return a.source<b.source end;if (a.tier or math.huge)~=(b.tier or math.huge) then return (a.tier or math.huge)<(b.tier or math.huge) end
		end
		if a.text~=b.text then return a.text<b.text end;return a.id<b.id
	end)
	return rows
end
return M
