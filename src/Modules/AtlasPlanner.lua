-- Native Atlas plans use pinned GGG data, independently of character passives.
-- cspell:ignore jsontype
local json = require("dkjson")
local M = {versions={"3.27.0","3.27.0-ruthless","3.29.1","3.29.1-ruthless","3.29.3","3.29.3-ruthless","3.30.0-preview","3.30.0-preview-ruthless"},cache={}}
function M.defaultVersion(treeVersion)
	treeVersion=treeVersion or ""
	if treeVersion:find("ruthless",1,true) then
		return treeVersion:match("3_30") and "3.30.0-preview-ruthless" or treeVersion:match("3_27") and "3.27.0-ruthless" or "3.29.3-ruthless"
	end
	return treeVersion:match("3_30") and "3.30.0-preview" or treeVersion:match("3_27") and "3.27.0" or "3.29.3"
end
local function integer(value,low,high,label)
	assert(type(value) == "number" and value == math.floor(value) and value >= low and value <= high,"Invalid "..label)
	return value
end
local function text(value,limit,label)
	assert(type(value) == "string" and #value <= limit,"Invalid "..label)
	return value
end
local function array(value,limit,label)
	assert(type(value) == "table" and value ~= json.null and #value <= limit,"Invalid "..label)
	local meta=getmetatable(value)
	assert(not meta or meta.__jsontype ~= "object","Expected an array for "..label)
	for key in pairs(value) do assert(type(key) == "number" and key == math.floor(key) and key >= 1 and key <= #value,"Invalid array for "..label) end
	return value
end
function M.tree(version)
	assert(isValueInTable(M.versions,version),"Unsupported Atlas version; choose a bundled tree")
	if not M.cache[version] then
		local root=GetScriptPath()
		local file=assert(io.open((root ~= "" and root.."/" or "").."Data/Atlas/"..version..".json","rb"))
		local raw=file:read("*a"); file:close()
		local tree=assert(json.decode(raw))
		local nodes={}
		for id,node in pairs(tree.nodes) do nodes[tonumber(id)]=node end
		tree.nodes=nodes; M.cache[version]=tree
	end
	return M.cache[version]
end
local function nodeSet(tree,ids)
	array(ids,300,"Atlas node IDs")
	local set={}
	for _,id in ipairs(ids) do
		integer(id,1,65535,"Atlas node ID")
		assert(tree.nodes[id],"Unknown or decorative Atlas node: "..id)
		assert(not set[id],"Duplicate Atlas node: "..id); set[id]=true
	end
	return set
end
local function sorted(set)
	local result={}; for id in pairs(set) do result[#result+1]=id end; table.sort(result); return result
end
local function reachable(tree,set)
	local visited,queue={[tree.start]=true},{tree.start}
	local index=1
	while index <= #queue do
		for _,id in ipairs(tree.nodes[queue[index]].links) do
			if set[id] and not visited[id] then visited[id]=true; queue[#queue+1]=id end
		end
		index=index+1
	end
	return visited
end
function M.validate(plan)
	assert(type(plan) == "table","Invalid Atlas plan")
	local tree=M.tree(plan.version)
	local result={id=text(plan.id,64,"Atlas plan ID"),title=text(plan.title,120,"Atlas title"),version=plan.version,
		budget=integer(plan.budget,0,tree.maxPoints,"Atlas point budget"),notes=text(plan.notes or "",8000,"Atlas notes"),nodes={}}
	assert(result.id:match("^[%w_-]+$") and result.title:match("%S"),"Use an Atlas plan ID and title")
	if plan.progression then
		local p=plan.progression;assert(type(p)=="table" and ({starter=true,intermediate=true,final=true})[p.stage],"Choose an Atlas progression stage")
		result.progression={stage=p.stage}
		if p.previousId and p.previousId~="" then result.progression.previousId=text(p.previousId,64,"previous Atlas plan");assert(p.previousId~=plan.id,"A plan cannot follow itself") end
	end
	if plan.strategy then
		assert(type(plan.strategy)=="table","Invalid Atlas strategy");local s={};result.strategy=s
		for _,key in ipairs({"maps","scarabs","requirements","avoid","notes"}) do s[key]=text(plan.strategy[key] or "",4000,"strategy "..key) end
		if plan.strategy.setupCost then
			local cost=plan.strategy.setupCost;assert(type(cost)=="table" and type(cost.amount)=="number" and cost.amount>=0 and cost.amount<=1e12,"Invalid Atlas setup cost")
			s.setupCost={amount=cost.amount,currency=text(cost.currency,40,"setup currency"),source=text(cost.source or "",240,"cost source"),quotedAt=integer(cost.quotedAt,0,4102444800,"cost date")}
		end
	end
	local set=nodeSet(tree,plan.nodes); set[tree.start]=true
	local desired=nodeSet(tree,plan.desired or {});local avoided=nodeSet(tree,plan.avoided or {})
	for id in pairs(desired) do assert(id~=tree.start,"The Atlas start is already free");assert(not avoided[id],"An Atlas node cannot be both desired and avoided") end
	for id in pairs(avoided) do assert(id~=tree.start and not set[id],"Cannot avoid an allocated Atlas node") end
	if plan.desired~=nil then result.desired=sorted(desired) end
	if plan.avoided~=nil then result.avoided=sorted(avoided) end
	local connected=reachable(tree,set)
	local used,bonus=0,0
	for id in pairs(set) do
		assert(connected[id],"Atlas plan has disconnected nodes")
		if id ~= tree.start then used=used+1; result.nodes[#result.nodes+1]=id end
		bonus=bonus+(tree.nodes[id].grantedPoints or 0)
	end
	assert(used <= result.budget+bonus,"Atlas plan exceeds point budget")
	table.sort(result.nodes)
	return result
end
-- A grant cannot pay for the path that must be allocated before receiving it.
-- Keep legacy plans readable; callers can report or reject unattainable budgets.
local function budgetReachabilityChecked(plan)
	local tree=M.tree(plan.version)
	local available=plan.budget+(tree.nodes[tree.start].grantedPoints or 0)
	if #plan.nodes<=available then return true end
	local set=nodeSet(tree,plan.nodes);set[tree.start]=true
	local grants={};for _,id in ipairs(plan.nodes) do if (tree.nodes[id].grantedPoints or 0)>0 then grants[#grants+1]=id end end
	if #grants~=1 then return nil,"Cannot verify the allocation order for multiple point grants." end
	local function distance(allowed)
		local distances,queue={[tree.start]=0},{tree.start};local index=1
		while index<=#queue do
			local id=queue[index];index=index+1;if id==grants[1] then return distances[id] end
			for _,other in ipairs(tree.nodes[id].links) do
				if (not allowed or allowed[other]) and distances[other]==nil then distances[other]=distances[id]+1;queue[#queue+1]=other end
			end
		end
	end
	local direct=assert(distance(set),"Disconnected grant node")
	if direct<=available then return true,nil,direct end
	local shortest=assert(distance(),"Unreachable grant node")
	if shortest>available then return false,"Need "..shortest.." earned points to reach "..tree.nodes[grants[1]].name.." before its grant.",shortest end
	return nil,"Reaching "..tree.nodes[grants[1]].name.." may require a temporary path and refunds; review the transition.",direct
end
function M.budgetReachability(plan) return budgetReachabilityChecked(M.validate(plan)) end
function M.search(version,query,limit)
	local tree=M.tree(version)
	query=text(query or "",160,"Atlas search"):lower(); limit=integer(limit or 30,1,100,"search limit")
	local all={}
	for _,id in ipairs(sorted(tree.nodes)) do
		local node=tree.nodes[id]
		if id ~= tree.start and (node.name.." "..table.concat(node.stats," ")):lower():find(query,1,true) then all[#all+1]=node end
	end
	local matches={}; for i=1,math.min(limit,#all) do matches[i]=copyTable(all[i]) end
	return {version=version,total=#all,matches=matches,source=tree.source}
end
-- Greedy shortest connections, deterministic in caller target order. Not a global optimizer.
function M.exclusions(plan,extra)
	local tree=M.tree(plan.version);local set=nodeSet(tree,plan.avoided or {})
	for id in pairs(nodeSet(tree,extra or {})) do set[id]=true end;return sorted(set)
end
function M.connect(plan,targets,avoid,checkpoint)
	plan=M.validate(plan)
	local tree=M.tree(plan.version)
	local set=nodeSet(tree,plan.nodes); set[tree.start]=true
	local exclusions=M.exclusions(plan,avoid);local blocked=nodeSet(tree,exclusions)
	for id in pairs(blocked) do assert(not set[id],"Cannot avoid an allocated Atlas node") end
	array(targets,300,"Atlas targets")
	local additions={}
	for targetIndex,target in ipairs(targets) do
		integer(target,1,65535,"Atlas target")
		assert(tree.nodes[target] and not blocked[target],"Unknown or avoided Atlas target")
		local previous,queue={},sorted(set)
		for _,id in ipairs(queue) do previous[id]=false end
		local index=1
		while previous[target] == nil and index <= #queue do
			if checkpoint and index%128==0 then checkpoint({target=targetIndex,targets=#targets}) end
			local current=queue[index]; index=index+1
			for _,id in ipairs(tree.nodes[current].links) do
				if previous[id] == nil and not blocked[id] then previous[id]=current; queue[#queue+1]=id end
			end
		end
		assert(previous[target] ~= nil,"Atlas target cannot be reached with these avoided nodes")
		local cursor=target
		while not set[cursor] do set[cursor]=true; additions[#additions+1]=cursor; cursor=previous[cursor] end
		if checkpoint then checkpoint({target=targetIndex,targets=#targets}) end
	end
	set[tree.start]=nil; plan.nodes=sorted(set)
	if plan.avoided~=nil or #exclusions>0 then plan.avoided=exclusions end
	local result=M.validate(plan);local reachable,why=budgetReachabilityChecked(result);assert(reachable~=false,why)
	return result,additions
end
-- Retain existing allocations. Compare bounded orders, then solve up to four
-- targets exactly. An invalid baseline must not prevent a valid reorder.
function M.connectOptimized(plan,targets,avoid,options)
	options=options or {};plan=M.validate(plan);array(targets,300,"Atlas targets")
	local tree=M.tree(plan.version);local blocked=nodeSet(tree,M.exclusions(plan,avoid))
	local allocated=nodeSet(tree,plan.nodes);allocated[tree.start]=true
	for id in pairs(blocked) do assert(not allocated[id],"Cannot avoid an allocated Atlas node") end
	for _,id in ipairs(targets) do integer(id,1,65535,"Atlas target");assert(tree.nodes[id] and not blocked[id],"Unknown or avoided Atlas target") end
	local best,additions,baseline;local attempts=0;local seen={}
	local function try(order)
		local signature=table.concat(order,",");if seen[signature] then return end;seen[signature]=true;attempts=attempts+1
		local ok,value,added=pcall(M.connect,plan,order,avoid,options.checkpoint and function(progress) progress.order=attempts;progress.orders=math.min(#targets+2,33);options.checkpoint(progress) end)
		if attempts==1 and ok then baseline=#added end
		if ok and (not best or #added<#additions) then best,additions=value,added end
	end
	try(targets)
	local reversed={};for i=#targets,1,-1 do reversed[#reversed+1]=targets[i] end;try(reversed)
	-- Bound order exploration; distribute rotations across larger desired sets.
	for trial=1,math.min(#targets-1,30) do local offset=math.floor(trial*#targets/math.min(#targets,31));local order={};for i=1,#targets do order[i]=targets[(i+offset-1)%#targets+1] end;try(order) end
	-- Also grow a route toward the nearest remaining target at each step. Its
	-- order can differ from every rotation and often shares more of the path.
	local remaining={};for _,id in ipairs(targets) do remaining[id]=true end
	local set=copyTable(allocated);local nearest={}
	while next(remaining) do
		local previous,queue={},sorted(set);local found
		for _,id in ipairs(queue) do previous[id]=false;if remaining[id] and not found then found=id end end
		local index=1
		while not found and index<=#queue do
			if options.checkpoint and index%128==0 then options.checkpoint({order=attempts+1,orders=math.min(#targets+2,33),target=#nearest+1,targets=#targets}) end
			local current=queue[index];index=index+1
			for _,id in ipairs(tree.nodes[current].links) do
				if previous[id]==nil and not blocked[id] then
					previous[id]=current;queue[#queue+1]=id
					if remaining[id] then found=id;break end
				end
			end
		end
		if not found then break end
		nearest[#nearest+1]=found;remaining[found]=nil
		local cursor=found;while not set[cursor] do set[cursor]=true;cursor=previous[cursor] end
		if options.checkpoint then options.checkpoint({order=attempts+1,orders=math.min(#targets+2,33),target=#nearest,targets=#targets}) end
	end
	if not next(remaining) then try(nearest) end
	-- A small target set can be solved exactly, including shared paths between
	-- targets. Larger requests retain the bounded order search above.
	local exact=false
	if options.exact~=false and #targets<=4 then
		local found=require("Modules.AtlasExactRoute").find(tree,allocated,blocked,targets,options.checkpoint)
		if found then
			local candidate=copyTable(plan);local set=copyTable(allocated)
			for id in pairs(found) do set[id]=true end;set[tree.start]=nil;candidate.nodes=sorted(set)
			local exclusions=M.exclusions(plan,avoid);if candidate.avoided~=nil or #exclusions>0 then candidate.avoided=exclusions end
			local ok,value=pcall(M.validate,candidate)
			if ok then
				local reachable=budgetReachabilityChecked(value)
				if reachable~=false then
					local added=sorted(found)
					if not best or #added<=#additions then best,additions=value,added;exact=true end
				end
			end
		end
	end
	assert(best,"Atlas targets cannot be connected within this budget and exclusions")
	return best,additions,{attempts=attempts,originalCost=baseline,cost=#additions,saved=baseline and baseline-#additions or nil,heuristic=not exact}
end
function M.remove(plan,id)
	plan=M.validate(plan); local tree=M.tree(plan.version)
	assert(id ~= tree.start and tree.nodes[id],"Cannot remove the Atlas start")
	local set=nodeSet(tree,plan.nodes); set[id]=nil
	local keep=reachable(tree,set); keep[tree.start]=nil; plan.nodes=sorted(keep)
	return M.validate(plan)
end
function M.report(plan)
	plan=M.validate(plan); local tree=M.tree(plan.version)
	local reachable,budgetWarning,pointsBeforeGrant=budgetReachabilityChecked(plan)
	local counts,notables,keystones,stats,bonus={small=0,notable=0,keystone=0,gateway=0},{},{},{},0
	for _,id in ipairs(plan.nodes) do
		local node=tree.nodes[id]; counts[node.kind]=counts[node.kind]+1
		if node.kind == "notable" then notables[#notables+1]=node.name end
		if node.kind == "keystone" then keystones[#keystones+1]=node.name end
		bonus=bonus+node.grantedPoints
		for _,stat in ipairs(node.stats) do stats[stat]=(stats[stat] or 0)+1 end
	end
	local lines={}
	for stat,count in pairs(stats) do lines[#lines+1]={text=stat,count=count} end
	table.sort(lines,function(a,b) return a.text < b.text end); table.sort(notables); table.sort(keystones)
	return {version=plan.version,mode=tree.mode=="ruthless" and "Ruthless" or "Standard",preview=tree.preview,compatibleModes=tree.compatibleModes,used=#plan.nodes,budget=plan.budget,bonus=bonus,remaining=plan.budget+bonus-#plan.nodes,budgetReachable=reachable,budgetWarning=budgetWarning,pointsBeforeGrant=pointsBeforeGrant,
		counts=counts,notables=notables,keystones=keystones,stats=lines,source=tree.source,sourceCommit=tree.commit,
		limitations={"Atlas plans do not modify character DPS or EHP.","Stat lines are grouped verbatim, not combined into effective map odds. Keystone interactions are not simulated.","Budget is supplied progression, not imported account completion. Small optimized routes can be exact; larger routes use a heuristic."}}
end
function M.export(plan)
	return json.encode({schemaVersion=1,atlasPlan=M.validate(plan)})
end
function M.import(raw,version,id,title,budget)
	text(raw,64000,"Atlas import")
	raw=raw:match("^%s*(.-)%s*$")
	if raw:match("^%s*{") then
		local decoded=assert(json.decode(raw),"Invalid Atlas JSON")
		assert(decoded.schemaVersion == 1,"Unsupported Atlas export version")
		local plan=M.validate(decoded.atlasPlan); plan.id=id or plan.id; plan.title=title or plan.title
		return M.validate(plan)
	end
	assert(M.tree(version).mode~="ruthless","Official Ruthless Atlas links are not yet verified; import a saved plan JSON instead.")
	local host,path=raw:match("^https://([^/]+)/(.+)$")
	assert(host=="www.pathofexile.com" or host=="pathofexile.com","Paste plan JSON or an official pathofexile.com Atlas link. Other planners must export an official link first.")
	path=path:match("^[^?#]+") or ""
	local token=path:match("^fullscreen%-atlas%-skill%-tree/([%w_%-=]+)/?$")
	assert(token,"This is not a supported official Atlas tree link. Choose the matching bundled version before importing.")
	local bytes=common.base64.decode(token:gsub("-","+"):gsub("_","/"))
	assert(bytes and #bytes >= 9 and bytes:sub(1,5) == string.char(0,0,0,6,0),"Unsupported Atlas URL format or game mode")
	local count=bytes:byte(6)*256+bytes:byte(7)
	assert(count <= 300 and #bytes == 9+count*2 and bytes:sub(-2) == string.char(0,0),"Unsupported or truncated Atlas URL")
	local ids={}; for i=1,count do ids[i]=bytes:byte(6+i*2)*256+bytes:byte(7+i*2) end
	return M.validate({id=id or "atlas-import",title=title or "Imported Atlas",version=version,budget=budget or M.tree(version).maxPoints,nodes=ids})
end
function M.url(plan)
	plan=M.validate(plan)
	assert(M.tree(plan.version).mode~="ruthless","Official Ruthless Atlas links are not yet verified; use Copy plan instead.")
	local ids=copyTable(plan.nodes); ids[#ids+1]=M.tree(plan.version).start; table.sort(ids)
	local bytes={0,0,0,6,0,math.floor(#ids/256),#ids%256}
	for _,id in ipairs(ids) do bytes[#bytes+1]=math.floor(id/256); bytes[#bytes+1]=id%256 end
	bytes[#bytes+1]=0; bytes[#bytes+1]=0
	return "https://www.pathofexile.com/fullscreen-atlas-skill-tree/"..common.base64.encode(string.char(unpack(bytes))):gsub("+","-"):gsub("/","_")
end
function M.new(build)
	local self={plans={},build=build}
	local function shortTitle(title)
		title=title:gsub("%s+"," ")
		return #title>24 and title:sub(1,21).."..." or title
	end
	function self:Load(xml)
		local ok,plans=pcall(function()
			local raw=table.concat(xml); assert(#raw <= 2*1024*1024,"Atlas metadata too large")
			if not raw:match("%S") then return {} end
			local decoded=assert(json.decode(raw)); assert(decoded.schemaVersion == 1); array(decoded.plans,math.huge,"saved Atlas plans")
			local result,ids={},{}
			for _,plan in ipairs(decoded.plans) do local entry=M.validate(plan); assert(not ids[entry.id]); ids[entry.id]=true; result[#result+1]=entry end
			return result
		end)
		if ok then self.plans=plans else self.unreadable=copyTable(xml); self.warning="Atlas metadata could not be read; it is preserved unchanged." end
	end
	function self:Save(xml)
		if self.unreadable then for _,entry in ipairs(self.unreadable) do xml[#xml+1]=type(entry) == "table" and copyTable(entry) or entry end
		elseif #self.plans > 0 then xml[#xml+1]=json.encode({schemaVersion=1,plans=self.plans}) end
	end
	function self:Upsert(plan)
		assert(not self.unreadable,self.warning)
		local entry=M.validate(plan); local replacement=copyTable(self.plans); local found
		local reachable,why=budgetReachabilityChecked(entry)
		if reachable==false then
			local old;for _,saved in ipairs(self.plans) do if saved.id==entry.id then old=saved;break end end
			local unchanged=old and old.version==entry.version and old.budget==entry.budget and #old.nodes==#entry.nodes
			if unchanged then for i,id in ipairs(entry.nodes) do if old.nodes[i]~=id then unchanged=false;break end end end
			assert(unchanged,why)
		end
		for i,old in ipairs(replacement) do if old.id == entry.id then replacement[i]=entry; found=true; break end end
		if not found then replacement[#replacement+1]=entry end
		for _,other in ipairs(replacement) do
			if other.progression and other.progression.previousId==entry.id then
				assert(other.version==entry.version,"'"..shortTitle(other.title).."' follows this plan. Change its previous plan first.")
			end
		end
		local seen={[entry.id]=true};local previous=entry.progression and entry.progression.previousId
		while previous do assert(not seen[previous],"Atlas progression contains a cycle");seen[previous]=true;local nextPlan;for _,p in ipairs(replacement) do if p.id==previous then nextPlan=p end end;assert(nextPlan and nextPlan.version==entry.version,"Previous Atlas plan is missing or uses a different version");previous=nextPlan.progression and nextPlan.progression.previousId end
		assert(#json.encode(replacement) <= 2*1024*1024,"Atlas metadata too large")
		self.plans=replacement; build.modFlag=true;require("Modules.PlanningUI").kept(build,"atlas"); return entry
	end
	function self:Remove(id)
		assert(not self.unreadable,self.warning)
		for _,plan in ipairs(self.plans) do
			assert(not (plan.progression and plan.progression.previousId==id),"'"..shortTitle(plan.title).."' follows this plan. Change its previous plan first.")
		end
		for i,plan in ipairs(self.plans) do if plan.id == id then table.remove(self.plans,i); build.modFlag=true; return end end
	end
	return self
end
return M
