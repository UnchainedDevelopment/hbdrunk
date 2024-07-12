local effects = {}

-- Function to jumble text
function effects.jumble_text(text)
    local jumbled_text = ""
    local vowels = { 'a', 'e', 'i', 'o', 'u' }
    local consonants = { 'b', 'c', 'd', 'f', 'g', 'h', 'j', 'k', 'l', 'm', 'n', 'p', 'q', 'r', 's', 't', 'v', 'w', 'x', 'y', 'z' }

    for char in text:gmatch(".") do
        local rand = math.random(1, 100)
        if rand <= 25 then
            if char:match("[%a]") then
                local replacement_char
                if char:match("[AEIOUaeiou]") then
                    replacement_char = vowels[math.random(1, #vowels)]
                else
                    replacement_char = consonants[math.random(1, #consonants)]
                end
                jumbled_text = jumbled_text .. replacement_char
            else
                jumbled_text = jumbled_text .. char
            end
        else
            jumbled_text = jumbled_text .. char
        end
    end

    return jumbled_text
end

-- Function to apply blur vision effect
function effects.apply_blur_vision(player)
    local intoxication_level = player:get_meta():get_int("intoxication") or 0

    -- Remove existing blur vision HUD elements
    for i = 1, 5 do
        local hud_id = player:get_meta():get_int("blur_vision_hud_id_" .. i)
        if hud_id then
            player:hud_remove(hud_id)
        end
    end

    if intoxication_level >= 5 then
        local intensity_steps = { 5, 25, 45, 65, 90 }
        local max_opacity = 255

        for i, threshold in ipairs(intensity_steps) do
            if intoxication_level >= threshold then
                local intensity = math.min(max_opacity, (intoxication_level - threshold + 1) * (max_opacity / (#intensity_steps * 10)))
                local hud_id = player:hud_add({
                    hud_elem_type = "image",
                    position = { x = 0.5, y = 0.5 },
                    scale = { x = -100, y = -100 },
                    text = "intoxicated_vignette.png^[opacity:" .. intensity,
                    alignment = { x = 0, y = 0 },
                    offset = { x = 0, y = 0 },
                })
                player:get_meta():set_int("blur_vision_hud_id_" .. i, hud_id)
            end
        end

        -- Schedule removal of blur vision after 3 seconds if not intoxicated enough
        minetest.after(3, function()
            local current_intoxication = player:get_meta():get_int("intoxication") or 0
            if current_intoxication < 5 then
                effects.cleanup_blur_vision(player)
            end
        end)
    else
        effects.cleanup_blur_vision(player)
    end
end

-- Cleanup function for blur vision HUD elements
function effects.cleanup_blur_vision(player)
    for i = 1, 5 do
        local hud_id = player:get_meta():get_int("blur_vision_hud_id_" .. i)
        if hud_id then
            player:hud_remove(hud_id)
        end
    end
    -- Reset player's visual and movement effects
    player:set_physics_override({ speed = 1.0 })
    player:hud_change(player:get_meta():get_int("shake_hud_id"), "text", "")
    player:hud_change(player:get_meta():get_int("distort_hud_id"), "text", "")
    player:set_fov(0)
end

-- Function to apply stumble effect
function effects.apply_stumble_effect(player)
    local direction = math.random(1, 4)
    local pos = player:get_pos()
    if direction == 1 then
        pos.x = pos.x + 1
    elseif direction == 2 then
        pos.x = pos.x - 1
    elseif direction == 3 then
        pos.z = pos.z + 1
    elseif direction == 4 then
        pos.z = pos.z - 1
    end
    player:set_pos(pos)
end


-- Function to apply blackout effect
function effects.apply_blackout_effect(player, blackout_duration)
    -- Freeze player in place
    player:set_physics_override({ speed = 0.0 })
    
    -- Check if the blackout message has already been sent
    if player:get_meta():get_int("blackout_message_sent") ~= 1 then
        -- Send message to inform the player
        minetest.chat_send_player(player:get_player_name(), "You are too intoxicated to move!")
        player:get_meta():set_int("blackout_message_sent", 1)
    end

    -- Add blackout HUD element
    local hud_id = player:get_meta():get_int("blackout_hud_id")
    if hud_id ~= 0 then
        player:hud_remove(hud_id)
    end
    hud_id = player:hud_add({
        hud_elem_type = "image",
        position = { x = 0.5, y = 0.5 },
        scale = { x = -100, y = -100 },
        text = "blackout.png",
        alignment = { x = 0, y = 0 },
        offset = { x = 0, y = 0 },
    })
    player:get_meta():set_int("blackout_hud_id", hud_id)
    
    minetest.log("action", "[hbdrunk] Added blackout HUD element for player: " .. player:get_player_name() .. ", HUD ID: " .. hud_id)

    -- Schedule waking up after blackout_duration seconds
    minetest.after(blackout_duration, function()
        if player:get_meta():get_int("in_blackout") == 1 then
            effects.wake_up_from_blackout(player)
            -- Set next blackout time to at least 2 minutes after waking up
            player:get_meta():set_float("next_blackout_time", minetest.get_gametime() + 120)
        end
    end)
end

-- Function to wake up from blackout
function effects.wake_up_from_blackout(player)
    -- Remove blackout HUD element if it exists
    local hud_id = player:get_meta():get_int("blackout_hud_id")
    if hud_id ~= 0 then
        player:hud_remove(hud_id)
    end
    player:get_meta():set_int("blackout_hud_id", 0)

    -- Reset physics override
    player:set_physics_override({ speed = 1.0 })
    
    -- Reset flag indicating the player is in blackout
    player:get_meta():set_int("in_blackout", 0)

    -- Reset the message sent flag
    player:get_meta():set_int("blackout_message_sent", 0)

    -- Reset blackout timers
    player:get_meta():set_float("next_blackout_time", 0)
    player:get_meta():set_float("wake_up_time", 0)

    -- Send message to inform the player they woke up groggy
    minetest.chat_send_player(player:get_player_name(), "You woke up groggy and can move again.")
end

-- Function to check for alcohol poisoning and handle player death
function effects.check_alcohol_poisoning(player)
    local max_intoxication = 100
    local current_intoxication = player:get_meta():get_int("intoxication") or 0

    if current_intoxication >= max_intoxication then
        -- Kill the player
        local player_hp = player:get_hp()
        if player_hp > 0 then
            player:set_hp(0)
            minetest.chat_send_player(player:get_player_name(), "You drank yourself to death! 🍻☠️")
        end
    end
end

-- Function to update intoxication level
function effects.update_intoxication(player, increase_amount)
    local current_intoxication = player:get_meta():get_int("intoxication") or 0
    local new_intoxication = math.min(100, current_intoxication + increase_amount)
    player:get_meta():set_int("intoxication", new_intoxication)

    effects.apply_blur_vision(player)
    effects.check_alcohol_poisoning(player) -- Ensure this is called after updating intoxication
end

-- Function to reset intoxication on player death
function effects.reset_intoxication_on_death(player)
    player:get_meta():set_int("intoxication", 0)
    hb.change_hudbar(player, "intoxication", 0)  -- Update HUD bar to show 0 intoxication
    effects.update_intoxication_hud(player, 0)  -- Ensure HUD bar visibility is updated

    -- Remove intoxicated_vignette.png
    local vignette_hud_id = player:get_meta():get_int("vignette_hud_id")
    if vignette_hud_id ~= 0 then
        player:hud_remove(vignette_hud_id)
        player:get_meta():set_int("vignette_hud_id", 0)  -- Reset HUD ID
    end
end


return effects
