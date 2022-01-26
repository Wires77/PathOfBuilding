expose("test copy/paste items", function()
    local itemList = LoadModule("../spec/TestItems.lua")
    for _, itemText in pairs(itemList) do
        local item = new("Item", itemText)
        assert.are.same(itemText:gsub("%s*$", ""), item:BuildRaw())
    end
end)

expose("test db items", function()
    for _, typeList in pairs(data.uniques) do
        for _, itemText in pairs(typeList) do
            local item = new("Item", "Rarity: UNIQUE\n"..itemText)
            assert.are.same("Rarity: UNIQUE\n"..itemText:gsub("%s*$", ""), item:BuildRaw():gsub("Implicits: 0\n", ""):gsub("Selected Variant:.-\n", ""):gsub("Quality: 20\n", ""):gsub("{range:0.5}", ""):gsub("LevelReq: (%d+)\n", "Requires Level %1\n"))
        end
    end
    for _, itemText in pairs(data.rares) do
        local item = new("Item", "Rarity: RARE\n"..itemText)
        assert.are.same("Rarity: RARE\n"..itemText:gsub("%s*$", ""), item:BuildRaw())
    end
end)
