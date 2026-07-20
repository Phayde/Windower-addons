_addon.name = 'Medicine Cabinet'
_addon.version = '2.10'
_addon.author = 'Phayde'
_addon.command = 'med'

require('tables')
require('strings')
require('logger')
require('sets')
config  = require('config')
res     = require('resources')
texts   = require('texts')

-- ===========================================================
--  Buff ID Reference
-- ===========================================================
local BUFF = {
    PARALYZE    = S{4, 566},
    DOOM        = S{15},
    CURSE       = S{9, 20},
    SILENCE     = S{6},
    BLINDNESS   = S{5},
    POISON      = S{3},
    SLOW        = S{13, 565},
    BIO         = S{135},
    DIA         = S{134},
    STAT_DOWN   = S{136,137,138,139,140,141,142},
    STR_DOWN    = S{136},
    DEX_DOWN    = S{137},
    VIT_DOWN    = S{138},
    AGI_DOWN    = S{139},
    INT_DOWN    = S{140},
    MND_DOWN    = S{141},
    CHR_DOWN    = S{142},
    MAX_HP_DOWN = S{144},
    MAX_MP_DOWN = S{145},
    DEF_DOWN    = S{149, 558},
    MDEF_DOWN   = S{167, 560},
    ATK_DOWN    = S{147, 557},
    ACC_DOWN    = S{146, 561},
    EVA_DOWN    = S{148, 562},
    MATK_DOWN   = S{175, 559},
    MACC_DOWN   = S{174, 563},
    COMBAT_DOWN = S{147,557,149,558,146,561,148,562},
    MAGIC_DOWN  = S{175,559,167,560,174,563},
    ADDLE       = S{21},
    FLASH       = S{156},
    HELIX       = S{186},
    BURN        = S{128},
    FROST       = S{129},
    CHOKE       = S{130},
    RASP        = S{131},
    SHOCK       = S{132},
    DROWN       = S{133},
    GRAVITY     = S{12, 567},
    BIND        = S{11},
    FOOD        = S{251},
}

-- All IDs curable by Panacea
local PANACEA_IDS = S{}
for _, s in pairs({
    BUFF.SLOW, BUFF.BIO, BUFF.DIA, BUFF.STAT_DOWN,
    BUFF.MAX_HP_DOWN, BUFF.MAX_MP_DOWN, BUFF.DEF_DOWN,
    BUFF.MDEF_DOWN, BUFF.ATK_DOWN, BUFF.ACC_DOWN,
    BUFF.EVA_DOWN, BUFF.MATK_DOWN, BUFF.MACC_DOWN,
    BUFF.ADDLE, BUFF.FLASH, BUFF.HELIX,
    BUFF.BURN, BUFF.FROST, BUFF.CHOKE,
    BUFF.RASP, BUFF.SHOCK, BUFF.DROWN, BUFF.GRAVITY, BUFF.BIND,
}) do
    for id in pairs(s) do PANACEA_IDS:add(id) end
end

-- All IDs curable by Remedy
local REMEDY_IDS = S{}
for _, s in pairs({BUFF.PARALYZE, BUFF.POISON, BUFF.BLINDNESS, BUFF.SILENCE}) do
    for id in pairs(s) do REMEDY_IDS:add(id) end
end

-- ============================================================
--  Buff Name -> ID lookup for monitor mode
-- ============================================================
local BUFF_NAME_MAP = {
    ['paralyze']    = BUFF.PARALYZE,
    ['paralysis']   = BUFF.PARALYZE,
    ['doom']        = BUFF.DOOM,
    ['curse']       = BUFF.CURSE,
    ['silence']     = BUFF.SILENCE,
    ['blind']       = BUFF.BLINDNESS,
    ['blindness']   = BUFF.BLINDNESS,
    ['poison']      = BUFF.POISON,
    ['slow']        = BUFF.SLOW,
    ['bio']         = BUFF.BIO,
    ['dia']         = BUFF.DIA,
    ['bind']        = BUFF.BIND,
    ['gravity']     = BUFF.GRAVITY,
    ['addle']       = BUFF.ADDLE,
    ['flash']       = BUFF.FLASH,
    ['helix']       = BUFF.HELIX,
    ['burn']        = BUFF.BURN,
    ['frost']       = BUFF.FROST,
    ['choke']       = BUFF.CHOKE,
    ['rasp']        = BUFF.RASP,
    ['shock']       = BUFF.SHOCK,
    ['drown']       = BUFF.DROWN,
    ['statdown']    = BUFF.STAT_DOWN,
    ['stat_down']   = BUFF.STAT_DOWN,
    ['strdown']     = BUFF.STR_DOWN,
    ['str_down']    = BUFF.STR_DOWN,
    ['dexdown']     = BUFF.DEX_DOWN,
    ['dex_down']    = BUFF.DEX_DOWN,
    ['vitdown']     = BUFF.VIT_DOWN,
    ['vit_down']    = BUFF.VIT_DOWN,
    ['agidown']     = BUFF.AGI_DOWN,
    ['agi_down']    = BUFF.AGI_DOWN,
    ['intdown']     = BUFF.INT_DOWN,
    ['int_down']    = BUFF.INT_DOWN,
    ['mnddown']     = BUFF.MND_DOWN,
    ['mnd_down']    = BUFF.MND_DOWN,
    ['chrdown']     = BUFF.CHR_DOWN,
    ['chr_down']    = BUFF.CHR_DOWN,
    ['maxhpdown']   = BUFF.MAX_HP_DOWN,
    ['maxmpdown']   = BUFF.MAX_MP_DOWN,
    ['defdown']     = BUFF.DEF_DOWN,
    ['mdefdown']    = BUFF.MDEF_DOWN,
    ['atkdown']     = BUFF.ATK_DOWN,
    ['accdown']     = BUFF.ACC_DOWN,
    ['evadown']     = BUFF.EVA_DOWN,
    ['matkdown']    = BUFF.MATK_DOWN,
    ['maccdown']    = BUFF.MACC_DOWN,
    ['macc_down']   = BUFF.MACC_DOWN,
    ['combatdown']  = BUFF.COMBAT_DOWN,
    ['combat_down'] = BUFF.COMBAT_DOWN,
    ['magicdown']   = BUFF.MAGIC_DOWN,
    ['magic_down']  = BUFF.MAGIC_DOWN,
}

-- ============================================================
--  Item Names
-- ============================================================
local ITEMS = {
    REMEDY           = 'Remedy',
    PANACEA          = 'Panacea',
    ECHO_DROPS       = 'Echo Drops',
    EYE_DROPS        = 'Eye Drops',
    ANTIDOTE         = 'Antidote',
    HOLY_WATER       = 'Holy Water',
    VILE_ELIXIR      = 'Vile Elixir',
    VILE_ELIXIR_PLUS = 'Vile Elixir +1',
    ANTACID          = 'Antacid',
    ICARUS_WING      = 'Icarus Wing',
    PACHIRA_FRUIT    = 'El. Pachira Fruit',
    PRISM_POWDER     = 'Prism Powder',
    SILENT_OIL       = 'Silent Oil',
    RERAISER         = 'Reraiser',
    HI_RERAISER      = 'Hi-Reraiser',
    SUPER_RERAISER   = 'Super Reraiser',
    INSTANT_RERAISE  = 'Scroll of Instant Reraise',
}

-- ============================================================
--  Retry Caps & Timing
-- ============================================================
local RETRY = {PARALYZE=10, DOOM=10, DEFAULT=3}
local USE_DELAY          = 3.0
local DEBOUNCE           = 0.2
local CLEAR_DISPLAY_TIME = 2.0
local AP_RETRY_DELAY     = 3.0
local AP_BUSY_POLL       = 0.5

-- ============================================================
--  Defaults & Settings
-- ============================================================
local defaults = {}
defaults.ignore   = S{'poison'}
defaults.autoscan = false
defaults.hud_x       = 10
defaults.hud_y       = 3
defaults.movement_check = false

local settings = config.load(defaults)

-- ============================================================
--  Chat Output
-- ============================================================
local COL    = {INFO=207, WARN=167, ERR=123}
local PREFIX = '[MedCab] '

local function info(text) windower.add_to_chat(COL.INFO, PREFIX..text) end
local function warn(text) windower.add_to_chat(COL.WARN, PREFIX..text) end
local function err(text)  windower.add_to_chat(COL.ERR,  PREFIX..text) end

-- ============================================================
--  Monitor Mode State (session only)
--  Declared before HUD functions which reference these.
-- ============================================================
local monitor_mode   = false
local monitor_buffs  = S{}
local monitor_labels = {}

-- ============================================================
--  Movement Detection State
-- ============================================================
local last_pos          = nil   -- {x, y, z} from last position check
local movement_waiting  = false -- true if we're currently waiting for the player to stop moving
local MOVE_THRESHOLD     = 0.05 -- minimum distance change (in-game units) to count as "moving"
local MOVE_POLL_INTERVAL = 0.5  -- how often to re-check position while waiting

local function get_player_pos()
    local mob = windower.ffxi.get_mob_by_target('me')
    if not mob then return nil end
    return {x = mob.x, y = mob.y, z = mob.z}
end

local function is_player_moving()
    if not settings.movement_check then return false end
    local pos = get_player_pos()
    if not pos then return false end
    if last_pos == nil then
        last_pos = pos
        return false  -- first check, no baseline yet
    end
    local dx = pos.x - last_pos.x
    local dy = pos.y - last_pos.y
    local dz = pos.z - last_pos.z
    local dist = math.sqrt(dx*dx + dy*dy + dz*dz)
    last_pos = pos
    return dist > MOVE_THRESHOLD
end

-- ============================================================
--  Autopoison State (session only)
--  Declared before HUD functions which reference these.
-- ============================================================
local autopoison      = false
local autopoison_busy = false
local ap_hud_state    = 'idle'  -- 'idle', 'applying', 'empty'

-- ============================================================
--  Autofood State (session only)
--  Declared before HUD functions which reference these.
-- ============================================================
local autofood          = false
local autofood_item     = nil    -- item name string set by user
local autofood_busy     = false
local autofood_gen      = 0
local af_hud_state      = 'idle' -- 'idle', 'applying', 'empty', 'notfound'

-- ============================================================
--  Inventory Helper
--  Declared before HUD functions which call it.
-- ============================================================
local function get_item_count(item_name)
    local count = 0
    for _, bag_id in ipairs({0, 3, 5, 6}) do
        local bag = windower.ffxi.get_items(bag_id)
        if bag then
            for _, item in ipairs(bag) do
                if item and item.id and item.id > 0 then
                    local resource = res.items[item.id]
                    if resource and resource.english:lower() == item_name:lower() then
                        count = count + item.count
                    end
                end
            end
        end
    end
    return count
end

-- ============================================================
--  HUD
-- ============================================================
local hud = texts.new({
    text  = {font='Arial', size=11, bold=true},
    pos   = {x=settings.hud_x, y=settings.hud_y},
    bg    = {red=0, green=0, blue=0, alpha=180},
    flags = {draggable=true},
})

local HUD_STATE = {OFF=1, IDLE=2, ACTIVE=3, CLEAR=4}

-- Builds the autopoison second line - empty string if autopoison is off
local function ap_line()
    if not autopoison then return '' end
    local count = get_item_count(ITEMS.PACHIRA_FRUIT)
    local count_str = ' | '..count..' fruit'..(count ~= 1 and 's' or '')
    if ap_hud_state == 'applying' then
        return '\n[AutoPoison] Applying poison...'..count_str
    elseif ap_hud_state == 'empty' then
        return '\n[AutoPoison] Out of fruit!'
    else
        return '\n[AutoPoison] Active'..count_str
    end
end

-- Builds the autofood third line - empty string if autofood is off
local function af_line()
    if not autofood then return '' end
    local item = autofood_item or '?'
    local count = autofood_item and get_item_count(autofood_item) or 0
    local count_str = ' | '..count..' left'
    if af_hud_state == 'applying' then
        return '\n[AutoFood] Applying '..item..'...'..count_str
    elseif af_hud_state == 'empty' then
        return '\n[AutoFood] Out of '..item..'!'
    elseif af_hud_state == 'notfound' then
        return '\n[AutoFood] Item not found: '..item
    else
        return '\n[AutoFood] Active: '..item..count_str
    end
end

local function hud_update(state, queue_items)
    local ap = ap_line()..af_line()
    if state == HUD_STATE.OFF then
        hud:text(PREFIX..'OFF'..ap)
        hud:color(128, 128, 128)
    elseif state == HUD_STATE.IDLE then
        local main
        if monitor_mode and #monitor_labels > 0 then
            if #monitor_labels <= 3 then
                main = PREFIX..'Monitoring: '..table.concat(monitor_labels, ', ')
            else
                main = PREFIX..'Monitoring: '..#monitor_labels..' ailments'
            end
        else
            local ignore_list = {}
            for k in pairs(settings.ignore) do table.insert(ignore_list, k) end
            if #ignore_list == 0 then
                main = PREFIX..'Autoscanning'
            elseif #ignore_list <= 3 then
                main = PREFIX..'Autoscanning | ignoring: '..table.concat(ignore_list, ', ')
            else
                main = PREFIX..'Autoscanning | ignoring '..#ignore_list..' ailments'
            end
        end
        hud:text(main..ap)
        if ap_hud_state == 'applying' then
            hud:color(255, 180, 0)
        elseif ap_hud_state == 'empty' then
            hud:color(255, 60, 60)
        else
            hud:color(200, 200, 200)
        end
    elseif state == HUD_STATE.ACTIVE then
        local items = queue_items or {}
        local label = table.concat(items, ' -> ')
        hud:text(PREFIX..'>> '..label..ap)
        hud:color(255, 60, 60)
    elseif state == HUD_STATE.CLEAR then
        hud:text(PREFIX..'Clear!'..ap)
        hud:color(60, 255, 60)
    end
end

local function hud_show() hud:show() end
local function hud_hide() hud:hide() end

local function hud_set_idle()
    if monitor_mode or settings.autoscan then
        hud_update(HUD_STATE.IDLE)
    else
        hud_update(HUD_STATE.OFF)
    end
end

local function save_hud_pos()
    local x, y = hud:pos()
    settings.hud_x = x
    settings.hud_y = y
    settings:save()
end

-- ============================================================
--  Remaining Helpers
-- ============================================================
local function check_item(item_name)
    local count = get_item_count(item_name)
    if count == 0 then
        warn('Out of '..item_name..'! Skipping.')
        return false, 0
    end
    if count == 1 then
        warn('Using last '..item_name..'!')
    end
    return true, count
end

local function get_active_buffs()
    local active = S{}
    for _, id in ipairs(windower.ffxi.get_player().buffs) do
        if id and id > 0 then active:add(id) end
    end
    return active
end

local function any_active(buff_set)
    local active = get_active_buffs()
    for id in pairs(buff_set) do
        if active:contains(id) then return true end
    end
    return false
end

local function is_ignored(name)
    for key in pairs(settings.ignore) do
        if key:lower() == name:lower() then return true end
    end
    return false
end

-- ============================================================
--  State Machine
-- ============================================================
local queue    = {}
local pending  = nil
local busy     = false
local no_effect_flag = false
local player_name    = nil

local use_next_in_queue
local attempt_current

local function get_queue_item_names()
    local names = {}
    if pending then table.insert(names, pending.item) end
    for _, entry in ipairs(queue) do table.insert(names, entry.item) end
    return names
end

local function finish_queue()
    busy    = false
    pending = nil
    queue   = {}
    local was_monitor  = monitor_mode
    local was_autoscan = settings.autoscan

    -- Cleanup scan: check if any new debuffs landed while the queue was running.
    -- Only applies in autoscan or monitor mode since manual mode is a single cycle.
    if was_autoscan or was_monitor then
        local source = was_monitor and 'monitor' or 'autoscan'
        local built = build_queue(was_monitor and monitor_buffs or nil)
        if built and #built > 0 then
            info('New debuffs detected after cure cycle - starting follow-up scan.')
            busy  = true
            queue = built
            hud_update(HUD_STATE.ACTIVE, (function()
                local names = {}
                for _, e in ipairs(built) do table.insert(names, e.item) end
                return names
            end)())
            use_next_in_queue()
            return
        end
    end

    hud_update(HUD_STATE.CLEAR)
    coroutine.schedule(function()
        if not busy then
            if was_monitor or was_autoscan then
                hud_update(HUD_STATE.IDLE)
            else
                hud_update(HUD_STATE.OFF)
            end
        end
    end, CLEAR_DISPLAY_TIME)
end

attempt_current = function()
    if pending == nil then return end
    if not any_active(pending.track_ids) then
        pending = nil
        use_next_in_queue()
        return
    end
    if pending.retries >= pending.retry_cap then
        err('Max retries reached for '..pending.item..' ('..pending.label..'). Giving up.')
        pending = nil
        use_next_in_queue()
        return
    end

    -- Movement check: wait for the player to stop moving before using the item
    if is_player_moving() then
        if not movement_waiting then
            movement_waiting = true
            windower.add_to_chat(COL.WARN, PREFIX..pending.item..' for '..pending.label..
                ' is ready - will use when you stop moving.')
        end
        coroutine.schedule(function()
            attempt_current()
        end, MOVE_POLL_INTERVAL)
        return
    elseif movement_waiting then
        movement_waiting = false
        info('Movement stopped - using '..pending.item..' now.')
    end

    local ok, count = check_item(pending.item)
    if not ok then
        pending = nil
        use_next_in_queue()
        return
    end
    pending.retries  = pending.retries + 1
    no_effect_flag   = false
    player_name      = player_name or windower.ffxi.get_player()['name']
    windower.send_command('input /item "'..pending.item..'" '..player_name)
    coroutine.schedule(function()
        if pending == nil then return end
        if no_effect_flag then
            if pending.doom_mode then
                no_effect_flag = false
                attempt_current()
            else
                warn(pending.label..' appears unremovable - skipping.')
                pending = nil
                use_next_in_queue()
            end
            return
        end
        if not any_active(pending.track_ids) then
            pending = nil
            use_next_in_queue()
        else
            attempt_current()
        end
    end, USE_DELAY)
end

use_next_in_queue = function()
    if #queue == 0 then
        finish_queue()
        return
    end
    local entry = table.remove(queue, 1)
    if not any_active(entry.track_ids) then
        use_next_in_queue()
        return
    end
    local ok, count = check_item(entry.item)
    if not ok then
        use_next_in_queue()
        return
    end
    info('Using '..entry.item..' for '..entry.label..' ('..count..' remaining)')
    pending = {
        item      = entry.item,
        track_ids = entry.track_ids,
        label     = entry.label,
        retry_cap = entry.retry_cap,
        doom_mode = entry.doom_mode or false,
        retries   = 0,
    }
    hud_update(HUD_STATE.ACTIVE, get_queue_item_names())
    attempt_current()
end

-- ============================================================
--  Queue Builder
-- ============================================================
local function build_queue(monitor_filter)
    local active = get_active_buffs()
    if monitor_filter then
        local masked = S{}
        for id in pairs(active) do
            if monitor_filter:contains(id) then masked:add(id) end
        end
        active = masked
    end

    local function active_has(buff_set)
        for id in pairs(buff_set) do
            if active:contains(id) then return true end
        end
        return false
    end

    local has_paralyze = active_has(BUFF.PARALYZE)
    local has_doom     = active_has(BUFF.DOOM)
    local has_curse    = active_has(BUFF.CURSE)
    local has_silence  = active_has(BUFF.SILENCE)
    local has_blind    = active_has(BUFF.BLINDNESS)
    local has_poison   = active_has(BUFF.POISON)

    local panacea_ids_active = S{}
    for id in pairs(PANACEA_IDS) do
        if active:contains(id) then panacea_ids_active:add(id) end
    end
    local has_panacea_debuff = next(panacea_ids_active) ~= nil

    local ignore_poison = (monitor_filter == nil) and is_ignored('poison') or false

    local new_queue = {}

    -- 1. PARALYZE
    if has_paralyze then
        if ignore_poison and has_poison then
            warn('Paralysis detected - using Remedy which will also remove Poison (ignore list overridden).')
        end
        local remedy_active = S{}
        for id in pairs(REMEDY_IDS) do
            if active:contains(id) then remedy_active:add(id) end
        end
        table.insert(new_queue, {
            item=ITEMS.REMEDY, track_ids=remedy_active,
            label='Paralysis (+ Remedy-curable debuffs)', retry_cap=RETRY.PARALYZE,
        })
        has_silence = false
        has_blind   = false
        has_poison  = false
    end

    -- 2. DOOM
    if has_doom then
        table.insert(new_queue, {
            item=ITEMS.HOLY_WATER, track_ids=BUFF.DOOM,
            label='Doom', retry_cap=RETRY.DOOM, doom_mode=true,
        })
    end

    -- 3. SILENCE
    if has_silence and not is_ignored('silence') then
        local echo_count = get_item_count(ITEMS.ECHO_DROPS)
        if has_poison and ignore_poison then
            if echo_count > 0 then
                table.insert(new_queue, {
                    item=ITEMS.ECHO_DROPS, track_ids=BUFF.SILENCE,
                    label='Silence', retry_cap=RETRY.DEFAULT,
                })
            else
                warn('No Echo Drops and Poison is on ignore list - using Remedy (poison will be removed).')
                local remedy_active = S{}
                for id in pairs(REMEDY_IDS) do
                    if active:contains(id) then remedy_active:add(id) end
                end
                table.insert(new_queue, {
                    item=ITEMS.REMEDY, track_ids=remedy_active,
                    label='Silence (no Echo Drops)', retry_cap=RETRY.DEFAULT,
                })
            end
        else
            if echo_count > 0 then
                table.insert(new_queue, {
                    item=ITEMS.ECHO_DROPS, track_ids=BUFF.SILENCE,
                    label='Silence', retry_cap=RETRY.DEFAULT,
                })
            else
                warn('No Echo Drops - using Remedy for Silence.')
                local remedy_active = S{}
                for id in pairs(REMEDY_IDS) do
                    if active:contains(id) then remedy_active:add(id) end
                end
                table.insert(new_queue, {
                    item=ITEMS.REMEDY, track_ids=remedy_active,
                    label='Silence (no Echo Drops)', retry_cap=RETRY.DEFAULT,
                })
            end
        end
    end

    -- 4. PANACEA bucket
    if has_panacea_debuff then
        local panacea_labels = {}
        if active_has(BUFF.STAT_DOWN)   then table.insert(panacea_labels, 'Stat Down') end
        if active_has(BUFF.MAX_HP_DOWN) then table.insert(panacea_labels, 'Max HP Down') end
        if active_has(BUFF.MAX_MP_DOWN) then table.insert(panacea_labels, 'Max MP Down') end
        if active_has(BUFF.DEF_DOWN)    then table.insert(panacea_labels, 'Def Down') end
        if active_has(BUFF.MDEF_DOWN)   then table.insert(panacea_labels, 'MDef Down') end
        if active_has(BUFF.ATK_DOWN)    then table.insert(panacea_labels, 'Atk Down') end
        if active_has(BUFF.ACC_DOWN)    then table.insert(panacea_labels, 'Acc Down') end
        if active_has(BUFF.EVA_DOWN)    then table.insert(panacea_labels, 'Eva Down') end
        if active_has(BUFF.MATK_DOWN)   then table.insert(panacea_labels, 'MAtk Down') end
        if active_has(BUFF.MACC_DOWN)   then table.insert(panacea_labels, 'MAcc Down') end
        if active_has(BUFF.SLOW)        then table.insert(panacea_labels, 'Slow') end
        if active_has(BUFF.BIO)         then table.insert(panacea_labels, 'Bio') end
        if active_has(BUFF.DIA)         then table.insert(panacea_labels, 'Dia') end
        if active_has(BUFF.ADDLE)       then table.insert(panacea_labels, 'Addle') end
        if active_has(BUFF.FLASH)       then table.insert(panacea_labels, 'Flash') end
        if active_has(BUFF.HELIX)       then table.insert(panacea_labels, 'Helix') end
        if active_has(BUFF.BURN)        then table.insert(panacea_labels, 'Burn') end
        if active_has(BUFF.FROST)       then table.insert(panacea_labels, 'Frost') end
        if active_has(BUFF.CHOKE)       then table.insert(panacea_labels, 'Choke') end
        if active_has(BUFF.RASP)        then table.insert(panacea_labels, 'Rasp') end
        if active_has(BUFF.SHOCK)       then table.insert(panacea_labels, 'Shock') end
        if active_has(BUFF.DROWN)       then table.insert(panacea_labels, 'Drown') end
        if active_has(BUFF.GRAVITY)     then table.insert(panacea_labels, 'Gravity') end
        if active_has(BUFF.BIND)        then table.insert(panacea_labels, 'Bind') end
        table.insert(new_queue, {
            item=ITEMS.PANACEA, track_ids=panacea_ids_active,
            label=table.concat(panacea_labels, '/'), retry_cap=RETRY.DEFAULT,
        })
    end

    -- 5. BLINDNESS
    if has_blind and not is_ignored('blindness') then
        if has_silence and not is_ignored('silence') then
            if has_poison and ignore_poison then
                local eye_count = get_item_count(ITEMS.EYE_DROPS)
                if eye_count > 0 then
                    table.insert(new_queue, {
                        item=ITEMS.EYE_DROPS, track_ids=BUFF.BLINDNESS,
                        label='Blindness', retry_cap=RETRY.DEFAULT,
                    })
                else
                    warn('No Eye Drops - using Remedy for Blindness (poison will be removed).')
                    local remedy_active = S{}
                    for id in pairs(REMEDY_IDS) do
                        if active:contains(id) then remedy_active:add(id) end
                    end
                    table.insert(new_queue, {
                        item=ITEMS.REMEDY, track_ids=remedy_active,
                        label='Blindness+Silence (no Eye Drops)', retry_cap=RETRY.DEFAULT,
                    })
                    has_silence = false
                end
            else
                local remedy_active = S{}
                for id in pairs(REMEDY_IDS) do
                    if active:contains(id) then remedy_active:add(id) end
                end
                table.insert(new_queue, {
                    item=ITEMS.REMEDY, track_ids=remedy_active,
                    label='Blindness+Silence', retry_cap=RETRY.DEFAULT,
                })
                has_silence = false
            end
        else
            local eye_count = get_item_count(ITEMS.EYE_DROPS)
            if eye_count > 0 then
                table.insert(new_queue, {
                    item=ITEMS.EYE_DROPS, track_ids=BUFF.BLINDNESS,
                    label='Blindness', retry_cap=RETRY.DEFAULT,
                })
            else
                warn('No Eye Drops - using Remedy for Blindness.')
                local remedy_active = S{}
                for id in pairs(REMEDY_IDS) do
                    if active:contains(id) then remedy_active:add(id) end
                end
                table.insert(new_queue, {
                    item=ITEMS.REMEDY, track_ids=remedy_active,
                    label='Blindness (no Eye Drops)', retry_cap=RETRY.DEFAULT,
                })
            end
        end
    end

    -- 6. CURSE
    if has_curse and not is_ignored('curse') then
        table.insert(new_queue, {
            item=ITEMS.HOLY_WATER, track_ids=BUFF.CURSE,
            label='Curse', retry_cap=RETRY.DEFAULT, doom_mode=false,
        })
    end

    -- 7. POISON
    if has_poison and not ignore_poison then
        local antidote_count = get_item_count(ITEMS.ANTIDOTE)
        if antidote_count > 0 then
            table.insert(new_queue, {
                item=ITEMS.ANTIDOTE, track_ids=BUFF.POISON,
                label='Poison', retry_cap=RETRY.DEFAULT,
            })
        else
            warn('No Antidote - using Remedy for Poison.')
            local remedy_active = S{}
            for id in pairs(REMEDY_IDS) do
                if active:contains(id) then remedy_active:add(id) end
            end
            table.insert(new_queue, {
                item=ITEMS.REMEDY, track_ids=remedy_active,
                label='Poison (no Antidote)', retry_cap=RETRY.DEFAULT,
            })
        end
    elseif has_poison and ignore_poison and not has_paralyze and #new_queue == 0 then
        info('Poison detected but is on the ignore list. No action taken.')
        return nil
    end

    return new_queue
end

-- ============================================================
--  Autopoison Engine
-- ============================================================
local MAX_AP_RETRIES  = 3
local ap_generation    = 0  -- incremented each time a new attempt chain starts
local autopoison_attempt

local function autopoison_hud_refresh()
    hud_set_idle()
end

autopoison_attempt = function(retries, generation)
    retries    = retries or 0
    generation = generation or ap_generation
    -- If generation has changed, a newer attempt chain has taken over - bail out
    if generation ~= ap_generation then return end
    if not autopoison then return end
    if busy then
        coroutine.schedule(function()
            autopoison_attempt(retries, generation)
        end, AP_BUSY_POLL)
        return
    end
    if any_active(BUFF.POISON) then
        autopoison_busy = false
        ap_hud_state    = 'idle'
        autopoison_hud_refresh()
        return
    end
    if retries >= MAX_AP_RETRIES then
        warn('[AutoPoison] Max retries reached - could not reapply poison.')
        autopoison_busy = false
        ap_hud_state    = 'idle'
        autopoison_hud_refresh()
        return
    end
    local fruit_count = get_item_count(ITEMS.PACHIRA_FRUIT)
    if fruit_count == 0 then
        err('[AutoPoison] Out of El. Pachira Fruit!')
        autopoison_busy = false
        ap_hud_state    = 'empty'
        autopoison_hud_refresh()
        return
    end
    ap_hud_state    = 'applying'
    autopoison_busy = true
    autopoison_hud_refresh()
    player_name = player_name or windower.ffxi.get_player()['name']
    windower.send_command('input /item "'..ITEMS.PACHIRA_FRUIT..'" '..player_name)
    coroutine.schedule(function()
        -- Bail if a newer attempt chain has taken over
        if generation ~= ap_generation then return end
        if not autopoison then return end
        if any_active(BUFF.POISON) then
            autopoison_busy = false
            ap_hud_state    = 'idle'
            autopoison_hud_refresh()
        else
            autopoison_attempt(retries + 1, generation)
        end
    end, AP_RETRY_DELAY)
end

local function autopoison_trigger()
    if not autopoison then return end
    if autopoison_busy then return end
    -- Increment generation to invalidate any stale coroutines still in flight
    ap_generation   = ap_generation + 1
    autopoison_busy = true
    autopoison_attempt(0, ap_generation)
end

-- ============================================================
--  Autofood Engine
-- ============================================================
local MAX_AF_RETRIES = 3
local autofood_attempt

local function autofood_hud_refresh()
    hud_set_idle()
end

autofood_attempt = function(retries, generation)
    retries    = retries or 0
    generation = generation or autofood_gen
    if generation ~= autofood_gen then return end
    if not autofood then return end

    -- Wait if main cure queue is busy
    if busy then
        coroutine.schedule(function()
            autofood_attempt(retries, generation)
        end, AP_BUSY_POLL)
        return
    end

    -- Food is already active - nothing to do
    if any_active(BUFF.FOOD) then
        autofood_busy = false
        af_hud_state  = 'idle'
        autofood_hud_refresh()
        return
    end

    if retries >= MAX_AF_RETRIES then
        warn('[AutoFood] Max retries reached - could not apply '..
             (autofood_item or '?')..'. Disabling autofood.')
        autofood      = false
        autofood_busy = false
        af_hud_state  = 'idle'
        autofood_hud_refresh()
        return
    end

    -- Check inventory
    local count = autofood_item and get_item_count(autofood_item) or 0
    if count == 0 then
        if autofood_item then
            err('[AutoFood] Out of '..autofood_item..'! Disabling autofood.')
        else
            err('[AutoFood] No food item set. Disabling autofood.')
        end
        autofood      = false
        autofood_busy = false
        af_hud_state  = 'empty'
        autofood_hud_refresh()
        return
    end

    af_hud_state  = 'applying'
    autofood_busy = true
    autofood_hud_refresh()
    player_name = player_name or windower.ffxi.get_player()['name']
    windower.send_command('input /item "'..autofood_item..'" '..player_name)

    coroutine.schedule(function()
        if generation ~= autofood_gen then return end
        if not autofood then return end
        if any_active(BUFF.FOOD) then
            autofood_busy = false
            af_hud_state  = 'idle'
            autofood_hud_refresh()
        else
            autofood_attempt(retries + 1, generation)
        end
    end, AP_RETRY_DELAY)
end

local function autofood_trigger()
    if not autofood then return end
    if autofood_busy then return end
    autofood_gen   = autofood_gen + 1
    autofood_busy  = true
    autofood_attempt(0, autofood_gen)
end

-- ============================================================
--  Scan & Cure Entry Points
-- ============================================================
local debounce_scheduled = false

local function run_scan(source)
    if busy then
        warn('Already clearing debuffs ('..(source or 'manual')..'). Please wait.')
        return
    end
    local built
    if source == 'monitor' then
        built = build_queue(monitor_buffs)
    else
        built = build_queue(nil)
    end
    if built == nil then return end
    if #built == 0 then
        if source == 'manual' then
            info('No actionable debuffs detected.')
        end
        return
    end
    busy  = true
    queue = built
    if source == 'autoscan' then
        info('Autoscan triggered! Clearing debuffs - please hold movement and actions.')
    elseif source == 'monitor' then
        info('Monitor triggered! Clearing: '..table.concat(monitor_labels, ', ')..
             ' - please hold movement and actions.')
    end
    use_next_in_queue()
end

-- ============================================================
--  Gain Buff: autoscan/monitor trigger
-- ============================================================
windower.register_event('gain buff', function(id)
    -- If poison gained externally, clear autopoison state
    if id == 3 and autopoison then
        autopoison_busy = false
        ap_hud_state    = 'idle'
        autopoison_hud_refresh()
    end
    -- If food gained externally, clear autofood applying state
    if id == 251 and autofood then
        autofood_busy = false
        af_hud_state  = 'idle'
        autofood_hud_refresh()
    end

    if busy then return end

    if monitor_mode then
        if not monitor_buffs:contains(id) then return end
        if not debounce_scheduled then
            debounce_scheduled = true
            coroutine.schedule(function()
                debounce_scheduled = false
                if not busy then run_scan('monitor') end
            end, DEBOUNCE)
        end
        return
    end

    if not settings.autoscan then return end
    local tracked = false
    for _, s in pairs(BUFF) do
        if s:contains(id) then tracked = true break end
    end
    if not tracked then return end
    if not debounce_scheduled then
        debounce_scheduled = true
        coroutine.schedule(function()
            debounce_scheduled = false
            if not busy then run_scan('autoscan') end
        end, DEBOUNCE)
    end
end)

-- ============================================================
--  Lose Buff: fast-path queue advancement + autopoison trigger
-- ============================================================
windower.register_event('lose buff', function(id)
    if pending ~= nil and pending.track_ids:contains(id) then
        if not any_active(pending.track_ids) then
            pending = nil
            use_next_in_queue()
        end
    end
    if id == 3 and autopoison and not autopoison_busy then
        autopoison_trigger()
    end
    if id == 251 and autofood and not autofood_busy then
        autofood_trigger()
    end
end)

-- ============================================================
--  Incoming Text + Slash Command Shortcuts (single handler)
-- ============================================================
local SLASH_SHORTCUTS = {
    ['^/remedy$']        = ITEMS.REMEDY,
    ['^/rem$']           = ITEMS.REMEDY,
    ['^/remed$']         = ITEMS.REMEDY,
    ['^/panacea$']       = ITEMS.PANACEA,
    ['^/pan$']           = ITEMS.PANACEA,
    ['^/panac$']         = ITEMS.PANACEA,
    ['^/echodrops$']     = ITEMS.ECHO_DROPS,
    ['^/ech$']           = ITEMS.ECHO_DROPS,
    ['^/echod$']         = ITEMS.ECHO_DROPS,
    ['^/eyedrops$']      = ITEMS.EYE_DROPS,
    ['^/eye$']           = ITEMS.EYE_DROPS,
    ['^/antidote$']      = ITEMS.ANTIDOTE,
    ['^/anti$']          = ITEMS.ANTIDOTE,
    ['^/antid$']         = ITEMS.ANTIDOTE,
    ['^/holywater$']     = ITEMS.HOLY_WATER,
    ['^/hol$']           = ITEMS.HOLY_WATER,
    ['^/holyw$']         = ITEMS.HOLY_WATER,
    ['^/vileelixir$']    = ITEMS.VILE_ELIXIR,
    ['^/vile$']          = ITEMS.VILE_ELIXIR,
    ['^/ve$']            = ITEMS.VILE_ELIXIR,
    ['^/vileelixir%+1$'] = ITEMS.VILE_ELIXIR_PLUS,
    ['^/ve1$']           = ITEMS.VILE_ELIXIR_PLUS,
    ['^/antacid$']       = ITEMS.ANTACID,
    ['^/icaruswing$']    = ITEMS.ICARUS_WING,
    ['^/wing$']          = ITEMS.ICARUS_WING,
    ['^/iw$']            = ITEMS.ICARUS_WING,
    ['^/fruit$']         = ITEMS.PACHIRA_FRUIT,
    ['^/pachira$']       = ITEMS.PACHIRA_FRUIT,
    -- Prism Powder (/invisible excluded - spell conflict via shortcuts addon)
    ['^/prism$']         = ITEMS.PRISM_POWDER,
    ['^/powder$']        = ITEMS.PRISM_POWDER,
    ['^/prismpowder$']   = ITEMS.PRISM_POWDER,
    ['^/invis$']         = ITEMS.PRISM_POWDER,
    ['^/inv$']           = ITEMS.PRISM_POWDER,
    -- Silent Oil (/sneak excluded - spell conflict via shortcuts addon)
    ['^/oil$']           = ITEMS.SILENT_OIL,
    ['^/silentoil$']     = ITEMS.SILENT_OIL,
    ['^/snk$']           = ITEMS.SILENT_OIL,
}

windower.register_event('incoming text', function(original, modified, mode, newmode, blocked)
    if blocked then return end
    local cmd = original:match('^>>medicine(.*)$')
    if cmd then
        windower.send_command('med'..cmd)
        return ''
    end
    if pending then
        player_name = player_name or windower.ffxi.get_player()['name']
        if original:find('No effect on '..player_name) then
            no_effect_flag = true
        end
        if original:find('fails to activate%.') then
            info(pending.item..' failed to activate - will retry.')
        end
    end
end)

-- ============================================================
--  Outgoing Text: slash shortcuts
--  Registered after use_single/use_reraise are defined below.
-- ============================================================
local use_single   -- forward declaration
local use_reraise  -- forward declaration

local function register_outgoing()
    windower.register_event('outgoing text', function(original, modified, blocked)
        if blocked then return end
        local lower = original:lower()
        if lower == '/med' then
            run_scan('manual')
            return ''
        end
        if lower == '/rr' then
            use_reraise()
            return ''
        end
        for pattern, item_name in pairs(SLASH_SHORTCUTS) do
            if lower:match(pattern) then
                use_single(item_name)
                return ''
            end
        end
    end)
end

-- ============================================================
--  Direct Item Use
-- ============================================================
use_single = function(item_name)
    if busy then
        warn('Currently clearing debuffs. Please wait.')
        return
    end
    local ok, count = check_item(item_name)
    if not ok then return end
    info('Using '..item_name..' ('..count..' remaining)')
    player_name = player_name or windower.ffxi.get_player()['name']
    windower.send_command('input /item "'..item_name..'" '..player_name)
end

use_reraise = function()
    for _, item in ipairs({
        ITEMS.SUPER_RERAISER, ITEMS.HI_RERAISER,
        ITEMS.RERAISER, ITEMS.INSTANT_RERAISE,
    }) do
        local count = get_item_count(item)
        if count > 0 then
            info('Using '..item..' ('..count..' remaining)')
            hud:text(PREFIX..'>> '..item)
            hud:color(255, 180, 0)
            coroutine.schedule(function()
                if not busy then hud_set_idle() end
            end, CLEAR_DISPLAY_TIME)
            player_name = player_name or windower.ffxi.get_player()['name']
            windower.send_command('input /item "'..item..'" '..player_name)
            return
        end
    end
    err('No Reraise items found in inventory!')
end

-- ============================================================
--  Status Print
-- ============================================================
local function print_status()
    info('---- Medicine Cabinet v'.._addon.version..' ----')
    local watch_sets = {
        {name='Paralysis',      set=BUFF.PARALYZE},
        {name='Doom',           set=BUFF.DOOM},
        {name='Curse',          set=BUFF.CURSE},
        {name='Silence',        set=BUFF.SILENCE},
        {name='Blindness',      set=BUFF.BLINDNESS},
        {name='Poison',         set=BUFF.POISON},
        {name='Slow',           set=BUFF.SLOW},
        {name='Bio',            set=BUFF.BIO},
        {name='Dia',            set=BUFF.DIA},
        {name='Stat Down',      set=BUFF.STAT_DOWN},
        {name='Max HP Down',    set=BUFF.MAX_HP_DOWN},
        {name='Max MP Down',    set=BUFF.MAX_MP_DOWN},
        {name='Defense Down',   set=BUFF.DEF_DOWN},
        {name='Magic Def Down', set=BUFF.MDEF_DOWN},
    }
    local found = {}
    for _, w in ipairs(watch_sets) do
        if any_active(w.set) then table.insert(found, w.name) end
    end
    info('Active debuffs: '..(#found > 0 and table.concat(found, ', ') or 'None'))
    if monitor_mode then
        info('Mode: Monitor ('..table.concat(monitor_labels, ', ')..')')
    else
        info('Autoscan: '..(settings.autoscan and 'ON' or 'OFF'))
    end
    info('Autopoison: '..(autopoison and 'ON | '..get_item_count(ITEMS.PACHIRA_FRUIT)..' fruits remaining' or 'OFF'))
    if autofood and autofood_item then
        info('Autofood: ON | '..autofood_item..' ('..get_item_count(autofood_item)..' remaining)')
    else
        info('Autofood: OFF')
    end
    info('Movement detection: '..(settings.movement_check and 'ON' or 'OFF'))
    local ignore_list = {}
    for k in pairs(settings.ignore) do table.insert(ignore_list, k) end
    info('Ignore list: '..(#ignore_list > 0 and table.concat(ignore_list, ', ') or '(empty)'))
    local tracked_items = {
        ITEMS.REMEDY, ITEMS.PANACEA, ITEMS.ECHO_DROPS, ITEMS.EYE_DROPS,
        ITEMS.ANTIDOTE, ITEMS.HOLY_WATER, ITEMS.ICARUS_WING,
        ITEMS.RERAISER, ITEMS.HI_RERAISER, ITEMS.SUPER_RERAISER,
        ITEMS.PACHIRA_FRUIT,
        ITEMS.PRISM_POWDER,
        ITEMS.SILENT_OIL,
    }
    local inv = {}
    for _, item in ipairs(tracked_items) do
        local c = get_item_count(item)
        if c > 0 then table.insert(inv, item..':'..c) end
    end
    info('Inventory: '..(#inv > 0 and table.concat(inv, ' | ') or 'None found'))
    info('----------------------------------')
end

-- ============================================================
--  Command Handler
-- ============================================================
windower.register_event('addon command', function(...)
    local args = {...}
    local cmd  = args[1] and args[1]:lower() or ''

    if cmd == '' then
        run_scan('manual')
        return
    end

    local shortcuts = {
        ['r']        = ITEMS.REMEDY,
        ['rem']      = ITEMS.REMEDY,
        ['remedy']   = ITEMS.REMEDY,
        ['p']        = ITEMS.PANACEA,
        ['pan']      = ITEMS.PANACEA,
        ['panacea']  = ITEMS.PANACEA,
        ['e']        = ITEMS.ECHO_DROPS,
        ['echo']     = ITEMS.ECHO_DROPS,
        ['eye']      = ITEMS.EYE_DROPS,
        ['a']        = ITEMS.ANTIDOTE,
        ['anti']     = ITEMS.ANTIDOTE,
        ['antidote'] = ITEMS.ANTIDOTE,
        ['h']        = ITEMS.HOLY_WATER,
        ['hw']       = ITEMS.HOLY_WATER,
        ['holy']     = ITEMS.HOLY_WATER,
        ['vile']     = ITEMS.VILE_ELIXIR,
        ['ve']       = ITEMS.VILE_ELIXIR,
        ['vile+1']   = ITEMS.VILE_ELIXIR_PLUS,
        ['ve1']      = ITEMS.VILE_ELIXIR_PLUS,
        ['antacid']  = ITEMS.ANTACID,
        ['wing']     = ITEMS.ICARUS_WING,
        ['iw']       = ITEMS.ICARUS_WING,
        ['fruit']    = ITEMS.PACHIRA_FRUIT,
        ['prism']    = ITEMS.PRISM_POWDER,
        ['powder']   = ITEMS.PRISM_POWDER,
        ['prismpowder'] = ITEMS.PRISM_POWDER,
        ['oil']      = ITEMS.SILENT_OIL,
        ['silentoil']= ITEMS.SILENT_OIL,
    }

    if shortcuts[cmd] then
        use_single(shortcuts[cmd])
        return
    end

    if cmd == 'rr' or cmd == 'reraise' then
        use_reraise()
        return
    end

    if cmd == 'movement' or cmd == 'move' then
        local sub = args[2] and args[2]:lower() or ''
        if sub == 'on' then
            settings.movement_check = true
        elseif sub == 'off' then
            settings.movement_check = false
        else
            settings.movement_check = not settings.movement_check
        end
        settings:save()
        last_pos = nil  -- reset baseline so the next check doesn't false-trigger
        info('Movement detection '..(settings.movement_check and 'ON' or 'OFF'))
        return
    end

    if cmd == 'doom' then
        if busy then warn('Already clearing debuffs. Please wait.') return end
        if not any_active(BUFF.DOOM) then warn('No Doom detected.') return end
        local ok, count = check_item(ITEMS.HOLY_WATER)
        if not ok then return end
        info('Doom removal started - spamming Holy Water ('..count..' remaining). Do not move!')
        busy  = true
        queue = {}
        pending = {
            item=ITEMS.HOLY_WATER, track_ids=BUFF.DOOM,
            label='Doom', retry_cap=RETRY.DOOM, doom_mode=true, retries=0,
        }
        hud_update(HUD_STATE.ACTIVE, {ITEMS.HOLY_WATER})
        attempt_current()
        return
    end

    if cmd == 'autoscan' then
        local sub = args[2] and args[2]:lower() or ''
        if sub == 'on' then
            settings.autoscan = true
        elseif sub == 'off' then
            settings.autoscan = false
        else
            settings.autoscan = not settings.autoscan
        end
        settings:save()
        if settings.autoscan and monitor_mode then
            monitor_mode   = false
            monitor_buffs  = S{}
            monitor_labels = {}
            info('Monitor mode disabled.')
        end
        info('Autoscan '..(settings.autoscan and 'ON' or 'OFF'))
        hud_set_idle()
        return
    end

    if cmd == 'autopoison' or cmd == 'ap' then
        local sub = args[2] and args[2]:lower() or ''
        if sub == 'on' then
            autopoison = true
        elseif sub == 'off' then
            autopoison = false
        else
            autopoison = not autopoison
        end
        if autopoison then
            ap_hud_state = 'idle'
            info('Autopoison ON - will reapply poison using '..ITEMS.PACHIRA_FRUIT..
                 ' ('..get_item_count(ITEMS.PACHIRA_FRUIT)..' in inventory)')
            if not any_active(BUFF.POISON) then
                autopoison_trigger()
            end
        else
            autopoison_busy = false
            ap_hud_state    = 'idle'
            info('Autopoison OFF')
        end
        hud_set_idle()
        return
    end

    if cmd == 'autofood' or cmd == 'af' then
        -- //med autofood <item name> - set food and enable
        -- //med autofood off         - disable
        -- //med autofood             - toggle off if active, show status if not
        local sub = args[2] and args[2]:lower() or ''

        if sub == 'off' then
            if autofood then
                autofood      = false
                autofood_busy = false
                af_hud_state  = 'idle'
                autofood_gen  = autofood_gen + 1
                info('Autofood disabled.')
                hud_set_idle()
            else
                info('Autofood is not active.')
            end
            return
        end

        if sub == '' then
            -- No args - toggle off if active, otherwise show usage
            if autofood then
                autofood      = false
                autofood_busy = false
                af_hud_state  = 'idle'
                autofood_gen  = autofood_gen + 1
                info('Autofood disabled (was using: '..( autofood_item or '?')..').')
                hud_set_idle()
            else
                info('Autofood is not active. Usage: //med autofood <item name>')
            end
            return
        end

        -- Reconstruct item name from remaining args (space separated)
        local item_parts = {}
        for i = 2, #args do table.insert(item_parts, args[i]) end
        local item_name = table.concat(item_parts, ' ')

        -- Check inventory
        local count = get_item_count(item_name)
        if count == 0 then
            err('Autofood: "'..item_name..'" not found in inventory. Check spelling.')
            return
        end

        -- Enable autofood
        autofood      = true
        autofood_item = item_name
        autofood_busy = false
        af_hud_state  = 'idle'
        autofood_gen  = autofood_gen + 1
        info('Autofood ON - will reapply '..item_name..' when food wears off ('..count..' in inventory)')

        -- Fire immediately if no food buff is active
        if not any_active(BUFF.FOOD) then
            autofood_trigger()
        else
            info('Food buff already active - will reapply when it wears off.')
        end
        hud_set_idle()
        return
    end

    if cmd == 'monitor' then
        local sub = args[2] and args[2]:lower() or ''
        if sub == '' or sub == 'off' then
            if monitor_mode then
                monitor_mode   = false
                monitor_buffs  = S{}
                monitor_labels = {}
                info('Monitor mode disabled.')
                hud_set_idle()
            else
                info('Monitor mode is not active. Use //med monitor <buff> [buff] ... to start.')
            end
            return
        end
        local new_buffs  = S{}
        local new_labels = {}
        local unknown    = {}
        for i = 2, #args do
            local bname = args[i]:lower()
            local bset  = BUFF_NAME_MAP[bname]
            if bset then
                for id in pairs(bset) do new_buffs:add(id) end
                local display = bname:gsub('^%l', string.upper)
                local already = false
                for _, l in ipairs(new_labels) do
                    if l:lower() == display:lower() then already = true break end
                end
                if not already then table.insert(new_labels, display) end
            else
                table.insert(unknown, args[i])
            end
        end
        if #unknown > 0 then
            warn('Unrecognized debuff(s): '..table.concat(unknown, ', ')..'. Check spelling and try again.')
        end
        if next(new_buffs) == nil then
            warn('No valid debuffs specified. Monitor mode not changed.')
            return
        end
        if settings.autoscan then
            settings.autoscan = false
            settings:save()
            info('Autoscan disabled - switching to monitor mode.')
        end
        monitor_mode   = true
        monitor_buffs  = new_buffs
        monitor_labels = new_labels
        info('Monitor mode ON - watching: '..table.concat(new_labels, ', '))
        hud_update(HUD_STATE.IDLE)
        return
    end

    if cmd == 'ignore' then
        local debuff = args[2] and args[2]:lower() or ''
        if debuff == '' then
            local list = {}
            for k in pairs(settings.ignore) do table.insert(list, k) end
            info('Ignore list: '..(#list > 0 and table.concat(list, ', ') or '(empty)'))
        else
            if settings.ignore:contains(debuff) then
                settings.ignore:remove(debuff)
                info(debuff..' removed from ignore list (will now be cured).')
            else
                settings.ignore:add(debuff)
                info(debuff..' added to ignore list.')
            end
            settings:save()
        end
        return
    end

    if args[2] then
        local debuff = cmd
        local toggle = args[2]:lower()
        if toggle == 'off' then
            if not settings.ignore:contains(debuff) then
                settings.ignore:add(debuff)
                info(debuff..' added to ignore list.')
                settings:save()
            else
                info(debuff..' is already on the ignore list.')
            end
            return
        elseif toggle == 'on' then
            if settings.ignore:contains(debuff) then
                settings.ignore:remove(debuff)
                info(debuff..' removed from ignore list (will now be cured).')
                settings:save()
            else
                info(debuff..' is not on the ignore list.')
            end
            return
        end
    end

    if cmd == 'status' or cmd == 'print' then
        print_status()
        return
    end

    if cmd == 'list' then
        local sub = args[2] and args[2]:lower() or ''
        if sub == 'ignore' then
            local list = {}
            for k in pairs(settings.ignore) do table.insert(list, k) end
            info('Ignore list ('..(#list)..'): '..(#list > 0 and table.concat(list, ', ') or '(empty)'))
        elseif sub == 'monitor' then
            if not monitor_mode or #monitor_labels == 0 then
                info('Monitor mode is not active.')
            else
                info('Monitoring ('..#monitor_labels..'): '..table.concat(monitor_labels, ', '))
            end
        else
            print_status()
        end
        return
    end

    if cmd == 'help' then
        local helptext = {
            'Medicine Cabinet v'.._addon.version..' - Commands:',
            ' //med                       - Scan and cure debuffs by priority',
            ' //med autoscan [on|off]     - Toggle automatic debuff detection',
            ' //med monitor <buff> [...]  - Watch specific debuffs only (session)',
            ' //med monitor off           - Disable monitor mode',
            ' //med autopoison/ap [on|off]- Toggle automatic poison reapplication',
            ' //med autofood/af <item>     - Auto-reapply food when it wears off',
            ' //med autofood off           - Disable autofood',
            ' //med doom                  - Manually trigger Doom removal loop',
            ' //med status                - Show debuffs, ignore list, inventory',
            ' //med list ignore           - List all ignored ailments',
            ' //med list monitor          - List all monitored ailments',
            ' //med ignore <buff>         - Toggle buff on/off the ignore list',
            ' //med <buff> off/on         - Add/remove buff from ignore list',
            ' //med r/rem/remedy          - Use a Remedy',
            ' //med p/pan/panacea         - Use a Panacea',
            ' //med e/echo                - Use Echo Drops',
            ' //med eye                   - Use Eye Drops',
            ' //med a/anti/antidote       - Use an Antidote',
            ' //med h/hw/holy             - Use a Holy Water',
            ' //med vile/ve               - Use a Vile Elixir',
            ' //med vile+1/ve1            - Use a Vile Elixir +1',
            ' //med antacid               - Use an Antacid',
            ' //med wing/iw               - Use an Icarus Wing',
            ' //med fruit                 - Use an El. Pachira Fruit',
            ' //med prism/powder/prismpowder - Use a Prism Powder',
            ' //med oil/silentoil          - Use a Silent Oil',
            ' //med rr                    - Use best Reraise item',
            ' //med help                  - Show this help',
        }
        for _, line in ipairs(helptext) do
            windower.add_to_chat(COL.INFO, line)
        end
        return
    end

    warn('Unknown command: '..cmd..'. Type //med help for commands.')
end)

-- ============================================================
--  Load / Unload
-- ============================================================
windower.register_event('load', function()
    player_name = windower.ffxi.get_player()['name']
    hud:pos(settings.hud_x, settings.hud_y)
    hud_show()
    hud_set_idle()
    register_outgoing()
    local ignore_display
    if next(settings.ignore) then
        local t = {}
        for k in pairs(settings.ignore) do t[#t+1] = k end
        ignore_display = table.concat(t, ', ')
    else
        ignore_display = '(empty)'
    end
    info('Loaded v'.._addon.version..'. Autoscan: '..(settings.autoscan and 'ON' or 'OFF')..
         '. Monitor: OFF. Ignore: '..ignore_display)
end)

windower.register_event('unload', function()
    save_hud_pos()
    hud_hide()
end)
