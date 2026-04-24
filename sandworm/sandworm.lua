_addon.name    = 'sandworm';
_addon.version = '1.0.1';
_addon.author  = 'Phayde';
_addon.commands = { 'sandworm', 'worm' };

require('strings');
require('pack');
local bit      = require('bit');
local config   = require('config');
local texts    = require('texts');
local res      = require('resources');

-- ============================================================
-- ZONE & MOB CONFIGURATION
-- Update target indexes here if testing reveals they are wrong.
-- ============================================================
local WORM_ZONES = {
    -- ['Zone Name'] = { target_index = 0xHEX }
    -- Zone names must match exactly what resources.zones returns (English field).
    ['East Ronfaure [S]']         = { target_index = 0x16D },
    ['North Gustaberg [S]']       = { target_index = 0x179 },
    ['West Sarutabaruta [S]']     = { target_index = 0x180 },
    ['Meriphataud Mountains [S]'] = { target_index = 0x168 },
    ['Batallia Downs [S]']        = { target_index = 0x19D },
    ['Rolanberry Fields [S]']     = { target_index = 0x16D },
    ['Sauromugue Champaign [S]']  = { target_index = 0x115 },
};

-- Ordered rotation sequence for autowarp cycling.
-- Edit this list to change the order zones are visited.
local ZONE_ROTATION = {
    'East Ronfaure [S]',
    'North Gustaberg [S]',
    'West Sarutabaruta [S]',
    'Meriphataud Mountains [S]',
    'Batallia Downs [S]',
    'Rolanberry Fields [S]',
    'Sauromugue Champaign [S]',
};
-- ============================================================
-- MAP GRID CALIBRATION
-- Universal cell size: 161.0 world units per grid square.
-- Per-zone offsets anchor the grid to each zone's coordinate space.
-- Calibrated from two in-game reference points per zone.
-- Formula:
--   col_index = floor((x - x_offset) / GRID_SCALE) + 1  -> letter A=1, B=2...
--   row_index = floor((z_offset - z) / GRID_SCALE) + 1  -> number
-- ============================================================
local GRID_SCALE = 161.0;
local GRID_COL_LETTERS = ' ABCDEFGHIJKLMNOPQRSTUVWXYZ';

local MAP_CALIBRATION = {
    ['East Ronfaure [S]']         = { x_offset = -931.240,   z_offset = 1167.398 },
    ['North Gustaberg [S]']       = { x_offset = -1171.422,  z_offset = 1567.324 },
    ['West Sarutabaruta [S]']     = { x_offset = -1213.478,  z_offset = 1247.248 },
    ['Meriphataud Mountains [S]'] = { x_offset = -1052.293,  z_offset = 1209.379 },
    ['Batallia Downs [S]']        = { x_offset = -1373.301,  z_offset = 1206.796 },
    ['Rolanberry Fields [S]']     = { x_offset = -1335.123,  z_offset = 1250.366 },
    ['Sauromugue Champaign [S]']  = { x_offset = -1333.398,  z_offset = 1287.303 },
};

local function coords_to_grid(zone_name, x, z)
    local cal = MAP_CALIBRATION[zone_name];
    if not cal then return nil; end
    local col_idx = math.floor((x - cal.x_offset) / GRID_SCALE) + 1;
    local row_idx = math.floor((cal.z_offset - z) / GRID_SCALE) + 1;
    if col_idx < 1 or col_idx > 26 or row_idx < 1 then return nil; end
    local col_letter = GRID_COL_LETTERS:sub(col_idx + 1, col_idx + 1);
    return string.format('%s-%d', col_letter, row_idx);
end

-- Spawn window constants (in seconds)
local WINDOW_OPEN_DOOMVOID   = 20 * 3600;   -- 20 hours after Doomvoid
local WINDOW_CLOSE_DOOMVOID  = 25 * 3600;   -- 25 hours after Doomvoid
local WINDOW_OPEN_NORMAL     = 48 * 3600;   -- 48 hours after death
local WINDOW_CLOSE_NORMAL    = 72 * 3600;   -- 72 hours after death
local DESPAWN_TIME           = 1 * 3600;    -- despawns after 1 hour unclaimed

-- Scan timing
local SCAN_INTERVAL         = 30;          -- seconds between scans
local SCAN_COUNT            = 5;           -- number of scans per cycle
local CONFIRM_SCAN_COUNT    = 3;           -- confirmation scans when cross-session change detected
local MOVE_THRESHOLD        = 1.0;         -- units of movement to consider "moved"

-- Navigation
local NAV_CLEAR_DISTANCE    = 10.0;        -- units; hide nav compass when this close

-- Chat color codes (Windower)
local COLOR_INFO   = 207;
local COLOR_ALERT  = 158;  -- bright yellow/orange
local COLOR_WARN   = 167;  -- red-ish
local COLOR_OK     = 204;  -- green-ish

-- ============================================================
-- STATE
-- ============================================================
local state = {
    scanning             = false,
    scan_number          = 0,         -- which scan in the current cycle (1..SCAN_COUNT)
    scan_timer           = nil,
    last_pos             = nil,       -- { x, y, z } from previous scan
    current_pos          = nil,       -- { x, y, z } from latest scan
    pending_index        = nil,       -- target index we're waiting a response for
    pending_id           = nil,       -- full server ID once received
    worm_confirmed       = false,     -- true once movement detected this zone visit
    nav_active           = false,     -- show nav compass?
    nav_target           = nil,       -- { x, z } destination
    tod                  = nil,       -- Unix timestamp (os.time()) of last known death
    tod_type             = nil,       -- 'kill', 'doomvoid', or nil (unknown)
    zone_id              = nil,       -- current zone id
    zone_info            = nil,       -- entry from WORM_ZONES for current zone, or nil
    zone_name            = nil,       -- resolved English name of current zone
    autowarp             = true,      -- automatically warp to next zone after failed scan
    rotation_index       = 1,         -- current position in ZONE_ROTATION
    investigating        = false,     -- true when confirming a cross-session position change
    confirm_scan_number  = 0,         -- how many confirmation scans have run
    confirm_base_pos     = nil,       -- position that triggered investigation
    last_session_ts      = nil,       -- timestamp of last disk scan for current zone
};

-- Per-zone position memory, persists for the session.
-- Keyed by zone name; value is the last known { x, y, z } from any scan.
-- Allows scan 1 on a return visit to immediately detect movement vs the
-- position recorded on the previous visit to that zone.
local zone_last_known = {};
-- ============================================================
local LOG_PATH = windower.addon_path .. 'sandworm_log.csv';
local TOD_PATH = windower.addon_path .. 'sandworm_tod.txt';
local POS_PATH = windower.addon_path .. 'sandworm_positions.csv';

local function log_event(event, zone_name, x, z, notes)
    local f = io.open(LOG_PATH, 'a');
    if f then
        local ts = os.date('%Y-%m-%d %H:%M:%S');
        f:write(string.format('"%s","%s","%s","%.2f","%.2f","%s"\n',
            event, ts, zone_name or '', x or 0, z or 0, notes or ''));
        f:close();
    end
end

-- Load all zone positions from disk.
-- Returns a table keyed by zone name:
--   { x=..., z=..., timestamp=<unix int>, ts_str=<human string> }
local function load_positions()
    local result = {};
    local f = io.open(POS_PATH, 'r');
    if not f then return result; end
    local first = true;
    for line in f:lines() do
        if first then
            first = false; -- skip header
        else
            -- CSV columns: zone, x, z, timestamp, ts_str
            local zone, x, z, ts, ts_str = line:match('^"([^"]*)","([^"]*)","([^"]*)","([^"]*)","([^"]*)"$');
            if zone and x and z and ts then
                result[zone] = {
                    x      = tonumber(x),
                    z      = tonumber(z),
                    timestamp = tonumber(ts),
                    ts_str = ts_str or '',
                };
            end
        end
    end
    f:close();
    return result;
end

-- Save a single zone's position to disk, replacing its existing row.
local function save_position(zone_name, x, z)
    local all = load_positions();
    local ts  = os.time();
    local ts_str = os.date('%Y-%m-%d %H:%M:%S', ts);
    all[zone_name] = { x = x, z = z, timestamp = ts, ts_str = ts_str };

    local f = io.open(POS_PATH, 'w');
    if f then
        f:write('"zone","x","z","timestamp","ts_str"\n');
        for zname, entry in pairs(all) do
            f:write(string.format('"%s","%.4f","%.4f","%d","%s"\n',
                zname, entry.x, entry.z, entry.timestamp, entry.ts_str));
        end
        f:close();
    end
end

local function save_tod(t, tod_type)
    local f = io.open(TOD_PATH, 'w');
    if f then
        f:write(tostring(t) .. '\n' .. (tod_type or 'unknown'));
        f:close();
    end
end

local function load_tod()
    local f = io.open(TOD_PATH, 'r');
    if f then
        local ts_str   = f:read('*l');
        local type_str = f:read('*l');
        f:close();
        return tonumber(ts_str), type_str;
    end
    return nil, nil;
end

local function clear_tod()
    local f = io.open(TOD_PATH, 'w');
    if f then f:write(''); f:close(); end
end

-- Remove a single zone's entry from the positions file and session memory.
-- Called when Doomvoid or death is detected so the next visit isn't a false alert.
local function clear_zone_position(zone_name)
    if not zone_name then return; end
    zone_last_known[zone_name] = nil;
    local all = load_positions();
    if all[zone_name] then
        all[zone_name] = nil;
        local f = io.open(POS_PATH, 'w');
        if f then
            f:write('"zone","x","z","timestamp","ts_str"\n');
            for zname, entry in pairs(all) do
                f:write(string.format('"%s","%.4f","%.4f","%d","%s"\n',
                    zname, entry.x, entry.z, entry.timestamp, entry.ts_str));
            end
            f:close();
        end
    end
end
-- ============================================================
local nav_display_defaults = {
    display = {
        pos   = { x = 640, y = 20 },
        bg    = { red = 0, green = 0, blue = 0, alpha = 160 },
        text  = { font = 'Consolas', size = 13, red = 255, green = 220, blue = 80, alpha = 255 },
    }
};
local nav_box = texts.new('', nav_display_defaults);

local function hide_nav()
    state.nav_active = false;
    state.nav_target = nil;
    nav_box:hide();
end

local function show_nav(wx, wz)
    state.nav_active = true;
    state.nav_target = { x = wx, z = wz };
    nav_box:show();
end

-- ============================================================
-- HELPERS
-- ============================================================
local DIR_LABELS = { 'N','NNE','NE','ENE','E','ESE','SE','SSE','S','SSW','SW','WSW','W','WNW','NW','NNW' };

local function bearing_to_dir(bearing_deg)
    -- bearing: 0 = North, clockwise
    local idx = math.floor((bearing_deg + 11.25) / 22.5) % 16 + 1;
    return DIR_LABELS[idx];
end

local function chat(color, msg)
    windower.add_to_chat(color, '[Sandworm] ' .. msg);
end

local function distance2d(x1, z1, x2, z2)
    local dx = x2 - x1;
    local dz = z2 - z1;
    return math.sqrt(dx * dx + dz * dz);
end

-- FFXI uses a right-handed coordinate system where Z is north/south.
-- Bearing from (px,pz) to (tx,tz):
local function calc_bearing(px, pz, tx, tz)
    local dx = tx - px;
    local dz = tz - pz;  -- positive Z = north in most FFXI zones
    local angle = math.atan2(dx, dz) * (180 / math.pi);
    return (angle + 360) % 360;
end

local function format_time_diff(seconds)
    if seconds < 0 then seconds = -seconds; end
    local h = math.floor(seconds / 3600);
    local m = math.floor((seconds % 3600) / 60);
    return string.format('%dh %02dm', h, m);
end

local function parse_tod_string(str)
    -- Accepts "MM-DD HH:MM" or "now"
    if str:lower() == 'now' then
        return os.time();
    end
    local mo, d, h, mi = str:match('(%d%d)-(%d%d) (%d%d):(%d%d)');
    if mo then
        local now = os.date('*t');
        local t = os.time({ year = now.year, month = tonumber(mo), day = tonumber(d),
                            hour = tonumber(h), min = tonumber(mi), sec = 0 });
        -- Reject timestamps more than 5 minutes in the future
        if t > os.time() + 300 then
            return nil, 'future';
        end
        return t, nil;
    end
    return nil, nil;
end

-- ============================================================
-- WINDOW STATUS
-- ============================================================
local function get_window_status()
    if not state.tod then
        return 'unknown', 'No ToD recorded.';
    end
    local now     = os.time();
    local elapsed = now - state.tod;
    local tod_str = os.date('%m-%d %H:%M', state.tod);
    local ttype   = state.tod_type;  -- 'kill', 'doomvoid', or nil

    -- Helper: format a window open/close message for a single window type
    local function single_window(open_s, close_s, label)
        if elapsed < open_s then
            return 'before', string.format('ToD: %s (%s) | Window opens in %s.',
                tod_str, label, format_time_diff(open_s - elapsed));
        elseif elapsed <= close_s then
            return 'open', string.format('ToD: %s (%s) | Window OPEN. Closes in %s.',
                tod_str, label, format_time_diff(close_s - elapsed));
        else
            return 'expired', string.format('ToD: %s (%s) | Window EXPIRED (%s ago).',
                tod_str, label, format_time_diff(elapsed - close_s));
        end
    end

    if ttype == 'doomvoid' then
        return single_window(WINDOW_OPEN_DOOMVOID, WINDOW_CLOSE_DOOMVOID, 'Doomvoid');

    elseif ttype == 'kill' then
        return single_window(WINDOW_OPEN_NORMAL, WINDOW_CLOSE_NORMAL, 'kill');

    else
        -- Unknown type - show both windows
        if elapsed < WINDOW_OPEN_DOOMVOID then
            return 'before', string.format(
                'ToD: %s | Window opens in %s (Doomvoid 20-25h) / %s (normal 48-72h)',
                tod_str,
                format_time_diff(WINDOW_OPEN_DOOMVOID - elapsed),
                format_time_diff(WINDOW_OPEN_NORMAL - elapsed));
        elseif elapsed < WINDOW_CLOSE_DOOMVOID then
            return 'doomvoid', string.format(
                'ToD: %s | Doomvoid window OPEN (closes in %s). Normal window opens in %s.',
                tod_str,
                format_time_diff(WINDOW_CLOSE_DOOMVOID - elapsed),
                format_time_diff(WINDOW_OPEN_NORMAL - elapsed));
        elseif elapsed < WINDOW_OPEN_NORMAL then
            return 'doomvoid_closed', string.format(
                'ToD: %s | Doomvoid window closed. Normal window opens in %s.',
                tod_str, format_time_diff(WINDOW_OPEN_NORMAL - elapsed));
        elseif elapsed <= WINDOW_CLOSE_NORMAL then
            return 'open', string.format(
                'ToD: %s | Normal window OPEN. Closes in %s.',
                tod_str, format_time_diff(WINDOW_CLOSE_NORMAL - elapsed));
        else
            return 'expired', string.format(
                'ToD: %s | Window EXPIRED (%s ago).',
                tod_str, format_time_diff(elapsed - WINDOW_CLOSE_NORMAL));
        end
    end
end

-- ============================================================
-- SCANNING
-- ============================================================
local function send_scan(target_index)
    -- Inject an outgoing scan packet identical to ScanZone's approach
    windower.packets.inject_outgoing(
        0x16,
        string.char(
            0x16, 0x08, 0x00, 0x00,
            (target_index % 256),
            math.floor(target_index / 256),
            0x00, 0x00
        )
    );
    state.pending_index = target_index;
end

local function positions_differ(p1, p2)
    if p1 == nil or p2 == nil then return false; end
    return distance2d(p1.x, p1.z, p2.x, p2.z) > MOVE_THRESHOLD;
end

local function alert_worm_found(pos)
    local zone_name = state.zone_info and state.zone_info.name or 'Unknown Zone';
    local grid = coords_to_grid(zone_name, pos.x, pos.z);
    local grid_str = grid and ('  Map: ' .. grid) or '';
    chat(COLOR_ALERT, string.format('*** SANDWORM DETECTED in %s! ***', zone_name));
    chat(COLOR_ALERT, string.format('Position: (%.2f, %.2f, %.2f)%s  |  Go NOW!', pos.x, pos.y, pos.z, grid_str));

    -- Play a sound using windower's built-in bell or a wav if available
    windower.play_sound(windower.addon_path .. 'alert.wav');

    -- Activate navigation compass
    show_nav(pos.x, pos.z);

    -- Log it
    log_event('DETECTED', zone_name, pos.x, pos.z, grid or 'grid unknown');
end

local do_scan_cycle  -- forward declare

local function schedule_next_scan()
    if state.scan_number >= SCAN_COUNT then
        -- Cycle complete, worm not confirmed here
        state.scanning = false;
        state.scan_number = 0;
        if not state.worm_confirmed then
            chat(COLOR_INFO, string.format('Scan complete. Sandworm not detected in %s.',
                state.zone_info and state.zone_info.name or 'this zone'));
        end
        return;
    end

    -- Schedule next scan
    state.scan_timer = windower.register_event('time change', function()
        -- We use a countdown trick via prerender instead; see prerender handler
    end);

    -- Use a simple counter-based delay via the prerender tick
    state._scan_countdown = SCAN_INTERVAL;
end

-- Because Windower Lua doesn't have a native sleep/setTimeout, we drive
-- the scan delay from the prerender event using a frame counter converted
-- to seconds via os.clock() delta.
local _last_tick = os.clock();
local _scan_wait_remaining = 0;
local _waiting_for_scan = false;

local function start_scan_wait(seconds)
    _last_tick = os.clock();
    _scan_wait_remaining = seconds;
    _waiting_for_scan = true;
end

local function perform_single_scan()
    _waiting_for_scan = false;
    if not state.zone_info then return; end
    state.scan_number = state.scan_number + 1;
    chat(COLOR_INFO, string.format('Scanning (%d/%d)...', state.scan_number, SCAN_COUNT));
    send_scan(state.zone_info.target_index);
    -- Response will arrive in incoming chunk 0x0E handler
end

local function autowarp_to_next()
    -- Advance rotation index, wrapping back to 1 after the last zone
    state.rotation_index = (state.rotation_index % #ZONE_ROTATION) + 1;
    local next_zone = ZONE_ROTATION[state.rotation_index];
    chat(COLOR_INFO, string.format('Warping to next zone: %s', next_zone));
    windower.send_command('sw sg ' .. next_zone);
end

-- Entry point for a full cycle
local function begin_scan_cycle()
    if not state.zone_info then
        chat(COLOR_WARN, 'Not in a Sandworm zone.');
        return;
    end

    local status, msg = get_window_status();
    if status == 'before' then
        chat(COLOR_WARN, 'Spawn window not yet open. ' .. msg);
        -- still allow scanning in case window calc is off; just warn
    else
        chat(COLOR_OK, msg);
    end

    state.scanning            = true;
    state.scan_number         = 0;
    state.last_pos            = nil;
    state.current_pos         = nil;
    state.worm_confirmed      = false;
    state.investigating       = false;
    state.confirm_scan_number = 0;
    state.confirm_base_pos    = nil;
    state.last_session_ts     = nil;

    chat(COLOR_INFO, string.format('Starting scan cycle in %s (%d scans, %ds apart).',
        state.zone_info.name, SCAN_COUNT, SCAN_INTERVAL));

    -- Kick off first scan immediately
    perform_single_scan();
end

-- ============================================================
-- INCOMING CHUNK - packet handler
-- ============================================================
windower.register_event('incoming chunk', function(id, original, modified, injected, blocked)

    -- 0x0E = Entity Update packet
    if id == 0x0E then
        local target_index = original:unpack('h', 0x08 + 1);

        -- Is this a response to our pending scan?
        if state.scanning and state.pending_index and target_index == state.pending_index then
            state.pending_index = nil;

            local updatemask = original:unpack('b', 0x0A + 1);
            local full_id    = original:unpack('I', 0x04 + 1);
            state.pending_id = full_id;

            local new_pos = nil;

            -- Bit 0x01 = position update
            if updatemask and bit.band(updatemask, 0x01) == 0x01 then
                local x, z, y = original:unpack('fff', 0x0C + 1);
                if x and z and y then
                    new_pos = { x = x, y = y, z = z };
                end
            end

            -- Bit 0x04 = status update (check for death)
            if updatemask and bit.band(updatemask, 0x04) == 0x04 then
                local hpp, animation, status_byte = original:unpack('ccc', 0x1E + 1);
                -- status 2 = dead in FFXI packet convention
                if status_byte and status_byte == 2 then
                    state.tod      = os.time();
                    state.tod_type = 'kill';
                    save_tod(state.tod, state.tod_type);
                    local zone_name = state.zone_info and state.zone_info.name or 'Unknown';
                    chat(COLOR_WARN, string.format('Sandworm killed! ToD recorded: %s (48-72h window)',
                        os.date('%m-%d %H:%M', state.tod)));
                    clear_zone_position(zone_name);
                    log_event('DEATH_KILL', zone_name, 0, 0, 'Auto-detected via status packet');
                end
            end

            -- Process position
            if new_pos then
                local prev = state.current_pos;
                state.last_pos    = prev;
                state.current_pos = new_pos;

                local zone_name  = state.zone_info and state.zone_info.name or nil;
                local historical = zone_name and zone_last_known[zone_name] or nil;

                -- Always update session memory with latest position
                if zone_name then
                    zone_last_known[zone_name] = new_pos;
                end

                -- Always write the latest position to disk
                if zone_name then
                    save_position(zone_name, new_pos.x, new_pos.z);
                end

                -- -----------------------------------------------
                -- INVESTIGATING STATE: confirming cross-session change
                -- -----------------------------------------------
                if state.investigating then
                    state.confirm_scan_number = state.confirm_scan_number + 1;

                    if positions_differ(state.confirm_base_pos, new_pos) then
                        -- Moved again during confirmation - worm is actively roaming
                        chat(COLOR_ALERT, 'Confirmation scan: position changed again - worm is actively roaming!');
                        state.investigating = false;
                        state.worm_confirmed = true;
                        state.scanning = false;
                        alert_worm_found(new_pos);
                    else
                        chat(COLOR_INFO, string.format(
                            'Confirmation scan %d/%d: position unchanged.',
                            state.confirm_scan_number, CONFIRM_SCAN_COUNT));

                        if state.confirm_scan_number < CONFIRM_SCAN_COUNT then
                            start_scan_wait(SCAN_INTERVAL);
                        else
                            -- All confirmation scans stable - conclude external kill
                            state.investigating = false;
                            state.scanning = false;

                            local last_ts  = state.last_session_ts or 0;
                            local now_ts   = os.time();
                            local mid_ts   = math.floor((last_ts + now_ts) / 2);
                            local last_str = os.date('%m-%d %H:%M', last_ts);
                            local now_str  = os.date('%m-%d %H:%M', now_ts);
                            local mid_str  = os.date('%m-%d %H:%M', mid_ts);

                            chat(COLOR_WARN, string.format(
                                'Position changed in %s but worm is not actively moving.', zone_name or 'this zone'));
                            chat(COLOR_WARN, 'Conclusion: Sandworm was likely killed by another player.');
                            chat(COLOR_WARN, string.format(
                                'It died some time between %s (last scan) and %s (now).', last_str, now_str));
                            chat(COLOR_WARN, string.format(
                                'Suggested ToD: %s (midpoint). Set with: //worm tod %s',
                                mid_str, os.date('%m-%d %H:%M', mid_ts)));
                            chat(COLOR_WARN, 'Saved ToD has been cleared. Use //worm tod to set manually.');

                            -- Clear ToD since it is no longer valid
                            state.tod = nil;
                            clear_tod();

                            log_event('EXT_KILL', zone_name or '', new_pos.x, new_pos.z,
                                string.format('between %s and %s', last_str, now_str));

                            if state.autowarp then
                                chat(COLOR_INFO, 'Warping to next zone in 5 seconds...');
                                start_scan_wait(5);
                                state._autowarp_pending = true;
                            end
                        end
                    end

                -- -----------------------------------------------
                -- NORMAL SCAN 1: compare vs session memory and disk
                -- -----------------------------------------------
                elseif state.scan_number == 1 then
                    -- Check session memory first (previous visit this session)
                    local changed_pos  = nil;
                    local changed_from = nil;
                    local changed_ts   = nil;

                    if historical and positions_differ(historical, new_pos) then
                        changed_pos  = new_pos;
                        changed_from = 'previous visit this session';
                        changed_ts   = nil;  -- no timestamp for session memory
                    else
                        -- Check disk (cross-session comparison)
                        local disk_positions = load_positions();
                        local disk_entry     = zone_name and disk_positions[zone_name] or nil;
                        if disk_entry and positions_differ({ x = disk_entry.x, z = disk_entry.z }, new_pos) then
                            changed_pos  = new_pos;
                            changed_from = string.format('last recorded scan on %s', disk_entry.ts_str);
                            changed_ts   = disk_entry.timestamp;
                        end
                    end

                    if changed_pos then
                        -- Position changed vs known reference - enter investigating state
                        chat(COLOR_WARN, string.format(
                            'Scan 1: position differs from %s!', changed_from));
                        chat(COLOR_WARN, string.format(
                            'Current: (%.1f, %.1f)', new_pos.x, new_pos.z));
                        chat(COLOR_INFO, string.format(
                            'Running %d confirmation scans to determine if worm is actively roaming...',
                            CONFIRM_SCAN_COUNT));

                        state.investigating       = true;
                        state.confirm_scan_number = 0;
                        state.confirm_base_pos    = new_pos;
                        state.last_session_ts     = changed_ts;
                        start_scan_wait(SCAN_INTERVAL);
                    else
                        -- No change vs any known reference
                        local hist_str = historical and 'no change vs previous visit'
                            or (load_positions()[zone_name or ''] and 'no change vs last session' or 'no previous data');
                        chat(COLOR_INFO, string.format(
                            'Scan 1: position recorded (%.1f, %.1f, %.1f) - %s',
                            new_pos.x, new_pos.y, new_pos.z, hist_str));
                        start_scan_wait(SCAN_INTERVAL);
                    end

                -- -----------------------------------------------
                -- NORMAL SCANS 2-N: compare vs previous scan
                -- -----------------------------------------------
                else
                    if positions_differ(state.last_pos, state.current_pos) then
                        state.worm_confirmed = true;
                        state.scanning = false;
                        alert_worm_found(state.current_pos);
                    else
                        chat(COLOR_INFO, string.format('Scan %d: no movement detected.',
                            state.scan_number));
                        if state.scan_number < SCAN_COUNT then
                            start_scan_wait(SCAN_INTERVAL);
                        else
                            state.scanning = false;
                            chat(COLOR_INFO, string.format('Scan cycle complete. Sandworm not confirmed in %s.',
                                state.zone_info and state.zone_info.name or 'this zone'));
                            if state.autowarp then
                                chat(COLOR_INFO, 'Warping to next zone in 5 seconds...');
                                start_scan_wait(5);
                                state._autowarp_pending = true;
                            end
                        end
                    end
                end
            else
                -- No position in this packet; still wait and try again
                chat(COLOR_INFO, string.format('Scan %d: no position data in response. Will retry.',
                    state.scan_number));
                if state.scan_number < SCAN_COUNT then
                    start_scan_wait(SCAN_INTERVAL);
                else
                    state.scanning = false;
                    chat(COLOR_INFO, string.format('Scan cycle complete. Sandworm not confirmed in %s.',
                        state.zone_info and state.zone_info.name or 'this zone'));
                    if state.autowarp then
                        chat(COLOR_INFO, 'Warping to next zone in 5 seconds...');
                        start_scan_wait(5);
                        state._autowarp_pending = true;
                    end
                end
            end
        end
    end

    -- Zone-in packet (0x0A)
    if id == 0x0A then
        -- Short delay to let zone fully load before we read zone info
        start_scan_wait(5);
        _waiting_for_scan = false;  -- override; we'll handle zone-in specially
        state._pending_zone_check = true;
    end
end);

-- ============================================================
-- ACTION EVENT - detect Doomvoid mob ability use
-- ============================================================
windower.register_event('action', function(act)
    -- Category 7 = mob readies a TP move (the yellow "readies X" message)
    if act.category ~= 7 then return; end

    local actor = windower.ffxi.get_mob_by_id(act.actor_id);
    if not actor or actor.name ~= 'Sandworm' then return; end

    -- Read the ability name from resources
    local ability_param = act.targets and act.targets[1] and
                          act.targets[1].actions and act.targets[1].actions[1] and
                          act.targets[1].actions[1].param;
    if not ability_param then return; end

    local ability = res.monster_abilities[ability_param];
    if not ability then return; end

    if ability.en == 'Doomvoid' then
        local zone_name = state.zone_info and state.zone_info.name or 'Unknown';
        state.tod      = os.time();
        state.tod_type = 'doomvoid';
        save_tod(state.tod, state.tod_type);

        -- Clear position for this zone so the next visit isn't a false alert
        clear_zone_position(zone_name);

        -- Stop any active scan cycle - we're about to be teleported out
        state.scanning            = false;
        state.investigating       = false;
        state._autowarp_pending   = false;
        _waiting_for_scan         = false;

        chat(COLOR_WARN, string.format(
            'Sandworm used Doomvoid in %s! ToD recorded: %s (20-25h window)',
            zone_name, os.date('%m-%d %H:%M', state.tod)));
        windower.play_sound(windower.addon_path .. 'alert.wav');
        log_event('DOOMVOID', zone_name, actor.x or 0, actor.z or 0,
            os.date('%m-%d %H:%M', state.tod));
    end
end);

-- ============================================================
-- ZONE CHANGE - auto-start scan if entering a worm zone
-- ============================================================
windower.register_event('zone change', function(new_zone, old_zone)
    -- Reset nav when zoning
    hide_nav();
    state.scanning    = false;
    state.scan_number = 0;
    _waiting_for_scan = false;
    state._pending_zone_check = false;

    local zone_entry  = res.zones[new_zone];
    local zone_name   = zone_entry and zone_entry.english or ('Zone #' .. new_zone);
    state.zone_id     = new_zone;
    state.zone_name   = zone_name;
    state.zone_info   = WORM_ZONES[zone_name];

    if state.zone_info then
        state.zone_info.name = zone_name;  -- store resolved name for later use
        -- Sync rotation index to match the zone we actually landed in
        for i, name in ipairs(ZONE_ROTATION) do
            if name == zone_name then
                state.rotation_index = i;
                break;
            end
        end
        chat(COLOR_INFO, string.format('Entered Sandworm zone: %s (%d/%d)',
            zone_name, state.rotation_index, #ZONE_ROTATION));
        local status, msg = get_window_status();
        chat(status == 'open' and COLOR_OK or COLOR_INFO, msg);
        -- Auto-start scan after a short load delay
        start_scan_wait(8);
        state._auto_scan_pending = true;
    else
        state._auto_scan_pending = false;
    end
end);

-- ============================================================
-- PRERENDER - drives the scan delay timer and nav compass
-- ============================================================
windower.register_event('prerender', function()
    local now   = os.clock();
    local delta = now - _last_tick;
    _last_tick  = now;

    -- Countdown timer for delayed scans
    if _waiting_for_scan then
        _scan_wait_remaining = _scan_wait_remaining - delta;
        if _scan_wait_remaining <= 0 then
            if state._autowarp_pending then
                state._autowarp_pending = false;
                _waiting_for_scan = false;
                autowarp_to_next();
            else
                perform_single_scan();
            end
        end
    end

    -- Auto-scan after zone-in
    if state._auto_scan_pending then
        state._auto_scan_pending = false;
        begin_scan_cycle();
    end

    -- Navigation compass update
    if state.nav_active and state.nav_target then
        local me = windower.ffxi.get_mob_by_target('me');
        if me then
            -- Windower mob object: x=EW, y=NS, z=elevation
            -- nav_target coords come from packet storage: x=EW, z=NS
            -- Use me.x/me.y vs target.x/target.z accordingly
            local dist = distance2d(me.x, me.y, state.nav_target.x, state.nav_target.z);
            if dist <= NAV_CLEAR_DISTANCE then
                chat(COLOR_OK, string.format("You've reached the Sandworm's position! Distance: %.1fy.", dist));
                hide_nav();
            else
                local bearing  = calc_bearing(me.x, me.y, state.nav_target.x, state.nav_target.z);
                local dir      = bearing_to_dir(bearing);
                local grid     = coords_to_grid(state.zone_name, state.nav_target.x, state.nav_target.z);
                local grid_str = grid and ('  Map: ' .. grid) or '';
                nav_box:text(string.format(
                    '[Sandworm Navigator]\n> %s  |  %.0fy away%s\nTarget: (%.1f, %.1f)',
                    dir, dist, grid_str, state.nav_target.x, state.nav_target.z
                ));
                nav_box:show();
            end
        end
    end
end);

-- ============================================================
-- LOAD / UNLOAD
-- ============================================================
windower.register_event('load', function()
    -- Restore ToD from file
    state.tod, state.tod_type = load_tod();
    if state.tod and state.tod > 0 then
        local type_str = state.tod_type and (' [' .. state.tod_type .. ']') or '';
        chat(COLOR_INFO, string.format('Loaded saved ToD: %s%s', os.date('%m-%d %H:%M', state.tod), type_str));
        local status, msg = get_window_status();
        chat(status == 'open' and COLOR_OK or COLOR_INFO, msg);
    end

    -- Check if we're already in a worm zone on load
    local info = windower.ffxi.get_info();
    if info and info.logged_in then
        local zone_entry = res.zones[info.zone];
        local zone_name  = zone_entry and zone_entry.english or ('Zone #' .. info.zone);
        state.zone_id    = info.zone;
        state.zone_name  = zone_name;
        state.zone_info  = WORM_ZONES[zone_name];
        if state.zone_info then
            state.zone_info.name = zone_name;
            -- Sync rotation index so autowarp continues from the correct zone
            for i, name in ipairs(ZONE_ROTATION) do
                if name == zone_name then
                    state.rotation_index = i;
                    break;
                end
            end
            chat(COLOR_INFO, string.format('Already in Sandworm zone: %s (%d/%d)',
                zone_name, state.rotation_index, #ZONE_ROTATION));
        end
    end

    -- Write CSV headers if files don't exist
    local f = io.open(LOG_PATH, 'r');
    if not f then
        local fw = io.open(LOG_PATH, 'w');
        if fw then
            fw:write('"event","timestamp","zone","x","z","notes"\n');
            fw:close();
        end
    else
        f:close();
    end

    local fp = io.open(POS_PATH, 'r');
    if not fp then
        local fw = io.open(POS_PATH, 'w');
        if fw then
            fw:write('"zone","x","z","timestamp","ts_str"\n');
            fw:close();
        end
    else
        fp:close();
    end

    chat(COLOR_INFO, 'SandwormTracker loaded. Type //worm help for commands.');
end);

windower.register_event('unload', function()
    hide_nav();
end);

-- ============================================================
-- ADDON COMMANDS
-- ============================================================
windower.register_event('addon command', function(...)
    local args = { ... };
    local cmd  = args[1] and args[1]:lower() or 'help';

    if cmd == 'help' then
        chat(COLOR_INFO, '--- SandwormTracker Commands ---');
        windower.add_to_chat(COLOR_INFO, '  //worm scan              - Trigger scan cycle in current zone');
        windower.add_to_chat(COLOR_INFO, '  //worm stop              - Stop scanning and cancel pending autowarp');
        windower.add_to_chat(COLOR_INFO, '  //worm status            - Show ToD and window status');
        windower.add_to_chat(COLOR_INFO, '  //worm tod now [kill|doomvoid]           - Set ToD to right now');
        windower.add_to_chat(COLOR_INFO, '  //worm tod MM-DD HH:MM [kill|doomvoid]   - Set ToD manually');
        windower.add_to_chat(COLOR_INFO, '  //worm autowarp [on/off] - Toggle auto-warp to next zone after scan');
        windower.add_to_chat(COLOR_INFO, '  //worm nav               - Toggle navigation display');
        windower.add_to_chat(COLOR_INFO, '  //worm reset             - Clear all saved data');
        windower.add_to_chat(COLOR_INFO, '  //worm zones             - List Sandworm zones and rotation order');

    elseif cmd == 'scan' then
        begin_scan_cycle();

    elseif cmd == 'stop' then
        state.scanning            = false;
        state.scan_number         = 0;
        state.investigating       = false;
        state.confirm_scan_number = 0;
        state._autowarp_pending   = false;
        state._auto_scan_pending  = false;
        _waiting_for_scan         = false;
        chat(COLOR_WARN, 'Scan and autowarp stopped.');

    elseif cmd == 'status' then
        local status, msg = get_window_status();
        local color = (status == 'open' or status == 'doomvoid') and COLOR_OK or
                      (status == 'expired' and COLOR_WARN or COLOR_INFO);
        chat(color, msg);

    elseif cmd == 'tod' then
        -- Usage: //worm tod now [kill|doomvoid]
        --        //worm tod MM-DD HH:MM [kill|doomvoid]
        if #args < 2 then
            chat(COLOR_WARN, 'Usage: //worm tod now [kill|doomvoid]  OR  //worm tod MM-DD HH:MM [kill|doomvoid]');
            return;
        end

        -- Last arg may be a type specifier
        local last_arg = args[#args] and args[#args]:lower() or '';
        local tod_type = nil;
        local time_args_end = #args;
        if last_arg == 'kill' or last_arg == 'doomvoid' then
            tod_type = last_arg;
            time_args_end = #args - 1;
        end

        local time_str = table.concat(args, ' ', 2, time_args_end);
        if time_str == '' then
            chat(COLOR_WARN, 'Usage: //worm tod now [kill|doomvoid]  OR  //worm tod MM-DD HH:MM [kill|doomvoid]');
            return;
        end

        local t, err = parse_tod_string(time_str);
        if err == 'future' then
            chat(COLOR_WARN, 'That time is in the future. ToD must be a past timestamp.');
        elseif t then
            state.tod      = t;
            state.tod_type = tod_type;
            save_tod(t, tod_type);
            local type_str = tod_type and (' [' .. tod_type .. ']') or ' [type unknown]';
            chat(COLOR_OK, string.format('ToD set to: %s%s', os.date('%m-%d %H:%M', t), type_str));
            local status, msg = get_window_status();
            chat(status == 'open' and COLOR_OK or COLOR_INFO, msg);
            log_event('TOD_SET', state.zone_info and state.zone_info.name or '', 0, 0,
                string.format('%s %s', os.date('%m-%d %H:%M', t), tod_type or 'unknown'));
        else
            chat(COLOR_WARN, 'Could not parse time. Use: now  OR  MM-DD HH:MM');
        end

    elseif cmd == 'nav' then
        if state.nav_active then
            hide_nav();
            chat(COLOR_INFO, 'Navigation compass hidden.');
        elseif state.current_pos then
            show_nav(state.current_pos.x, state.current_pos.z);
            chat(COLOR_INFO, 'Navigation compass enabled.');
        else
            chat(COLOR_WARN, 'No worm position recorded yet. Run a scan first.');
        end

    elseif cmd == 'reset' then
        state.tod = nil;
        state.last_pos = nil;
        state.current_pos = nil;
        state.worm_confirmed = false;
        hide_nav();
        clear_tod();
        chat(COLOR_WARN, 'All saved data cleared.');

    elseif cmd == 'autowarp' then
        local arg = args[2] and args[2]:lower();
        if arg == 'on' then
            state.autowarp = true;
        elseif arg == 'off' then
            state.autowarp = false;
        else
            state.autowarp = not state.autowarp;
        end
        chat(state.autowarp and COLOR_OK or COLOR_WARN,
            string.format('Autowarp %s.', state.autowarp and 'ENABLED' or 'DISABLED'));

    elseif cmd == 'zones' then
        chat(COLOR_INFO, '--- Sandworm Zone Rotation ---');
        for i, zname in ipairs(ZONE_ROTATION) do
            local marker = (state.zone_name == zname) and ' << current' or '';
            windower.add_to_chat(COLOR_INFO, string.format('  %d. %s  (0x%X)%s',
                i, zname, WORM_ZONES[zname].target_index, marker));
        end

    else
        chat(COLOR_WARN, string.format("Unknown command '%s'. Type //worm help.", cmd));
    end
end);
