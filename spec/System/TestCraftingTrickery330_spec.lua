describe("3.30 Essence of Trickery",function()
	local sim=require("Modules.CraftingSimulator")
	local id="PlayerIsDeliriousEssence1"
	local essence="Metadata/Items/Currency/CurrencyEssenceUber1"
	local belt="Rarity: NORMAL\nLeather Belt\nItem Level: 86"
	it("offers the confirmed belt modifier only through the special essence",function()
		local model=sim.model(belt);local found
		for _,row in ipairs(model.essences) do if row.id==essence then found=row end end
		assert.equal(id,assert(found).modId);assert.is_true(model.special[id])
		for _,row in ipairs(model.mods) do assert.not_equal(id,row.id) end
		local workbench=require("Modules.CraftingWorkbench")
		assert.equal("Essence of Trickery",workbench.actionLabel({method="essence",essenceId=essence},model))
		assert.equal(workbench.icon("essence",{essenceId="Metadata/Items/Currency/CurrencyEssenceDelirium1"},model),workbench.icon("essence",{essenceId=essence},model))
		local name,art,kind=require("Modules.CraftingPrices").describe(essence,model)
		assert.equal("Essence of Trickery",name);assert.is_truthy(art);assert.equal("Currency",kind)
		local helmet=sim.model("Rarity: NORMAL\nIron Hat\nItem Level: 86")
		assert.is_truthy(sim.essenceReason(helmet,helmet.initial,essence))
	end)
	it("forces the modifier and preserves it through item copies",function()
		local result=sim.perform(belt,{method="essence",essenceId=essence},12)
		assert.matches("You are affected by Delirium Fog",result.itemText)
		local reopened=sim.model(result.itemText);local found
		for _,entry in ipairs(reopened.initial.affixes) do if entry.id==id then found=true end end
		assert.is_true(found)
		local plain=sim.model("Rarity: RARE\nFog Belt\nLeather Belt\nItem Level: 86\nYou are affected by Delirium Fog")
		assert.equal(id,plain.initial.affixes[1].id)
		local details=table.concat(require("Modules.CraftingInspection").modDetails(plain,id)," ")
		assert.matches("not modeled",details)
		local recipe={steps={{method="essence",essenceId=essence}},targets={{anyOf={id}}}}
		local summary=sim.simulate(belt,recipe,{trials=3,maxActions=1,seed=4,prices={[essence]=2},currency="chaos"})
		assert.equal(3,summary.successes);assert.equal(3,summary.currencySpent[essence]);assert.equal(2,summary.meanCost)
	end)
	it("can reforge a rare belt and has no item-level restriction",function()
		local low="Rarity: NORMAL\nLeather Belt\nItem Level: 1"
		local first=sim.perform(low,{method="essence",essenceId=essence},17)
		local second=sim.perform(low,{method="essence",essenceId=essence},18,first.state)
		local found;for _,entry in ipairs(second.state.affixes) do if entry.id==id then found=true end end
		assert.is_true(found)
	end)
end)
