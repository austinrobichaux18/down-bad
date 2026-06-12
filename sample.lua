
--Initial code modified from LoupAndSoup's Rubia mod, with permission.

local rubia_wind = {}

---Mechanic: Restricting the directions of specific items. Entity passed in could be invalid.
---Warning: Player index could be nil
---@param entity LuaEntity Entity to correct
---@param player_index uint? Index of the player to send notifications, if applicable
---@param skip_recheck boolean? if true, then don't recheck the same entity next frame.
function rubia_wind.wind_correction(entity, player_index, skip_recheck)
    if  not entity or not entity.valid
        or entity.surface.name ~= "rubia" then return end

    --This recheck is currently needed due to a bug in 2.0.66
    if not skip_recheck then 
        rubia.timing_manager.wait_then_do(1, "rubia-wind-correction", {entity, player_index, true})
    end

    local entity_type = entity.type;
    if entity.type == "entity-ghost" then entity_type = entity.ghost_type end

    --Put a lock on responding to repeat rotation event callbacks.
    if storage.rubia_wind_callback_lock then return 
    else storage.rubia_wind_callback_lock = true
    end

    --Requester check
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

    --Check wind behaviors. Prioritize specific entity, then prototype if relevant
    local behavior = wind_entity_functions[entity.prototype.name] or wind_prototype_functions[entity_type]    
    if behavior then
        behavior(entity, player_index); 
        storage.rubia_wind_callback_lock = false
        return
    end

    --Inserters are their own beast.
    --Rotate relevant items to not conflict with wind
    if entity_type == "inserter" then
        local true_prototype = entity.type == "entity-ghost" and entity.ghost_prototype or entity.prototype
        if true_prototype.allow_custom_vectors then
            if try_adjust_inserter(entity) then 
                wind_correction_notification(entity, player_index)
            end
        else force_orientation_condition(entity, player_index, is_unadj_inserter_valid_orientation)
        end
    end

    --Undo the lock
    storage.rubia_wind_callback_lock = false
end
rubia.timing_manager.register("rubia-wind-correction",rubia_wind.wind_correction)