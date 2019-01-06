-- Moai 2018
-- This is the Job Controller for the Miner. It is responsible for awarding XP
-- to the miner based on the things he mines, as well as keeing his mining stats
-- up to date.
-- Parts of this file were based on other professions included in Stonehearth,
-- particularly the trapper's ability to increase inventory size.

local MinerClass = class()
local BaseJob = require 'stonehearth.jobs.base_job'
local NUM_BLOCKS_PER_XP = 20
radiant.mixin(MinerClass, BaseJob)

-- Initialize ourselves and set our default values to mimic regular SH mining
function MinerClass:initialize()
  BaseJob.initialize(self)
  self._mined_items = {}
  self._mined_item_num = 0
  self._stance = nil
  self._status = 'off'
  self._sv.strikes = 1
  self._sv.blocks = 1
end

-- Listen for things being mined
function MinerClass:_create_listeners()
  self._on_posture_changed_listener = radiant.events.listen(self._sv._entity, 'stonehearth:posture_changed', self, self._on_posture_changed)
  self._on_light_status_listener = radiant.events.listen(self._sv._entity, 'miner_prof:light_status', self, self._on_light_status)
  self._on_mined_listener = radiant.events.listen(self._sv._entity, 'miner_prof:fast_mined_anything', self, self._on_mined_anything)
end

function MinerClass:_remove_listeners()
  if self._on_mined_listener then
    self._on_mined_listener:destroy()
    self._on_mined_listener = nil
  end
  if self._on_posture_changed_listener then
    self._on_posture_changed_listener:destroy()
    self._on_posture_changed_listener = nil
  end
  if self._on_light_status_listener then
    self._on_light_status_listener:destroy()
    self._on_light_status_listener = nil
  end
end

-- Mining light request received; try to toggle light, remember request otherwise
function MinerClass:_on_light_status(args)
  -- radiant.log.write('miner_prof', 0, 'posture changed')
  self._status = args.status
  self:_try_toggle_light()
end

-- Stance received; try to turn on the light if we wanted to before
function MinerClass:_on_posture_changed(args)
  self._posture = radiant.entities.get_posture(self._sv._entity)
  self:_try_toggle_light()
end

function MinerClass:_try_toggle_light()
  local jc = self._sv._entity:get_component('stonehearth:job')
  if jc:curr_job_has_perk('miner_light_bonus') then
    local hlc = self._sv._entity:add_component('miner_prof:headlamp')
    if self._status == 'on' and self._posture == 'stonehearth:mine' then
      hlc:turn_on()
    else
      hlc:turn_off()
    end
  end
end

function contains(table, element)
  for _, value in pairs(table) do
    if value == element then
      return true
    end
  end
  return false
end

-- Remember what we mined and award XP
function MinerClass:_on_mined_anything(args)
   local loot = args.mined
   local res = self._mined_items
   local total = self._mined_item_num
   for uri, val in pairs(loot) do
     res[uri] = val
   end
   total = total + 1
   self._mined_items = res
   self._mined_item_num = total
   if total >= NUM_BLOCKS_PER_XP then
     -- Award 1 base xp for mining NUM_BLOCKS_PER_XP blocks
     -- radiant.log.write('miner_prof', 0, 'Init xp adding code')

     local total_xp = 1
     local found_ore = false
     for uri, val in pairs(self._mined_items) do
       -- Check if we found ore
       local tags = radiant.entities.get_entity_data(uri, 'stonehearth:catalog').material_tags or nil
       if type(tags) == 'table' then
         if contains(tags, 'ore') then
           found_ore = true
           break
         end
       else if type(tags) == 'string' then
         if string.match(tags, 'ore') then
           found_ore = true
           break
         end
     end
     if found_ore then
       -- Award 1 xp for finding ore
       total_xp = total_xp + 1
     end
     -- radiant.log.write('miner_prof', 0, 'Awarding ' .. total_xp .. 'xp for mining ' .. NUM_BLOCKS_PER_XP .. 'blocks')
     self._job_component:add_exp(total_xp)
     self._mined_items = {}
     self._mined_item_num = 0
   end
end

-- Shows its own work ability
function MinerClass:get_miner_work()
  return self._sv.strikes, self._sv.blocks
end

-- The functions below are all referenced in the miner_description.json
-- Each one corresponds to a special perk that the Miner gets, or loses, on job
-- promotion or demotion.

-- Sets the miner's work ability
function MinerClass:set_miner_work(args)
  self._sv.strikes = args.strikes
  self._sv.blocks = args.blocks
  -- radiant.log.write('miner_prof', 0, 'Mining strikes set to ' .. tostring(args.strikes) .. ' and blocks set to ' .. tostring(args.blocks))
  self.__saved_variables:mark_changed()
end

-- adds or removes the backpack
function MinerClass:add_backpack()
  self._backpack =  radiant.entities.create_entity('miner_prof:equipment:backpack')
  radiant.entities.equip_item(self._sv._entity, self._backpack)
end
function MinerClass:remove_backpack()
  local ec = self._sv._entity:get_component('stonehearth:equipment')
  if not ec then return end
  ec:unequip_item('miner_prof:equipment:backpack')
  if self._backpack then
    radiant.entities.destroy_entity(self._backpack)

    self._backpack = nil
  end
end

-- Adds or removes the headlamp
function MinerClass:add_light()
  self._sv._entity:add_component('miner_prof:headlamp'):add()
  self:_try_toggle_light()
end

function MinerClass:remove_light()
  self._sv._entity:add_component('miner_prof:headlamp'):remove()
end

-- Increases backpack size (adapted from trapper)
function MinerClass:increase_backpack_size(args)
   local sc = self._sv._entity:get_component('stonehearth:storage')
   sc:change_max_capacity(args.backpack_size_increase)
   local capacity = sc:get_capacity()
   if capacity > 4 then
     self:add_backpack()
   else
     self:remove_backpack()
   end
end

-- Decreases backpack size
function MinerClass:decrease_backpack_size(args)
   self:increase_backpack_size({backpack_size_increase = -args.backpack_size_increase})
end

function MinerClass:destroy()
  -- radiant.log.write('miner_prof', 0, 'destroyed')

  if self._backpack then
    self:remove_backpack()
  end
end

return MinerClass
