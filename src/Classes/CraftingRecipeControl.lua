-- Native recipe routing editor with emulator actions and future currency steps.
local sim=require("Modules.CraftingSimulator")
local Panel={}
local function button(controls,key,x,y,w,label,callback)
	controls[key]=new("ButtonControl"):ButtonControl({"TOPLEFT",nil,"TOPLEFT"},{x,y,w,24},label,function()
		local ok,message=pcall(callback);if not ok then main:OpenMessagePopup("Crafting recipe",require("Modules.PlanningUI").errorText(message)) end
	end)
end
local function edit(x,y,w,value,prompt,limit)
	return new("EditControl"):EditControl({"TOPLEFT",nil,"TOPLEFT"},{x,y,w,24},tostring(value or ""),prompt,nil,limit)
end
function Panel.Open(recipe,currentAction,onKeep,model)
	local draft=copyTable(recipe or {steps={},targets={}})
	local controls={};local selected=1
	local ui=require("Modules.PlanningUI")
	controls.info=new("LabelControl"):LabelControl({"TOPLEFT",nil,"TOPLEFT"},{16,28,0,14},"Select a step card, or connect routes in the flow graph.")
	controls.graph=new("TextListControl"):TextListControl({"TOPLEFT",nil,"TOPLEFT"},{16,62,828,264},nil,{})
	controls.step=new("DropDownControl"):DropDownControl({"TOPLEFT",nil,"TOPLEFT"},{16,350,828,24},{})
	controls.attempts=edit(16,400,180,"1","Attempts per visit",3)
	controls.condition=new("DropDownControl"):DropDownControl({"TOPLEFT",nil,"TOPLEFT"},{212,400,632,24},{"After a successful action","Until final targets and properties match","Keep custom conditions"})
	controls.success=new("DropDownControl"):DropDownControl({"TOPLEFT",nil,"TOPLEFT"},{16,456,404,24},{})
	controls.failure=new("DropDownControl"):DropDownControl({"TOPLEFT",nil,"TOPLEFT"},{440,456,404,24},{})
	controls.routeLabel=new("LabelControl"):LabelControl({"TOPLEFT",nil,"TOPLEFT"},{16,436,0,14},"Success route                                                   Failure / exhausted attempts route")
	local function loadStep()
		local step=draft.steps[selected];if not step then return end
		for _,row in ipairs(controls.graph.list) do row.selected=row.step==selected end
		local scroll=controls.graph.controls.scrollBar;local _,height=controls.graph:GetSize()
		scroll:SetContentDimension(#draft.steps*92,height-4);scroll:ScrollIntoView((selected-1)*92,92)
		controls.attempts:SetText(tostring(step.maxAttempts or 1))
		controls.condition:SelByValue((step.untilTargets or step.untilRequirements) and "Keep custom conditions" or "After a successful action")
		controls.success:SelByValue(step.onSuccess or 0,"val")
		controls.failure:SelByValue(step.onFailureAction and step.onFailureAction~="route" and step.onFailureAction or step.onFailure or 0,"val")
	end
	local function refresh()
		local list,routes,lines={ },{{label="Next step",val=0}},{}
		for i,step in ipairs(draft.steps) do
			list[#list+1]={label=i..". "..require("Modules.CraftingWorkbench").actionLabel(step,model),val=i}
			routes[#routes+1]={label="Step "..i,val=i}
			local function route(target) return target>#draft.steps and "Finish" or "Step "..target end
			lines[#lines+1]={height=92,textSize=16,x=44,card=true,step=i,selected=i==selected,iconPath=require("Modules.CraftingWorkbench").icon(step.method,step,model),
				subtitle=string.format("Success -> %s | Failure -> %s",route(step.onSuccess or i+1),step.onFailureAction and step.onFailureAction~="route" and require("Classes.CraftingRecoveryControl").labels[step.onFailureAction] or route(step.onFailure or i+1)),
				detail=(step.untilTargets or step.untilRequirements) and "Repeat until target conditions match" or "Continue after one successful action",
				"^7"..string.format("%d. %s | up to %d attempts",i,require("Modules.CraftingWorkbench").actionLabel(step,model),step.maxAttempts or 1)}
		end
		routes[#routes+1]={label="End recipe",val=#draft.steps+1}
		controls.graph.list=lines;controls.step:SetList(list);controls.step:SelByValue(selected,"val")
		controls.success:SetList(routes)
		local failureRoutes=copyTable(routes);local recovery=require("Classes.CraftingRecoveryControl")
		for _,policy in ipairs({"stop","restart","salvage"}) do failureRoutes[#failureRoutes+1]={label=recovery.labels[policy],val=policy} end
		controls.failure:SetList(failureRoutes);loadStep()
	end
	controls.step.selFunc=function(_,entry) selected=entry.val;loadStep() end
	button(controls,"flowGraph",664,24,180,"Flow graph",function()
		require("Classes.CraftingRecipeGraphControl").Open(draft,{model=model,change=function(next) draft=next;refresh() end,edit=function(index) selected=index;refresh();main:ClosePopup();main.popups[1]:SelectControl(controls.attempts) end})
	end)
	ui.selectable(controls.graph,function(row) return row.step end,function(row) selected=row.step;controls.step:SelByValue(selected,"val");loadStep() end)
	button(controls,"add",16,514,256,"Append current emulator action",function()
		assert(#draft.steps < 20,"Use up to twenty steps")
		draft=require("Modules.CraftingRoutes").append(draft,currentAction);selected=#draft.steps;refresh()
	end)
	button(controls,"replace",288,514,272,"Replace selected with emulator action",function()
		local old=assert(draft.steps[selected],"Select a step");local next=copyTable(currentAction)
		for _,key in ipairs({"maxAttempts","onSuccess","onFailure","onFailureAction","recoveryNotes","untilTargets","untilRequirements"}) do
			local value=old[key];if value~=nil then next[key]=type(value)=="table" and copyTable(value) or value end
		end
		draft.steps[selected]=next;refresh()
	end)
	button(controls,"delete",576,514,268,"Delete selected step",function()
		assert(draft.steps[selected],"Select a step");table.remove(draft.steps,selected)
		for _,step in ipairs(draft.steps) do for _,key in ipairs({"onSuccess","onFailure"}) do if step[key] and step[key] > selected then step[key]=step[key]-1 end end end
		selected=math.min(selected,math.max(1,#draft.steps));refresh()
	end)
	button(controls,"update",16,558,256,"Update selected routes",function()
		local candidate=copyTable(draft);local step=assert(candidate.steps[selected],"Select a step")
		step.maxAttempts=assert(tonumber(controls.attempts.buf),"Enter an attempt count")
		local condition=controls.condition:GetSelValue()
		if condition == "Until final targets and properties match" then assert(#draft.targets > 0 or draft.requirements,"Choose targets or properties in the emulator first");step.untilTargets=#draft.targets > 0 and copyTable(draft.targets) or nil;step.untilRequirements=draft.requirements and copyTable(draft.requirements) or nil
		elseif condition == "After a successful action" then step.untilTargets=nil;step.untilRequirements=nil end
		local success,failure=controls.success:GetSelValueByKey("val"),controls.failure:GetSelValueByKey("val")
		step.onSuccess=success ~= 0 and success or nil
		if type(failure)=="string" then step.onFailureAction=failure
		else step.onFailureAction="route";step.onFailure=failure ~= 0 and failure or nil end
		sim.validateRecipe(candidate);draft=candidate;refresh()
	end)
	controls.note=new("LabelControl"):LabelControl({"TOPLEFT",nil,"TOPLEFT"},{16,604,0,14},"Loops stop at the simulation action budget. Keeping a recipe does not craft or equip an item.")
	button(controls,"recovery",288,558,272,"Failure recovery",function()
		local step=assert(draft.steps[selected],"Select a recipe step")
		require("Classes.CraftingRecoveryControl").Open(step,function(replacement) draft.steps[selected]=replacement;sim.validateRecipe(draft);refresh() end)
	end)
	button(controls,"keep",16,642,256,"Keep recipe",function() onKeep(sim.validateRecipe(draft));main:ClosePopup() end)
	button(controls,"addCurrency",288,642,272,"Add recipe step",function()
		assert(#draft.steps < 20,"Use up to twenty steps")
		local entries={};local workbench=require("Modules.CraftingWorkbench")
		for _,method in ipairs({"transmute","alteration","augmentation","regal","alchemy","binding","chaos","exalt","annul","scour","divine","vaal","blessed","sacred","chromatic","quality"}) do
			local details={"Add this action to the recipe without changing the working item.","The item must meet its requirements when this step runs."}
			if method=="binding" then details[#details+1]="No longer generated in 3.30; existing Orbs of Binding still work." end
			entries[#entries+1]={id=method,label=sim.labels[method],category="Currency",icon=workbench.icon(method),action={method=method},
				details=details}
		end
		for _,count in ipairs({1,3}) do entries[#entries+1]={id="bench-reroll-"..count,label="Bench: reroll "..count.." modifier"..(count==1 and "" or "s"),category="Bench",icon=workbench.icon("bench_reroll"),action={method="bench_reroll",count=count},
			details={"Add this bench action to the recipe without changing the working item.","The item must have enough removable modifiers when this step runs."}} end
		entries[#entries+1]={id="beast_max_links",label=sim.labels.beast_max_links,category="Bestiary",icon=workbench.icon("beast_max_links"),action={method="beast_max_links"},details={"Link the item's existing sockets using the Black Morrigan and a Craicic Sand Spitter.","Add sockets first; this step does not increase their number."}}
		entries[#entries+1]={id="beast_talisman_imprint",label=sim.labels.beast_talisman_imprint,category="Bestiary",icon=workbench.icon("beast_talisman_imprint"),action={method="beast_talisman_imprint"},details={"Create an imprint of an uncorrupted, non-fractured rare Talisman.","Enter a whole-action price for the Bestiary service."}}
		if model then
			entries[#entries+1]={id="fossil-combination",label="Fossil combination",category="Fossils",configure="fossil",details={"Choose up to four fossils for this recipe step.","The item must meet the fossil requirements when this step runs."}}
			for _,entry in ipairs(model.bench or {}) do
				local action={method="bench",modId=entry.id};local label=workbench.actionLabel(action,model)
				entries[#entries+1]={id=entry.id,label=label,search=entry.id,category="Bench",action=action,details={label,"Uses a bench-crafted slot. Item requirements and conflicts are checked when this step runs."}}
			end
			for _,entry in ipairs(model.essences or {}) do
				local action={method="essence",essenceId=entry.id}
				local mod=model.descriptions330[entry.modId] or model.byId[entry.modId];local guaranteed=mod and table.concat(mod," / ") or "Unavailable"
				local details={entry.name,"Guaranteed on this base: "..guaranteed}
				if entry.maxModLevel then details[#details+1]="Other random modifiers are restricted to level "..entry.maxModLevel.." or below." end
				details[#details+1]="Crafting data: "..sim.dataPatch..". The item must meet the Essence's requirements when this step runs."
				entries[#entries+1]={id=entry.id,label=entry.name,search=entry.id,category="Essences",icon=workbench.icon("essence",action,model),action=action,
					details=details}
			end
		end
		for _,method in ipairs({"harvest_reforge","harvest_augment"}) do for _,tag in ipairs({"attack","caster","physical","fire","cold","lightning","chaos","life","defences","speed","critical","influence"}) do
			if method~="harvest_augment" or tag~="influence" then local action={method=method,tag=tag};local label=workbench.actionLabel(action,model)
				entries[#entries+1]={id=method..":"..tag,label=label,category="Harvest",action=action,details={label,"A legal modifier and item state are required when this step runs."}}
			end
		end end
		require("Classes.PlanningBrowserControl").Open("Add a recipe step",entries,{action="Add step",closeOnChoose=false,choose=function(entry)
			main:ClosePopup()
			local function append(action) draft=require("Modules.CraftingRoutes").append(draft,action);selected=#draft.steps;refresh() end
			if entry.configure=="fossil" then require("Classes.CraftingFossilControl").Open(model,nil,append) else append(entry.action) end
		end})
	end)
	button(controls,"editFossils",576,642,136,"Edit fossils",function()
		local index=selected;local step=assert(draft.steps[index],"Select a fossil step")
		assert(model and step.method=="fossil","Select a fossil step")
		require("Classes.CraftingFossilControl").Open(model,step,function(action)
			local next=copyTable(step);next.fossils=copyTable(action.fossils);next.tangledOutcome=action.tangledOutcome
			draft.steps[index]=next;refresh()
		end)
	end)
	controls.editFossils.enabled=function() return model~=nil and draft.steps[selected]~=nil and draft.steps[selected].method=="fossil" end
	button(controls,"close",728,642,116,"Close",function() main:ClosePopup() end)
	local height=math.max(520,math.min(690,main.screenH-60));local offset=690-height
	controls.graph.height=264-offset
	for key,control in pairs(controls) do if key ~= "graph" and control.y >= 350 then control.y=control.y-offset end end
	refresh();ui.style(controls,{keep=true});for _,control in pairs(controls) do control.layoutAudit="recipe-editor" end;main:OpenPopup(860,height,"Crafting recipe routes",controls,nil,nil,"close")
	return controls
end
return Panel
