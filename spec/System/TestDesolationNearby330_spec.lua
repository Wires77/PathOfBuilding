describe("3.30 nearby-enemy Desolation wording",function()
	it("parses the current wording with the same multiplier and caps as the prior wording",function()
		for _,pair in ipairs({
			{"5% increased Attack and Cast Speed for each nearby Enemy, up to a maximum of 30%","5% increased Attack and Cast Speed for each Enemy within 6 metres, up to a maximum of 30%"},
			{"5% increased Movement Speed for each nearby Enemy, up to a maximum of 50%","5% increased Movement Speed for each Enemy within 6 metres, up to a maximum of 50%"},
		}) do
			local old,oldExtra=modLib.parseMod(pair[1]);local current,currentExtra=modLib.parseMod(pair[2])
			assert.is_nil(oldExtra);assert.is_nil(currentExtra)
			assert.same(old,current)
		end
	end)
	it("applies and caps movement speed using the configured nearby enemy count",function()
		newBuild();build.configTab.input.customMods="5% increased Movement Speed for each Enemy within 6 metres, up to a maximum of 50%"
		for _,case in ipairs({{0,1},{3,1.15},{20,1.5}}) do
			build.configTab.input.multiplierNearbyEnemies=case[1];build.configTab:BuildModList();runCallback("OnFrame")
			assert.are.near(case[2],build.calcsTab.mainOutput.MovementSpeedMod,1e-8)
		end
	end)
	it("crafts and imports current text while preserving existing older descriptions",function()
		local sim=require("Modules.CraftingSimulator");local essence="Metadata/Items/Currency/CurrencyEssenceFaridun1"
		for _,case in ipairs({
			{"Iron Gauntlets","AttackCastSpeedPerNearbyEnemyEssence1","5% increased Attack and Cast Speed for each nearby Enemy, up to a maximum of 30%","5% increased Attack and Cast Speed for each Enemy within 6 metres, up to a maximum of 30%"},
			{"Iron Greaves","MovementSpeedPerNearbyEnemyEssence1","5% increased Movement Speed for each nearby Enemy, up to a maximum of 50%","5% increased Movement Speed for each Enemy within 6 metres, up to a maximum of 50%"},
		}) do
			local raw="Rarity: NORMAL\n"..case[1].."\nItem Level: 86"
			local result=sim.perform(raw,{method="essence",essenceId=essence},42)
			assert.is_truthy(result.itemText:find(case[4],1,true));assert.is_truthy(sim.model(result.itemText))
			local model=sim.model(raw);local validated=sim.validateState(model,result.state)
			assert.is_truthy(sim.toItem(model,validated).raw:find(case[4],1,true))
			local changes=table.concat(require("Modules.CraftingInspection").diff(model,model.initial,validated)," ")
			assert.is_truthy(changes:find(case[4],1,true))
			for _,line in ipairs({case[3],case[4]}) do
				local model=sim.model("Rarity: RARE\nTest Item\n"..case[1].."\nItem Level: 86\n"..line)
				assert.equal(case[2],model.initial.affixes[1].id)
				assert.is_truthy(sim.toItem(model,model.initial).raw:find(line,1,true))
			end
		end
	end)
	it("retains the current description in a saved crafting inventory",function()
		newBuild();local sim=require("Modules.CraftingSimulator");local raw="Rarity: NORMAL\nIron Gauntlets\nItem Level: 86"
		local result=sim.perform(raw,{method="essence",essenceId="Metadata/Items/Currency/CurrencyEssenceFaridun1"},42)
		local project={id="desolation-description",title="Desolation gloves",slot="Gloves",startingItem=raw,goals={},steps={}}
		project.inventory={require("Modules.CraftingInventory").capture(project,result.state,"Crafted gloves")};build.savers.CraftingProjects:Upsert(project)
		local xml=build:SaveDB("Desolation gloves");loadBuildFromXML(xml,"Desolation gloves")
		local state=build.savers.CraftingProjects.projects[1].inventory[1].state
		assert.is_truthy(sim.toItem(sim.model(raw),state).raw:find("within 6 metres",1,true))
	end)
end)
