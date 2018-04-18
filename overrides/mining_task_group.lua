local MiningTaskGroup = class()
MiningTaskGroup.name = 'mining'
MiningTaskGroup.does = 'stonehearth:simple_labor'
MiningTaskGroup.priority = {0.4, 1}

return stonehearth.ai:create_task_group(MiningTaskGroup)
         :work_order_tag("mine")
         :declare_task('stonehearth:mine', {0, 1})
