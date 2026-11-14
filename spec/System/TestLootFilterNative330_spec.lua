describe("3.30 native filter update",function()
	local filters=require("Modules.LootFilters")
	local parser=require("Modules.LootFilterParser")
	local library=require("Modules.LootFilterLibrary")
	before_each(function() newBuild();main.popups={} end)
	after_each(function() main.popups={} end)
	it("keeps the reviewed base's own decisions across all strictness levels",function()
		for strictness=0,6 do
			local profile=filters.profile("native","Native");profile.strictness=strictness
			local base,changes=filters.migratedBase(profile);assert.same({},changes)
			local output,report,compiled=filters.compile(profile,true)
			assert.is_nil(output:find("# 3.30 new-item safety:",1,true))
			for _,diagnostic in ipairs(report.diagnostics) do assert.is_nil(diagnostic.error,diagnostic.error) end
			local original=parser.parse(base)
			for _,sample in ipairs(library.scene(profile,build,"Covens & Threads",0,83,86)) do
				local before=parser.simulate(original,sample);local after=parser.simulate(compiled,sample)
				assert.equal(before.action,after.action,sample.BaseType);assert.same(before.styles,after.styles)
			end
		end
	end)
	it("requires review of old profiles and keeps personal rules ahead of the new base",function()
		local old=filters.profile("old","Old");old.baseCommit="3ab00dd016b00c6be7acfa989baf498842973d54"
		old.rules={{id="personal",title="Hide thread",text='Hide\n BaseType == "Frayed Thread"',enabled=true}}
		old.tiers={{id="tier",title="Currency tier",items={"Divine Orb"},text='Show\n BaseType == "Divine Orb"'}}
		old.appearance={textColor={255,220,100,255}}
		assert.has_error(function() filters.compile(old) end)
		local updated=filters.update(old);assert.same(old.rules,updated.rules);assert.same(old.tiers,updated.tiers);assert.same(old.appearance,updated.appearance);assert.equal(filters.source().commit,updated.baseCommit)
		local sample=library.sample();sample.BaseType="Frayed Thread";sample.Class="Stackable Currency"
		assert.equal("Hide",filters.simulate(updated,sample).action)
	end)
	it("retains the safety layer for imported filters",function()
		local profile=filters.profile("import","Imported");profile.template='Hide\n BaseType == "Chaos Orb"\nShow'
		local output=filters.compile(profile);assert.is_truthy(output:find("# 3.30 new-item safety:",1,true))
	end)
end)
