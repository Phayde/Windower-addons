--[[
================================================================================
  DigSkill (digskill) - Automated Chocobo Digging Addon
================================================================================
  Author: Phayde
  Version: 1.2.9

  Automates chocobo digging, tracks daily fatigue, and logs session stats
  across multiple sessions within the same JP day.

  SETUP:
    1. Ride your chocobo (rented or personal)
    2. Have Gysahl Greens in your inventory
    3. Run //cc log (chococard addon) to find your chocobo's END stat value
       and set it with: //ds end <value>  (or edit settings.xml)
    4. //ds start

  COMMANDS:
    //ds start             - Begin a digging session
    //ds stop              - End the current session early
    //ds pause / resume    - Pause and resume the current session
    //ds status            - Show session stats and daily fatigue progress
    //ds settings          - Show all current settings
    //ds rank [name]       - Show or set dig rank
    //ds body [type]       - Set body piece: none / blue / sky
    //ds campaign          - Toggle Hyper Campaign mode
    //ds dst               - Toggle DST (EDT/EST) for JP midnight calculation
    //ds maxtime [min]     - Set max session duration in minutes (0 = no limit)
    //ds tossitems         - Toggle dropping of unwanted dug items
    //ds warp              - Toggle auto-warp home on dismount after session
    //ds wingskill         - Show/set wing skill level and auto-rank toggle
    //ds zonelist          - List all diggable zones with grades
    //ds report            - Print today's JP day session log
    //ds fullreport        - Compile all-time report from all daily logs
    //ds cumulative        - Show all-time career stats
    //ds help              - Show full command list

  CONFIGURATION (settings.xml):
    body_piece                - "None", "Blue Racing Silks", "Sky Blue Racing Silks"
    chocobo_end_value         - Raw END stat from //cc log (0-255). 0 = rental.
    keep_items                - Comma-separated items to keep when tossitems is on
    drop_dug_items            - true = destroy unwanted dug items
    max_session_minutes       - Max session duration in minutes (0 = no limit)
    dst                       - true = EDT (UTC-4), false = EST (UTC-5)
================================================================================
]]

_addon.name    = 'digskill'
_addon.author  = 'Phayde'
_addon.version = '1.2.9'
_addon.commands = {'digskill', 'digs', 'ds'}

require('luau')
require('logger')
local config   = require('config')
local res_items = require('resources').items
local extdata  = require('extdata')

-- ============================================================================
--  DEFAULT CONFIGURATION
-- ============================================================================

local defaults = {
    -- Gear
    body_piece              = 'None',
    -- Options: "None", "Blue Racing Silks", "Sky Blue Racing Silks"
    -- Blue Racing Silks:     ~50% chance of free dig (no fatigue cost) per item found
    -- Sky Blue Racing Silks: ~50% chance of bonus skill up per item found

    -- Chocobo
    chocobo_end_value       = 0,
    -- Raw END stat value from running //cc log (chococard addon)
    -- 0   = rental chocobo or Poor(F) endurance (100 dig cap)
    -- 128 = Better than average (B) endurance (~164 dig cap)
    -- 224 = First-class (SS) endurance (~200 dig cap)
    -- Formula: fatigue_cap = min(100 + floor(END/2), 200)

    -- Stopping conditions
    max_session_minutes     = 60,
    -- Maximum session duration in minutes. Session stops when this time elapses,
    -- even if the fatigue cap has not been reached.
    -- Default: 60 minutes. Set to 0 to disable the time limit entirely
    -- (session will only stop when fatigue cap is reached or //ds stop is used).

    -- Automation
    dig_rank                = 'Amateur',
    -- Your current chocobo digging rank. Controls area and dig delay timers.
    -- Options: Amateur, Recruit, Initiate, Novice, Apprentice, Journeyman,
    --          Craftsman, Artisan, Adept, Veteran, Expert
    -- Dig delay = time between individual digs

    dst                     = true,
    -- Set to true if you are currently observing Daylight Saving Time (EDT, UTC-4).
    -- Set to false for standard time (EST, UTC-5).
    -- JP midnight (00:00 JST) = 10:00 AM EDT = 11:00 AM EST.
    -- Use //ds dst to toggle.

    hyper_campaign          = false,
    -- Set to true during Hyper Campaign event (overrides all delays to minimum:
    -- 5s area delay, 3s dig delay regardless of rank)

    move_forward_secs       = 0.5,
    -- How long to hold Numpad8 (forward) before adding the left turn
    move_left_secs          = 0.5,
    -- How long to additionally hold Numpad4 (left) while still holding Numpad8
    -- Total movement = move_forward_secs + move_left_secs forward, move_left_secs left

    min_move_distance       = 1.0,
    -- Minimum distance in feet the chocobo must move before attempting a dig
    -- If movement is blocked, the move sequence will retry until this is met

    -- Inventory management
    keep_items              = 'Gysahl Greens',
    -- Comma-separated list of items to keep when dug up.
    -- Gysahl Greens are always kept regardless of this setting.

    drop_dug_items          = true,
    -- true  = destroy any dug item not on keep_items list
    -- false = keep everything (useful for testing or farming specific items)

    warp                    = false,
    -- true  = automatically use Warp Ring when dismounting after a dig session
    -- false = no auto-warp (manual dismount behavior unchanged)
    -- Use //ds warp to toggle. Requires a Warp Ring in inventory or wardrobe.

    auto_rank               = true,
    -- true  = automatically update dig_rank when a wing skill level-up is detected
    --         and the new level maps to a higher rank in WING_SKILL_RANKS table.
    -- false = never change dig_rank automatically; update manually with //ds rank.
}

settings = config.load(defaults)

-- Normalize addon_path: replace all backslashes with forward slashes and
-- ensure it ends with a single '/'. windower.addon_path may use backslashes
-- and may or may not include a trailing separator depending on Windower version.
local ADDON_PATH = windower.addon_path:gsub('\\', '/'):gsub('/*$', '/')

-- ============================================================================
--  CONSTANTS
-- ============================================================================

local BASE_FATIGUE_CAP      = 100   -- baseline digs for rental/Poor chocobo
local HARD_FATIGUE_CAP      = 200   -- game engine ceiling on fatigue cap
-- Minimum wait after /dig before movement is safe (animation + lag buffer)
local DIG_ANIM_SECS = 0

-- Dig rank delay table {area_delay, dig_delay} in seconds
local RANK_DELAYS = {
    ['Amateur']     = {area=60, dig=15},
    ['Recruit']     = {area=55, dig=10},
    ['Initiate']    = {area=50, dig=5},
    ['Novice']      = {area=45, dig=3},
    ['Apprentice']  = {area=40, dig=3},
    ['Journeyman']  = {area=35, dig=3},
    ['Craftsman']   = {area=30, dig=3},
    ['Artisan']     = {area=25, dig=3},
    ['Adept']       = {area=20, dig=3},
    ['Veteran']     = {area=15, dig=3},
    ['Expert']      = {area=10, dig=3},
}
local HYPER_DELAYS = {area=5, dig=3}

-- Automation states
local STATE = {
    IDLE     = 'idle',
    DIGGING  = 'digging',
    MOVING   = 'moving',
    PAUSED   = 'paused',
}

-- Chat message patterns
local MSG = {
    miss         = "You dig and you dig, but find nothing.",
    obtained     = "Obtained: ",
    conquest     = "You discover a cache of beastman resources and receive",
    skillup_rent = "Your chocobo appears to have gained valuable knowledge from this discovery.",
    skillup_own  = " appears to have gained valuable knowledge from this discovery.",
    -- System error messages (red text, different mode)
    wait_longer  = "You must wait longer to perform that action.",
    cannot_dig   = "You cannot dig here.",
    -- Wing skill level-up message pattern (Lua pattern, not plain string)
    -- Uses [^%d]* to skip any color-code bytes the game may insert before the number.
    -- Matches both integer ("20") and potential future decimal ("20.1") formats.
    -- Anchored loosely so leading/trailing escape bytes do not break the match.
    wing_skill_up = "wing skill improved to [^%d]*([%d%.]+)",
}

-- Wing skill rank breakpoints (ordered lowest->highest).
-- These are PLACEHOLDER values until SE publishes official rank thresholds.
-- Edit the min values here once real data is known; everything else updates automatically.
local WING_SKILL_RANKS = {
    {min=0,   rank="Amateur"},
    {min=10,  rank="Recruit"},
    {min=20,  rank="Initiate"},
    {min=30,  rank="Novice"},
    {min=40,  rank="Apprentice"},
    {min=50,  rank="Journeyman"},
    {min=60,  rank="Craftsman"},
    {min=70,  rank="Artisan"},
    {min=80,  rank="Adept"},
    {min=90,  rank="Veteran"},
    {min=100, rank="Expert"},
}

-- Returns the rank name corresponding to a given wing skill level.
-- Walks the table in reverse to find the highest threshold not exceeding the level.
local function wing_skill_rank_for(level)
    local result = WING_SKILL_RANKS[1].rank
    for i = 1, #WING_SKILL_RANKS do
        if level >= WING_SKILL_RANKS[i].min then
            result = WING_SKILL_RANKS[i].rank
        end
    end
    return result
end

-- Debug mode flag -- toggled via //ds debug on/off
local debug_mode = false

-- Chat color codes
local COLOR = {
    info    = 207,  -- white/light
    success = 158,  -- green
    warn    = 167,  -- orange/yellow
    error   = 167,  -- orange/yellow
    header  = 200,  -- bright white
    notice  = 036,  -- sky blue, for informational zone/status messages
}

-- Grade display colors for //ds zonelist
-- Each grade letter maps to a Windower chat color code
local GRADE_COLOR = {
    A = 055,   -- yellow
    B = 158,   -- green
    C = 207,   -- white (acceptable/neutral)
    D = 028,   -- red (undesirable)
    F = 028,   -- red (undesirable)
}

-- Returns a grade string wrapped in its color code, resetting to reset_col after.
-- Grades like "A-", "B+", "C" all key off the first letter.
local function colored_grade(grade, reset_col)
    if grade == 'N/A' then
        return ('N/A'):color(reset_col, reset_col)
    end
    local letter = grade:sub(1, 1):upper()
    local col = GRADE_COLOR[letter] or reset_col
    return grade:color(col, reset_col)
end

-- Diggable zones with skill and profit grades
-- Format: [zone name] = {skill = 'grade', profit = 'grade'}
local DIGGABLE_ZONES = {
    -- ---- Graded zones (skill and profit data available) ----
    ['Eastern Altepa Desert']    = {skill='D-', profit='A'},
    ['Western Altepa Desert']    = {skill='F',  profit='A+'},
    ['Batallia Downs']           = {skill='B+', profit='C-'},
    ['Bhaflau Thickets']         = {skill='C',  profit='A-'},
    ['Bibiki Bay']               = {skill='B',  profit='C'},
    ['Buburimu Peninsula']       = {skill='B',  profit='B-'},
    ["Carpenters' Landing"]      = {skill='B-', profit='C'},  -- apostrophe-after variant
    ["Carpenter's Landing"]      = {skill='B-', profit='C'},  -- apostrophe-before variant
    ['North Gustaberg']          = {skill='B-', profit='B+'},
    ['South Gustaberg']          = {skill='A-', profit='B'},
    ['Jugner Forest']            = {skill='C+', profit='C'},
    ['Konschtat Highlands']      = {skill='C+', profit='B'},
    ['La Theine Plateau']        = {skill='B+', profit='D+'},
    ['Meriphataud Mountains']    = {skill='D',  profit='B+'},
    ['Pashhow Marshlands']       = {skill='C-', profit='C+'},
    ['Rolanberry Fields']        = {skill='F',  profit='B+'},
    ['East Ronfaure']            = {skill='B-', profit='B-'},
    ['West Ronfaure']            = {skill='B',  profit='C'},
    ["The Sanctuary of Zi'Tah"] = {skill='B',  profit='C'},   -- with "The"
    ["Sanctuary of Zi'Tah"]     = {skill='B',  profit='C'},   -- without "The"
    ['East Sarutabaruta']        = {skill='A',  profit='C'},
    ['West Sarutabaruta']        = {skill='A',  profit='B-'},
    ['Sauromugue Champaign']     = {skill='D',  profit='B'},
    ['Tahrongi Canyon']          = {skill='C',  profit='B+'},
    ['Valkurm Dunes']            = {skill='A',  profit='C+'},
    ['Wajaom Woodlands']         = {skill='C',  profit='A-'},
    ['Yhoator Jungle']           = {skill='C-', profit='A'},
    ['Yuhtunga Jungle']          = {skill='C-', profit='A-'},

    -- ---- Ungraded diggable zones (confirmed diggable, no grade data) ----
    ['Attohwa Chasm']            = {skill='N/A', profit='N/A'},
    ['Batallia Downs (S)']       = {skill='N/A', profit='N/A'},
    ['Beaucedine Glacier']       = {skill='N/A', profit='N/A'},
    ['Beaucedine Glacier (S)']   = {skill='N/A', profit='N/A'},
    ["Behemoth's Dominion"]      = {skill='N/A', profit='N/A'},
    ['Caedarva Mire']            = {skill='N/A', profit='N/A'},
    ['Cape Teriggan']            = {skill='N/A', profit='N/A'},
    ['Ceizak Battlegrounds']     = {skill='N/A', profit='N/A'},
    ['Foret de Hennetiel']       = {skill='N/A', profit='N/A'},
    ['Fort Karugo-Narugo (S)']   = {skill='N/A', profit='N/A'},
    ['Grauberg (S)']             = {skill='N/A', profit='N/A'},
    ['Jugner Forest (S)']        = {skill='N/A', profit='N/A'},
    ['Kamihr Drifts']            = {skill='N/A', profit='N/A'},
    ['Lufaise Meadows']          = {skill='N/A', profit='N/A'},
    ['Marjami Ravine']           = {skill='N/A', profit='N/A'},
    ['Meriphataud Mountains (S)']= {skill='N/A', profit='N/A'},
    ['Misareaux Coast']          = {skill='N/A', profit='N/A'},
    ['Morimar Basalt Fields']    = {skill='N/A', profit='N/A'},
    ['North Gustaberg (S)']      = {skill='N/A', profit='N/A'},
    ['Pashhow Marshlands (S)']   = {skill='N/A', profit='N/A'},
    ['Purgonorgo Isle']          = {skill='N/A', profit='N/A'},
    ['Qufim Island']             = {skill='N/A', profit='N/A'},
    ['Rolanberry Fields (S)']    = {skill='N/A', profit='N/A'},
    ['East Ronfaure (S)']        = {skill='N/A', profit='N/A'},
    ['Sauromugue Champaign (S)'] = {skill='N/A', profit='N/A'},
    ['Uleguerand Range']         = {skill='N/A', profit='N/A'},
    ['Valley of Sorrows']        = {skill='N/A', profit='N/A'},
    ['Vunkerl Inlet (S)']        = {skill='N/A', profit='N/A'},
    ['West Sarutabaruta (S)']    = {skill='N/A', profit='N/A'},
    ['Xarcabard']                = {skill='N/A', profit='N/A'},
    ['Xarcabard (S)']            = {skill='N/A', profit='N/A'},
    ['Yahse Hunting Grounds']    = {skill='N/A', profit='N/A'},
    ['Yorcia Weald']             = {skill='N/A', profit='N/A'},
}

-- ============================================================================
--  SESSION STATE
-- ============================================================================

local session = {
    active              = false,
    paused              = false,
    pause_reason        = nil,
    start_time          = nil,
    chocobo_name        = nil,
    is_rental           = true,

    -- Automation state machine
    auto_state          = STATE.IDLE,
    dig_sent_time       = nil,   -- os.clock() when last /dig was sent
    dig_response_rcvd   = false, -- true when we got any dig response this cycle
    last_dig_time       = nil,   -- os.clock() when last successful dig completed
    move_start_pos      = nil,   -- {x,y} before movement started
    move_phase          = 0,     -- 0=not moving, 1=forward only, 2=forward+left
    move_phase_end      = nil,   -- os.clock() when current move phase ends
    move_after_time     = nil,   -- os.clock() time when we're allowed to start moving
    retry_count         = 0,     -- movement retries for current dig spot

    -- Counters
    digs_attempted      = 0,
    items_found         = 0,
    fatigue_spent       = 0,    -- non-greens items found this session
    sky_blue_procs      = 0,    -- Sky Blue Racing Silks procs this session
    wing_skill_ups      = 0,    -- wing skill level-ups received this session
    conquest_points     = 0,    -- conquest point digs this session (counts as success, no fatigue)
    consecutive_misses  = 0,

    -- Calculated limits
    fatigue_cap         = 0,
    time_limit_sec      = 0,
    jp_day_key          = '',   -- JP day key at session start, for midnight crossover detection

    stop_reason         = nil,

    -- Warp ring
    warp_eligible       = false,  -- set true on //ds start, cleared after warp fires
}

-- Track last known player status for dismount detection
local last_player_status = nil

-- Wing skill career stat (persisted to data/<charname>/wing_skill.lua, never resets)
-- level: last confirmed level seen in a skill-up message (number, not integer)
-- total_skill_ups: career count of skill-up messages received
local wing_skill = {
    level           = 0,
    total_skill_ups = 0,
}

-- Cumulative all-time stats (persisted to data/<charname>/cumulative.lua)
local cumulative = {
    total_sessions      = 0,
    total_digs          = 0,
    total_items         = 0,
    total_fatigue_spent = 0,
    total_seconds       = 0,    -- total all-time digging time in seconds
    total_skill_ups     = 0,    -- mirrored from wing_skill.total_skill_ups for report convenience
}

-- Daily stats for the current JP day (persisted to data/<charname>/daily_state.lua)
-- Loaded on session start, updated on session end, reset when JP day rolls over.
local daily = {
    jp_day          = '',   -- YYYY-MM-DD key for the JP day this data belongs to
    total_digs      = 0,    -- all digs this JP day across all sessions
    total_items     = 0,    -- all items found this JP day
    fatigue_spent   = 0,    -- items found that cost fatigue (non-greens)
    sky_blue_procs  = 0,    -- times Sky Blue Racing Silks proc'd this JP day
    total_seconds   = 0,    -- total digging time this JP day in seconds
}

-- ============================================================================
--  UTILITY FUNCTIONS
-- ============================================================================

local function cprint(color, msg)
    windower.add_to_chat(color, '[DigSkill] '..tostring(msg))
end

-- Debug log: only prints when debug_mode is true
local function dlog(msg)
    if debug_mode then
        windower.add_to_chat(COLOR.notice, '[DigSkill DBG] '..tostring(msg))
    end
end

local function elapsed_seconds()
    if not session.start_time then return 0 end
    return os.time() - session.start_time
end

local function elapsed_string()
    local s = elapsed_seconds()
    local m = math.floor(s / 60)
    s = s % 60
    return ('%dm %02ds'):format(m, s)
end

-- Format a raw seconds count into a readable string.
-- Uses h/m/s for large values (cumulative), m/s for smaller (session).
local function format_duration(total_secs)
    total_secs = math.floor(total_secs or 0)
    local h = math.floor(total_secs / 3600)
    local m = math.floor((total_secs % 3600) / 60)
    local s = total_secs % 60
    if h > 0 then
        return ('%dh %dm %02ds'):format(h, m, s)
    else
        return ('%dm %02ds'):format(m, s)
    end
end

local function parse_keep_items()
    local t = S{}
    -- Always keep greens
    t:add('Gysahl Greens')
    -- Parse user setting (comma-separated string or set)
    local raw = settings.keep_items
    if type(raw) == 'string' then
        for item in raw:gmatch('[^,]+') do
            t:add(item:match('^%s*(.-)%s*$')) -- trim whitespace
        end
    end
    return t
end

-- ============================================================================
--  FATIGUE / LIMIT CALCULATIONS
-- ============================================================================

-- JP midnight (00:00 JST) = 10:00 AM EDT (UTC-4) = 11:00 AM EST (UTC-5)
-- Driven by settings.dst; use //ds dst to toggle.
local function jp_reset_hour()
    return settings.dst and 10 or 11
end

local function get_jp_day_key(timestamp)
    -- Convert local time to JP time (JST = UTC+9).
    -- os.time() gives UTC seconds; os.date('*t') gives local wall-clock.
    -- We derive local UTC offset, then shift to JST to get the JP calendar date.
    -- This ensures log files are always named after the JP date, not the local date.
    local local_t  = os.date('*t', timestamp)
    local utc_t    = os.date('!*t', timestamp)  -- '!' prefix = UTC
    -- Local offset from UTC in seconds (positive = east of UTC)
    local utc_offset = os.difftime(
        os.time(local_t),
        os.time(utc_t)
    )
    local JST_OFFSET = 9 * 3600  -- Japan Standard Time = UTC+9
    local jp_timestamp = timestamp + JST_OFFSET - utc_offset
    local jp_t = os.date('*t', jp_timestamp)
    return ('%04d-%02d-%02d'):format(jp_t.year, jp_t.month, jp_t.day)
end

local function get_delays()
    if settings.hyper_campaign then
        return HYPER_DELAYS
    end
    return RANK_DELAYS[settings.dig_rank] or RANK_DELAYS['Amateur']
end

local function get_position()
    local me = windower.ffxi.get_mob_by_target('me')
    if me then return {x=me.x, y=me.y} end
    return nil
end

local function calc_distance(p1, p2)
    if not p1 or not p2 then return 0 end
    return math.sqrt((p2.x-p1.x)^2 + (p2.y-p1.y)^2)
end

local function calculate_fatigue_cap()
    local end_val   = tonumber(settings.chocobo_end_value) or 0
    local end_bonus = math.floor(end_val / 2)
    local silks_bonus = (settings.body_piece == 'Blue Racing Silks') and 50 or 0
    return math.min(BASE_FATIGUE_CAP + end_bonus + silks_bonus, HARD_FATIGUE_CAP)
end

local function calculate_time_limit()
    local mins = tonumber(settings.max_session_minutes) or 60
    if mins <= 0 then
        return math.huge  -- no time limit
    end
    return mins * 60
end

-- ============================================================================
--  INVENTORY FUNCTIONS
-- ============================================================================

local function get_item_count(item_name)
    local inventory = windower.ffxi.get_items(0)
    local name_lower = item_name:lower()
    for _, item in ipairs(inventory) do
        if item.id ~= 0 then
            local res = res_items[item.id]
            if res and res.name:lower() == name_lower then
                return item.count
            end
        end
    end
    return 0
end

local function get_inventory_count()
    local inventory = windower.ffxi.get_items(0)
    local count = 0
    for _, item in ipairs(inventory) do
        if item.id ~= 0 then count = count + 1 end
    end
    return count
end

local function get_inventory_max()
    return windower.ffxi.get_items(0).max
end

local function drop_item(item_name)
    local inventory = windower.ffxi.get_items(0)
    local name_lower = item_name:lower()
    for index, item in pairs(inventory) do
        -- index must be a number (slot index), skip non-slot keys like 'max', 'count'
        if type(index) == 'number' and type(item) == 'table' and item.id and item.id ~= 0 then
            local res = res_items[item.id]
            if res and res.name:lower() == name_lower and item.status == 0 then
                windower.ffxi.drop_item(index, item.count)
                cprint(COLOR.info, item_name..' dropped.')
                return
            end
        end
    end
    cprint(COLOR.warn, 'Could not find '..item_name..' in inventory to drop.')
end

-- ============================================================================
--  DATA PERSISTENCE (cumulative stats)
-- ============================================================================

-- Character name — populated on login or session start.
-- All data files are stored under data/<charname>/ so multiple characters
-- on the same computer each get their own stats and logs.
local char_name = nil

-- Returns the character data directory, e.g. ADDON_PATH..'data/Phayde/'
-- Falls back to 'data/unknown/' if char_name is not yet set.
local function char_data_path()
    return ADDON_PATH..'data/'..(char_name or 'unknown')..'/'
end

local function cumulative_file()   return char_data_path()..'cumulative.lua'   end
local function daily_state_file()  return char_data_path()..'daily_state.lua'  end
local function wing_skill_file()   return char_data_path()..'wing_skill.lua'   end

local function load_lua_table(filepath, target)
    local f = io.open(filepath, 'r')
    if not f then return end
    local text = f:read('*all')
    f:close()
    local fn = loadstring(text)
    if fn then
        local ok, data = pcall(fn)
        if ok and type(data) == 'table' then
            for k, v in pairs(data) do
                target[k] = v
            end
        end
    end
end

local function save_lua_table(filepath, tbl, comment)
    local f = io.open(filepath, 'w')
    if not f then return false end
    if comment then f:write('-- '..comment..'\n') end
    f:write('return {\n')
    for k, v in pairs(tbl) do
        if type(v) == 'string' then
            f:write(('    %s = %q,\n'):format(k, v))
        else
            f:write(('    %s = %s,\n'):format(k, tostring(v)))
        end
    end
    f:write('}\n')
    f:close()
    return true
end

local function load_cumulative()
    load_lua_table(cumulative_file(), cumulative)
end

local function save_cumulative()
    if not save_lua_table(cumulative_file(), cumulative, 'DigSkill all-time cumulative stats') then
        cprint(COLOR.warn, 'Warning: Could not save cumulative stats.')
    end
end

local function load_wing_skill()
    load_lua_table(wing_skill_file(), wing_skill)
end

local function save_wing_skill()
    if not save_lua_table(wing_skill_file(), wing_skill, 'DigSkill wing skill career stat') then
        cprint(COLOR.warn, 'Warning: Could not save wing skill data.')
    end
end

-- Load daily state and reset it if it belongs to a different JP day
local function load_daily_state(current_jp_day)
    load_lua_table(daily_state_file(), daily)
    if daily.jp_day ~= current_jp_day then
        -- New JP day: reset all counters, keep the jp_day key current
        daily.jp_day         = current_jp_day
        daily.total_digs     = 0
        daily.total_items    = 0
        daily.fatigue_spent  = 0
        daily.sky_blue_procs = 0
        daily.total_seconds  = 0
        dlog(('Daily state reset for new JP day: %s'):format(current_jp_day))
    end
end

local function save_daily_state()
    if not save_lua_table(daily_state_file(), daily, 'DigSkill daily state - JP day: '..daily.jp_day) then
        cprint(COLOR.warn, 'Warning: Could not save daily state.')
    end
end

-- ============================================================================
--  SESSION LOG
-- ============================================================================

local function write_session_log()
    local jp_day   = get_jp_day_key(session.start_time)
    local day_file = char_data_path()..'dig logs/log_'..jp_day..'.txt'

    local duration       = elapsed_string()
    local blue_silks     = settings.body_piece == 'Blue Racing Silks'
    local success_rate   = session.digs_attempted > 0
        and ((session.items_found + session.conquest_points) / session.digs_attempted * 100) or 0

    -- Daily running totals AFTER this session (already merged before this call)
    local daily_remain   = math.max(session.fatigue_cap - daily.fatigue_spent, 0)
    local daily_pct      = session.fatigue_cap > 0
        and math.floor(daily.fatigue_spent / session.fatigue_cap * 100) or 0

    local sep = ('='):rep(72)
    local div = ('-'):rep(72)

    -- Append this session block to the day's log file
    local f = io.open(day_file, 'a')
    if not f then
        cprint(COLOR.warn, 'Warning: Could not write session log to: '..day_file)
        cprint(COLOR.warn, ('Check that the "data/%s/dig logs" folder exists in your digskill addon directory.'):format(char_name or 'unknown'))
        return
    end

    f:write(sep..'\n')
    f:write(('SESSION  %s  |  JP Day: %s\n'):format(os.date('%H:%M:%S'), jp_day))
    f:write(('Duration: %s  |  Stop: %s\n'):format(duration, session.stop_reason or 'Unknown'))
    f:write(div..'\n')
    -- Gear / chocobo
    local chocobo_str = session.is_rental and 'Rental'
        or ('Own: %s'):format(session.chocobo_name or 'Unknown')
    f:write(('Chocobo: %s  |  END: %d  |  Body: %s\n'):format(
        chocobo_str, settings.chocobo_end_value, settings.body_piece))
    f:write(('Fatigue Cap: %d  (base 100 + END bonus %d%s)\n'):format(
        session.fatigue_cap,
        math.floor((tonumber(settings.chocobo_end_value) or 0) / 2),
        blue_silks and ' + 50 Blue Silks' or ''))
    f:write(div..'\n')
    -- This session stats
    f:write(('Digs:         %d\n'):format(session.digs_attempted))
    local total_success = session.items_found + session.conquest_points
    f:write(('Items Found:  %d  (%.1f%% success)\n'):format(
        total_success, success_rate))
    if session.conquest_points > 0 then
        f:write(('  (of which %d item digs, %d conquest point digs)\n'):format(
            session.items_found, session.conquest_points))
    end
    f:write(('Fatigue Used: %d  (non-greens items)\n'):format(session.fatigue_spent))
    if session.conquest_points > 0 then
        f:write(('Conquest Digs: %d  (counted as success, fatigue consumed)\n'):format(session.conquest_points))
    end
    if session.sky_blue_procs > 0 then
        f:write(('Sky Blue Procs: %d  (chocobo gained knowledge)\n'):format(session.sky_blue_procs))
    end
    if session.wing_skill_ups > 0 then
        f:write(('Wing Skill Ups: %d  (level now %g)\n'):format(
            session.wing_skill_ups, wing_skill.level))
    end
    f:write(div..'\n')
    -- JP day running totals
    f:write(('JP DAY TOTALS  (%s)\n'):format(jp_day))
    f:write(('Digs: %d  |  Items: %d  |  Fatigue Used: %d / %d  (%d%%)\n'):format(
        daily.total_digs, daily.total_items,
        daily.fatigue_spent, session.fatigue_cap, daily_pct))
    f:write(('Est. Fatigue Remaining: ~%d\n'):format(daily_remain))
    if daily.sky_blue_procs > 0 then
        f:write(('Sky Blue Procs Today: %d\n'):format(daily.sky_blue_procs))
    end
    f:write(sep..'\n\n')
    f:close()

    cprint(COLOR.info, 'Session log saved: '..day_file)
end


-- ============================================================================
--  SESSION CONTROL
-- ============================================================================

local function start_move()
    dlog('Moving: phase 1 (forward only)')
    session.move_start_pos = get_position()
    session.move_phase     = 1
    session.move_phase_end = os.clock() + (tonumber(settings.move_forward_secs) or 0.5)
    windower.send_command('setkey numpad8 down')
end

local function stop_move()
    windower.send_command('setkey numpad8 up')
    windower.send_command('setkey numpad4 up')
    session.move_phase = 0
end

local function send_dig()
    dlog('Dig: sending input /dig command')
    session.dig_sent_time     = os.clock()
    session.dig_response_rcvd = false
    session.digs_attempted    = session.digs_attempted + 1
    session.auto_state        = STATE.DIGGING
    windower.send_command('input /dig')
end

local function stop_session(reason)
    if not session.active then return end

    stop_move()
    session.active      = false
    session.auto_state  = STATE.IDLE
    session.stop_reason = reason

    -- Merge session into daily state
    daily.total_digs     = daily.total_digs    + session.digs_attempted
    daily.total_items    = daily.total_items   + session.items_found
    daily.fatigue_spent  = daily.fatigue_spent + session.fatigue_spent
    daily.sky_blue_procs = daily.sky_blue_procs + session.sky_blue_procs
    daily.total_seconds  = (daily.total_seconds or 0) + elapsed_seconds()
    save_daily_state()

    -- Merge into cumulative all-time
    cumulative.total_sessions      = cumulative.total_sessions + 1
    cumulative.total_digs          = cumulative.total_digs + session.digs_attempted
    cumulative.total_items         = cumulative.total_items + session.items_found
    cumulative.total_fatigue_spent = cumulative.total_fatigue_spent + session.fatigue_spent
    cumulative.total_seconds       = (cumulative.total_seconds or 0) + elapsed_seconds()
    save_cumulative()

    write_session_log()

    -- Print session summary to chat
    local daily_remain = math.max(session.fatigue_cap - daily.fatigue_spent, 0)
    local success_rate = session.digs_attempted > 0
        and math.floor((session.items_found + session.conquest_points) / session.digs_attempted * 100) or 0
    cprint(COLOR.header, ('--- Session Complete: %s ---'):format(reason))
    local total_success = session.items_found + session.conquest_points
    cprint(COLOR.info, ('Duration: %s | Digs: %d | Items: %d (%d%% success)'):format(
        elapsed_string(), session.digs_attempted, total_success, success_rate))
    cprint(COLOR.info, ('Fatigue used today: %d / %d | Est. remaining: ~%d'):format(
        daily.fatigue_spent, session.fatigue_cap, daily_remain))
    if session.conquest_points > 0 then
        cprint(COLOR.info, ('Conquest point digs this session: %d'):format(session.conquest_points))
    end
    if session.sky_blue_procs > 0 then
        cprint(COLOR.info, ('Sky Blue procs this session: %d'):format(session.sky_blue_procs))
    end
    if session.wing_skill_ups > 0 then
        cprint(COLOR.success, ('Wing skill ups this session: %d | Current level: %g'):format(
            session.wing_skill_ups, wing_skill.level))
    end

    -- Auto-dismount: if warp is enabled and the session ended for any reason other than
    -- manual stop or dismount, send /dismount so the warp ring sequence can fire.
    -- Only fires if the player is still mounted (status 5).
    if settings.warp and session.warp_eligible then
        local player = windower.ffxi.get_player()
        if player and player.status == 5 then
            cprint(COLOR.info, 'Auto-warp: dismounting chocobo...')
            windower.send_command('input /dismount')
            -- dismount_watch will detect the status transition and trigger use_warp_ring
        end
    end
end

local function pause_session(reason)
    if not session.active or session.paused then return end
    session.paused       = true
    session.pause_reason = reason
    stop_move()  -- make sure keys are released if we pause mid-movement
    cprint(COLOR.warn, ('--- Session Paused: %s ---'):format(reason))
    cprint(COLOR.warn, 'Use //ds resume to continue or //ds stop to end the session.')
end

-- ============================================================================
--  WARP RING
-- ============================================================================

-- Numeric bag IDs for windower.ffxi.get_items(bag_id) and set_equip()
local WARP_BAG_IDS = {
    inventory=0,
    wardrobe=8,   wardrobe2=9,  wardrobe3=10, wardrobe4=11,
    wardrobe5=12, wardrobe6=13, wardrobe7=14, wardrobe8=15,
}
local WARP_RING_NAME    = 'Warp ring'
local WARP_RING_EQ_SLOT = 13  -- equipment slot ID for rings in set_equip() (resources.slots ring ID)
local WARP_USE_TIMEOUT  = 20  -- seconds to wait for zone change after /item
local WARP_MAX_RETRIES  = 3

-- Searches inventory and wardrobes for the Warp Ring.
-- Returns the raw item table from get_items() plus bag_id and bag_name, or nil.
-- item.slot is the item's real inventory position (used by set_equip).
-- item.status == 5 means already equipped.
local function find_warp_ring()
    local name_lower = WARP_RING_NAME:lower()
    for bag_name, bag_id in pairs(WARP_BAG_IDS) do
        local bag = windower.ffxi.get_items(bag_id)
        if bag then
            for _, item in ipairs(bag) do
                if item.id and item.id ~= 0 then
                    local res = res_items[item.id]
                    if res and res.name:lower() == name_lower then
                        item.bag_id  = bag_id
                        item.bag_name = bag_name
                        return item
                    end
                end
            end
        end
    end
    return nil
end

-- Warp ring coroutine handle (one active at a time)
local warp_coroutine = nil

-- GearSwap slot name for Ring1 (left_ring). Disabling this slot prevents GearSwap
-- from swapping our Warp Ring back out when it applies the idle gear set on dismount.
local WARP_GS_SLOT = 'left_ring'

local function gs_disable_warp_slot()
    windower.send_command('gs disable '..WARP_GS_SLOT)
end

local function gs_enable_warp_slot()
    windower.send_command('gs enable '..WARP_GS_SLOT)
end

-- Equips the Warp Ring using set_equip() (direct API, more reliable than /equip command),
-- disabling GearSwap's ring slot first so it can't override the equip.
-- Polls extdata activation_time until the equip delay clears, then uses it.
-- On each retry, re-checks that the ring is still equipped and re-equips if GearSwap
-- or any other swap has removed it. Re-enables the GearSwap slot when done.
-- Retries /item up to WARP_MAX_RETRIES times if no zone change is detected.
local function use_warp_ring()
    local ring = find_warp_ring()
    if not ring then
        cprint(COLOR.warn, 'Auto-warp: Warp Ring not found in inventory or wardrobes. Skipped.')
        return
    end

    session.warp_eligible = false

    -- Close any prior warp attempt still running
    if warp_coroutine and coroutine.status(warp_coroutine) ~= 'dead' then
        coroutine.close(warp_coroutine)
    end

    warp_coroutine = coroutine.schedule(function()
        -- Disable GearSwap's ring slot immediately so the idle set swap on dismount
        -- cannot override the Warp Ring equip. Matches Smeagol's gs_disable_slot approach.
        gs_disable_warp_slot()

        -- Helper: equip the ring and poll until activation_time clears.
        -- Returns true on success, false on timeout.
        local function equip_and_wait()
            cprint(COLOR.info, 'Auto-warp: equipping Warp Ring...')
            windower.ffxi.set_equip(ring.slot, WARP_RING_EQ_SLOT, ring.bag_id)
            local poll_timeout = 0
            repeat
                coroutine.sleep(1)
                poll_timeout = poll_timeout + 1
                local current = windower.ffxi.get_items(ring.bag_id, ring.slot)
                if current and current.id and current.id ~= 0 then
                    local ok, ext = pcall(extdata.decode, current)
                    if ok and ext then
                        local delay = math.max((ext.activation_time or 0) + 18000 - os.time(), 0)
                        if delay == 0 then return true end
                    end
                end
            until poll_timeout >= 30
            return false
        end

        -- Helper: check if the Warp Ring is currently equipped in the target slot.
        local function warp_ring_is_equipped()
            local r = find_warp_ring()
            return r and r.status == 5
        end

        if not warp_ring_is_equipped() then
            if not equip_and_wait() then
                cprint(COLOR.warn, 'Auto-warp: timed out waiting for equip delay. Please warp manually.')
                gs_enable_warp_slot()
                return
            end
        end

        -- Wait for player status == 0 (idle) with a minimum 3s buffer after equip.
        local status_wait = 0
        repeat
            coroutine.sleep(1)
            status_wait = status_wait + 1
            local p = windower.ffxi.get_player()
            if p and p.status == 0 and status_wait >= 3 then break end
        until status_wait >= 15
        if status_wait >= 15 then
            cprint(COLOR.warn, 'Auto-warp: character not ready after 15s. Please warp manually.')
            gs_enable_warp_slot()
            return
        end

        -- Capture zone ONCE before any use attempt.
        local zone_before = windower.ffxi.get_info().zone

        for attempt = 1, WARP_MAX_RETRIES do
            if windower.ffxi.get_info().zone ~= zone_before then
                cprint(COLOR.success, 'Auto-warp: warped successfully.')
                gs_enable_warp_slot()
                return
            end

            -- Before each attempt confirm the ring is still equipped; re-equip if not.
            if not warp_ring_is_equipped() then
                cprint(COLOR.info, 'Auto-warp: ring no longer equipped, re-equipping...')
                if not equip_and_wait() then
                    cprint(COLOR.warn, 'Auto-warp: could not re-equip Warp Ring. Please warp manually.')
                    gs_enable_warp_slot()
                    return
                end
            end

            if attempt == 1 then
                cprint(COLOR.info, 'Auto-warp: using Warp Ring...')
            else
                cprint(COLOR.info, ('Auto-warp: retrying (%d/%d)...'):format(attempt, WARP_MAX_RETRIES))
            end
            windower.chat.input('/item "Warp ring" <me>')

            local elapsed = 0
            while elapsed < WARP_USE_TIMEOUT do
                coroutine.sleep(1)
                elapsed = elapsed + 1
                if windower.ffxi.get_info().zone ~= zone_before then
                    cprint(COLOR.success, 'Auto-warp: warped successfully.')
                    gs_enable_warp_slot()
                    return
                end
            end

            if attempt == WARP_MAX_RETRIES then
                cprint(COLOR.warn, 'Auto-warp: Warp Ring failed after '..WARP_MAX_RETRIES..' attempts. Please warp manually.')
                gs_enable_warp_slot()
            end
        end
    end, 0)
end

-- Dismount watcher: fires use_warp_ring on the mounted->unmounted transition.
local function dismount_watch()
    local player = windower.ffxi.get_player()
    if not player then return end

    local status = player.status
    if last_player_status == 5 and status ~= 5 then
        if settings.warp and session.warp_eligible then
            use_warp_ring()
        end
    end
    last_player_status = status
end

windower.register_event('prerender', dismount_watch)

local last_status_check = 0

local function status_watch()
    if not session.active or session.paused then return end

    local now = os.clock()
    if now - last_status_check < 2 then return end
    last_status_check = now

    -- Check chocobo mount status
    local player = windower.ffxi.get_player()
    if not player or player.status ~= 5 then
        pause_session('Not mounted on a chocobo. Remount then use //ds resume.')
        return
    end

    -- Check for JP midnight crossover (day changed since session started)
    local current_jp_day = get_jp_day_key(os.time())
    if current_jp_day ~= session.jp_day_key then
        cprint(COLOR.warn, ('JP midnight crossed: day changed from %s to %s.'):format(
            session.jp_day_key, current_jp_day))
        cprint(COLOR.warn, 'Daily fatigue and dig counts have been reset for the new JP day.')
        -- Save the old day's totals, then start fresh for the new day
        save_daily_state()
        session.jp_day_key   = current_jp_day
        daily.jp_day         = current_jp_day
        daily.total_digs     = 0
        daily.total_items    = 0
        daily.fatigue_spent  = 0
        daily.sky_blue_procs = 0
        daily.total_seconds  = 0
        save_daily_state()
        -- No interruption: digging continues unaffected
    end
end

windower.register_event('prerender', status_watch)

local function check_session_limits()
    -- Read time limit live so //ds maxtime changes take effect immediately
    local time_limit = calculate_time_limit()
    local elapsed    = elapsed_seconds()
    if time_limit ~= math.huge and elapsed >= time_limit then
        stop_session('Time limit reached ('..math.floor(time_limit/60)..'m)')
        return false
    end
    -- No hard fatigue stop; 10 consecutive misses triggers a warning instead
    local greens = get_item_count('Gysahl Greens')
    if greens == 0 then
        pause_session('Out of Gysahl Greens. Restock then use //ds resume.')
        return false
    end
    if greens == 10 or greens == 5 then
        cprint(COLOR.error, ('Warning: Low Gysahl Greens -- %d remaining!'):format(greens))
    end
    local player = windower.ffxi.get_player()
    if not player or player.status ~= 5 then
        pause_session('Not mounted on a chocobo. Remount then use //ds resume.')
        return false
    end
    if get_inventory_count() >= get_inventory_max() then
        cprint(COLOR.warn, 'Inventory full! Waiting 10 seconds...')
        session.move_after_time = os.clock() + 10
        return false
    end
    return true
end

--[[
  DIG LOOP STATE MACHINE
  ======================
  States and their meaning:

  IDLE      First dig of session (or after movement). Send /dig when cooldown allows.

  DIGGING   /dig has been sent, waiting for a chat response (miss/obtained/error).
            Hard timeout after 5s in case game swallowed the command.
            On ANY dig response: record last_dig_time, set move_after_time = now + DIG_ANIM_SECS,
            transition to MOVING.

  MOVING    Phase 0: Animation delay - sitting still waiting for DIG_ANIM_SECS to elapse.
                     After animation: if rank delay not yet elapsed, wait (stay in MOVING ph0).
                     Once both animation AND rank delay are done: start keypresses.
            Phase 1: Numpad8 held (forward). After move_forward_secs: add Numpad4.
            Phase 2: Numpad8+4 held. After move_left_secs: release keys, check distance.
                     If distance OK: transition to IDLE (which will immediately send /dig).
                     If distance not OK: retry keypresses.

  NOTE: WAITING state is removed. All cooldown waiting now happens inside MOVING phase 0.
  This ensures movement always happens before the next dig.
--]]

local function dig_loop()
    if not session.active or session.paused then return end

    local now = os.clock()

    -- ===== MOVING PHASE 1: forward only =====
    if session.move_phase == 1 then
        if now >= session.move_phase_end then
            dlog('Moving: phase 1 done, adding left key (phase 2)')
            session.move_phase     = 2
            session.move_phase_end = now + (tonumber(settings.move_left_secs) or 0.5)
            windower.send_command('setkey numpad4 down')
        end
        return
    end

    -- ===== MOVING PHASE 2: forward + left =====
    if session.move_phase == 2 then
        if now >= session.move_phase_end then
            stop_move()
            local dist = calc_distance(session.move_start_pos, get_position())
            dlog(('Moving: done, dist=%.2f (need %.1f)'):format(
                dist, tonumber(settings.min_move_distance) or 1.0))
            if dist >= (tonumber(settings.min_move_distance) or 1.0) then
                session.retry_count = 0
                -- Movement complete - transition to IDLE so we dig immediately
                dlog('Moving: sufficient distance achieved, transitioning to IDLE for next dig')
                session.auto_state = STATE.IDLE
            else
                session.retry_count = session.retry_count + 1
                if session.retry_count >= 5 then
                    cprint(COLOR.warn, 'Warning: Cannot move after 5 attempts. Possibly stuck.')
                    session.retry_count = 0
                end
                dlog(('Moving: insufficient distance, retry #%d'):format(session.retry_count))
                start_move()
            end
        end
        return
    end

    -- ===== DIGGING: waiting for game response =====
    if session.auto_state == STATE.DIGGING then
        -- Hard 5s timeout - if no response, assume the dig happened silently
        if session.dig_sent_time and (now - session.dig_sent_time) >= 5 then
            dlog('Dig: 5s timeout with no response, treating as dig occurred, scheduling move')
            cprint(COLOR.warn, 'No dig response received, proceeding anyway.')
            session.last_dig_time   = now
            session.auto_state      = STATE.MOVING
            session.move_after_time = now + DIG_ANIM_SECS
        end
        return
    end

    -- ===== MOVING PHASE 0: waiting out animation + any remaining rank cooldown =====
    if session.auto_state == STATE.MOVING then
        -- Wait for animation to complete
        if session.move_after_time and now < session.move_after_time then
            dlog(('Moving: waiting for animation/cooldown, %.1fs remaining'):format(
                session.move_after_time - now))
            return
        end
        -- Animation done. Also wait for full rank delay since last dig.
        local delays = get_delays()
        if session.last_dig_time then
            local elapsed = now - session.last_dig_time
            if elapsed < delays.dig then
                -- Rank delay not yet elapsed - extend move_after_time to cover it
                local extra = delays.dig - elapsed
                dlog(('Moving: rank cooldown needs %.1fs more, extending wait'):format(extra))
                session.move_after_time = now + extra
                return
            end
        end
        -- Both animation and rank delay satisfied - run pre-checks then move
        if not check_session_limits() then return end
        dlog('Moving: animation and cooldown done, starting keypresses')
        start_move()
        return
    end

    -- ===== IDLE: send next dig =====
    if session.auto_state == STATE.IDLE then
        -- Gate on dig cooldown (covers wait_longer retries and first-dig timing)
        local delays = get_delays()
        if session.last_dig_time and (now - session.last_dig_time) < delays.dig then
            return
        end
        if not check_session_limits() then return end
        dlog('Dig: idle, sending /dig')
        send_dig()
        return
    end
end

windower.register_event('prerender', dig_loop)

local function start_session()
    -- If a session is paused, block start and direct user to resume or stop
    if session.active and session.paused then
        cprint(COLOR.warn, 'You have a paused session in progress.')
        cprint(COLOR.warn, 'Use //ds resume to continue it, or //ds stop to end it before starting a new one.')
        return
    end

    if session.active then
        cprint(COLOR.warn, 'A session is already active. Use //ds stop first.')
        return
    end

    -- Reload settings to pick up any manual edits
    config.reload(settings)

    -- Check player is mounted on a chocobo (status 5 = mounted)
    local player = windower.ffxi.get_player()
    if not player or player.status ~= 5 then
        cprint(COLOR.error, 'You must be mounted on a chocobo before starting a session!')
        return
    end

    -- Check greens before starting
    local greens = get_item_count('Gysahl Greens')
    if greens == 0 then
        cprint(COLOR.error, 'No Gysahl Greens in inventory! Cannot start.')
        return
    end

    -- Calculate session limits
    local fatigue_cap  = calculate_fatigue_cap()
    local time_limit   = calculate_time_limit()

    -- Load daily state for this JP day (accumulates across sessions)
    local jp_day = get_jp_day_key(os.time())
    load_daily_state(jp_day)

    -- Reset per-session state
    session.active             = true
    session.paused             = false
    session.pause_reason       = nil
    session.start_time         = os.time()
    session.jp_day_key         = jp_day
    session.auto_state         = STATE.IDLE
    session.dig_sent_time      = nil
    session.dig_response_rcvd  = false
    session.last_dig_time      = nil
    session.move_start_pos     = nil
    session.move_phase         = 0
    session.move_phase_end     = nil
    session.move_after_time    = nil
    session.retry_count        = 0

    session.chocobo_name       = nil
    session.is_rental          = true
    session.digs_attempted     = 0
    session.items_found        = 0
    session.fatigue_spent      = 0
    session.sky_blue_procs     = 0
    session.conquest_points     = 0
    session.consecutive_misses = 0
    session.fatigue_cap        = fatigue_cap
    session.time_limit_sec     = time_limit
    session.stop_reason        = nil
    session.warp_eligible      = true   -- cleared after warp fires or until next session
    session.wing_skill_ups      = 0

    local daily_used    = daily.fatigue_spent
    local daily_remain  = math.max(fatigue_cap - daily_used, 0)
    local time_display  = time_limit == math.huge and 'None' or ('%dm'):format(math.floor(time_limit / 60))

    cprint(COLOR.header, '--- DigSkill Session Started ---')
    cprint(COLOR.info, ('JP Day: %s | Fatigue Cap: %d | Time Limit: %s'):format(
        jp_day, fatigue_cap, time_display))
    cprint(COLOR.info, ('Fatigue used today: %d / %d | Est. remaining: ~%d'):format(
        daily_used, fatigue_cap, daily_remain))
    cprint(COLOR.info, ('Body: %s | END: %d | Greens: %d | Drop items: %s'):format(
        settings.body_piece, settings.chocobo_end_value,
        greens, tostring(settings.drop_dug_items)))
    local delays = get_delays()
    cprint(COLOR.info, ('Rank: %s | Dig delay: %ds%s'):format(
        settings.dig_rank, delays.dig,
        settings.hyper_campaign and ' (Hyper Campaign active)' or ''))
    cprint(COLOR.info, ('Auto-warp: %s | Wing skill: %g'):format(
        settings.warp and 'ON' or 'OFF', wing_skill.level))

end

-- ============================================================================
--  CHAT MESSAGE HANDLER
-- ============================================================================

local keep_items_set = nil  -- populated on first use / session start

windower.register_event('incoming text', function(original, modified, original_mode, modified_mode, blocked)
    local msg = original

    -- Skip our own output entirely to avoid feedback loops
    if msg:find('[DigSkill', 1, true) then return end

    -- Log relevant messages in debug mode
    if debug_mode then
        local lower = msg:lower()
        if lower:find('dig') or lower:find('wait longer') or lower:find('cannot') or lower:find('wing skill') then
            local clean = msg:gsub('[^%w%s%p]','')
            cprint(COLOR.notice, ('DBG msg mode=%d [%s]'):format(original_mode, clean:sub(1,60)))
        end
        if lower:find('area') then
            local clean = msg:gsub('[^%w%s%p%[%]:=]','')
            cprint(COLOR.notice, ('DBG zone mode=%d [%s]'):format(original_mode, clean:sub(1,80)))
        end
    end

    -- ---- WING SKILL LEVEL-UP ----
    -- Handled BEFORE the session.active guard so it fires even during manual digging
    -- outside of an active DigSkill session. Wing skill is a career stat.
    -- Pattern tolerant of color code bytes around the number: skips any non-digit
    -- bytes between "to " and the actual number, and doesn't require trailing "!".
    local wing_level_str = msg:match(MSG.wing_skill_up)
    if wing_level_str then
        local new_level = tonumber(wing_level_str)
        if new_level then
            local old_level = wing_skill.level
            wing_skill.level           = new_level
            wing_skill.total_skill_ups = wing_skill.total_skill_ups + 1
            cumulative.total_skill_ups = wing_skill.total_skill_ups
            save_wing_skill()
            save_cumulative()

            -- Update session counter if a session is running
            if session.active then
                session.wing_skill_ups = session.wing_skill_ups + 1
            end

            -- Announce with old and new level
            cprint(COLOR.success, ('Wing skill level up! %g -> %g (Career ups: %d)'):format(
                old_level, new_level, wing_skill.total_skill_ups))

            -- Auto-rank: update dig_rank if the new level maps to a higher rank
            if settings.auto_rank then
                local new_rank = wing_skill_rank_for(new_level)
                if new_rank ~= settings.dig_rank and RANK_DELAYS[new_rank] then
                    local old_rank = settings.dig_rank
                    settings.dig_rank = new_rank
                    config.save(settings)
                    local delays = get_delays()
                    cprint(COLOR.success, ('Auto-rank updated: %s -> %s (dig delay now %ds)'):format(
                        old_rank, new_rank, delays.dig))
                end
            end
        end
        -- Do NOT return here -- wing skill messages don't interfere with session logic
    end

    if not session.active then return end

    -- ---- SYSTEM ERROR: must wait longer ----
    if msg:find(MSG.wait_longer, 1, true) then
        -- Dig didn't fire -- cooldown not elapsed. No animation played.
        -- Go back to IDLE and gate on last_dig_time so we retry after cooldown.
        session.digs_attempted = math.max(session.digs_attempted - 1, 0)
        session.dig_response_rcvd = true
        local delays = get_delays()
        dlog(('Dig: cooldown not elapsed, retrying in %ds'):format(delays.dig))
        cprint(COLOR.info, ('Dig not ready, retrying in %ds.'):format(delays.dig))
        session.last_dig_time = os.clock()  -- will gate IDLE's send_dig
        session.auto_state    = STATE.IDLE
        return
    end

    -- ---- SYSTEM ERROR: cannot dig here ----
    if msg:find(MSG.cannot_dig, 1, true) then
        session.digs_attempted = math.max(session.digs_attempted - 1, 0)
        session.dig_response_rcvd = true
        dlog('Dig: cannot dig here, no animation -- moving immediately')
        cprint(COLOR.info, 'Cannot dig here. Moving...')
        session.auto_state      = STATE.MOVING
        session.move_after_time = os.clock()  -- no animation delay needed
        start_move()
        return
    end

    -- Refresh keep items set lazily
    if not keep_items_set then
        keep_items_set = parse_keep_items()
    end

    -- ---- MISSED DIG ----
    if msg:find(MSG.miss, 1, true) then
        session.consecutive_misses  = session.consecutive_misses + 1
        session.dig_response_rcvd   = true
        session.last_dig_time       = os.clock()
        session.auto_state          = STATE.MOVING
        session.move_after_time     = os.clock() + DIG_ANIM_SECS
        dlog(('Dig: miss #%d, move scheduled in %ds (animation delay)'):format(
            session.consecutive_misses, DIG_ANIM_SECS))
        if session.consecutive_misses >= 10 then
            cprint(COLOR.warn, ('Warning: %d consecutive misses!'):format(session.consecutive_misses))
            cprint(COLOR.warn, 'This may indicate: (1) daily fatigue cap reached, or (2) zone is out of items to dig up.')
            cprint(COLOR.warn, ('Fatigue used today: %d / %d | Consider changing zones if fatigue seems available.'):format(
                daily.fatigue_spent + session.fatigue_spent, session.fatigue_cap))
        end
        return
    end

    -- ---- CONQUEST POINTS DIG ----
    -- Counts as a successful dig: resets consecutive misses and consumes fatigue.
    if msg:find(MSG.conquest, 1, true) then
        session.conquest_points     = session.conquest_points + 1
        session.fatigue_spent       = session.fatigue_spent + 1
        session.consecutive_misses  = 0
        session.dig_response_rcvd   = true
        session.last_dig_time       = os.clock()
        session.auto_state          = STATE.MOVING
        session.move_after_time     = os.clock() + DIG_ANIM_SECS
        dlog(('Dig: conquest points, move scheduled in %ds (animation delay)'):format(DIG_ANIM_SECS))
        cprint(COLOR.info, ('Conquest points received. (Session total: %d)'):format(session.conquest_points))
        return
    end

    -- ---- SUCCESSFUL DIG ----
    if msg:startswith(MSG.obtained) then
        -- Extract item name from "Obtained: <Item>."
        -- FFXI wraps item names in color codes: char(0x1E,0x02) + name + char(0x1E,0x01)
        local raw = msg:sub(#MSG.obtained + 1)
        local opener = string.char(0x1e, 0x02)
        local closer = string.char(0x1e, 0x01)
        local item_name = raw:match(opener..'(.+)'..closer)
        if not item_name then
            -- Fallback: strip non-printable bytes then trailing period
            item_name = raw:gsub('[^%w%s%p]', ''):gsub('[%.%s]+$', ''):match('^%s*(.-)%s*$')
        end

        -- Canonicalize against resources to get exact inventory name
        local item_name_lower = item_name:lower()
        for _, res in pairs(res_items) do
            if res.name:lower() == item_name_lower or
               (res.name_log and res.name_log:lower() == item_name_lower) then
                item_name = res.name
                break
            end
        end

        session.items_found         = session.items_found + 1
        session.consecutive_misses  = 0
        session.dig_response_rcvd   = true
        session.last_dig_time       = os.clock()
        session.auto_state          = STATE.MOVING
        session.move_after_time     = os.clock() + DIG_ANIM_SECS
        dlog(('Dig: obtained [%s], move scheduled in %ds (animation delay)'):format(
            item_name, DIG_ANIM_SECS))

        -- Gysahl Greens don't consume fatigue (they're the cost of digging, not a dig result)
        -- All other items are results of a dig and consume fatigue
        if item_name:lower() ~= 'gysahl greens' then
            session.fatigue_spent = session.fatigue_spent + 1
        end

        -- Save cumulative after every item (crash protection)
        cumulative.total_items = cumulative.total_items + 1
        save_cumulative()

        -- Handle item keep/drop
        -- IMPORTANT: Only drop items during an active dig session while mounted.
        -- This prevents DigSkill from discarding items obtained outside of dig sessions
        -- (e.g. gardening, fishing, NPC rewards).
        local player_now = windower.ffxi.get_player()
        local is_digging = session.active and player_now and player_now.status == 5
        if item_name:lower() == 'gysahl greens' then
            local greens = get_item_count('Gysahl Greens')
            cprint(COLOR.success, ('Gysahl Greens kept. (%d in inventory)'):format(greens))
        elseif is_digging and settings.drop_dug_items then
            if keep_items_set:contains(item_name) then
                cprint(COLOR.success, item_name..' kept.')
            else
                drop_item(item_name)
            end
        else
            cprint(COLOR.success, ('Obtained: %s'):format(item_name))
        end
        return
    end

    -- ---- SKY BLUE RACING SILKS PROC ----
    -- "Your chocobo appears to have gained valuable knowledge" = Sky Blue proc (rental)
    -- "[Name] appears to have gained valuable knowledge"       = Sky Blue proc (own chocobo)
    -- We detect the chocobo name from the own-chocobo variant to set session.chocobo_name.
    if msg:find(MSG.skillup_rent, 1, true) then
        -- Rental chocobo or no name prefix
        session.sky_blue_procs = session.sky_blue_procs + 1
        session.is_rental      = true
        cprint(COLOR.success, ('Sky Blue proc! (Session: %d | Today: %d)'):format(
            session.sky_blue_procs, daily.sky_blue_procs + session.sky_blue_procs))
        return
    end

    if msg:find(MSG.skillup_own, 1, true) and not msg:find(MSG.skillup_rent, 1, true) then
        -- Own chocobo: name precedes the trigger phrase
        local opener = string.char(0x1e, 0x02)
        local closer = string.char(0x1e, 0x01)
        local pos = msg:find(MSG.skillup_own, 1, true)
        local raw_name = msg:sub(1, pos - 1)
        local choco_name = raw_name:match(opener..'(.+)'..closer)
        if not choco_name then
            choco_name = raw_name:gsub('[^%w%s%-]', ''):match('^%s*(.-)%s*$')
        end
        if choco_name and choco_name ~= '' then
            session.chocobo_name = choco_name
            session.is_rental    = false
        end
        session.sky_blue_procs = session.sky_blue_procs + 1
        cprint(COLOR.success, ('Sky Blue proc! %s gained knowledge. (Session: %d | Today: %d)'):format(
            session.chocobo_name or 'Your chocobo',
            session.sky_blue_procs, daily.sky_blue_procs + session.sky_blue_procs))
        return
    end
end)

-- ============================================================================
--  COMMANDS
-- ============================================================================

windower.register_event('addon command', function(...)
    local args = {...}
    local cmd  = (args[1] or ''):lower()

    if cmd == 'start' then
        start_session()

    elseif cmd == 'stop' then
        if session.active then
            stop_session('Manually stopped by user')
        else
            cprint(COLOR.warn, 'No active session to stop.')
        end

    elseif cmd == 'tossitems' then
        settings.drop_dug_items = not settings.drop_dug_items
        config.save(settings)
        if settings.drop_dug_items then
            local keep = settings.keep_items ~= '' and settings.keep_items or '(none)'
            cprint(COLOR.success, 'Drop dug items: ON (keeping: '..keep..')')
        else
            cprint(COLOR.info, 'Drop dug items: OFF (all items kept)')
        end

    elseif cmd == 'warp' then
        settings.warp = not settings.warp
        config.save(settings)
        if settings.warp then
            cprint(COLOR.success, 'Auto-warp: ON (Warp Ring will fire on dismount after a session)')
        else
            cprint(COLOR.info, 'Auto-warp: OFF')
        end

    elseif cmd == 'wingskill' then
        local sub = (args[2] or ''):lower()
        if sub == '' then
            -- Show current wing skill state
            cprint(COLOR.header, '--- Wing Skill ---')
            cprint(COLOR.info, ('Level:       %g'):format(wing_skill.level))
            cprint(COLOR.info, ('Career ups:  %d'):format(wing_skill.total_skill_ups))
            cprint(COLOR.info, ('Mapped rank: %s'):format(wing_skill_rank_for(wing_skill.level)))
            cprint(COLOR.info, ('Auto-rank:   %s'):format(settings.auto_rank and 'ON' or 'OFF'))
            cprint(COLOR.info, 'To set manually: //ds wingskill set <level>')
            cprint(COLOR.info, 'To toggle auto-rank: //ds wingskill autorank')
        elseif sub == 'autorank' then
            settings.auto_rank = not settings.auto_rank
            config.save(settings)
            cprint(settings.auto_rank and COLOR.success or COLOR.info,
                ('Auto-rank: %s'):format(settings.auto_rank and 'ON (dig_rank updates on skill-up)' or 'OFF'))
        elseif sub == 'set' then
            local val = tonumber(args[3])
            if not val then
                cprint(COLOR.warn, 'Usage: //ds wingskill set <level>  (e.g. //ds wingskill set 20)')
            else
                wing_skill.level = val
                save_wing_skill()
                local mapped = wing_skill_rank_for(val)
                cprint(COLOR.success, ('Wing skill set to %g (maps to rank: %s)'):format(val, mapped))
            end
        else
            cprint(COLOR.warn, 'Usage: //ds wingskill | //ds wingskill set <level> | //ds wingskill autorank')
        end

    elseif cmd == 'body' then
        local arg = (args[2] or ''):lower()
        local valid = {
            ['none']           = 'None',
            ['blue']           = 'Blue Racing Silks',
            ['sky']            = 'Sky Blue Racing Silks',
            ['sky blue']       = 'Sky Blue Racing Silks',
            ['blue racing silks']      = 'Blue Racing Silks',
            ['sky blue racing silks']  = 'Sky Blue Racing Silks',
        }
        -- Rejoin args in case they typed "sky blue" as two words
        local full_arg = table.concat({table.unpack(args, 2)}, ' '):lower()
        local body_val = valid[full_arg] or valid[arg]
        if not body_val then
            cprint(COLOR.warn, 'Unknown body piece. Valid options:')
            cprint(COLOR.info, '  //ds body none      - No racing silks')
            cprint(COLOR.info, '  //ds body blue      - Blue Racing Silks (~50% free digs)')
            cprint(COLOR.info, '  //ds body sky       - Sky Blue Racing Silks (~50% bonus skill ups)')
            cprint(COLOR.info, ('Current: %s'):format(settings.body_piece))
        else
            settings.body_piece = body_val
            config.save(settings)
            local fcap = calculate_fatigue_cap()
            cprint(COLOR.success, ('Body piece set to: %s'):format(body_val))
            cprint(COLOR.info, ('Fatigue cap: ~%d'):format(fcap))
        end

    elseif cmd == 'maxtime' then
        local arg = tonumber(args[2])
        if args[2] == nil then
            local tlim = calculate_time_limit()
            local cur = tlim == math.huge and 'None (no time limit)' or ('%d minutes'):format(math.floor(tlim / 60))
            cprint(COLOR.info, ('Max session time: %s'):format(cur))
            cprint(COLOR.info, 'Usage: //ds maxtime <minutes>  (e.g. //ds maxtime 30)')
            cprint(COLOR.info, '       //ds maxtime 0          (disable time limit)')
        elseif arg and arg >= 0 then
            settings.max_session_minutes = arg
            config.save(settings)
            if arg == 0 then
                cprint(COLOR.info, 'Max session time: disabled (session runs until //ds stop)')
            else
                cprint(COLOR.success, ('Max session time set to %d minutes'):format(arg))
            end
            -- Apply immediately to a running session
            if session.active then
                local new_limit = calculate_time_limit()
                session.time_limit_sec = new_limit
                if new_limit ~= math.huge then
                    local elapsed = elapsed_seconds()
                    if elapsed >= new_limit then
                        -- Already past the new limit -- stop now
                        stop_session(('Time limit reduced to %dm (already elapsed)'):format(arg))
                    else
                        local remaining = math.floor((new_limit - elapsed) / 60)
                        cprint(COLOR.info, ('Session time limit updated. ~%d minute(s) remaining.'):format(remaining))
                    end
                else
                    cprint(COLOR.info, 'Session time limit removed. Session will run until //ds stop.')
                end
            end
        else
            cprint(COLOR.warn, 'Invalid value. Usage: //ds maxtime <minutes>  (e.g. //ds maxtime 30)')
        end

    elseif cmd == 'dst' then
        settings.dst = not settings.dst
        config.save(settings)
        local reset = jp_reset_hour()
        if settings.dst then
            cprint(COLOR.success, ('DST: ON (EDT, UTC-4) -- JP midnight = %d:00 AM local time'):format(reset))
        else
            cprint(COLOR.info, ('DST: OFF (EST, UTC-5) -- JP midnight = %d:00 AM local time'):format(reset))
        end
        cprint(COLOR.info, 'JP day key will use the updated offset from next session start.')

    elseif cmd == 'campaign' then
        settings.hyper_campaign = not settings.hyper_campaign
        config.save(settings)
        local delays = get_delays()
        if settings.hyper_campaign then
            cprint(COLOR.success, ('Hyper Campaign: ON (dig delay reduced to %ds)'):format(delays.dig))
        else
            cprint(COLOR.info, ('Hyper Campaign: OFF (dig delay restored to %ds for rank %s)'):format(
                delays.dig, settings.dig_rank))
        end

    elseif cmd == 'pause' then
        if not session.active then
            cprint(COLOR.warn, 'No active session to pause.')
        elseif session.paused then
            cprint(COLOR.warn, 'Session is already paused. Use //ds resume to continue.')
        else
            pause_session('Manually paused by user')
        end

    elseif cmd == 'settings' then
        local delays = get_delays()
        cprint(COLOR.header, '--- DigSkill Settings ---')
        cprint(COLOR.info, ('Rank:            %s'):format(settings.dig_rank))
        cprint(COLOR.info, ('  Dig delay:     %ds%s'):format(
            delays.dig,
            settings.hyper_campaign and ' (Hyper Campaign ON - all delays minimized)' or ''))
        cprint(COLOR.info, ('Drop dug items:  %s'):format(tostring(settings.drop_dug_items)))
        if settings.drop_dug_items then
            local keep = settings.keep_items ~= '' and settings.keep_items or '(none)'
            cprint(COLOR.info, ('  Keep items:    %s'):format(keep))
        end
        cprint(COLOR.info, ('Chocobo body:    %s | END: %d'):format(
            settings.body_piece, settings.chocobo_end_value))
        local fcap = calculate_fatigue_cap()
        local tlim = calculate_time_limit()
        local tlim_str = tlim == math.huge and 'None' or ('%dm'):format(math.floor(tlim / 60))
        cprint(COLOR.info, ('Fatigue cap:     %d  (100 base + %d END bonus%s)'):format(
            fcap,
            math.floor((tonumber(settings.chocobo_end_value) or 0) / 2),
            settings.body_piece == 'Blue Racing Silks' and ' + 50 Blue Silks' or ''))
        cprint(COLOR.info, ('Time limit:      %s | DST: %s (JP midnight = %d:00 AM local)'):format(
            tlim_str,
            settings.dst and 'ON (EDT)' or 'OFF (EST)',
            jp_reset_hour()))
        cprint(COLOR.info, ('Move timing:     %.1fs forward, %.1fs forward+left'):format(
            tonumber(settings.move_forward_secs) or 0.5,
            tonumber(settings.move_left_secs) or 0.5))
        cprint(COLOR.info, ('Hyper Campaign:  %s'):format(tostring(settings.hyper_campaign)))
        cprint(COLOR.info, ('Auto-warp:       %s (//ds warp to toggle)'):format(settings.warp and 'ON' or 'OFF'))
        cprint(COLOR.info, ('Auto-rank:       %s (auto-updates dig_rank on wing skill up)'):format(
            settings.auto_rank and 'ON' or 'OFF'))
        cprint(COLOR.info, ('Wing skill:      %g (career ups: %d)'):format(
            wing_skill.level, wing_skill.total_skill_ups))
        cprint(COLOR.info, ('Debug mode:      %s'):format(debug_mode and 'ON' or 'OFF'))
        cprint(COLOR.info, 'To change rank: //ds rank <RankName>')
        cprint(COLOR.info, 'To edit other settings: edit settings.xml in the addon folder')

    elseif cmd == 'status' then
        if not session.active then
            cprint(COLOR.warn, 'No active session.')
            -- Still show useful environment info
            local player = windower.ffxi.get_player()
            local mounted = player and player.status == 5
            local info   = windower.ffxi.get_info()
            local zone_id = info and info.zone
            local zone_name, zone_data = nil, nil
            if zone_id then
                local res_zones = require('resources').zones
                zone_name = res_zones[zone_id] and res_zones[zone_id].english or ('Zone #'..zone_id)
                zone_data = DIGGABLE_ZONES[zone_name]
            end
            cprint(COLOR.header, '--- Current Environment ---')
            if zone_name then
                if zone_data then
                    cprint(COLOR.notice, ('Zone: %s | Skill: [%s] | Profit: [%s]'):format(
                        zone_name, zone_data.skill, zone_data.profit))
                else
                    cprint(COLOR.info, ('Zone: %s (not a diggable zone)'):format(zone_name))
                end
            end
            cprint(COLOR.info, ('Mounted: %s | Gysahl Greens: %d'):format(
                mounted and 'On chocobo' or 'No chocobo',
                get_item_count('Gysahl Greens')))
            local delays = get_delays()
            cprint(COLOR.info, ('Rank: %s | Dig delay: %ds%s'):format(
                settings.dig_rank, delays.dig,
                settings.hyper_campaign and ' (Hyper Campaign)' or ''))
            -- Show maxtime setting
            local tlim = calculate_time_limit()
            local tlim_str = tlim == math.huge and 'None' or ('%dm'):format(math.floor(tlim / 60))
            cprint(COLOR.info, ('Max session time: %s'):format(tlim_str))
            -- Load daily state to show today's fatigue progress
            local jp_day_now = get_jp_day_key(os.time())
            load_daily_state(jp_day_now)
            local fcap = calculate_fatigue_cap()
            local fat_remain = math.max(fcap - daily.fatigue_spent, 0)
            local fat_pct    = fcap > 0 and math.floor(daily.fatigue_spent / fcap * 100) or 0
            cprint(COLOR.header, ("--- Today's Progress (%s) ---"):format(jp_day_now))
            cprint(COLOR.info, ('Items dug today: %d | Fatigue used: %d / %d (%d%%)'):format(
                daily.total_items, daily.fatigue_spent, fcap, fat_pct))
            cprint(COLOR.info, ('Est. fatigue remaining: ~%d'):format(fat_remain))
            if daily.sky_blue_procs > 0 then
                cprint(COLOR.info, ('Sky Blue procs today: %d'):format(daily.sky_blue_procs))
            end
            -- Total time dug today
            cprint(COLOR.info, ('Total dig time today: %s | Auto-warp: %s'):format(
                format_duration(daily.total_seconds), settings.warp and 'ON' or 'OFF'))
            cprint(COLOR.info, ('Wing skill: %g | Career skill ups: %d'):format(
                wing_skill.level, wing_skill.total_skill_ups))
            return
        end
        local delays = get_delays()
        local state_label = session.paused and ('PAUSED (%s)'):format(session.pause_reason or '?')
                            or session.auto_state:upper()
        cprint(COLOR.header, '--- Current Session Status ---')
        local tlim = session.time_limit_sec
        local tlim_str = tlim == math.huge and 'No limit' or ('%dm'):format(math.floor(tlim / 60))
        cprint(COLOR.info, ('State: %s | Duration: %s | Time Limit: %s'):format(
            state_label, elapsed_string(), tlim_str))
        local conquest_str = session.conquest_points > 0 and (' | Conquest: %d'):format(session.conquest_points) or ''
        cprint(COLOR.info, ('Digs: %d | Items: %d | Session Fatigue: %d | Sky Blue Procs: %d%s'):format(
            session.digs_attempted, session.items_found,
            session.fatigue_spent, session.sky_blue_procs, conquest_str))
        cprint(COLOR.info, ('Greens: %d | Consecutive Misses: %d'):format(
            get_item_count('Gysahl Greens'), session.consecutive_misses))
        local daily_fat_total = daily.fatigue_spent + session.fatigue_spent
        local daily_remain    = math.max(session.fatigue_cap - daily_fat_total, 0)
        local daily_pct       = session.fatigue_cap > 0
            and math.floor(daily_fat_total / session.fatigue_cap * 100) or 0
        cprint(COLOR.info, ('Fatigue today: %d / %d (%d%%) | Est. remaining: ~%d'):format(
            daily_fat_total, session.fatigue_cap, daily_pct, daily_remain))
        cprint(COLOR.info, ('Rank: %s | Dig delay: %ds%s'):format(
            settings.dig_rank, delays.dig,
            settings.hyper_campaign and ' (Hyper)' or ''))
        -- Show total time dug today (prior sessions + current session)
        cprint(COLOR.info, ('Total dig time today: %s | Auto-warp: %s'):format(
            format_duration((daily.total_seconds or 0) + elapsed_seconds()),
            settings.warp and 'ON' or 'OFF'))
        if session.wing_skill_ups > 0 then
            cprint(COLOR.success, ('Wing skill ups this session: %d | Level: %g'):format(
                session.wing_skill_ups, wing_skill.level))
        else
            cprint(COLOR.info, ('Wing skill: %g | Career skill ups: %d'):format(
                wing_skill.level, wing_skill.total_skill_ups))
        end

    elseif cmd == 'report' then
        -- Print today's JP day log file
        local jp_day  = get_jp_day_key(os.time())
        local day_file = char_data_path()..'dig logs/log_'..jp_day..'.txt'
        local f = io.open(day_file, 'r')
        if not f then
            cprint(COLOR.warn, 'No session log found for today ('..jp_day..').')
            return
        end
        local lines = {}
        for line in f:lines() do lines[#lines+1] = line end
        f:close()
        cprint(COLOR.header, '--- Today\'s Session Report ('..jp_day..') ---')
        for i = 1, #lines do
            if lines[i] ~= '' then
                windower.add_to_chat(COLOR.info, lines[i])
            end
        end

    elseif cmd == 'fullreport' then
        -- Scan all daily log files and compile a master cumulative report
        local data_path = char_data_path()..'dig logs/'
        local report_file = data_path..'full_report.txt'

        local day_totals = {}
        local grand_sessions = 0
        local grand_digs     = 0
        local grand_items    = 0
        local grand_fatigue  = 0
        local grand_seconds  = 0

        -- Lua can't glob files, so iterate over all dates from a reasonable start
        local start_year = 2024
        local current_t  = os.date('*t', os.time())

        for year = start_year, current_t.year do
            for month = 1, 12 do
                for day = 1, 31 do
                    local date_str = ('%04d-%02d-%02d'):format(year, month, day)
                    local fn = data_path..'log_'..date_str..'.txt'
                    local lf = io.open(fn, 'r')
                    if lf then
                        local content = lf:read('*all')
                        lf:close()

                        local d_sessions = 0
                        local d_digs     = 0
                        local d_items    = 0
                        local d_fatigue  = 0
                        local d_seconds  = 0

                        -- Parse current log format fields
                        -- Count sessions by SESSION header lines
                        for _ in content:gmatch('SESSION%s+%d+:%d+:%d+') do
                            d_sessions = d_sessions + 1
                        end
                        for v in content:gmatch('Digs:%s+(%d+)') do
                            d_digs = d_digs + tonumber(v)
                        end
                        for v in content:gmatch('Items Found:%s+(%d+)') do
                            d_items = d_items + tonumber(v)
                        end
                        for v in content:gmatch('Fatigue Used:%s+(%d+)') do
                            d_fatigue = d_fatigue + tonumber(v)
                        end
                        -- Parse "Duration: Xm XXs" from each session header
                        for hh, mm, ss in content:gmatch('Duration:%s+(%d+)h%s+(%d+)m%s+(%d+)s') do
                            d_seconds = d_seconds + tonumber(hh)*3600 + tonumber(mm)*60 + tonumber(ss)
                        end
                        for mm, ss in content:gmatch('Duration:%s+(%d+)m%s+(%d+)s') do
                            d_seconds = d_seconds + tonumber(mm)*60 + tonumber(ss)
                        end

                        if d_sessions > 0 then
                            day_totals[#day_totals+1] = {
                                date     = date_str,
                                sessions = d_sessions,
                                digs     = d_digs,
                                items    = d_items,
                                fatigue  = d_fatigue,
                                seconds  = d_seconds,
                                success  = d_digs > 0 and (d_items / d_digs * 100) or 0,
                            }
                            grand_sessions = grand_sessions + d_sessions
                            grand_digs     = grand_digs     + d_digs
                            grand_items    = grand_items    + d_items
                            grand_fatigue  = grand_fatigue  + d_fatigue
                            grand_seconds  = grand_seconds  + d_seconds
                        end
                    end
                end
            end
        end

        if #day_totals == 0 then
            cprint(COLOR.warn, 'No session logs found to compile.')
            return
        end

        -- Write full report file
        local rf = io.open(report_file, 'w')
        if not rf then
            cprint(COLOR.warn, 'Could not write full report file.')
            return
        end

        local sep = ('='):rep(80)
        local div = ('-'):rep(80)

        rf:write(sep..'\n')
        rf:write(('DIGSKILL FULL REPORT  |  Generated: %s\n'):format(os.date('%Y-%m-%d %H:%M:%S')))
        rf:write(sep..'\n\n')

        rf:write('GRAND TOTALS\n')
        rf:write(div..'\n')
        rf:write(('Total JP Days:    %d\n'):format(#day_totals))
        rf:write(('Total Sessions:   %d\n'):format(grand_sessions))
        rf:write(('Total Digs:       %d\n'):format(grand_digs))
        rf:write(('Total Items:      %d  (%.1f%% success rate)\n'):format(
            grand_items, grand_digs > 0 and (grand_items / grand_digs * 100) or 0))
        rf:write(('Total Fatigue:    %d\n'):format(grand_fatigue))
        rf:write(('Total Time:       %s\n'):format(format_duration(grand_seconds)))
        rf:write(('Items/Session:    %.1f\n'):format(
            grand_sessions > 0 and (grand_items / grand_sessions) or 0))
        rf:write('\n')

        rf:write('BREAKDOWN BY JP DAY\n')
        rf:write(div..'\n')
        rf:write(('%-12s  %4s  %5s  %5s  %5s  %8s  %6s\n'):format(
            'Date', 'Sess', 'Digs', 'Items', 'Fatg', 'Time', 'Succ%'))
        rf:write(div..'\n')
        for _, d in ipairs(day_totals) do
            rf:write(('%-12s  %4d  %5d  %5d  %5d  %8s  %5.1f%%\n'):format(
                d.date, d.sessions, d.digs, d.items,
                d.fatigue, format_duration(d.seconds), d.success))
        end
        rf:write(div..'\n')
        rf:write(sep..'\n')
        rf:close()

        -- Also print summary to chat
        cprint(COLOR.header, '--- Full Report Compiled ---')
        cprint(COLOR.info, ('Days: %d | Sessions: %d | Digs: %d | Items: %d | Time: %s'):format(
            #day_totals, grand_sessions, grand_digs, grand_items, format_duration(grand_seconds)))
        cprint(COLOR.info, 'Report saved to: '..report_file)

    elseif cmd == 'cumulative' then
        -- Display all-time cumulative stats from the persisted cumulative.lua
        local c = cumulative
        local success = c.total_digs > 0
            and math.floor(c.total_items / c.total_digs * 100) or 0
        local items_per_session = c.total_sessions > 0
            and string.format('%.1f', c.total_items / c.total_sessions) or '0.0'
        cprint(COLOR.header, '--- DigSkill All-Time Stats ---')
        cprint(COLOR.info, ('Sessions:      %d'):format(c.total_sessions))
        cprint(COLOR.info, ('Total Digs:    %d'):format(c.total_digs))
        cprint(COLOR.info, ('Total Items:   %d  (%d%% success | %s items/session)'):format(
            c.total_items, success, items_per_session))
        cprint(COLOR.info, ('Total Fatigue: %d'):format(c.total_fatigue_spent))
        cprint(COLOR.info, ('Wing Skill:    %g  (career ups: %d)'):format(
            wing_skill.level, wing_skill.total_skill_ups))
        cprint(COLOR.info, ('Total Time:    %s'):format(format_duration(c.total_seconds)))

    elseif cmd == 'rank' then
        local rank_arg = args[2]
        if not rank_arg then
            local delays = get_delays()
            cprint(COLOR.info, ('Current rank: %s (dig delay: %ds%s)'):format(
                settings.dig_rank, delays.dig,
                settings.hyper_campaign and ', Hyper Campaign ON' or ''))
            cprint(COLOR.info, 'Usage: //ds rank <RankName>  (e.g. //ds rank Novice)')
            cprint(COLOR.info, 'Valid ranks: Amateur, Recruit, Initiate, Novice, Apprentice,')
            cprint(COLOR.info, '             Journeyman, Craftsman, Artisan, Adept, Veteran, Expert')
            return
        end
        -- Capitalize first letter, lowercase rest to match table keys
        rank_arg = rank_arg:sub(1,1):upper()..rank_arg:sub(2):lower()
        if RANK_DELAYS[rank_arg] then
            settings.dig_rank = rank_arg
            config.save(settings)
            local delays = get_delays()
            cprint(COLOR.success, ('Rank set to %s (dig delay: %ds)'):format(
                rank_arg, delays.dig))
        else
            cprint(COLOR.warn, ('Unknown rank: "%s". Use //ds rank to see valid options.'):format(rank_arg))
        end

    elseif cmd == 'debug' then
        local arg = (args[2] or ''):lower()
        if arg == 'on' then
            debug_mode = true
            cprint(COLOR.notice, 'Debug mode ON. Verbose state machine logging enabled.')
        elseif arg == 'off' then
            debug_mode = false
            cprint(COLOR.info, 'Debug mode OFF.')
        else
            debug_mode = not debug_mode
            cprint(debug_mode and COLOR.notice or COLOR.info,
                'Debug mode '..(debug_mode and 'ON' or 'OFF')..'.')
        end

    elseif cmd == 'resume' then
        if not session.active then
            cprint(COLOR.warn, 'No active session to resume. Use //ds start to begin one.')
            return
        end
        if not session.paused then
            cprint(COLOR.warn, 'Session is already running.')
            return
        end
        -- Re-check mount and greens before allowing resume
        local player = windower.ffxi.get_player()
        if not player or player.status ~= 5 then
            cprint(COLOR.error, 'You must be mounted on a chocobo to resume.')
            return
        end
        local greens = get_item_count('Gysahl Greens')
        if greens == 0 then
            cprint(COLOR.error, 'You have no Gysahl Greens. Restock before resuming.')
            return
        end
        session.paused             = false
        session.pause_reason       = nil

        session.auto_state         = STATE.IDLE
        session.dig_sent_time      = nil
        session.dig_response_rcvd  = false
        session.move_phase         = 0
        session.retry_count           = 0

        cprint(COLOR.header, '--- Session Resumed ---')
        local daily_fat_total = daily.fatigue_spent + session.fatigue_spent
        local daily_remain    = math.max(session.fatigue_cap - daily_fat_total, 0)
        cprint(COLOR.info, ('Digs: %d | Items: %d | Session Fatigue: %d | Sky Blue Procs: %d'):format(
            session.digs_attempted, session.items_found,
            session.fatigue_spent, session.sky_blue_procs))
        cprint(COLOR.info, ('Fatigue today: %d / %d | Est. remaining: ~%d'):format(
            daily_fat_total, session.fatigue_cap, daily_remain))

    elseif cmd == 'zonelist' then
        -- Separate graded zones from ungraded, sort each group alphabetically
        local graded   = {}
        local ungraded = {}
        -- Skip the secondary spelling variants (kept in table for zone detection,
        -- but we only want the canonical names in the display list)
        local ZONELIST_SKIP = {
            ["Carpenter's Landing"] = true,
            ["Sanctuary of Zi'Tah"] = true,
        }
        local seen = {}
        for name, data in pairs(DIGGABLE_ZONES) do
            if not seen[name] and not ZONELIST_SKIP[name] then
                seen[name] = true
                if data.skill == 'N/A' then
                    ungraded[#ungraded+1] = name
                else
                    graded[#graded+1] = name
                end
            end
        end
        -- Sort graded zones by skill grade (A best -> F worst), then alphabetically
        local GRADE_ORDER = {A=1, B=2, C=3, D=4, F=5}
        table.sort(graded, function(a, b)
            local da = DIGGABLE_ZONES[a]
            local db = DIGGABLE_ZONES[b]
            local la = da.skill:sub(1,1):upper()
            local lb = db.skill:sub(1,1):upper()
            local oa = GRADE_ORDER[la] or 9
            local ob = GRADE_ORDER[lb] or 9
            if oa ~= ob then return oa < ob end
            -- Same letter grade: sort by modifier (+ before none before -)
            local ma = da.skill:sub(2) == '+' and 0 or (da.skill:sub(2) == '-' and 2 or 1)
            local mb = db.skill:sub(2) == '+' and 0 or (db.skill:sub(2) == '-' and 2 or 1)
            if ma ~= mb then return ma < mb end
            return a < b  -- alphabetical tiebreak
        end)
        table.sort(ungraded)

        cprint(COLOR.header, '--- Diggable Zones (Skill / Profit) ---')
        for _, name in ipairs(graded) do
            local data = DIGGABLE_ZONES[name]
            local line = name:color(COLOR.notice, COLOR.info)
                ..' | Skill: '..colored_grade(data.skill, COLOR.info)
                ..' | Profit: '..colored_grade(data.profit, COLOR.info)
            windower.add_to_chat(COLOR.info, line)
        end
        if #ungraded > 0 then
            windower.add_to_chat(COLOR.info, ' ')
            windower.add_to_chat(COLOR.header, '--- Diggable (no grade data) ---')
            -- Print ungraded in rows of 3 to keep it compact
            local row = {}
            for i, name in ipairs(ungraded) do
                row[#row+1] = name:color(COLOR.notice, COLOR.info)
                if #row == 3 or i == #ungraded then
                    windower.add_to_chat(COLOR.info, table.concat(row, '  |  '))
                    row = {}
                end
            end
        end

    elseif cmd == 'help' then
        cprint(COLOR.header, '--- DigSkill Help ---')
        windower.add_to_chat(COLOR.info, '  //ds start          - Begin a digging session')
        windower.add_to_chat(COLOR.info, '  //ds stop           - End the current session and save log')
        windower.add_to_chat(COLOR.info, '  //ds pause          - Pause an active session')
        windower.add_to_chat(COLOR.info, '  //ds resume         - Resume a paused session')
        windower.add_to_chat(COLOR.info, '  //ds status         - Show session stats (or environment info if idle)')
        windower.add_to_chat(COLOR.info, '  //ds settings       - Show all current addon settings')
        windower.add_to_chat(COLOR.info, '  //ds rank [name]    - Show or set dig rank (e.g. //ds rank Novice)')
        windower.add_to_chat(COLOR.info, '  //ds tossitems      - Toggle dropping of unwanted dug items')
        windower.add_to_chat(COLOR.info, '  //ds warp           - Toggle auto-warp home on dismount after session')
        windower.add_to_chat(COLOR.info, '  //ds wingskill      - Show wing skill level, ups, and auto-rank status')
        windower.add_to_chat(COLOR.info, '  //ds wingskill set <n>    - Manually set wing skill level')
        windower.add_to_chat(COLOR.info, '  //ds wingskill autorank   - Toggle auto-rank on skill-up')
        windower.add_to_chat(COLOR.info, '  //ds body [type]    - Set body piece: none / blue / sky')
        windower.add_to_chat(COLOR.info, '  //ds campaign       - Toggle Hyper Campaign mode on/off')
        windower.add_to_chat(COLOR.info, '  //ds dst            - Toggle Daylight Saving Time (EDT/EST) for JP midnight calc')
        windower.add_to_chat(COLOR.info, '  //ds maxtime [min]  - Set max session duration in minutes (0 = no limit)')
        windower.add_to_chat(COLOR.info, '  //ds zonelist       - List all diggable zones with skill/profit grades')
        windower.add_to_chat(COLOR.info, '  //ds report         - Show today\'s JP day session log')
        windower.add_to_chat(COLOR.info, '  //ds fullreport     - Compile all-time report from all daily logs')
        windower.add_to_chat(COLOR.info, '  //ds cumulative     - Show all-time career stats')
        windower.add_to_chat(COLOR.info, '  //ds debug [on/off] - Toggle verbose state machine logging')
        windower.add_to_chat(COLOR.info, '  //ds help           - Show this help text')
        windower.add_to_chat(COLOR.info, 'Shortcut: //ds works for all commands.')
        windower.add_to_chat(COLOR.info, 'Configure via settings.xml in the addon data folder.')

    else
        cprint(COLOR.warn, 'Unknown command. Use //ds help for a list of commands.')
    end
end)

-- ============================================================================
--  ZONE CHANGE DETECTION
-- ============================================================================

local function display_zone_info(zone_id)
    local res_zones = require('resources').zones
    local zone_name = res_zones[zone_id] and res_zones[zone_id].english or ('Zone #'..zone_id)
    local zone_data = DIGGABLE_ZONES[zone_name]
    if zone_data then
        cprint(COLOR.notice, ('Zone: %s | Skill: [%s] | Profit: [%s]'):format(
            zone_name, zone_data.skill, zone_data.profit))
    else
        cprint(COLOR.info, ('Zone: %s (not a diggable zone)'):format(zone_name))
    end
    return zone_name, zone_data
end

windower.register_event('zone change', function(new_id, old_id)
    local zone_name, zone_data = display_zone_info(new_id)
    -- Reset consecutive misses on every zone change -- a fresh zone is a fresh start
    if session.consecutive_misses > 0 then
        session.consecutive_misses = 0
        dlog('Consecutive miss counter reset on zone change.')
    end
    -- If a session is active, pause it (zone changes during automation shouldn't
    -- happen, but handle gracefully in case the user manually zones out)
    if session.active and not session.paused then
        if zone_data then
            pause_session('Zone change to '..zone_name..'. Use //ds resume when ready.')
        else
            pause_session('Zone change to non-diggable zone: '..zone_name)
        end
    end
end)

-- ============================================================================
--  LOAD / UNLOAD
-- ============================================================================

-- Sets char_name, creates the per-character data folder structure,
-- and loads all persistent data for that character.
local function init_char_data(name)
    char_name = name
    -- Create per-character data directories (mkdir is idempotent)
    os.execute('mkdir "'..ADDON_PATH..'data\\'..name..'" >nul 2>&1')
    os.execute('mkdir "'..ADDON_PATH..'data\\'..name..'\\dig logs" >nul 2>&1')
    load_cumulative()
    load_wing_skill()
    load_lua_table(daily_state_file(), daily)
end

windower.register_event('load', function()
    keep_items_set = parse_keep_items()
    -- Try to get character name immediately (works if addon is loaded while already logged in)
    local player = windower.ffxi.get_player()
    if player and player.name and player.name ~= '' then
        init_char_data(player.name)
        cprint(COLOR.info, ('v%s loaded for %s. %d sessions all-time. Wing skill: %g. Type //ds help to get started.'):format(
            _addon.version, char_name, cumulative.total_sessions, wing_skill.level))
    else
        -- Not yet logged in; data will load on the login event below
        cprint(COLOR.info, ('v%s loaded. Waiting for character login to load stats.'):format(_addon.version))
    end
end)

windower.register_event('login', function(name)
    init_char_data(name)
    cprint(COLOR.info, ('Character: %s | %d sessions all-time. Wing skill: %g.'):format(
        char_name, cumulative.total_sessions, wing_skill.level))
end)

windower.register_event('unload', function()
    if session.active then
        stop_session('Addon unloaded')
    end
end)

windower.register_event('logout', function()
    if session.active then
        stop_session('Player logged out')
    end
end)
