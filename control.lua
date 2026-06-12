--Initial code modified from LoupAndSoup's Rubia mod, with permission.
-- local sample = require("sample")
local main = {}

--Given a valid adjustable inserter entity, apply adjustments that will work with adjustable inserter mods.
--Return true if an edit was made.
local function try_adjust_inserter(entity)
            game.print('is using try_adjust_inserter')

    local old_pickup_vector = {
        x = entity.pickup_position.x - entity.position.x,
        y = entity.pickup_position.y - entity.position.y
    }

    local old_drop_vector = {
        x = entity.drop_position.x - entity.position.x,
        y = entity.drop_position.y - entity.position.y
    }

    -- Only modify top -> bottom inserters
    if old_pickup_vector.x == 0
        and old_drop_vector.x == 0
        and old_pickup_vector.y < 0
        and old_drop_vector.y > 0 then

        local old_pickup = entity.pickup_position
        entity.pickup_position = entity.drop_position
        entity.drop_position = old_pickup

        return true
    end

    return false
end


---Remove the last undo item from the given player index, if there is one.
---@param player_index uint?
local function squash_undo_actions(player_index)
    if not player_index then return end
    local player = game.players[player_index]
    if not player then return end
    local stack = player.undo_redo_stack

    --assert(stack.get_undo_item_count() > 1, "Fewer than 2 items on the undo stack!")

    if stack.get_undo_item_count() < 2 then return end
    local undo1 = stack.get_undo_item(1)
    local undo2 = stack.get_undo_item(2)

    if not undo1 or not undo2 then return end

    --Squash them together
    for _, action in pairs(undo1) do
        table.insert(undo2, action)
    end
    --Remove the last one
    stack.remove_undo_item(1)
end

---Force this entity to any orientation until the input function returns TRUE on the entity.
---@param entity LuaEntity
---@param player_index any
---@param orientation_validator function Takes in a LuaEntity, and returns TRUE if the orientation is INVALID.
local function force_orientation_condition(entity, player_index, orientation_validator)
    game.print('is using force_orientation_condition')

    if not orientation_validator(entity) then return end --Done without issues

    entity.rotate{by_player=player_index}
    squash_undo_actions(player_index)

    entity.rotate{by_player=player_index}
    squash_undo_actions(player_index)

    if not orientation_validator(entity) then return end --Done without issues
        game.print('rotated twice but still bad')
    
    local true_type = (entity.type == "entity-ghost") and entity.ghost_type or entity.type
    error("Could not find an allowed orientation for an entity of type: " .. entity.prototype.name .. ", True type: " .. true_type)
end


---Return true if the given unadjustable inserter is in a valid orientation.
---@param entity LuaEntity
---@return boolean
local function is_inserter_facing_east(entity)
    return entity.drop_position.x > entity.pickup_position.x + 0.5
end

local function is_inserter_facing_south(entity)
    return entity.drop_position.y > entity.pickup_position.y + 0.5
end
--#endregion

--Initial code modified from Nancy B + Exfret the wise.
--Thanks to CodeGreen, for help sorting out horizontal splitters

---@param entity LuaEntity Entity to correct
---@param player_index uint? Index of the player to send notifications, if applicable
---@param skip_recheck boolean? if true, then don't recheck the same entity next frame.
function main.direction_correction(entity, player_index, skip_recheck)
    if  not entity 
        or not entity.valid
         then return end

    -- --This recheck is currently needed due to a bug in 2.0.66
    -- if not skip_recheck then 
    --     rubia.timing_manager.wait_then_do(1, "rubia-wind-correction", {entity, player_index, true})
    -- end

    local entity_type = entity.type;
    if entity.type == "entity-ghost" then 
        entity_type = entity.ghost_type end

    -- --Requester check
    -- local req_point = entity.get_requester_point()
    -- if req_point and not maintain_requester_types[entity_type] then
    --     req_point.enabled = false
    --     local sections = entity.get_logistic_sections()
    --     if remove_logi_section_types[entity_type] and sections then
    --         for i = 1, sections.sections_count do
    --             sections.remove_section(i)
    --         end
    --     end
    -- end

    --Inserters are their own beast.
    --Rotate relevant items to not conflict with wind
    if entity_type == "inserter" then
        local true_prototype = entity.type == "entity-ghost" and entity.ghost_prototype or entity.prototype
        if true_prototype.allow_custom_vectors then
            try_adjust_inserter(entity)
        else 
            force_orientation_condition(entity, player_index, is_inserter_facing_south)
        end
    end
end

script.on_event(defines.events.on_built_entity, function(event)
    main.direction_correction(event.entity, event.player_index)
end)

script.on_event(defines.events.on_player_flipped_entity, function(event)
    main.direction_correction(event.entity, event.player_index)
end)

script.on_event(defines.events.on_player_rotated_entity, function(event)
    main.direction_correction(event.entity, event.player_index)
end)

