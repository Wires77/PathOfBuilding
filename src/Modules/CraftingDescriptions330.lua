-- Equivalent client descriptions for the two Desolation nearby-enemy mods.
local text={
	AttackCastSpeedPerNearbyEnemyEssence1="5% increased Attack and Cast Speed for each Enemy within 6 metres, up to a maximum of 30%",
	MovementSpeedPerNearbyEnemyEssence1="5% increased Movement Speed for each Enemy within 6 metres, up to a maximum of 50%",
}
local M={}
function M.prepare(model)
	model.descriptions330={}
	for id,line in pairs(text) do if model.byId[id] then
		local mod=copyTable(model.byId[id]);mod[1]=line;model.descriptions330[id]=mod
	end end
end
return M
