-- cspell:ignore RGBWAD
-- Data-only PoE filter parsing. Unknown conditions produce an explained unknown,
-- never a falsely certain hidden/shown result. Imports are not read from disk.
local M={}
local styleOptions=require("Modules.LootFilterAppearanceSettings");local colors,shapes={},{}
for _,value in ipairs(styleOptions.colors) do colors[value]=true end;for _,value in ipairs(styleOptions.shapes) do shapes[value]=true end
M.actions={SetTextColor=true,SetBorderColor=true,SetBackgroundColor=true,SetFontSize=true,PlayAlertSound=true,PlayAlertSoundPositional=true,
	CustomAlertSound=true,CustomAlertSoundOptional=true,DisableDropSound=true,EnableDropSound=true,DisableDropSoundIfAlertSound=true,EnableDropSoundIfAlertSound=true,MinimapIcon=true,PlayEffect=true}
M.numeric={AreaLevel=true,ItemLevel=true,DropLevel=true,Quality=true,LinkedSockets=true,Sockets=true,Width=true,Height=true,StackSize=true,GemLevel=true,MapTier=true,
	BaseArmour=true,BaseEvasion=true,BaseEnergyShield=true,BaseWard=true,BaseDefencePercentile=true,EnchantmentPassiveNum=true,CorruptedMods=true,
	HasEaterOfWorldsImplicit=true,HasSearingExarchImplicit=true,UnidentifiedItemTier=true,MemoryStrands=true}
M.booleans={Identified=true,Corrupted=true,TwiceCorrupted=true,Mirrored=true,FracturedItem=true,SynthesisedItem=true,ShaperItem=true,ElderItem=true,ShapedMap=true,ElderMap=true,
	BlightedMap=true,UberBlightedMap=true,Replica=true,Scourged=true,HasImplicitMod=true,AnyEnchantment=true,HasCruciblePassiveTree=true,Foulborn=true,Fated=true,Exceptional=true,TransfiguredGem=true,AlternateQuality=true,Imbued=true,Vestigial=true,ZanaMemory=true,MirageMap=true}
M.strings={Class=true,BaseType=true,HasInfluence=true,HasExplicitMod=true,HasEnchantment=true,EnchantmentPassiveNode=true,Prophecy=true,ArchnemesisMod=true,GemQualityType=true}
local rarity={Normal=0,Magic=1,Rare=2,Unique=3}
function M.tokens(line)
	local out,quoted={},{};local pos=1
	while pos<=#line do
		local char=line:sub(pos,pos)
		if char=="#" then break
		elseif char:match("%s") then pos=pos+1
		elseif char=='"' then
			local last=line:find('"',pos+1,true);assert(last,"Unclosed quoted value")
			out[#out+1]=line:sub(pos+1,last-1);quoted[#out]=true;pos=last+1
		else local last=line:find('[%s#]',pos) or #line+1;out[#out+1]=line:sub(pos,last-1);quoted[#out]=false;pos=last end
	end
	return out,quoted
end
function M.parse(raw)
	assert(type(raw)=="string" and #raw<=2*1024*1024,"Filter exceeds 2 MiB")
	local result={rules={},diagnostics={},imports={}};local current;local title
	for line in (raw:gsub("^\239\187\191","").."\n"):gmatch("([^\n]*)\n") do
		local ok,t,quoted=pcall(M.tokens,line);local lineNo=(result.lineCount or 0)+1;result.lineCount=lineNo
		title=line:match("^%s*# PoB rule: (.*)") or title
		if not ok then result.diagnostics[#result.diagnostics+1]={line=lineNo,error=t}
		elseif #t>0 then
			local key=table.remove(t,1);table.remove(quoted,1)
			if key=="Show" or key=="Hide" or key=="Minimal" then
				current={action=key,line=lineNo,title=title,conditions={},styles={},rawLines={line}};title=nil;result.rules[#result.rules+1]=current
				if #t>0 then result.diagnostics[#result.diagnostics+1]={line=lineNo,error="Unexpected values after "..key} end
			elseif key=="Import" then
				if #t<1 or #t>2 or not t[1]:match("%S") or #t==2 and t[2]~="Optional" then result.diagnostics[#result.diagnostics+1]={line=lineNo,error="Invalid Import; specify a file and optional Optional keyword"}
				else result.imports[#result.imports+1]={line=lineNo,file=t[1],optional=t[2]=="Optional"} end
				current=nil
			elseif not current then result.diagnostics[#result.diagnostics+1]={line=lineNo,error="Expected Show, Hide or Minimal before "..key}
			else
				current.rawLines[#current.rawLines+1]=line
				if key=="Continue" then current.continue=true
				elseif M.actions[key] then
					current.styles[key]=t
					local invalid
					if key=="SetTextColor" or key=="SetBorderColor" or key=="SetBackgroundColor" then
						invalid=#t<3 or #t>4;for _,v in ipairs(t) do local n=tonumber(v);if not n or n<0 or n>255 or n~=math.floor(n) then invalid=true end end
					elseif key=="SetFontSize" then local n=tonumber(t[1]);invalid=#t~=1 or not n or n<1 or n>45 or n~=math.floor(n)
					elseif key=="PlayAlertSound" or key=="PlayAlertSoundPositional" or key=="CustomAlertSound" or key=="CustomAlertSoundOptional" then
						local custom=key=="CustomAlertSound" or key=="CustomAlertSoundOptional";local id=tonumber(t[1]);local volume=tonumber(t[2])
						invalid=#t<1 or #t>2 or not t[1] or not t[1]:match("%S")
						if not custom and t[1]~="None" and (not id or id~=math.floor(id) or id<1 or id>16) then invalid=true end
						if t[2] and (not volume or volume~=math.floor(volume) or volume<0 or volume>300) then invalid=true end
					elseif key=="MinimapIcon" then local size=tonumber(t[1]);invalid=not (#t==1 and size==-1) and (#t~=3 or not size or size<0 or size>2 or size~=math.floor(size) or not colors[t[2]] or not shapes[t[3]])
					elseif key=="PlayEffect" then invalid=not (#t==1 and t[1]=="None") and (not colors[t[1]] or #t>2 or #t==2 and t[2]~="Temp") end
					if invalid then result.diagnostics[#result.diagnostics+1]={line=lineNo,error="Invalid "..key} end
				else
					local op="=";local first=t[1] or "";local prefix=not quoted[1] and first:match("^[<>=!]+")
					local separated=prefix and #first==#prefix
					if prefix then op=prefix;t[1]=first:sub(#prefix+1);if t[1]=="" then table.remove(t,1);table.remove(quoted,1) end end
					local known=M.numeric[key] or M.booleans[key] or M.strings[key] or key=="Rarity" or key=="SocketGroup"
					current.conditions[#current.conditions+1]={keyword=key,operator=op,values=t,quoted=quoted,known=known,line=lineNo}
					if #t==0 then result.diagnostics[#result.diagnostics+1]={line=lineNo,error="Condition requires a value: "..key}
					elseif not known then result.diagnostics[#result.diagnostics+1]={line=lineNo,warning="Simulator cannot resolve "..key.."; original text is preserved"} end
					if not ({["="]=true,["=="]=true,["!="]=true,["!"]=true,[">="]=true,["<="]=true,[">"]=true,["<"]=true})[op] then result.diagnostics[#result.diagnostics+1]={line=lineNo,error="Invalid operator "..op} end
					if (key=="HasExplicitMod" or key=="HasEnchantment") and separated and not quoted[1] and tonumber(t[1]) then result.diagnostics[#result.diagnostics+1]={line=lineNo,error="Join the operator and modifier count for "..key} end
					if M.booleans[key] and (key~="TransfiguredGem" and t[1]~="True" and t[1]~="False" or op~="=" and op~="==" and op~="!" and op~="!=") then result.diagnostics[#result.diagnostics+1]={line=lineNo,error="Invalid boolean "..key} end
					if key=="UnidentifiedItemTier" then local n=tonumber(t[1]);if not n or n<0 or n>5 or n~=math.floor(n) then result.diagnostics[#result.diagnostics+1]={line=lineNo,error="UnidentifiedItemTier must be 0 to 5"} end end
					if key=="SocketGroup" or key=="Sockets" then for _,value in ipairs(t) do
						if value=="" or not value:match("^%d*[RGBWAD]*$") and not (key=="Sockets" and tonumber(value)) then result.diagnostics[#result.diagnostics+1]={line=lineNo,error="Invalid socket pattern for "..key};break end
					end end
					if M.numeric[key] and key~="Sockets" then for _,value in ipairs(t) do local n=tonumber(value);if not n or n~=n or math.abs(n)==math.huge then result.diagnostics[#result.diagnostics+1]={line=lineNo,error="Invalid numeric value for "..key};break end end end
				end
			end
		end
	end
	return result
end
local function compare(a,b,op)
	if op=="=" or op=="==" then return a==b elseif op=="!" or op=="!=" then return a~=b elseif op==">=" then return a>=b elseif op=="<=" then return a<=b elseif op==">" then return a>b elseif op=="<" then return a<b end
end
local function socketMatch(value,pattern,op)
	local required={};local number=tonumber(pattern:match("^%d+"))
	for color in pattern:gmatch("[RGBWAD]") do required[color]=(required[color] or 0)+1 end
	local available={};local count=0;for color in value:gmatch("[RGBWAD]") do available[color]=(available[color] or 0)+1;count=count+1 end
	-- GGG defines strict comparisons as any specified count being greater or less.
	if op=="<" or op==">" then
		if number and compare(count,number,op) then return true end
		for color,n in pairs(required) do if compare(available[color] or 0,n,op) then return true end end
		return false
	end
	if number and not compare(count,number,op) then return false end
	local colorOp=op=="==" and "==" or (op=="!" or op=="!=") and op or ">="
	for color,n in pairs(required) do if not compare(available[color] or 0,n,colorOp) then return false end end
	return true
end
function M.condition(c,item)
	if not c.known then return nil,"Unsupported condition "..c.keyword end
	if c.keyword=="HasExplicitMod" and item.Identified~=true then
		return nil,item.Identified==false and "Explicit modifiers are hidden on unidentified items" or "Supply identification state for explicit modifiers"
	end
	local value=item[c.keyword]
	if c.keyword=="SocketGroup" and value==nil and tonumber(item.Sockets)==0 then value="0" end
	if value==nil then return nil,"Missing "..c.keyword end
	local op=c.operator;local values=c.values
	if c.keyword=="Sockets" then
		local count=tonumber(value);local colours=item.SocketColours or (count==0 and "") or (not count and type(value)=="string" and value or nil);local unknown
		local negative=op=="!" or op=="!="
		for _,pattern in ipairs(values) do
			local number=tonumber(pattern);local pass
			if number then
				if count then pass=compare(count,number,op) else unknown="Invalid Sockets" end
			elseif type(colours)~="string" then unknown="Supply socket colours for Sockets"
			elseif colours:find("[^RGBWAD%s%-]") then unknown="Invalid socket colours for Sockets"
			elseif count and select(2,colours:gsub("[RGBWAD]",""))~=count then unknown="Socket count does not match socket colours"
			else pass=socketMatch(colours,pattern,op) end
			if pass~=nil and (negative and not pass or not negative and pass) then return not negative end
		end
		if unknown then return nil,unknown end
		return negative
	end
	if c.keyword=="SocketGroup" then
		if type(value)~="string" then return nil,"Supply socket colours for "..c.keyword end
		if value=="0" or value=="" then
			for _,pattern in ipairs(values) do if socketMatch("",pattern,op) then return true end end
			return false
		end
		if value:find("[^RGBWAD%s%-]") then return nil,"Invalid socket colours for "..c.keyword end
		for _,pattern in ipairs(values) do
			-- Abyss and Delve sockets cannot link to other sockets, even when
			-- a manually entered sample places them inside a group.
			local separated=value:gsub("([AD])"," %1 ")
			for group in separated:gmatch("[^ ]+") do if socketMatch(group,pattern,op) then return true end end
		end;return false
	elseif M.numeric[c.keyword] or c.keyword=="Rarity" then
		value=c.keyword=="Rarity" and rarity[value] or tonumber(value)
		if value==nil then return nil,"Invalid "..c.keyword end
		local negative=op=="!" or op=="!="
		for _,v in ipairs(values) do local n=c.keyword=="Rarity" and rarity[v] or tonumber(v);if not n then return nil,"Invalid numeric value for "..c.keyword end
			if negative and value==n then return false elseif not negative and compare(value,n,op) then return true end
		end
		return negative
	elseif M.booleans[c.keyword] then
		if c.keyword=="TransfiguredGem" then
			if values[1]=="True" or values[1]=="False" then return compare(value==true or type(value)=="string" and value~="",values[1]=="True",op) end
			if value==false then return op=="!" or op=="!=" end
			if type(value)~="string" then return nil,"Supply the base name for TransfiguredGem" end
			local found=false;for _,name in ipairs(values) do if value==name then found=true end end;return (op=="!" or op=="!=") and not found or op~="!" and op~="!=" and found
		end
		if type(value)~="boolean" or (values[1]~="True" and values[1]~="False") then return nil,"Invalid boolean "..c.keyword end
		return compare(value,values[1]=="True",op)
	else
		local negative=op=="!" or op=="!=";local entries=type(value)=="table" and value or {value}
		local count=0;local minimum=(c.keyword=="HasExplicitMod" or c.keyword=="HasEnchantment") and not (c.quoted and c.quoted[1]) and tonumber(values[1]) or nil;local start=minimum and 2 or 1
		for _,entry in ipairs(entries) do for i=start,#values do
			local found=op=="==" and tostring(entry)==values[i] or op~="==" and tostring(entry):lower():find(values[i]:lower(),1,true)~=nil
			if found then count=count+1;break end
		end end
		if minimum then return compare(count,minimum,op) end
		return negative and count==0 or not negative and count>0
	end
end
function M.simulate(parsed,item)
	local result={action="Show",status="matched",styles={},matches={},reasons={}}
	for _,d in ipairs(parsed.diagnostics) do if d.error then return {status="invalid",action="Unknown",styles={},matches={},reasons={"Syntax error on line "..d.line}} end end
	local importIndex=1
	local function unresolvedImport()
		local entry=parsed.imports[importIndex]
		result.status="unknown";result.action="Unknown";result.line=entry.line
		result.reasons={"Included file '"..entry.file.."' is unresolved and could change this result. Attach it for an exact preview."}
		return result
	end
	for _,rule in ipairs(parsed.rules) do
		if parsed.imports[importIndex] and parsed.imports[importIndex].line<rule.line then return unresolvedImport() end
		local matched,unknown=true,{}
		for _,condition in ipairs(rule.conditions) do local pass,why=M.condition(condition,item);if pass==false then matched=false;break elseif pass==nil then unknown[#unknown+1]=why end end
		if matched then
			if #unknown>0 then result.status="unknown";result.action="Unknown";result.reasons=unknown;result.line=rule.line;return result end
			result.action=rule.action;result.line=rule.line;result.ruleTitle=rule.title;result.matches[#result.matches+1]=rule.line
			for key,value in pairs(rule.styles) do result.styles[key]=value end
			if not rule.continue then
				if #parsed.imports>0 then result.reasons[#result.reasons+1]="Later included files are unresolved; this preview assumes they are valid and available when required." end
				return result
			end
		end
	end
	if parsed.imports[importIndex] then return unresolvedImport() end
	return result
end
return M
