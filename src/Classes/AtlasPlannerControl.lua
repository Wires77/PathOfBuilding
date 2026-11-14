-- Atlas planning is separate from the character tree and its calculations.
local atlas=require("Modules.AtlasPlanner")
local strategy=require("Modules.AtlasStrategy")
local browser=require("Classes.PlanningBrowserControl")
local Panel={}
local function safely(callback)
	local ok,err=pcall(callback)
	if not ok then main:OpenMessagePopup("Atlas planner",require("Modules.PlanningUI").errorText(err)) end
end
local function button(x,y,w,label,callback)
	return new("ButtonControl"):ButtonControl({"TOPLEFT",nil,"TOPLEFT"},{x,y,w,24},label,function() safely(callback) end)
end
local function edit(x,y,w,h,value,prompt,limit,clearable)
	return new("EditControl"):EditControl({"TOPLEFT",nil,"TOPLEFT"},{x,y,w,h},value or "",prompt,h>24 and "^%C\t\n" or nil,limit,nil,h > 24 and 16 or nil,nil,clearable)
end
local ui=require("Modules.PlanningUI")
local rows=ui.rows
local Canvas=newClass("AtlasTreeCanvas","Control","TooltipHost")
function Canvas:AtlasTreeCanvas(rect,tree,selected,onSelect)
	self:Control({"TOPLEFT",nil,"TOPLEFT"},rect)
	self:TooltipHost();self.art=require("Modules.AtlasArt").load(tree.version)
	self.tree,self.selected,self.onSelect=tree,selected,onSelect
	self:Fit();self:StartView()
	return self
end
function Canvas:Fit()
	local lowX,highX,lowY,highY=math.huge,-math.huge,math.huge,-math.huge
	for _,node in pairs(self.tree.nodes) do lowX=math.min(lowX,node.x); highX=math.max(highX,node.x); lowY=math.min(lowY,node.y); highY=math.max(highY,node.y) end
	self.centerX,self.centerY=(lowX+highX)/2,(lowY+highY)/2
	self.mapBounds={lowX,lowY,highX,highY}
	self.scale=math.min((self.width-30)/(highX-lowX),(self.height-30)/(highY-lowY))
end
function Canvas:StartView()
	local start=self.tree.nodes[self.tree.start]
	self.scale=0.16;self.centerX=start.x;self.centerY=start.y-self.height/self.scale*0.28
end
function Canvas:Position(node)
	return self.width/2+(node.x-self.centerX)*self.scale,self.height/2+(node.y-self.centerY)*self.scale
end
function Canvas:IsMouseOver() return self:IsShown() and self:IsMouseInBounds() end
function Canvas:Draw()
	local x,y=self:GetPos()
	local cursorX,cursorY=GetCursorPos()
	if self.drag then
		self.centerX=self.drag.centerX-(cursorX-self.drag.x)/self.scale
		self.centerY=self.drag.centerY-(cursorY-self.drag.y)/self.scale
	end
	SetViewport(x,y,self.width,self.height)
	SetDrawColor(0.035,0.045,0.065); DrawImage(nil,0,0,self.width,self.height)
	local bounds=self.tree.bounds
	if bounds then
		local centerX,centerY=self:Position({x=(bounds[1]+bounds[3])/2,y=(bounds[2]+bounds[4])/2})
		SetDrawColor(0.8,0.8,0.8)
		local sheet=self.art.sprites.atlasBackground;local rect=sheet.coords.AtlasPassiveBackground
		self.art:draw("atlasBackground","AtlasPassiveBackground",centerX,centerY,(bounds[3]-bounds[1])*self.scale/rect.w)
	end
	for _,group in ipairs(self.tree.groups or {}) do
		local a,b=self:Position(group)
		local rect=self.art.sprites.groupBackground.coords[group.background]
		if rect and a+rect.w*self.scale>=0 and b+rect.h*self.scale>=0 and a-rect.w*self.scale<=self.width and b-rect.h*self.scale<=self.height then
			SetDrawColor(0.8,0.8,0.8);self.art:draw("groupBackground",group.background,a,b,self.scale*2)
		end
	end
	for _,node in ipairs(self.tree.decorations or {}) do
		local a,b=self:Position(node);SetDrawColor(0.85,0.85,0.85);self.art:draw("mastery",node.icon,a,b,self.scale*2)
	end
	local allocated={[self.tree.start]=true}
	local desired={};for _,id in ipairs(self.selected().desired or {}) do desired[id]=true end
	local comparison=self.comparison
	local avoided={}; for _,id in ipairs(self.avoided and self.avoided() or {}) do avoided[id]=true end
	for _,id in ipairs(self.selected().nodes) do allocated[id]=true end
	local planned=copyTable(allocated);for id in pairs(self.preview or {}) do planned[id]=true end
	for id,node in pairs(self.tree.nodes) do
		local a,b=self:Position(node)
		for _,other in ipairs(node.links) do if id < other then
			local c,d=self:Position(self.tree.nodes[other])
			if allocated[id] and allocated[other] then
				if comparison and (not comparison.before[id] or not comparison.before[other]) then SetDrawColor(0.3,0.95,0.5) else SetDrawColor(0.75,0.61,0.25) end
			elseif comparison and comparison.before[id] and comparison.before[other] then SetDrawColor(0.9,0.3,0.3)
			elseif planned[id] and planned[other] then SetDrawColor(0.25,0.8,0.75) else SetDrawColor(0.18,0.22,0.29) end
			local dx,dy=c-a,d-b; local length=math.max(1,math.sqrt(dx*dx+dy*dy)); local ox,oy=-dy/length,dx/length
			if math.max(a,c)>=0 and math.min(a,c)<=self.width and math.max(b,d)>=0 and math.min(b,d)<=self.height then
				DrawImageQuad(nil,a+ox,b+oy,c+ox,d+oy,c-ox,d-oy,a-ox,b-oy)
			end
		end end
	end
	self.hover=nil; local distance=math.huge
	local margin=160*self.scale+4
	for id,node in pairs(self.tree.nodes) do
		local a,b=self:Position(node)
		local r=node.kind == "keystone" and 5 or node.kind == "notable" and 4 or 2
		if avoided[id] then SetDrawColor(1,0.25,0.25) elseif allocated[id] then SetDrawColor(1,0.78,0.3) elseif node.kind == "keystone" then SetDrawColor(0.65,0.44,0.9) else SetDrawColor(0.45,0.56,0.7) end
		if self.focus == id then SetDrawColor(0.3,1,0.85); r=r+2 end
		if a > -margin and b > -margin and a < self.width+margin and b < self.height+margin then
			local kind=node.kind == "gateway" and "wormhole" or node.kind == "small" and "normal" or node.kind
			local frame=node.kind == "gateway" and "WormholeFrame" or node.kind == "keystone" and "KeystoneFrame" or node.kind == "notable" and "NotableFrame" or "PSSkillFrame"
			local active=allocated[id]
			SetDrawColor(1,1,1);self.art:draw(kind..(active and "Active" or "Inactive"),node.icon or "Wormhole",a,b,self.scale*2)
			if node.kind == "small" then frame=active and "PSSkillFrameActive" or "PSSkillFrame" else frame=frame..(active and "Allocated" or "Unallocated") end
			if avoided[id] or comparison and comparison.before[id] and not allocated[id] then SetDrawColor(1,0.25,0.25)
			elseif desired[id] then SetDrawColor(0.2,1,0.85) else SetDrawColor(0.9,0.9,0.9) end
			local highlight=node.kind=="keystone" and "KeystoneFrameCanAllocate" or node.kind=="notable" and "NotableFrameCanAllocate" or node.kind=="gateway" and "WormholeFrameHighlight" or "PSSkillFrameHighlighted"
			self.art:draw("frame",(self.focus == id or desired[id] or self.preview and self.preview[id] or self.matches and self.matches[id]) and highlight or frame,a,b,self.scale*2)
			if id==self.tree.start then self.art:draw("startNode","AtlasPassiveSkillScreenStart",a,b,self.scale*2) end
		end
		local dist=(cursorX-x-a)^2+(cursorY-y-b)^2
		local radius=math.max(8,(node.kind=="keystone" and 68 or node.kind=="gateway" and 86 or node.kind=="notable" and 49 or 34)*self.scale)
		if self:IsMouseOver() and dist<=radius*radius and dist < distance then self.hover=id; distance=dist end
	end
	-- A small overview preserves orientation while zoomed into a cluster.
	local bounds=self.mapBounds
	local mx,my,mw,mh=self.width-132,self.height-104,120,92
	SetDrawColor("^x344253");DrawImage(nil,mx,my,mw,mh);SetDrawColor("^x101822");DrawImage(nil,mx+1,my+1,mw-2,mh-2)
	local sx,sy=(mw-8)/(bounds[3]-bounds[1]),(mh-8)/(bounds[4]-bounds[2])
	for id,node in pairs(self.tree.nodes) do
		local px,py=mx+4+(node.x-bounds[1])*sx,my+4+(node.y-bounds[2])*sy
		SetDrawColor(allocated[id] and "^xD3B987" or self.matches and self.matches[id] and "^x64DBCE" or "^x42516A");DrawImage(nil,px,py,2,2)
	end
	local vx=math.max(mx+1,mx+4+(self.centerX-self.width/(2*self.scale)-bounds[1])*sx)
	local vy=math.max(my+1,my+4+(self.centerY-self.height/(2*self.scale)-bounds[2])*sy)
	local vr=math.min(mx+mw-1,mx+4+(self.centerX+self.width/(2*self.scale)-bounds[1])*sx)
	local vb=math.min(my+mh-1,my+4+(self.centerY+self.height/(2*self.scale)-bounds[2])*sy)
	if vr>vx and vb>vy then SetDrawColor("^x83C8EF");DrawImage(nil,vx,vy,vr-vx,1);DrawImage(nil,vx,vb,vr-vx,1);DrawImage(nil,vx,vy,1,vb-vy);DrawImage(nil,vr,vy,1,vb-vy) end
	SetViewport()
	if self.hover then
		local node=self.tree.nodes[self.hover];self.tooltip:Clear();self.tooltip:AddLine(18,node.name)
		for _,stat in ipairs(node.stats) do self.tooltip:AddLine(14,stat) end
		if desired[self.hover] then self.tooltip:AddLine(14,"Desired route target") end
		self.tooltip:AddLine(14,"Shift-click: toggle desired target")
		self.tooltip:AddLine(14,"Double click to connect this node")
		SetDrawLayer(nil,100);self.tooltip:Draw(cursorX,cursorY,1,1,main.viewPort);SetDrawLayer(nil,0)
	end
end
function Canvas:OnKeyDown(key,doubleClick)
	if not self:IsMouseOver() then return end
	local cx,cy=self:GetPos();local px,py=GetCursorPos();px,py=px-cx,py-cy
	if key=="LEFTBUTTON" and px>=self.width-132 and py>=self.height-104 and px<self.width-12 and py<self.height-12 then
		local b=self.mapBounds;self.centerX=b[1]+(px-self.width+128)/112*(b[3]-b[1]);self.centerY=b[2]+(py-self.height+100)/84*(b[4]-b[2]);return
	end
	if key == "LEFTBUTTON" and self.hover then
		self.focus=self.hover
		if self.onIntent and (IsKeyDown("SHIFT") or self.intentMode and self.intentMode~="Select nodes") then self.onIntent(self.hover,IsKeyDown("SHIFT") and "desired" or self.intentMode=="Mark desired" and "desired" or "avoided")
		else self.onSelect(self.hover);if doubleClick and self.onActivate then self.onActivate(self.hover) end end
	elseif key == "LEFTBUTTON" or key == "RIGHTBUTTON" then
		local x,y=GetCursorPos(); self.drag={x=x,y=y,centerX=self.centerX,centerY=self.centerY}; return self
	end
end
function Canvas:OnKeyUp(key)
	if key == "WHEELUP" or key == "WHEELDOWN" then
		local old=self.scale
		self.scale=key == "WHEELUP" and math.min(0.8,old*1.25) or math.max(0.008,old/1.25)
		local x,y=self:GetPos(); local cursorX,cursorY=GetCursorPos()
		self.centerX=self.centerX+(cursorX-x-self.width/2)*(1/old-1/self.scale)
		self.centerY=self.centerY+(cursorY-y-self.height/2)*(1/old-1/self.scale)
	else self.drag=nil end
end
function Canvas:OnFocusLost() self.drag=nil end

function Panel.Open(build,source,layout)
	local store=build.savers.AtlasPlans
	local version=atlas.defaultVersion(build.spec.treeVersion)
	local draft=copyTable(source or store.plans[1] or {id="atlas-"..require("sha1")(tostring({})..os.time()):sub(1,12),title="New Atlas plan",version=version,budget=atlas.tree(version).maxPoints,nodes={},notes=""})
	local width=layout and layout.width or math.min(1180,main.screenW-40); local height=layout and layout.height or math.min(820,main.screenH-50)
	local inspector=math.max(260,math.min(width-600,layout and (layout.inspectorWidth or layout.restore and layout.restore.inspectorWidth) or 260))
	local graphWidth=width-inspector-48; local graphHeight=height-262; local side=graphWidth+32
	local controls,undo,avoided,redo={},{},copyTable(draft.avoided or {}),{}
	local preferred
	local pointUsage,routeAvailable
	local function current()
		local result=copyTable(draft); result.title=controls.title.buf; result.budget=assert(tonumber(controls.budget.buf),"Enter a point budget"); result.notes=controls.notes.buf
		if result.avoided~=nil or #avoided>0 then result.avoided=copyTable(avoided) end
		return atlas.validate(result)
	end
	local function refresh(id)
		if draft.avoided~=nil or #avoided>0 then draft.avoided=copyTable(avoided) end
		if controls.canvas.tree.version ~= draft.version then
			controls.canvas.tree=atlas.tree(draft.version);controls.canvas.art=require("Modules.AtlasArt").load(draft.version); controls.canvas:Fit(); avoided={}
			controls.results:SetList({}); controls.matchCount.label="Search names and modifiers"
			controls.avoid.label="Avoid selected"
		end
		if not controls.canvas.tree.nodes[controls.canvas.focus] then controls.canvas.focus=nil end
		controls.version:SelByValue(draft.version)
		local report=atlas.report(draft)
		if controls.strategySummary then
			local counts={};for _,id in ipairs(draft.nodes) do local mechanic=strategy.mechanic(controls.canvas.tree.nodes[id]);counts[mechanic]=(counts[mechanic] or 0)+1 end
			local parts={};for name,count in pairsSortByKey(counts) do parts[#parts+1]=name.." "..count end
			local lines={#parts>0 and table.concat(parts," | ") or "Allocate nodes to build your strategy.",#(draft.desired or {}).." desired | "..#avoided.." avoided | "..report.counts.small.." small nodes | "..report.counts.gateway.." gateways"}
			controls.strategySummary.list=ui.rows(lines,graphWidth-16,14)
		end
		local budget=tonumber(controls.budget.buf)
		if budget and budget==math.floor(budget) and budget>=0 and budget<=controls.canvas.tree.maxPoints then
			report.budget=budget;report.remaining=budget+report.bonus-report.used;pointUsage=report
			local warning;controls.status.tooltipText=nil
			if report.remaining>=0 then local candidate=copyTable(draft);candidate.budget=budget;local reachable,why,needed=atlas.budgetReachability(candidate);if reachable~=true then warning=reachable==false and ("Need "..needed.." points before grant") or "Grant path needs review";controls.status.tooltipText=why end end
			controls.status.label=string.format("%s%d / %d points%s | %s",(report.remaining<0 or warning) and "^xE58F8F" or "^7",report.used,report.budget,report.bonus>0 and " + "..report.bonus.." granted" or "",warning or (report.remaining<0 and (-report.remaining).." over budget" or report.remaining.." left"))
		else pointUsage=nil;controls.status.label="^xE58F8FEnter a budget from 0 to "..controls.canvas.tree.maxPoints end
		local node=atlas.tree(draft.version).nodes[id or controls.canvas.focus]
		local lines={node and node.name or "Select a node on the tree or search.",node and node.kind:gsub("^%l",string.upper) or "Search a mechanic, or select a node."}
		controls.canvas.preview={};routeAvailable=false
		if node then
			for _,stat in ipairs(node.stats) do lines[#lines+1]=stat end
			local allocated={[controls.canvas.tree.start]=true};for _,other in ipairs(draft.nodes) do allocated[other]=true end
			if not allocated[node.id] then
				local ok,plan=pcall(function() return atlas.connect(current(),{node.id},avoided) end)
				if ok then
					local cost=0;for _,other in ipairs(plan.nodes) do if not allocated[other] then controls.canvas.preview[other]=true;cost=cost+1 end end
					routeAvailable=true;controls.allocate.label="Connect +"..cost
					lines[#lines+1]="";lines[#lines+1]=cost.." new points to connect this node."
				else controls.allocate.label="No route";lines[#lines+1]="";lines[#lines+1]="No route within the point budget and avoided nodes." end
			else controls.allocate.label="Allocated" end
		else controls.allocate.label="Connect path" end
		local detailRows=rows({lines[1]},inspector-30,18)
		for _,row in ipairs(rows({lines[2]},inspector-30,13)) do row[1]="^xA6B3C6"..StripEscapes(row[1]);detailRows[#detailRows+1]=row end
		for i=3,#lines do for _,row in ipairs(rows({lines[i]},inspector-30)) do detailRows[#detailRows+1]=row end end
		controls.details.list=detailRows
		controls.avoid.label=#avoided>0 and "Avoid ("..#avoided..")" or "Avoid selected"
		local costs=strategy.costs(draft,avoided)
		for _,entry in ipairs(controls.results.list) do local resultNode=controls.canvas.tree.nodes[entry.val];if resultNode then entry.label=resultNode.name..(costs[entry.val] and " | +"..costs[entry.val] or " | blocked") end end
	end
	controls.title=edit(16,30,graphWidth-130,24,draft.title,nil,120)
	ui.label(controls,"planLabel",16,10,"Plan name",13)
	ui.label(controls,"budgetLabel",graphWidth-100,10,"Point budget",13)
	controls.budget=edit(graphWidth-100,30,116,24,tostring(draft.budget),nil,3)
	controls.version=new("DropDownControl"):DropDownControl({"TOPLEFT",nil,"TOPLEFT"},{side,30,260,24},atlas.versions,function(_,value)
		if value ~= draft.version then
			controls.version:SelByValue(draft.version)
			local replacement={id=draft.id,title=controls.title.buf,version=value,budget=atlas.tree(value).maxPoints,nodes={},notes=controls.notes.buf}
			main:OpenConfirmPopup("Change Atlas version","Changing versions starts an empty draft. Saved plans are kept.","Change",function() if not layout then main:ClosePopup() end;Panel.Open(build,replacement,layout) end)
		end
	end)
	controls.version:SelByValue(draft.version)
	controls.canvas=new("AtlasTreeCanvas"):AtlasTreeCanvas({16,96,graphWidth,graphHeight},atlas.tree(draft.version),function() return draft end,function(id) refresh(id) end)
	controls.canvas.avoided=function() return avoided end
	controls.status=new("LabelControl"):LabelControl({"TOPLEFT",nil,"TOPLEFT"},{16,70,0,14},"")
	controls.search=edit(side,96,180,24,"",nil,160,true)
	controls.search.placeholder="Search nodes"
	local function findNodes(recenter)
		local mechanic=controls.mechanic:GetSelValue();local filtered=mechanic~="All mechanics" and mechanic or nil
		local matches=strategy.results(draft,controls.search.buf,filtered,avoided);local list={};controls.canvas.matches={}
		for i,entry in ipairs(matches) do
			if i<=100 then list[#list+1]={label=entry.node.name..(entry.cost and " | +"..entry.cost or " | blocked"),val=entry.id} end
			if controls.search.buf~="" or filtered then controls.canvas.matches[entry.id]=true end
		end
		controls.results:SetList(list);controls.results.selIndex=1
		if not recenter then
			if controls.search.buf~="" or filtered then
				if not controls.canvas.matches[controls.canvas.focus] then controls.canvas.focus=list[1] and list[1].val end
				for i,entry in ipairs(list) do if entry.val==controls.canvas.focus then controls.results.selIndex=i end end
				refresh()
			else controls.results:SetList({});controls.canvas.focus=nil;refresh() end
		end
		if recenter and list[1] then controls.results.selFunc(1,list[1]) end
		controls.matchCount.label="^7"..#matches..(#matches==1 and " match" or " matches").." | costs show new points"
	end
	controls.find=button(side+188,96,72,"Go",function() findNodes(true) end)
	controls.find.enabled=function() return #controls.results.list>0 end
	controls.search.changeFunc=function() findNodes(false) end
	controls.search.enterFunc=function() findNodes(true) end
	controls.search.disableCol="^x8797A8"
	controls.results=new("TextListControl"):TextListControl(ui.anchor,{side,188,260,88},nil,{})
	controls.results.selIndex=1
	controls.results.selFunc=function(_,value)
		controls.canvas.focus=value.val; local node=atlas.tree(draft.version).nodes[value.val]
		controls.canvas.centerX,controls.canvas.centerY=node.x,node.y
		controls.canvas.scale=math.max(controls.canvas.scale,0.12); refresh(value.val)
	end
	function controls.results:SetList(entries)
		self.list={};for _,entry in ipairs(entries) do local row=copyTable(entry);local node=controls.canvas.tree.nodes[row.val]
			local title=node and node.name or row.label;while #title>0 and DrawStringWidth(14,"VAR",title)>inspector-30 do title=title:sub(1,-2) end
			row[1]="^7"..title;row.height=40;row.textSize=14;row.subtitle=node and strategy.mechanic(node).." | "..(row.label:match("%+%d+") or "blocked").." points" or "";self.list[#self.list+1]=row
		end
	end
	function controls.results:SelByValue(value,key) for i,row in ipairs(self.list) do if row[key or "val"]==value then self.selIndex=i end end end
	ui.selectable(controls.results,function(row) return row.val end,function(row) for i,entry in ipairs(controls.results.list) do if row==entry then controls.results.selIndex=i end end;controls.results.selFunc(controls.results.selIndex,row) end)
	local mechanics={"All mechanics"};for _,name in ipairs(strategy.mechanics) do mechanics[#mechanics+1]=name end
	controls.mechanic=new("DropDownControl"):DropDownControl(ui.anchor,{side,130,260,24},mechanics,function() findNodes(false) end)
	controls.matchCount=new("LabelControl"):LabelControl(ui.anchor,{side,164,0,14},"Filter a mechanic or search nodes")
	controls.details=new("TextListControl"):TextListControl(ui.anchor,{side,286,260,math.max(54,height-486)},nil,{})
	ui.description(controls,"strategySummary",16,height-158,graphWidth,44,{"Allocate nodes to build your strategy."},14)
	local function syncEditors()
		controls.title:SetText(draft.title); controls.budget:SetText(tostring(draft.budget)); controls.notes:SetText(draft.notes)
	end
	local function snapshot() return {plan=copyTable(draft),avoided=copyTable(avoided)} end
	local function remember() undo[#undo+1]=snapshot();if #undo>40 then table.remove(undo,1) end;redo={} end
	local function change(nextPlan) remember();draft=atlas.validate(nextPlan);avoided=copyTable(draft.avoided or {});controls.canvas.comparison=nil;ui.draft(build,"atlas");syncEditors();refresh() end
	controls.canvas.onIntent=function(id,kind) safely(function() change(require("Modules.AtlasTargets").toggle(current(),id,kind)) end) end
	controls.allocate=button(side,height-188,124,"Connect path",function() assert(controls.canvas.focus,"Select a node first"); change(atlas.connect(current(),{controls.canvas.focus},avoided)) end)
	controls.remove=button(side+136,height-188,124,"Remove branch",function()
		local before=current();local id=assert(controls.canvas.focus,"Select a node first");local after=atlas.remove(before,id)
		local count=#before.nodes-#after.nodes
		if count>1 then
			main:OpenConfirmPopup("Remove Atlas branch",string.format("Removing this node also removes %d disconnected nodes.\n%d nodes will be unallocated. You can undo this change.",count-1,count),"Remove",function() change(after) end)
		else change(after) end
	end)
	controls.undo=button(16,height-86,64,"Undo",function() assert(#undo>0,"No changes to undo");redo[#redo+1]=snapshot();local saved=table.remove(undo);draft=saved.plan;avoided=saved.avoided;syncEditors();refresh() end)
	controls.redo=button(86,height-86,64,"Redo",function() assert(#redo>0,"No changes to redo");undo[#undo+1]=snapshot();local saved=table.remove(redo);draft=saved.plan;avoided=saved.avoided;syncEditors();refresh() end)
	controls.fit=button(156,height-86,70,"Fit tree",function() controls.canvas:Fit() end)
	controls.help=new("LabelControl"):LabelControl({"TOPLEFT",nil,"TOPLEFT"},{16,height-106,0,14},"^7Wheel: zoom | Drag: pan | Shift-click: desire | Double click: connect")
	controls.avoid=button(side,height-156,124,"Avoid selected",function()
		local id=assert(controls.canvas.focus,"Select a node first"); local tree=atlas.tree(draft.version)
		assert(id ~= tree.start,"Cannot avoid the start")
		for _,allocated in ipairs(draft.nodes) do assert(id ~= allocated,"Remove this node before avoiding it") end
		change(require("Modules.AtlasTargets").toggle(current(),id,"avoided"))
	end)
	controls.clearAvoid=button(side+136,height-156,124,"Clear avoided",function() local next=current();next.avoided={};change(next);controls.avoid.label="Avoid selected" end)
	controls.notes=edit(16,110,width-32,height-250,draft.notes,nil,8000)
	controls.stats=button(side,height-124,260,"Allocated stats",function()
		local plan=current();local report=atlas.report(plan);local summary=require("Modules.AtlasTargets").summary(plan)
		local lines={string.format("%d allocated | %d small | %d notables | %d keystones | %d gateways",report.used,report.counts.small,report.counts.notable,report.counts.keystone,report.counts.gateway),summary.connectedDesired.." / "..summary.desired.." desired nodes connected",report.remaining.." points available","Counts describe allocations, not effective map odds or farming income."}
		for _,warning in ipairs(summary.warnings) do lines[#lines+1]=warning end
		local entries={{id="summary",label="Allocated investment overview",category="Overview",details=lines}}
		for _,row in ipairs(summary.mechanics) do entries[#entries+1]={id="mechanic-"..row.name,label=row.name.." | "..row.total.." points",category=row.name,details={row.name,row.small.." small nodes",row.notable.." notables",row.keystone.." keystones",row.gateway.." gateways","Small nodes can carry valuable bonuses; they are not assumed to be wasted travel."}} end
		for _,keystone in ipairs(summary.keystones) do local details={keystone.name,"Review the whole keystone, including restrictions and tradeoffs."};for _,stat in ipairs(keystone.stats) do details[#details+1]=stat end;entries[#entries+1]={id="keystone-"..keystone.id,label=keystone.name.." | Keystone tradeoffs",category="Keystones",details=details} end
		for _,id in ipairs(plan.nodes) do local node=atlas.tree(plan.version).nodes[id];for i,stat in ipairs(node.stats) do entries[#entries+1]={id=id.."-"..i,label=stat,category=strategy.mechanic(node),details={node.name,stat,"Verbatim bonus; keystone interactions are not combined."}} end end
		browser.Open("Atlas bonuses by mechanic",entries)
	end)
	controls.browse=button(232,height-86,100,"Find nodes",function()
		local costs=strategy.results(current(),"",nil,avoided);local entries={}
		for _,entry in ipairs(costs) do
			local node=entry.node
			entries[#entries+1]={id=node.id,label=node.name..(entry.cost and " | +"..entry.cost or " | blocked"),category=strategy.mechanic(node),search=table.concat(node.stats," "),details=function()
				local lines={node.name,node.kind,entry.cost and entry.cost.." new points (before any granted points)" or "Blocked by avoided nodes"};for _,stat in ipairs(node.stats) do lines[#lines+1]=stat end;return lines
			end}
		end
		browser.Open("Find Atlas nodes",entries,{action="Show on tree",choose=function(entry)
			controls.canvas.matches={};for _,match in ipairs(strategy.results(current(),"",entry.category,avoided)) do controls.canvas.matches[match.id]=true end
			controls.search:SetText("");controls.results:SetList({{label=entry.node and entry.node.name or controls.canvas.tree.nodes[entry.id].name,val=entry.id}});controls.matchCount.label="^7"..entry.category.." nodes highlighted"
			controls.mechanic:SelByValue(entry.category)
			controls.canvas.focus=entry.id;local node=controls.canvas.tree.nodes[entry.id];controls.canvas.centerX,controls.canvas.centerY=node.x,node.y;controls.canvas.scale=math.max(0.12,controls.canvas.scale);refresh()
		end})
	end)
	controls.routes=button(338,height-86,86,"Routes",function()
		local target=assert(controls.canvas.focus,"Select a node first");local entries={}
		for i,route in ipairs(strategy.routes(current(),target,avoided,preferred)) do
			local details={route.label,route.cost.." new points","Uses the current point budget and avoided nodes.","New allocations:"}
			for _,id in ipairs(route.added) do
				local node=controls.canvas.tree.nodes[id];details[#details+1]=node.name.." ["..id.."]"
				for _,stat in ipairs(node.stats) do details[#details+1]="  "..stat end
			end
			if #route.added==0 then details[#details+1]="Target is already allocated." end
			entries[#entries+1]={id=i,label=route.label.." | +"..route.cost,details=details,plan=route.plan}
		end
		browser.Open("Compare Atlas routes",entries,{action="Use route",choose=function(entry) change(entry.plan) end})
	end)
	controls.targets=button(522,height-86,100,"Targets",function()
		require("Classes.AtlasTargetsControl").Open(build,{current=current,change=change,selected=function() return controls.canvas.focus end,mode=function(value)
			if value then controls.canvas.intentMode=value;controls.help.label="^7"..ui.fit(value=="Select nodes" and "Wheel: zoom | Drag: pan | Shift-click: desire | Double click: connect" or "Click nodes to "..value:lower().." | Targets: return to selection",graphWidth,14) end
			return controls.canvas.intentMode or "Select nodes"
		end})
	end)
	controls.tools=button(430,height-86,86,"Plan tools",function()
		local entries={
			{id="presets",label="Strategy starting points",details={"Connect up to three nearby notables for a mechanic.","Generated from this version's bundled tree, within your budget.","Editable starting routes, not recommendations for farming profit."}},
			{id="compare",label="Compare with a saved plan",details={"Review added nodes, removed nodes and changed bonus lines.","Both plans must use the same Atlas version."}},
			{id="history",label="Change history",details={#undo.." earlier states | "..#redo.." redo states","History includes routes, node exclusions, imports and budget changes."}},
			{id="preferred",label="Prefer selected node in routes",details={"Use the selected node as a waypoint when comparing routes.",preferred and "Current: "..controls.canvas.tree.nodes[preferred].name or "No preferred waypoint."}},
			{id="clearComparison",label="Clear comparison overlay",details={"Return to the current plan without saved-plan difference colours."}},
		}
		browser.Open("Atlas plan tools",entries,{closeOnChoose=false,action="Open",choose=function(entry)
			main:ClosePopup()
			if entry.id=="presets" then
				local choices={};for i,preset in ipairs(strategy.presets(current())) do local lines={preset.mechanic,"Adds "..(#preset.plan.nodes-#draft.nodes).." points to the current draft.","Compares target orders; keeps existing allocations.",preset.routing and preset.routing.saved and "Order comparison saved "..preset.routing.saved.." points." or "No global optimum is assumed."};for _,id in ipairs(preset.targets) do lines[#lines+1]=controls.canvas.tree.nodes[id].name end;choices[#choices+1]={id=i,label=preset.label,category=preset.mechanic,details=lines,plan=preset.plan} end
				browser.Open("Atlas starting routes",choices,{action="Use starting route",choose=function(choice) change(choice.plan) end})
			elseif entry.id=="compare" then
				local choices={};for _,plan in ipairs(store.plans) do if plan.version==draft.version then
					local comparison=strategy.compare(plan,current());local lines={"Saved: "..plan.title,"Current draft: "..#comparison.added.." added, "..#comparison.removed.." removed"}
					for _,node in ipairs(comparison.added) do lines[#lines+1]="+ "..node.name end;for _,node in ipairs(comparison.removed) do lines[#lines+1]="- "..node.name end
					lines[#lines+1]="Changed bonus counts";for _,stat in ipairs(comparison.stats) do lines[#lines+1]=stat end
					choices[#choices+1]={id=plan.id,label=plan.title,details=lines,plan=plan}
				end end;browser.Open("Compare Atlas plans",choices,{action="Show overlay",choose=function(choice)
					local before={};for _,id in ipairs(choice.plan.nodes) do before[id]=true end;controls.canvas.comparison={before=before};controls.help.label="^7Green: added paths | Red: removed paths | Gold: shared paths"
				end})
			elseif entry.id=="history" then
				local choices={};for i=#undo,1,-1 do local saved=undo[i];choices[#choices+1]={id=i,label="State "..i.." | "..#saved.plan.nodes.." points",details={saved.plan.title,#saved.plan.nodes.." points",#saved.avoided.." exclusions"},saved=saved,index=i} end
				browser.Open("Atlas change history",choices,{action="Restore state",choose=function(choice) remember();draft=copyTable(choice.saved.plan);avoided=copyTable(choice.saved.avoided);syncEditors();refresh() end})
			elseif entry.id=="clearComparison" then controls.canvas.comparison=nil;controls.help.label="^7Wheel: zoom | Drag: pan | Shift-click: desire | Double click: connect"
			else preferred=controls.canvas.focus;refresh() end
		end})
	end)
	controls.copy=button(16,height-104,120,"Copy plan",function() Copy(atlas.export(current())) end)
	controls.import=button(148,height-104,120,"Paste plan",function() change(atlas.import(Paste(),draft.version,draft.id,controls.title.buf,tonumber(controls.budget.buf))); avoided={}; controls.avoid.label="Avoid selected"; controls.budget:SetText(tostring(draft.budget)); controls.version:SelByValue(draft.version); controls.canvas.tree=atlas.tree(draft.version);controls.canvas.art=require("Modules.AtlasArt").load(draft.version); controls.canvas:Fit() end)
	controls.url=button(280,height-104,120,"Official link",function() Copy(atlas.url(current())); main:OpenMessagePopup("Atlas link copied","Official URLs do not carry patch versions. Use Copy plan to preserve the exact version.") end)
	controls.url.enabled=function() return atlas.tree(draft.version).mode~="ruthless" end
	controls.url.tooltipFunc=function(tooltip) tooltip:AddLine(14,atlas.tree(draft.version).mode=="ruthless" and "Ruthless official-link encoding is not verified. Use Copy plan for a versioned share." or "Copy an official Atlas link. Copy plan also preserves the exact version.") end
	controls.keep=button(16,height-42,160,"Keep plan",function() store:Upsert(current());if layout then controls.status.label="^7Plan kept. Save the build to persist it." else main:ClosePopup() end end)
	controls.library=button(188,height-42,120,"Saved plans",function() Panel.Library(build,layout) end)
	controls.new=button(320,height-42,120,"New plan",function() if not layout then main:ClosePopup() end;Panel.Open(build,{id="atlas-"..require("sha1")(tostring({})..os.time()):sub(1,12),title="New Atlas plan",version=draft.version,budget=atlas.tree(draft.version).maxPoints,nodes={},notes=""},layout) end)
	controls.progression=button(452,height-42,180,"Stages & strategy",function() require("Classes.AtlasPlanningControl").Open(build,current(),function(plan) change(plan) end) end)
	controls.close=button(width-132,height-42,116,"Close",function() main:ClosePopup() end)
	controls.page=new("DropDownControl"):DropDownControl(ui.anchor,{side,64,260,24},{"Tree","Notes & sharing"})
	ui.label(controls,"notesLabel",16,88,"Farming goals, maps, supplies and strategy notes")
	ui.label(controls,"ruthlessShareNote",16,height-130,"Ruthless: use Copy plan for versioned sharing.",14)
	controls.ruthlessShareNote.shown=function() return controls.page:GetSelValue()=="Notes & sharing" and atlas.tree(draft.version).mode=="ruthless" end
	for _,key in ipairs({"canvas","strategySummary","search","find","results","mechanic","matchCount","details","allocate","remove","undo","redo","fit","help","avoid","clearAvoid","stats","browse","routes","tools"}) do
		controls[key].shown=function() return controls.page:GetSelValue()=="Tree" end
	end
	for _,key in ipairs({"notes","notesLabel","copy","import","url"}) do controls[key].shown=function() return controls.page:GetSelValue()=="Notes & sharing" end end
	controls.canvas.onActivate=function() if controls.remove:IsEnabled() then controls.remove:Click() else controls.allocate:Click() end end
	controls.undo.enabled=function() return #undo>0 end
	controls.redo.enabled=function() return #redo>0 end
	controls.routes.enabled=function() return controls.canvas.focus~=nil end
	local function allocatedFocus()
		for _,id in ipairs(draft.nodes) do if id==controls.canvas.focus then return true end end
		return false
	end
	controls.allocate.enabled=function() return routeAvailable end
	controls.remove.enabled=allocatedFocus
	controls.avoid.enabled=function() return controls.canvas.focus~=nil and controls.canvas.focus~=controls.canvas.tree.start and not allocatedFocus() end
	controls.clearAvoid.enabled=function() return #avoided>0 end
	if layout then
		controls.close.shown=false
		layout.tick=function() require("Modules.AtlasTargets").tick(build) end
		layout.inspectorWidth=inspector
		layout.viewState=function() return {centerX=controls.canvas.centerX,centerY=controls.canvas.centerY,scale=controls.canvas.scale,focus=controls.canvas.focus,page=controls.page:GetSelValue(),avoided=copyTable(avoided),undo=copyTable(undo),redo=copyTable(redo),preferred=preferred,inspectorWidth=inspector,search=controls.search.buf,mechanic=controls.mechanic:GetSelValue(),title=controls.title.buf,budgetText=controls.budget.buf,notes=controls.notes.buf} end
		-- Keep unfinished editor text separate from the validated graph draft.
		layout.snapshot=function() return copyTable(draft) end
	end
	if layout and layout.restore then
		local view=layout.restore;layout.restore=nil
		controls.canvas.centerX,controls.canvas.centerY,controls.canvas.scale,controls.canvas.focus=view.centerX,view.centerY,view.scale,view.focus
		controls.page:SelByValue(view.page);avoided=view.avoided;undo=view.undo;redo=view.redo or {};preferred=view.preferred
		if view.title~=nil then controls.title:SetText(view.title) end
		if view.notes~=nil then controls.notes:SetText(view.notes) end
		if view.budgetText~=nil then controls.budget:SetText(view.budgetText) end
		controls.search:SetText(view.search or "");controls.mechanic:SelByValue(view.mechanic or "All mechanics");findNodes(false)
	end
	controls.pointBar=new("Control"):Control(ui.anchor,{16,85,graphWidth,3})
	function controls.pointBar:Draw()
		local x,y=self:GetPos();SetDrawColor("^x263343");DrawImage(nil,x,y,graphWidth,3)
		if pointUsage and pointUsage.used>0 then SetDrawColor("^xC8A569");DrawImage(nil,x,y,graphWidth*math.min(1,pointUsage.used/math.max(1,pointUsage.budget+pointUsage.bonus)),3) end
	end
	ui.tabs(controls,controls.page,{{"tab_tree","Tree","Tree"},{"tab_notes","Notes & sharing","Plan & notes"}},side,64,260)
	controls.title.changeFunc=function() ui.draft(build,"atlas") end
	controls.notes.changeFunc=function() ui.draft(build,"atlas") end
	controls.budget.changeFunc=function() ui.draft(build,"atlas");refresh() end
	controls.budget.enterFunc=function() safely(function() local nextPlan=current();if nextPlan.budget~=draft.budget then change(nextPlan) end end) end
	controls.budget.tooltipText="Press Enter to keep this budget in change history."
	if layout then
		ui.splitter(controls,"splitter",graphWidth+20,96,graphHeight,function(delta)
			local source=layout.snapshot();local view=layout.viewState();layout.inspectorWidth=math.max(260,math.min(width-600,inspector-delta));layout.restore=view;Panel.Open(build,source,layout)
		end).shown=controls.canvas.shown
	end
	for _,control in pairs(controls) do
		if type(control.x)=="number" and control.x>=side then
			if control.width==260 then control.width=inspector elseif control.width==124 then control.width=math.floor((inspector-12)/2) end
			if control.x==side+136 then control.x=side+math.floor((inspector-12)/2)+12 end
		end
	end
	ui.style(controls,{allocate=true,keep=true})
	for _,control in pairs(controls) do control.layoutAudit="atlas" end
	refresh()
	if layout then layout.mount(width,height,"Atlas planner",controls) else main:OpenPopup(width,height,"Atlas planner",controls,nil,nil,"close") end
	return controls
end
function Panel.Library(build,layout)
	local store=build.savers.AtlasPlans; local controls,list={},{}
	for _,plan in ipairs(store.plans) do list[#list+1]={label=plan.title.." ["..plan.version.."]",val=plan.id} end
	controls.plans=new("DropDownControl"):DropDownControl({"TOPLEFT",nil,"TOPLEFT"},{16,32,568,24},list)
	controls.info=new("LabelControl"):LabelControl({"TOPLEFT",nil,"TOPLEFT"},{16,76,0,14},"^7"..(store.warning or "Keep farming strategies in this build. Save the build to persist them."))
	local function selected() local choice=controls.plans:GetSelValue(); for _,plan in ipairs(store.plans) do if choice and plan.id == choice.val then return plan end end; error("Choose a saved plan") end
	controls.open=button(16,112,160,"Open plan",function() local plan=selected(); main:ClosePopup(); Panel.Open(build,plan,layout) end)
	controls.delete=button(188,112,160,"Delete plan",function()
		local ok,err=pcall(function() local plan=selected(); store:Remove(plan.id) end)
		if not ok then main:OpenMessagePopup("Saved Atlas plans",ui.errorText(err)); return end
		main:ClosePopup(); Panel.Library(build,layout)
	end)
	controls.open.enabled=#list>0;controls.delete.enabled=#list>0
	controls.close=button(468,160,116,"Close",function() main:ClosePopup() end)
	main:OpenPopup(600,204,"Saved Atlas plans",controls,nil,nil,"close")
end
return Panel
