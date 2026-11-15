-- cspell:ignore RRAG GGGRRW GGGGR GGGRR GGRRRW
describe("Build-owned loot filters",function()
	local filters=require("Modules.LootFilters")
	local parser=require("Modules.LootFilterParser")
	it("keeps Ruthless Minimal results separate from unknown drop outcomes",function()
		local outcome=require("Classes.LootFilterWorkspace").dropOutcome
		for _,action in ipairs({"Show","Hide","Minimal"}) do
			assert.equal(action,outcome(parser.simulate(parser.parse(action),{})))
		end
		assert.equal("Unknown",outcome(parser.simulate(parser.parse("Show\n ItemLevel >= 80"),{})))
		assert.equal("Unknown",outcome(parser.simulate(parser.parse("Show\n ItemLevel >= nope"),{})))
	end)
	before_each(function() newBuild();main.popups={} end)
	after_each(function() main.popups={} end)
	it("rejects malformed imports even when other imports are unresolved",function()
		for _,line in ipairs({"Import",'Import ""','Import "file.filter" Invalid','Import "file.filter" Optional extra'}) do
			local parsed=parser.parse('Import "valid.filter" Optional\n'..line..'\nShow')
			assert.equal("invalid",parser.simulate(parsed,{}).status);assert.equal(2,parsed.diagnostics[1].line)
		end
		local parsed=parser.parse('Import "required.filter"\nImport "optional.filter" Optional\nShow')
		assert.equal(0,#parsed.diagnostics);assert.equal(2,#parsed.imports);assert.is_true(parsed.imports[2].optional);assert.equal("unknown",parser.simulate(parsed,{}).status)
		local profile=filters.profile("bad-import","Bad import");profile.template='Import "file.filter" Invalid\nShow'
		local _,report=filters.compile(profile);local found=false;for _,entry in ipairs(report.diagnostics) do if entry.error and entry.error:find("Invalid Import",1,true) then found=true end end;assert.is_true(found)
	end)
	it("respects unresolved imports in rule order",function()
		local raw='Hide\n BaseType "Iron Hat"\nImport "missing.filter"\nShow'
		local before=parser.simulate(parser.parse(raw),{BaseType="Iron Hat"})
		assert.equal("matched",before.status);assert.equal("Hide",before.action);assert.equal(1,before.line)
		assert.matches("Later included files",before.reasons[1])
		local after=parser.simulate(parser.parse(raw),{BaseType="Iron Ring"})
		assert.equal("unknown",after.status);assert.equal(3,after.line);assert.matches("missing.filter",after.reasons[1])
		local continuing=parser.simulate(parser.parse('Hide\n Continue\nImport "missing.filter"\nShow'),{})
		assert.equal("unknown",continuing.status);assert.equal("Unknown",continuing.action);assert.same({1},continuing.matches)
		assert.equal("unknown",parser.simulate(parser.parse('Show\n BaseType "Iron Hat"\nImport "missing.filter"'),{}).status)
		assert.equal("invalid",parser.simulate(parser.parse('Show\nImport "bad.filter" Invalid'),{}).status)
		local profile=filters.profile("ordered-import","Ordered import");profile.template=raw
		assert.equal("Hide",filters.simulate(profile,{BaseType="Iron Hat"}).action)
		assert.equal("unknown",filters.simulate(profile,{BaseType="Iron Ring"}).status)
		profile.importFiles={{name="missing.filter",text='Hide\n BaseType "Iron Ring"'}}
		assert.equal("Hide",filters.simulate(profile,{BaseType="Iron Ring"}).action)
	end)
	it("preserves quoted conditions and modifier counts when restyling",function()
		local library=require("Modules.LootFilterLibrary")
		for _,condition in ipairs({'HasExplicitMod >=2 "Haast" "Ephij"','HasExplicitMod "1"','BaseType "123"'}) do
			local rule={id="quoted",title="Quoted",text="Show\n "..condition}
			local edited=library.appearance(rule,{SetFontSize={"42"}});local parsed=parser.parse(edited.text)
			assert.equal(0,#parsed.diagnostics)
			local before=parser.parse(rule.text).rules[1].conditions[1];local after=parsed.rules[1].conditions[1]
			assert.equal(before.operator,after.operator);assert.same(before.values,after.values);assert.same(before.quoted,after.quoted)
		end
	end)
	it("distinguishes known zero sockets from an unknown socket group",function()
		local function test(condition,item) return parser.simulate(parser.parse("Show\n "..condition.."\nHide"),item) end
		for _,item in ipairs({{Sockets=0},{SocketGroup="0"},{SocketGroup=""}}) do
			assert.equal("Show",test("SocketGroup 0",item).action)
			assert.equal("Show",test("SocketGroup < 1",item).action)
			assert.equal("Hide",test("SocketGroup >= 1",item).action)
		end
		assert.equal("Hide",test("SocketGroup 0",{SocketGroup="W"}).action)
		assert.equal("unknown",test("SocketGroup 0",{}).status)
		assert.equal("Hide",test("Sockets R",{Sockets=0}).action)
	end)
	it("never treats Abyss or Delve sockets as links in simulated drops",function()
		local function action(condition,item)
			return parser.simulate(parser.parse("Show\n "..condition.."\nHide"),item).action
		end
		assert.equal("Hide",action("SocketGroup RG",{SocketGroup="RAG"}))
		assert.equal("Hide",action("SocketGroup >= 2",{SocketGroup="AA"}))
		assert.equal("Hide",action("SocketGroup DD",{SocketGroup="DD"}))
		assert.equal("Show",action("SocketGroup A",{SocketGroup="RAG"}))
		assert.equal("Show",action("SocketGroup 2RR",{SocketGroup="RRAG"}))
		assert.equal("Show",action("Sockets RAG",{Sockets=3,SocketColours="RAG"}))
	end)
	it("compares socket counts separately from minimum colours",function()
		local function action(condition,item)
			return parser.simulate(parser.parse("Show\n "..condition.."\nHide"),item).action
		end
		assert.equal("Show",action("SocketGroup > 5GGG",{SocketGroup="GGGRRW"}))
		assert.equal("Show",action("SocketGroup <= 5GGG",{SocketGroup="GGGGR"}))
		assert.equal("Hide",action("SocketGroup == 5GGG",{SocketGroup="GGGGR"}))
		assert.equal("Show",action("SocketGroup == 5GGG",{SocketGroup="GGGRR"}))
		assert.equal("Show",action("Sockets < 6GGG",{Sockets=5,SocketColours="GGGGR"}))
		assert.equal("Show",action("Sockets > 5GGG",{Sockets=6,SocketColours="GGRRRW"}))
		assert.equal("Show",action("SocketGroup < 4RG",{SocketGroup="BBBB"}))
		assert.equal("Show",action("SocketGroup > 4RG",{SocketGroup="RR"}))
		assert.equal("Hide",action("SocketGroup > 4RG",{SocketGroup="RG"}))
		assert.equal("Show",action("Sockets < 4RG",{Sockets=4,SocketColours="BBBB"}))
		assert.equal("Show",action("Sockets > 4RG",{Sockets=2,SocketColours="RR"}))
		assert.equal("Hide",action("Sockets > 4RG",{Sockets=2,SocketColours="RG"}))
	end)
	it("rejects malformed socket patterns and explains invalid sample colours",function()
		for _,condition in ipairs({"SocketGroup XYZ","SocketGroup 3RGBx","Sockets 5GR?",'SocketGroup ""'}) do
			local parsed=parser.parse("Hide\n "..condition.."\nShow")
			assert.equal("invalid",parser.simulate(parsed,{SocketGroup="RGB",Sockets=3,SocketColours="RGB"}).status)
		end
		local result=parser.simulate(parser.parse("Hide\n SocketGroup RGB\nShow"),{SocketGroup="RGB?"})
		assert.equal("unknown",result.status);assert.equal("Unknown",result.action);assert.matches("Invalid socket colours",result.reasons[1])
		result=parser.simulate(parser.parse("Hide\n Sockets RGB\nShow"),{Sockets=3,SocketColours="RGB?"})
		assert.equal("unknown",result.status);assert.equal("Unknown",result.action)
		assert.equal("Hide",parser.simulate(parser.parse("Hide\n SocketGroup RGB\nShow"),{SocketGroup="R-G-B"}).action)
	end)
	it("tests mixed socket-count and colour alternatives without guessing missing colours",function()
		local function result(condition,item) return parser.simulate(parser.parse("Hide\n "..condition.."\nShow"),item) end
		local rgb={Sockets=3,SocketColours="RGB"}
		assert.equal("Hide",result("Sockets 6 RGB",rgb).action)
		assert.equal("Hide",result("Sockets RGB 3",rgb).action)
		assert.equal("Hide",result("Sockets RGB",{Sockets="RGB"}).action)
		assert.equal("Show",result("Sockets 6 RRR",rgb).action)
		assert.equal("Hide",result("Sockets 3 RGB",{Sockets=3}).action)
		assert.equal("Hide",result("Sockets RGB 3",{Sockets=3}).action)
		assert.equal("unknown",result("Sockets 6 RGB",{Sockets=3}).status)
		assert.equal("unknown",result("Sockets RGB 6",{Sockets=3,SocketColours="RGB?"}).status)
		local inconsistent={Sockets=4,SocketColours="RGB"}
		assert.equal("unknown",result("Sockets RGB",inconsistent).status)
		assert.matches("Socket count does not match",result("Sockets RGB",inconsistent).reasons[1])
		assert.equal("Hide",result("Sockets 4 RGB",inconsistent).action)
		assert.equal("unknown",result("Sockets 6 RGB",inconsistent).status)
		assert.equal("unknown",result("Sockets RGB",{Sockets=0,SocketColours="RGB"}).status)
		assert.equal("Show",result("Sockets != 3 6",{Sockets=3}).action)
	end)
	it("applies first-match ordering, Continue styles and exact/partial names",function()
		local raw='Show\n BaseType "Iron"\n SetTextColor 255 0 0\n Continue\nHide\n BaseType == "Iron Hat"\n SetFontSize 25\nShow'
		local result=parser.simulate(parser.parse(raw),{BaseType="Iron Hat"})
		assert.equal("Hide",result.action);assert.equal(2,#result.matches);assert.same({"255","0","0"},result.styles.SetTextColor)
		assert.equal("Show",parser.simulate(parser.parse(raw),{BaseType="Iron Ring"}).action)
	end)
	it("validates documented alert sound IDs and volumes",function()
		for _,line in ipairs({"PlayAlertSound 0","PlayAlertSound 17","PlayAlertSound 1 301","PlayAlertSoundPositional 2 -1",'CustomAlertSound "file.wav" 301',"CustomAlertSoundOptional",'CustomAlertSound ""'}) do
			local result=parser.simulate(parser.parse("Show\n "..line.."\nHide"),{})
			assert.equal("invalid",result.status,line)
		end
		for _,line in ipairs({"PlayAlertSound None","PlayAlertSound 1 0","PlayAlertSoundPositional 16 300",'CustomAlertSound "file one.wav;file two.wav" 100',"DisableDropSound True"}) do
			assert.equal("matched",parser.simulate(parser.parse("Show\n "..line),{}).status,line)
		end
	end)
	it("treats numeric text as a name outside modifier-count conditions",function()
		local function action(condition,item) return parser.simulate(parser.parse("Hide\n "..condition.."\nShow"),item).action end
		assert.equal("Hide",action('BaseType "1"',{BaseType="Level 1 Relic"}))
		assert.equal("Show",action('BaseType == "1"',{BaseType="Level 1 Relic"}))
		assert.equal("Hide",action('Class "2"',{Class="Tier 2 Items"}))
		assert.equal("Show",action('BaseType != "1"',{BaseType="Level 1 Relic"}))
		assert.equal("Hide",action('HasExplicitMod >=2 "Haast" "Ephij"',{Identified=true,HasExplicitMod={"of Haast","of Ephij"}}))
		assert.equal("Show",action('HasExplicitMod >=2 "Haast" "Ephij"',{Identified=true,HasExplicitMod={"of Haast"}}))
	end)
	it("preserves quoted names that resemble numbers or operators",function()
		local function action(condition,item) return parser.simulate(parser.parse("Hide\n "..condition.."\nShow"),item).action end
		assert.equal("Hide",action('HasExplicitMod "1"',{Identified=true,HasExplicitMod={"Tier 1"}}))
		assert.equal("Hide",action('HasEnchantment "1"',{HasEnchantment={"Enchantment 1"}}))
		assert.equal("Hide",action('BaseType ">=1"',{BaseType=">=1 Token"}))
		assert.equal("Hide",action('HasExplicitMod >=2 "Haast" "Ephij"',{Identified=true,HasExplicitMod={"of Haast","of Ephij"}}))
		local saved;require("Classes.LootFilterControl").Conditions({id="quoted",title="Quoted",text='Hide\n HasExplicitMod "1"\n BaseType ">=1"'},function(value) saved=value end)
		main.popups[1].controls.keepRule:Click();assert.is_truthy(saved.text:find('HasExplicitMod = "1"',1,true));assert.is_truthy(saved.text:find('BaseType = ">=1"',1,true))
		assert.equal("Hide",parser.simulate(parser.parse(saved.text.."\nShow"),{Identified=true,HasExplicitMod={"Tier 1"},BaseType=">=1 Token"}).action)
	end)
	it("keeps modifier count operators joined to their number",function()
		for _,key in ipairs({"HasExplicitMod","HasEnchantment"}) do
			local raw='Hide\n '..key..' >=2 "Haast" "Ephij"';local saved
			require("Classes.LootFilterControl").Conditions({id="count",title="Count",text=raw},function(value) saved=value end)
			main.popups[1].controls.keepRule:Click();assert.is_truthy(saved.text:find(key..' >=2 "Haast" "Ephij"',1,true))
			local item={Identified=true,[key]={"of Haast","of Ephij"}};assert.equal("Hide",parser.simulate(parser.parse(saved.text.."\nShow"),item).action)
			assert.equal("invalid",parser.simulate(parser.parse('Hide\n '..key..' >= 2 "Haast"\nShow'),item).status)
		end
	end)
	it("never treats incomplete or unsupported samples as a certain hide",function()
		for _,raw in ipairs({'Hide\n Fated True','Hide\n TwiceCorrupted True','Hide\n UnidentifiedItemTier >= 3','Hide\n FutureKeyword True'}) do
			assert.equal("unknown",parser.simulate(parser.parse(raw),{}).status)
		end
		assert.equal("Show",parser.simulate(parser.parse('Hide\n Fated True\n Class == "Viscera"\nShow'),{Class="Currency"}).action)
		assert.equal("unknown",parser.simulate(parser.parse('Import "other.filter"\nHide'),{}).status)
		assert.equal("invalid",parser.simulate(parser.parse('Hide\n BaseType "broken'),{}).status)
		assert.equal("invalid",parser.simulate(parser.parse('Hide\n ItemLevel'),{}).status)
		assert.equal("invalid",parser.simulate(parser.parse('Hide\n TransfiguredGem >= True'),{TransfiguredGem=true}).status)
	end)
	it("expands supplied filter files in order and leaves missing or cyclic imports unresolved",function()
		local bom=string.char(239,187,191);local profile=filters.profile("included","Included");profile.template=bom..'Import "outer.filter"\nShow'
		profile.importFiles={{name="outer.filter",text=bom..'Import "inner.filter"\nShow\n BaseType "Iron"'},{name="inner.filter",text=bom..'Hide\n BaseType "Iron Hat"'}}
		local raw,report=filters.compile(profile);assert.equal(0,#report.imports);assert.is_truthy(raw:find("# Included filter: inner.filter",1,true))
		assert.is_falsy(raw:find(bom,1,true));for _,diagnostic in ipairs(report.diagnostics) do assert.is_nil(diagnostic.error) end
		assert.equal("Hide",filters.simulate(profile,{BaseType="Iron Hat"}).action)
		assert.equal("Show",filters.simulate(profile,{BaseType="Iron Ring"}).action)
		local checked=filters.validate({schemaVersion=1,activeId=profile.id,profiles={profile}});assert.same(profile.importFiles,checked.profiles[1].importFiles)
		assert.is_truthy(require("Modules.LootFilterStructure").outline(profile).entries[1])
		local store=filters.new(build);store.data=checked;local xml={};store:Save(xml);local restored=filters.new(build);restored:Load(xml);assert.same(profile.importFiles,restored.data.profiles[1].importFiles)
		profile.importFiles[2].text='Import "outer.filter"';local _,cyclic=filters.compile(profile);assert.equal(1,#cyclic.imports);assert.equal("unknown",filters.simulate(profile,{BaseType="Iron Hat"}).status)
		profile.importFiles={};local _,missing=filters.compile(profile);assert.equal(1,#missing.imports);assert.equal("unknown",filters.simulate(profile,{BaseType="Iron Hat"}).status)
		profile.template='Import "outer.filter"';assert.is_truthy(filters.validate({schemaVersion=1,activeId=profile.id,profiles={profile}}))
		profile.template='Hide\n BaseType "Orb of Binding"\nImport "missing.filter"\nShow';local _,migrated=filters.compile(profile);assert.equal(1,#migrated.imports)
	end)
	it("edits and validates included files without touching the original profile",function()
		local profile=filters.profile("included","Included");local saved
		require("Classes.LootFilterImportControl").Open(profile,function(files) saved=files end)
		local c=main.popups[1].controls;c.name:SetText("rules.filter");c.text:SetText('Hide\n BaseType "Iron Hat"');c.keep:Click()
		assert.is_nil(profile.importFiles);assert.equal("rules.filter",saved[1].name);assert.is_truthy(saved[1].text:find("Iron Hat",1,true))
	end)
	it("retains attachment edits across selection and rejected saves",function()
		local profile=filters.profile("included","Included");profile.importFiles={{name="one.filter",text="Show"},{name="two.filter",text="Hide"}};local saved
		require("Classes.LootFilterImportControl").Open(profile,function(files) saved=files end);local c=main.popups[1].controls
		c.files.selFunc(2,c.files.list[2]);c.text:SetText('Hide\n BaseType "Iron Hat"');c.files.selFunc(3,c.files.list[3]);c.files.selFunc(2,c.files.list[2])
		assert.is_truthy(c.text.buf:find("Iron Hat",1,true));c.name:SetText("");c.keep:Click();assert.is_truthy(main.popups[1].controls);assert.equal("",c.name.buf);assert.is_nil(saved)
		main:ClosePopup();c.name:SetText("one.filter");c.keep:Click();assert.is_truthy(saved[1].text:find("Iron Hat",1,true));assert.equal("Hide",saved[2].text)
	end)
	it("evaluates the twice-corrupted filter condition",function()
		local parsed=parser.parse("Hide\n TwiceCorrupted True\nShow")
		assert.equal("Hide",parser.simulate(parsed,{TwiceCorrupted=true}).action)
		assert.equal("Show",parser.simulate(parsed,{TwiceCorrupted=false}).action)
		assert.equal("unknown",parser.simulate(parsed,{}).status)
		assert.equal("invalid",parser.simulate(parser.parse("Hide\n TwiceCorrupted Maybe"),{TwiceCorrupted=true}).status)
	end)
	it("does not use hidden explicit modifier names on unidentified samples",function()
		local parsed=parser.parse('Hide\n HasExplicitMod >=2 "of Haast" "of Ephij"\nShow')
		local names={"of Haast","of Ephij"}
		assert.equal("Hide",parser.simulate(parsed,{Identified=true,HasExplicitMod=names}).action)
		local hidden=parser.simulate(parsed,{Identified=false,HasExplicitMod=names})
		assert.equal("unknown",hidden.status);assert.is_truthy(hidden.reasons[1]:find("hidden",1,true))
		assert.equal("unknown",parser.simulate(parsed,{HasExplicitMod=names}).status)
		assert.equal("unknown",parser.simulate(parsed,{Identified=true}).status)
	end)
	it("supports 3.30 tier/fated, numeric alternatives, booleans, sockets and influences",function()
		local parsed=parser.parse('Show\n UnidentifiedItemTier >= 3\n Fated True\n SocketGroup RGB\n HasInfluence Shaper\nHide')
		assert.equal("Show",parser.simulate(parsed,{UnidentifiedItemTier=4,Fated=true,SocketGroup="RGB BB",HasInfluence={"Shaper"}}).action)
		assert.equal("Hide",parser.simulate(parsed,{UnidentifiedItemTier=2,Fated=true,SocketGroup="RGB BB",HasInfluence={"Shaper"}}).action)
		for _,keyword in ipairs({"Imbued","Vestigial","ZanaMemory","MirageMap"}) do assert.equal("Show",parser.simulate(parser.parse("Show\n "..keyword.." True\nHide"),{[keyword]=true}).action) end
		assert.equal("Show",parser.simulate(parser.parse('Show\n TransfiguredGem "Leap Slam"\nHide'),{TransfiguredGem="Leap Slam"}).action)
		assert.equal("Show",parser.simulate(parser.parse('Show\n TransfiguredGem True\nHide'),{TransfiguredGem="Leap Slam"}).action)
	end)
	it("requests validated account writes without exposing tokens and distinguishes pending from success",function()
		local account=require("Modules.LootFilterAccount");local original=launch.DownloadPage;local called=false
		local api={authToken="test-only",ValidateAuth=function(_,callback) callback(true) end}
		local payload={filter_name="Test",realm="pc",filter="Show",public=false}
		local ok,message=pcall(function()
			launch.DownloadPage=function(_,url,callback,options)
				called=true;assert.equal("https://api.pathofexile.com/item-filter?validate=true",url)
				assert.is_truthy(options.header:find("Content-Type: application/json",1,true));assert.is_false(require("dkjson").decode(options.body).public)
				callback({header="HTTP/1.1 202 Accepted",body='{"filter":{"id":"test"}}'},"Response code: 202")
			end
			account.nextRequest=0;account.request(api,"POST",nil,payload,function(_,err) assert.is_truthy(err:find("processing",1,true)) end)
			assert.is_true(called);assert.is_false(account.busy)
			launch.DownloadPage=function(_,_,callback) callback({header="HTTP/1.1 200 Connection established\r\n\r\nHTTP/2 201 Created",body='{"filter":{"id":"test","validation":{"valid":true}}}'},"Response code: 201") end
			account.nextRequest=0;account.request(api,"POST",nil,payload,function(value,err) assert.is_nil(err);assert.equal("test",value.filter.id) end)
			launch.DownloadPage=function(_,_,callback) callback({header="HTTP/1.1 403 Forbidden",body="{}"}) end
			account.nextRequest=0;account.request(api,"GET",nil,nil,function(_,err) assert.is_truthy(err:find("account:item_filter",1,true)) end)
			assert.has_error(function() account.request(api,"POST","../other",payload,function() end) end)
		end)
		launch.DownloadPage=original;account.busy=false;account.nextRequest=0;assert.is_true(ok,message)
	end)
	it("migrates renamed items and drops empty removed-item blocks without widening Hide",function()
		local raw='Hide\n BaseType == "Orb of Binding"\nShow\n BaseType == "Maven\'s Chisel of Scarabs"\nShow\n BaseType == "Chaos Orb" "Orb of Binding"'
		local migrated,changes=filters.migrate(raw)
		assert.is_nil(migrated:find("Orb of Binding",1,true));assert.is_truthy(migrated:find("Maven's Chisel of Threads",1,true))
		assert.equal(2,#parser.parse(migrated).rules);assert.equal("removed",changes["Orb of Binding"])
		assert.equal("Show",parser.simulate(parser.parse(migrated),{BaseType="Iron Hat"}).action)
		local mixed='Hide\n BaseType "Orb of Binding" Chaos # "Orb of Binding" is a comment\nShow'
		local result=filters.migrate(mixed)
		assert.is_truthy(result:find('Chaos # "Orb of Binding" is a comment',1,true))
		assert.equal("Hide",parser.simulate(parser.parse(result),{BaseType="Chaos Orb"}).action)
		local commentOnly='Show\n BaseType Chaos # "Orb of Binding"\nHide'
		local preserved,notes=filters.migrate(commentOnly);assert.equal(commentOnly,preserved);assert.is_nil(next(notes))
	end)
	it("compiles all seven 3.30-native bases with provenance",function()
		for strictness=0,6 do
			local profile=filters.profile("test","Test");profile.strictness=strictness
			local raw,report=filters.compile(profile)
			assert.is_true(#raw>10000);assert.equal(filters.source().commit,report.baseCommit)
			assert.is_truthy(raw:find("# Copyright (c) 2026 NeverSink",1,true));assert.is_truthy(raw:find("# Permission is hereby granted",1,true))
			assert.is_truthy(raw:find('"Frayed Thread"',1,true))
			for _,diagnostic in ipairs(report.diagnostics) do assert.is_nil(diagnostic.error,diagnostic.error) end
		end
	end)
	it("preserves imported text, personal rules and unknown future metadata",function()
		local profile=filters.profile("test","Test");profile.template='Show\n BaseType == "Iron Hat" # original'
		profile.rules={filters.rule("mine","My rule",{'BaseType == "Chaos Orb"'})}
		local updated=filters.update(profile);assert.equal(profile.template,updated.template);assert.same(profile.rules,updated.rules)
		local saver=build.savers.LootFilters;saver:Upsert(profile)
		local xml={};saver:Save(xml);local restored=filters.new(build);restored:Load(xml);assert.same(saver.data,restored.data)
		restored:Load({'{"schemaVersion":99,"profiles":[]}'});local preserved={};restored:Save(preserved);assert.equal('{"schemaVersion":99,"profiles":[]}',preserved[1])
		assert.has_error(function() restored:Upsert(profile) end)
	end)
	it("requires an explicit base update and produces Ruthless Minimal blocks",function()
		local p=filters.profile("test","Test");p.baseCommit=string.rep("0",40)
		assert.has_error(function() filters.compile(p) end)
		p=filters.update(p);p.mode="Ruthless";local raw=filters.compile(p)
		for _,rule in ipairs(parser.parse(raw).rules) do assert.is_not.equal("Hide",rule.action) end
		assert.is_truthy(raw:find("Minimal",1,true))
		p.mode="Normal";p.template="Minimal\n BaseType Iron";assert.equal("invalid",filters.simulate(p,{BaseType="Iron"}).status)
	end)
	it("generates from saved craft and gear goals while preserving personal rules",function()
		local craft={id="hat",title="Craft helmet",slot="Helmet",startingItem="Rarity: NORMAL\nIron Hat\nItem Level: 86",goals={},steps={}}
		build.savers.CraftingProjects:Upsert(craft)
		local journey=require("Modules.BuildJourney").empty();journey.wishlist={{id="ring",title="Ring",slot="Ring 1",route="farm",targetItem="Rarity: NORMAL\nIron Ring\nItem Level: 80"}};build.savers.BuildJourney:Replace(journey)
		local profile=filters.profile("test","Test");profile.rules={filters.rule("mine","My rule",{'BaseType == "Chaos Orb"'})}
		profile.rules=filters.generate(build,profile);assert.equal(3,#profile.rules);assert.equal("mine",profile.rules[1].id)
		assert.equal("Show",filters.simulate(profile,{BaseType="Iron Hat",Rarity="Rare",ItemLevel=86}).action)
		local count=#profile.rules;profile.rules=filters.generate(build,profile);assert.equal(count,#profile.rules)
	end)
	it("generates gem rules only for enabled groups in the active weapon set",function()
		local original=build.skillsTab.socketGroupList
		build.skillsTab.socketGroupList={
			{enabled=true,slot="Weapon 1",gemList={{nameSpec="Fireball",enabled=true,grantedEffect={color="R"}},{nameSpec="Added Fire Damage Support",enabled=true,grantedEffect={color="R"}}}},
			{enabled=false,gemList={{nameSpec="Ice Nova",enabled=true}}},
			{enabled=true,slot="Weapon 1 Swap",gemList={{nameSpec="Arc",enabled=true}}},
			{enabled=true,gemList={{nameSpec="Spark",enabled=false}}},
		}
		local profile=filters.profile("active-gems","Active gems","campaign")
		local rules=filters.generate(build,profile);local titles={};for _,rule in ipairs(rules) do titles[rule.title]=true end
		assert.is_true(titles.Fireball);assert.is_true(titles["Links for skill group 1"])
		assert.is_nil(titles["Ice Nova"]);assert.is_nil(titles.Arc);assert.is_nil(titles.Spark)
		build.itemsTab.activeItemSet.useSecondWeaponSet=true
		rules=filters.generate(build,profile);titles={};for _,rule in ipairs(rules) do titles[rule.title]=true end
		assert.is_true(titles.Arc);assert.is_nil(titles.Fireball);assert.is_nil(titles["Links for skill group 1"])
		build.itemsTab.activeItemSet.useSecondWeaponSet=false;build.skillsTab.socketGroupList=original
	end)
	it("rejects malformed metadata, title injection, duplicate IDs and executable imports",function()
		local p=filters.profile("test","Bad\nHide");assert.has_error(function() filters.validate({schemaVersion=1,profiles={p}}) end)
		p=filters.profile("test","Test");p.rules={{id="bad",title="Bad",text='Import "evil.filter"'}}
		assert.has_error(function() filters.validate({schemaVersion=1,profiles={p}}) end)
		p=filters.profile("test","Test");assert.has_error(function() filters.validate({schemaVersion=1,profiles={p,p}}) end)
	end)
	it("carries filters through native proposal review and portable XML without exporting files",function()
		local p=filters.profile("test","Test");p.rules={filters.rule("mine","My rule",{'BaseType == "Chaos Orb"'})}
		local bridge=require("Modules.DesktopBuildBridge");local prepared=bridge.prepare(build,{mode="edit",title="Loot filter",baseRevision=bridge.revision(build),operations={{type="set_loot_filters",filters={schemaVersion=1,activeId="test",profiles={p}}}}})
		assert.equal(0,#build.savers.LootFilters.data.profiles);assert.equal(1,#prepared.candidate.savers.LootFilters.data.profiles)
		assert.is_truthy(table.concat(prepared.changes," "):find("Loot filters updated",1,true))
		local raw,contents=require("Modules.PlanningBundle").export(prepared.candidate);assert.equal(1,contents.filters);assert.equal(1,require("Modules.PlanningBundle").import(raw).contents.filters)
	end)
	it("keeps cached preset migrations isolated and still rejects unavailable revisions",function()
		local p=filters.profile("test","Test");local raw,changes=filters.migratedBase(p);changes["invented"]="poisoned report"
		local again,nextChanges=filters.migratedBase(p);assert.equal(raw,again);assert.is_nil(nextChanges.invented)
		p.baseCommit=string.rep("a",40);assert.has_error(function() filters.migratedBase(p) end)
		p.template='Show\n BaseType == "Iron Hat"';assert.is_truthy(filters.migratedBase(p):find("Iron Hat",1,true));p.template='Hide\n BaseType == "Iron Ring"';assert.is_truthy(filters.migratedBase(p):find("Iron Ring",1,true))
	end)
end)
