-- Native item emulator and bounded recipe trials, isolated from equipped items.
local simulator=require("Modules.CraftingSimulator")
local workbench=require("Modules.CraftingWorkbench")
local pricing=require("Modules.CraftingPrices")
local ui=require("Modules.PlanningUI")
local inspect=require("Modules.CraftingInspection")
local browser=require("Classes.PlanningBrowserControl")
local tasks=require("Modules.CraftingTasks")
local Panel={ }
local pageHints={["Target conditions"]="Choose the modifiers and item properties you want.",["Simulate recipe"]="Compare modeled chances and costs before keeping a recipe.",["Craft settings"]="Advanced methods, item edits and recipe settings."}
local function button(controls,key,x,y,w,label,callback)
	controls[key]=new("ButtonControl"):ButtonControl({"TOPLEFT",nil,"TOPLEFT"},{x,y,w,24},label,function()
		local ok,err=pcall(callback)
		if not ok then main:OpenMessagePopup("Native crafting",require("Modules.PlanningUI").errorText(err)) else return err end
	end)
	ui.styleButton(controls[key])
end
local function edit(controls,key,x,y,w,h,value,prompt,limit)
	controls[key]=new("EditControl"):EditControl({"TOPLEFT",nil,"TOPLEFT"},{x,y,w,h},value or "",prompt,h>24 and "^%C\t\n" or nil,limit,nil,h > 24 and 16 or nil)
end
local function rows(lines,width)
	width=width or 388
	local result={ }
	for _,line in ipairs(lines) do
		for part in tostring(line):gmatch("[^\r\n]+") do
			part=StripEscapes(part)
			while DrawStringWidth(18,"VAR",part) > width do
				local low,high=1,#part
				while low < high do local middle=math.ceil((low+high)/2);if DrawStringWidth(18,"VAR",part:sub(1,middle)) <= width then low=middle else high=middle-1 end end
				local space=part:sub(1,low):match("^.*()%s")
				local cut=space and space > 1 and space-1 or low
				result[#result+1]={height=18,colorCodes.NORMAL..part:sub(1,cut)};part=part:sub(cut+1):gsub("^%s+","")
			end
			result[#result+1]={height=18,colorCodes.NORMAL..part}
		end
	end
	return result
end
local function label(controls,key,x,y,text)
	controls[key]=new("LabelControl"):LabelControl({"TOPLEFT",nil,"TOPLEFT"},{x,y,0,14},colorCodes.NORMAL..text)
end

function Panel.Open(build,project,layout)
	local draft=copyTable(project)
	local model=simulator.model(draft.startingItem)
	local state=draft.nativeRecipe and draft.nativeRecipe.initialState and simulator.validateState(model,draft.nativeRecipe.initialState) or copyTable(model.initial)
	local initial=copyTable(state)
	local targets=draft.nativeRecipe and copyTable(draft.nativeRecipe.targets) or { }
	local requirements=draft.nativeRecipe and draft.nativeRecipe.requirements and copyTable(draft.nativeRecipe.requirements)
	local requiredGroups=draft.nativeRecipe and draft.nativeRecipe.requiredGroups
	local controls,history,actions={},{},{}
	local ready=false
	local function changed()
		if ready then ui.draft(build,"workingCraft",draft.id) end
	end
	local configured={}
	local sequence=0
	local lastSimulation,lastSimulationRun,lastFossilComparison
	local changedAffixes={}
	local favorites=layout and (layout.favorites or layout.workbench and layout.workbench.favorites) or {}
	if layout then layout.favorites=favorites end
	if layout then layout.selectedProject=draft.id end
	local restored=layout and layout.workbench or draft.run and require("Modules.CraftingCheckpoint").validate(draft.startingItem,draft.run)
	if layout then layout.workbench=nil end
	if restored then
		state=restored.state;initial=restored.initial;targets=restored.targets;requirements=restored.requirements;requiredGroups=restored.requiredGroups
		history=restored.history;actions=restored.actions;configured=restored.configured;sequence=restored.sequence;lastSimulation=restored.lastSimulation;lastSimulationRun=restored.lastSimulationRun;lastFossilComparison=restored.lastFossilComparison
	end
	local analysis=require("Modules.CraftingAnalysis").get(build,draft,restored)
	local function syncAnalysis()
		local result=analysis.results.simulation
		lastSimulation=result and result.result;lastSimulationRun=result and result.context
		lastFossilComparison=analysis.results.fossils and analysis.results.fossils.result
	end
	syncAnalysis()
	local paletteOpen=restored and restored.paletteOpen or false
	local inspectedId=restored and restored.inspectedId
	local paletteView
	local populateAffix
	local refreshTargetOptions
	local action,overrideKey,updateCurrency
	local function actionName()
		local selected=action()
		return (selected.allflame and "Allflame " or "")..simulator.labels[selected.method]
	end
	local priceOverrides=copyTable(restored and restored.priceOverrides or {})
	local width=layout and layout.width or math.min(1120,main.screenW-40)
	local height=layout and layout.height or math.max(520,math.min(740,main.screenH-60))
	local leftWidth=math.max(416,math.min(width-400,layout and layout.craftWidth or restored and restored.craftWidth or 416))
	local itemWidth=math.min(540,width-leftWidth-64)
	local itemX=leftWidth+32+math.floor((width-leftWidth-48-itemWidth)/2)
	label(controls,"intro",16,64,"Select a currency, then click your item to craft.")
	local refreshItem=workbench.item(controls,"item",itemX,112,itemWidth,height-184,model,function() return state end,function() controls.apply:Click() end,{header=196,artSize=96,compact=true,slot=draft.slot,selectedAffix=function() return inspectedId end,changedAffixes=function() return changedAffixes end})
	controls.targetSummary=new("TextListControl"):TextListControl({"TOPLEFT",nil,"TOPLEFT"},{16,244,416,height-312},nil,{})
	local targetReason,savedResultRows,warningActive
	local function refresh(extra)
		if refreshTargetOptions then refreshTargetOptions() end
		if action and controls.price then
			local key=simulator.priceKey(action())
			if overrideKey and overrideKey~=key then priceOverrides[overrideKey]=controls.price.buf;controls.price:SetText(priceOverrides[key] or "") end
			overrideKey=key
		end
		if inspectedId then local exists;for _,entry in ipairs(state.affixes) do if entry.id==inspectedId then exists=true end end;if not exists then inspectedId=nil end end
		refreshItem()
		local lines={inspect.slots(model,state),"Target groups: "..#targets.." ("..(requiredGroups or "all").." required)"}
		for index,group in ipairs(targets) do
			local names={}
			for _,id in ipairs(group.anyOf) do local mod=simulator.context(model,state).byId[id] or model.byId[id];names[#names+1]=mod and table.concat(mod," / ") or "Unknown modifier" end
			lines[#lines+1]=index..". "..(group.negate and "Exclude " or "Require ")..(group.atLeast or 1)..": "..table.concat(names," OR ")
			if group.fractured ~= nil then lines[#lines+1]=group.fractured and "Fractured only" or "Not fractured" end
			if group.crafted ~= nil then lines[#lines+1]=group.crafted and "Crafted only" or "Not crafted" end
			if group.minRoll then lines[#lines+1]="Minimum roll: "..(group.minRoll*100).."%" end
		end
		for key,value in pairsSortByKey(requirements or {}) do
			if key=="nativeStats" then
				for _,field in ipairs(require("Modules.CraftingItemStats").fields) do if value[field[1]] then lines[#lines+1]="Minimum "..field[2]..": "..value[field[1]] end end
			else lines[#lines+1]=key:gsub("(%l)(%u)","%1 %2")..": "..tostring(value) end
		end
		controls.targetSummary.list=rows(lines)
		local workingWarning=targetReason and targetReason()
		local savedWarning=targetReason and draft.nativeRecipe and targetReason(true)
		if controls.resultSummary then
			if extra then savedResultRows=rows(extra)
			elseif not warningActive then savedResultRows=controls.resultSummary.list end
			local notices={}
			if workingWarning then notices[#notices+1]="Working item: "..workingWarning end
			if savedWarning and not workingWarning then notices[#notices+1]="Saved recipe: "..savedWarning end
			local wasWarning=warningActive;warningActive=#notices>0
			if warningActive then
				local combined=rows(notices,leftWidth-28);for _,row in ipairs(savedResultRows or {}) do combined[#combined+1]=row end
				controls.resultSummary.list=combined
				if not wasWarning then controls.resultSummary.controls.scrollBar.offset=0 end
			else controls.resultSummary.list=savedResultRows or controls.resultSummary.list end
		end
		local craftingPage=not controls.page or controls.page:GetSelValue()=="Emulate item"
		local message=craftingPage and inspectedId and "Modifier details. Your working item stays in view." or craftingPage and paletteOpen and "Find an action without leaving your working item." or extra and extra[1] or controls.page and pageHints[controls.page:GetSelValue()] or "Select a currency, then click your item to craft."
		if controls.page and controls.page:GetSelValue()=="Simulate recipe" then message="Selected action: "..actionName() end
		if workingWarning or savedWarning then message=controls.page and controls.page:GetSelValue()=="Simulate recipe" and "Implicit target unavailable; details below." or "Implicit target unavailable; see Simulate tab." end
		controls.intro.label="^7"..ui.fit(message,leftWidth,14)
		if controls.actionHint and controls.actionHint.list then
			local hint=workbench.hint(controls.method:GetSelValueByKey("val"),state,model)
			local selected=controls.option and controls.option:GetSelValue()
			local id=selected and selected.action and selected.action.modId
			if selected and selected.action and selected.action.essenceId then
				for _,essence in ipairs(model.essences) do if essence.id==selected.action.essenceId and essence.maxModLevel then
					hint="Other random modifiers are restricted to level "..essence.maxModLevel.." or below."
				end end
			end
			if selected and selected.action and selected.action.essenceId=="Metadata/Items/Currency/CurrencyEssenceUber1" then
				hint="Delirium Fog effects are not modeled in build calculations."
			end
			if id and id:match("^bench:partial%-") or simulator.hasPartialLock(simulator.context(model,state),state) and workbench.available(controls.method:GetSelValueByKey("val"),state,model) then
				local method=controls.method:GetSelValueByKey("val")
				hint=(method=="harvest_reforge" or method=="harvest_augment") and "Experimental lock: some protection selections may leave no legal Harvest outcome."
					or method=="bench_reroll" and "Experimental lock: protection is selected once; some selections may leave too few removable modifiers."
					or "Experimental partial lock: random protection is modeled with assumed equal weights."
			end
			controls.actionHint.list=ui.rows({hint},leftWidth-30,14)
		end
	end
	label(controls,"methodLabel",16,64,"Crafting action")
	local methods={ }
	for _,method in ipairs(simulator.methods) do methods[#methods+1]={label=simulator.labels[method],val=method} end
	controls.method=new("DropDownControl"):DropDownControl({"TOPLEFT",nil,"TOPLEFT"},{16,84,416,24},methods)
	label(controls,"optionLabel",16,124,"Action options (dropdown search is available)")
	controls.option=new("DropDownControl"):DropDownControl({"TOPLEFT",nil,"TOPLEFT"},{16,144,416,24},{})
	local stateAwareOptions={bench=true,essence=true,harvest_reforge=true,harvest_augment=true,harvest_resistance=true}
	local function updateOptions()
		local method=controls.method:GetSelValueByKey("val")
		local previous=controls.option:GetSelValue()
		local reference=stateAwareOptions[method] and configured[method] or previous and previous.action
		local choices=simulator.actionOptions(model,state,method);local selected=1;local found=false
		for i,choice in ipairs(choices) do if tableDeepEquals(choice.action,reference) then selected=i;found=true;break end end
		controls.option:SetList(choices)
		if #choices>0 then controls.option:SetSel(selected,true) else controls.option.selIndex=1 end
		if #choices>0 and stateAwareOptions[method] and (not configured[method] or not found) then
			local old=configured[method];configured[method]=copyTable(choices[selected].action)
			if old and old.allflame and old.allflame.auto then configured[method].allflame=copyTable(old.allflame) end
		end
	end
	controls.method.selFunc=function() updateOptions();changed();refresh() end
	controls.option.enabled=function() return #controls.option.list > 0 end
	controls.option.selFunc=function()
		local method=controls.method:GetSelValueByKey("val");local previous=configured[method]
		local selected=controls.option:GetSelValue()
		configured[method]=stateAwareOptions[method] and selected and copyTable(selected.action) or nil
		if previous and previous.allflame and previous.allflame.auto and selected then
			configured[method]=copyTable(selected.action);configured[method].allflame=copyTable(previous.allflame)
		end
		changed()
		refresh()
	end
	label(controls,"seedLabel",16,184,"Seed")
	edit(controls,"seed",16,204,130,24,"104729","Seed",12)
	action=function()
		local method=controls.method:GetSelValueByKey("val")
		local option=controls.option:GetSelValue()
		return copyTable(configured[method] or option and option.action or {method=method})
	end
	local function chooseMethod(method)
		paletteOpen=false;inspectedId=nil;controls.method:SelByValue(method,"val");updateOptions();changed();refresh()
	end
	local function palette()
		paletteOpen=true;inspectedId=nil;paletteView.refresh();refresh()
		return controls.paletteSearch
	end
	local function pickTarget(id)
		assert(#targets<6,"Use up to six target groups")
		local kind=simulator.context(model,state).byId[id].type;targets[#targets+1]={anyOf={id},scope=(kind=="Exarch" or kind=="Eater" or kind=="Corrupted") and "implicit" or "explicit"};changed();refresh()
	end
	populateAffix=function(id)
		local found;for _,entry in ipairs(state.affixes) do if entry.id==id then found=entry end end
		if not found then return end
		controls.affixFacts.list=ui.rows(inspect.modDetails(simulator.context(model,state),id,found),leftWidth-30)
		controls.affixFacts.controls.scrollBar.offset=0
		local entries={}
		for _,method in ipairs(found.crafted and {"remove_crafted","divine"} or found.fractured and {"divine","bench"} or {"divine","annul","bench"}) do
			entries[#entries+1]={val=method,label=simulator.labels[method]}
		end
		controls.affixAction:SetList(entries)
	end
	controls.itemMods.onClick=function(row)
		local id=row and row.line.affixId;if not id then return end
		inspectedId=id;paletteOpen=false;controls.page:SelByValue("Emulate item");populateAffix(id);refresh()
	end

	button(controls,"apply",162,204,130,"Apply currency",function()
		sequence=sequence+1
		local craft=action();local usedSeed=assert(tonumber(controls.seed.buf),"Invalid seed")+sequence-1
		local result=simulator.perform(draft.startingItem,craft,usedSeed,state,build.spec.treeVersion)
		local function keep(nextState,index)
			changedAffixes={};local previous={};for _,entry in ipairs(state.affixes) do previous[entry.id]=require("dkjson").encode(entry) end
			for _,entry in ipairs(nextState.affixes) do if previous[entry.id]~=require("dkjson").encode(entry) then changedAffixes[entry.id]=true end end
			ui.draft(build,"workingCraft",draft.id)
			history[#history+1]=copyTable(state);if #history > 40 then table.remove(history,1) end
			if index then craft.allflame=craft.allflame or copyTable(result.allflame.settings);craft.allflame.choiceIndex=index end
			local label=craft.method=="essence" and "Essence: "..workbench.actionLabel(craft,model) or simulator.labels[craft.method] or "craft"
			state=nextState;actions[#actions+1]=craft;updateOptions();refresh({"Applied "..label..". Select another currency or undo."})
		end
		if result.choices and #result.choices > 1 then
			local popup={};local choices={}
			for i=1,#result.choices do choices[i]={label="Ghost outcome "..i,val=i} end
			popup.choice=new("DropDownControl"):DropDownControl({"TOPLEFT",nil,"TOPLEFT"},{16,28,628,24},choices)
			local showChoice=workbench.item(popup,"preview",16,70,628,300,model,function()
				return result.choices[popup.choice:GetSelValueByKey("val")].state
			end)
			popup.choice.selFunc=showChoice;showChoice()
			button(popup,"keep",16,390,200,"Keep ghost outcome",function() local index=popup.choice:GetSelValueByKey("val");keep(result.choices[index].state,index);main:ClosePopup() end)
			button(popup,"close",528,390,116,"Cancel",function() main:ClosePopup() end)
			main:OpenPopup(660,440,"Allflame outcomes",popup,nil,nil,"close")
		else keep(result.state) end
	end)
	button(controls,"undo",308,204,124,"Undo currency",function() assert(#history > 0,"No currency action to undo"); state=table.remove(history);table.remove(actions);changedAffixes={};ui.draft(build,"workingCraft",draft.id);updateOptions();refresh() end)
	button(controls,"history",232,390,200,"Item history",function()
		require("Classes.CraftingHistoryControl").Open(model,state,history,actions,function(saved,count)
			state=saved;for i=1,count do table.remove(history);table.remove(actions) end;changed();updateOptions();refresh({"Restored an earlier working item."})
		end)
	end)
	button(controls,"compareItem",16,238,200,"Before / after",function()
		local entries={};for i,line in ipairs(inspect.diff(model,initial,state)) do entries[#entries+1]={id=i,label=line,details={line,"Compared with the recipe starting item."}} end
		browser.Open("Starting item versus working item",entries)
	end)
	button(controls,"inspectItem",16,338,416,"Inspect affixes and slots",function()
		local current=simulator.context(model,state)
		local entries={};for _,entry in ipairs(state.affixes) do local id=entry.id;entries[#entries+1]={id=id,label=table.concat(simulator.entryMod(current,entry)," / "),category=current.byId[id].type,details=function() return inspect.modDetails(current,id,entry) end} end
		browser.Open(inspect.slots(model,state),entries,{action="Use as target",choose=function(entry) pickTarget(entry.id);controls.page:SelByValue("Target conditions") end})
	end)
	button(controls,"allflame",16,410,416,"Allflame settings (3.29)",function()
		local craft=action();local profile=craft.allflame or {};local popup={}
		popup.mode=new("DropDownControl"):DropDownControl({"TOPLEFT",nil,"TOPLEFT"},{16,28,296,24},{"3.29 client data","Observed override"})
		popup.mode:SelByValue(profile.outcomes and not profile.auto and "Observed override" or "3.29 client data")
		popup.upgrade=new("DropDownControl"):DropDownControl({"TOPLEFT",nil,"TOPLEFT"},{328,28,300,24},{{label="Ship: basic",val=0},{label="Ship: one upgrade",val=1},{label="Ship: fully upgraded",val=2}})
		popup.upgrade:SelByValue(profile.upgradeTier or 2,"val")
		popup.preview=new("TextListControl"):TextListControl({"TOPLEFT",nil,"TOPLEFT"},{16,70,628,100},nil,{})
		local function automatic() return popup.mode:GetSelValue() == "3.29 client data" end
		local function updateProfile()
			local copy=copyTable(craft);copy.allflame={auto=true,upgradeTier=popup.upgrade:GetSelValueByKey("val")}
			local ok,value=pcall(simulator.allflameProfile,model,state,copy)
			popup.preview.list=rows(ok and {value.outcomes.." ghost outcomes",string.format("Intangibility gain: %d-%d%% | Sulphur: %d",value.gainMin,value.gainMax,value.sulphur),"Choose the ship upgrades you have unlocked."} or {tostring(value):match("^[^\n]+")})
		end
		popup.upgrade.selFunc=updateProfile;popup.preview.shown=automatic;popup.upgrade.enabled=automatic
		edit(popup,"outcomes",16,80,140,24,tostring(profile.outcomes or ""),"Outcomes 1-4",12)
		edit(popup,"gainMin",172,80,140,24,tostring(profile.gainMin or ""),"Min gain %",12)
		edit(popup,"gainMax",328,80,140,24,tostring(profile.gainMax or ""),"Max gain %",12)
		edit(popup,"sulphur",16,120,296,24,tostring(profile.sulphur or ""),"Dead Man's Sulphur cost",12)
		for _,key in ipairs({"outcomes","gainMin","gainMax","sulphur"}) do popup[key].shown=function() return not automatic() end end
		ui.description(popup,"historical",16,178,628,36,{"Allflame is not core in 3.30. These settings model historical or hypothetical crafting."},14)
		label(popup,"policy",16,222,"Recipes prefer the most matching target groups; ties keep the first.")
		button(popup,"use",16,266,200,"Use Allflame settings",function()
			local values
			if automatic() then
				values={auto=true,upgradeTier=popup.upgrade:GetSelValueByKey("val")}
				local copy=copyTable(craft);copy.allflame=values;simulator.allflameProfile(model,state,copy)
			else
				values={};for _,key in ipairs({"outcomes","gainMin","gainMax","sulphur"}) do values[key]=assert(tonumber(popup[key].buf),"Enter all four observed settings") end
				assert(values.outcomes == math.floor(values.outcomes) and values.outcomes >= 1 and values.outcomes <= 4,"Choose one to four outcomes")
				assert(values.gainMin >= 0 and values.gainMax >= values.gainMin and values.gainMax <= 100,"Invalid Intangibility gain range")
			end
			if #targets > 0 then values.preferredTargets=copyTable(targets) end
			craft.allflame=values;configured[craft.method]=craft;changed();main:ClosePopup();refresh({"Allflame settings enabled for "..simulator.labels[craft.method]})
		end)
		button(popup,"disable",232,266,200,"Use ordinary currency",function() craft.allflame=nil;configured[craft.method]=craft;changed();main:ClosePopup() end)
		button(popup,"close",448,266,116,"Cancel",function() main:ClosePopup() end)
		updateProfile();main:OpenPopup(660,318,"Allflame settings (3.29)",popup,nil,nil,"close")
	end)
	button(controls,"configure",16,231,416,"Configure fossil combination / donor item",function()
		local method=controls.method:GetSelValueByKey("val")
		local popup={}
		if method == "fossil" then
			require("Classes.CraftingFossilControl").Open(model,configured.fossil,function(craft) configured.fossil=craft;changed() end)
			return
		elseif method == "awakener" or method == "recombine" or method == "recombine_predictable" then
			edit(popup,"donor",16,36,608,170,"","Paste the donor item",24000)
			if method == "recombine_predictable" then
				edit(popup,"chance",16,216,180,24,"","In-game success %",12)
				label(popup,"selectionHint",208,221,"Exact target IDs select mods from each input.")
			end
			button(popup,"use",16,260,180,"Use donor",function()
				local craft={method=method,donorItem=popup.donor.buf}
				if method == "recombine_predictable" then
					local donor=simulator.model(popup.donor.buf);local selected={left={},right={}}
					for _,group in ipairs(targets) do
						assert(#group.anyOf == 1 and not group.negate and (group.atLeast or 1) == 1 and (group.scope or "explicit") == "explicit","Use exact explicit targets without alternatives for predictable selections")
						local id=group.anyOf[1];local side
						for key,input in pairs({left=state,right=donor.initial}) do for _,entry in ipairs(input.affixes) do if entry.id == id and not entry.fractured then assert(not side,"Selected modifier appears on both inputs; use the MCP action to select its input explicitly");side=key end end end
						assert(side,"Each selected target must be present on one input");selected[side][#selected[side]+1]=id
					end
					assert(#selected.left > 0 and #selected.right > 0,"Select at least one exact target from each input")
					craft.selectedMods=selected;craft.reportedSuccessChance=assert(tonumber(popup.chance.buf),"Enter the game's displayed success percentage")
					assert(craft.reportedSuccessChance >= 0 and craft.reportedSuccessChance <= 100,"Success percentage must be between 0 and 100")
				end
				configured[method]=craft;changed();main:ClosePopup()
			end)
		else error("Select a fossil, Awakener's Orb or recombination first") end
		button(popup,"close",508,260,116,"Cancel",function() main:ClosePopup() end)
		main:OpenPopup(640,310,method=="fossil" and "Fossil combination" or "Craft options",popup,nil,nil,"close")
	end)
	label(controls,"targetLabel",16,262,"Target modifier (add several for AND conditions)")
	controls.target=new("DropDownControl"):DropDownControl({"TOPLEFT",nil,"TOPLEFT"},{16,282,416,24},{})
	local targetModel
	refreshTargetOptions=function()
		local current=simulator.context(model,state);if current==targetModel then return end;targetModel=current
		local selected=controls.target:GetSelValue();selected=selected and selected.val
		local mods={}
		for _,entry in ipairs(current.mods) do mods[#mods+1]={label=entry.mod.type.." | "..table.concat(entry.mod," / ").." | iLvl "..entry.mod.level,val=entry.id} end
		for _,entry in ipairs(current.essences) do mods[#mods+1]={label=entry.name.." guaranteed mod",val=entry.modId} end
		for id in pairs(current.special) do local mod=current.byId[id];if mod.type=="Prefix" or mod.type=="Suffix" or mod.type=="Corrupted" or mod.type=="Exarch" or mod.type=="Eater" then mods[#mods+1]={label=mod.type.." | "..table.concat(mod," / "),val=id} end end
		controls.target:SetList(mods);controls.target.selIndex=1;if selected then controls.target:SelByValue(selected,"val") end
	end
	refreshTargetOptions()
	button(controls,"targetPicker",16,188,416,"Find target modifiers",function()
		require("Classes.CraftingModifierControl").Open(model,copyTable(state),{choose=pickTarget,canAlternative=function() return #targets>0 end,alternative=function(id)
			local group=assert(targets[#targets],"Add a target group first");assert(require("Modules.CraftingModifiers").scope(simulator.context(model,state).byId[id])==(group.scope or "explicit"),"Choose the same explicit/implicit scope, or create a separate group");for _,value in ipairs(group.anyOf) do if value==id then return end end;assert(#group.anyOf<30,"Use up to thirty alternatives per group");group.anyOf[#group.anyOf+1]=id;changed();refresh()
		end,present=function(id)
			assert(not state.destroyed and not state.veil,"Reset destruction or finish the unveil first")
			local next=copyTable(state);if next.rarity=="NORMAL" then next.rarity="RARE" end
			next.affixes[#next.affixes+1]={id=id,range=0.5,crafted=false};state=simulator.validateState(model,next);initial=copyTable(state);history={};actions={};analysis:clearSimulation();syncAnalysis();changedAffixes={};ui.draft(build,"workingCraft",draft.id);updateOptions();refresh({"Modifier staged on a hypothetical item. Working actions reset."})
		end})
	end)
	button(controls,"addTarget",16,310,132,"Add target",function()
		assert(#targets < 6,"Use up to six target groups")
		local id=controls.target:GetSelValueByKey("val");local kind=simulator.context(model,state).byId[id].type
		targets[#targets+1]={anyOf={id},scope=(kind == "Exarch" or kind == "Eater" or kind == "Corrupted") and "implicit" or "explicit"};changed();refresh()
	end)
	button(controls,"alternative",160,310,132,"Add alternative",function()
		local group=assert(targets[#targets],"Add a target group first")
		assert(#group.anyOf < 30,"Use up to thirty alternatives per group")
		group.anyOf[#group.anyOf+1]=controls.target:GetSelValueByKey("val");changed();refresh()
	end)
	button(controls,"clearTargets",304,310,128,"Clear targets",function() targets={};changed();refresh() end)
	label(controls,"trialsLabel",16,354,"Trials / action budget per trial")
	edit(controls,"trials",16,374,130,24,"200","Trials",5)
	edit(controls,"budget",162,374,130,24,"20","Action budget",5)
	label(controls,"priceLabel",16,418,"Action override / unit / base cost")
	edit(controls,"price",16,438,130,24,"","Override price",16)
	edit(controls,"currency",162,438,130,24,"chaos","Unit",24)
	edit(controls,"baseCost",308,438,124,24,"","Base cost",16)
	local function capturedSettings(request)
		local options=request.options
		return "Action limit: "..options.maxActions.." per trial | seed "..options.seed
	end
	local function showSimulationResult(result,captured)
		local lines={string.format("Modeled successes: %d / %d (%.2f%%)",result.successes,result.trials,result.successChance),
			result.meanCost~=nil and string.format("Mean spent: %.2f %s",result.meanCost,result.costCurrency) or "Cost unavailable: some executed actions have no supplied price.",
			captured.label,capturedSettings(captured),
			string.format("95%% sampling interval: %.2f%% to %.2f%%",result.confidenceLow,result.confidenceHigh),string.format("Mean attempted actions: %.2f",result.meanActions)}
		local warnings=result.warnings or simulator.recipeWarnings(captured.recipe)
		for i,warning in ipairs(warnings) do table.insert(lines,1+i,"Model note: "..warning.message) end
		if result.treeVersion then table.insert(lines,2+#warnings,"Build tree: "..(treeVersions[result.treeVersion] and treeVersions[result.treeVersion].display or result.treeVersion).." (context only) | crafting data: "..tostring(result.dataPatch)) end
		if result.priceSource then lines[#lines+1]="Quotes: "..result.priceSource.." | "..os.date("%Y-%m-%d",result.priceQuotedAt) end
		if result.actionPriceOverridesSupplied then
			lines[#lines+1]=result.actionPriceOverridesApplied>0 and "Includes selected-action price overrides." or "Selected-action override was not used by this recipe."
		elseif result.priceOverridesSupplied then lines[#lines+1]="Includes resource price overrides." end
		lines[#lines+1]="Result uses the captured starting state."
		if result.resourceUsage then
			lines[#lines+1]="Modeled ingredients and services (all trials)"
			for _,entry in ipairs(result.resourceUsage) do lines[#lines+1]=string.format("%s%s: %.12g total | %.3g per trial",entry.kind=="service" and "Service: " or "",entry.name,entry.amount,entry.meanPerTrial) end
			if #result.resourceUsage==0 then lines[#lines+1]="No resources or services used." end
			lines[#lines+1]="Starting-item cost is separate. Price overrides do not change quantities."
		else
			for key,count in pairsSortByKey(result.currencySpent) do lines[#lines+1]=pricing.describe(key,simulator.context(model,state))..": "..count.." priced uses" end
		end
		for message,count in pairsSortByKey(result.transitionErrors) do lines[#lines+1]="Failed transitions: "..count.." | "..message end
		refresh(lines)
	end
	local function startSimulation(request)
		local captured=copyTable(request)
		local options=copyTable(captured.options)
		analysis:start("simulation",captured,function(checkpoint)
			options.checkpoint=checkpoint;return simulator.simulate(captured.raw,copyTable(captured.recipe),options)
		end)
	end
	local function showSimulation(recipe,fromInitial)
		local budget=assert(tonumber(controls.budget.buf),"Invalid action budget")
		local actionPrices=pricing.actionOverride(simulator.priceKey(action()),
			controls.price.buf~="" and assert(tonumber(controls.price.buf),"Invalid action price") or nil)
		local options={retainSuccesses=10,treeVersion=build.spec.treeVersion,baseCost=controls.baseCost.buf ~= "" and assert(tonumber(controls.baseCost.buf),"Invalid starting item cost") or 0,trials=assert(tonumber(controls.trials.buf),"Invalid trial count"),maxActions=budget,seed=assert(tonumber(controls.seed.buf),"Invalid seed"),
			initialState=copyTable(fromInitial and (recipe.initialState or model.initial) or state),actionPrices=actionPrices,priceBook=draft.priceBook and copyTable(draft.priceBook),currency=controls.currency.buf}
		startSimulation({raw=draft.startingItem,recipe=recipe,options=options,label=fromInitial and "Saved recipe | original starting item" or "Selected action: "..actionName()})
	end
	button(controls,"simulate",16,486,200,"Simulate action",function()
		local a=action();local attempts=assert(tonumber(controls.budget.buf),"Invalid budget");a.maxAttempts=math.min(200,attempts); a.untilTargets=#targets > 0 and copyTable(targets) or nil;a.untilRequirements=(requirements and copyTable(requirements) or nil)
		showSimulation({steps={a},targets=copyTable(targets),requirements=(requirements and copyTable(requirements) or nil),requiredGroups=requiredGroups},false)
	end)
	button(controls,"runRecipe",232,486,200,"Simulate saved recipe",function() assert(draft.nativeRecipe,"This project has no saved native recipe"); showSimulation(draft.nativeRecipe,true) end)
	button(controls,"compareRecipes",16,354,200,"Compare recipes",function()
		assert(#targets>0 or requirements and next(requirements),"Choose target modifiers or item conditions first")
		require("Classes.CraftingCompareControl").Open(build,draft.startingItem,copyTable(state),copyTable(targets),requirements and copyTable(requirements),requiredGroups,action(),draft.nativeRecipe,
			{trials=assert(tonumber(controls.trials.buf)),budget=assert(tonumber(controls.budget.buf)),seed=assert(tonumber(controls.seed.buf)),currency=controls.currency.buf,treeVersion=build.spec.treeVersion,priceBook=draft.priceBook and copyTable(draft.priceBook)})
	end)
	button(controls,"resourcePrices",232,266,200,"Resource prices",function()
		local books={};for _,project in ipairs(build.savers.CraftingProjects.projects) do if project.id~=draft.id and project.priceBook and next(project.priceBook.values) then books[#books+1]=project end end
		local crafts={action()};for _,step in ipairs(draft.nativeRecipe and draft.nativeRecipe.steps or {}) do crafts[#crafts+1]=step end
		require("Classes.CraftingPricesControl").Open(simulator.context(model,state),state,crafts,draft.priceBook,controls.currency.buf,function(book)
			if controls.currency.buf~=book.currency then controls.currency:SetText(book.currency);updateCurrency() end
			draft.priceBook=book;if draft.run then draft.run.settings.currency=book.currency end;draft=copyTable(build.savers.CraftingProjects:Upsert(draft))
			ui.kept(build,"craftingPrices");refresh({"Resource prices kept in this build. Use build Save to persist."})
		end,books,draft.nativeRecipe and (draft.nativeRecipe.initialState or model.initial))
	end)
	button(controls,"keepRecipe",16,530,200,"Keep actions as recipe",function()
		assert(#actions > 0,"Apply a crafting action first")
		draft.nativeRecipe=simulator.validateRecipe({steps=copyTable(actions),targets=copyTable(targets),requirements=(requirements and copyTable(requirements) or nil),requiredGroups=requiredGroups,initialState=copyTable(initial),rarity=state.rarity})
		draft.targetItem=simulator.toItem(model,state).raw
		build.savers.CraftingProjects:Upsert(draft)
		refresh({"Native recipe and target kept in this build. Use build Save to persist."})
	end)
	button(controls,"editRecipe",16,574,200,"Recipe routes",function()
		local recipe=draft.nativeRecipe or {steps=copyTable(actions),targets=copyTable(targets),requirements=(requirements and copyTable(requirements) or nil),requiredGroups=requiredGroups,initialState=copyTable(initial)}
		require("Classes.CraftingRecipeControl").Open(recipe,action(),function(result) draft.nativeRecipe=result;build.savers.CraftingProjects:Upsert(draft);refresh({"Recipe kept. Use build Save to persist."}) end,simulator.context(model,state))
	end)
	button(controls,"targetConditions",16,650,416,"Target counts, rolls and item properties",function()
		require("Classes.CraftingTargetControl").Open(targets,requirements,requiredGroups,function(groups,properties,count) targets=groups;requirements=properties;requiredGroups=count;changed();refresh() end,0)
	end)
	controls.targetConditions.width=200;controls.targetConditions.label="Item properties"
	button(controls,"targetGroups",232,226,200,"Edit target groups",function()
		require("Classes.CraftingTargetGroupsControl").Open(model,state,targets,requirements,requiredGroups,function(groups,properties,count) targets=groups;requirements=properties;requiredGroups=count;changed();refresh() end)
	end)
	local function showFossilComparison()
		assert(lastFossilComparison,"Run a fossil comparison first")
		require("Classes.CraftingFossilCompareControl").Open(lastFossilComparison,function(ids)
			configured.fossil={method="fossil",fossils=ids};changed();controls.method:SelByValue("fossil","val");updateOptions()
			refresh({"Selected fossil combination. No currency was spent; the item is unchanged."})
		end)
	end
	button(controls,"fossilResults",232,310,200,"Fossil results",showFossilComparison)
	button(controls,"optimize",16,618,200,"Compare fossil subsets",function()
		local selected=action();assert(selected.method == "fossil" and selected.fossils,"Configure a fossil combination first")
		local options={priceBook=draft.priceBook and copyTable(draft.priceBook),currency=controls.currency.buf,treeVersion=build.spec.treeVersion,fossils=copyTable(selected.fossils),initialState=copyTable(state),maxSockets=#selected.fossils,requirements=requirements and copyTable(requirements),requiredGroups=requiredGroups,trials=assert(tonumber(controls.trials.buf)),seed=assert(tonumber(controls.seed.buf))}
		local captured=copyTable(targets)
		analysis:start("fossils",nil,function(checkpoint) options.checkpoint=checkpoint;return simulator.optimizeFossils(draft.startingItem,captured,options) end)
	end)
	local function showOddsResult(result)
		local lines={string.format("Target chance under model: %.6f%%",result.successChance),result.exactFor or result.estimateFor}
		for i,warning in ipairs(result.warnings or {}) do table.insert(lines,1+i,"Model note: "..warning.message) end
		if result.treeVersion then lines[#lines+1]="Build tree: "..(treeVersions[result.treeVersion] and treeVersions[result.treeVersion].display or result.treeVersion).." (context only) | crafting data: "..tostring(result.dataPatch) end
		if result.sampled then lines[#lines+1]=string.format("%d trials | 95%% interval %.2f%% to %.2f%%",result.trials,result.confidenceLow,result.confidenceHigh) end
		for _,entry in ipairs(result.outcomes) do if entry.matches then lines[#lines+1]=string.format("%.6f%% | %s",entry.chance,entry.text or "Finite item outcome") end end
		refresh(lines)
	end
	button(controls,"exact",232,574,200,"Calculate action odds",function()
		local craft=action();local captured=copyTable(state);local capturedTargets=copyTable(targets)
		local options={trials=assert(tonumber(controls.trials.buf)),seed=assert(tonumber(controls.seed.buf)),treeVersion=build.spec.treeVersion,requirements=requirements and copyTable(requirements),requiredGroups=requiredGroups}
		analysis:start("odds",nil,function(checkpoint)
			options.checkpoint=checkpoint;return simulator.calculate(draft.startingItem,craft,capturedTargets,captured,options)
		end)
	end)
	button(controls,"distribution",448,height-48,140,"Results / distribution",function()
		local result=assert(lastSimulation,"Run a simulation first")
		local request=lastSimulationRun and copyTable(lastSimulationRun)
		local lines={{height=24,"Attempted actions per trial (all trials, including failures)"}}
		for i,warning in ipairs(result.warnings or request and simulator.recipeWarnings(request.recipe) or {}) do table.insert(lines,i,{height=24,"Model note: "..warning.message}) end
		for _,bucket in ipairs(result.actionDistribution) do
			lines[#lines+1]={height=20,string.format("%4d | %s %d trials, %d successes",bucket.actions,string.rep("|",math.max(1,math.floor(bucket.trials/result.trials*50))),bucket.trials,bucket.successes)}
		end
		lines[#lines+1]={height=26,"Trials stopped at the action budget: "..result.budgetExhausted}
		lines[#lines+1]={height=24,"Hypothetical items destroyed: "..result.destroyedTrials}
		lines[#lines+1]={height=24,"Spending percentiles include capped failures. They are not the cost of guaranteed success."}
		local function show(title,values)
			if not values then return end
			lines[#lines+1]={height=26,title}
			for _,key in ipairs({"p10","p25","p50","p75","p90","p95","p99"}) do lines[#lines+1]={height=20,key..": "..string.format("%.2f",values[key])} end
		end
		show("Actions among successful trials only",result.successfulActionQuantiles)
		show("Spending across all trials ("..result.costCurrency..")",result.spendingQuantiles)
		show("Spending among successful trials only",result.successfulSpendingQuantiles)
		if result.recovery then lines[#lines+1]={height=24,string.format("Recovery: %d restarted bases | %d stopped | %d set aside; no salvage proceeds assumed",result.recovery.restarts,result.recovery.stopped,result.recovery.salvaged)} end
		lines[#lines+1]={height=26,"Final modifier frequencies (all trials / successful trials)"}
		for id,bucket in pairsSortByKey(result.affixDistribution or {}) do
			lines[#lines+1]={height=22,string.format("%d / %d | %s",bucket.trials,bucket.successes,model.byId[id] and table.concat(model.byId[id]," / ") or id)}
		end
		for i,route in pairsSortByKey(result.routeCounts) do lines[#lines+1]={height=24,string.format("Step %d: %d visits, %d actions, %d success routes, %d failure routes",i,route.visits,route.executed,route.success,route.failure)} end
		local popup={}
		local resultHeight=math.max(420,math.min(650,main.screenH-60))
		local display={};for _,line in ipairs(lines) do for _,row in ipairs(require("Modules.PlanningUI").rows({line[1]},798)) do display[#display+1]=row end end;lines=display
		local cardWidth=195
		ui.card(popup,"successCard",16,28,cardWidth,"SUCCESS",string.format("%.1f%%",result.successChance),result.successes.." / "..result.trials.." trials")
		ui.card(popup,"attemptCard",227,28,cardWidth,"MEAN ACTIONS",string.format("%.1f",result.meanActions),"All trials, including failures")
		ui.card(popup,"costCard",438,28,cardWidth,"MEAN SPENDING",result.meanCost and string.format("%.2f",result.meanCost) or "Not priced",result.meanCost and result.costCurrency or "Unpriced actions")
		ui.card(popup,"intervalCard",649,28,195,"95% INTERVAL",string.format("%.1f-%.1f%%",result.confidenceLow,result.confidenceHigh),"Sampling uncertainty")
		local precision={}
		if result.warnings and #result.warnings>0 then precision[#precision+1]="Model notes are listed with the distribution below." end
		if request then precision[#precision+1]=request.label.." | "..capturedSettings(request) end
		precision[#precision+1]=(result.trials<100 or result.confidenceHigh-result.confidenceLow>10) and "Imprecise estimate: run more trials before choosing a crafting route." or "Results describe the captured starting item, targets and supplied prices."
		ui.description(popup,"precision",16,132,828,40,precision,14)
		for index,entry in ipairs({{"medianSpend","MEDIAN SPEND","p50"},{"unluckySpend","90TH PERCENTILE","p90"},{"veryUnluckySpend","99TH PERCENTILE","p99"}}) do
			local values=result.spendingQuantiles;local value=values and string.format("%.2f",values[entry[3]]) or "Not priced"
			ui.card(popup,entry[1],16+(index-1)*282,174,264,entry[2],value,values and result.costCurrency or "Supply every action price")
		end
		popup.results=new("TextListControl"):TextListControl({"TOPLEFT",nil,"TOPLEFT"},{16,284,828,resultHeight-398},nil,lines)
		local kept={};for i,entry in ipairs(result.retainedSuccesses or {}) do kept[#kept+1]={label="Successful item "..i.." (trial "..entry.trial..")",val=i} end
		button(popup,"resources",16,resultHeight-84,176,"Resources used",function()
			local entries={}
			for _,entry in ipairs(result.resourceUsage) do
				local _,icon=pricing.describe(entry.key)
				entries[#entries+1]={id=entry.key,label=entry.name.." | "..string.format("%.12g used",entry.amount),icon=icon,category=entry.kind=="service" and "Services" or "Ingredients",
					details={entry.name,string.format("Total used: %.12g",entry.amount),string.format("Mean per trial: %.6g",entry.meanPerTrial),"Across all "..result.trials.." trials, including failed and capped trials.",
						entry.kind=="service" and "Service units only: no verified ingredient breakdown is available." or "Modeled ingredient quantities from executed actions.",
						"Price overrides change spending, not these quantities. Starting-item costs are separate."}}
			end
			browser.Open("Crafting resources used",entries)
		end)
		popup.resources.enabled=result.resourceUsage and #result.resourceUsage>0 or false
		popup.resources.tooltipText=not result.resourceUsage and "Rerun this older simulation to record ingredient usage." or #result.resourceUsage==0 and "No modeled resources or services were used in this run." or "Browse captured ingredients and service quantities with currency artwork."
		popup.item=new("DropDownControl"):DropDownControl({"TOPLEFT",nil,"TOPLEFT"},{208,resultHeight-84,348,24},kept)
		button(popup,"preview",572,resultHeight-84,272,"Preview retained item",function()
			local index=assert(popup.item:GetSelValueByKey("val"),"No successful items retained")
			local entry=copyTable(draft);entry.targetItem=result.retainedSuccesses[index].itemText
			require("Classes.CraftingProjectControl").Preview(build,entry)
		end)
		popup.item.enabled=#kept>0;popup.preview.enabled=#kept>0
		if #kept==0 then popup.item:SetList({{label="No successful items retained",val=0}}) end
		button(popup,"close",728,resultHeight-42,116,"Close",function() main:ClosePopup() end)
		button(popup,"sample",252,resultHeight-42,220,"Inspect sampled outcome",function()
			local c={};local w,h=math.min(660,main.screenW-40),math.min(560,main.screenH-48)
			ui.description(c,"hint",16,28,w-32,48,{result.sampleSuccess and "One successful sampled outcome. Other trials can differ." or "One unsuccessful sampled outcome. Inspect it before deciding whether to salvage or restart."},16)
			local render=require("Classes.JourneyItemControl").new(c,"sampleItem",16,92,w-32,h-166,"SAMPLED OUTCOME");render(require("Modules.CraftingProjects").item(result.sampleItem))
			button(c,"close",w-156,h-48,140,"Back to results",function() main:ClosePopup() end);ui.style(c);main:OpenPopup(w,h,"Sampled crafting outcome",c,nil,nil,"close")
		end)
		popup.sample.enabled=result.sampleItem~=nil
		button(popup,"charts",484,resultHeight-42,220,"Explore charts",function() require("Classes.CraftingChartsControl").Open({{label=draft.title,result=result}}) end)
		button(popup,"moreTrials",16,resultHeight-42,220,"Run more trials",function()
			assert(request,"Run a fresh simulation to capture its setup")
			request.options.trials=math.min(2000,math.floor(20000/request.options.maxActions),math.max(32,result.trials*4))
			controls.trials:SetText(tostring(request.options.trials),true);main:ClosePopup();startSimulation(request)
		end)
		popup.moreTrials.enabled=function() return request~=nil and not tasks.job and result.trials<math.min(2000,math.floor(20000/request.options.maxActions)) end
		popup.moreTrials.tooltipText=request and "Repeat this captured recipe, item, targets, seed and prices with more trials. Only the trial count changes." or "Run a fresh simulation to capture the setup for this older result."
		ui.style(popup,{moreTrials=true})
		main:OpenPopup(860,resultHeight,"Crafting simulation results",popup,nil,nil,"close")
	end)
	button(controls,"manual",16,448,416,"Edit hypothetical item",function()
		require("Classes.CraftingItemEditorControl").Open(model,state,function(edited)
			state=edited;initial=copyTable(edited);history={};actions={};analysis:clearSimulation();syncAnalysis();changedAffixes={};ui.draft(build,"workingCraft",draft.id)
			updateOptions();refresh({"Manual edits set a new recipe starting state."})
		end)
	end)
	button(controls,"reset",232,530,200,"Reset item",function() state=copyTable(initial);history={};actions={};changedAffixes={};ui.draft(build,"workingCraft",draft.id);updateOptions();refresh() end)
	button(controls,"preview",16,height-48,200,"Preview in build",function()
		assert(not state.veil and not state.destroyed,"A pending unveil or destroyed item cannot be previewed")
		local entry=copyTable(draft); entry.targetItem=simulator.toItem(model,state).raw
		require("Classes.CraftingProjectControl").Preview(build,entry)
	end)
	button(controls,"cancelJob",232,height-48,200,"Cancel crafting job",function() require("Modules.CraftingTasks").cancel() end)
	button(controls,"coverage",width-312,height-48,132,"Coverage",function()
		local entries={}
		for i,line in ipairs(simulator.limits) do entries[#entries+1]={id=i,label=line,category="Assumptions",details={line,"Data patch: "..tostring(simulator.dataPatch or "bundled")}} end
		for _,method in ipairs(simulator.methods) do entries[#entries+1]={id=method,label=simulator.labels[method],category=inspect.category(method),details={"Implemented in the bounded model",workbench.hint(method,state,model),"Item-specific options and prerequisites are validated when applying.","Coverage does not imply complete game parity."}} end
		browser.Open("Crafting coverage and assumptions",entries)
	end)
	controls.coverage.label=function() return "Rules "..tostring(simulator.dataPatch or "bundled") end
	controls.coverage.tooltipText="View supported crafting methods and assumptions."
	button(controls,"close",width-164,height-48,148,layout and "Back to projects" or "Close",function()
		if tasks.job and tasks.job.owner==controls then tasks.cancel("Crafting view closed") end
		if layout then layout.openProjects() else ui.discard(build,"workingCraft",draft.id);main:ClosePopup() end
	end)
	controls.resultSummary=new("TextListControl"):TextListControl({"TOPLEFT",nil,"TOPLEFT"},{16,398,416,height-464},nil,rows({"Run an action or a recipe to inspect its results."}))
	controls.undo.enabled=function() return #history>0 end
	targetReason=function(saved)
		local recipe=saved and draft.nativeRecipe
		local current=recipe and (recipe.initialState or model.initial) or state
		return simulator.implicitTargetReason(simulator.context(model,current),current,recipe and recipe.targets or targets)
	end
	controls.simulate.enabled=function() return not tasks.job and not targetReason() and (#targets>0 or requirements and next(requirements)~=nil) end
	controls.simulate.tooltipText=function() return "Selected action: "..actionName().."\n"..(tasks.job and "Finish or cancel the running calculation first." or targetReason() or "Simulate from the working item using the chosen target modifiers or item conditions.") end
	controls.resourcePrices.enabled=function() return require("Modules.CraftingTasks").job==nil end
	controls.currency.enabled=function() return not draft.priceBook or not next(draft.priceBook.values) end
	controls.currency.showDisabledValue=true
	updateCurrency=function()
		if draft.priceBook and not next(draft.priceBook.values) then draft.priceBook.currency=controls.currency.buf end
		priceOverrides={};controls.price:SetText("");controls.baseCost:SetText("")
		if draft.run then
			draft.run.priceOverrides={};draft.run.settings.price="";draft.run.settings.baseCost="";draft.run.settings.currency=controls.currency.buf
		end
	end
	controls.currency.changeFunc=updateCurrency
	controls.currency.tooltipText="Saved resource quotes use this common unit. Change it through Resource prices. Changing units clears action overrides and base cost."
	controls.price.tooltipText=function() return "Optional total price of "..actionName()..". It applies when that action executes, including inside saved recipes." end
	controls.runRecipe.enabled=function() return not tasks.job and draft.nativeRecipe~=nil and not targetReason(true) end
	controls.runRecipe.tooltipText=function() return tasks.job and "Finish or cancel the running calculation first." or draft.nativeRecipe and targetReason(true) or "Run the project's saved steps from the original starting item, with the saved recipe's targets." end
	controls.exact.enabled=function() return not tasks.job and not targetReason() and (#targets>0 or requirements~=nil and next(requirements)~=nil) and workbench.available(controls.method:GetSelValueByKey("val"),state,model) end
	controls.exact.tooltipText=function()
		if tasks.job then return "Finish or cancel the running calculation first." end
		if #targets==0 and not (requirements and next(requirements)) then return "Choose a target modifier or item condition before calculating." end
		if targetReason() then return targetReason() end
		local available,reason=workbench.available(controls.method:GetSelValueByKey("val"),state,model)
		return available and "Calculate this action from the working item, with captured target conditions." or reason
	end
	controls.compareRecipes.enabled=function() return not tasks.job and not targetReason() and (#targets>0 or requirements and next(requirements)~=nil) end
	controls.compareRecipes.tooltipText=function() return targetReason() or "Compare recipes using the current targets." end
	controls.keepRecipe.enabled=function() return #actions>0 and not state.destroyed and not state.veil end
	controls.manual.enabled=function() return not state.destroyed and not state.veil end
	controls.allflame.enabled=function() return simulator.supportsAllflame(controls.method:GetSelValueByKey("val")) end
	controls.allflame.tooltipText=function() return controls.allflame:IsEnabled() and "Historical 3.29 Allflame model; Allflame is not core in 3.30." or "Allflame is not modeled for this action. Choose a supported itemised currency." end
	controls.fossilResults.tooltipText="Reopen the captured comparison. Rerun after changing the item, targets or quotes."
	controls.fossilResults.enabled=function() return lastFossilComparison~=nil and require("Modules.CraftingTasks").job==nil end
	controls.optimize.tooltipText=function() return targetReason() or "Set targets or item properties, then select Fossil resonator. Settings / Configure chooses multiple candidates. Comparisons use ordinary fossil crafts." end
	controls.optimize.enabled=function()
		if controls.method:GetSelValueByKey("val")~="fossil" or not controls.simulate:IsEnabled() then return false end
		local craft=action();return craft.fossils~=nil and #craft.fossils>0
	end
	controls.distribution.enabled=function() return not tasks.job and lastSimulation~=nil end
	controls.cancelJob.enabled=function() return require("Modules.CraftingTasks").job~=nil end
	controls.apply.enabled=function() return not state.destroyed end
	controls.preview.enabled=function() return not state.destroyed and not state.veil end
	controls.configure.label=function() return controls.method:GetSelValueByKey("val")=="fossil" and "Configure fossil combination" or "Configure donor item" end
	controls.configure.enabled=function() local method=controls.method:GetSelValueByKey("val");return method=="fossil" or method=="awakener" or method=="recombine" or method=="recombine_predictable" end
	controls.page=new("DropDownControl"):DropDownControl({"TOPLEFT",nil,"TOPLEFT"},{16,18,416,28},{"Emulate item","Target conditions","Simulate recipe","Craft settings"})
	controls.page.selFunc=function() refresh() end
	button(controls,"settings",16,380,200,"Find currencies",palette)
	local function crafting() return controls.page:GetSelValue()=="Emulate item" and not paletteOpen and not inspectedId end
	controls.item.enabled=function() return crafting() and controls.apply:IsEnabled() end
	controls.apply.x=16;controls.apply.width=200;controls.undo.x=232;controls.undo.width=200
	ui.label(controls,"selectedAction",16,230,"",20)
	controls.selectedAction.label=function()
		local name=simulator.labels[controls.method:GetSelValueByKey("val")];local suffix=""
		while #name>0 and DrawStringWidth(20,"VAR",name..suffix)>leftWidth do name=name:sub(1,-2);suffix="..." end
		return "^xE2C28C"..name..suffix
	end
	controls.actionHint=ui.description(controls,"actionHint",16,264,416,40,{})
	local pages={
		["Craft settings"]={methodLabel=96,method=116,configure=160,keepRecipe=198,reset=198,exact=238,compareItem=238,seedLabel=278,seed=298,inspectItem=338,allflame=378,manual=418},
		["Emulate item"]={selectedAction=230,actionHint=264,optionLabel=310,option=330,apply=370,undo=370,settings=414,history=414},
		["Target conditions"]={targetLabel=96,target=116,addTarget=154,alternative=154,clearTargets=154,targetPicker=188,targetConditions=226,targetGroups=226,targetSummary=270},
		["Simulate recipe"]={trialsLabel=96,trials=116,budget=116,priceLabel=160,price=180,currency=180,baseCost=180,simulate=224,runRecipe=224,editRecipe=266,resourcePrices=266,optimize=310,fossilResults=310,distribution=354,compareRecipes=354,resultSummary=398},
	}
	for page,layout in pairs(pages) do for key,y in pairs(layout) do
		local control=controls[key];control.y=y;control.shown=page=="Emulate item" and crafting or function() return controls.page:GetSelValue()==page end
	end end
	controls.distribution.x=232;controls.distribution.width=200
	controls.option.shown=function() return crafting() and #controls.option.list>0 end
	controls.optionLabel.shown=controls.option.shown
	controls.apply.enabled=function() return workbench.available(controls.method:GetSelValueByKey("val"),state,model) end
	controls.apply.height=32;controls.undo.height=32
	controls.apply.y=function() return #controls.option.list>0 and 370 or 320 end;controls.undo.y=controls.apply.y
	controls.settings.y=function() return controls.apply:GetProperty("y")+44 end;controls.history.y=controls.settings.y
	controls.targetSummary.height=height-338
	controls.history.enabled=function() return #history>0 end
	controls.settings.label="Find currencies"
	controls.cancelJob.shown=function() return require("Modules.CraftingTasks").job~=nil end
	ui.style(controls,{apply=true,preview=true},{item=true})
	ui.tabs(controls,controls.page,{{"tab_craft","Emulate item","Craft"},{"tab_targets","Target conditions","Targets"},{"tab_simulate","Simulate recipe","Simulate"},{"tab_settings","Craft settings","Settings"}},16,18,416)
	workbench.currencies(controls,function(method)
		chooseMethod(method)
	end,function() return controls.method:GetSelValueByKey("val") end,crafting,function(method)
		local count=0;for _,entry in ipairs(actions) do if entry.method == method then count=count+1 end end;return count
	end,function() return state end,model,leftWidth)
	controls.methodLabel.label="More currencies and crafting methods"
	controls.optionLabel.label="Options for selected currency"
	controls.apply.label="Apply to item"
	ui.label(controls,"projectName",leftWidth+32,24,"",18)
	controls.projectName.label=function()
		local title=draft.title
		while #title>0 and DrawStringWidth(18,"VAR",title)>width-leftWidth-64 do title=title:sub(1,-2) end
		return "^7"..title
	end
	local function inventoryChanged(project) if project.id==draft.id then draft.inventory=copyTable(project.inventory) end end
	button(controls,"inventory",leftWidth+32,54,math.floor((width-leftWidth-60)/2),"Item inventory",function()
		require("Classes.CraftingInventoryControl").Open(build,{current={baseItem=draft.startingItem,state=copyTable(state),title="Working item",slot=draft.slot},change=inventoryChanged,resume=function(project)
			if layout then layout.openWorkbench(project) else Panel.Open(build,project) end
		end})
	end)
	button(controls,"keepItem",leftWidth+44+math.floor((width-leftWidth-60)/2),54,math.floor((width-leftWidth-60)/2),"Keep item",function()
		local project=copyTable(draft);for _,saved in ipairs(build.savers.CraftingProjects.projects) do if saved.id==draft.id then project=copyTable(saved);break end end
		project.inventory=project.inventory or {};project.inventory[#project.inventory+1]=require("Modules.CraftingInventory").capture(draft,state,draft.title:sub(1,104).." / "..(#project.inventory+1))
		inventoryChanged(build.savers.CraftingProjects:Upsert(project));refresh({"Item snapshot kept in this build. Open Item inventory to compare or resume it; use build Save to persist."})
	end)
	controls.stage=new("Control"):Control(ui.anchor,{leftWidth+32,84,width-leftWidth-48,height-148})
	function controls.stage:Draw()
		local x,y=self:GetPos();local w,h=self:GetSize()
		SetDrawLayer(nil,1);SetDrawColor("^x0A1018");DrawImage(nil,x,y,w,h);SetDrawColor("^x8D9DB0")
		DrawString(x+w/2,y+8,"CENTER_X",12,"VAR","WORKING ITEM");DrawString(x+w/2,y+h-2,"CENTER_X",12,"VAR","Click a modifier to inspect it | F: fractured | C: crafted");SetDrawLayer(nil,0)
	end
	for _,key in ipairs({"item","itemMods"}) do
		local control=controls[key];local draw=control.Draw
		function control:Draw(...) SetDrawLayer(nil,2);draw(self,...);SetDrawLayer(nil,0) end
	end
	if draft.priceBook then controls.currency:SetText(draft.priceBook.currency) end
	if restored then
		controls.page:SelByValue(restored.page);controls.seed:SetText(restored.seed)
		for key,value in pairs(restored.settings or {}) do controls[key]:SetText(value) end
	end
	if layout then
		layout.snapshot=function() return copyTable({kind="workbench",priceOverrides=priceOverrides,project=draft,state=state,initial=initial,targets=targets,requirements=requirements,requiredGroups=requiredGroups,craftWidth=leftWidth,favorites=favorites,paletteOpen=paletteOpen,palette=paletteView and paletteView.snapshot(),inspectedId=inspectedId,
			history=history,actions=actions,configured=configured,sequence=sequence,lastSimulation=lastSimulation,lastSimulationRun=lastSimulationRun,lastFossilComparison=lastFossilComparison,page=controls.page:GetSelValue(),method=controls.method:GetSelValueByKey("val"),seed=controls.seed.buf,resultRows=savedResultRows or controls.resultSummary.list,settings={trials=controls.trials.buf,budget=controls.budget.buf,price=controls.price.buf,currency=controls.currency.buf,baseCost=controls.baseCost.buf}}) end
	end
	button(controls,"keepWorking",232,height-48,200,"Keep working craft",function()
		if overrideKey then priceOverrides[overrideKey]=controls.price.buf end
		local run={priceOverrides=priceOverrides,schemaVersion=1,state=state,initial=initial,history=history,actions=actions,configured=configured,sequence=sequence,targets=targets,requirements=requirements,requiredGroups=requiredGroups,
			page=controls.page:GetSelValue(),method=controls.method:GetSelValueByKey("val"),seed=controls.seed.buf,
			settings={trials=controls.trials.buf,budget=controls.budget.buf,price=controls.price.buf,currency=controls.currency.buf,baseCost=controls.baseCost.buf}}
		local saved=copyTable(draft);saved.run=run
		local kept=build.savers.CraftingProjects:Upsert(saved);draft=copyTable(kept)
		ui.kept(build,"workingCraft",draft.id)
		refresh({"Working item, history and settings kept. Use build Save to resume after restarting. No budget was spent."})
	end)
	controls.keepWorking.shown=function() return require("Modules.CraftingTasks").job==nil end
	ui.styleButton(controls.keepWorking,"primary")
	paletteView=require("Modules.CraftingPalette").new(controls,leftWidth,height,{current=function() return controls.method:GetSelValueByKey("val") end,favorites=favorites,restore=restored and restored.palette,
		shown=function() return controls.page:GetSelValue()=="Emulate item" and paletteOpen end,available=function(method) return workbench.available(method,state,model) end,hint=function(method) return workbench.hint(method,state,model) end,
		choose=chooseMethod,close=function() paletteOpen=false;refresh() end})
	ui.label(controls,"affixHeading",16,96,"Modifier details",20)
	controls.affixFacts=new("TextListControl"):TextListControl(ui.anchor,{16,128,leftWidth,height-290},nil,{})
	controls.affixAction=new("DropDownControl"):DropDownControl(ui.anchor,{16,height-146,leftWidth-136,26},{})
	button(controls,"affixUseAction",leftWidth-108,height-146,124,"Select action",function() chooseMethod(controls.affixAction:GetSelValueByKey("val")) end)
	button(controls,"affixBack",16,height-98,math.floor((leftWidth-12)/2),"< Currency tray",function() inspectedId=nil;refresh() end)
	button(controls,"affixTarget",28+math.floor((leftWidth-12)/2),height-98,math.floor((leftWidth-12)/2),"Use as target",function() pickTarget(inspectedId);inspectedId=nil;controls.page:SelByValue("Target conditions");refresh() end)
	local affixControls={}
	for _,key in ipairs({"affixHeading","affixFacts","affixAction","affixUseAction","affixBack","affixTarget"}) do controls[key].shown=function() return controls.page:GetSelValue()=="Emulate item" and inspectedId~=nil end;affixControls[key]=controls[key] end
	controls.affixUseAction.enabled=function() local method=controls.affixAction:GetSelValueByKey("val");return method and workbench.available(method,state,model) end
	controls.affixBack.height=28;controls.affixTarget.height=28
	ui.style(affixControls,{affixTarget=true})
	for key,control in pairs(controls) do
		if key~="item" and key~="itemMods" and key~="stage" and key~="projectName" and not key:match("^currency_") and not key:match("^palette") and not key:match("^affix") and type(control.x)=="number" and control.x<448 and type(control.width)=="number" then
			control.x=16+math.floor((control.x-16)*leftWidth/416);if control.width>0 then control.width=math.floor(control.width*leftWidth/416) end
		end
	end
	if layout then ui.splitter(controls,"splitter",leftWidth+19,84,height-148,function(delta)
		layout.workbench=layout.snapshot();layout.craftWidth=math.max(416,math.min(width-400,leftWidth+delta));Panel.Open(build,draft,layout)
	end);controls.splitter.enabled=function() return not tasks.job end end
	if restored then controls.method:SelByValue(restored.method or "alchemy","val");controls.resultSummary.list=restored.resultRows or controls.resultSummary.list
	elseif draft.preferredMethod then controls.method:SelByValue(draft.preferredMethod,"val") end
	updateOptions();refresh()
	-- Hook edits after restoring controls so viewing a saved craft stays clean.
	for _,key in ipairs({"trials","budget","price","currency","baseCost","seed"}) do
		local control=controls[key];local previous=control.changeFunc
		control.changeFunc=function(...)
			if previous then previous(...) end
			changed()
		end
	end
	ready=true
	if inspectedId then populateAffix(inspectedId) end
	for key,control in pairs(controls) do if key~="stage" then control.layoutAudit="crafting-workbench" end end
	if layout then layout.mount(width,height,"Crafting workbench",controls) else main:OpenPopup(width,height,"Crafting workbench",controls,nil,nil,"close") end
	analysis:bind(controls,function(event,announce)
		syncAnalysis()
		if event.phase=="error" then refresh({ui.errorText(event.message)})
		elseif event.phase=="queued" then refresh({"Calculation queued. You can cancel it below."})
		elseif event.phase=="progress" then
			local p=event.progress
			if event.kind=="fossils" and p.combinations then refresh({"Fossil combination "..p.combination.." / "..p.combinations})
			elseif p.trials then refresh({(event.kind=="simulation" and "Simulation running: trial " or "Calculating odds: trial ")..p.trial.." / "..p.trials})
			else refresh({"Calculation queued. You can cancel it below."}) end
		elseif event.kind=="simulation" then showSimulationResult(event.result,event.context)
		elseif event.kind=="odds" then showOddsResult(event.result)
		else
			refresh({"Compared "..#event.result.combinations.." ordinary fossil subsets. Open Fossil results to review captured chances and costs."})
			if announce then showFossilComparison() end
		end
	end,function()
		if layout then
			local workspace=build.planningWorkspace
			return #main.popups==0 and build.viewMode=="PLANNER" and workspace and workspace.body and workspace.body.controls==controls
		end
		return main.popups[1] and main.popups[1].controls==controls
	end)
	return controls
end
return Panel
