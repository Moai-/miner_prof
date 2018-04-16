-- Moai 2018
-- This is the Job Controller for the Miner. It is responsible for awarding XP
-- to the miner based on the things he mines, as well as keeing his mining stats
-- up to date.
-- Parts of this file were based on other professions included in Stonehearth,
-- particularly the trapper's ability to increase inventory size.

local MinerClass = class()
local BaseJob = require 'stonehearth.jobs.base_job'
radiant.mixin(MinerClass, BaseJob)

-- Initialize ourselves and set our default values to mimic regular SH mining
function MinerClass:initialize()
  BaseJob.initialize(self)
  self._sv.strikes = 1
  self._sv.blocks = 1
end

-- Listen for things being mined
function MinerClass:_create_listeners()
  self._mined_items = 0
  self._on_mined_listener = radiant.events.listen(self._sv._entity, 'miner_prof:fast_mined_anything', self, self._on_mined_anything)
end

function MinerClass:_remove_listeners()
   if self._on_mined_listener then
      self._on_mined_listener:destroy()
      self._on_mined_listener = nil
   end
end

-- Award XP for mining a number of anything
-- TODO: award XP based on the presence of rare ore??
function MinerClass:_on_mined_anything(args)
   self._mined_items = self._mined_items + 1
   if self._mined_items >= 8 then
     self._mined_items = 0
     self._job_component:add_exp(1)
   end
end

-- Sets the miner's work ability
function MinerClass:set_miner_work(args)
  self._sv.strikes = args.strikes
  self._sv.blocks = args.blocks
  -- radiant.log.write('miner_prof', 0, 'Mining strikes set to ' .. tostring(args.strikes) .. ' and blocks set to ' .. tostring(args.blocks))

  self.__saved_variables:mark_changed()
end

-- Increases backpack size (copied from trapper)
function MinerClass:increase_backpack_size(args)
   local sc = self._sv._entity:get_component('stonehearth:storage')
   sc:change_max_capacity(args.backpack_size_increase)
end

-- Decreases backpack size
function MinerClass:decrease_backpack_size(args)
   self:increase_backpack_size(-args.backpack_size_increase)
end

-- Shows its own work ability
function MinerClass:get_miner_work()
  return self._sv.strikes, self._sv.blocks
end

return MinerClass
