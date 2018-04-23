-- Moai 2018
-- Headlamp component. Toggles a "light" effect around given entity, and equips
-- appropriate armor variant depending on turned on/off state. The armors must
-- be named like so:
-- outfit.json outfit_female.json (standard) outfit_light_off.json,
-- outfit_light_off_female.json outfit_light_on.json outfit_light_on_female.json
-- (all those are new)
-- If the "glowing voxel" effect is desired, make sure to mix in the color map
-- and material map following the example in this mod.

local HeadlampComponent = class()
local MALE = 'male'
local FEMALE = 'female'
local NULL = 'null'
local VERSION = {
  INITIAL = 1,
  REMEMBER_GENDER = 2
}

function HeadlampComponent:initialize()
  self._sv.gender = NULL
  self._equip_changed_listener = radiant.events.listen(self._entity, 'stonehearth:equipment_piece:equip_changed', self, self._on_equip_changed)
end

function HeadlampComponent:destroy()
  self:_clean_up()
end

function HeadlampComponent:_clean_up()
  -- radiant.log.write('miner_prof', 0, 'cleanup called')
  if self._on_posture_changed_listener then
    self._on_posture_changed_listener:destroy()
    self._on_posture_changed_listener = nil
  end

  self:remove()
end

function HeadlampComponent:turn_on()
  -- radiant.log.write('miner_prof', 0, 'turnon called')

  self:_toggle(true)
end

function HeadlampComponent:turn_off()
  -- radiant.log.write('miner_prof', 0, 'turnoff called')

  self:_toggle(false)
end

function HeadlampComponent:remove()
  local rc = self._entity:add_component('render_info')
  if self._sv.gender == MALE then
    rc:set_model_variant('default')
  else
    rc:set_model_variant('female')
  end
end

function HeadlampComponent:add()
  self:_get_owner_info()
  -- radiant.log.write('miner_prof', 0, 'adding headlamp')
  self:_toggle(false)
end

function HeadlampComponent:_toggle(on_off)
  self:_get_owner_info()
  -- radiant.log.write('miner_prof', 0, 'toggling ' .. tostring(on_off))

  if self._entity ~= nil then

    -- radiant.log.write('miner_prof', 0, 'got gender: ' .. self.gender)

    local gen_str = ''
    local switch_str = '_off'
    if self._sv.gender == FEMALE then gen_str = '_female' end
    if on_off then
      switch_str = '_on'
      self:_toggle_light(true)
    else
      self:_toggle_light(false)
      -- self._entity:add_component('stonehearth:lamp'):light_off()
    end
    -- radiant.log.write('miner_prof', 0, 'equip: ' .. tostring(equip))

    local variant = 'light' .. switch_str .. gen_str
    -- radiant.log.write('miner_prof', 0, 'finally, equipping variant: ' .. variant)

    self._entity:add_component('render_info')
                   :set_model_variant(variant)

  end
end

function HeadlampComponent:_toggle_light(light_switch)
  -- radiant.log.write('miner_prof', 0, 'flipping light switch')
  if light_switch then
    if self._effect then return end
    -- radiant.log.write('miner_prof', 0, 'turning on')
    self._effect = radiant.effects.run_effect(self._entity, 'miner_prof:effects:headlamp')
  else
    -- radiant.log.write('miner_prof', 0, 'turning off')
    if self._effect then
      -- radiant.log.write('miner_prof', 0, 'effect exists, destroying')

      self._effect:stop()
      self._effect = nil
    end
  end
end

function HeadlampComponent:_get_owner_info()
  -- radiant.log.write('miner_prof', 0, 'fetch owner info')
  -- radiant.log.write('miner_prof', 0, tostring(self._entity))
  if self._sv.gender == NULL then
    local gender = MALE
    local variant = self._entity:get_component('render_info')
                                :get_model_variant()
    if string.find(variant, 'female') then gender = FEMALE end
    self._sv.gender = gender
    self.__saved_variables:mark_changed()
  end
  -- radiant.log.write('miner_prof', 0, 'Got owner' .. tostring(owner))

  -- self.__saved_variables:mark_changed()
end

function HeadlampComponent:_on_equip_changed()
  -- radiant.log.write('miner_prof', 0, 'equip changed!')

  self:_get_owner_info()
  if owner == nil then
    self:_clean_up()
  end
end

return HeadlampComponent
