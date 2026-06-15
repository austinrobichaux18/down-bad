--Initial code modified from LoupAndSnoop's Rubia mod, with permission.

--Given a valid adjustable inserter entity, apply adjustments that will work with adjustable inserter mods.
--Return true if an edit was made.
local function try_adjust_inserter(entity)
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
---@param is_orientation_invalid function Takes in a LuaEntity, and returns TRUE if the orientation is INVALID.
local function force_orientation_condition(entity, player_index, is_orientation_invalid)
    if not is_orientation_invalid(entity) then return end --Done without issues
    
    entity.rotate{by_player=player_index}
    squash_undo_actions(player_index)

    if not is_orientation_invalid(entity) then return end --Done without issues
    
    local true_type = (entity.type == "entity-ghost") and entity.ghost_type or entity.type
    error("Could not find an allowed orientation for an entity of type: " .. entity.prototype.name .. ", True type: " .. true_type)
end


local function is_inserter_facing_south(entity)
    return entity.drop_position.y > entity.pickup_position.y + 0.5
end

local function is_entity_facing_south(entity)
    return entity.direction == defines.direction.south
end

local function is_rail_facing_east(entity)
    return entity.direction == defines.direction.east 
end


local entity_not_allowed_south = {
    ["transport-belt"] = true,
    ["underground-belt"] = true,
    ["splitter"] = true,
    ["pump"] = true,
    ["mining-drill"] = true,
}

array_to_hashset = function(array)
  local hashset = {}
  for _, value in pairs(array) do
    hashset[value]=1
  end
  return hashset
end

--Hashset of prototype types that should keep requester points enabled.
local maintain_requester_types = array_to_hashset(
    {"character", "spider-vehicle", "cargo-landing-pad", "space-platform-hub"})

local remove_logi_section_types = array_to_hashset({"car", })


---@param entity LuaEntity Entity to correct
---@param player_index uint? Index of the player to send notifications, if applicable
---@param skip_recheck boolean? if true, then don't recheck the same entity next frame.
local function direction_correction(entity, player_index, skip_recheck)
    if  not entity 
        or not entity.valid
         then return end

    local entity_type = entity.type;
    if entity.type == "entity-ghost" then 
        entity_type = entity.ghost_type end

    --Requester check. Disables requester chests. Ideally would like bots not to fly south with items but idk how to do that.
    local req_point = entity.get_requester_point()
    if req_point and not maintain_requester_types[entity_type] then
        req_point.enabled = false
       
        local sections = entity.get_logistic_sections()
        if remove_logi_section_types[entity_type] and sections then
            for i = 1, sections.sections_count do
                sections.remove_section(i)
            end
        end
    end

    -- Only horizontal rails
    if entity_type:find("rail") then
        if entity_type == "straight-rail" then
            if not is_rail_facing_east(entity) then
                game.players[player_index].mine_entity(entity,true)
                squash_undo_actions(player_index)
                end
        else
            game.players[player_index].mine_entity(entity,true)
            squash_undo_actions(player_index)
        end
    end

    if entity_not_allowed_south[entity_type] then
            force_orientation_condition(entity, player_index, is_entity_facing_south)
            end

    --Inserters are their own beast.
    if entity_type == "inserter" then
        local true_prototype = entity.type == "entity-ghost" and entity.ghost_prototype or entity.prototype
        if true_prototype.allow_custom_vectors then
            try_adjust_inserter(entity)
        else 
            force_orientation_condition(entity, player_index, is_inserter_facing_south)
        end 
    end
end

-- todo check with modded inserters
-- todo try to make bots not fly south if they are carrying items
-- 

script.on_event(defines.events.on_built_entity, function(event)
    direction_correction(event.entity, event.player_index)
end)

script.on_event(defines.events.on_player_flipped_entity, function(event)
    direction_correction(event.entity, event.player_index)
end)

script.on_event(defines.events.on_player_rotated_entity, function(event)
    direction_correction(event.entity, event.player_index)
end)

script.on_event(defines.events.on_player_joined_game, function(event)
        local allow_move_down =
        settings.global["down-bad-allow-players-move-down"].value
        
        game.print( {"player-join-world.1"})
        if allow_move_down then 
            game.print( {"player-join-world.2"})
        else  
            game.print( {"player-join-world.3"})
        end
end)

-- Prevents player from moving south if setting is enabled local player_positions = {}storage.player_positions = storage.player_positions or {}

script.on_init(function()
    storage.player_positions = storage.player_positions or {}
end)

script.on_event(defines.events.on_player_changed_position, function(event)

    if settings.global["down-bad-allow-players-move-down"].value then
        return
    end

    local player = game.get_player(event.player_index)
    if not player or not player.character then
        return
    end

    local player_index = event.player_index
    local surface_index = player.surface.index
    local current_position = player.position

    storage.player_positions = storage.player_positions or {}
    storage.player_positions[player_index] =
        storage.player_positions[player_index] or {}

    local player_data = storage.player_positions[player_index]
    local last_position_this_surface = player_data[surface_index]

    if last_position_this_surface and current_position.y > last_position_this_surface.y then

        player.teleport{
            x = current_position.x,
            y = last_position_this_surface.y
        }

        player.surface.create_trivial_smoke{
            name = "fire-smoke",
            position = {
                x = current_position.x,
                y = current_position.y + 1
            }
        }

        if math.random(1, 100) == 1 then
            player.print({
                "",
                "[color=red][REDACTED][/color]: ",
                {"down-bad-lore." .. math.random(1, 99)}
            })
        end

        return
    end

    player_data[surface_index] = {
        x = current_position.x,
        y = current_position.y
    }
end)