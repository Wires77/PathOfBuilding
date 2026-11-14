describe("Visual filter catalogue",function()
	local filters=require("Modules.LootFilters")
	local parser=require("Modules.LootFilterParser")
	local library=require("Modules.LootFilterLibrary")
	before_each(function() newBuild();main.popups={} end)
	after_each(function() main.popups={} end)
	it("offers reproducible card and essence examples for testing filter rules",function()
		local profile=filters.profile("test","Test")
		for _,case in ipairs({{kind="Divination cards",class="Divination Cards",base="The Doctor",count=12},
			{kind="Essences",class="Stackable Currency",base="Essence of Horror",count=11}}) do
			local scene=library.scene(profile,build,case.kind,0,76,81);assert.equal(case.count,#scene)
			local rule=parser.parse('Show\n Class == "'..case.class..'"\n BaseType == "'..case.base..'"\nHide')
			local found=0;for _,item in ipairs(scene) do
				assert.equal(case.class,item.Class);assert.equal(76,item.AreaLevel);assert.equal(81,item.ItemLevel)
				if parser.simulate(rule,item).action=="Show" then assert.equal(case.base,item.BaseType);found=found+1 end
			end
			assert.equal(1,found)
			local rotated=library.scene(profile,build,case.kind,1,76,81);assert.equal(scene[2].BaseType,rotated[1].BaseType)
			assert.same(rotated,library.scene(profile,build,case.kind,1,76,81))
		end
	end)
	it("builds a reproducible 3.30 league-item example scene from published item classes",function()
		local profile=filters.profile("test","Test");local scene=library.scene(profile,build,"Covens & Threads",0,76,81)
		local file=assert(io.open("Data/LootFilters/patch-3.30.json","rb"));local patch=assert(require("dkjson").decode(file:read("*a")));file:close()
		assert.equal(16,#scene);local seen={}
		for _,item in ipairs(scene) do
			assert.is_truthy(isValueInTable(patch.added[item.Class],item.BaseType),item.BaseType)
			assert.equal(76,item.AreaLevel);assert.equal(81,item.ItemLevel);seen[item.BaseType]=true
		end
		assert.is_true(seen["Frayed Thread"]);assert.is_true(seen["Breach Thread"]);assert.is_true(seen["Enshrouded Quiver"]);assert.is_true(seen["Scorched Arm"])
		local rotated=library.scene(profile,build,"Covens & Threads",1,76,81)
		assert.equal(scene[2].BaseType,rotated[1].BaseType);assert.same(rotated,library.scene(profile,build,"Covens & Threads",1,76,81))
	end)
	it("browses real base blocks without mutating the profile or their conditions",function()
		local profile=filters.profile("test","Test");local before=copyTable(profile)
		local entries=library.catalog(profile);assert.is_true(#entries>500)
		assert.same(before,profile)
		local currency=library.entries(profile,entries,"All items","Chaos Orb");assert.is_true(#currency>0)
		for _,entry in ipairs(currency) do assert.is_truthy(entry.rule.text:find("Chaos Orb",1,true));assert.is_true(entry.base);assert.equal(1,#parser.parse(entry.rule.text).rules) end
	end)
	it("edits appearance while preserving multi-value conditions, Continue and custom sound volume",function()
		local rule={id="base-1",title="Target",text='Show\n HasExplicitMod >=2 "of Haast" "of Ephij"\n BaseType == "Iron Hat"\n CustomAlertSound "my sound.wav" 125\n Continue',enabled=false}
		local changed=library.appearance(rule,{SetTextColor={"255","200","100"},SetFontSize={"40"}})
		local old,new=parser.parse(rule.text).rules[1],parser.parse(changed.text).rules[1]
		assert.same(old.conditions,new.conditions);assert.same({"my sound.wav","125"},new.styles.CustomAlertSound);assert.is_true(new.continue);assert.is_false(changed.enabled)
		assert.is_nil(rule.text:find("SetTextColor",1,true))
	end)
	it("creates a personal override without replacing imported source text",function()
		local profile=filters.profile("test","Test");profile.template='Show\n BaseType == "Iron Hat"\n SetTextColor 255 255 255'
		local source=profile.template;local entry=library.catalog(profile)[1]
		local override=library.appearance(entry.rule,{SetTextColor={"255","0","0"}});profile.rules={override}
		assert.equal(source,profile.template)
		local result=filters.simulate(profile,{BaseType="Iron Hat"});assert.same({"255","0","0"},result.styles.SetTextColor)
	end)
	it("keeps base override identities stable when unrelated source rules move",function()
		local profile=filters.profile("test","Test");local hat='Show\n BaseType == "Iron Hat"\n SetFontSize 40';local ring='Show\n BaseType == "Iron Ring"\n SetFontSize 30'
		profile.template=hat.."\n"..ring;local original=library.catalog(profile)
		profile.template=ring.."\n"..hat;local reordered=library.catalog(profile)
		assert.equal(original[1].rule.id,reordered[2].rule.id);assert.is_not.equal(original[1].rule.id,reordered[1].rule.id)
	end)
	it("generates deterministic example scenes and labels unknown item data honestly",function()
		local profile=filters.profile("test","Test");local first=library.scene(profile,build,"Mixed drops",7,72)
		assert.same(first,library.scene(profile,build,"Mixed drops",7,72));assert.equal(72,first[1].AreaLevel)
		for _,item in ipairs(library.scene(profile,build,"Currency",1,83)) do assert.equal("Stackable Currency",item.Class) end
		profile.template='Hide\n FutureCondition True\nShow'
		local unresolved=copyTable(first[1]);unresolved.BaseType="Iron Hat";unresolved.Class="Helmets"
		assert.equal("unknown",filters.simulate(profile,unresolved).status)
	end)
	it("compares explicitly tiered unidentified gear without modeling drop rates",function()
		local scene=library.scene(filters.profile("test","Test"),build,"Tiered gear",4,72,75)
		assert.equal(5,#scene)
		for index,tier in ipairs({0,2,3,4,5}) do
			local item=scene[index];assert.equal(tier,item.UnidentifiedItemTier);assert.is_false(item.Identified)
			assert.equal("Iron Hat",item.BaseType);assert.equal(72,item.AreaLevel);assert.equal(75,item.ItemLevel)
			local result=parser.simulate(parser.parse("Show\n UnidentifiedItemTier >= 4\nHide"),item)
			assert.equal(tier>=4 and "Show" or "Hide",result.action)
		end
	end)
	it("builds example properties only when requested and reuses the parsed block",function()
		local p=filters.profile("test","Test");p.template='Show\n BaseType == "Iron Hat"\n ItemLevel >= 83'
		local entry=library.catalog(p)[1];assert.is_nil(rawget(entry,"sample"));local sample=entry.sample;assert.equal("Iron Hat",sample.BaseType);assert.equal(83,sample.ItemLevel)
		assert.equal(sample,entry.sample);assert.same(library.sample(entry.rule),sample)
	end)
	it("labels generic rules using their real conditions instead of an invented example",function()
		local p=filters.profile("labels","Labels");p.template='Show\n Identified True\n Rarity Rare\n HasExplicitMod "Elreon"\nShow\n Class == "Helmets"\nShow\n Sockets >= 5\nHide\n BaseType != "Chaos Orb"'
		local entries=library.catalog(p)
		assert.equal("Has Explicit Mod = Elreon",entries[1].rule.title)
		assert.equal("Class == Helmets",entries[2].rule.title)
		assert.equal("Sockets >= 5",entries[3].rule.title)
		assert.equal("Base Type != Chaos Orb",entries[4].rule.title)
		local structure=require("Modules.LootFilterStructure").filter(require("Modules.LootFilterStructure").outline(p),"","base")
		for i,entry in ipairs(entries) do assert.equal(entry.rule.title,structure[i].title);assert.is_nil(rawget(entry,"sample")) end
	end)
	it("builds representative rare and modifier examples without overriding identification",function()
		local text='Show\n Rarity Rare\n HasExplicitMod >=2 "Haast" "Ephij"\nHide'
		local item=library.sample({text=text});assert.equal("Iron Hat",item.BaseType);assert.equal("Helmets",item.Class)
		assert.is_true(item.Identified);assert.same({"Haast","Ephij"},item.HasExplicitMod);assert.equal("Show",parser.simulate(parser.parse(text),item).action)
		local unidentified=library.sample({text='Show\n Identified False\n HasExplicitMod "Haast"'});assert.is_false(unidentified.Identified)
		assert.equal("unknown",parser.simulate(parser.parse('Show\n Identified False\n HasExplicitMod "Haast"'),unidentified).status)
		local numeric=library.sample({text='Show\n HasExplicitMod "1"'});assert.same({"1"},numeric.HasExplicitMod)
		local alternatives=library.sample({text='Show\n HasExplicitMod "Haast" "Ephij"'});assert.same({"Haast"},alternatives.HasExplicitMod)
		local tooMany=library.sample({text='Show\n HasExplicitMod >=7 "a" "b" "c" "d" "e" "f" "g"'});assert.equal(6,#tooMany.HasExplicitMod)
		assert.equal("Iron Hat",library.sample({text='Show\n Rarity Magic'}).BaseType)
	end)
	it("builds coherent equipment examples for common socket rules",function()
		for _,condition in ipairs({"SocketGroup RGB", "SocketGroup == 5GGG", "SocketGroup == 5GW", "Sockets >= 5", "Sockets 5GGG", "LinkedSockets >= 5"}) do
			local text="Show\n "..condition.."\nHide"
			local item=library.sample({text=text})
			assert.equal("Body Armours",item.Class)
			assert.equal(item.Sockets,#item.SocketColours)
			assert.equal(item.Sockets,item.LinkedSockets)
			assert.equal("Show",parser.simulate(parser.parse(text),item).action)
		end
	end)
	it("uses native default text colours for item rarity and known item classes",function()
		local color=require("Modules.LootFilterVisuals").defaultTextColor
		assert.same({200,200,200},color({Rarity="Normal",Class="Helmets"}))
		assert.same({136,136,255},color({Rarity="Magic"}));assert.same({255,255,119},color({Rarity="Rare"}));assert.same({175,96,37},color({Rarity="Unique"}))
		assert.same({170,158,130},color({Rarity="Normal",Class="Stackable Currency"}));assert.same({26,162,155},color({Rarity="Normal",Class="Skill Gems"}))
		assert.same({255,255,119},color({Rarity="Rare",Class="Stackable Currency"}));assert.same({220,225,215},color({}))
	end)
	it("derives known equipment classes and leaves unfamiliar bases unknown",function()
		assert.equal("One Hand Swords",library.sample({text='Show\n BaseType == "Rusted Sword"'}).Class)
		local item=library.sample({text='Show\n BaseType == "Unknown Future Base"'});assert.is_nil(item.Class)
		assert.equal("unknown",parser.simulate(parser.parse('Hide\n Class == "Stackable Currency"\nShow'),item).status)
		local p=filters.profile("test","Test");p.template='Hide\nShow\n Continue'
		local entries=library.catalog(p);assert.equal("Hide remaining items",entries[1].rule.title);assert.equal("Style remaining items",entries[2].rule.title)
	end)
end)
