local intoxication_drain_rate = 2  -- Amount to drain per interval
local intoxication_max = 100  -- Maximum intoxication level
local last_drain_time = 0  -- Last drain time tracker
local drain_interval = 30  -- Time interval in seconds for draining intoxication
local stumble_timer = 0  -- Timer for stumble effect
local stumble_interval = 5.5  -- Delay between each stumble effect

-- Ensure `effects.lua` is properly loaded
local effects = dofile(minetest.get_modpath("hbdrunk") .. "/effects.lua")

-- Log message for debugging
minetest.log("action", "hbdrunk: init.lua loaded")

-- Load the drinks configuration
local drinks = dofile(minetest.get_modpath("hbdrunk") .. "/drinks.lua")

-- Load the commands file
dofile(minetest.get_modpath("hbdrunk") .. "/commands.lua")

-- Register HUD bar for intoxication
hb.register_hudbar("intoxication", 0xFFFFFF, "Intoxication", 
    {
        bar = "intox_bar.png",
        icon = "intox_icon.png"
    }, 
    0, 100, false, "@1: @2%", 
    {
        order = { "label", "value" }
    }
)

-- Function to handle HUD bar visibility based on intoxication level
local function update_intoxication_hud(player, intoxication_level)
    if intoxication_level <= 0 then
        hb.hide_hudbar(player, "intoxication")
    else
        hb.unhide_hudbar(player, "intoxication")
    end
    hb.change_hudbar(player, "intoxication", intoxication_level)
end

-- Assign update_intoxication_hud to effects table
effects.update_intoxication_hud = update_intoxication_hud

-- Initialize HUD bar on player join
minetest.register_on_joinplayer(function(player)
    local current_intoxication = player:get_meta():get_int("intoxication") or 0
    hb.init_hudbar(player, "intoxication", current_intoxication, intoxication_max, true)
    update_intoxication_hud(player, current_intoxication)
    player:get_meta():set_float("next_blackout_time", 0)  -- Initialize blackout timer
    player:get_meta():set_float("wake_up_time", 0)  -- Initialize wakeup timer
    player:get_meta():set_int("in_blackout", 0)  -- Ensure blackout state is clear
end)

-- Update intoxication level when consuming items
minetest.register_on_item_eat(function(hp_change, replace_with_item, itemstack, user)
    local itemname = itemstack:get_name()
    local drink = drinks[itemname]

    if drink then
        local current_intoxication = user:get_meta():get_int("intoxication") or 0
        local new_intoxication = math.min(intoxication_max, current_intoxication + drink.intoxication_increase)
        user:get_meta():set_int("intoxication", new_intoxication)
        hb.change_hudbar(user, "intoxication", new_intoxication)
        update_intoxication_hud(user, new_intoxication)  -- Update HUD bar visibility
        effects.apply_blur_vision(user)  -- Apply blur vision effect
    end
end)

-- Process sobering up periodically
local function drain_intoxication()
    for _, player in ipairs(minetest.get_connected_players()) do
        local current_intoxication = player:get_meta():get_int("intoxication") or 0
        if current_intoxication > 0 then
            local new_intoxication = math.max(0, current_intoxication - intoxication_drain_rate)
            player:get_meta():set_int("intoxication", new_intoxication)
            hb.change_hudbar(player, "intoxication", new_intoxication)
            update_intoxication_hud(player, new_intoxication)  -- Update HUD bar visibility
            effects.apply_blur_vision(player)  -- Apply blur vision effect
        end
    end
end

-- Separate globalstep to handle stumble effects
minetest.register_globalstep(function(dtime)
    stumble_timer = stumble_timer + dtime
    if stumble_timer >= stumble_interval then
        for _, player in ipairs(minetest.get_connected_players()) do
            local intoxication_level = player:get_meta():get_int("intoxication")
            if intoxication_level >= 35 then
                effects.apply_stumble_effect(player)
            end
        end
        stumble_timer = 0  -- Reset stumble timer after processing
    end
end)

-- Register globalstep to handle blackout effects and other intoxication mechanics
minetest.register_globalstep(function(dtime)
    -- Check if any player has died and reset intoxication on death
    for _, player in ipairs(minetest.get_connected_players()) do
        local hp = player:get_hp()
        if hp <= 0 then
            effects.reset_intoxication_on_death(player)
        end
    end

    -- Process intoxication updates and blackout effects
    last_drain_time = (last_drain_time or 0) + dtime

    if last_drain_time >= drain_interval then
        drain_intoxication()
        last_drain_time = 0  -- Reset last drain time after processing
    end

    for _, player in ipairs(minetest.get_connected_players()) do
        local intoxication_level = player:get_meta():get_int("intoxication")
        local current_time = minetest.get_gametime()
        local in_blackout = player:get_meta():get_int("in_blackout")
        local next_blackout_time = player:get_meta():get_float("next_blackout_time")
        local wake_up_time = player:get_meta():get_float("wake_up_time")

        -- Handle blackout effects based on intoxication level
        if intoxication_level >= 65 and in_blackout == 0 and current_time >= next_blackout_time then
            local blackout_duration = 10  -- Time in seconds to stay blacked out (adjust as needed)
            effects.apply_blackout_effect(player, blackout_duration)
            player:get_meta():set_float("wake_up_time", current_time + blackout_duration)
            player:get_meta():set_int("in_blackout", 1)

            -- Display blackout.png and blackout message
            if not player:get_meta():get_int("blackout_message_sent") then
                minetest.chat_send_player(player:get_player_name(), "You are too intoxicated to move!")
                player:get_meta():set_int("blackout_message_sent", 1)

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
            end

            -- Add intoxicated_vignette.png
            local vignette_hud_id = player:get_meta():get_int("vignette_hud_id")
            if vignette_hud_id == 0 then
                vignette_hud_id = player:hud_add({
                    hud_elem_type = "image",
                    position = { x = 0.5, y = 0.5 },
                    scale = { x = -100, y = -100 },
                    text = "intoxicated_vignette.png",
                    alignment = { x = 0, y = 0 },
                    offset = { x = 0, y = 0 },
                })
                player:get_meta():set_int("vignette_hud_id", vignette_hud_id)
            end
        elseif intoxication_level < 45 and in_blackout == 1 then
            if current_time >= wake_up_time then
                -- Remove blackout effects and message
                effects.wake_up_from_blackout(player)
                player:get_meta():set_int("in_blackout", 0)
                player:get_meta():set_float("next_blackout_time", current_time + 120)  -- Set next blackout time after wake-up
                player:get_meta():set_int("blackout_message_sent", 0)  -- Reset blackout message flag

                -- Remove blackout HUD element
                local hud_id = player:get_meta():get_int("blackout_hud_id")
                if hud_id ~= 0 then
                    player:hud_remove(hud_id)
                    player:get_meta():set_int("blackout_hud_id", 0)  -- Reset HUD ID
                end

                -- Remove intoxicated_vignette.png
                local vignette_hud_id = player:get_meta():get_int("vignette_hud_id")
                if vignette_hud_id ~= 0 then
                    player:hud_remove(vignette_hud_id)
                    player:get_meta():set_int("vignette_hud_id", 0)  -- Reset HUD ID
                end
            end
        end

        -- Remove intoxicated_vignette.png when intoxication level is 0
        if intoxication_level == 0 then
            local vignette_hud_id = player:get_meta():get_int("vignette_hud_id")
            if vignette_hud_id ~= 0 then
                player:hud_remove(vignette_hud_id)
                player:get_meta():set_int("vignette_hud_id", 0)  -- Reset HUD ID
            end
        end

        -- Check for alcohol poisoning and update intoxication levels
        if intoxication_level >= 100 then
            player:set_hp(0)  -- Kill the player
            effects.reset_intoxication_on_death(player)  -- Reset intoxication on death
        end
    end
end)

-- Intercept chat messages to apply speech slurring effect
minetest.register_on_chat_message(function(name, message)
    local player = minetest.get_player_by_name(name)
    if not player then
        return false
    end

    local intoxication_level = player:get_meta():get_int("intoxication")

    -- Apply slurred speech effect if intoxication level is >= 25
    if intoxication_level >= 25 then
        local jumbled_message = effects.jumble_text(message)
        minetest.chat_send_all(string.format("%s says: %s", name, jumbled_message))
        return true  -- Prevent the original message from being sent
    end

    return false  -- Let the original message go through unchanged
end)

