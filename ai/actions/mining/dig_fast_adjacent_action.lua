-- Moai 2018
-- Almost this entire file is copy-pasted from Radiant's own digging code.
-- /stonehearth/ai/actions/mining/dig_adjacent_action.lua
-- Relevant code added by me is highlighted via comments.

local Entity = _radiant.om.Entity
local Point3 = _radiant.csg.Point3
local DigAdjacent = class()
local log = radiant.log.create_logger('mining')

DigAdjacent.name = 'dig fast adjacent'
DigAdjacent.does = 'miner_prof:mining:dig_fast_adjacent'
DigAdjacent.args = {
   mining_zone = Entity,
   adjacent_location = Point3,
}
DigAdjacent.priority = 1

-- TODO: refactor this with mine_action
local resource_radius = 0.5 -- distance from the center of a voxel to the edge
local entity_reach = 1.0   -- read this from entity_data.stonehearth:entity_reach
local tool_reach = 0.75     -- read this from entity_data.stonehearth:weapon_data.reach
local harvest_range = entity_reach + tool_reach + resource_radius

function DigAdjacent:start_thinking(ai, entity, args)
   if ai.CURRENT.carrying then
      return
   end

   local mining_zone = args.mining_zone
   local adjacent_location = args.adjacent_location

   -- resolve which block we are going to mine first
   self._block, self._reserved_region_for_block = stonehearth.mining:get_block_to_mine(adjacent_location, mining_zone)
   if self._block then
      ai:set_think_output()
   end
end

function DigAdjacent:start(ai, entity, args)
   local mining_zone = args.mining_zone

   -- reserve the block and any supporting blocks
   local reserved = self:_reserve_blocks(self._reserved_region_for_block, mining_zone)
   self._reserved_region_for_block = nil

   if not reserved then
      ai:abort('could not reserve mining region')
   end

   -- if the enable bit is toggled while we're running the action, go ahead and abort.
   self._zone_enabled_trace = radiant.events.listen(mining_zone, 'stonehearth:mining:enable_changed', function()
         local enabled = mining_zone:get_component('stonehearth:mining_zone')
                                       :get_enabled()
         if not enabled then
            ai:abort('mining zone not enabled')
         end
      end)
end

-- #############################################################################
-- ############################ Changes start here #############################
-- #############################################################################
function DigAdjacent:run(ai, entity, args)
   local mining_zone = args.mining_zone
   local adjacent_location = args.adjacent_location
   local block = self._block
   local action_repeated = 0
   local numBlocksConsumed = 35
   self._block = nil
   local extra_blocks = 0

   ai:unprotect_argument(mining_zone)
   local weapon = radiant.entities.get_equipped_item(entity, 'mainhand')
   if weapon then
     extra_blocks = radiant.entities.get_entity_data(weapon, 'miner_prof:pickaxe_data').extra_blocks
   end

   -- Get a reference to the Miner job controller, which "knows" how good it is
   -- at its own job.
   local mc = entity:get_component('stonehearth:job'):get_curr_job_controller()
   local strikes, blocks = mc:get_miner_work()
   -- radiant.log.write('miner_prof', 0, 'Got' .. tostring(strikes) .. ' strikes and ' .. tostring(blocks) .. ' blocks')


   -- Mine the mining zone in a "fast" fashion
   -- H'ling approaches the block and hits it $strikes times first, then is
   -- allowed to pick up $blocks number of blocks.
   repeat
      strikes, blocks = mc:get_miner_work()
      blocks = blocks + extra_blocks
      if numBlocksConsumed >= blocks then
        numBlocksConsumed = 0
        action_repeated = 0
        repeat
          ai:execute('stonehearth:run_effect', { effect = 'mine_with_tool' })
          action_repeated = action_repeated + 1
        until action_repeated >= strikes
      end
      numBlocksConsumed = numBlocksConsumed + 1
      self:_mine_block(ai, entity, mining_zone, block)
      block, adjacent_location = self:_move_to_next_available_block(ai, entity, mining_zone, adjacent_location)
   until not block
end

function DigAdjacent:_mine_block(ai, entity, mining_zone, block)
   if not mining_zone:is_valid() then
      return false
   end

   local worker_location = radiant.entities.get_world_grid_location(entity)

   radiant.entities.turn_to_face(entity, block)

   -- check after yielding
   if not mining_zone:is_valid() then
      return false
   end

   -- The reserved region may include support blocks. We must release it before looking
   -- for the next block to mine so that they will be included as candidates.
   -- Also release it on any failure conditions.
   self:_release_blocks(mining_zone)

   -- any time we yield, check to make sure we're still in the same location
   if radiant.entities.get_world_grid_location(entity) ~= worker_location then
      return false
   end



   local mining_zone_component = mining_zone:get_component('stonehearth:mining_zone')
   local loot = mining_zone_component:mine_point(block)
   local items = radiant.entities.spawn_items(loot, worker_location, 1, 3, { owner = entity })
   local inventory = stonehearth.inventory:get_inventory(radiant.entities.get_player_id(entity))
   if inventory then
      for _, item in pairs(items) do
         inventory:add_item_if_not_full(item)
      end
   end
   -- Notify the job component that something was mined, allowing us to award Xp
   radiant.events.trigger(entity, 'miner_prof:fast_mined_anything', { mined = loot })

-- #############################################################################
-- ############################ Changes end here ###############################
-- #############################################################################
   return true
end

function DigAdjacent:_move_to_next_available_block(ai, entity, mining_zone, current_adjacent_location)
   if not mining_zone:is_valid() then
      return nil, nil
   end

   -- Current_adjacent_location is a point in the adjacent region of the mining_zone.
   -- Worker_location is where the worker is actually in the world. This is often different than the
   -- adjacent location becuase we stop short in follow path to allow space for the mining animation.
   local worker_location = radiant.entities.get_world_grid_location(entity)
   local next_block, next_adjacent_location, reserved_region_for_block

   -- check to see if there are more reachable blocks from our current_adjacent_location
   next_block, reserved_region_for_block = stonehearth.mining:get_block_to_mine(current_adjacent_location, mining_zone)
   if self:_is_eligible_block(next_block, worker_location) then
      next_adjacent_location = current_adjacent_location
      self:_reserve_blocks(reserved_region_for_block, mining_zone)
      return next_block, next_adjacent_location
   end

   -- no more work at current_adjacent_location, move to another
   local path = entity:get_component('stonehearth:pathfinder')
                           :find_path_to_entity_sync('find another block to mine', mining_zone, 8)

   if not path then
      return nil, nil
   end

   next_adjacent_location = path:get_finish_point()
   next_block, reserved_region_for_block = stonehearth.mining:get_block_to_mine(next_adjacent_location, mining_zone)
   if not next_block then
      return nil, nil
   end

   -- reserve the block and any supporting blocks before yielding
   self:_reserve_blocks(reserved_region_for_block, mining_zone)

   ai:execute('stonehearth:follow_path', {
      path = path,
      stop_distance = harvest_range,
   })

   return next_block, next_adjacent_location
end

function DigAdjacent:_is_eligible_block(block, worker_location)
   if not block then
      return false
   end

   -- don't mine blocks that we are standing on
   if block == worker_location - Point3.unit_y then
      return false
   end

   return true
end

function DigAdjacent:stop(ai, entity, args)
   local mining_zone = args.mining_zone

   self:_release_blocks(mining_zone)

   if self._zone_enabled_trace then
      self._zone_enabled_trace:destroy()
      self._zone_enabled_trace = nil
   end
end

function DigAdjacent:_reserve_blocks(region, mining_zone)
   local mining_zone_component = mining_zone:add_component('stonehearth:mining_zone')
   local reserved = mining_zone_component:reserve_region(region)

   if reserved then
      self._reserved_blocks = region
   else
      self._reserved_blocks = nil
   end

   return reserved
end

function DigAdjacent:_release_blocks(mining_zone)
   if not self._reserved_blocks then
      return
   end

   if not mining_zone:is_valid() then
      return
   end

   local mining_zone_component = mining_zone:add_component('stonehearth:mining_zone')
   mining_zone_component:unreserve_region(self._reserved_blocks)
   self._reserved_blocks = nil
end

return DigAdjacent
