-- Desktop build proposals are calculated separately and applied only in the UI.
local json = require("dkjson")
local sha1 = require("sha1")
local insights = require("Modules.BuildInsights")
local M = { enabled=false, history={}, undo={}, plan={goal="balanced"} }
local metrics = { "LifeUnreserved", "EnergyShield", "ManaUnreserved", "CombinedDPS", "FullDPS", "TotalEHP", "PhysicalMaximumHitTaken", "ChaosMaximumHitTaken", "RecoverySimulationSurvivalChance", "RecoverySimulationDamageDPS", "RecoverySimulationAttackUptime", "ManaRegen", "Speed", "EffectiveMovementSpeedMod", "FireResist", "ColdResist", "LightningResist", "ChaosResist", "Str", "Dex", "Int" }

local function capture(build,treeOnly)
	-- The native Notes saver temporarily hides color codes. Preserve the editor.
	local notes = build.notesTab
	local edit = notes.controls.edit
	local buf, colors, caret, selection = edit.buf,notes.showColorCodes,edit.caret,edit.sel
	local ok, result, tree = pcall(build.SaveDB,build,"AI build context",{snapshot=true,treeOnly=treeOnly})
	edit.buf, notes.showColorCodes, edit.caret, edit.sel = buf,colors,caret,selection
	notes.controls.toggleColorCodes.label = colors and "Hide Color Codes" or "Show Color Codes"
	assert(ok and (treeOnly and (tree or result) or result),ok and "Could not serialize build" or result)
	return result, tree
end

local function serialize(build) local raw=capture(build);return raw end

-- Match ComposeXML/ParseXML text normalization without reparsing the snapshot.
local function canonicalTree(node,level)
	local result={elem=node.elem,attrib=node.attrib and copyTable(node.attrib)}
	local pending={}
	local function flush()
		if #pending>0 then
			local text=table.concat(pending,"\n"..string.rep("\t",level+1)):match("^%s*(.-)%s*$")
			if text:find("%S") then result[#result+1]=text end
			pending={}
		end
	end
	for _,child in ipairs(node) do
		if type(child)=="table" then flush();result[#result+1]=canonicalTree(child,level+1) else pending[#pending+1]=child end
	end
	flush();return result
end

local function revisionXML(build,raw,tree)
	local root = tree and canonicalTree(tree,0) or assert(common.xml.ParseXML(raw))[1]
	for index=#root,1,-1 do
		local node = root[index]
		if type(node) == "table" then
			if node.elem == "TreeView" then table.remove(root,index)
			elseif node.elem == "Build" then
				node.attrib.viewMode = nil
				for i=#node,1,-1 do if type(node[i]) == "table" and (node[i].elem == "PlayerStat" or node[i].elem == "MinionStat" or node[i].elem == "FullDPSSkill") then table.remove(node,i) end end
			end
		end
	end
	return sha1((build.buildName or "")..assert(common.xml.ComposeXML(root)))
end
function M.revision(build) local raw,tree=capture(build,true);return revisionXML(build,raw,tree) end
function M.freeze(build)
	local raw,tree=capture(build);return {build=build,xml=raw,revision=revisionXML(build,raw,tree)}
end

local function stats(build)
	local result = { }
	for _,key in ipairs(metrics) do
		local value = build.calcsTab.calcsOutput[key]
		if type(value) == "number" and value == value and math.abs(value) < math.huge then result[key] = value end
	end
	return result
end

local function sandbox(callback)
	local originalMain, originalCache, originalError = main,GlobalCache,launch.ShowErrMsg
	local proxy = setmetatable({modes=setmetatable({},{__index=main.modes}),popups={}}, {__index=main})
	proxy.SetMode = function() error("Proposal requires a build conversion or an unsupported import") end
	proxy.OpenPopup = function() error("Proposal requires an interactive conversion or import") end
	proxy.SetWindowTitleSubtext = function() end
	main = proxy
	GlobalCache = setmetatable({cachedData={MAIN={},CALCS={},CALCULATOR={}}},{__index=originalCache})
	launch.ShowErrMsg = function(_,message,...) error(string.format(message,...)) end
	local ok,result = xpcall(function() return callback(proxy) end,debug.traceback)
	main,GlobalCache,launch.ShowErrMsg = originalMain,originalCache,originalError
	assert(ok,result)
	return result
end

local function integer(value, low, high, label)
	assert(type(value) == "number" and value == math.floor(value) and value >= low and value <= high,"Invalid "..label)
	return value
end

local function text(value, limit, label)
	assert(type(value) == "string" and #value <= limit,"Invalid "..label)
	return value
end

local function configOptions()
	local map = { }
	for _,entry in ipairs(require("Modules.ConfigOptions")) do if entry.var then map[entry.var] = entry end end
	return map
end

local function applyOperation(build, op)
	assert(type(op) == "table","Invalid operation")
	if op.type == "set_character" then
		if op.level then build.characterLevel = integer(op.level,1,100,"character level"); build.characterLevelAutoMode = false end
		if op.className then
			local classId = build.spec.tree.classNameMap[text(op.className,40,"class name")]
			assert(classId,"Unknown character class")
			-- Reset allocations when changing class, as for a fresh native tree.
			if classId ~= build.spec.curClassId then build.spec:ResetNodes(); build.spec:SelectClass(classId) end
		end
		if op.ascendancy then
			local id
			for index,entry in pairs(build.spec.curClass.classes) do if entry.name == op.ascendancy then id = index end end
			assert(id,"Unknown ascendancy for selected class")
			build.spec:SelectAscendClass(id)
		end
	elseif op.type == "allocate_passives" then
		for _,id in ipairs(op.remove or { }) do
			local node = assert(build.spec.nodes[integer(id,1,1000000,"passive ID")],"Unknown passive")
			assert(not node.isAscendancyStart and node.type ~= "ClassStart","Cannot remove a class start")
			if node.alloc then build.spec:DeallocNode(node) end
		end
		for _,id in ipairs(op.add or { }) do
			local node = assert(build.spec.nodes[integer(id,1,1000000,"passive ID")],"Unknown passive")
			assert(node.path and node.type ~= "Mastery","Passive is unreachable or needs a mastery effect")
			build.spec:AllocNode(node)
		end
		for _,selection in ipairs(op.masteries or { }) do
			local node = assert(build.spec.nodes[selection.nodeId],"Unknown mastery")
			assert(node.type == "Mastery" and node.path,"Mastery is unreachable")
			local valid = false
			for _,effect in ipairs(node.masteryEffects or { }) do if effect.effect == selection.effectId then valid = true end end
			assert(valid,"Effect does not belong to this mastery")
			for id,effectId in pairs(build.spec.masterySelections) do assert(id == node.id or effectId ~= selection.effectId,"Mastery effect is already allocated") end
			build.spec:AllocNode(node)
			local effect = assert(build.spec.tree.masteryEffects[selection.effectId],"Unknown mastery effect")
			node.sd,node.allMasteryOptions = effect.sd,false
			build.spec.tree:ProcessStats(node)
			build.spec.masterySelections[node.id] = selection.effectId
		end
	elseif op.type == "equip_item" then
		local slot = assert(build.itemsTab.slots[text(op.slot,80,"equipment slot")],"Unknown equipment slot")
		local item = new("Item"):Item(text(op.text,24000,"item text"))
		assert(item.baseName and build.itemsTab:IsItemValidForSlot(item,op.slot),"Item cannot be equipped in this slot")
		item:NormaliseQuality()
		build.itemsTab:AddItem(item,true)
		slot:SetSelItemId(item.id)
		if op.active ~= nil then assert(type(op.active) == "boolean","Invalid flask state"); slot.active = op.active end
		build.itemsTab:PopulateSlots()
	elseif op.type == "set_skills" then
		assert(type(op.groups) == "table" and #op.groups <= 40,"Invalid socket groups")
		local groups = { }
		for _,source in ipairs(op.groups) do
			assert(type(source.gems) == "table" and #source.gems <= 12,"Invalid gem list")
			if source.slot then assert(build.itemsTab.slots[source.slot],"Unknown socket-group slot") end
			local active = integer(source.mainActiveSkill or 1,1,12,"active skill index")
			local group = {label=text(source.label or "",120,"group label"),slot=source.slot,enabled=source.enabled ~= false,includeInFullDPS=source.includeInFullDPS == true,gemList={},mainActiveSkill=active,mainActiveSkillCalcs=active}
			for _,gem in ipairs(source.gems) do
				local entry = {nameSpec=text(gem.name,160,"gem name"),level=integer(gem.level or 20,1,40,"gem level"),quality=integer(gem.quality or 0,0,100,"gem quality"),qualityId="Default",enabled=gem.enabled ~= false,enableGlobal1=true,enableGlobal2=false,count=1}
				group.gemList[#group.gemList+1] = entry
			end
			build.skillsTab:ProcessSocketGroup(group)
			for _,gem in ipairs(group.gemList) do assert(gem.gemData and not gem.errMsg,"Unknown or invalid gem: "..gem.nameSpec) end
			groups[#groups+1] = group
		end
		build.skillsTab.socketGroupList = groups
		build.skillsTab.skillSets[build.skillsTab.activeSkillSetId].socketGroupList = groups
		build.mainSocketGroup = integer(op.mainGroup or 1,1,math.max(1,#groups),"main socket group")
		build.calcsTab.input.skill_number = build.mainSocketGroup
		build.skillsTab:SetDisplayGroup(groups[1])
	elseif op.type == "set_config" then
		local options = configOptions()
		assert(type(op.values) == "table","Invalid configuration")
		for key,value in pairs(op.values) do
			local option = assert(options[key],"Unknown configuration: "..tostring(key))
			if option.type == "check" then assert(type(value) == "boolean","Configuration requires a boolean: "..key)
			elseif option.type == "count" then assert(type(value) == "number" and value == value and math.abs(value) <= 1e9,"Configuration requires a finite number: "..key)
			elseif option.type == "list" then
				local valid = false
				local control = build.configTab.varControls[key]
				for _,entry in ipairs(control and control.list or { }) do if entry.val == value then valid = true end end
				assert(valid,"Invalid configuration choice: "..key)
			else text(value,24000,"configuration value") end
			build.configTab.input[key] = value
		end
	elseif op.type == "set_notes" then
		build.notesTab.controls.edit:SetText(text(op.text,64000,"notes"))
	elseif op.type == "set_build_journey" then
		build.savers.BuildJourney:Replace(op.journey)
	elseif op.type == "set_loot_filters" then
		build.savers.LootFilters:Replace(op.filters)
	elseif op.type == "set_crafting_project" then
		build.savers.CraftingProjects:Upsert(op.project)
	elseif op.type == "remove_crafting_project" then
		build.savers.CraftingProjects:Remove(text(op.projectId,64,"project ID"))
	elseif op.type == "set_atlas_plan" then
		build.savers.AtlasPlans:Upsert(op.plan)
	else error("Unknown operation: "..tostring(op.type)) end
end

function M.prepare(build, proposal, checkpoint, sourceXML, frozen)
	local yieldingCheckpoint=checkpoint
	checkpoint=checkpoint or function() end
	assert(type(proposal) == "table" and (proposal.mode == "edit" or proposal.mode == "new"),"Choose edit or new build")
	assert(type(proposal.operations) == "table" and #proposal.operations > 0 and #proposal.operations <= 100,"Use 1 to 100 operations")
	assert(not frozen or frozen.build==build,"Snapshot belongs to a different build")
	assert(proposal.baseRevision == (frozen and frozen.revision or M.revision(build)),"Build changed. Refresh context and submit a new proposal.")
	local title = text(proposal.title,120,"proposal title")
	assert(title:match("%S") and not title:find("[%c]"),"Title must be a nonempty single line")
	local source = sourceXML or proposal.mode == "edit" and (frozen and frozen.xml or serialize(build)) or nil
	checkpoint("Load candidate")
	local computed = sandbox(function(proxy)
		local candidate = LoadModule("Modules/Build")
		proxy.modes.BUILD = candidate
		candidate.planningCheckpoint=yieldingCheckpoint
		candidate.planningDeferInitialRecovery=true
		candidate:Init(nil,proposal.mode == "new" and title or build.buildName,source)
		candidate.planningDeferInitialRecovery=nil
		assert(candidate.abortSave == false,"Unable to initialize proposed build")
		candidate.planningCheckpoint=yieldingCheckpoint
		checkpoint("Apply candidate changes")
		for _,operation in ipairs(proposal.operations) do applyOperation(candidate,operation) end
		candidate.configTab:BuildModList()
		candidate.configTab:UpdateControls()
		candidate:UpdateClassDropdowns()
		candidate.skillsTab:UpdateSocketGroups()
		wipeGlobalCache()
		checkpoint("Calculate candidate")
		candidate.calcsTab:BuildOutput()
		candidate:RefreshStatList()
		local calculatedLevel = candidate.characterLevel
		candidate:EstimatePlayerProgress()
		if candidate.characterLevel ~= calculatedLevel then candidate.calcsTab:BuildOutput(); candidate:RefreshStatList() end
		candidate.controls.characterLevel:SetText(tostring(candidate.characterLevel))
		candidate.buildFlag = false
		candidate.planningCheckpoint=nil
		return {candidate=candidate,cache=GlobalCache}
	end)
	local candidate = computed.candidate
	checkpoint("Review requirements")
	local after = stats(candidate)
	local before = stats(build)
	local delta = { }
	for key,value in pairs(after) do if before[key] then delta[key] = value-before[key] end end
	local audit = insights.audit(candidate)
	local baseAudit = insights.audit(build)
	local known = { }
	for _,entry in ipairs(baseAudit.dependencies) do known[entry.key..entry.text]=true end
	audit.introduced = { }
	for _,entry in ipairs(audit.dependencies) do if not known[entry.key..entry.text] then audit.introduced[#audit.introduced+1]=entry end end
	local beforeSnapshot,afterSnapshot = insights.snapshot(build),insights.snapshot(candidate)
	local evaluation = insights.evaluate(before,after,M.plan,proposal.quote,audit)
	local changedConfig = false
	for key,value in pairs(beforeSnapshot.config) do if afterSnapshot.config[key] ~= value then changedConfig=true end end
	for key,value in pairs(afterSnapshot.config) do if beforeSnapshot.config[key] ~= value then changedConfig=true end end
	if changedConfig then
		evaluation.eligible=false
		evaluation.issues[#evaluation.issues+1]="Configuration differs from the base. Excluded from ranking; review assumptions and compare under matching settings."
	end
	evaluation.configurationChanged = changedConfig
	return {candidate=candidate,cache=computed.cache,baseRevision=proposal.baseRevision,mode=proposal.mode,title=title,operations=proposal.operations,before=before,after=after,delta=delta,base=build,warnings=copyTable(candidate.controls.warnings.lines),
		changes=insights.changes(beforeSnapshot,afterSnapshot),audit=audit,quote=proposal.quote,
		evaluation=evaluation}
end

function M.prepareBundle(build,bundle)
	assert(not M.prepared,"Review or reject the pending proposal first")
	return M.prepare(build,{mode="new",title=bundle.buildName,baseRevision=M.revision(build),operations={{type="set_character"}}},nil,bundle.xml)
end

M.serialize=serialize

function M.apply(prepared)
	assert(main.modes.BUILD == prepared.base and M.revision(prepared.base) == prepared.baseRevision,"Build changed since preview. Submit a fresh proposal.")
	local candidate = prepared.candidate
	if prepared.mode=="edit" then
		local carriedRemoval=false
		local previousRemoval=prepared.base.savers.CraftingProjects.lastRemoved
		if not candidate.savers.CraftingProjects.lastRemoved and previousRemoval then
			local copy=copyTable(previousRemoval);copy.project=require("Modules.CraftingProjects").copy({previousRemoval.project})[1]
			candidate.savers.CraftingProjects.lastRemoved=copy;carriedRemoval=true
		end
		local workspace=prepared.base.planningWorkspace
		if workspace then workspace:CopyCraftingDrafts(candidate) end
		local removed=candidate.savers.CraftingProjects.lastRemoved
		if removed and not carriedRemoval then
			removed.draft=workspace and workspace:CraftingDraft(removed.project.id)
			removed.pending=require("Modules.PlanningUI").hasDraft(prepared.base,"workingCraft",removed.project.id)
			if not removed.draft then local recovery=require("Modules.PlanningRecovery").forCraftingProject(prepared.base,removed.project.id);if recovery then removed.draft=recovery.draft;removed.pending=recovery.pending end end
		end
	end
	if prepared.mode == "edit" then candidate.dbFileName,candidate.dbFileSubPath = prepared.base.dbFileName,prepared.base.dbFileSubPath end
	candidate.modFlag,candidate.unsaved = true,true
	M.undo[#M.undo+1] = {build=prepared.base,cache=GlobalCache}
	if #M.undo > 5 then table.remove(M.undo,1) end
	M.previousCache,GlobalCache = GlobalCache,prepared.cache
	main.modes.BUILD = candidate
	candidate.spec:SetWindowTitleWithBuildClass()
	M.previous,M.build,M.owner = prepared.base,candidate,candidate
	M.appliedRevision = M.revision(candidate)
	M.prepared = nil
	return candidate
end

local function writeFile(path, value)
	local file = assert(io.open(path,"wb"),"Cannot write AI context")
	local ok,err = file:write(json.encode(value))
	file:close()
	assert(ok,err)
end

local function path(name) return main.userPath.."AI-build-"..name..".json" end

function M.capture(build)
	local context = {revision=M.revision(build),name=build.buildName,level=build.characterLevel,className=build.spec.curClassName,ascendancy=build.spec.curAscendClassName,
		stats=stats(build),items={},skills={},passives={},masteries=copyTable(build.spec.masterySelections),config=copyTable(build.configTab.input),
		warnings=copyTable(build.controls.warnings.lines),slots={},plan=M.plan,audit=insights.audit(build),encounter=insights.diagnose(build),
		craftingProjects=require("Modules.CraftingProjects").copy(build.savers.CraftingProjects.projects),craftingWarning=build.savers.CraftingProjects.warning,
		lootFilters=copyTable(build.savers.LootFilters.data),lootFilterWarning=build.savers.LootFilters.warning,
		journey=copyTable(build.savers.BuildJourney.data),journeyWarning=build.savers.BuildJourney.warning,
		journeyBudget=require("Modules.BuildJourney").budget(build.savers.BuildJourney.data),nextActions=require("Modules.BuildJourney").next(build.savers.BuildJourney.data,build),
		atlasPlans=copyTable(build.savers.AtlasPlans.plans),atlasWarning=build.savers.AtlasPlans.warning,atlasVersions=copyTable(require("Modules.AtlasPlanner").versions)}
	local catalog = {gems={},passives={},config={},classes={}}
	for name,slot in pairs(build.itemsTab.slots) do
		context.slots[#context.slots+1] = name
		local item = build.itemsTab.items[slot.selItemId]
		if item then context.items[#context.items+1] = {slot=name,id=item.id,name=item.name,text=item.raw,active=slot.active} end
	end
	table.sort(context.slots)
	for index,group in ipairs(build.skillsTab.socketGroupList) do
		local entry = {index=index,label=group.label,slot=group.slot,enabled=group.enabled,includeInFullDPS=group.includeInFullDPS,gems={}}
		for _,gem in ipairs(group.gemList) do entry.gems[#entry.gems+1] = {name=gem.nameSpec,level=gem.level,quality=gem.quality,enabled=gem.enabled} end
		context.skills[#context.skills+1] = entry
	end
	for _,node in pairs(build.spec.nodes) do
		if node.alloc then context.passives[#context.passives+1] = node.id end
		catalog.passives[#catalog.passives+1] = {id=node.id,name=node.name,type=node.type,stats=node.sd,ascendancy=node.ascendancyName,allocated=node.alloc or false,pathLength=node.path and #node.path,masteryEffects=node.masteryEffects}
	end
	table.sort(context.passives)
	for _,gem in pairs(build.data.gems) do catalog.gems[#catalog.gems+1] = {name=gem.name,id=gem.id,maxLevel=gem.naturalMaxLevel} end
	for _,option in ipairs(require("Modules.ConfigOptions")) do
		if option.var then
			local choices = { }
			local control = build.configTab.varControls[option.var]
			if option.type == "list" then for _,entry in ipairs(control and control.list or { }) do choices[#choices+1] = {value=entry.val,label=entry.label} end end
			catalog.config[#catalog.config+1] = {key=option.var,label=StripEscapes(option.label or ""),type=option.type,choices=choices}
		end
	end
	for _,class in pairs(build.spec.tree.classes) do
		local entry = {name=class.name,ascendancies={}}
		for _,ascendancy in pairs(class.classes) do entry.ascendancies[#entry.ascendancies+1] = ascendancy.name end
		catalog.classes[#catalog.classes+1] = entry
	end
	return {schemaVersion=1,session=M.session,capturedAt=os.date("!%Y-%m-%dT%H:%M:%SZ"),context=context,catalog=catalog}
end

function M.publishState()
	writeFile(path("state"),{schemaVersion=1,session=M.session,enabled=M.enabled,heartbeat=os.time(),revision=M.contextRevision,connectionTest=M.connectionTest,proposal=M.status,history=M.historySummary(),plan=M.plan,diagnostics={lastPoll=M.lastPoll,lastContext=M.lastContext,lastRequest=M.lastRequest,lastError=M.lastError,undoDepth=#M.undo}})
end

function M.refresh(build)
	local captured = M.capture(build)
	M.contextRevision = captured.context.revision
	M.contextStamp=require("Modules.PlanningRevision").stamp(build)
	M.lastContext = os.time()
	writeFile(path("context"),captured)
	M.publishState()
end

function M.enable(build)
	M.client=nil;M.connectionTest=nil
	M.enabled,M.build,M.prepared,M.status,M.contextRevision = true,build,nil,nil,nil
	if M.owner ~= build then M.history,M.undo,M.previous,M.previousCache,M.comparison = {},{},nil,nil,nil end
	M.owner = build
	M.session = sha1(tostring({})..tostring(os.time())..tostring(GetTime()))
	local ok,err = pcall(M.refresh,build)
	if not ok then M.enabled=false; error(err) end
end

function M.disable(build)
	if not M.enabled or M.build ~= build then return end
	local tasks=require("Modules.CraftingTasks")
	if tasks.job and tasks.job.requestId then tasks.cancel("Desktop connection closed") end
	M.enabled,M.prepared = false,nil
	M.publishState()
end

function M.close(build)
	if M.owner ~= build and M.build ~= build then return end
	local tasks=require("Modules.CraftingTasks")
	if tasks.job and tasks.job.requestId then tasks.cancel("Desktop connection closed") end
	M.enabled,M.prepared,M.status,M.build,M.owner = false,nil,nil,nil,nil
	M.history,M.undo,M.previous,M.previousCache,M.comparison = {},{},nil,nil,nil
	pcall(M.publishState)
end

function M.configure(plan)
	assert(type(plan) == "table","Invalid build goals")
	local valid = false
	for _,goal in ipairs(insights.goals) do if plan.goal == goal then valid=true end end
	assert(valid,"Unknown build goal")
	if plan.budget then assert(type(plan.budget) == "number" and plan.budget >= 0 and plan.budget < math.huge and type(plan.currency) == "string" and #plan.currency > 0,"Budget needs a currency and a finite amount") end
	local allowed = { }
	for _,key in ipairs(metrics) do allowed[key]=true end
	for key,value in pairs(plan.minimums or { }) do assert(allowed[key] and type(value) == "number" and value == value and math.abs(value) < math.huge,"Invalid minimum metric") end
	M.plan = copyTable(plan)
end

function M.evaluate(prepared)
	local evaluation = insights.evaluate(prepared.before,prepared.after,M.plan,prepared.quote,prepared.audit)
	if prepared.evaluation.configurationChanged then
		evaluation.eligible=false; evaluation.configurationChanged=true
		evaluation.issues[#evaluation.issues+1]="Configuration differs from the base; excluded from ranking."
	end
	return evaluation
end

function M.summary(prepared)
	local resolved = M.capture(prepared.candidate).context
	-- Avoid duplicating large opaque simulator exports across every comparison result.
	resolved.craftingProjectSummaries = { }
	for _,project in ipairs(resolved.craftingProjects) do resolved.craftingProjectSummaries[#resolved.craftingProjectSummaries+1]={id=project.id,title=project.title,slot=project.slot} end
	resolved.craftingProjects = nil
	return {id=prepared.id,title=prepared.title,baseRevision=prepared.baseRevision,before=prepared.before,after=prepared.after,delta=prepared.delta,warnings=prepared.warnings,
		resolved=resolved,changes=prepared.changes,audit=prepared.audit,evaluation=prepared.evaluation,
		instructions="Open AI builds in PoB to review. Only a desktop button can apply this proposal."}
end

function M.historySummary()
	local result = { }
	for _,entry in ipairs(M.history) do entry.evaluation=M.evaluate(entry); result[#result+1] = {id=entry.id,title=entry.title,baseRevision=entry.baseRevision,after=entry.after,evaluation=entry.evaluation} end
	return result
end

function M.remember(prepared)
	M.history[#M.history+1] = prepared
	if #M.history > 8 then table.remove(M.history,1) end
end

function M.selectHistory(id)
	for _,entry in ipairs(M.history) do
		if entry.id == id then
			assert(entry.base == main.modes.BUILD and entry.baseRevision == M.revision(main.modes.BUILD),"This candidate uses an older base. Restore that base or request a fresh proposal.")
			entry.evaluation = M.evaluate(entry)
			M.prepared = entry
			M.status = M.summary(entry); M.status.status = "review"
			M.publishState()
			return entry
		end
	end
	error("Candidate is no longer in session history")
end

function M.calculateBatch(build, request)
	local entries = request.candidates or request.stages
	assert(type(entries) == "table" and #entries >= 1 and #entries <= (request.kind == "leveling" and 8 or 5),"Invalid candidate count")
	local results,cumulative,previousLevel = {},{},0
	for index,entry in ipairs(entries) do
		local proposal
		if request.kind == "leveling" then
			integer(entry.level,1,100,"milestone level")
			assert(entry.level > previousLevel,"Milestone levels must increase")
			previousLevel = entry.level
			for _,operation in ipairs(entry.operations or { }) do assert(operation.type ~= "set_character","Milestone character level is set by the stage"); cumulative[#cumulative+1]=operation end
			local operations = {{type="set_character",level=entry.level}}
			for _,operation in ipairs(cumulative) do operations[#operations+1]=operation end
			proposal = {mode="edit",title=entry.title,baseRevision=request.baseRevision,operations=operations,quote=entry.quote}
		else proposal = entry end
		local ok,prepared = pcall(M.prepare,build,proposal)
		if ok then
			prepared.id = request.id.."-"..index
			M.remember(prepared)
			local summary = M.summary(prepared)
			summary.status="calculated"; summary.level=prepared.candidate.characterLevel
			results[#results+1] = summary
		else
			results[#results+1] = {title=entry.title,status="failed",error=tostring(prepared):match("^[^\n]+")}
		end
	end
	local ranking = { }
	for _,entry in ipairs(results) do if entry.evaluation and entry.evaluation.eligible and entry.evaluation.score then ranking[#ranking+1] = {id=entry.id,title=entry.title,score=entry.evaluation.score,cost=entry.evaluation.quote and entry.evaluation.quote.amount,scorePerCurrency=entry.evaluation.scorePerCurrency} end end
	table.sort(ranking,function(a,b) if a.score == b.score then return a.id < b.id end; return a.score > b.score end)
	M.status = {id=request.id,status="compared",kind=request.kind,results=results,ranking=ranking,plan=M.plan,
		instructions="Candidates are calculated against the same desktop base. Select one in AI builds > Candidates to review and apply. Leveling stages accumulate changes; no stage has been applied."}
	M.comparison = M.status
end

function M.poll(build, force)
	require("Modules.CraftingTasks").tick(build)
	require("Modules.JourneyUpgrades").tick(build)
	if not M.enabled then return end
	local upgrades=require("Modules.JourneyUpgrades")
	if upgrades.job and upgrades.job.build==build and M.status and M.status.kind=="journeyUpgrades" then local result=upgrades.current(build);M.status.progress={completed=result.completed,total=result.total,phase=upgrades.job.phase} end
	if M.build ~= build then M.close(M.build); return end
	if not force and GetTime() < (M.nextPoll or 0) then return end
	M.nextPoll = GetTime()+1000
	local clientFile=io.open(path("client"),"rb")
	if clientFile then
		local raw=clientFile:read(8193);clientFile:close()
		local ok,client=pcall(json.decode,raw)
		if ok and type(client)=="table" and client.session==M.session and type(client.seenAt)=="number" and client.seenAt<=os.time()+5 and client.seenAt>=os.time()-180 and type(client.name)=="string" and #client.name<=80 then
			M.client=client
			if M.connectionTest and client.testNonce==M.connectionTest.nonce then M.connectionTest.passed=true end
		end
	end
	M.lastPoll = os.time()
	local requestId
	local ok,err = pcall(function()
		if build.buildFlag then return end
		local revisions=require("Modules.PlanningRevision")
		if not M.contextRevision or not revisions.same(M.contextStamp,revisions.stamp(build)) then M.refresh(build) else M.publishState() end
		local file = io.open(path("request"),"rb")
		if not file then return end
		local requestText = file:read(262145); file:close()
		os.remove(path("request"))
		assert(#requestText <= 262144,"Proposal exceeds the supported size")
		local request = assert(json.decode(requestText),"Invalid proposal JSON")
		assert(request.session == M.session,"Proposal belongs to another desktop session")
		assert(type(request.id) == "string" and request.id:match("^[%w%-]+$") and #request.id <= 80,"Invalid proposal ID")
		requestId=request.id
		if M.prepared then return end
		M.lastRequest,M.lastError = os.time(),nil
		if request.kind == "craftCancel" then
			local tasks=require("Modules.CraftingTasks")
			assert(tasks.job and tasks.job.requestId == request.requestId,"No matching active crafting request")
			tasks.cancel("Cancelled from the MCP client")
			M.status={id=request.id,status="cancelled",cancelledId=request.requestId};M.publishState();return
		end
		assert(not require("Modules.CraftingTasks").job,"Finish or cancel the active crafting job first")
		assert(not require("Modules.JourneyUpgrades").job,"Finish or cancel upgrade measurements first")
		if request.kind=="journeyUpgrades" then
			assert(request.baseRevision==M.revision(build),"Build changed. Refresh Journey context.")
			local session=M.session
			require("Modules.JourneyUpgrades").start(build,function(result)
				if not M.enabled or M.session~=session then return end
				M.status={id=request.id,status=result.cancelled and "cancelled" or "measured",upgrades=result};M.publishState()
			end)
			M.status={id=request.id,status="calculating",kind="journeyUpgrades"};M.publishState();return
		end
		if request.kind=="generate_loot_filter" or request.kind=="test_loot_filter" or request.kind=="test_loot_filter_examples" or request.kind=="export_loot_filter" then
			assert(request.baseRevision==M.revision(build),"Build changed. Refresh loot-filter context.")
			local filters=require("Modules.LootFilters")
			local profile=request.profile or filters.find(build.savers.LootFilters.data,request.profileId)
			assert(profile,"Choose a loot-filter profile")
			profile=filters.validate({schemaVersion=1,activeId=profile.id,profiles={profile}}).profiles[1]
			if request.kind=="test_loot_filter_examples" then
				local session=M.session
				local function publish(status,values)
					if not M.enabled or M.session~=session then return end
					M.status={id=request.id,status=status,baseRevision=request.baseRevision}
					for key,value in pairs(values) do M.status[key]=value end;M.publishState()
				end
				local job=require("Modules.CraftingTasks").start(build,function(checkpoint)
					return filters.simulateExamples(profile,request.sampleSetId,request.offset,request.limit,checkpoint)
				end,function(result)
					if M.revision(build)~=request.baseRevision then publish("failed",{error="Build changed. Refresh loot-filter context."}) else publish("tested",{examples=result}) end
				end,function(message) publish("failed",{error=message}) end,function(progress) publish("calculating",{progress=progress}) end,"Filter example evaluation slice")
				job.requestId=request.id;publish("calculating",{});return
			elseif request.kind=="generate_loot_filter" then
				local rules,warnings=filters.generate(build,profile);profile.rules=rules;M.status={id=request.id,status="generated",profile=profile,warnings=warnings}
			elseif request.kind=="test_loot_filter" then
				assert(type(request.sample)=="table","Supply drop properties");M.status={id=request.id,status="tested",result=filters.simulate(profile,request.sample)}
			else local raw,report=filters.compile(profile);M.status={id=request.id,status="exported",filter=raw,report=report} end
			M.publishState();return
		end
		if request.kind == "atlasSearch" or request.kind == "atlasConnect" then
			assert(request.baseRevision == M.revision(build),"Build changed. Refresh Atlas context.")
			local planner=require("Modules.AtlasPlanner")
			local result
			if request.kind == "atlasSearch" then result=planner.search(request.version,request.query,request.limit)
			else
				assert(request.optimize==nil or type(request.optimize)=="boolean","Invalid Atlas optimization setting")
				local plan,added,routing=(request.optimize and planner.connectOptimized or planner.connect)(request.plan,request.targets,request.avoid)
				result={plan=plan,added=added,routing=routing,report=planner.report(plan)}
				if planner.tree(plan.version).mode=="ruthless" then result.officialUrlWarning="Official Ruthless Atlas link encoding is not verified; use the versioned plan JSON."
				else result.officialUrl=planner.url(plan) end
			end
			M.status={id=request.id,status="atlas",atlas=result}; M.publishState(); return
		end
		if request.kind == "craftAction" or request.kind == "craftSimulate" or request.kind == "craftCalculate" or request.kind == "craftOptimize" then
			assert(request.baseRevision == M.revision(build),"Build changed. Refresh crafting context.")
			local raw=request.itemText
			if not raw then local slot=assert(build.itemsTab.slots[request.slot],"Unknown item slot"); raw=assert(build.itemsTab.items[slot.selItemId],"Selected slot is empty").raw end
			local simulator=require("Modules.CraftingSimulator")
			M.status={id=request.id,status="calculating"}; M.publishState()
			if request.kind == "craftSimulate" or request.kind == "craftOptimize" or request.kind == "craftCalculate" then
				local session=M.session;local options=copyTable(request.options or {});options.treeVersion=build.spec.treeVersion
				local function publish(status,values)
					if not M.enabled or M.session ~= session then return end
					M.status={id=request.id,status=status,baseRevision=request.baseRevision}
					for key,value in pairs(values) do M.status[key]=value end;M.publishState()
				end
				local job=require("Modules.CraftingTasks").start(build,function(checkpoint)
					options.checkpoint=checkpoint
					if request.kind == "craftCalculate" then return simulator.calculate(raw,request.action,request.targets,request.initialState,options) end
					return request.kind == "craftOptimize" and simulator.optimizeFossils(raw,request.targets,options) or simulator.simulate(raw,request.recipe,options)
				end,function(result) publish("crafted",{nativeCrafting=result}) end,function(message) publish("failed",{error=message}) end,function(progress) publish("calculating",{progress=progress}) end)
				job.requestId=request.id
			else
				local result=simulator.perform(raw,request.action,request.seed,request.initialState,build.spec.treeVersion)
				M.status={id=request.id,status="crafted",nativeCrafting=result}; M.publishState()
			end
			return
		end
		if request.kind == "craftInspect" then
			assert(request.baseRevision == M.revision(build),"Build changed. Refresh crafting context.")
			local raw = request.itemText
			if not raw then
				local slot = assert(build.itemsTab.slots[request.slot],"Unknown item slot")
				raw = assert(build.itemsTab.items[slot.selItemId],"Selected slot is empty").raw
			end
			M.status = {id=request.id,status="inspected",crafting=require("Modules.CraftingProjects").inspect(raw,request.query,request.limit)}
			local ok,catalog=pcall(require("Modules.CraftingSimulator").catalog,raw,request.query,request.limit,request.initialState,build.spec.treeVersion)
			if ok then
				M.status.crafting.nativeEngine=catalog
				if request.action then
					local simulator=require("Modules.CraftingSimulator");local model=simulator.model(raw)
					local state=request.initialState and simulator.validateState(model,request.initialState) or model.initial
					local action=copyTable(request.action);action.allflame=action.allflame or {auto=true}
					local valid,profile=pcall(simulator.allflameProfile,model,state,action)
					if valid then catalog.allflameProfile=profile else catalog.allflameUnavailable=tostring(profile):match("^[^\n]+") end
				end
			else M.status.crafting.nativeEngineUnavailable=tostring(catalog):match("^[^\n]+") end
			M.publishState()
			return
		end
		if request.kind == "plan" then
			M.configure(request.plan)
			M.status = {id=request.id,status="configured",title="Build goals updated"}
			M.refresh(build)
			return
		end
		M.status = {id=request.id,title=request.proposal and request.proposal.title,status="calculating"}
		M.publishState()
		if request.kind == "compare" or request.kind == "leveling" then
			M.calculateBatch(build,request)
		else
			local prepared = M.prepare(build,request.proposal)
			prepared.id = request.id
			M.remember(prepared)
			M.prepared = prepared
			M.status = M.summary(prepared)
			M.status.status = "review"
		end
		M.publishState()
	end)
	if not ok then
		M.lastError = tostring(err):match("^[^\n]+")
		M.status = {id=requestId,status="failed",error=M.lastError}
		pcall(M.publishState)
	end
end

function M.reject()
	M.prepared = nil
	if M.status then M.status.status = "rejected" end
	M.publishState()
end

function M.restore()
	assert(M.previous and main.modes.BUILD == M.build,"No original build available")
	assert(M.revision(M.build) == M.appliedRevision,"The proposed build has been edited. Save your work before switching builds.")
	local original = M.previous
	local entry = M.undo[#M.undo]
	assert(entry and entry.build == original,"Undo history is unavailable")
	table.remove(M.undo)
	GlobalCache = entry.cache
	main.modes.BUILD = original
	original.spec:SetWindowTitleWithBuildClass()
	local previous = M.undo[#M.undo]
	M.previous,M.previousCache,M.build = previous and previous.build,previous and previous.cache,original
	M.appliedRevision = M.revision(original)
	M.owner = original
	if M.status then M.status.status = "reverted" end
	M.refresh(original)
	return original
end

return M
