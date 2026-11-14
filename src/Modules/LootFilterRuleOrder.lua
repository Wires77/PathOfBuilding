-- Move one personal rule relative to another without reordering the rest.
local M={}
function M.move(rules,sourceId,targetId,after)
	if sourceId==targetId then return false end
	local source,target
	for index,rule in ipairs(rules) do
		if rule.id==sourceId then source=index end
		if rule.id==targetId then target=index end
	end
	if not source or not target or (after and source==target+1) or (not after and source+1==target) then return false end
	local rule=table.remove(rules,source)
	if source<target then target=target-1 end
	table.insert(rules,target+(after and 1 or 0),rule)
	return true
end
return M
