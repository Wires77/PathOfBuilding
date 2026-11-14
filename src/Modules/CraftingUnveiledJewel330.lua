-- Client-derived unveiled jewel descriptions. These are special modifiers,
-- never part of the natural currency pool. Acquisition remains separate.
local M={}
local cached
local function data()
	if cached then return cached end
	local root=GetScriptPath();local f=assert(io.open((root~="" and root.."/" or "").."Data/Crafting/3.30-unveiled-jewels.json","rb"))
	local raw=f:read("*a");f:close();local source=assert(require("dkjson").decode(raw))
	assert(source.schemaVersion==1 and source.clientVersion=="3.30.0.1.4","Invalid unveiled jewel data")
	local ids={};for id in pairs(source.mods) do ids[#ids+1]=id end;table.sort(ids);cached={}
	for index,id in ipairs(ids) do
		local row=source.mods[id];local mod={type=row.type=="prefix" and "Prefix" or "Suffix",affix=row.name,level=row.level,group=row.group,weightKey={},weightVal={},modTags=copyTable(row.tags),clientStats=copyTable(row.stats),statOrder={}}
		mod.modTags[#mod.modTags+1]="unveiled_mod"
		for i,line in ipairs(row.text) do mod[i]=line;mod.statOrder[i]=100000000+index*10+i end
		for _,weight in ipairs(row.weights) do mod.weightKey[#mod.weightKey+1]=weight.tag;mod.weightVal[#mod.weightVal+1]=weight.weight end
		cached[id]=mod
	end
	return cached
end
function M.prepare(model)
	model.unveiledJewels={}
	if model.item.type~="Jewel" then return end
	for id,mod in pairs(data()) do
		if mod.level<=model.item.itemLevel and model.item:GetModSpawnWeight(mod)>0 then model.byId[id]=mod;model.unveiledJewels[id]=mod end
	end
end
-- Native item parsing cannot resolve IDs added after its bundled data. Recover
-- those explicit advanced-copy identities before checking the rendered lines.
function M.restoreIdentities(model,raw,special)
	special=special or model.unveiledJewels
	if not next(special) or not raw:find("\nCrafted: true",1,true) then return end
	local indices={Prefix=0,Suffix=0}
	for line in (raw.."\n"):gmatch("([^\n]*)\n") do
		local side,value=line:match("^%s*(Prefix):%s*(.-)%s*$")
		if not side then side,value=line:match("^%s*(Suffix):%s*(.-)%s*$") end
		if side then
			indices[side]=indices[side]+1
			local fractured=value:match("^{fractured}")~=nil;value=value:gsub("^{fractured}","")
			local range,id=value:match("^{range:([^}]+)}(.+)$");id=id or value
			if special[id] then
				assert(special[id].type==side,"Special modifier is on the wrong affix side")
				local values={};if range then
					assert(not range:find("^,") and not range:find(",$") and not range:find(",,",1,true),"Invalid unveiled modifier roll")
					for number in range:gmatch("[^,]+") do local value=assert(tonumber(number),"Invalid unveiled modifier roll");assert(value==value and math.abs(value)<=100,"Invalid unveiled modifier roll");values[#values+1]=value end
					assert(#values>0 and #values<=20,"Invalid unveiled modifier roll count")
				else values={main.defaultItemAffixQuality} end
				local list=side=="Prefix" and model.item.prefixes or model.item.suffixes
				list[indices[side]]={modId=id,range=values,fractured=fractured}
			end
		end
	end
end
return M
