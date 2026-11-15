-- Recover corruption identities only when the complete legal assignment is unique.
local I={}
function I.resolve(M,model,metadata)
	local item=model.item
	if not item.corrupted or #item.implicitModLines==0 or model.initial.implicits then return end
	for _,line in ipairs(item.implicitModLines) do if line.exarch or line.eater then return end end
	if item.synthesised then return nil,"unresolved" end
	local infer=require("Modules.CraftingImport").inferRange
	local rows={};for _,line in ipairs(item.implicitModLines) do rows[#rows+1]={source=line.line,text=itemLib.applyRange(line.line,line.range or 0.5)} end
	if #rows>12 then return nil,"unresolved" end
	if item.base.implicit and type(item.base.implicit)~="string" then return nil,"unresolved" end
	local base={};for line in (item.base.implicit or ""):gmatch("[^\n]+") do base[#base+1]=line end
	local candidates,work={},0
	local baseUsed={}
	local function matchesBase(index)
		work=work+1;if work>10000 then return false end
		if index>#base then return true end
		for i,row in ipairs(rows) do if not baseUsed[i] and infer(base[index],row.text) then
			baseUsed[i]=true;if matchesBase(index+1) then return true end;baseUsed[i]=nil
		end end
		return false
	end
	local baseMatch=#base==#rows and matchesBase(1)
	if work>10000 then return nil,"unresolved" end
	local function consider(id,mod,is330)
		if #mod>#rows then return end
		local selected,ranges={},{}
		local function assign(index,exact)
			work=work+1;if work>10000 then return end
			if index>#mod then
				local indices={};for i in pairs(selected) do indices[#indices+1]=i end
				candidates[#candidates+1]={indices=indices,exact=exact,entry={id=id,range=#ranges==0 and 0.5 or #ranges==1 and ranges[1] or copyTable(ranges),corruption330=is330 or nil}}
				return
			end
			for i,row in ipairs(rows) do if not selected[i] then
				local values=infer(mod[index],row.text)
				if values then
					selected[i]=true;local n=#ranges;for _,value in ipairs(values) do ranges[#ranges+1]=value end
					assign(index+1,exact+(row.source==mod[index] and 1 or 0))
					while #ranges>n do table.remove(ranges) end;selected[i]=nil
				end
			end end
		end
		assign(1,0)
	end
	for _,entry in ipairs(model.corruptions) do
		consider(entry.id,model.byId[entry.id])
		if model.corruptions330 and model.corruptions330[entry.id] then consider(entry.id,model.corruptions330[entry.id],true) end
		if work>10000 then return nil,"unresolved" end
	end
	local used,groups,chosen,seen={},{},{},{}
	local best,solutions=-1,{}
	local function search(score)
		work=work+1;if work>10000 then return end
		local first;for i=1,#rows do if not used[i] then first=i;break end end
		if not first then
			local result=copyTable(chosen);table.sort(result,function(a,b) return a.id<b.id end)
			local key=require("dkjson").encode(result)
			if score>best then best=score;solutions={};seen={} end
			if score==best and not seen[key] then solutions[#solutions+1]=result;seen[key]=true end
			return
		end
		if #chosen==2 then return end
		for _,candidate in ipairs(candidates) do
			local legal,contains=true,false;local id=candidate.entry.id;local memberGroups=metadata[id].groups
			for _,index in ipairs(candidate.indices) do if used[index] then legal=false end;if index==first then contains=true end end
			for _,group in ipairs(memberGroups) do if groups[group] then legal=false end end
			for _,entry in ipairs(chosen) do if entry.id==id then legal=false end end
			if legal and contains then
				for _,index in ipairs(candidate.indices) do used[index]=true end
				for _,group in ipairs(memberGroups) do groups[group]=true end
				chosen[#chosen+1]=candidate.entry;search(score+candidate.exact);table.remove(chosen)
				for _,group in ipairs(memberGroups) do groups[group]=nil end
				for _,index in ipairs(candidate.indices) do used[index]=nil end
			end
		end
	end
	search(0)
	if work>10000 then return nil,"unresolved" end
	-- An unchanged natural implicit is a valid alternative to a corruption roll.
	if #solutions==0 and baseMatch then return end
	if #solutions~=1 or baseMatch then return nil,"unresolved" end
	return solutions[1]
end
return I
