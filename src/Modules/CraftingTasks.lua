-- Cooperative, cancellable native crafting work. A job never applies equipment.
local M={}
function M.start(build,run,done,failed,progress,label)
	assert(not M.job,"A crafting job is already running; finish or cancel it first")
	local job={build=build,done=done,failed=failed,progress=progress,label=label,started=os.clock(),current={trial=0}}
	job.thread=coroutine.create(function()
		return run(function(state)
			job.current=state
			if os.clock() >= job.deadline then coroutine.yield() end
		end)
	end)
	M.job=job;return job
end
function M.tick(build)
	local job=M.job;if not job then return end
	if job.build ~= build then M.cancel("The active build changed");return end
	job.deadline=os.clock()+0.004
	local sliceStart=os.clock()
	local ok,result=coroutine.resume(job.thread)
	if build then require("Modules.PlanningPerformance").record(build,job.label or "Crafting simulation slice",os.clock()-sliceStart) end
	if not ok then M.job=nil;if job.failed then pcall(job.failed,tostring(result)) end
	elseif coroutine.status(job.thread) == "dead" then
		M.job=nil
		if job.done then local success,message=pcall(job.done,result);if not success and job.failed then pcall(job.failed,tostring(message)) end end
	elseif job.progress and os.clock() >= (job.nextProgress or 0) then job.nextProgress=os.clock()+0.5;pcall(job.progress,job.current) end
end
function M.cancel(reason)
	local job=M.job;M.job=nil
	if job and job.failed then pcall(job.failed,reason or "Crafting job cancelled") end
end
return M
