_addon.version = '1.0.1'
_addon.name = 'smarttarget'
_addon.author = 'Anonymous; v0.0.4+ by Phayde'
_addon.commands = {'smarttarget','smrt','smart'}

local packets = require('packets')
local config  = require('config')

local defaults = {
    active = true,
    statues_first = false,
    target_non_aggro = false,
    max_distance = 25,
    debug_mode = false,
    switch_hysteresis = 2,
    retarget_window = 2.0,
    retarget_max = 2,
    hp_threshold = 0,
    manual_first_target = false,
    limbus_autostop = false,
    limbus_autostop_cooldown = 3.0,
    limbus_pause_seconds = 6.0,
    list_bias_yalms = 8,
    whitelist = "",
    greylist = "",
    blacklist = "",
}

local settings = config.load(defaults)

-- Split a comma-separated settings string into a clean sequential Lua table.
local function list_from_string(s)
    local out = {}
    if type(s) ~= 'string' or s:gsub('%s','') == '' then return out end
    for token in s:gmatch('[^,]+') do
        local trimmed = token:match('^%s*(.-)%s*$'):lower()
        if trimmed ~= '' then
            out[#out + 1] = trimmed
        end
    end
    return out
end

-- Serialize a list table back to a comma-separated string for saving.
local function list_to_string(t)
    return table.concat(t, ',')
end

-- Forward-declare locals so functions defined below capture these upvalues, not globals.
local active, statues_first, target_non_aggro, max_distance, debug_mode
local switch_hysteresis, retarget_window, retarget_max
local hp_threshold, manual_first_target
local limbus_autostop, limbus_autostop_cooldown, limbus_pause_seconds
local list_bias_yalms, whitelist, greylist, blacklist

-- Save/sync helpers (reference the upvalues declared above).
local function save_settings()
    config.save(settings)
end

local function sync_settings_from_locals()
    settings.active = active
    settings.statues_first = statues_first
    settings.target_non_aggro = target_non_aggro
    settings.max_distance = max_distance
    settings.debug_mode = debug_mode

    settings.switch_hysteresis = switch_hysteresis
    settings.retarget_window = retarget_window
    settings.retarget_max = retarget_max

    settings.hp_threshold = hp_threshold
    settings.manual_first_target = manual_first_target

    settings.limbus_autostop = limbus_autostop
    settings.limbus_autostop_cooldown = limbus_autostop_cooldown
    settings.limbus_pause_seconds = limbus_pause_seconds

    settings.list_bias_yalms = list_bias_yalms
    settings.whitelist = list_to_string(whitelist)
    settings.greylist  = list_to_string(greylist)
    settings.blacklist = list_to_string(blacklist)
end

local function sync_and_save()
    sync_settings_from_locals()
    save_settings()
end

-- Initialise locals from saved settings.
active = settings.active
statues_first = settings.statues_first
target_non_aggro = settings.target_non_aggro
max_distance = settings.max_distance
debug_mode = settings.debug_mode

switch_hysteresis = settings.switch_hysteresis
retarget_window = settings.retarget_window
retarget_max = settings.retarget_max

hp_threshold = settings.hp_threshold
manual_first_target = settings.manual_first_target

limbus_autostop = settings.limbus_autostop
limbus_autostop_cooldown = settings.limbus_autostop_cooldown
limbus_pause_seconds = settings.limbus_pause_seconds

list_bias_yalms = settings.list_bias_yalms
whitelist = list_from_string(settings.whitelist)
greylist  = list_from_string(settings.greylist)
blacklist = list_from_string(settings.blacklist)

-- the rest of the locals that are NOT saved:
local status = 0
local target_id = nil
local desired_target = nil
local recently_departed = nil
local radians_45degrees = math.pi / 4
local retarget_times = {}
local initial_target_lock_id = nil
local limbus_last_autostop_time = 0
local limbus_pause_until = 0
local pending_retarget = false
local pending_retarget_time = 0
local pending_retarget_delay = 0.25
local statues = S{"Impish Statue","Corporal Tombstone","Lithicthrower Image","Incarnation Idol","Goblin Replica","Goblin Statue"}

-- Radius (in yalms) used by //smrt finish to scan for the lowest HP mob.
-- Edit this value to adjust the scan range.
local finish_radius = 10

-- Whole-word, case-insensitive matching helper.
local function escape_lua_pattern(s)
    return (s:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1"))
end

local function contains_whole_phrase(haystack, phrase)
    if not haystack or not phrase then return false end
    haystack = tostring(haystack):lower()
    phrase = tostring(phrase):lower():gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
    if phrase == "" then return false end

    -- "whole phrase" boundary match (frontiers around the phrase start/end)
    local p = escape_lua_pattern(phrase)
    local pat = "%f[%a]" .. p .. "%f[^%a]"
    return haystack:find(pat) ~= nil
end

local function list_distance_adjust(name)
    -- grey overrides whitelist if both match (safer behavior)
    for _,token in ipairs(greylist or {}) do
        if contains_whole_phrase(name, token) then
            return (list_bias_yalms or 0)
        end
    end
    for _,token in ipairs(whitelist or {}) do
        if contains_whole_phrase(name, token) then
            return - (list_bias_yalms or 0)
        end
    end
    return 0
end

-- -----------------------------------------------------------------------------
-- List management helpers
-- -----------------------------------------------------------------------------

-- Returns the name of the list a token already lives in, or nil if not found.
local function find_token_in_lists(token)
    token = tostring(token):lower()
    for _,v in pairs(whitelist or {}) do
        if tostring(v):lower() == token then return 'whitelist', whitelist end
    end
    for _,v in pairs(greylist or {}) do
        if tostring(v):lower() == token then return 'greylist', greylist end
    end
    for _,v in pairs(blacklist or {}) do
        if tostring(v):lower() == token then return 'blacklist', blacklist end
    end
    return nil, nil
end

-- Removes a token from a list table (case-insensitive). Returns true if removed.
local function remove_from_list(lst, token)
    if not lst then return false end
    token = tostring(token):lower()
    for i, v in ipairs(lst) do
        if tostring(v):lower() == token then
            table.remove(lst, i)
            return true
        end
    end
    return false
end

-- Adds a token to a target list, handling cross-list conflicts.
-- list_tbl  : the actual table (whitelist / greylist / blacklist)
-- list_name : human-readable name for messages ("whitelist" etc.)
local function list_add(list_tbl, list_name, token)
    if not token or tostring(token):gsub("%s","") == "" then
        add_chat('Smart Target: please provide a name to add.')
        return
    end
    token = tostring(token):lower()

    -- Check if already on THIS list
    for _,v in ipairs(list_tbl) do
        if tostring(v):lower() == token then
            add_chat('Smart Target: "'..token..'" is already on the '..list_name..'.')
            return
        end
    end

    -- Check if on a DIFFERENT list and auto-move with notification
    local other_name, other_tbl = find_token_in_lists(token)
    if other_name and other_tbl and other_name ~= list_name then
        remove_from_list(other_tbl, token)
        add_chat('Smart Target: "'..token..'" moved from '..other_name..' to '..list_name..'.')
    end

    list_tbl[#list_tbl + 1] = token
    add_chat('Smart Target: "'..token..'" added to '..list_name..'.')
    sync_and_save()
end

-- Removes a token from a target list.
local function list_del(list_tbl, list_name, token)
    if not token or tostring(token):gsub("%s","") == "" then
        add_chat('Smart Target: please provide a name to remove.')
        return
    end
    token = tostring(token):lower()

    if remove_from_list(list_tbl, token) then
        add_chat('Smart Target: "'..token..'" removed from '..list_name..'.')
        sync_and_save()
    else
        add_chat('Smart Target: "'..token..'" was not found on the '..list_name..'.')
    end
end

-- Prints all entries in a list as a comma-separated line.
local function list_print(list_tbl, list_name)
    if not list_tbl or #list_tbl == 0 then
        add_chat('Smart Target: '..list_name..' is empty.')
        return
    end
    add_chat('Smart Target '..list_name..' ('..#list_tbl..'): '..table.concat(list_tbl, ', '))
end

-- Dispatches wlist/glist/blist sub-commands.
-- list_tbl, list_name : the target list and its display name
-- subcmd              : "add" / "del" / "list"
-- token               : the mob name keyword (may be nil for "list")
local function handle_list_command(list_tbl, list_name, subcmd, token)
    if subcmd == 'add' then
        list_add(list_tbl, list_name, token)
    elseif subcmd == 'del' or subcmd == 'remove' or subcmd == 'rm' then
        list_del(list_tbl, list_name, token)
    elseif subcmd == 'list' or subcmd == 'show' or subcmd == 'print' then
        list_print(list_tbl, list_name)
    else
        add_chat('Smart Target: unknown '..list_name..' sub-command "'..tostring(subcmd)..'".')
        add_chat('  Usage: //smrt '..list_name:sub(1,1)..'list add|del|list <name>')
    end
end

-- -----------------------------------------------------------------------------

function is_mob_claimable(mob, player_mob, party)
    if mob.valid_target and mob.is_npc and not mob.charmed and not mob.in_party and not mob.in_alliance and mob.spawn_type == 16 and math.sqrt(mob.distance) <= max_distance then
        if not mob.claim_id or mob.claim_id < 1 then
            return true
        elseif mob.claim_id == player_mob.id then
            return true
        else
            for _,v in pairs(party) do
                if mob.claim_id == v then
                    return true
                end
            end
            return false
        end
    else
        return false
    end
end

function calculate_target_type_rating(mob)
    if recently_departed and mob.id == recently_departed then
        return nil
    end

    if not string.match(mob.name, "Luopan") and (string.match(mob.name, "'s") or string.match(mob.name, "???")) then
        return nil
    end

    for _,v in ipairs(blacklist or {}) do
        if contains_whole_phrase(mob.name, v) then
            return nil
        end
    end

    if statues:contains(mob.name) then
        if statues_first then
            return 0
        else
            return 8
        end
    end
--[[ Legacy Dynamis mob type priorities. Uncomment to restore hardcoded targeting order
     instead of managing priorities via the whitelist/greylist system.
    if string.match(mob.name, "Operative") or string.match(mob.name, "Shinobi") or string.match(mob.name, "Shadowstalker") or string.match(mob.name, "Spy") or string.match(mob.name, "Ninja") or string.match(mob.name, "Hitman") then
        return 10
    end

    if string.match(mob.name, "Animist") or string.match(mob.name, "Tamer") or string.match(mob.name, "Harnesser") or string.match(mob.name, "Empath") or string.match(mob.name, "Beastmaster") or string.match(mob.name, "Pathfinder") then
        return 9
    end

    if string.match(mob.name, "Commander") or string.match(mob.name, "Leader") then
        return 8
    end

    if string.match(mob.name, "Knight") or string.match(mob.name, "Cavalier") or string.match(mob.name, "Champion") or string.match(mob.name, "Banneret") then
        return 7
    end

    if string.match(mob.name, "Fleetfoot") or string.match(mob.name, "Trickster") or string.match(mob.name, "Ruffian") or string.match(mob.name, "Vandal") then
        return 7
    end

    if string.match(mob.name, "Circle") or mob.name == "Agon Halo" then
        return 3
    end

    if mob.name == "Aurix" then
        return 4
    end
]]
    return 5
end

function calculate_target_rating(mob, player_mob, party, not_aggro_okay)
    
    if not is_mob_claimable(mob, player_mob, party) then
        return nil
    end

    local aggro_rating = 0

    if mob.status ~= 1 then
        if debug_mode then
          add_chat('Mob '..mob.name..' ('..mob.id..') not aggro, status '..mob.status)
        end
        if not target_non_aggro and not not_aggro_okay then
            return nil
        else
            aggro_rating = 1
        end
    end

    local type_rating = calculate_target_type_rating(mob)

    if not type_rating then
        if debug_mode then
          add_chat('Mob '..mob.name..' ('..mob.id..') blacklisted')
        end
        return nil
    end

    local distance_rating = math.sqrt(mob.distance)

    if distance_rating <= 5 then
        local angle = math.atan2((mob.y - player_mob.y), (mob.x - player_mob.x)) * -1
        if angle < 0 then
            angle = angle + 2*math.pi
        end
		local diff = math.abs(angle-player_mob.facing)
		if diff > math.pi then
			diff = 2*math.pi - diff
		end
		if diff < radians_45degrees then
            distance_rating = 0
        else
            distance_rating = 1
        end
    end
	-- Apply whitelist/greylist as a distance-equivalent adjustment (in yalms)
    distance_rating = distance_rating + list_distance_adjust(mob.name)

    if debug_mode then
      add_chat('Rated '..mob.name..' ('..mob.id..') at '..(aggro_rating * 10000 + type_rating * 100 + distance_rating))
    end

    return aggro_rating * 10000 + type_rating * 100 + distance_rating
end

local party_member_names = {"p0","p1","p2","p3","p4","p5","a10","a11","a12","a13","a14","a15","a20","a21","a22","a23","a24","a25"}

function get_party()
    local party_table = windower.ffxi.get_party()
    local party = {}

    for _,v in pairs(party_member_names) do
        if party_table and party_table[v] and party_table[v].mob and party_table[v].mob.id then
            party[v] = party_table[v].mob.id
        end
    end

    return party
end

local function better_mob(a, a_rating, b, b_rating)
    if not b then return true end
    if a_rating < b_rating then return true end
    if a_rating > b_rating then return false end

    -- Tie-breaker 1: closer distance wins
    local ad = math.sqrt(a.distance)
    local bd = math.sqrt(b.distance)
    if ad < bd then return true end
    if ad > bd then return false end

    -- Tie-breaker 2: stable ordering by id
    return a.id < b.id
end

local function allow_retarget()
    local now = os.clock()

    -- remove timestamps outside the window
    local kept = {}
    for _,t in ipairs(retarget_times) do
        if (now - t) <= retarget_window then
            kept[#kept+1] = t
        end
    end
    retarget_times = kept

    if #retarget_times >= retarget_max then
        return false
    end

    retarget_times[#retarget_times+1] = now
    return true
end

local function passes_hp_threshold(mob)
    if hp_threshold == nil or hp_threshold <= 0 then
        return true
    end
    if mob.hpp == nil then
        return true
    end
    return mob.hpp >= hp_threshold
end

function find_mob(player_mob, current_target_id)
    local party = get_party()
    local mobs = windower.ffxi.get_mob_array()

    local selected_mob = nil
    local selected_target_rating = nil
    
    if debug_mode then
        add_chat('Finding mob for player with default '..(current_target_id or 0)..' and hp_threshold '..(hp_threshold or 0))
    end

    -- PASS 1: Prefer mobs that meet HP threshold (if enabled)
    local function consider_mob(mob, allow_non_aggro_for_default, enforce_hp)
        if enforce_hp and not passes_hp_threshold(mob) then
            return
        end

        local rating = calculate_target_rating(mob, player_mob, party, allow_non_aggro_for_default and 1 or nil)
        if rating == nil then
            return
        end

        if selected_target_rating == nil then
            selected_mob = mob
            selected_target_rating = rating
            return
        end

        -- Only switch if meaningfully better (hysteresis), otherwise use stable tie-breakers
        if (rating + switch_hysteresis) < selected_target_rating then
            selected_mob = mob
            selected_target_rating = rating
        elseif math.abs(rating - selected_target_rating) <= switch_hysteresis then
            if better_mob(mob, rating, selected_mob, selected_target_rating) then
                selected_mob = mob
                selected_target_rating = rating
            end
        end
    end

    -- Sticky baseline: only keep current/default as baseline if it meets HP threshold (otherwise we try to move off it)
    if current_target_id ~= nil then
        for _,mob in pairs(mobs) do
            if mob.id == current_target_id then
                consider_mob(mob, true, true) -- allow non-aggro for baseline, enforce HP on pass 1
                break
            end
        end
    end

    for _,mob in pairs(mobs) do
        consider_mob(mob, false, true) -- enforce HP on pass 1
    end

    -- PASS 2 (fallback): If nothing met threshold, allow targets below threshold
    if selected_mob == nil and hp_threshold ~= nil and hp_threshold > 0 then
        if debug_mode then
            add_chat('No mobs met HP threshold; falling back to any HP%')
        end

        -- baseline in fallback too
        if current_target_id ~= nil then
            for _,mob in pairs(mobs) do
                if mob.id == current_target_id then
                    consider_mob(mob, true, false)
                    break
                end
            end
        end

        for _,mob in pairs(mobs) do
            consider_mob(mob, false, false)
        end
    end

    return selected_mob
end

function add_chat(s)
    windower.add_to_chat(207, s)
end


local function handle_limbus_units_line(msg)
    if not active or not limbus_autostop then return end
    if not msg then return end

    local lower = tostring(msg):lower()
    lower = lower:gsub("^%b[]%s*", "") -- strips [hh:mm:ss] if present
    if not (lower:find('acquired apollyon units:') or lower:find('acquired temenos units:')) then
        return
    end

    if debug_mode then
        add_chat('DEBUG matched Limbus Units line: '..tostring(msg))
    end

    local now = os.clock()
    if (now - (limbus_last_autostop_time or 0)) < (limbus_autostop_cooldown or 3.0) then
        return
    end
    limbus_last_autostop_time = now

    local player = windower.ffxi.get_player()
    if not player or not player.index then return end
    local player_mob = windower.ffxi.get_mob_by_index(player.index)
    if not player_mob then return end

    add_chat('Smart Target: Limbus completion detected - disengaging.')

    initial_target_lock_id = nil
    desired_target = nil
    recently_departed = nil

	-- Cancel any retarget that was queued from the last kill
    pending_retarget = false
    -- Pause targeting briefly so we don't immediately re-engage anything.
    limbus_pause_until = os.clock() + (limbus_pause_seconds or 6.0)

    disengage_player(player_mob)
end



local function print_status()
    local c0 = string.char(0x1F, 200) -- bright white  (header)
    local c1 = string.char(0x1F, 006) -- yellow        (section labels)
    local c2 = string.char(0x1F, 001) -- white         (values)
    local cr = string.char(0x1F, 207) -- light blue    (reset / default)

    local function onoff(b)
        return b and (string.char(0x1F, 158)..'ON'..cr) or (string.char(0x1F, 167)..'OFF'..cr)
    end

    local wl = #(whitelist or {})
    local gl = #(greylist  or {})
    local bl = #(blacklist or {})

    windower.add_to_chat(200, c0..'---- Smart Target v'.._addon.version..' --------------------------------')
    windower.add_to_chat(207, c1..'  Active        '..cr..': '..onoff(active)
        ..'   '..c1..'Debug'..cr..': '..onoff(debug_mode))
    windower.add_to_chat(207, c1..'  Targeting     '..cr..': '
        ..(target_non_aggro and (string.char(0x1F, 158)..'aggro + non-aggro'..cr) or 'aggro only')
        ..'   '..c1..'Max dist'..cr..': '..c2..tostring(max_distance)..cr..'y')
    windower.add_to_chat(207, c1..'  Statues       '..cr..': '
        ..(statues_first and (string.char(0x1F, 158)..'FIRST'..cr) or 'later')
        ..'   '..c1..'HP threshold'..cr..': '..c2..tostring(hp_threshold or 0)..cr..'%')
    windower.add_to_chat(207, c1..'  Manual first  '..cr..': '..onoff(manual_first_target)
        ..'   '..c1..'Limbus auto-stop'..cr..': '..onoff(limbus_autostop))
    windower.add_to_chat(207, c1..'  Anti-thrash   '..cr..': hysteresis='..c2..tostring(switch_hysteresis)..cr
        ..'  rate='..c2..tostring(retarget_max)..cr..' per '..c2..tostring(retarget_window)..cr..'s')
    windower.add_to_chat(207, c1..'  List bias      '..cr..': '..c2..tostring(list_bias_yalms or 0)..cr..'y'
        ..'   '..c1..'Whitelist'..cr..': '..c2..wl..cr
        ..'  '..c1..'Greylist'..cr..': '..c2..gl..cr
        ..'  '..c1..'Blacklist'..cr..': '..c2..bl..cr)
    windower.add_to_chat(200, c0..'----------------------------------------------------------')
end

local function limbus_is_paused()
    return limbus_autostop and (os.clock() < (limbus_pause_until or 0))
end

-- One-shot command: immediately targets the lowest HP% mob within finish_radius yalms.
-- Bypasses the auto-targeting loop and anti-thrash rate limiter — this is a deliberate
-- manual action. Works even when the addon is toggled off. Respects the blacklist.
local function do_finish()
    local player = windower.ffxi.get_player()
    if not player or not player.index then
        add_chat('Smart Target: could not find player.')
        return
    end
    local player_mob = windower.ffxi.get_mob_by_index(player.index)
    if not player_mob then
        add_chat('Smart Target: could not find player mob.')
        return
    end

    local party = get_party()
    local mobs  = windower.ffxi.get_mob_array()

    local best_mob = nil
    local best_hpp = math.huge

    local function best_finish_mob(mob)
        if math.sqrt(mob.distance) > finish_radius then return end
        if not is_mob_claimable(mob, player_mob, party) then return end
        if mob.status ~= 1 then return end
        if mob.hpp == nil then return end
        for _, v in ipairs(blacklist or {}) do
            if contains_whole_phrase(mob.name, v) then return end
        end
        if mob.hpp < best_hpp then
            best_hpp = mob.hpp
            best_mob = mob
        end
    end

    for _, mob in pairs(mobs) do
        best_finish_mob(mob)
    end

    if not best_mob then
        add_chat('Smart Target: no eligible mob within '..finish_radius..'y.')
        return
    end

    add_chat('Smart Target: finishing on '..best_mob.name..' ('..best_mob.hpp..'% HP)')

    -- Lock onto this mob so the auto-targeting loop doesn't immediately override the selection.
    -- The lock is cleared automatically when the mob dies or the player disengages.
    initial_target_lock_id = best_mob.id

    if status ~= 0 then
        switch_player(player_mob, best_mob)
    else
        engage_player(player_mob, best_mob)
    end
end

function smarttarget_command(...)
    local args = {...}

    if not args[1] then
        active = true
        do_target()
        return
    end

    if args[1] == 'on' then
        add_chat('Smart Target: ON')
        active = true
        target_id = nil
        desired_target = nil
        recently_departed = nil
    elseif args[1] == 'off' then
        add_chat('Smart Target: OFF')
        active = false
        status = 0
        target_id = nil
        desired_target = nil
        recently_departed = nil
        return
    elseif args[1] == 'debug' then
        debug_mode = not debug_mode
		sync_and_save()
        if debug_mode == true then
            add_chat('Smart Target: debug messages enabled')
        else
            add_chat('Smart Target: debug messages disabled')
        end
    elseif args[1] == 'aggro' then
        target_non_aggro = not target_non_aggro
		sync_and_save()
        if target_non_aggro == true then
            add_chat('Smart Target: will target aggro and non-aggro monsters')
        else
            add_chat('Smart Target: will only target aggro monsters')
        end
	elseif args[1] == 'hp' then
		local v = args[2]
		if v == nil then
			add_chat('Smart Target: HP threshold is '..tostring(hp_threshold or 0)..'% (0 = off)')
			return
		end

		if v == 'off' or v == '0' then
			if hp_threshold ~= 0 then
				hp_threshold = 0
				add_chat('Smart Target: HP threshold OFF (will target any HP%)')
				sync_and_save()
			else
				add_chat('Smart Target: HP threshold is already OFF')
			end
			return
		end
		local n = tonumber(v)
		if n == nil then
			add_chat('Smart Target: invalid hp value. Use //smrt hp <0-100> or //smrt hp off')
			return
		end
		if n < 0 then n = 0 end
		if n > 100 then n = 100 end
		n = math.floor(n + 0.5)
		if hp_threshold ~= n then
			hp_threshold = n
			add_chat('Smart Target: HP threshold set to '..hp_threshold..'% (prefers mobs >= threshold; falls back if none)')
			sync_and_save()                  
		else
			add_chat('Smart Target: HP threshold is already '..hp_threshold..'%')
		end
	elseif args[1] == 'first' then
		if not args[2] or args[2] == 'toggle' then
			manual_first_target = not manual_first_target
		elseif args[2] == 'on' then
			manual_first_target = true
		else
			manual_first_target = false
		end

		if manual_first_target then
			add_chat('Smart Target: Manual FIRST target enabled')
		else
			add_chat('Smart Target: Manual FIRST target disabled')
		end
		sync_and_save()
		return
	elseif args[1] == 'status' then
		print_status()
		return
	elseif args[1] == 'limbus' then
		if not args[2] or args[2] == 'toggle' then
			limbus_autostop = not limbus_autostop
		elseif args[2] == 'on' then
			limbus_autostop = true
		else
			limbus_autostop = false
		end

		if limbus_autostop then
			add_chat('Smart Target: Limbus auto-stop ON (will disengage when floor is completed)')
		else
			add_chat('Smart Target: Limbus auto-stop OFF')
		end
		sync_and_save()
		return
	elseif args[1] == 'bias' then
        local v = tonumber(args[2])
        if not v then
            add_chat('Smart Target: list bias is '..tostring(list_bias_yalms or 0)..' yalms')
            return
        end
        if v < 0 then v = 0 end
        list_bias_yalms = math.floor(v + 0.5)
        add_chat('Smart Target: list bias set to '..list_bias_yalms..' yalms')
        sync_and_save()
        return
	elseif string.match(args[1], "stat") then
		if not args[2] or args[2] == 'toggle' then
			statues_first = not statues_first
		elseif args[2] == 'first' then
			statues_first = true
		else
			statues_first = false
		end
		if statues_first then
			add_chat('Smart Target: Statues FIRST')
		else
			add_chat('Smart Target: Statues LATER')
		end
		sync_and_save()
		return

    elseif args[1] == 'finish' then
        do_finish()
        return

    elseif args[1] == 'wlist' then
        handle_list_command(whitelist, 'whitelist', args[2], args[3])
        return
    elseif args[1] == 'glist' then
        handle_list_command(greylist, 'greylist', args[2], args[3])
        return
    elseif args[1] == 'blist' then
        handle_list_command(blacklist, 'blacklist', args[2], args[3])
        return

    else
        local c0 = string.char(0x1F, 200) -- bright white (header)
        local c1 = string.char(0x1F, 006) -- yellow       (commands)
        local c2 = string.char(0x1F, 001) -- white        (args)
        local cr = string.char(0x1F, 207) -- light blue   (reset)
        local function cmd(c, a, d)
            windower.add_to_chat(207, '  '..c1..c..cr..(a ~= '' and ' '..c2..a..cr or '')..'  - '..d)
        end
        windower.add_to_chat(200, c0..'---- Smart Target v'.._addon.version..' Commands --------------------')
        cmd('//smrt',         '',                 'Engage immediately')
        cmd('//smrt on | off',  '',                 'Enable / disable smart targeting')
        cmd('//smrt status',  '',                 'Show current settings')
        cmd('//smrt debug',   '',                 'Toggle debug messages')
        windower.add_to_chat(207, ' ')
        cmd('//smrt aggro',   '',                 'Toggle aggro-only vs all monsters')
        cmd('//smrt stat',    'on | off | toggle',    'Prioritize statues first or later')
        cmd('//smrt hp',      '<0-100 | off>',    'Prefer mobs at or above HP% threshold')
        cmd('//smrt first',   'on | off | toggle',    'Lock your manually chosen first target')
        cmd('//smrt limbus',  'on | off | toggle',    'Auto-disengage on Limbus floor completion')
        cmd('//smrt finish',  '',                     'Swap to lowest HP mob within '..finish_radius..'y (one-shot)')
        windower.add_to_chat(207, ' ')
		cmd('//smrt bias',    '<0-25>',           'Yalm bonus/penalty for whitelist/greylist')
        cmd('//smrt wlist',   'add | del | list <n>', 'Whitelist - preferred targets')
        cmd('//smrt glist',   'add | del | list <n>', 'Greylist  - deprioritized targets')
        cmd('//smrt blist',   'add | del | list <n>', 'Blacklist - ignored targets')
        windower.add_to_chat(200, c0..'--------------------------------------------------------')
        return
    end
end

function facemob(player_mob, mob)
    if not mob then
        return
    end
    if not player_mob then
        return
    end
    windower.ffxi.turn(math.atan2((mob.y - player_mob.y), (mob.x - player_mob.x)) * -1)
end

function disengage_player(player_mob)
    if status == 0 then
        return
    end

    status = 0
    target_id = nil

    if not player_mob then
        return
    end
    
    local p = packets.new('outgoing', 0x01A, {
        ["Target"] = player_mob.id,
        ["Target Index"] = player_mob.index,
        ["Category"] = 0x04 -- Disengage
    })

    packets.inject(p)
end

function engage_player(player_mob, mob)
    if not mob then
        return
    end

    add_chat('Engaging '..mob.name..' ('..mob.id..')')

    local p = packets.new('outgoing', 0x01A, {
        ["Target"] = mob.id,
        ["Target Index"] = mob.index,
        ["Category"] = 0x02 -- Engage Monster
    })

    packets.inject(p)

    status = 2

    facemob(player_mob, mob)
end

function switch_player(player_mob, mob)
    if not mob then
        return
    end

    add_chat('Switching to '..mob.name..' ('..mob.id..')')

    local p = packets.new('outgoing', 0x01A, {
        ["Target"] = mob.id,
        ["Target Index"] = mob.index,
        ["Category"] = 0x0F -- Switch Target
    })

    packets.inject(p)

    status = 2

    facemob(player_mob, mob)
end

function do_target(current_target_id, engage)
    if not active then
        return
    end

    if limbus_is_paused() then
        if debug_mode then
            add_chat('Smart Target: targeting suppressed (Limbus pause)')
        end
        return
    end
	
    if current_target_id and desired_target and current_target_id == desired_target.id and not engage then
        desired_target = nil
        recently_departed = nil
        return
    end

    if debug_mode then
        add_chat('Doing target routine with default '..(current_target_id or 0)..' and engage '..(engage or 0))
    end

    local player_mob = windower.ffxi.get_mob_by_index(windower.ffxi.get_player().index or 0)

    if not player_mob then
        add_chat('No player mob found')
        return
    end

    if debug_mode then
        add_chat('Finding mob')
    end
    local mob = find_mob(player_mob, current_target_id)
    if not mob then
        if debug_mode then
            add_chat('No mob found')
        end
        desired_target = nil
        recently_departed = nil
        if not engage then
            disengage_player(player_mob)
        end
        return
    end

	desired_target = mob

	if status ~= 0 and engage == nil then
		if not allow_retarget() then
			if debug_mode then
				add_chat('Retarget suppressed (rate limit)')
			end
			return
		end
	end

	if status == 0 or engage ~= nil then
		engage_player(player_mob, mob)
	else
		switch_player(player_mob, mob)
	end
end

function mob_died(id, index)
	if initial_target_lock_id and id == initial_target_lock_id then	-- Release manual lock when the mob dies
        initial_target_lock_id = nil
	end
    if target_id == id or (desired_target and desired_target.id == id) then
        target_id = nil
        desired_target = nil
        if status ~= 0 then
            recently_departed = id
            status = 2

            if limbus_autostop then
                pending_retarget = true
                pending_retarget_time = os.clock()
            else
                do_target()
            end
        end
    end
end

function smarttarget_outgoing(id, original, modified, injected, blocked)
    if not active then
        return
    end
    if blocked then
        return
    end
    if injected then
        return
    end
    if id == 0x01A then -- Player action
        local p = packets.parse('outgoing', original)
        if p.Category == 0x02 then -- Engage
    
			if manual_first_target and status == 0 then
				status = 1
				initial_target_lock_id = p.Target
				desired_target = nil
				recently_departed = nil
        -- Allow the original engage packet to go through unmodified
			return false
		end
			status = 1
			do_target(p.Target, 1)
			blocked = true
			return blocked
        elseif p.Category == 0x04 then -- Disengage
			status = 0
			initial_target_lock_id = nil	-- Remove manual target lock on disengage
		end
    end
end

function smarttarget_incoming(id, original, modified, injected, blocked)
    if not active then
        return
    end
    if blocked == true then
        return
    end
    if injected == true then
        return
    end
    
    if id == 0x058 then -- Switch target
        local p = packets.parse('incoming', original)
        target_id = p.Target
        status = 1
        if initial_target_lock_id and p.Target == initial_target_lock_id then
            return
        end
        do_target(p.Target)

    elseif id == 0x02D then -- Monster kill
        local p = packets.parse('incoming', original)
        mob_died(p.Target)

    elseif id == 0x00E then -- NPC update
        local p = packets.parse('incoming', original)
        if (math.floor(p.Mask / 0x20) % 2) ~= 0 then
            mob_died(p.NPC, p.Index)
        elseif (math.floor(p.Mask / 0x04) % 2) ~= 0 then
            if p['HP %'] == 0 then
                mob_died(p.NPC, p.Index)
            end
        end
    end
end

-- Limbus message detector via incoming text.
function smarttarget_incoming_text(original, modified, color, mode, blocked)
    if blocked then return end
    local msg = modified or original
    if not msg or msg == '' then return end

    msg = tostring(msg)

    handle_limbus_units_line(msg)
end

-- Pre-render tick for delayed retarget after a kill.
local function smarttarget_prerender()
    if not pending_retarget then return end

    if (os.clock() - (pending_retarget_time or 0)) < (pending_retarget_delay or 0.25) then
        return
    end

    pending_retarget = false

    -- If the floor-complete message arrived, we'll be paused; do nothing
    if limbus_is_paused() then return end

    -- Otherwise, proceed with normal retarget
    do_target()
end

function smarttarget_zone(new_id, old_id)
    status = 0
    desired_target = nil
    recently_departed = nil
    zone = new_id
	initial_target_lock_id = nil	-- Release manual lock on zone change as a failsafe
end

windower.register_event('addon command', smarttarget_command)
windower.register_event('incoming chunk', smarttarget_incoming)
windower.register_event('incoming text', smarttarget_incoming_text)
windower.register_event('outgoing chunk', smarttarget_outgoing)
windower.register_event('prerender', smarttarget_prerender)
windower.register_event('zone change', smarttarget_zone)
