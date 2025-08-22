/*  Game Modes Menu (persistent, per-mode cvars, Roundend Blocker wiring)
 *  ---------------------------------------------------------------------
 *  Modes:
 *    0 = STANDARD    (CSDM OFF, GunGame OFF, Roundend Blocker OFF)
 *    1 = DEATHMATCH  (CSDM ON,  GunGame OFF, Roundend Blocker ON)
 *    2 = GUNGAME     (CSDM OFF, GunGame ON,  Roundend Blocker ON)
 *
 *  Persistence:
 *    Saves current mode to addons/amxmodx/configs/gamemodes_menu_mode.cfg
 *    and auto-execs it on next boot (survives restarts/crashes).
 *
 *  Per-mode server cvars (enforced at map start + round start):
 *    mp_freezetime, mp_chattime
 *
 *  Roundend Blocker (AMXX plugin) cvars (set only if they exist):
 *    reb_enable       (0/1)  // toggled by mode
 *    reb_plrmin       (int)
 *    reb_plrmax       (int)
 *    reb_fakefull     (0/1)
 *    reb_fullkick     (0/1)
 *
 *  CVARs to tune in server.cfg (defaults below):
 *    gm_mode             "0"     // 0=Standard, 1=Deathmatch, 2=GunGame (stored in file too)
 *    gm_restart_method   "1"     // 1=sv_restart 1, 2=changelevel <current> (on mode switch)
 *    gm_restart_delay    "2.0"   // seconds before restart/changelevel (on mode switch)
 *    gm_announce         "1"     // chat announce on mode switch
 *    gm_freezetime_std   "5"     // mp_freezetime for Standard
 *    gm_freezetime_dm    "0"     // mp_freezetime for Deathmatch
 *    gm_freezetime_gg    "0"     // mp_freezetime for GunGame
 *    gm_chattime_std     "10"    // mp_chattime for Standard
 *    gm_chattime_dm      "10"     // mp_chattime for Deathmatch
 *    gm_chattime_gg      "10"     // mp_chattime for GunGame
 *
 */

#include <amxmodx>
#include <amxmisc>

#define MODE_STANDARD   0
#define MODE_DM         1
#define MODE_GG         2

new const MODE_CFG_PATH[] = "addons/amxmodx/configs/gamemodes_menu_mode.cfg";

// ---- Core CVAR handles
new gCvarMode;
new gCvarRestartMethod;
new gCvarRestartDelay;
new gCvarAnnounce;
new gCvarFreezeStd, gCvarFreezeDM, gCvarFreezeGG;
new gCvarChatStd,   gCvarChatDM,   gCvarChatGG;

// ---- Roundend Blocker pass-through CVAR handles
new gCvarREB_PlrMin, gCvarREB_PlrMax, gCvarREB_FakeFull, gCvarREB_FullKick;

public plugin_init()
{
    register_plugin("Game Modes Menu", "2.4", "jklenner");

    // Admin commands to open menu
    register_clcmd("amx_gamemodes", "CmdOpenMenu", ADMIN_CFG, " - open Game Modes menu");
    register_clcmd("say /modes", "CmdOpenMenu");
    register_clcmd("say /mode",  "CmdOpenMenu");

    // Core mode + behavior
    gCvarMode          = register_cvar("gm_mode", "0");
    gCvarRestartMethod = register_cvar("gm_restart_method", "1");   // 1=sv_restart, 2=changelevel
    gCvarRestartDelay  = register_cvar("gm_restart_delay", "2.0");  // seconds
    gCvarAnnounce      = register_cvar("gm_announce", "1");

    // Per-mode freeze/chat time
    gCvarFreezeStd     = register_cvar("gm_freezetime_std", "5");
    gCvarFreezeDM      = register_cvar("gm_freezetime_dm",  "0");
    gCvarFreezeGG      = register_cvar("gm_freezetime_gg",  "0");

    gCvarChatStd       = register_cvar("gm_chattime_std", "10");
    gCvarChatDM        = register_cvar("gm_chattime_dm",  "10");
    gCvarChatGG        = register_cvar("gm_chattime_gg",  "10");

    // Load persisted mode very early
    if (file_exists(MODE_CFG_PATH)) {
        server_cmd("exec %s", MODE_CFG_PATH);
        server_exec();
    }

    // Apply per-mode cvars at each round start (and map start)
    register_event("HLTV", "OnNewRound", "a", "1=0", "2=0");
}

public OnConfigsExecuted()
{
    // After server.cfg/amxx.cfg/plugins cfgs: set mods and per-mode cvars + REB
    ApplyMode(get_pcvar_num(gCvarMode), true);
    ApplyPerModeServerCvarsOnce();     // freezetime/chattime
    ApplyRoundendBlockerForMode();     // reb_enable + tuning (if plugin exists)
}

// Round start (and map start)
public OnNewRound()
{
    ApplyPerModeServerCvarsOnce();
    ApplyRoundendBlockerForMode();
    // Re-apply shortly after to win any late writes
    set_task(0.10, "ReapplyAllPerMode");
}

public ReapplyAllPerMode()
{
    ApplyPerModeServerCvarsOnce();
    ApplyRoundendBlockerForMode();
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
    menu_additem(menu, "Standard");    // CSDM OFF, GG OFF, REB OFF
    menu_additem(menu, "Deathmatch");  // CSDM ON,  GG OFF, REB ON
    menu_additem(menu, "GunGame");     // CSDM OFF, GG ON,  REB ON
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
    switch (mode)
    {
        case MODE_STANDARD:
        {
            // Turn both off
            server_cmd("csdm_disable");
            server_cmd("amx_gungame 0");
            server_cmd("gg_dm 0");
            if (!postConfig) Broadcast("Switched to STANDARD (CSDM OFF, GunGame OFF).");
        }
        case MODE_DM:
        {
            // CSDM only
            server_cmd("amx_gungame 0");
            server_cmd("gg_dm 0");
            server_cmd("csdm_enable");
            if (!postConfig) Broadcast("Switched to DEATHMATCH (CSDM ON, GunGame OFF).");
        }
        case MODE_GG:
        {
            // GunGame only
            server_cmd("csdm_disable");
            server_cmd("amx_gungame 1");
            server_cmd("gg_dm 1");               // if you use GG's DM mode
            if (postConfig) server_cmd("gg_reloadweapons");
            if (!postConfig) Broadcast("Switched to GUNGAME (CSDM OFF, GunGame ON).");
        }
    }
    server_exec();

    // Also apply per-mode server cvars and REB immediately when switching
    ApplyPerModeServerCvarsOnce();
    ApplyRoundendBlockerForMode();
}

stock ApplyPerModeServerCvarsOnce()
{
    new mode = get_pcvar_num(gCvarMode);

    new ft, ct;
    switch (mode)
    {
        case MODE_STANDARD:
        {
            ft = get_pcvar_num(gCvarFreezeStd);
            ct = get_pcvar_num(gCvarChatStd);
        }
        case MODE_DM:
        {
            ft = get_pcvar_num(gCvarFreezeDM);
            ct = get_pcvar_num(gCvarChatDM);
        }
        case MODE_GG:
        {
            ft = get_pcvar_num(gCvarFreezeGG);
            ct = get_pcvar_num(gCvarChatGG);
        }
    }

    // Set cvars directly so we win ordering wars
    set_cvar_num("mp_freezetime", ft);
    set_cvar_num("mp_chattime",   ct);
}

// ------------- Roundend Blocker wiring ------------------------

stock ApplyRoundendBlockerForMode()
{
    // If Roundend Blocker isn't loaded, do nothing.
    if (!cvar_exists("reb_enable"))
        return;

    // Enable per mode
    switch (get_pcvar_num(gCvarMode))
    {
        case MODE_STANDARD: set_cvar_num("reb_enable", 0);
        case MODE_DM:       set_cvar_num("reb_enable", 1);
        case MODE_GG:       set_cvar_num("reb_enable", 1);
    }
}

stock SetCvarIfExistsNum(const name[], value)
{
    if (cvar_exists(name))
        set_cvar_num(name, value);
}

stock Broadcast(const msg[])
{
    if (get_pcvar_num(gCvarAnnounce)) {
        client_print(0, print_chat, "[GameModes] %s", msg);
        server_print("[GameModes] %s", msg);
    }
}

// ------------- persistence + restart helpers ------------------

stock SaveModeToFile(mode)
{
    // Write a one-line cfg we exec on startup, e.g.:  gm_mode 2
    new line[32];
    formatex(line, charsmax(line), "gm_mode %d", mode);

    if (file_exists(MODE_CFG_PATH)) delete_file(MODE_CFG_PATH);
    write_file(MODE_CFG_PATH, line);
}

stock QueueRestart()
{
    new Float:delay = get_pcvar_float(gCvarRestartDelay);
    if (delay < 0.01) delay = 0.01;
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
}

// --------------------- Mode setters (menu) --------------------

stock SetModeAndPersist(mode)
{
    SaveModeToFile(mode);           // persist for next boot
    set_pcvar_num(gCvarMode, mode); // set now
}

stock SetMode_Standard()
{
    SetModeAndPersist(MODE_STANDARD);
    ApplyMode(MODE_STANDARD, false);
    QueueRestart();
}

stock SetMode_Deathmatch()
{
    SetModeAndPersist(MODE_DM);
    ApplyMode(MODE_DM, false);
    QueueRestart();
}

stock SetMode_GunGame()
{
    SetModeAndPersist(MODE_GG);
    ApplyMode(MODE_GG, false);
    QueueRestart();
}
