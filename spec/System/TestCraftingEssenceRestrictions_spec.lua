describe("Essence modifier restrictions",function()
	local sim=require("Modules.CraftingSimulator")
	local desolation="Metadata/Items/Currency/CurrencyEssenceFaridun1"
	local function checkRoll(raw,essenceId,cap,seed)
		local model=sim.model(raw);local reason,selected=sim.essenceReason(model,model.initial,essenceId)
		assert.is_nil(reason);assert.is_truthy(selected)
		local result=sim.perform(raw,{method="essence",essenceId=essenceId},seed)
		local forced=false
		for _,entry in ipairs(result.state.affixes) do
			if entry.id==selected.modId then forced=true else assert.is_true(model.byId[entry.id].level<=cap,entry.id) end
		end
		assert.is_true(forced);assert.is_nil(result.state.maxEssenceModLevel)
		return model,result,selected
	end
	it("limits ordinary low-tier essence rolls and prevents reforging rares",function()
		local raw="Rarity: NORMAL\nIron Hat\nItem Level: 86"
		for tier,cap in ipairs({35,45,60,75}) do
			local id="Metadata/Items/Currency/CurrencyEssenceWoe"..tier
			for seed=1,12 do local model,result=checkRoll(raw,id,cap,seed)
				assert.is_truthy(sim.essenceReason(model,result.state,id),"Low-tier essence reforged a rare item")
			end
		end
	end)
	it("uses the 3.30 class mappings and caps the non-guaranteed modifiers",function()
		local cases={{"Leather Belt","MagicFlaskEffectNoAdjacentFlasksEssence1"},{"Iron Hat","LocalGemLevelIfOnlySocketedGemEssence1"},
			{"Iron Ring","ShockwaveUnleashCountEssence1"},{"Rusted Sword","AilmentDoubleDamageEssence1"},
			{"Crude Bow","AilmentDoubleDamageTwoHandEssence1"},{"Iron Gauntlets","AttackCastSpeedPerNearbyEnemyEssence1"}}
		for _,case in ipairs(cases) do
			local raw="Rarity: NORMAL\n"..case[1].."\nItem Level: 86"
			local model,result,selected=checkRoll(raw,desolation,15,18)
			assert.equal(case[2],selected.modId)
			assert.is_nil(sim.essenceReason(model,result.state,desolation))
			local reopened=sim.model(result.itemText);local found
			for _,entry in ipairs(reopened.initial.affixes) do if entry.id==case[2] then found=true end end
			assert.is_true(found,case[1])
		end
	end)
	it("rejects a fractured modifier in the guaranteed modifier's client group",function()
		local model=sim.model("Rarity: NORMAL\nIron Gauntlets\nItem Level: 86")
		local metadata=require("Modules.CraftingAdvanced").data().mods
		local special="AttackCastSpeedPerNearbyEnemyEssence1";local family=metadata[special].groups[1];local conflict
		for _,entry in ipairs(model.mods) do
			local meta=metadata[entry.id]
			if entry.mod.group~=model.byId[special].group and meta then for _,group in ipairs(meta.groups) do if group==family then conflict=entry.id;break end end end
			if conflict then break end
		end
		assert.is_truthy(conflict,"Fixture needs a different native group in the same client family")
		local state=sim.validateState(model,{rarity="RARE",affixes={{id=conflict,range=0.5,fractured=true}}})
		assert.matches("fractured",assert(sim.essenceReason(model,state,desolation)))
		assert.is_false(pcall(sim.perform,model.raw,{method="essence",essenceId=desolation},1,state))
	end)
	it("applies the cap to influenced modifier pools too",function()
		local raw="Rarity: NORMAL\nLeather Belt\nItem Level: 86";local model=sim.model(raw)
		local state=copyTable(model.initial);state.rarity="RARE";state.influences={"shaper"}
		local result=sim.perform(raw,{method="essence",essenceId=desolation},27,state)
		for _,entry in ipairs(result.state.affixes) do if entry.id~="MagicFlaskEffectNoAdjacentFlasksEssence1" then assert.is_true(model.byId[entry.id].level<=15,entry.id) end end
		assert.same({"shaper"},result.state.influences)
	end)
end)
