local EquipmentPieceComponent = class()
local log = radiant.log.create_logger('equipment_piece')

local SLOT_TO_BONE_MAP = {
      mainhand = 'mainHand',
      offhand = 'offHand',
      leftArm = 'leftArm',
      back = 'torso'
   }

function EquipmentPieceComponent:initialize()
   -- Saved variables
   self._sv.owner = nil
   self._sv._injected_commands = {}
   self._sv._injected_buffs = {}
   self._json = radiant.entities.get_json(self)
end

function EquipmentPieceComponent:restore()
   if not self._json then
      self._json = {}
      self._should_be_destroyed = true
      return
   end
end

function EquipmentPieceComponent:activate()
   if self._should_be_destroyed then
      self:destroy()
      return
   end
   self._roles = self:_get_roles()
end

function EquipmentPieceComponent:post_activate()
   if radiant.entities.exists(self._sv.owner) then
      -- we can't be sure what gets loaded first: us or our owner.  if we get
      -- loaded first, it's way too early to inject the ai.  if the owner got loaded
      -- first, the 'radiant:entities:post_create' event has already been fired.
      self:_inject_ai(self._json.injected_ai)
      -- Only needed for the posture trace? Everything else rehydrates on its own.
      self:_setup_item_rendering()
   end
end

function EquipmentPieceComponent:destroy()
   self:unequip()

   if self._posture_changed_listener then
      self._posture_changed_listener:destroy()
      self._posture_changed_listener = nil
   end
end

function EquipmentPieceComponent:get_slot()
   return self._json.slot
end

function EquipmentPieceComponent:get_additional_equipment()
   return self._json.additional_equipment
end

function EquipmentPieceComponent:get_should_drop()
   -- don't drop equipment that is trivial (ilevel == 0) or equipment that has
   -- the no_drop flag.
   return self:get_ilevel() > 0 and not self._json.no_drop
end

function EquipmentPieceComponent:get_ilevel()
   return self._json.ilevel or 0
end

function EquipmentPieceComponent:get_required_job_level()
   return self._json.required_job_level or 0
end

function EquipmentPieceComponent:get_equip_effect()
   return self._json.equip_effect
end

function EquipmentPieceComponent:_get_roles()
   if not self._roles then
      self._roles = {}
      if self._json and self._json.roles then
         local split_roles = radiant.util.split_string(self._json.roles)
         for _, job_role in ipairs(split_roles) do
            self._roles[job_role] = true
         end
      end
   end
   return self._roles
end

-- roles is a dictionary
function EquipmentPieceComponent:suitable_for_roles(job_roles)
   local roles = self:_get_roles()
   for job_role, _ in pairs(job_roles) do
      if roles[job_role] then
         return true
      end
   end
   return false
end

function EquipmentPieceComponent:equip(entity)
   self:unequip()

   self._sv.owner = entity
   self:_inject_ai(self._json.injected_ai)
   self:_inject_buffs()
   self:_inject_commands(self._json.injected_commands)
   self:_setup_item_rendering()

   radiant.events.trigger(self._entity, 'stonehearth:equipment_piece:equip_changed')
   self.__saved_variables:mark_changed()
end

function EquipmentPieceComponent:unequip()
   if self._sv.owner and self._sv.owner:is_valid() then
      local equipment_component = self._sv.owner:get_component('stonehearth:equipment')
      if equipment_component then
         -- This is a way to ensure if the equipment is destroyed in some way
         -- say if we remove an alias, then we need to tell the owner that
         -- this equipment is no longer valid
         equipment_component:ensure_item_unequipped(self._entity:get_uri())
      end

      self:_remove_ai()
      self:_remove_buffs()
      self:_remove_commands()
      self:_remove_item_rendering()

      self._sv.owner = nil
      radiant.events.trigger(self._entity, 'stonehearth:equipment_piece:equip_changed')
      self.__saved_variables:mark_changed()
   end
end

function EquipmentPieceComponent:is_upgrade_for(unit)
   -- upgradable items have a slot.  if there's not slot (e.g. the job outfits that
   -- just contain abilities), there's no possibility for upgrade
   local slot = self:get_slot()
   if not slot then
      return false
   end

   -- if the unit can't wear equipment, obviously not an upgrade!  similarly, if the
   -- unit has no job, we can't figure out if it can wear this
   local equipment_component = unit:get_component('stonehearth:equipment')
   local job_component = unit:get_component('stonehearth:job')
   if not equipment_component or not job_component then
      return false
   end

   -- if we're not suitable for the unit, bail. (if we don't have a job, bail)
   local job_roles = job_component:get_roles()
   if not job_roles or not self:suitable_for_roles(job_roles) then
      return false
   end

   -- if we're not better than what's currently equipped, bail
   local equipped = equipment_component:get_item_in_slot(slot)
   if equipped and equipped:is_valid() then
      local current_ilevel = equipped:get_component('stonehearth:equipment_piece'):get_ilevel()
      if current_ilevel < 0 or current_ilevel >= self:get_ilevel() then
         -- if current ilevel is < 0, that means the item is not unequippable. It's linked to another item
         return false
      end
   end

   if self:get_required_job_level() > job_component:get_current_job_level() then
      -- not high enough level to equip this
      return false
   end

   -- finally!!!  this is good.  use it!
   return true
end

function EquipmentPieceComponent:_setup_item_rendering()
   local render_type = self._json.render_type

   if render_type == 'merge_with_model' then
      local render_info = self._sv.owner:add_component('render_info')
      render_info:attach_entity(self._entity)

   elseif render_type == 'attach_to_bone' then
      local postures = self._json.postures
      if postures then
         self._posture_changed_listener = radiant.events.listen(self._sv.owner, 'stonehearth:posture_changed', self, self._on_posture_changed)
         self:_on_posture_changed()
      else
         self:_attach_to_bone()
      end
   end
end

function EquipmentPieceComponent:_remove_item_rendering()
   assert(self._sv.owner and self._sv.owner:is_valid())
   local render_type = self._json.render_type

   if render_type == 'merge_with_model' then
      self._sv.owner:add_component('render_info'):remove_entity(self._entity:get_uri())
   elseif render_type == 'attach_to_bone' then
      local postures = self._json.postures
      if postures and self._posture_changed_listener then
         self._posture_changed_listener:destroy()
         self._posture_changed_listener = nil
      end
      self:_remove_from_bone()
   end
end

function EquipmentPieceComponent:_on_posture_changed()
   local posture = radiant.entities.get_posture(self._sv.owner)

   -- use a set/map for this if the list gets long
   if self:_value_is_in_array(posture, self._json.postures) then
      self:_attach_to_bone()
   else
      self:_remove_from_bone()
   end
end

function EquipmentPieceComponent:_value_is_in_array(value, array)
   for _, entry_value in pairs(array) do
      if entry_value == value then
         return true
      end
   end
   return false
end

-- this exists because the equipment slot will not always be the same string as the name of
-- the bone to attch to. For instance, the 'ring' slot will map to 'rightFinger12' bone
function EquipmentPieceComponent:_get_bone_for_slot(slot)
   return SLOT_TO_BONE_MAP[slot]
end

function EquipmentPieceComponent:_attach_to_bone()
   local entity_container = self._sv.owner:add_component('entity_container')
   local bone_name = self:_get_bone_for_slot(self:get_slot())
   log:debug('%s attaching %s to bone %s', self._sv.owner, self._entity, bone_name)
   local mob = self._entity:add_component('mob')
   mob:set_transform(_radiant.csg.Transform())
   entity_container:add_child_to_bone(self._entity, bone_name)
end

function EquipmentPieceComponent:_remove_from_bone()
   local entity_container = self._sv.owner:add_component('entity_container')
   local bone_name = self:get_slot()
   log:debug('%s detaching item on bone %s', self._sv.owner, self._entity, bone_name)
   entity_container:remove_child(self._entity:get_id())
end

function EquipmentPieceComponent:_inject_ai(ai_list)
   assert(self._sv.owner)
   assert(not self._injected_ai)

   if ai_list then
      self._injected_ai = stonehearth.ai:inject_ai(self._sv.owner, ai_list)
   end
end

function EquipmentPieceComponent:_remove_ai()
   if self._injected_ai then
      self._injected_ai:destroy()
      self._injected_ai = nil
   end
end

function EquipmentPieceComponent:_inject_buffs()
   assert(self._sv.owner)

   if self._json.injected_buffs then
      for _, buff in ipairs(self._json.injected_buffs) do
         radiant.entities.add_buff(self._sv.owner, buff);
      end
   end
end

function EquipmentPieceComponent:_remove_buffs()
   if self._json.injected_buffs then
      for _, buff in ipairs(self._json.injected_buffs) do
         radiant.entities.remove_buff(self._sv.owner, buff);
      end
   end
end

function EquipmentPieceComponent:_inject_commands(command_list)
   assert(self._sv.owner)
   -- Don't worry about adding the same command twice.
   -- The command component protects against that.
   if command_list then
      local command_component = self._sv.owner:add_component('stonehearth:commands')
      for _, uri in ipairs(command_list) do
         local command = command_component:add_command(uri)
         if command then -- Have to check if command is nil. If command is nil, that means this entity already had the command added to it.
            table.insert(self._sv._injected_commands, uri)
         end
      end
   end
end

function EquipmentPieceComponent:_remove_commands()
   assert(self._sv.owner and self._sv.owner:is_valid())

   if #self._sv._injected_commands > 0 then
      local command_component = self._sv.owner:add_component('stonehearth:commands')
      for _, uri in ipairs(self._sv._injected_commands) do
         command_component:remove_command(uri)
      end
      self._sv._injected_commands = {}
   end
end

function EquipmentPieceComponent:get_owner()
   return self._sv.owner
end

function EquipmentPieceComponent:get_score_contribution()
   if self._json.military_score then
      return self._json.military_score
   end

   if self._json.ilevel and self._json.ilevel > 0 then
      return self._json.ilevel
   end

   local combined_stats = 0
   -- don't throw an error on getting entity data in case this item has been removed
   local weapon_data = radiant.entities.get_entity_data(self._entity, 'stonehearth:combat:weapon_data', false)
   if weapon_data then
      combined_stats = combined_stats + weapon_data.base_damage
   end

   local armor_data = radiant.entities.get_entity_data(self._entity, 'stonehearth:combat:armor_data', false)
   if armor_data then
      combined_stats = combined_stats + armor_data.base_damage_reduction
   end

   return combined_stats
end

return EquipmentPieceComponent
