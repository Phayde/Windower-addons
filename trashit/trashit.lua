--[[
================================================================================
  Trash It (trashit) - Auto-Discard Addon for Windower 4
================================================================================
  Author: Phayde
  Version: 1.0.0

  Automatically discards newly acquired items while active. Designed for Mog
  Gardening: activate before collecting crops, deactivate when done. A
  prominent on-screen display warns you whenever the addon is active so you
  never accidentally trash something valuable.

  SAFETY DESIGN:
    - An inventory snapshot is taken the moment you activate the addon.
    - Only items that appear AFTER activation are eligible for discard.
    - If you already own any quantity of an item when you activate, that item
      will NEVER be touched, even if you pick up another one.
    - Drops are always quantity 1, never the full stack.
    - A whitelist lets you protect additional items you want to keep.

  SETUP:
    1. Place trashit.lua in: Windower/addons/trashit/
    2. Load with: //lua load trashit
    3. //trash on  (then do your gardening)
    4. //trash off

  COMMANDS:
    //trash on              - Activate: begin discarding new items
    //trash off             - Deactivate: stop discarding
    //trash                 - Toggle on/off
    //trash keep <item>     - Add item to whitelist (exact name, case-insensitive)
    //trash remove <item>   - Remove item from whitelist
    //trash list            - Show current whitelist
    //trash status          - Show current state and snapshot summary
    //trash debug           - Toggle debug output on/off
    //trash help            - Show this help text

  CONFIGURATION (settings.xml):
    whitelist               - Comma-separated item names to always keep
================================================================================
]]

_addon.name     = 'trashit'
_addon.author   = 'Phayde'
_addon.version  = '1.0.0'
_addon.commands = {'trashit', 'trash'}

require('logger')
local config    = require('config')
local texts     = require('texts')
local res_items = require('resources').items

-- ============================================================================
--  DEFAULT CONFIGURATION
-- ============================================================================

local defaults = {
    -- Comma-separated list of item names to always keep, even when active.
    -- Names are case-insensitive. Exact match only, no partial matching.
    whitelist = '',
}

settings = config.load(defaults)

-- ============================================================================
--  STATE
-- ============================================================================

local active    = false   -- is Trash It currently discarding items?
local debug_mode = false  -- print debug output to chat when true

-- Inventory snapshot: { [item_name_lowercase] = count }
-- Populated when the addon is activated. Any item with a count > 0 here
-- is considered pre-existing and will never be touched.
local snapshot  = {}

-- Parsed whitelist: { [item_name_lowercase] = true }
local whitelist = {}

-- ============================================================================
--  HUD (on-screen display)
-- ============================================================================

local HUD_X = 810   -- horizontal position (pixels from left edge)
local HUD_Y = 12    -- vertical position (pixels from top edge)
-- For non-1920x1080 resolutions: HUD_X = math.floor(screen_width / 2) - 140

local hud = texts.new({
    text = {
        font   = 'Arial',
        size   = 13,
        bold   = true,
        italic = false,
    },
    pos = {
        x = HUD_X,
        y = HUD_Y,
    },
    bg = {
        alpha   = 210,
        red     = 120,
        green   = 0,
        blue    = 0,
        visible = true,
    },
    padding = 6,
    flags = {
        draggable = false,
    },
})

local function hud_show_active()
    hud:text('  !  TRASH IT: ACTIVE  !  New items will be DISCARDED  !  ')
    hud:color(255, 80, 80)
    hud:show()
end

local function hud_hide()
    hud:hide()
end

-- ============================================================================
--  UTILITY FUNCTIONS
-- ============================================================================

local function cprint(color, msg)
    windower.add_to_chat(color, '[TrashIt] ' .. tostring(msg))
end

local COLOR = {
    info    = 207,  -- white/light
    success = 158,  -- green
    warn    = 167,  -- orange/yellow
    header  = 200,  -- bright white
    notice  = 036,  -- sky blue, used for debug output
}

local function dlog(msg)
    if debug_mode then
        cprint(COLOR.notice, '[DEBUG] ' .. tostring(msg))
    end
end

local function parse_whitelist()
    local t = {}
    local raw = settings.whitelist
    if type(raw) == 'string' and raw ~= '' then
        for item in raw:gmatch('[^,]+') do
            local name = item:match('^%s*(.-)%s*$'):lower()
            if name ~= '' then
                t[name] = true
            end
        end
    end
    return t
end

local function save_whitelist()
    local parts = {}
    for name in pairs(whitelist) do
        parts[#parts + 1] = name
    end
    table.sort(parts)
    settings.whitelist = table.concat(parts, ', ')
    config.save(settings)
end

-- ============================================================================
--  INVENTORY SNAPSHOT
-- ============================================================================

local function take_snapshot()
    snapshot = {}
    local inventory = windower.ffxi.get_items(0)
    for _, item in ipairs(inventory) do
        if type(item) == 'table' and item.id and item.id ~= 0 then
            local res = res_items[item.id]
            if res then
                local name_lower = res.name:lower()
                snapshot[name_lower] = (snapshot[name_lower] or 0) + (item.count or 1)
            end
        end
    end
end

-- ============================================================================
--  ITEM DROP LOGIC
-- ============================================================================

local function try_drop_one(item_name)
    local name_lower   = item_name:lower()
    local pre_existing = snapshot[name_lower] or 0
    local inventory    = windower.ffxi.get_items(0)

    dlog(('try_drop_one: "%s" | snapshot count=%d'):format(item_name, pre_existing))

    for index, item in pairs(inventory) do
        if type(index) == 'number' and type(item) == 'table'
        and item.id and item.id ~= 0 and item.status == 0 then
            local res = res_items[item.id]
            if res and res.name:lower() == name_lower then
                local current_count = item.count or 1
                dlog(('  slot %d: count=%d vs snapshot=%d'):format(index, current_count, pre_existing))
                if current_count > pre_existing then
                    dlog(('  -> dropping 1x "%s" from slot %d'):format(item_name, index))
                    windower.ffxi.drop_item(index, 1)
                    return
                else
                    dlog(('  -> count not > snapshot, skipping slot %d'):format(index))
                end
            end
        end
    end
    dlog(('try_drop_one: no eligible slot found for "%s" - item kept.'):format(item_name))
end

-- ============================================================================
--  ACTIVATION / DEACTIVATION
-- ============================================================================

local function activate()
    if active then
        cprint(COLOR.warn, 'Already active.')
        return
    end
    take_snapshot()
    active = true
    hud_show_active()
    local count = 0
    for _ in pairs(snapshot) do count = count + 1 end
    cprint(COLOR.warn, ('ACTIVE. Snapshot taken: %d unique item types on record. New items will be discarded.'):format(count))
    cprint(COLOR.warn, 'Use //trash off to deactivate.')
end

local function deactivate()
    if not active then
        cprint(COLOR.info, 'Already inactive.')
        return
    end
    active   = false
    snapshot = {}
    hud_hide()
    cprint(COLOR.success, 'Deactivated. Items will no longer be discarded.')
end

-- ============================================================================
--  INCOMING TEXT EVENT (item detection)
-- ============================================================================
--
-- FFXI prints "Obtained: <Item Name>." whenever an item lands in inventory.
-- The chat mode varies by acquisition method; the text pattern is the only gate.
-- Debug mode will print the mode in case there are issues to track down
-- number of every match so you can confirm all acquisition types are caught.

windower.register_event('incoming text', function(original, modified, original_mode)
    if not active then return end

    -- Strip embedded color/escape bytes before pattern matching
    local clean = original:gsub('%c', '')
    local item_name = clean:match('[Oo]btained:%s+(.-)%s*%.')
    if not item_name or item_name == '' then return end

    -- DEBUG: always print matches when debug mode is on
    dlog(('Obtained match | mode=%d | item="%s"'):format(original_mode, item_name))

    local name_lower = item_name:lower()

    -- Whitelist check: keep this item if the player added it
    if whitelist[name_lower] then
        dlog(('"%s" is whitelisted - keeping.'):format(item_name))
        return
    end

    -- Safety check: if the player already had ANY of this item before
    -- activation, leave it alone entirely. The per-slot count comparison
    -- happens inside try_drop_one after the auto-sorter delay.
    if snapshot[name_lower] and snapshot[name_lower] > 0 then
        dlog(('"%s" was in snapshot (count=%d) - skipping.'):format(item_name, snapshot[name_lower]))
        return
    end

    dlog(('Scheduling drop of "%s" in 0.5s...'):format(item_name))

    -- Give the auto-sorter a moment to move the item to its final slot
    coroutine.schedule(function()
        try_drop_one(item_name)
    end, 0.5)
end)

-- ============================================================================
--  COMMANDS
-- ============================================================================

windower.register_event('addon command', function(cmd, ...)
    local args = {...}
    cmd = cmd and cmd:lower() or ''

    if cmd == '' or cmd == 'toggle' then
        if active then deactivate() else activate() end

    elseif cmd == 'on' then
        activate()

    elseif cmd == 'off' then
        deactivate()

    elseif cmd == 'debug' then
        debug_mode = not debug_mode
        if debug_mode then
            cprint(COLOR.notice, 'Debug mode ON. Verbose output enabled.')
        else
            cprint(COLOR.info, 'Debug mode OFF.')
        end

    elseif cmd == 'keep' then
        if #args == 0 then
            cprint(COLOR.warn, 'Usage: //trash keep <item name>')
            return
        end
        local item_name  = table.concat(args, ' ')
        local name_lower = item_name:lower()
        if whitelist[name_lower] then
            cprint(COLOR.info, ('"' .. item_name .. '" is already on the whitelist.'))
        else
            whitelist[name_lower] = true
            save_whitelist()
            cprint(COLOR.success, ('"' .. item_name .. '" added to whitelist. It will be kept if obtained.'))
        end

    elseif cmd == 'remove' then
        if #args == 0 then
            cprint(COLOR.warn, 'Usage: //trash remove <item name>')
            return
        end
        local item_name  = table.concat(args, ' ')
        local name_lower = item_name:lower()
        if not whitelist[name_lower] then
            cprint(COLOR.warn, ('"' .. item_name .. '" is not on the whitelist.'))
        else
            whitelist[name_lower] = nil
            save_whitelist()
            cprint(COLOR.success, ('"' .. item_name .. '" removed from whitelist.'))
        end

    elseif cmd == 'list' then
        local items = {}
        for name in pairs(whitelist) do
            items[#items + 1] = name
        end
        table.sort(items)
        if #items == 0 then
            cprint(COLOR.info, 'Whitelist is empty. All new items will be discarded when active.')
        else
            cprint(COLOR.header, '--- Whitelist (' .. #items .. ' items) ---')
            for _, name in ipairs(items) do
                windower.add_to_chat(COLOR.info, '  ' .. name)
            end
        end

    elseif cmd == 'status' then
        if active then
            local snap_count = 0
            for _ in pairs(snapshot) do snap_count = snap_count + 1 end
            cprint(COLOR.warn, ('ACTIVE | Snapshot: %d unique item types on record.'):format(snap_count))
        else
            cprint(COLOR.info, 'Inactive. Use //trash on to activate.')
        end
        local wl_count = 0
        for _ in pairs(whitelist) do wl_count = wl_count + 1 end
        cprint(COLOR.info, ('Whitelist: %d item(s). Use //trash list to view.'):format(wl_count))
        cprint(COLOR.info, ('Debug mode: %s'):format(debug_mode and 'ON' or 'OFF'))

    elseif cmd == 'help' then
        cprint(COLOR.header, '--- Trash It v' .. _addon.version .. ' ---')
        windower.add_to_chat(COLOR.info, '  //trash on              - Activate and begin discarding new items')
        windower.add_to_chat(COLOR.info, '  //trash off             - Deactivate: stop discarding items')
        windower.add_to_chat(COLOR.info, '  //trash                 - Toggle on/off')
        windower.add_to_chat(COLOR.info, '  //trash keep <item>     - Add item to whitelist (exact name)')
        windower.add_to_chat(COLOR.info, '  //trash remove <item>   - Remove item from whitelist')
        windower.add_to_chat(COLOR.info, '  //trash list            - Show whitelist')
        windower.add_to_chat(COLOR.info, '  //trash status          - Show current state and snapshot info')
        windower.add_to_chat(COLOR.info, '  //trash debug           - Toggle verbose debug output')
        windower.add_to_chat(COLOR.info, '  //trash help            - Show this help text')
        windower.add_to_chat(COLOR.info, 'SAFETY: Items already in inventory at activation are never touched.')
        windower.add_to_chat(COLOR.info, 'Only 1 unit is ever dropped per obtained message, never a full stack.')

    else
        cprint(COLOR.warn, 'Unknown command "' .. cmd .. '". Use //trash help.')
    end
end)

-- ============================================================================
--  LOAD / UNLOAD
-- ============================================================================

windower.register_event('load', function()
    whitelist = parse_whitelist()
    hud_hide()
    local wl_count = 0
    for _ in pairs(whitelist) do wl_count = wl_count + 1 end
    cprint(COLOR.info, ('v%s loaded. Whitelist: %d item(s). Use //trash on to activate.'):format(
        _addon.version, wl_count))
end)

windower.register_event('unload', function()
    if active then
        active = false
        hud_hide()
    end
end)

windower.register_event('logout', function()
    if active then
        active   = false
        snapshot = {}
        hud_hide()
        cprint(COLOR.warn, 'Deactivated on logout.')
    end
end)
