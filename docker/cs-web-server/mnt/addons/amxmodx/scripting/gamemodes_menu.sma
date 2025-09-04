/*  Game Modes Menu
 *  ----------------
 *  Modes:
 *    0 = STANDARD  (CSDM OFF, GunGame OFF)
 *    1 = DEATHMATCH (CSDM ON,  GunGame OFF)
 *    2 = GUNGAME    (CSDM OFF, GunGame ON)
 *    3 = SURF (CSDM OFF,GunGame OFF)
 *
 *  Cvars (put these in server.cfg if you want custom values):
 *    gm_mode            "1"     // 0=Standard, 1=Deathmatch, 2=GunGame (plugin keeps this in sync)
 *    gm_restart_method  "1"     // 1=sv_restart 1 (round restart), 2=changelevel <current map>
 *    gm_restart_delay   "2.0"   // seconds to wait before restarting (give mods time to switch)
 *    gm_announce        "1"     // 1=chat announce on mode switch
 *
 *  Commands:
 *    amx_gamemodes      // opens the Game Modes menu (ADMIN_CFG)
 *    say /modes, /mode  // chat shortcuts (ADMIN only)
 *
 *  Files:
 *    Place the compiled .amxx into: addons/amxmodx/plugins/
 *    Add to addons/amxmodx/configs/plugins.ini:  gamemodes_menu.amxx
 */

#include <amxmodx>
#include <amxmisc>

// ---- Constants
#define MODE_STANDARD   0
#define MODE_DM         1
#define MODE_GG         2
#define MODE_SURF 	3

// ---- CVAR handles
new gCvarMode;              // 0=std, 1=dm, 2=gg
new gCvarRestartMethod;     // 1=sv_restart, 2=changelevel
new gCvarRestartDelay;      // Float seconds
new gCvarAnnounce;          // 0/1

public plugin_init()
{
    register_plugin("Game Modes Menu", "1.1", "jklenner");

    // open from console or chat (admins only)
    register_clcmd("amx_gamemodes", "CmdOpenMenu", ADMIN_CFG, " - open Game Modes menu");
    register_clcmd("say /modes", "CmdOpenMenu");
    register_clcmd("say /mode",  "CmdOpenMenu");

    // cvars
    gCvarMode          = register_cvar("gm_mode", "1");             // default DEATHMATCH
    gCvarRestartMethod = register_cvar("gm_restart_method", "1");   // 1=sv_restart, 2=changelevel
    gCvarRestartDelay  = register_cvar("gm_restart_delay", "2.0");  // seconds
    gCvarAnnounce      = register_cvar("gm_announce", "1");
}

public plugin_cfg() {
    ApplyMode(get_pcvar_num(gCvarMode), true); // runs after all cfgs
    ApplyQuotaByPool();	
}

/*  Re-apply the desired mode AFTER all configs on a fresh map.
 *  This ensures GunGame is enabled properly if we used changelevel.
 */
public OnConfigsExecuted()
{
    ApplyMode(get_pcvar_num(gCvarMode), true /*postConfig*/);
    ApplyQuotaByPool();
}

// --------------------------- Menu -----------------------------

public CmdOpenMenu(id)
{
    if (!is_user_admin(id)) {
        client_print(id, print_chat, "[GameModes] You are not authorized.");
        return PLUGIN_HANDLED;
    }

    new current = get_pcvar_num(gCvarMode);

    new title[64];
    formatex(title, charsmax(title), "Game Modes  \r(Current: %s)",
        (current == MODE_STANDARD) ? "Standard" :
        (current == MODE_DM)       ? "Deathmatch" : "GunGame");

    new menu = menu_create(title, "MenuHandler");
    menu_additem(menu, "Standard");    // CSDM OFF, GG OFF
    menu_additem(menu, "Deathmatch");  // CSDM ON,  GG OFF
    menu_additem(menu, "GunGame");     // CSDM OFF, GG ON
    menu_additem(menu, "Surf"); // after GunGame
    menu_setprop(menu, MPROP_EXIT, MEXIT_ALL);
    menu_display(id, menu, 0);
    return PLUGIN_HANDLED;
}

public MenuHandler(id, menu, item)
{
    if (item < 0) { menu_destroy(menu); return PLUGIN_HANDLED; }

    switch (item) {
        case 0: SetMode_Standard();
        case 1: SetMode_Deathmatch();
        case 2: SetMode_GunGame();
	case 3: SetMode_Surf();
    }
    menu_destroy(menu);
    return PLUGIN_HANDLED;
}

// ------------------------ Core logic --------------------------

stock ApplyMode(mode, bool:postConfig)
{
    // postConfig=true means we're being called from OnConfigsExecuted on a fresh map.
    // We avoid forcing another restart here; just ensure correct mod state.

    switch (mode)
    {
        case MODE_STANDARD:
        {
            server_cmd("csdm_disable");
            server_cmd("amx_gungame 0");
            server_cmd("gg_dm 0");
	    server_cmd("reb_enable 0");
	    server_cmd("mp_timelimit 20");
            server_cmd("mp_freezetime 6");
            server_cmd("sv_airaccelerate 10");
            server_cmd("gal_vote_mapfile addons/amxmodx/configs/galileo/votefill_standard.ini");
            server_cmd("gal_mapcyclefile addons/amxmodx/configs/galileo/1.ini"); // STANDARD
            server_cmd("gal_nom_mapfile #");  // nominations follow current mapcycle
            if (!postConfig) Broadcast("Switched to STANDARD (CSDM OFF, GunGame OFF).");
        }
        case MODE_DM:
        {
            server_cmd("amx_gungame 0");
            server_cmd("gg_dm 0");          // keep GG DM off when using CSDM
            server_cmd("csdm_enable");
            server_cmd("reb_enable 1");
            server_cmd("mp_timelimit 10");
            server_cmd("mp_freezetime 0");
            server_cmd("sv_airaccelerate 10");
            server_cmd("gal_vote_mapfile addons/amxmodx/configs/galileo/votefill_dmgg.ini");
            server_cmd("gal_mapcyclefile addons/amxmodx/configs/galileo/2.ini"); // DMGG
            server_cmd("gal_nom_mapfile #");  // nominations follow current mapcycle
            if (!postConfig) Broadcast("Switched to DEATHMATCH (CSDM ON, GunGame OFF).");
        }
        case MODE_GG:
        {
            server_cmd("csdm_disable");
            server_cmd("amx_gungame 1");    // enable GunGame
            server_cmd("gg_dm 1");          // GunGame’s own deathmatch/respawn
            server_cmd("reb_enable 1");
	    server_cmd("mp_timelimit 0");
            server_cmd("mp_freezetime 0");
            server_cmd("sv_airaccelerate 10");
            server_cmd("gal_vote_mapfile addons/amxmodx/configs/galileo/votefill_dmgg.ini");
            server_cmd("gal_mapcyclefile addons/amxmodx/configs/galileo/2.ini"); // DMGG
            server_cmd("gal_nom_mapfile #");  // nominations follow current mapcycle
            // Optional but harmless: make sure weapon order is reloaded on new map
            if (postConfig) server_cmd("gg_reloadweapons");
            if (!postConfig) Broadcast("Switched to GUNGAME (CSDM OFF, GunGame ON).");
        }
        case MODE_SURF:
        {
            server_cmd("csdm_disable");
            server_cmd("amx_gungame 0"); 
	    server_cmd("gg_dm 0");
            server_cmd("reb_enable 0");
            server_cmd("mp_timelimit 0");
	    server_cmd("mp_freezetime 0");
            server_cmd("sv_airaccelerate 150");
            server_cmd("gal_vote_mapfile addons/amxmodx/configs/galileo/votefill_surf.ini");
            server_cmd("gal_mapcyclefile addons/amxmodx/configs/galileo/3.ini"); // SURF
            server_cmd("gal_nom_mapfile #");  // nominations follow current mapcycle
            if (!postConfig) Broadcast("Switched to SURF.");
        }
    }
    server_exec();
}

stock Broadcast(const msg[])
{
    if (get_pcvar_num(gCvarAnnounce)) {
        client_print(0, print_chat, "[GameModes] %s", msg);
        server_print("[GameModes] %s", msg);
    }
}

stock QueueRestart()
{
    // give the mods a moment to process their commands
    new Float:delay = get_pcvar_float(gCvarRestartDelay);
    if (delay < 0.1) delay = 0.1;  // sanity

    set_task(delay, "Task_DoRestart");
}

public Task_DoRestart()
{
    new method = get_pcvar_num(gCvarRestartMethod);

    if (method == 2) {
        new map[32]; get_mapname(map, charsmax(map));
        server_cmd("changelevel %s", map);
    } else {
        server_cmd("sv_restart 1");
    }
    // no server_exec here; engine will execute immediately
}

// Paths to your Galileo pools
new const POOL1_FILE[] = "addons/amxmodx/configs/galileo/1.ini"; // classic
new const POOL2_FILE[] = "addons/amxmodx/configs/galileo/2.ini"; // DM+GG
new const POOL3_FILE[] = "addons/amxmodx/configs/galileo/3.ini"; // SURF

stock bool:IsMapInFile(const path[], const find[])
{
    new fp = fopen(path, "rt");
    if (!fp) return false;

    new line[64], ok = false;
    while (!feof(fp))
    {
        fgets(fp, line, charsmax(line));
        trim(line);
        if (!line[0] || line[0] == ';' || line[0] == '#') continue;
        if (equali(line, find)) { ok = true; break; }
    }
    fclose(fp);
    return ok;
}

stock ApplyQuotaByPool()
{
    new map[32]; get_mapname(map, charsmax(map));
    if (IsMapInFile(POOL3_FILE, map))       server_cmd("yb_quota 0");
    else if (IsMapInFile(POOL2_FILE, map))  server_cmd("yb_quota 6");
    else if (IsMapInFile(POOL1_FILE, map))  server_cmd("yb_quota 10");
    // else: leave as-is
    server_exec();
}

// Reservoir-sample one valid, non-empty line from a file
stock bool:GetRandomMapFromFile(const path[], map[], const maplen)
{
    new fp = fopen(path, "rt");
    if (!fp) return false;

    new line[64], n = 0;
    while (!feof(fp))
    {
        fgets(fp, line, charsmax(line));
        trim(line);
        if (!line[0] || line[0] == ';' || line[0] == '#') continue;

        n++;
        if (n == 1 || random_num(1, n) == 1) {
            copy(map, maplen, line);
        }
    }
    fclose(fp);
    return n > 0;
}

stock bool:MapExists(const map[])
{
    new path[96];
    formatex(path, charsmax(path), "maps/%s.bsp", map); // relative to mod dir
    return file_exists(path);
}

stock bool:ForceMapFromPool(const path[])
{
    new map[64];
    if (!GetRandomMapFromFile(path, map, charsmax(map))) return false;
    if (!MapExists(map)) return false;
    server_cmd("changelevel %s", map); // immediate; no server_exec needed
    return true;
}

stock bool:IsSurfMap()
{
    new map[32]; get_mapname(map, charsmax(map));
    return equali(map, "surf_", 5); // case-insensitive prefix match
}

// --------------------- Mode setters (menu) --------------------

// SURF
stock SetMode_Surf()
{
    new prev = get_pcvar_num(gCvarMode);

    set_pcvar_num(gCvarMode, MODE_SURF);
    ApplyMode(MODE_SURF, false);

    if (!IsSurfMap()) {
        if (!ForceMapFromPool(POOL3_FILE)) QueueRestart();
    } else {
        QueueRestart();
    }
}

// DM
stock SetMode_Deathmatch()
{
    new prev = get_pcvar_num(gCvarMode);

    set_pcvar_num(gCvarMode, MODE_DM);
    ApplyMode(MODE_DM, false);

    if (prev == MODE_SURF) {
        if (!ForceMapFromPool(POOL2_FILE)) QueueRestart();
    } else {
        QueueRestart();
    }
}

// GG
stock SetMode_GunGame()
{
    new prev = get_pcvar_num(gCvarMode);

    set_pcvar_num(gCvarMode, MODE_GG);
    ApplyMode(MODE_GG, false);

    if (prev == MODE_SURF) {
        if (!ForceMapFromPool(POOL2_FILE)) QueueRestart();
    } else {
        QueueRestart();
    }
}

// STANDARD
stock SetMode_Standard()
{
    new prev = get_pcvar_num(gCvarMode);

    set_pcvar_num(gCvarMode, MODE_STANDARD);
    ApplyMode(MODE_STANDARD, false);

    if (prev == MODE_SURF) {
        if (!ForceMapFromPool(POOL2_FILE)) QueueRestart();
    } else {
        QueueRestart();
    }
}
