-- Relate each compiled block to its build-owned section without rewriting sources.
local filters=require("Modules.LootFilters")
local library=require("Modules.LootFilterLibrary")
local parser=require("Modules.LootFilterParser")
local M={}
function M.outline(profile,raw,report,parsed)
	profile=filters.validate({schemaVersion=1,activeId=profile.id,profiles={profile}}).profiles[1]
	if not raw then raw,report=filters.compile(profile) end;parsed=parsed or parser.parse(raw);local sources={}
	local function add(section,title,rule,category,editable)
		local id=editable and rule.id or section=="base" and rule.id or "override-"..require("sha1")(section..":"..(rule.id or rule.title)):sub(1,20)
		sources[#sources+1]={section=section,sectionTitle=title,rule=rule,category=category or library.category(rule),editable=editable,overrideId=id}
	end
	for _,rule in ipairs(profile.rules) do if rule.enabled then add("personal","Personal pickups",rule,nil,true) end end
	for _,tier in ipairs(profile.tiers or {}) do local rule=require("Modules.LootFilterEditing").rule(tier);if rule then add("tiers","Custom tiers",rule) end end
	for _,module in ipairs(profile.modules or {}) do if module.enabled then for _,rule in ipairs(module.rules) do if rule.enabled then add("module-"..module.id,"Module: "..module.title,rule) end end end end
	for _,rule in ipairs(require("Modules.LootFilterCampaign").rules(profile.campaign,profile.theme)) do add("campaign","Campaign policies",rule,"Campaign") end
	if filters.needsSafety(profile) then for class in pairsSortByKey(filters.patch().added) do add("safety","3.30 item safety",{title=class,text=""},library.category({text='Class == "'..class..'"'})) end end
	for _,entry in ipairs(library.catalog(profile)) do add("base","Base preset",entry.rule,entry.category) end
	assert(#sources==#parsed.rules,"Compiled filter structure does not match its sources")
	local entries,sections,bySection={},{},{}
	for i,block in ipairs(parsed.rules) do
		local source=sources[i];local section=bySection[source.section]
		if not section then section={id=source.section,title=source.sectionTitle,count=0,categories={}};bySection[section.id]=section;sections[#sections+1]=section end
		section.count=section.count+1;section.categories[source.category]=(section.categories[source.category] or 0)+1
		local text=table.concat(block.rawLines,"\n");local rule=copyTable(source.rule);rule.id=source.overrideId;rule.text=text;rule.enabled=true
		entries[#entries+1]={id=i,title=source.rule.title or block.title or "Filter block",section=section.id,sectionTitle=section.title,category=source.category,line=block.line,
			lastLine=parsed.rules[i+1] and parsed.rules[i+1].line-1 or parsed.lineCount,block=block,text=text,rule=rule,editable=source.editable}
	end
	return {entries=entries,sections=sections,report=report,raw=raw}
end
function M.diagnostics(outline,entry)
	local result={};for _,d in ipairs(outline.report.diagnostics) do if d.line>=entry.line and d.line<=entry.lastLine then result[#result+1]=d end end;return result
end
function M.filter(outline,query,section,category,mode)
	query=(query or ""):lower();local result={}
	for _,entry in ipairs(outline.entries) do
		local accept=not section or entry.section==section;accept=accept and (not category or entry.category==category)
		accept=accept and (entry.title.." "..entry.sectionTitle.." "..entry.category.." "..entry.text):lower():find(query,1,true)~=nil
		if accept and mode and mode~="All blocks" then
			if mode=="Continue blocks" then accept=entry.block.continue==true
			elseif mode=="Hidden blocks" then accept=entry.block.action=="Hide" or entry.block.action=="Minimal"
			else local found=false;for _,d in ipairs(M.diagnostics(outline,entry)) do if mode=="Priority conflicts" and d.shadowedBy or mode=="Warnings / errors" and (d.warning or d.error) then found=true end end;accept=found end
		end
		if accept then result[#result+1]=entry end
	end;return result
end
return M
