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
      will NEVER be touched - even if you pick up another one.
    - Drops only the exact number of units that exceed your pre-activation count.
    - A whitelist lets you protect items by keyword: "mythril ore" protects
      any item whose name contains that phrase.

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
    -- Comma-separated list of terms to always keep, even when active.
    -- Matching is case-insensitive substring: "bayld" protects
    -- "Pinch of High-Purity Bayld", etc.
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

-- True when a sweep coroutine is already scheduled and waiting to fire.
-- Prevents stacking multiple redundant sweeps when several "Obtained"
-- messages arrive within the same 0.5s window.
local sweep_scheduled = false

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

-- Returns true if item_name (lowercase) contains any whitelist entry
-- as a substring. "mythril ore" will match "chunk of mythril ore", etc.
local function is_whitelisted(name_lower)
    for term in pairs(whitelist) do
        if name_lower:find(term, 1, true) then
            return true
        end
    end
    return false
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

-- Walks every slot in main inventory and drops any units of any item that
-- exceed the snapshot baseline, subject to whitelist protection.
-- Called via a 0.5s delayed coroutine so the auto-sorter has time to settle
-- before we scan. Because it checks the whole inventory in one pass, it
-- catches all new items regardless of how many arrived simultaneously.
local function sweep_and_drop()
    sweep_scheduled = false
    local inventory = windower.ffxi.get_items(0)
    dlog('Sweep firing...')

    for index, item in pairs(inventory) do
        if type(index) == 'number' and type(item) == 'table'
        and item.id and item.id ~= 0 and item.status == 0 then
            local res = res_items[item.id]
            if res then
                local name_lower    = res.name:lower()
                local pre_existing  = snapshot[name_lower] or 0
                local current_count = item.count or 1
                local to_drop       = math.max(current_count - pre_existing, 0)

                -- Skip if nothing new in this slot
                if to_drop > 0 then
                    -- Whitelist check - never drop protected items
                    if is_whitelisted(name_lower) then
                        dlog(('  slot %d: "%s" +%d new but whitelisted - keeping.'):format(
                            index, res.name, to_drop))
                    else
                        dlog(('  slot %d: "%s" current=%d snapshot=%d - dropping %d'):format(
                            index, res.name, current_count, pre_existing, to_drop))
                        windower.ffxi.drop_item(index, to_drop)
                    end
                end
            end
        end
    end
    dlog('Sweep complete.')
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
    active          = false
    snapshot        = {}
    sweep_scheduled = false
    hud_hide()
    cprint(COLOR.success, 'Deactivated. Items will no longer be discarded.')
end

-- ============================================================================
--  INCOMING TEXT EVENT (item detection)
-- ============================================================================
--
-- FFXI prints "Obtained: <Item Name>." whenever an item lands in inventory.
-- The chat mode varies by acquisition method - mode 4 for digging, but
-- gardening and fishing may use a different mode number. We no longer filter
-- by mode; the text pattern is the only gate. Debug mode will print the mode
-- number of every match so you can confirm all acquisition types are caught.

windower.register_event('incoming text', function(original, modified, original_mode)
    if not active then return end

    -- Strip embedded color/escape bytes before pattern matching
    local clean = original:gsub('%c', '')
    local item_name = clean:match('[Oo]btained:%s+(.-)%s*%.')
    if not item_name or item_name == '' then return end

    -- DEBUG: always print matches when debug mode is on
    dlog(('Obtained match | mode=%d | item="%s"'):format(original_mode, item_name))

    -- Whitelist check: if this item is protected, no sweep needed unless
    -- other non-whitelisted items also arrived in the same batch.
    -- The sweep itself also enforces the whitelist, but skipping here avoids
    -- scheduling a sweep that would do nothing when only kept items are obtained.
    if is_whitelisted(item_name:lower()) then
        dlog(('"%s" is whitelisted - keeping.'):format(item_name))
        return
    end

    -- Schedule a sweep if one is not already pending. Any additional "Obtained"
    -- messages that arrive within the 0.5s window are covered automatically
    -- when the single sweep fires and checks the whole inventory at once.
    if not sweep_scheduled then
        sweep_scheduled = true
        dlog('Sweep scheduled in 0.5s...')
        coroutine.schedule(function()
            sweep_and_drop()
        end, 0.5)
    else
        dlog('Sweep already pending - no new coroutine needed.')
    end
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
        windower.add_to_chat(COLOR.info, '  //trash keep <term>     - Add term to whitelist (substring match, case-insensitive)')
        windower.add_to_chat(COLOR.info, '  //trash remove <item>   - Remove item from whitelist')
        windower.add_to_chat(COLOR.info, '  //trash list            - Show whitelist')
        windower.add_to_chat(COLOR.info, '  //trash status          - Show current state and snapshot info')
        windower.add_to_chat(COLOR.info, '  //trash debug           - Toggle verbose debug output')
        windower.add_to_chat(COLOR.info, '  //trash help            - Show this help text')
        windower.add_to_chat(COLOR.info, 'SAFETY: Items already in inventory at activation are never touched.')
        windower.add_to_chat(COLOR.info, 'Only newly acquired units are dropped - pre-existing stacks are never touched.')

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
