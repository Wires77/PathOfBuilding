describe("Personal filter rule ordering",function()
	local order=require("Modules.LootFilterRuleOrder")
	local function ids(rules) local result={};for _,rule in ipairs(rules) do result[#result+1]=rule.id end;return result end
	it("moves relative to visible rules while preserving the order of hidden rules",function()
		local rules={{id="a"},{id="hidden1"},{id="b"},{id="hidden2"},{id="c"}}
		assert.is_true(order.move(rules,"c","b",false));assert.same({"a","hidden1","c","b","hidden2"},ids(rules))
		assert.is_true(order.move(rules,"a","b",true));assert.same({"hidden1","c","b","a","hidden2"},ids(rules))
		assert.is_true(order.move(rules,"a","c",false));assert.same({"hidden1","a","c","b","hidden2"},ids(rules))
	end)
	it("leaves missing, identical and already-adjacent destinations unchanged",function()
		local rules={{id="a"},{id="b"},{id="c"}}
		assert.is_false(order.move(rules,"a","missing",true));assert.is_false(order.move(rules,"missing","a",false))
		assert.is_false(order.move(rules,"a","a",false));assert.is_false(order.move(rules,"a","b",false));assert.is_false(order.move(rules,"c","b",true))
		assert.same({"a","b","c"},ids(rules))
	end)
	it("changes the compiled filter's first matching rule",function()
		local filters=require("Modules.LootFilters");local profile=filters.profile("order-test","Order test")
		profile.template="Show";profile.rules={{id="show",title="Show hat",text='Show\n BaseType == "Iron Hat"',enabled=true},
			{id="hide",title="Hide hat",text='Hide\n BaseType == "Iron Hat"',enabled=true}}
		assert.equal("Show",filters.simulate(profile,{BaseType="Iron Hat"}).action)
		assert.is_true(order.move(profile.rules,"hide","show",false))
		assert.equal("Hide",filters.simulate(profile,{BaseType="Iron Hat"}).action)
	end)
end)
