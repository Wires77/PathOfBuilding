-- Presentation for the crafting workbench. All mutations stay in the simulator.
local M = { }
local anchor = {"TOPLEFT",nil,"TOPLEFT"}
local simulator = require("Modules.CraftingSimulator")
local artwork
local function image(path)
	local handle = NewImageHandle();handle:Load(path);return handle
end
local function text(x,y,size,value,color,width)
	while width and size>12 and DrawStringWidth(size,"VAR",value)>width do size=size-1 end
	if width and DrawStringWidth(size,"VAR",value)>width then
		while #value>0 and DrawStringWidth(size,"VAR",value.."...")>width do value=value:sub(1,-2) end
		value=value.."..."
	end
	SetDrawColor(color or "^xC8C8C8");DrawString(x,y,"LEFT",size,"VAR",value)
end
local function box(x,y,w,h,color)
	SetDrawColor(color);DrawImage(nil,x,y,w,h)
end
local function wrap(list,value,color,width)
	value=StripEscapes(value)
	while #value > 0 do
		local length=#value
		while length > 1 and DrawStringWidth(16,"VAR",value:sub(1,length)) > width do length=length-1 end
		if length < #value then length=value:sub(1,length):match("^.*()%s") or length end
		list[#list+1]={height=19,textSize=16,(color or "^x8888FF")..value:sub(1,length)}
		value=value:sub(length+1):gsub("^%s+","")
	end
end

-- Keep imagery honest: unknown bases use PoB's equipment silhouette, rather
-- than showing a different base's artwork.
local slots={Helmet="helmet",["Body Armour"]="body_armour",Gloves="gloves",Boots="boots",Shield="shield",Ring="ring_left",Amulet="amulet",Belt="belt",Quiver="quiver",Bow="bow"}
function M.itemArt(item)
	if not artwork then
		local file=assert(io.open("Assets/Crafting/items.json","r"));artwork=assert(require("dkjson").decode(file:read("*a"))).bases;file:close()
	end
	local entry=artwork[item.baseName] or artwork[item.baseName:gsub(" %b()$","")]
	if entry and entry.path then return entry.path,entry.width,entry.height end
	return "Assets/icon_"..(slots[item.type] or "weapon")..".png",84,84
end
function M.item(controls,key,x,y,w,h,model,getState,onClick,options)
	options=options or {};local weaponItem=model.item.base.weapon~=nil;local header=(options.header or 180)+(weaponItem and 22 or 0);local artSize=options.artSize or 84;local propertyX=artSize+26
	local art,artWidth,artHeight,artPath
	local function setArt(item)
		local path,width,height=M.itemArt(item)
		if path ~= artPath then art=image(path);artPath=path end
		local scale=artSize/math.max(width,height)
		artWidth,artHeight=width*scale,height*scale
	end
	setArt(model.item)
	local card=new("ButtonControl"):ButtonControl(anchor,{x,y,w,header},"",onClick or function() end)
	controls[key]=card
	local mods=new("TextListControl"):TextListControl(anchor,{x,y+header,w,h-header},nil,{})
	controls[key.."Mods"]=mods
	if options.compact then mods.columns={{x=68,align="LEFT"},{x=8,align="LEFT"}} end
	function card:Draw()
		local cx,cy=self:GetPos();local state=getState();local item=self.preview or model.item
		local rarity=state.rarity or "NORMAL"
		local color=state.destroyed and "^xE07070" or rarity == "RARE" and "^xFFFF77" or rarity == "MAGIC" and "^x8888FF" or "^xC8C8C8"
		box(cx,cy,w,header,options.compact and "^x756647" or color);box(cx+1,cy+1,w-2,header-2,"^x101016")
		box(cx+2,cy+2,w-4,53,rarity == "RARE" and "^x302B18" or rarity == "MAGIC" and "^x1B1B30" or "^x232326")
		local title=state.destroyed and "Item destroyed" or rarity == "RARE" and (item.title or "Crafted item") or item.baseName
		local subtitle=rarity == "RARE" and item.baseName or rarity:sub(1,1)..rarity:sub(2):lower().." item"
		if options.compact then
			while #title>1 and DrawStringWidth(20,"VAR",title)>w-32 do title=title:sub(1,-2) end
			while #subtitle>1 and DrawStringWidth(16,"VAR",subtitle)>w-32 do subtitle=subtitle:sub(1,-2) end
			SetDrawColor(color);DrawString(cx+w/2,cy+8,"CENTER_X",20,"VAR",title);DrawString(cx+w/2,cy+33,"CENTER_X",16,"VAR",subtitle)
			box(cx+12,cy+56,w-24,1,"^x756647")
		else text(cx+16,cy+9,20,title,color,w-32);text(cx+16,cy+33,16,subtitle,color,w-32) end
		SetDrawColor(1,1,1,state.destroyed and 0.2 or 1);DrawImage(art,cx+12+(artSize-artWidth)/2,cy+66+(artSize-artHeight)/2,artWidth,artHeight)
		text(cx+propertyX,cy+67,16,"Item level "..item.itemLevel)
		text(cx+propertyX,cy+89,16,"Quality: +"..(state.quality or item.quality or 0).."%")
		text(cx+propertyX,cy+111,16,self.defences or "",nil,w-propertyX-16)
		if self.weaponStats then
			local weapon=self.weaponStats
			local dps=string.format("Weapon DPS %.1f | phys %.1f | ele %.1f",weapon.TotalDPS or 0,weapon.PhysicalDPS or 0,weapon.ElementalDPS or 0)
			if (weapon.ChaosDPS or 0)>0 then dps=dps..string.format(" | chaos %.1f",weapon.ChaosDPS) end
			text(cx+propertyX,cy+111,16,dps,nil,w-propertyX-16)
			text(cx+propertyX,cy+133,16,string.format("%.2f attacks/s | %.2f%% crit",weapon.AttackRate or 0,weapon.CritChance or 0),nil,w-propertyX-16)
		end
		local extra=weaponItem and 22 or 0
		local sockets=state.sockets or item.sockets or {}
		for i,socket in ipairs(sockets) do
			local sx=cx+propertyX+(i-1)*24
			if i>1 and socket.color~="A" and sockets[i-1].color~="A" and socket.group == sockets[i-1].group then box(sx-9,cy+139+extra,12,3,"^xA68B59") end
			box(sx,cy+133+extra,14,14,"^xA68B59")
			box(sx+2,cy+135+extra,10,10,({R="^xE07070",G="^x70BB70",B="^x7070EE",W="^xEEEEEE",A="^x205B42"})[socket.color] or "^xC8C8C8")
			if socket.color=="A" then text(sx+3,cy+133+extra,12,"A","^xFFFFFF",8) end
		end
		if (header>=212 or options.compact) and self.slotSummary then text(cx+propertyX,cy+158+extra,14,self.slotSummary,"^xA6B3C6",w-propertyX-16) end
		if (header>=212 or options.compact) and self.influenceSummary then text(cx+propertyX,cy+176+extra,12,self.influenceSummary,"^xD3B987",w-propertyX-16) end
		if not options.compact then text(cx+16,cy+header-21,14,state.destroyed and "Undo or reset to continue" or onClick and self:IsEnabled() and "Click the item to apply the selected currency" or "Item preview","^xD3B987") end
	end
	if options.compact then
		local draw=mods.Draw
		function mods:Draw(viewport)
			draw(self,viewport)
			local selected=options.selectedAffix and options.selectedAffix()
			if selected then
				local mx,my=self:GetPos();local mw,mh=self:GetSize();SetViewport(mx+2,my+2,mw-20,mh-4)
				local top=-self.controls.scrollBar.offset
				for _,row in ipairs(self.list) do if row.affixId==selected and top+row.height>=0 and top<mh-4 then box(0,top,3,row.height,"^xD3B987") end;top=top+row.height end
				SetViewport()
			end
		end
	end
	local function refresh()
		local state=getState();local lines={};card.defences=nil;card.weaponStats=nil;card.influenceSummary=nil
		if state.destroyed then wrap(lines,"This item was destroyed.","^xE07070",w-30)
		else
			local context=simulator.context(model,state)
			card.preview=context.item;setArt(context.item)
			local item=simulator.toItem(model,state)
			local defences={}
			for _,property in ipairs({"Armour","Evasion","EnergyShield","Ward"}) do
				local value=item.armourData and item.armourData[property]
				if value and value>0 then defences[#defences+1]=(property == "EnergyShield" and "ES" or property)..": "..math.floor(value) end
			end
			card.defences=#defences>0 and table.concat(defences," / ") or nil
			card.weaponStats=item.weaponData and item.weaponData[options.slot and options.slot:match("^Weapon 2") and 2 or 1]
			if #(item.implicitModLines or {})>0 then wrap(lines,"Implicit modifiers","^xA6B3C6",w-30) end
			for _,line in ipairs(item.implicitModLines or {}) do wrap(lines,itemLib.formatModLine(line,false) or line.line,"^x8888FF",w-30) end
			if #(item.enchantModLines or {})>0 then wrap(lines,"Enchantments","^xA6B3C6",w-30) end
			for _,line in ipairs(item.enchantModLines or {}) do wrap(lines,itemLib.formatModLine(line,false) or line.line,"^xB4B4FF",w-30) end
			local influences={};for _,info in ipairs(itemLib.influenceInfo.all) do if item[info.key] then influences[#influences+1]=info.display end end
			card.influenceSummary=#influences>0 and table.concat(influences," / ") or nil
			if #lines>0 then lines[#lines+1]={height=12,""} end
			local entries=state.affixes
			if options.compact then
				entries={};for _,kind in ipairs({"Prefix","Suffix"}) do for _,entry in ipairs(state.affixes) do if context.byId[entry.id].type==kind then entries[#entries+1]=entry end end end
			end
			local group,groupIndex
			for _,entry in ipairs(entries) do
				local mod=context.byId[entry.id]
				local marker=(entry.fractured and "Fractured " or entry.crafted and "Crafted " or "")..(mod.type or "Explicit")
				if options.compact then
					if group~=mod.type then group=mod.type;groupIndex=0;lines[#lines+1]={height=29,textSize=13,x=10,"^xA6B3C6"..(group=="Prefix" and "PREFIXES" or "SUFFIXES")} end
					groupIndex=groupIndex+1
				else wrap(lines,marker,entry.fractured and "^xD6B677" or "^xA6B3C6",w-30) end
				local firstMod=#lines+1
				for _,line in ipairs(simulator.rolledLines(simulator.entryMod(context,entry) or {},entry.range)) do
					local first=#lines+1
					wrap(lines,line,entry.fractured and "^xD6B677" or entry.crafted and "^xB4B4FF" or "^x8888FF",w-(options.compact and 98 or 30))
					for i=first,#lines do lines[i].affixId=entry.id end
					if options.changedAffixes and options.changedAffixes()[entry.id] then for i=first,#lines do lines[i][1]="^x92D39C"..StripEscapes(lines[i][1]);lines[i].changed=true end end
				end
				if options.compact and lines[firstMod] then lines[firstMod][2]=(lines[firstMod].changed and "^x92D39C+" or entry.fractured and "^xD6B677" or "^x8D9DB0")..(entry.fractured and "F " or entry.crafted and "C " or "")..mod.type:sub(1,1)..groupIndex end
			end
			if #state.affixes == 0 then wrap(lines,"No explicit modifiers","^xAAAAAA",w-30) end
			if state.veil then wrap(lines,"Veiled modifier - select Unveil to reveal choices","^xD3B987",w-30) end
			if state.corrupted then wrap(lines,state.twiceCorrupted and "Twice Corrupted" or "Corrupted","^xE07070",w-30) end
			if (state.intangibility or 0)>0 then wrap(lines,"Intangibility: "..state.intangibility.."%","^xD3B987",w-30) end
			if (state.memoryStrands or 0)>0 then wrap(lines,"Memory strands: "..state.memoryStrands,"^xD3B987",w-30) end
		end
		mods.list=lines;mods.controls.scrollBar.offset=0
		if options.compact then
			for _,line in ipairs(lines) do if not line.affixId then line.x=line.x or 10 end end
			mods.borderColor="^x756647";mods.backgroundColor="^x101016"
		end
		card.slotSummary=not state.destroyed and require("Modules.CraftingInspection").slots(model,state) or nil
	end
	return refresh
end

local currencies={
	{"transmute","Transmute"},{"alteration","Alteration"},{"augmentation","Augment"},{"regal","Regal"},{"alchemy","Alchemy"},{"chaos","Chaos"},
	{"exalt","Exalted"},{"annul","Annul"},{"scour","Scour"},{"divine","Divine"},{"vaal","Vaal"},{"chromatic","Chromatic"},
}
local descriptions={beast_max_links="Link existing sockets using the Black Morrigan and a Craicic Sand Spitter.",omen_trichromatism="Guarantee one red, green and blue socket. Uses one Omen and one Chromatic Orb.",omen_connections="Fully link existing sockets. Uses one Omen of Connections and one Orb of Fusing.",transmute="Add magic modifiers to a normal item.",alteration="Reroll the modifiers on a magic item.",augmentation="Add a modifier to a magic item.",regal="Upgrade a magic item and add a modifier.",alchemy="Turn a normal item into a rare item.",chaos="Reroll the modifiers on a rare item.",exalt="Add a modifier to a rare item.",annul="Remove a random modifier.",scour="Remove the item's modifiers.",divine="Reroll the values of existing modifiers.",vaal="Corrupt the item. Outcomes can be destructive.",chromatic="Reroll socket colours."}
local currencyArt,currencyNames
function M.actionLabel(action,model)
	if action.method=="bench_reroll" and (action.count==1 or action.count==3) then return "Bench: reroll "..action.count.." modifier"..(action.count==1 and "" or "s") end
	if model and action.method=="bench" and model.byId[action.modId] then return "Bench: "..table.concat(model.byId[action.modId]," / ") end
	if model and action.method=="essence" then for _,entry in ipairs(model.essences or {}) do if entry.id==action.essenceId then return entry.name end end end
	if model and action.method=="fossil" and action.fossils then
		local names={};for _,id in ipairs(action.fossils) do for _,entry in ipairs(model.fossils or {}) do if entry.id==id then names[#names+1]=entry.name;break end end end
		if #names==#action.fossils and #names>0 then return "Fossils: "..table.concat(names,", ") end
	end
	if (action.method=="harvest_reforge" or action.method=="harvest_augment") and action.tag then return (simulator.labels[action.method] or action.method).." ("..action.tag..")" end
	return simulator.labels[action.method] or action.method
end
function M.icon(method,action,model)
	if not currencyArt then
		local file=assert(io.open("Assets/Crafting/currencies.json","rb"));currencyArt=assert(require("dkjson").decode(file:read("*a")));file:close();currencyNames={}
		for _,entry in pairs(currencyArt.items) do currencyNames[entry.name]=entry.path end
		-- The 3.30 client assigns Trickery the same inventory art as Delirium.
		currencyNames["Essence of Trickery"]=currencyNames["Essence of Delirium"]
	end
	action=action or {};local id=currencyArt.methods[method];local name
	if method=="socket_white_bench" then name="Orb of Scouring"
	elseif method=="omen_jeweller" then name="Jeweller's Orb"
	elseif method=="essence" and action.essenceId then
		local entry=data.essences[action.essenceId]
		if model then for _,candidate in ipairs(model.essences or {}) do if candidate.id==action.essenceId then entry=candidate;break end end end
		name=entry and entry.name
	elseif method=="catalyst" and action.catalyst then local entry=({"Abrasive","Accelerating","Dextral","Fertile","Imbued","Intrinsic","Noxious","Prismatic","Sinistral","Tempering","Turbulent","Unstable"})[action.catalyst];name=entry and entry.." Catalyst"
	elseif method=="fossil" and action.fossils then local prefix=({"Primitive","Potent","Powerful","Prime"})[#action.fossils];name=prefix and prefix.." Chaotic Resonator"
	elseif method=="eldritch_implicit" and action.tier then local prefix=({"Lesser","Greater","Grand","Exceptional"})[action.tier];name=prefix and prefix.." Eldritch "..(action.side=="Eater" and "Ichor" or "Ember")
	elseif method=="influence_exalt" then local prefix=({shaper="Shaper",elder="Elder",adjudicator="Warlord",basilisk="Hunter",crusader="Crusader",eyrie="Redeemer"})[action.influence];name=prefix and prefix.."'s Exalted Orb"
	elseif method=="quality" or method=="tainted_quality" then
		if not model then return end;local kind=model.item.type
		if kind=="Flask" or kind=="Tincture" then if method=="tainted_quality" then return end;name="Glassblower's Bauble"
		else name=(method=="tainted_quality" and "Tainted " or "")..(data.weaponTypeInfo[kind] and "Blacksmith's Whetstone" or "Armourer's Scrap") end
	elseif method:find("harvest",1,true) then return end
	return name and currencyNames[name] or id and currencyArt.items[id].path or descriptions[method] and "Assets/Crafting/"..method..".png" or nil
end
function M.available(method,state,model)
	return require("Modules.CraftingAvailability").check(method,state,model)
end
function M.hint(method,state,model)
	local available,reason=M.available(method,state,model)
	if available and method=="annul" then return "3.30: remove a random modifier. Attack/caster roll blockers do not protect it; fractures and prefix/suffix locks still apply." end
	if available and method=="binding" then return "No longer generated in 3.30. Existing Orbs of Binding still work." end
	if available and method=="recombine" then return "3.30 uses the chosen base's item level. Count odds for one-to-three modifiers still use older estimates." end
	if available and method=="locus" then return "Assumes 25% implicit, 25% sockets, 50% destruction; not verified." end
	if available and method=="socket_white_bench" then return "3.30 bench: turn sockets white for one Scouring Orb, plus one Vaal Orb on corrupted items." end
	if available and method=="omen_jeweller" then return "Add white sockets up to the base and item-level limit. Uses one Omen and one Jeweller's Orb." end
	if available and method=="harvest_enchant" then return "Replace the enchantment with a quality bonus. Options show the Lifeforce cost." end
	if available and method=="harvest_resistance" then return "Change one elemental resistance to another. Costs 300 Lifeforce for each element." end
	return available and (descriptions[method] or "Choose the craft options, then apply to the item.") or reason
end
function M.currencies(controls,selectMethod,currentMethod,isShown,usage,getState,model,leftWidth)
	local cell=math.floor(((leftWidth or 416)-20)/6)
	for i,entry in ipairs(currencies) do
		local method,caption=unpack(entry)
		local control=new("ButtonControl"):ButtonControl(anchor,{16+(i-1)%6*(cell+4),94+math.floor((i-1)/6)*65,cell,61},"",function() selectMethod(method) end)
		controls["currency_"..method]=control;control.shown=isShown
		control.planningFocusable=true
		local art=image("Assets/Crafting/"..method..".png")
		control.enabled=function() return M.available(method,getState(),model) end
		control.tooltipText=function() return (simulator.labels[method] or caption).."\n"..M.hint(method,getState(),model) end
		function control:Draw(viewPort,noTooltip)
			local x,y=self:GetPos();local selected=currentMethod() == method
			box(x,y,cell,61,self.hasFocus and "^x83C8EF" or selected and "^xD3B987" or self:IsMouseOver() and "^xAAAAAA" or "^x4E473A")
			box(x+1,y+1,cell-2,59,selected and "^x302B20" or "^x18181C")
			local tint=self:IsEnabled() and 1 or 0.38;SetDrawColor(tint,tint,tint);DrawImage(art,x+(cell-38)/2,y+2,38,38)
			SetDrawColor("^xDDDDDD");DrawString(x+cell/2,y+44,"CENTER_X",12,"VAR",caption)
			local count=usage(method)
			if count>0 then text(x+48,y+3,12,tostring(count),"^xFFFF77") end
			if self:IsMouseOver() and not noTooltip then
				SetDrawLayer(nil,100);self:DrawTooltip(x,y,66,61,viewPort);SetDrawLayer(nil,0)
			end
		end
	end
end
return M
