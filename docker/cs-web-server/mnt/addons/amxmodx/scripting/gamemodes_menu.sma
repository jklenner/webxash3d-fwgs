/*  Game Modes Menu
 *  ----------------
 *  Modes:
 *    0 = STANDARD  (CSDM OFF, GunGame OFF)
 *    1 = DEATHMATCH (CSDM ON,  GunGame OFF)
 *    2 = GUNGAME    (CSDM OFF, GunGame ON)
 *
 *  Cvars (put these in server.cfg if you want custom values):
 *    gm_mode            "0"     // 0=Standard, 1=Deathmatch, 2=GunGame (plugin keeps this in sync)
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
    gCvarMode          = register_cvar("gm_mode", "1");             // default STANDARD
    gCvarRestartMethod = register_cvar("gm_restart_method", "1");   // 1=sv_restart, 2=changelevel
    gCvarRestartDelay  = register_cvar("gm_restart_delay", "2.0");  // seconds
    gCvarAnnounce      = register_cvar("gm_announce", "1");
}

/*  Re-apply the desired mode AFTER all configs on a fresh map.
 *  This ensures GunGame is enabled properly if we used changelevel.
 */
public OnConfigsExecuted()
{
    ApplyMode(get_pcvar_num(gCvarMode), true /*postConfig*/);
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
            if (!postConfig) Broadcast("Switched to STANDARD (CSDM OFF, GunGame OFF).");
        }
        case MODE_DM:
        {
            server_cmd("amx_gungame 0");
            server_cmd("gg_dm 0");          // keep GG DM off when using CSDM
            server_cmd("csdm_enable");
            server_cmd("reb_enable 1");
            if (!postConfig) Broadcast("Switched to DEATHMATCH (CSDM ON, GunGame OFF).");
        }
        case MODE_GG:
        {
            server_cmd("csdm_disable");
            server_cmd("amx_gungame 1");    // enable GunGame
            server_cmd("gg_dm 1");          // GunGame’s own deathmatch/respawn
            server_cmd("reb_enable 1");
            // Optional but harmless: make sure weapon order is reloaded on new map
            if (postConfig) server_cmd("gg_reloadweapons");
            if (!postConfig) Broadcast("Switched to GUNGAME (CSDM OFF, GunGame ON).");
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

// --------------------- Mode setters (menu) --------------------

stock SetMode_Standard()
{
    set_pcvar_num(gCvarMode, MODE_STANDARD);
    ApplyMode(MODE_STANDARD, false);
    QueueRestart();
}

stock SetMode_Deathmatch()
{
    set_pcvar_num(gCvarMode, MODE_DM);
    ApplyMode(MODE_DM, false);
    QueueRestart();
}

stock SetMode_GunGame()
{
    set_pcvar_num(gCvarMode, MODE_GG);
    ApplyMode(MODE_GG, false);
    QueueRestart();
}
