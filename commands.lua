-- commands.lua

local function update_intoxication_hud(player, intoxication_level)
    if intoxication_level <= 0 then
        hb.hide_hudbar(player, "intoxication")
    else
        hb.unhide_hudbar(player, "intoxication")
    end
    hb.change_hudbar(player, "intoxication", intoxication_level)
end

-- Register /drunk command
minetest.register_chatcommand("drunk", {
    params = "<playername> <intoxication_level>",
    description = "Set or check a player's intoxication level.",
    privs = { drunk = true },  -- Require drunk privilege
    func = function(name, param)
        local target_player_name, intox_level_str = param:match("(%S+)%s*(.*)")
        if not target_player_name then
            return false, "Usage: /drunk <playername> <intoxication_level>"
        end

        local target_player = minetest.get_player_by_name(target_player_name)
        if not target_player then
            return false, "Player not found or not online."
        end

        local current_intoxication = target_player:get_meta():get_int("intoxication") or 0
        if intox_level_str and intox_level_str ~= "" then
            local new_intoxication = tonumber(intox_level_str)
            if not new_intoxication then
                return false, "Invalid intoxication level."
            end
            target_player:get_meta():set_int("intoxication", new_intoxication)
            update_intoxication_hud(target_player, new_intoxication)
            return true, string.format("Set %s's intoxication level to %d.", target_player_name, new_intoxication)
        else
            return true, string.format("%s's current intoxication level is %d.", target_player_name, current_intoxication)
        end
    end,
})

return {
    update_intoxication_hud = update_intoxication_hud
}
