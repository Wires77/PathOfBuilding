describe("Compiled filter structure",function()
	local filters=require("Modules.LootFilters")
	local structure=require("Modules.LootFilterStructure")
	local function profile()
		local p=filters.profile("test","Test");p.template='Show\n BaseType == "Chaos Orb"\nHide\n Class == "Helmets"'
		p.rules={filters.rule("personal","Personal Chaos",{'BaseType == "Chaos Orb"'})}
		p.tiers={{id="tier",title="Currency tier",items={"Divine Orb"},text='Show\n BaseType == "Divine Orb"'}}
		p.modules={{id="shared",title="Shared",rules={filters.rule("duplicate","Duplicate Chaos",{'BaseType == "Chaos Orb"'})}}}
		p.campaign=require("Modules.LootFilterCampaign").defaults();p.campaign.weapons={"Bow"};p.campaign.upgradeWindow=0;return p
	end
	before_each(function() newBuild() end)
	it("maps a native 3.30 preset without nonexistent safety blocks",function()
		local p=filters.profile("native","Native");local view=structure.outline(p)
		assert.equal(view.report.rules,#view.entries);assert.equal(0,#structure.filter(view,"","safety"));assert.is_true(#structure.filter(view,"","base")>500)
	end)
	it("does not flag different modifier counts as unreachable in the structure",function()
		local p=filters.profile("counts","Counts");p.template='Show\n HasExplicitMod >=2 "1"\nHide\n HasExplicitMod >=1 "2"'
		local view=structure.outline(p);local base=structure.filter(view,"","base")
		assert.equal(2,#base)
		for _,entry in ipairs(base) do for _,diagnostic in ipairs(structure.diagnostics(view,entry)) do assert.is_nil(diagnostic.shadowedBy) end end
	end)
	it("maps every active block to its real source section and edit behavior",function()
		local view=structure.outline(profile());assert.equal(view.report.rules,#view.entries);local sections={};for _,group in ipairs(view.sections) do sections[group.id]=true end
		for _,id in ipairs({"personal","tiers","module-shared","campaign","safety","base"}) do assert.is_true(sections[id],id) end
		assert.equal("personal",view.entries[1].rule.id);assert.is_true(view.entries[1].editable)
		local tiers=structure.filter(view,"","tiers");assert.equal(1,#tiers);assert.is_truthy(tiers[1].rule.id:match("^override%-"));assert.is_nil(tiers[1].editable)
		local conflicts=structure.filter(view,"Chaos Orb",nil,nil,"Priority conflicts");assert.is_true(#conflicts>=2)
		for _,entry in ipairs(conflicts) do assert.is_truthy(structure.diagnostics(view,entry)[1].shadowedBy) end
	end)
	it("keeps disabled rules outside compiled structure and distinguishes Continue and unknown predicates",function()
		local p=profile();p.rules[1].enabled=false;p.modules={};p.template='Show\n BaseType == "Chaos Orb"\n Continue\nHide\n FutureProperty True'
		local view=structure.outline(p);assert.equal(0,#structure.filter(view,"","personal"));assert.equal(1,#structure.filter(view,"",nil,nil,"Continue blocks"))
		assert.equal(1,#structure.filter(view,"FutureProperty",nil,nil,"Warnings / errors"))
		assert.equal(0,#structure.filter(view,"[not a pattern]"))
	end)
	it("preserves unresolved imports as diagnostics rather than reading external files",function()
		local p=profile();p.template='Import "external.filter"\nShow\n BaseType == "Chaos Orb"';local view=structure.outline(p)
		assert.equal(1,#view.report.imports);assert.equal("external.filter",view.report.imports[1].file);assert.equal(1,#structure.filter(view,"","base"))
	end)
	it("uses one override identity across catalogue, structure, matched rules and appearance changes",function()
		local p=profile();local base=require("Modules.LootFilterLibrary").catalog(p)[1];local view=structure.outline(p);local source=structure.filter(view,"","base")[1]
		assert.equal(base.rule.id,source.rule.id)
		p.appearance={textColor={255,0,0,255}};local styled=structure.filter(structure.outline(p),"","base")[1];assert.equal(source.rule.id,styled.rule.id)
		local module=structure.filter(view,"","module-shared")[1];p.appearance.alertVolume=0;assert.equal(module.rule.id,structure.filter(structure.outline(p),"","module-shared")[1].rule.id)
	end)
end)
