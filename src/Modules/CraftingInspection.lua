-- Readable facts and item-state differences, separate from crafting transitions.
local sim=require("Modules.CraftingSimulator")
local M={}
local lightRadius330=require("Modules.CraftingLightRadius330").ranges
function M.modDetails(model,id,entry)
	local mod=assert(entry and sim.entryMod(model,entry) or (model.corruptions330 or {})[id] or model.byId[id],"Unknown modifier")
	local lines={mod.type.." | "..(mod.affix or "Modifier"),"Required item level: "..(mod.level or 0)}
	-- Rank only comparable, eligible ordinary tiers. Special modifiers keep their names.
	local levels={};local group=mod.group
	if group and not id:find(":",1,true) then
		for _,other in pairs(model.byId) do if other.group==group and other.type==mod.type and other.level and other.weightKey and model.item:GetModSpawnWeight(other,{})>0 then levels[other.level]=true end end
		local rank=1;for level in pairs(levels) do if level>(mod.level or 0) then rank=rank+1 end end
		lines[#lines+1]="Group tier: "..rank
	end
	for _,line in ipairs(mod) do lines[#lines+1]="Range: "..line end
	if lightRadius330[id] then lines[#lines+1]="3.30 Light Radius range: "..lightRadius330[id].."%."..(entry and entry.legacyLightRadius and " Existing legacy value is retained until rerolled." or "") end
	if model.legacyAbyss and model.legacyAbyss[id] then lines[#lines+1]="3.30: this older Abyss modifier no longer rolls naturally. Existing copies are retained." end
	if model.unveiledJewels and model.unveiledJewels[id] then lines[#lines+1]="3.30 unveiled jewel modifier. Unveil offers and acquisition are not yet simulated." end
	if model.trickery330 and model.trickery330[id] then lines[#lines+1]="Essence of Trickery: Delirium Fog effects are not modeled in build calculations." end
	if sim.isClusterSpeedMod(model,id) then lines[#lines+1]="3.30: small-passive attack and cast speed modifiers share a family." end
	if mod.tags and #mod.tags>0 then lines[#lines+1]="Tags: "..table.concat(mod.tags,", ") end
	if entry then
		lines[#lines+1]=entry.fractured and "Fractured: protected from ordinary rerolls." or entry.crafted and "Crafted modifier: uses a bench-crafted slot." or model.special and model.special[id] and "Special explicit modifier." or "Natural explicit modifier."
		for _,line in ipairs(sim.rolledLines(mod,entry.range)) do lines[#lines+1]="Current: "..line end
	end
	return lines
end
function M.slots(model,state)
	model=sim.context(model,state)
	local caps=sim.capacities(model,state);local prefixes,suffixes=0,0
	for _,entry in ipairs(state.affixes) do local mod=model.byId[entry.id];if mod.type=="Prefix" then prefixes=prefixes+1 elseif mod.type=="Suffix" then suffixes=suffixes+1 end end
	return string.format("Prefixes %d/%d | Suffixes %d/%d",prefixes,caps.Prefix,suffixes,caps.Suffix)
end
local function values(model,state)
	model=sim.context(model,state)
	local result={}
	for _,entry in ipairs(state.affixes) do
		local texts=sim.rolledLines(sim.entryMod(model,entry),entry.range)
		result[entry.id]=table.concat(texts," / ")..(entry.fractured and " [fractured]" or entry.crafted and " [crafted]" or "")
	end
	return result
end
function M.diff(model,before,after)
	local old,new=values(model,before),values(model,after);local result={}
	local oldItem,newItem=sim.context(model,before).item,sim.context(model,after).item
	if oldItem.baseName~=newItem.baseName then result[#result+1]="Base: "..oldItem.baseName.." -> "..newItem.baseName end
	if oldItem.itemLevel~=newItem.itemLevel then result[#result+1]="Item level: "..oldItem.itemLevel.." -> "..newItem.itemLevel end
	for id,text in pairs(old) do if not new[id] then result[#result+1]="- "..text elseif new[id]~=text then result[#result+1]="Changed: "..text.." -> "..new[id] end end
	for id,text in pairs(new) do if not old[id] then result[#result+1]="+ "..text end end
	for _,key in ipairs({"rarity","quality","corrupted","destroyed","intangibility","memoryStrands","baseName"}) do if before[key]~=after[key] then result[#result+1]=key..": "..tostring(before[key] or "none").." -> "..tostring(after[key] or "none") end end
	if (before.twiceCorrupted or false)~=(after.twiceCorrupted or false) then result[#result+1]="Twice Corrupted: "..(before.twiceCorrupted and "yes" or "no").." -> "..(after.twiceCorrupted and "yes" or "no") end
	local json=require("dkjson");if json.encode(before.sockets or {})~=json.encode(after.sockets or {}) then result[#result+1]="Socket colours, count or links changed." end
	for _,key in ipairs({"implicits","influences","enchants","harvestEnchant","catalyst","catalystQuality","veil"}) do if json.encode(before[key])~=json.encode(after[key]) then result[#result+1]=key=="harvestEnchant" and "Harvest quality enchantment changed." or key.." changed." end end
	table.sort(result);if #result==0 then result[1]="No displayed modifier or item-property changes." end
	return result
end
function M.category(method)
	if method:find("harvest",1,true) then return "Harvest" elseif method:find("beast",1,true) or method=="restore_imprint" then return "Bestiary"
	elseif method:find("eldritch",1,true) then return "Eldritch" elseif method:find("bench",1,true) or method=="remove_crafted" then return "Bench"
	elseif method:find("socket",1,true) or method=="chromatic" or method=="jeweller" or method=="fusing" or method=="omen_jeweller" or method=="omen_connections" or method=="omen_trichromatism" then return "Sockets"
	elseif method:find("ducat",1,true) or method:find("memory",1,true) or method:find("recombine",1,true) then return "Special mechanics"
	elseif method=="essence" or method=="fossil" then return "Essences and fossils" else return "Currency" end
end
return M
