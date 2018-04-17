-- Moai 2018
-- Almost this entire file is copy-pasted from Radiant's own digging code.
-- /stonehearth/ai/actions/mining/mine_action.lua

local Mine = class()

Mine.name = 'mine_fast'
Mine.does = 'stonehearth:mine'
Mine.status_text_key = 'stonehearth:ai.actions.status_text.mine'
Mine.args = {}
Mine.priority = 0

local ai = stonehearth.ai
return ai:create_compound_action(Mine)
         :execute('miner_prof:mining:dig_fast', {
               purpose = stonehearth.constants.mining.purpose.MINING,
               description = 'mine fast'
            })
