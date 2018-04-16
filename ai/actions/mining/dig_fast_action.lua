-- Moai 2018
-- Almost this entire file is copy-pasted from Radiant's own digging code.
-- /stonehearth/ai/actions/mining/dig_action.lua

local Dig = class()

Dig.name = 'dig fast'
Dig.does = 'miner_prof:mining:dig_fast'
Dig.args = {
   purpose = 'string',
   description = 'string',
}
Dig.priority = 0.5

local resource_radius = 0.5 -- distance from the center of a voxel to the edge
local entity_reach = 1.0   -- read this from entity_data.stonehearth:entity_reach
local tool_reach = 0.75     -- read this from entity_data.stonehearth:weapon_data.reach
local harvest_range = entity_reach + tool_reach + resource_radius


-- the filter function will check if the entity is actually an enabled
-- mining zone.  That doesn't mean we can work in it, though... (see below)
local function get_filter_fn(entity, purpose)
   local player_id = radiant.entities.get_player_id(entity)
   local key = player_id .. ' : ' .. purpose
   -- radiant.log.write('miner_prof', 0, 'Initializing filter with key: ' .. key)

   return stonehearth.ai:filter_from_key('stonehearth:mining:dig', key, function(entity)
         -- radiant.log.write('miner_prof', 0, 'Searching for area...')

         local mzc = entity:get_component('stonehearth:mining_zone')
         if not mzc then
            return false
         end
         -- radiant.log.write('miner_prof', 0, 'Valid area, searching for purpose...')

         if mzc:get_purpose() ~= purpose then
            return false
         end

         -- radiant.log.write('miner_prof', 0, 'Valid purpose, checking enabled...')


         -- make sure it's enabled, too!
         local enabled = mzc:get_enabled()
         if not enabled then
            return false
         end
         -- radiant.log.write('miner_prof', 0, 'Area enabled, checking ownership')


         if radiant.entities.get_player_id(entity) ~= player_id then
            return false
         end

         -- radiant.log.write('miner_prof', 0, 'OK')


         return true
      end)
end

-- the solved function will check to make sure we can work in the mine.
-- we need a permit to do so, first (which we can't acquire until we
-- actually start, but we can at least check up front to see if we *could*
-- get one.)  If we fail to acquire the permit later, we'll just abort.
local function mine_solved_fn(ai, entity, args, path)
   local mzc = path:get_destination()
                      :get_component('stonehearth:mining_zone')
   if not mzc:is_work_available(entity) then
      -- radiant.log.write('miner_prof', 0, 'no work is available at mining zone')

      return false
   end
   -- radiant.log.write('miner_prof', 0, 'work is available at mining zone')

   return true
end

local function get_description(reason)
   return 'find mine to dig quickly in (' .. reason .. ')'
end

local ai = stonehearth.ai

-- function Dig:start()
--   radiant.log.write('miner_prof', 0, 'Dig fast action started')
-- end

return ai:create_compound_action(Dig)
         :execute('stonehearth:find_path_to_entity_type', {
                  filter_fn = ai.CALL(get_filter_fn, ai.ENTITY, ai.ARGS.purpose),
                  description = ai.CALL(get_description, ai.ARGS.description),
                  solved_cb = mine_solved_fn,
               })
         :execute('stonehearth:get_work_permit', {
            worker_permit_manager = ai.BACK(1).destination:get_component('stonehearth:mining_zone')
         })
         :execute('stonehearth:drop_carrying_now')
         :execute('stonehearth:follow_path', {
            path = ai.BACK(3).path,
            stop_distance = harvest_range,
         })
         :execute('miner_prof:mining:dig_fast_adjacent', {
            mining_zone = ai.BACK(4).destination,
            adjacent_location = ai.BACK(4).path:get_finish_point()
         })
