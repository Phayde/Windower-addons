--[[
================================================================================
  Trash It (trashit) - Auto-Discard Addon for Windower 4
================================================================================
  Author: Phayde
  Version: 2.1.0

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
      any item whose name contains that phrase (case-insensitive substring).

  SETUP:
    1. Place trashit.lua in: Windower/addons/trashit/
    2. Load with: //lua load trashit
    3. //trash on  (then do your gardening, farming, or fishing)
    4. //trash off

  COMMANDS:
    //trash on              - Activate: begin discarding new items
    //trash off             - Deactivate: stop discarding
    //trash                 - Toggle on/off
    //trash keep <term>     - Add term to whitelist (case-insensitive substring)
    //trash remove <term>   - Remove term from whitelist
    //trash list            - Show current whitelist
    //trash toss <term>     - Session-only: discard new slots of this item even if already owned
    //trash toss            - Show toss list
    //trash untoss <term>   - Remove term from toss list
    //trash status          - Show current state and snapshot summary
    //trash help            - Show this help text

  CONFIGURATION (settings.xml):
    whitelist               - Comma-separated terms to always keep
    tosslist                - not saved; session-only via //trash toss
================================================================================
]]

_addon.name     = 'trashit'
_addon.author   = 'Phayde'
_addon.version  = '2.0.0'
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
    -- Matching is case-insensitive substring: "mythril ore" protects
    -- "Chunk of mythril ore", "Lump of mythril ore", etc.
    whitelist = '',
}

settings = config.load(defaults)

-- ============================================================================
--  STATE
-- ============================================================================

local active    = false   -- is Trash It currently discarding items?

-- Inventory snapshot: { [item_name_lowercase] = count }
-- Populated when the addon is activated. Any item with a count > 0 here
-- is considered pre-existing and will never be touched.
local snapshot  = {}

-- Parsed whitelist: { [term_lowercase] = true }
local whitelist = {}

-- Toss list: { [term_lowercase] = true }
-- Session-only (not saved to settings.xml). Items matching a toss term are
-- non-stackable items where any slot NOT recorded in the snapshot is dropped.
-- Pre-existing slots recorded at activation are always protected.
local tosslist = {}

-- True when a sweep coroutine is already scheduled and waiting to fire.
-- Prevents stacking multiple redundant sweeps when several item messages
-- arrive within the same 0.5s window.
local sweep_scheduled = false

-- Cached player name, set on load and on activation.
-- Used to match mob-drop and fishing messages: "<Player> obtains/caught a/an <item>."
local player_name = nil

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
}

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

-- Returns true if item_name (lowercase) contains any whitelist term
-- as a substring. "mythril ore" will match "chunk of mythril ore", etc.
local function is_whitelisted(name_lower)
    for term in pairs(whitelist) do
        if name_lower:find(term, 1, true) then
            return true
        end
    end
    return false
end

-- Returns true if item_name (lowercase) contains any toss list term.
-- Toss overrides whitelist if a term matches both.
local function is_tossed(name_lower)
    for term in pairs(tosslist) do
        if name_lower:find(term, 1, true) then
            return true
        end
    end
    return false
end

-- ============================================================================
--  INVENTORY SNAPSHOT
-- ============================================================================

-- snapshot structure:
--   snapshot[name_lower].count = total units owned at activation
--   snapshot[name_lower].slots = { [slot_index] = true } for toss list items
--     so we can identify which slots are pre-existing vs newly acquired.
local function take_snapshot()
    snapshot = {}
    local inventory = windower.ffxi.get_items(0)
    for index, item in pairs(inventory) do
        if type(index) == 'number' and type(item) == 'table'
        and item.id and item.id ~= 0 then
            local res = res_items[item.id]
            if res then
                local name_lower = res.name:lower()
                if not snapshot[name_lower] then
                    snapshot[name_lower] = { count = 0, slots = {} }
                end
                snapshot[name_lower].count = snapshot[name_lower].count + (item.count or 1)
                snapshot[name_lower].slots[index] = true
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
local function sweep_and_drop(verbose)
    sweep_scheduled = false
    local inventory = windower.ffxi.get_items(0)

    for index, item in pairs(inventory) do
        if type(index) == 'number' and type(item) == 'table'
        and item.id and item.id ~= 0 and item.status == 0 then
            local res = res_items[item.id]
            if res then
                local name_lower  = res.name:lower()
                local snap        = snapshot[name_lower]
                local pre_count   = snap and snap.count or 0
                local cur_count   = item.count or 1
                local tossed      = is_tossed(name_lower)
                local listed      = is_whitelisted(name_lower)

                if tossed then
                    -- Toss list logic: slot-based for non-stackable items.
                    -- If this slot index was NOT present at activation, it is
                    -- a newly acquired item - drop the whole slot.
                    local slot_is_new = not (snap and snap.slots[index])
                    if verbose then
                        cprint(COLOR.info, ('slot %d: "%s" tossed=true slot_is_new=%s'):format(
                            index, res.name, tostring(slot_is_new)))
                    end
                    if slot_is_new then
                        if verbose then
                            cprint(COLOR.success, ('  -> dropping tossed item "%s" from slot %d'):format(res.name, index))
                        end
                        windower.ffxi.drop_item(index, cur_count)
                    end
                else
                    -- Standard logic: drop units that exceed the snapshot count.
                    local to_drop = math.max(cur_count - pre_count, 0)
                    if verbose then
                        cprint(COLOR.info, ('slot %d: "%s" count=%d snap=%d to_drop=%d whitelisted=%s'):format(
                            index, res.name, cur_count, pre_count, to_drop, tostring(listed)))
                    end
                    if to_drop > 0 and not listed then
                        if verbose then
                            cprint(COLOR.success, ('  -> dropping %d of "%s" from slot %d'):format(to_drop, res.name, index))
                        end
                        windower.ffxi.drop_item(index, to_drop)
                    end
                end
            end
        end
    end
    if verbose then cprint(COLOR.info, 'Sweep complete.') end
end

-- ============================================================================
--  ACTIVATION / DEACTIVATION
-- ============================================================================

local function activate()
    if active then
        cprint(COLOR.warn, 'Already active.')
        return
    end
    if not player_name then
        local player = windower.ffxi.get_player()
        player_name = player and player.name or nil
    end
    take_snapshot()
    active = true
    hud_show_active()
    local count = 0
    for _ in pairs(snapshot) do count = count + 1 end
    -- Refresh toss list slot records now that snapshot is taken
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
-- FFXI uses distinct message formats depending on how an item is acquired:
--
--   Gardening / digging:   "Obtained: <Item Name>."
--   Mob / chest drops:     "<Player> obtains a/an <Item Name>."
--   Fishing:               "<Player> caught a/an <Item Name>!"
--
-- We match all three patterns. The player name is fetched once at activation
-- and cached so we don't call get_player() on every incoming line.

windower.register_event('incoming text', function(original, modified, original_mode)
    if not active then return end

    -- Strip embedded color/escape bytes before pattern matching
    local clean = original:gsub('%c', '')
    local item_name =
        -- Pattern 1: gardening, digging, etc. - "Obtained: <item>."
        clean:match('[Oo]btained:%s+(.-)%s*%.') or
        -- Pattern 2: mob drops - "<Player> obtains a/an <item>."
        -- Match against the cached player name so we don't react to party
        -- members' drops appearing in your log.
        (player_name and clean:match(player_name .. ' obtains an?%s+(.-)%s*%.')) or
        -- Pattern 3: fishing - "<Player> caught a/an <item>!"
        (player_name and clean:match(player_name .. ' caught an?%s+(.-)%s*!'))

    if not item_name or item_name == '' then return end

    -- Whitelist check: skip sweep if this item is protected and not on the
    -- toss list. Toss overrides whitelist, so a tossed item always triggers
    -- a sweep even if it also matches a whitelist term.
    local name_lower = item_name:lower()
    if is_whitelisted(name_lower) and not is_tossed(name_lower) then return end

    -- Schedule a sweep if one is not already pending. Any additional item
    -- messages that arrive within the 0.5s window are covered automatically
    -- when the single sweep fires and checks the whole inventory at once.
    if not sweep_scheduled then
        sweep_scheduled = true
        coroutine.schedule(function()
            sweep_and_drop()
        end, 0.5)
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
        -- Run an immediate verbose sweep to inspect inventory state
        if not active then
            cprint(COLOR.warn, 'Trash It is not active - activate first with //trash on.')
        else
            cprint(COLOR.info, 'Running debug sweep...')
            sweep_and_drop(true)
        end

    elseif cmd == 'keep' then
        if #args == 0 then
            cprint(COLOR.warn, 'Usage: //trash keep <term>')
            return
        end
        local term = table.concat(args, ' '):lower()
        if whitelist[term] then
            cprint(COLOR.info, ('"' .. term .. '" is already on the whitelist.'))
        else
            whitelist[term] = true
            save_whitelist()
            cprint(COLOR.success, ('"' .. term .. '" added to whitelist.'))
        end

    elseif cmd == 'remove' then
        if #args == 0 then
            cprint(COLOR.warn, 'Usage: //trash remove <term>')
            return
        end
        local term = table.concat(args, ' '):lower()
        if not whitelist[term] then
            cprint(COLOR.warn, ('"' .. term .. '" is not on the whitelist.'))
        else
            whitelist[term] = nil
            save_whitelist()
            cprint(COLOR.success, ('"' .. term .. '" removed from whitelist.'))
        end

    elseif cmd == 'toss' then
        if #args == 0 then
            -- //trash toss with no args shows the toss list
            local items = {}
            for name in pairs(tosslist) do
                items[#items + 1] = name
            end
            table.sort(items)
            if #items == 0 then
                cprint(COLOR.info, 'Toss list is empty.')
            else
                cprint(COLOR.header, '--- Toss list (' .. #items .. ' items) ---')
                for _, name in ipairs(items) do
                    windower.add_to_chat(COLOR.info, '  ' .. name)
                end
            end
            return
        end
        local term = table.concat(args, ' '):lower()
        if tosslist[term] then
            cprint(COLOR.info, ('"' .. term .. '" is already on the toss list.'))
        else
            tosslist[term] = true
            cprint(COLOR.success, ('"' .. term .. '" added to toss list (session only). New slots of this item will be discarded.'))
        end

    elseif cmd == 'untoss' then
        if #args == 0 then
            cprint(COLOR.warn, 'Usage: //trash untoss <term>')
            return
        end
        local term = table.concat(args, ' '):lower()
        if not tosslist[term] then
            cprint(COLOR.warn, ('"' .. term .. '" is not on the toss list.'))
        else
            tosslist[term] = nil
            cprint(COLOR.success, ('"' .. term .. '" removed from toss list.'))
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
        local tl_count = 0
        for _ in pairs(tosslist) do tl_count = tl_count + 1 end
        cprint(COLOR.info, ('Toss list: %d item(s) (session only). Use //trash toss to view.'):format(tl_count))

    elseif cmd == 'help' then
        cprint(COLOR.header, '--- Trash It v' .. _addon.version .. ' ---')
        windower.add_to_chat(COLOR.info, '  //trash on              - Activate and begin discarding new items')
        windower.add_to_chat(COLOR.info, '  //trash off             - Deactivate: stop discarding items')
        windower.add_to_chat(COLOR.info, '  //trash                 - Toggle on/off')
        windower.add_to_chat(COLOR.info, '  //trash keep <term>     - Add term to whitelist (substring, case-insensitive)')
        windower.add_to_chat(COLOR.info, '  //trash remove <term>   - Remove term from whitelist')
        windower.add_to_chat(COLOR.info, '  //trash list            - Show whitelist')
        windower.add_to_chat(COLOR.info, '  //trash toss <term>     - Session: discard new slots of item even if already owned')
        windower.add_to_chat(COLOR.info, '  //trash toss            - Show toss list')
        windower.add_to_chat(COLOR.info, '  //trash untoss <term>   - Remove term from toss list')
        windower.add_to_chat(COLOR.info, '  //trash status          - Show current state and snapshot info')
        windower.add_to_chat(COLOR.info, '  //trash debug           - Run a verbose inventory sweep for troubleshooting')
        windower.add_to_chat(COLOR.info, '  //trash help            - Show this help text')
        windower.add_to_chat(COLOR.info, 'SAFETY: Items already in inventory at activation are never touched.')
        windower.add_to_chat(COLOR.info, 'Only newly acquired units are dropped - pre-existing stacks are never touched.')
        windower.add_to_chat(COLOR.info, 'Toss list (session only) overrides this for non-stackable items by slot.')

    else
        cprint(COLOR.warn, 'Unknown command "' .. cmd .. '". Use //trash help.')
    end
end)

-- ============================================================================
--  LOAD / UNLOAD
-- ============================================================================

windower.register_event('load', function()
    whitelist = parse_whitelist()
    tosslist  = {}
    hud_hide()
    local player = windower.ffxi.get_player()
    player_name = player and player.name or nil
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
