-- Moai 2018
-- Backpack component
-- This is the custom component that goes onto the miner's backpack.
-- The backpack is equipped into the new "Torso" slot (attach_to_bone), see
-- overrides for equipment component and equipment_piece.
-- This component does not add any extra storage to the hearthling by itself, or
-- remove the game-set constants for maximum amount of storage for a single
-- hearthling. Its sole purpose is to render the contents of the hearthling's
-- own virtual"backpack".

local BackpackComponent = class()

function BackpackComponent:initialize()
  radiant.log.write('backpack', 0, 'initialized')
  self._equip_changed_listener = radiant.events.listen(self._entity, 'stonehearth:equipment_piece:equip_changed', self, self._on_equip_changed)
  self._sv.owner = self._sv.owner or nil
  self._sv.item_mockups = {}
end

function BackpackComponent:post_activate()
  self:_get_owner()
  if self._sv.owner then self:_attach_to_owner() end
end

function BackpackComponent:_update_description()
  local empty = 'i18n(miner_prof:items.backpack.desc_empty)'
  local contains = 'i18n(miner_prof:items.backpack.desc_cont)'
  local contents = ''
  for id, itemRec in pairs(self._sv.item_mockups) do
     local item = itemRec and itemRec.item
     if item and item:is_valid() then
       local cat = radiant.entities.get_entity_data(item, 'stonehearth:catalog')
       local name = cat and cat.display_name
       if name then
         contents = contents .. name .. ' '
       end
     end
  end
  local full
  if contents == '' then
    full = empty
    -- don't look at me like that
  else
    full = contains .. contents
  end
  radiant.entities.set_description(self._entity, full)

end
function BackpackComponent:_get_owner()
  local epc = self._entity:get_component('stonehearth:equipment_piece')
  local owner = epc:get_owner()
  if owner ~= self._sv.owner then
    self._sv.owner = owner
    self.__saved_variables:mark_changed()
  end
end
function BackpackComponent:_on_equip_changed()
  -- radiant.log.write('miner_prof', 0, 'equip changed!')
  self:_get_owner()
  if self._sv.owner then
    self:_attach_to_owner()
  else
    self:_release_from_owner()
  end
end

function BackpackComponent:_on_item_added(args)
  local item = args.item
  self:_add_local_item(item)
end

function BackpackComponent:_on_item_removed(args)
  local id = args.item_id
  self:_remove_local_item(id)
end

function BackpackComponent:_add_local_item(item)
  if not item or not item:is_valid() then return end
  local sc = self._entity:get_component('stonehearth:storage')
  local id = item:get_id()
  local uri = item:get_uri()
  local copy = radiant.entities.create_entity(uri)
  if copy then
    local res = sc:add_item(copy)
    -- radiant.log.write('backpack', 0, 'Added item ' .. tostring(item) .. ' to backpack store with result ' .. tostring(res))
    self._sv.item_mockups[id] = {
      id = copy:get_id(),
      item = copy
    }
    self:_update_description()
    self.__saved_variables:mark_changed()
  end
end

function BackpackComponent:_remove_local_item(id)
  local copy_rec = self._sv.item_mockups[id]
  if copy_rec then
    local copy_id = copy_rec.id
    local sc = self._entity:get_component('stonehearth:storage')
    local res = sc:remove_item(copy_id)
    -- radiant.log.write('backpack', 0, 'Removed item ' .. tostring(copy_id) .. ' from backpack store with result ' .. tostring(res))
    self._sv.item_mockups[id] = nil
    self:_update_description()
    self.__saved_variables:mark_changed()
  end
end

function BackpackComponent:_attach_to_owner()
  self:_add_item_listeners()
  local sc = self._sv.owner:get_component('stonehearth:storage')
  if sc then
    local items = sc:get_items()
    for id, item in pairs(items) do
       if item and item:is_valid() then
         self:_add_local_item(item)
       end
    end
  end
  self:_update_description()
end

function BackpackComponent:_release_from_owner()
  self:_release_item_listeners()
  for id, itemRec in ipairs(self._sv.item_mockups) do
     local item = itemRec and itemRec.item
     if item and item:is_valid() then
       self:_remove_local_item(id)
     end
  end

  self:_update_description()
end

function BackpackComponent:_add_item_listeners()
  local owner = self._sv.owner
  if not owner then return end
  self._item_added_listener = radiant.events.listen(owner, 'stonehearth:storage:item_added', self, self._on_item_added)
  self._item_removed_listener = radiant.events.listen(owner, 'stonehearth:storage:item_removed', self, self._on_item_removed)
end

function BackpackComponent:_release_item_listeners()
  if self._item_removed_listener then
    self._item_removed_listener:destroy()
    self._item_removed_listener = nil
  end
  if self._item_added_listener then
    self._item_added_listener:destroy()
    self._item_added_listener = nil
  end
end

function BackpackComponent:destroy()
  -- radiant.log.write('backpack', 0, 'destroyed')

  self:_release_from_owner()
  if self._equip_changed_listener then
    self._equip_changed_listener:destroy()
    self._equip_changed_listener = nil
  end
  radiant.entities.kill_entity(self._entity)
end

return BackpackComponent
