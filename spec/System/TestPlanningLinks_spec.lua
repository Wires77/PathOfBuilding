describe("Linked planning tools",function()
	local filters=require("Modules.LootFilters")
	local dependencies=require("Modules.LootFilterDependencies")
	local function craft() return {id="helmet",title="Helmet",slot="Helmet",startingItem="Rarity: NORMAL\nIron Hat\nItem Level: 86",goals={},steps={}} end
	before_each(function() newBuild();main.popups={} end)
	after_each(function() main.popups={} end)
	it("lets an older saved filter review and keep the new base",function()
		local profile=filters.profile("old-base","Old base");profile.baseCommit="3ab00dd016b00c6be7acfa989baf498842973d54"
		profile.rules={{id="personal",title="My thread",text='Hide\n BaseType == "Frayed Thread"',enabled=true}}
		local workspace=require("Modules.PlanningWorkspace").new(build)
		workspace:Show("filters",{data={schemaVersion=1,activeId=profile.id,profiles={profile}},page="Overview"})
		workspace.controls.manage:Click();main.popups[1].controls.search:SetText("Audit and update",true);main.popups[1].controls.choose:Click()
		assert.equal("Filter audit",main.popups[1].title);main.popups[1].controls.choose:Click()
		local updated=workspace.cache.filters.layout.snapshot().data.profiles[1]
		assert.equal(filters.source().commit,updated.baseCommit);assert.same(profile.rules,updated.rules)
		assert.is_truthy(filters.compile(updated));workspace.controls.keep:Click()
		local xml=build:SaveDB("Filter update");loadBuildFromXML(xml,"Filter update")
		local saved=build.savers.LootFilters.data.profiles[1];assert.equal(filters.source().commit,saved.baseCommit);assert.same(profile.rules,saved.rules)
	end)
	it("selects and deduplicates examples when switching filter scenes",function()
		local profile=filters.profile("scene-switch","Scene switch");local workspace=require("Modules.PlanningWorkspace").new(build)
		workspace:Show("filters",{data={schemaVersion=1,activeId=profile.id,profiles={profile}},page="Simulate"})
		workspace.controls.sceneKind.selFunc(nil,"Divination cards")
		assert.equal("Divination Cards",workspace.cache.filters.layout.snapshot().sample.Class)
		workspace.controls.sceneStats:Click();assert.matches("12 results",main.popups[1].controls.count.label);main:ClosePopup()
		workspace.controls.sceneKind.selFunc(nil,"Essences")
		assert.matches("Essence",workspace.cache.filters.layout.snapshot().sample.BaseType)
		workspace.controls.sceneStats:Click();assert.matches("11 results",main.popups[1].controls.count.label);main:ClosePopup()
		local draft=workspace.cache.filters.layout.snapshot();draft.sample=require("Modules.LootFilterLibrary").sample();draft.sample.BaseType="Divine Orb"
		workspace:Show("filters",draft);workspace.controls.sceneStats:Click()
		assert.matches("12 results",main.popups[1].controls.count.label);main:ClosePopup()
	end)
	it("distinguishes quoted numeric modifier names from counts when checking linked targets",function()
		build.savers.CraftingProjects:Upsert(craft());local profile=filters.profile("filter","Filter");profile.rules=filters.generate(build,profile)
		profile.rules[1].text='Show\n HasExplicitMod "1" "foo"'
		local current=copyTable(profile.rules);current[1].text='Show\n HasExplicitMod 1 "foo"'
		local generate=filters.generate;filters.generate=function() return current end
		local ok,report=pcall(dependencies.report,build,profile);filters.generate=generate
		assert.is_true(ok);assert.is_true(report.stale);assert.equal("Changed",report.entries[1].status)
	end)
	it("does not mark linked targets stale for harmless string quoting",function()
		build.savers.CraftingProjects:Upsert(craft());local profile=filters.profile("filter","Filter");profile.rules=filters.generate(build,profile)
		profile.rules[1].text='Show\n BaseType "IronHat"'
		local current=copyTable(profile.rules);current[1].text='Show\n BaseType IronHat'
		local generate=filters.generate;filters.generate=function() return current end
		local ok,report=pcall(dependencies.report,build,profile);filters.generate=generate
		assert.is_true(ok);assert.is_false(report.stale)
	end)
	it("detects changed or removed generated targets without treating styles or inventory as dependencies",function()
		local project=craft();build.savers.CraftingProjects:Upsert(project);local profile=filters.profile("filter","Filter");profile.rules=filters.generate(build,profile)
		assert.is_false(dependencies.report(build,profile).stale)
		profile.rules[1].enabled=false;profile.rules[1].text=profile.rules[1].text.."\n SetFontSize 20";assert.is_false(dependencies.report(build,profile).stale)
		project.inventory={require("Modules.CraftingInventory").capture(project,require("Modules.CraftingSimulator").model(project.startingItem).initial)};build.savers.CraftingProjects:Upsert(project);assert.is_false(dependencies.report(build,profile).stale)
		project.startingItem=project.startingItem:gsub("86","87");build.savers.CraftingProjects:Upsert(project);local report=dependencies.report(build,profile);assert.is_true(report.stale);assert.equal("Changed",report.entries[1].status)
		profile.rules=filters.generate(build,profile);assert.is_false(dependencies.report(build,profile).stale)
		build.savers.CraftingProjects.projects={};assert.is_true(dependencies.report(build,profile).stale)
	end)
	it("links modeled recipe currencies to the filter and marks changed recipes stale",function()
		local project=craft();project.nativeRecipe={steps={{method="omen_connections"},{method="beast_max_links"}},targets={},requirements={links=4}}
		build.savers.CraftingProjects:Upsert(project)
		local profile=filters.profile("craft-resources","Craft resources");profile.rules=filters.generate(build,profile)
		local names={};for _,rule in ipairs(profile.rules) do names[rule.title]=true end
		assert.is_true(names["Omen of Connections"]);assert.is_true(names["Orb of Fusing"]);assert.is_nil(names["The Black Morrigan"])
		assert.equal("Show",filters.simulate(profile,{BaseType="Omen of Connections"}).action)
		assert.is_false(dependencies.report(build,profile).stale)
		project.nativeRecipe.steps={{method="socket_white_bench"}};build.savers.CraftingProjects:Upsert(project)
		assert.is_true(dependencies.report(build,profile).stale)
		profile.rules=filters.generate(build,profile);names={};for _,rule in ipairs(profile.rules) do names[rule.title]=true end
		assert.is_nil(names["Omen of Connections"]);assert.is_true(names["Orb of Scouring"])
	end)
	it("preserves recipe pickups and reports inspection failures",function()
		local project=craft();project.nativeRecipe={steps={{method="omen_connections"}},targets={},requirements={links=4}}
		build.savers.CraftingProjects:Upsert(project);local profile=filters.profile("review-craft","Review craft");profile.rules=filters.generate(build,profile)
		project.nativeRecipe.steps={{method="omen_connections"},{method="scour"}};build.savers.CraftingProjects:Upsert(project)
		local sim=require("Modules.CraftingSimulator");local original=sim.model;sim.model=function() error("fixture failure") end
		local ok,rules,warnings=pcall(filters.generate,build,profile)
		local reportOk,report=pcall(dependencies.report,build,profile);sim.model=original
		assert.is_true(ok);assert.equal(1,#warnings);assert.equal("craft:helmet",warnings[1].origin)
		assert.is_true(reportOk,report);assert.is_true(report.stale);assert.equal("Needs review",report.entries[1].status)
		local found=false;for _,rule in ipairs(rules) do if rule.title=="Omen of Connections" then found=true end end;assert.is_true(found)
		report=dependencies.report(build,profile);assert.equal("Changed",report.entries[1].status)
	end)
	it("reports partial ingredient coverage while retaining known pickups",function()
		local project=craft();project.nativeRecipe={steps={{method="omen_connections"}},targets={},requirements={links=4}}
		build.savers.CraftingProjects:Upsert(project);local profile=filters.profile("partial-craft","Partial craft");profile.rules=filters.generate(build,profile)
		project.nativeRecipe.steps={{method="omen_connections"},{method="locus"}};build.savers.CraftingProjects:Upsert(project)
		local rules,warnings=filters.generate(build,profile);assert.equal(1,#warnings);assert.matches("ingredient breakdown",warnings[1].message)
		local names={};for _,rule in ipairs(rules) do names[rule.title]=true end;assert.is_true(names["Omen of Connections"]);assert.is_true(names["Orb of Fusing"])
		assert.is_true(dependencies.report(build,profile).stale)
	end)
	it("reuses incomplete recipe checks until the retained draft changes",function()
		local project=craft();project.nativeRecipe={steps={{method="omen_connections"},{method="locus"}},targets={},requirements={links=4}}
		build.savers.CraftingProjects:Upsert(project);local profile=filters.profile("partial-cache","Partial cache");profile.rules=filters.generate(build,profile)
		local original=filters.generate;local calls=0;filters.generate=function(...) calls=calls+1;return original(...) end
		local ok,err=pcall(function()
			local first=dependencies.report(build,profile);assert.equal("Needs review",first.entries[1].status)
			assert.same(first,dependencies.report(build,profile));assert.equal(1,calls)
			profile.rules[1].title="Edited pickup";dependencies.report(build,profile);assert.equal(2,calls)
		end)
		filters.generate=original;assert.is_true(ok,err)
	end)
	it("shows recipe inspection warnings when refreshing pickups in the workspace",function()
		local project=craft();project.nativeRecipe={steps={{method="omen_connections"}},targets={},requirements={links=4}}
		build.savers.CraftingProjects:Upsert(project);local profile=filters.profile("review-ui","Review UI");profile.rules=filters.generate(build,profile)
		local workspace=require("Modules.PlanningWorkspace").new(build);workspace:Show("filters",{data={schemaVersion=1,activeId=profile.id,profiles={profile}}})
		project.nativeRecipe.steps={{method="omen_connections"},{method="chaos"}};build.savers.CraftingProjects:Upsert(project)
		local sim=require("Modules.CraftingSimulator");local original=sim.model;sim.model=function() error("fixture failure") end
		local ok,err=pcall(function()
			workspace.controls.generate:Click()
			for _=1,10 do if main.popups[1] then break end;workspace.cache.filters.layout.tick() end
			assert.is_truthy(main.popups[1].controls.results)
		end)
		sim.model=original;assert.is_true(ok,err)
	end)
	it("leaves entirely manual filters untracked and preserves personal overrides on refresh",function()
		build.savers.CraftingProjects:Upsert(craft());local profile=filters.profile("filter","Filter");profile.rules={filters.rule("mine","Personal",{'BaseType == "Chaos Orb"'})}
		assert.is_false(dependencies.report(build,profile).stale);local original=copyTable(profile.rules[1]);profile.rules=filters.generate(build,profile);assert.same(original,profile.rules[1])
		local opened;dependencies.open(build,{openWorkbench=function(project) opened=project.id end},"craft:helmet");assert.equal("helmet",opened)
		assert.has_error(function() dependencies.open(build,{},"craft:missing") end)
	end)
	it("reuses generated dependencies until native source state changes",function()
		local project=craft();build.savers.CraftingProjects:Upsert(project);local p=filters.profile("filter","Filter");local original=filters.generate;local calls=0
		filters.generate=function(...) calls=calls+1;return original(...) end
		local ok,err=pcall(function()
			dependencies.report(build,p);dependencies.report(build,p);assert.equal(1,calls)
			project.startingItem=project.startingItem:gsub("86","87");build.savers.CraftingProjects:Upsert(project);dependencies.report(build,p);assert.equal(2,calls)
		end)
		filters.generate=original;assert.is_true(ok,err)
	end)
	it("detects skill and active weapon changes before recalculation",function()
		local original=build.skillsTab.socketGroupList
		build.skillsTab.socketGroupList={{enabled=true,slot="Weapon 1",gemList={{enabled=true,nameSpec="Fireball"}}},{enabled=true,slot="Weapon 1 Swap",gemList={{enabled=true,nameSpec="Arc"}}}}
		local profile=filters.profile("skills","Skills");profile.rules=filters.generate(build,profile)
		local revision=build.outputRevision;assert.is_false(dependencies.report(build,profile).stale)
		build.itemsTab.activeItemSet.useSecondWeaponSet=true
		assert.equal(revision,build.outputRevision);assert.is_true(dependencies.report(build,profile).stale)
		profile.rules=filters.generate(build,profile);assert.is_false(dependencies.report(build,profile).stale)
		build.skillsTab.socketGroupList[2].enabled=false
		assert.equal(revision,build.outputRevision);assert.is_true(dependencies.report(build,profile).stale)
		build.itemsTab.activeItemSet.useSecondWeaponSet=false;build.skillsTab.socketGroupList=original
	end)
	it("checks recipe dependencies in bounded steps and discards changed sources",function()
		for i=1,3 do
			local project=craft();project.id="step"..i;project.startingItem=project.startingItem:gsub("86",tostring(70+i))
			project.nativeRecipe={steps={{method="omen_connections"}},targets={},requirements={links=4}};build.savers.CraftingProjects:Upsert(project)
		end
		local profile=filters.profile("async-check","Async check");local job=dependencies.begin(build,profile)
		local done,result,err=dependencies.poll(job);assert.is_false(done)
		local changed=copyTable(build.savers.CraftingProjects.projects[1]);changed.title="Changed during check";build.savers.CraftingProjects:Upsert(changed)
		done,result,err=dependencies.poll(job);assert.is_true(done);assert.is_nil(result);assert.equal("changed",err)
		job=dependencies.begin(build,profile);local slices=0
		repeat slices=slices+1;done,result,err=dependencies.poll(job);assert.is_nil(err) until done or slices>10
		assert.is_true(done);assert.is_true(slices>1);assert.same(dependencies.report(build,profile),result)
	end)
	it("generates pickups in steps and rejects an edited filter",function()
		for i=1,3 do
			local project=craft();project.id="generation"..i;project.startingItem=project.startingItem:gsub("86",tostring(30+i))
			project.nativeRecipe={steps={{method="socket_white_bench"}},targets={},requirements={sockets=1}};build.savers.CraftingProjects:Upsert(project)
		end
		local profile=filters.profile("generation","Generation");local job=dependencies.beginGenerate(build,profile)
		local done,result,err=dependencies.poll(job);assert.is_false(done)
		profile.rules[1]=filters.rule("manual","Manual",{'BaseType == "Chaos Orb"'})
		done,result,err=dependencies.poll(job);assert.is_true(done);assert.is_nil(result);assert.equal("changed",err)
		job=dependencies.beginGenerate(build,profile);local slices=0
		repeat slices=slices+1;done,result,err=dependencies.poll(job);assert.is_nil(err) until done or slices>10
		local rules,warnings=filters.generate(build,profile);assert.is_true(done);assert.is_true(slices>1);assert.same(rules,result.rules);assert.same(warnings,result.warnings)
	end)
	it("keeps the filter workspace usable while linked recipes are checked",function()
		for i=1,3 do
			local project=craft();project.id="ui-step"..i;project.startingItem=project.startingItem:gsub("86",tostring(60+i))
			project.nativeRecipe={steps={{method="socket_white_bench"}},targets={},requirements={sockets=1}};build.savers.CraftingProjects:Upsert(project)
		end
		local profile=filters.profile("async-ui","Async UI");local workspace=require("Modules.PlanningWorkspace").new(build)
		workspace:Show("filters",{data={schemaVersion=1,activeId=profile.id,profiles={profile}}})
		assert.is_false(workspace.controls.generate:IsEnabled())
		assert.equal("Checking build pickups...",workspace.controls.generate.label())
		for _=1,10 do if workspace.controls.generate:IsEnabled() then break end;workspace.cache.filters.layout.tick() end
		assert.is_true(workspace.controls.generate:IsEnabled())
	end)
	it("does not apply a pending pickup update after the build changes",function()
		local profile=filters.profile("generation-ui","Generation UI");local workspace=require("Modules.PlanningWorkspace").new(build)
		workspace:Show("filters",{data={schemaVersion=1,activeId=profile.id,profiles={profile}}})
		local project=craft();project.startingItem=project.startingItem:gsub("86","37")
		project.nativeRecipe={steps={{method="socket_white_bench"}},targets={},requirements={sockets=1}};build.savers.CraftingProjects:Upsert(project)
		workspace.controls.generate:Click();assert.is_false(workspace.controls.generate:IsEnabled());assert.equal("Updating build pickups...",workspace.controls.generate.label())
		project.title="Changed during update";build.savers.CraftingProjects:Upsert(project);workspace.cache.filters.layout.tick()
		assert.equal(0,#workspace.cache.filters.layout.snapshot().data.profiles[1].rules);assert.is_truthy(main.popups[1])
	end)
	it("applies generated pickups after the staged update completes",function()
		local profile=filters.profile("generation-complete","Generation complete");local workspace=require("Modules.PlanningWorkspace").new(build)
		workspace:Show("filters",{data={schemaVersion=1,activeId=profile.id,profiles={profile}}})
		for i=1,2 do
			local project=craft();project.id="ui-generate"..i;project.startingItem=project.startingItem:gsub("86",tostring(40+i))
			project.nativeRecipe={steps={{method="socket_white_bench"}},targets={},requirements={sockets=1}};build.savers.CraftingProjects:Upsert(project)
		end
		local previous=workspace.cache.filters.layout;workspace.controls.generate:Click()
		assert.equal(0,#previous.snapshot().data.profiles[1].rules)
		for _=1,10 do if workspace.cache.filters.layout~=previous then break end;previous.tick() end
		assert.is_not.equal(previous,workspace.cache.filters.layout)
		assert.is_true(#workspace.cache.filters.layout.snapshot().data.profiles[1].rules>0)
	end)
	it("continues a pickup update after changing filter screens",function()
		local profile=filters.profile("generation-nav","Generation navigation");local workspace=require("Modules.PlanningWorkspace").new(build)
		workspace:Show("filters",{data={schemaVersion=1,activeId=profile.id,profiles={profile}}})
		for i=1,2 do
			local project=craft();project.id="nav-generate"..i;project.startingItem=project.startingItem:gsub("86",tostring(20+i))
			project.nativeRecipe={steps={{method="socket_white_bench"}},targets={},requirements={sockets=1}};build.savers.CraftingProjects:Upsert(project)
		end
		workspace.controls.generate:Click();assert.is_truthy(workspace.transient.filterGeneration)
		assert.is_nil(workspace.cache.filters.layout.snapshot().filterGeneration)
		workspace.controls.customize:Click()
		assert.is_truthy(workspace.transient.filterGeneration)
		workspace:Remember("filters");workspace.cache.filters=nil;workspace:Show("filters");local current=workspace.cache.filters.layout
		assert.is_truthy(workspace.transient.filterGeneration)
		for _=1,10 do if not workspace.transient.filterGeneration then break end;workspace.cache.filters.layout.tick() end
		assert.is_nil(workspace.transient.filterGeneration);assert.is_not.equal(current,workspace.cache.filters.layout)
		assert.is_true(#workspace.cache.filters.layout.snapshot().data.profiles[1].rules>0)
	end)
	it("does not apply an update to a different filter profile",function()
		local first=filters.profile("generation-first","First");local second=filters.profile("generation-second","Second")
		local workspace=require("Modules.PlanningWorkspace").new(build)
		workspace:Show("filters",{data={schemaVersion=1,activeId=first.id,profiles={first,second}}})
		local project=craft();project.startingItem=project.startingItem:gsub("86","19")
		project.nativeRecipe={steps={{method="socket_white_bench"}},targets={},requirements={sockets=1}};build.savers.CraftingProjects:Upsert(project)
		workspace.controls.generate:Click();assert.is_truthy(workspace.transient.filterGeneration)
		local state=workspace.cache.filters.layout.snapshot();state.selected=second.id;workspace:Show("filters",state)
		workspace.cache.filters.layout.tick();assert.is_nil(workspace.transient.filterGeneration);assert.is_truthy(main.popups[1])
		local profiles=workspace.cache.filters.layout.snapshot().data.profiles;assert.equal(0,#profiles[1].rules);assert.equal(0,#profiles[2].rules)
	end)
	it("prepares build-target simulator examples in stages and refreshes changed sources",function()
		for i=1,3 do
			local project=craft();project.id="scene"..i;project.startingItem=project.startingItem:gsub("86",tostring(10+i))
			project.nativeRecipe={steps={{method="socket_white_bench"}},targets={},requirements={sockets=1}};build.savers.CraftingProjects:Upsert(project)
		end
		local profile=filters.profile("target-scene","Target scene");local workspace=require("Modules.PlanningWorkspace").new(build)
		workspace:Show("filters",{data={schemaVersion=1,activeId=profile.id,profiles={profile}},page="Simulate",sceneKind="Build targets"})
		local first=workspace.transient.filterSceneTargets;assert.is_truthy(first);assert.is_nil(first.rules)
		local changed=copyTable(build.savers.CraftingProjects.projects[1]);changed.title="Updated target";build.savers.CraftingProjects:Upsert(changed)
		for _=1,20 do if workspace.transient.filterSceneTargets.rules then break end;workspace.cache.filters.layout.tick() end
		local ready=workspace.transient.filterSceneTargets;assert.is_not.equal(first,ready);assert.is_truthy(ready.rules)
		local found=false;for _,rule in ipairs(ready.rules) do if rule.title=="Updated target base" then found=true end end;assert.is_true(found)
		assert.equal(0,#workspace.cache.filters.layout.snapshot().data.profiles[1].rules)
	end)
	it("clears pending simulator targets if the last profile is removed",function()
		local profile=filters.profile("target-remove","Target removal");local workspace=require("Modules.PlanningWorkspace").new(build)
		workspace:Show("filters",{data={schemaVersion=1,activeId=profile.id,profiles={profile}},page="Simulate",sceneKind="Build targets"})
		assert.is_truthy(workspace.transient.filterSceneTargets)
		workspace:Show("filters",{data={schemaVersion=1,profiles={}},page="Simulate",sceneKind="Build targets"})
		assert.is_nil(workspace.transient.filterSceneTargets);assert.has_no.errors(function() workspace.cache.filters.layout.tick() end)
	end)
	it("reuses a compiled filter across navigation but recompiles after an edit",function()
		local profile=filters.profile("compile-cache","Compile cache");local workspace=require("Modules.PlanningWorkspace").new(build)
		local original=filters.compile;local calls=0;filters.compile=function(...) calls=calls+1;return original(...) end
		local ok,err=pcall(function()
			workspace:Show("filters",{data={schemaVersion=1,activeId=profile.id,profiles={profile}}});local first=calls
			workspace.controls.viewSimulate:Click();assert.equal(first,calls)
			local state=workspace.cache.filters.layout.snapshot();state.data.profiles[1].title="Edited filter";workspace:Show("filters",state);assert.is_true(calls>first)
		end)
		filters.compile=original;assert.is_true(ok,err)
	end)
	it("keeps the source filter draft and previous working craft when following a link",function()
		local project=craft();build.savers.CraftingProjects:Upsert(project);local workspace=require("Modules.PlanningWorkspace").new(build)
		local profile=filters.profile("filter","Unsaved filter name");workspace:Show("filters",{data={schemaVersion=1,activeId=profile.id,profiles={profile}},dirty=true})
		workspace.cache.filters.layout.openWorkbench(project);assert.equal("crafting",workspace.page);assert.is_truthy(workspace.drafts.filters.plan.dirty)
		workspace.controls.currency_alchemy:Click();workspace.controls.apply:Click();local previous=workspace.cache.crafting.layout.snapshot();assert.equal(1,#previous.actions)
		local item=require("Modules.CraftingInventory").capture(project,previous.state);workspace.cache.crafting.layout.openWorkbench(require("Modules.CraftingInventory").project(item))
		assert.equal(1,#workspace.craftDrafts[project.id].actions)
		workspace:Show("filters");assert.equal("Unsaved filter name",workspace.cache.filters.layout.snapshot().data.profiles[1].title)
	end)
end)
