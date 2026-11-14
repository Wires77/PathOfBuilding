-- cspell:ignore jsontype katakohi ukatoa
-- Saved quotes share a common unit; no economy feed or conversion is implied.
local sim=require("Modules.CraftingSimulator")
local M={}
local art,names
local aliasCache={}
local function catalogue()
	if not art then
		local file=assert(io.open("Assets/Crafting/currencies.json","rb"));art=assert(require("dkjson").decode(file:read("*a")));file:close();names={}
		local ids={};for id in pairs(art.items) do ids[#ids+1]=id end;table.sort(ids)
		for _,id in ipairs(ids) do names[art.items[id].name]=id end
	end
	return art
end
local catalysts={"Abrasive","Accelerating","Dextral","Fertile","Imbued","Intrinsic","Noxious","Prismatic","Sinistral","Tempering","Turbulent","Unstable"}
-- Artwork may represent a service or a composite action. Only these actions
-- have a one-to-one currency price; adding artwork must not add a price alias.
local simpleCurrency={alchemy=true,alteration=true,annul=true,augmentation=true,awakener=true,binding=true,blessed=true,chaos=true,chromatic=true,conflict=true,divine=true,dominance=true,
	ducat_brinehook=true,ducat_cyaxan=true,ducat_genteel=true,ducat_katakohi=true,ducat_kishara=true,ducat_merrick=true,ducat_rotmother=true,ducat_tzamoto=true,ducat_ukatoa=true,
	eldritch_annul=true,eldritch_chaos=true,eldritch_exalt=true,exalt=true,foulborn_augmentation=true,foulborn_exalt=true,foulborn_regal=true,fracture=true,fusing=true,jeweller=true,
	regal=true,remembrance=true,sacred=true,scour=true,tainted_catalyst=true,tainted_chaos=true,tainted_chromatic=true,tainted_exalt=true,tainted_fusing=true,tainted_jeweller=true,transmute=true,unravelling=true,vaal=true,veiled_chaos=true,veiled_orb=true}
function M.currencyAliases(methods)
	local result={};for method in pairs(simpleCurrency) do local id=methods[method];if id then result[method]=id end end;return result
end
function M.aliases(model)
	local kind=model and model.item.type or ""
	if aliasCache[kind] then return aliasCache[kind] end
	local data=catalogue();local result=M.currencyAliases(data.methods)
	for id,entry in pairs(data.items) do
		local stackable=id:gsub("/DelveSocketableCurrencyReroll","/DelveStackableSocketableCurrencyReroll")
		if stackable~=id and data.items[stackable] and data.items[stackable].name==entry.name then result[id]=stackable end
	end
	for i,name in ipairs(catalysts) do result["catalyst:"..i]=names[name.." Catalyst"] end
	for i,name in ipairs({"Primitive","Potent","Powerful","Prime"}) do result["resonator:"..i]=names[name.." Chaotic Resonator"] end
	for i,name in ipairs({"Lesser","Greater","Grand","Exceptional"}) do
		result["eldritch_implicit:Exarch:"..i]=names[name.." Eldritch Ember"];result["eldritch_implicit:Eater:"..i]=names[name.." Eldritch Ichor"]
	end
	for _,info in ipairs(itemLib.influenceInfo.all) do result["influence_exalt:"..info.key]=names[info.display.."'s Exalted Orb"] end
	for key,name in pairs({wild_lifeforce="Wild Crystallised Lifeforce",vivid_lifeforce="Vivid Crystallised Lifeforce",primal_lifeforce="Primal Crystallised Lifeforce",sacred_lifeforce="Sacred Crystallised Lifeforce",crystallised_rancour="Crystallised Rancour"}) do result[key]=names[name] end
	if model then
		local kind=model.item.type;local ordinary=(kind=="Flask" or kind=="Tincture") and "Glassblower's Bauble" or _G.data.weaponTypeInfo[kind] and "Blacksmith's Whetstone" or "Armourer's Scrap"
		result.quality=names[ordinary]
		result.tainted_quality=names[_G.data.weaponTypeInfo[kind] and "Tainted Blacksmith's Whetstone" or "Tainted Armourer's Scrap"]
	end
	aliasCache[kind]=result;return result
end
local function text(value,limit,label)
	assert(type(value)=="string" and #value<=limit and value:match("%S") and not value:find("[%c]"),"Invalid "..label);return value
end
function M.validate(book)
	assert(type(book)=="table" and type(book.values)=="table","Invalid resource prices")
	local result={currency=text(book.currency,24,"price currency"),source=text(book.source,240,"price source"),quotedAt=book.quotedAt,values=setmetatable({},{__jsontype="object"})}
	assert(type(book.quotedAt)=="number" and book.quotedAt==math.floor(book.quotedAt) and book.quotedAt>=0 and book.quotedAt<=4102444800,"Invalid quote time")
	local count=0
	for key,value in pairs(book.values) do
		text(key,240,"resource key");assert(type(value)=="number" and value==value and value>=0 and value<=1e12,"Invalid price for "..key)
		result.values[key]=value;count=count+1
	end
	assert(count<=2000,"Resource prices exceed the supported size")
	return result
end
function M.key(key,model) return M.aliases(model)[key] or key end
local function canonicalValues(values,model)
	local result=setmetatable({},{__jsontype="object"})
	for key,value in pairs(values) do
		key=M.key(key,model);assert(result[key]==nil or result[key]==value,"Conflicting quotes for the same resource");result[key]=value
	end
	return result
end
function M.forSimulation(book,currency,model,overrides)
	local result={}
	if book then
		book=M.validate(book)
		assert(not next(book.values) or currency==book.currency,"Saved prices are in "..book.currency..". Use that unit or edit resource prices.")
		result=canonicalValues(book.values,model)
	end
	for key,value in pairs(canonicalValues(overrides or {},model)) do result[key]=value end
	for alias,id in pairs(M.aliases(model)) do if result[id]~=nil then result[alias]=result[id] end end
	return next(result) and result or nil
end
function M.actionOverride(key,value)
	if value==nil then return end
	assert(type(key)=="string" and #key>0 and #key<=1024 and not key:find("[%c]"),"Choose an action before setting its price")
	assert(type(value)=="number" and value==value and value>=0 and value<=1e12,"Invalid action price")
	return {[key]=value}
end
-- Resource aliases share a unit quote; use actionOverride for an action total.
function M.resolve(book,currency,model,overrideKey,override)
	local overrides
	if override~=nil then
		assert(type(override)=="number" and override==override and override>=0 and override<=1e12,"Invalid action price")
		overrides={[assert(overrideKey,"Choose an action before setting its price")]=override}
	end
	return M.forSimulation(book,currency,model,overrides)
end
function M.describe(key,model)
	local data=catalogue();local canonical=M.key(key,model);local entry=data.items[canonical]
	if entry then return entry.name,entry.path,"Currency" end
	if model then for _,essence in ipairs(model.essences or {}) do if essence.id==canonical then
		return essence.name,require("Modules.CraftingWorkbench").icon("essence",{essenceId=canonical},model),"Currency"
	end end end
	local method,option=key:match("^([^:]+):(.+)$");method=method or key
	local label=sim.labels[method] or key
	if method=="bench" then local mod=_G.data.masterMods[tonumber(option)];if mod then label="Bench: "..table.concat(mod," / ") end
	elseif option then label=label.." / "..option end
	local id=data.methods[method]
	if key=="dead_mans_sulphur" then return "Dead Man's Sulphur",nil,"Resource" end
	if key=="beast_black_morrigan" or key=="beast_craicic_sand_spitter" then
		local orb=data.methods.beast_max_links;local path=orb and data.items[orb] and data.items[orb].path
		return key=="beast_black_morrigan" and "The Black Morrigan" or "Craicic Sand Spitter",path,"Beast"
	end
	return label,id and data.items[id].path,"Whole action"
end
function M.entries(model,state,actions,book,recipeState)
	local result,seen={},{};local aliases=M.aliases(model)
	local function add(key,required)
		local canonical=aliases[key] or key
		if seen[canonical] then seen[canonical].required=seen[canonical].required or required;return end
		local name,path,kind=M.describe(canonical,model);local row={key=canonical,name=name,path=path,kind=kind,required=required or false};seen[canonical]=row;result[#result+1]=row
	end
	-- Routes can jump backwards or restart, so a corruption action anywhere in
	-- the guide can precede another step on a later visit. Show possible
	-- ingredients conservatively rather than assuming linear execution.
	local mayCorrupt=false
	for _,action in ipairs(actions or {}) do if action.method=="vaal" or action.method=="locus" then mayCorrupt=true;break end end
	for _,action in ipairs(actions or {}) do
		local found=false
		-- Include both general recipe ingredients and the current item's
		-- state-dependent ingredients, including the saved recipe's start.
		local inputs={false,state or false,recipeState or false}
		if mayCorrupt then
			local corrupt=copyTable(recipeState or state or model.initial);corrupt.corrupted=true;inputs[#inputs+1]=corrupt
		end
		for _,input in ipairs(inputs) do
			local ok,components=pcall(sim.components,action,input or nil,model)
			if ok then found=true;for key in pairs(components) do add(key,true) end end
		end
		if not found then add(sim.priceKey(action),true) end
	end
	for key in pairs(book and book.values or {}) do add(key,false) end
	for id in pairs(catalogue().items) do add(id,false) end
	table.sort(result,function(a,b) if a.required~=b.required then return a.required end;return a.name<b.name end)
	return result
end
function M.normalized(book,model)
	book=M.validate(book);book.values=canonicalValues(book.values,model);return book
end
return M
