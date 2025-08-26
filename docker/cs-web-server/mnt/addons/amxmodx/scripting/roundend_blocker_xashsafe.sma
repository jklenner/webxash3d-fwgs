/*  RoundEnd Blocker (Xash-safe, watchdog + hard cleanup)
 *  - reb_enable 0 : rounds end on team wipe (keepers removed)
 *  - reb_enable 1 : rounds DO NOT end on team wipe (keepers present)
 *  - Max two keepers (T+CT, or only CT with reb_team 1)
 *  - No ghost RoundKeepers in “Game Info” after flips/mapchanges
 *
 *  CVARs:
 *    reb_enable 1/0   (default 1)
 *    reb_delay  5.0   (default 5.0s)
 *    reb_hide   1/0   (default 1)
 *    reb_team   0/1   (default 0; 1 = only CT keeper)
 *    reb_debug  0/1   (default 0; verbose logs)
 *
 *  Requires: amxmodx, cstrike, fakemeta, hamsandwich, fun
 */

#include <amxmodx>
#include <cstrike>
#include <fakemeta>
#include <hamsandwich>
#include <fun>

/* ---- Plugin ---- */
#define PLUGIN  "RoundEnd Blocker (Xash-safe)"
#define VERSION "1.0.5"
#define AUTHOR  "jklenner (+ fixes)"

#define NAME_T   "[OS] RoundKeeperT"
#define NAME_CT  "[OS] RoundKeeperCT"

/* Teams (ints to avoid CsTeams redefinition) */
#define TEAM_UNASSIGNED 0
#define TEAM_T          1
#define TEAM_CT         2
#define TEAM_SPEC       3

/* Keeper slots */
enum KeeperSlot { KS_T = 0, KS_CT = 1, KS_MAX = 2 }
enum KeeperState { K_NONE = 0, K_PENDING = 1, K_LIVE = 2 }

/* Task ids (disjoint spaces) */
const TASK_TEAM     = 10000;
const TASK_SPAWN    = 20000;
const TASK_KEEPAL   = 30000;
const TASK_SWEEP    = 40000; // general sweep
const TASK_WATCH    = 50000;

/* State */
new g_state[KS_MAX];
new g_ent[KS_MAX];
new g_userid[KS_MAX];
new g_target[KS_MAX];
new g_last[KS_MAX];

new bool:g_changingLevel = false;
new bool:g_enabled_prev  = true;  // last seen reb_enable value
new g_msgTeamInfo;

/* CVAR handles */
new pEnable, pDelay, pHide, pTeam, pDebug;

/* ----- helpers ----- */
stock slot_team(KeeperSlot:ks) { return (ks == KS_T) ? TEAM_T : TEAM_CT; }
stock bool:is_valid_ent(id)    { return (1 <= id && id <= get_maxplayers()); }
stock bool:is_in_game_safe(id) { return is_valid_ent(id) && is_user_connected(id); }

stock clear_slot(KeeperSlot:ks)
{
    g_state[ks]  = K_NONE;
    g_ent[ks]    = 0;
    g_userid[ks] = 0;
    g_target[ks] = TEAM_UNASSIGNED;
    g_last[ks]   = TEAM_UNASSIGNED;
}
stock reset_all_slots()
{
    clear_slot(KS_T);
    clear_slot(KS_CT);
}
stock dlog(const fmt[], any:...)
{
    if (!get_pcvar_num(pDebug)) return;
    static buff[192];
    vformat(buff, charsmax(buff), fmt, 2);
    server_print("[REB] %s", buff);
}

/* ----- task control ----- */
stock shutdown_keep_tasks(const bool:wipeFlags)
{
    remove_task(TASK_KEEPAL);
    remove_task(TASK_SWEEP);
    remove_task(TASK_WATCH);

    new maxp = get_maxplayers();
    for (new i = 1; i <= maxp; i++)
    {
        remove_task(TASK_TEAM + i);
        remove_task(TASK_SPAWN + i);
    }
    if (wipeFlags) reset_all_slots();
}

/* ===== lifecycle ===== */
public plugin_init()
{
    register_plugin(PLUGIN, VERSION, AUTHOR);

    pEnable = register_cvar("reb_enable", "1");
    pDelay  = register_cvar("reb_delay",  "5.0");
    pHide   = register_cvar("reb_hide",   "1");
    pTeam   = register_cvar("reb_team",   "0");
    pDebug  = register_cvar("reb_debug",  "0");

    register_event("HLTV", "OnRoundStart", "a", "1=0", "2=0");

    g_msgTeamInfo = get_user_msgid("TeamInfo");
    register_message(g_msgTeamInfo, "Msg_TeamInfo");

    register_forward(FM_ChangeLevel,      "fw_ChangeLevel",      1);
    register_forward(FM_ServerDeactivate, "fw_ServerDeactivate", 1);

    hook_cvar_change(pEnable, "OnRebEnableChanged");

    register_srvcmd("reb_cleanup", "SrvCmd_RebCleanup");
    register_concmd("reb_status",  "Cmd_Status");
}

public plugin_cfg()
{
    g_enabled_prev = (get_pcvar_num(pEnable) != 0);

    // watchdog for CVAR edge detection
    set_task(0.5, "Task_WatchEnable", TASK_WATCH, "", 0, "b");

    if (g_enabled_prev)
    {
        prune_duplicate_keepers(); // connect-time dedup
        set_task(get_pcvar_float(pDelay), "Task_EnsureKeepers");
        set_task(5.0, "Task_KeepAlive", TASK_KEEPAL, "", 0, "b");

        // one-shot connected sweep after start (no name-kick here)
        set_task(7.0, "Task_SweepConnectedOnce", TASK_SWEEP + 10);
    }
}

public OnRoundStart()
{
    if (g_changingLevel) return;
    if (get_pcvar_num(pEnable))
    {
        prune_duplicate_keepers();
        set_task(get_pcvar_float(pDelay), "Task_EnsureKeepers");
    }
}

public fw_ChangeLevel(const map[])
{
    g_changingLevel = true;
    cleanup_keepers_full();
    shutdown_keep_tasks(true);
}

public fw_ServerDeactivate()
{
    g_changingLevel = true;
    cleanup_keepers_full();
    shutdown_keep_tasks(true);
}

public plugin_end()
{
    cleanup_keepers_full();
}

/* ===== client hooks ===== */
public client_putinserver(id)
{
    if (g_changingLevel) return;

    new name[32];
    get_user_name(id, name, charsmax(name));

    if (equal(name, NAME_T))
    {
        g_state[KS_T]  = K_LIVE;
        g_ent[KS_T]    = id;
        g_userid[KS_T] = get_user_userid(id);
        dlog("bind keeper T to id=%d uid=%d", id, g_userid[KS_T]);
        if (get_pcvar_num(pHide)) mask_keeper_to_spectator_one_all(id);
    }
    else if (equal(name, NAME_CT))
    {
        g_state[KS_CT]  = K_LIVE;
        g_ent[KS_CT]    = id;
        g_userid[KS_CT] = get_user_userid(id);
        dlog("bind keeper CT to id=%d uid=%d", id, g_userid[KS_CT]);
        if (get_pcvar_num(pHide)) mask_keeper_to_spectator_one_all(id);
    }
}

public client_disconnected(id)
{
    if (id == g_ent[KS_T])  clear_slot(KS_T);
    if (id == g_ent[KS_CT]) clear_slot(KS_CT);

    if (!g_changingLevel && get_pcvar_num(pEnable))
        set_task(get_pcvar_float(pDelay), "Task_EnsureKeepers");
}

/* ===== TeamInfo masking ===== */
public Msg_TeamInfo(msgid, dest, id)
{
    if (g_changingLevel) return PLUGIN_CONTINUE;
    if (!get_pcvar_num(pEnable) || !get_pcvar_num(pHide))
        return PLUGIN_CONTINUE;

    new pid = get_msg_arg_int(1);
    if (1 <= pid && pid <= get_maxplayers())
    {
        if (pid == g_ent[KS_T] || pid == g_ent[KS_CT])
            set_msg_arg_string(2, "SPECTATOR");
    }
    return PLUGIN_CONTINUE;
}

/* ===== watchdog: edge-triggered enable/disable ===== */
public Task_WatchEnable()
{
    if (g_changingLevel) return;

    new enabled_now = (get_pcvar_num(pEnable) != 0);
    if (enabled_now == g_enabled_prev) return;

    g_enabled_prev = enabled_now;

    if (!enabled_now)
    {
        dlog("watch: reb_enable -> 0 (standard mode). Full disable cleanup.");
        schedule_disable_cleanup();
    }
    else
    {
        dlog("watch: reb_enable -> 1 (dm/gg). Reset & ensure.");
        reset_all_slots();
        prune_duplicate_keepers();
        Task_EnsureKeepers();
        set_task(get_pcvar_float(pDelay), "Task_EnsureKeepers");
        set_task(5.0, "Task_KeepAlive", TASK_KEEPAL, "", 0, "b");
        // one-shot connected dedup after enable
        set_task(7.0, "Task_SweepConnectedOnce", TASK_SWEEP + 10);
    }
}

/* Also update baseline when engines do fire this hook */
public OnRebEnableChanged(pcvar, const oldValue[], const newValue[])
{
    g_enabled_prev = (str_to_num(newValue) != 0);
}

/* ===== ensure / keepalive ===== */
public Task_EnsureKeepers()
{
    if (g_changingLevel || !get_pcvar_num(pEnable)) return;

    if (get_pcvar_num(pTeam) == 0)
    {
        ensure_slot(KS_T);
        ensure_slot(KS_CT);
    }
    else
    {
        ensure_slot(KS_CT);
        drop_slot(KS_T);
    }
}

public Task_KeepAlive()
{
    if (g_changingLevel || !get_pcvar_num(pEnable)) return;
    if (get_pcvar_num(pTeam) == 0)
    {
        ensure_slot(KS_T);
        ensure_slot(KS_CT);
    }
    else
    {
        ensure_slot(KS_CT);
    }
}

/* ===== disable cleanup (fixes Game Info ghosts) ===== */
stock schedule_disable_cleanup()
{
    shutdown_keep_tasks(true);
    cleanup_keepers_full();
    // do 2 delayed passes to catch any late engine bookkeeping
    set_task(1.0, "Task_SweepFullOnce",  TASK_SWEEP + 1);
    set_task(2.5, "Task_SweepFullOnce",  TASK_SWEEP + 2);
}

public Task_SweepConnectedOnce() { prune_duplicate_keepers(); }
public Task_SweepFullOnce()      { sweep_full(); }

/* ===== per-slot logic ===== */
stock ensure_slot(KeeperSlot:ks)
{
    if (g_state[ks] == K_LIVE)
    {
        if (is_in_game_safe(g_ent[ks]))
        {
            if (!is_user_alive(g_ent[ks]))
            {
                remove_task(TASK_SPAWN + g_ent[ks]);
                set_task(0.40, "Task_SpawnKeeper", TASK_SPAWN + g_ent[ks]);
            }
            else
            {
                apply_keeper_props(g_ent[ks]);
                if (get_pcvar_num(pHide)) mask_keeper_to_spectator_global(g_ent[ks]);
            }
            return;
        }
        clear_slot(ks);
    }

    if (g_state[ks] == K_PENDING) return;

    new id = find_keeper_by_name((ks == KS_T) ? NAME_T : NAME_CT);
    if (id)
    {
        g_state[ks]  = K_LIVE;
        g_ent[ks]    = id;
        g_userid[ks] = get_user_userid(id);
        g_last[ks]   = TEAM_UNASSIGNED;

        schedule_set_team(id, slot_team(ks));
        remove_task(TASK_SPAWN + id);
        set_task(0.45, "Task_SpawnKeeper", TASK_SPAWN + id);
        dlog("ensure: bound existing %s id=%d", (ks==KS_T)?"T":"CT", id);
        return;
    }

    id = create_keeper((ks == KS_T) ? NAME_T : NAME_CT);
    if (!id) return;

    g_state[ks]  = K_PENDING;
    g_ent[ks]    = id;
    g_userid[ks] = 0;
    g_last[ks]   = TEAM_UNASSIGNED;

    schedule_set_team(id, slot_team(ks));
    remove_task(TASK_SPAWN + id);
    set_task(0.45, "Task_SpawnKeeper", TASK_SPAWN + id);
    dlog("ensure: created %s id=%d", (ks==KS_T)?"T":"CT", id);
}

stock drop_slot(KeeperSlot:ks)
{
    if (is_in_game_safe(g_ent[ks]))
        drop_ent_hard(g_ent[ks]);
    clear_slot(ks);
}

/* ===== team & spawn tasks ===== */
stock schedule_set_team(id, team)
{
    new KeeperSlot:ks = slot_from_ent(id);
    if (ks != KS_MAX) g_target[ks] = team;

    remove_task(TASK_TEAM + id);
    set_task(0.25, "Task_SetTeam", TASK_TEAM + id);
}

public Task_SetTeam(taskid)
{
    if (g_changingLevel) return;

    new id = taskid - TASK_TEAM;
    if (!is_valid_ent(id)) return;

    new KeeperSlot:ks = slot_from_ent(id);
    if (ks == KS_MAX) return;

    if (!is_in_game_safe(id))
    {
        set_task(0.25, "Task_SetTeam", taskid);
        return;
    }

    new team = g_target[ks];
    if (team == TEAM_UNASSIGNED) team = TEAM_CT;

    if (g_last[ks] != team)
    {
        cs_set_user_team(id, CsTeams:team);
        g_last[ks] = team;

        if (get_pcvar_num(pHide)) mask_keeper_to_spectator_global(id);
    }
}

public Task_SpawnKeeper(taskid)
{
    if (g_changingLevel) return;

    new id = taskid - TASK_SPAWN;
    if (!is_valid_ent(id) || !is_user_connected(id)) return;

    if (!is_user_alive(id))
        ExecuteHamB(Ham_Spawn, id);

    // ensure counted as alive by round logic
    set_pev(id, pev_iuser1, 0);
    set_pev(id, pev_deadflag, DEAD_NO);

    apply_keeper_props(id);
    if (get_pcvar_num(pHide)) mask_keeper_to_spectator_global(id);
}

/* ===== low-level ops ===== */
stock KeeperSlot:slot_from_ent(id)
{
    if (id == g_ent[KS_T])  return KS_T;
    if (id == g_ent[KS_CT]) return KS_CT;
    return KS_MAX;
}

stock create_keeper(const name[])
{
    if (g_changingLevel) return 0;

    new id = engfunc(EngFunc_CreateFakeClient, name);
    if (!id) return 0;

    dllfunc(DLLFunc_ClientConnect, id, name, "127.0.0.1", "127.0.0.1");
    dllfunc(DLLFunc_ClientPutInServer, id);

    set_pev(id, pev_flags, pev(id, pev_flags) | FL_FAKECLIENT);
    return id;
}

stock apply_keeper_props(id)
{
    if (!is_in_game_safe(id)) return;

    set_pev(id, pev_effects, pev(id, pev_effects) | EF_NODRAW);
    set_pev(id, pev_takedamage, DAMAGE_NO);
    set_pev(id, pev_solid, SOLID_NOT);
    set_pev(id, pev_movetype, MOVETYPE_NOCLIP);
    set_pev(id, pev_flags, pev(id, pev_flags) | FL_NOTARGET);
    set_pev(id, pev_health, 1000000.0);
    strip_user_weapons(id);
}

stock find_keeper_by_name(const name[])
{
    new maxp = get_maxplayers(), pname[32];
    for (new i = 1; i <= maxp; i++)
    {
        if (!is_user_connected(i)) continue;
        get_user_name(i, pname, charsmax(pname));
        if (equal(pname, name)) return i;
    }
    return 0;
}

/* ===== masking ===== */
stock mask_keeper_to_spectator_global(id)
{
    if (!is_in_game_safe(id)) return;
    message_begin(MSG_ALL, g_msgTeamInfo);
    write_byte(id);
    write_string("SPECTATOR");
    message_end();
}
stock mask_keeper_to_spectator_one_all(id)
{
    new maxp = get_maxplayers();
    for (new r = 1; r <= maxp; r++)
    {
        if (!is_user_connected(r)) continue;
        message_begin(MSG_ONE, g_msgTeamInfo, _, r);
        write_byte(id);
        write_string("SPECTATOR");
        message_end();
    }
}

/* ===== cleanup / dedup ===== */
stock kick_userid_safe(uid)
{
    if (uid <= 0) return 0;
    server_cmd("kick #%d ^"reb_cleanup^"", uid);
    server_exec();
    return 1;
}
stock drop_ent_hard(id)
{
    if (!is_user_connected(id)) return;
    new uid = get_user_userid(id);
    if (!kick_userid_safe(uid))
        dllfunc(DLLFunc_ClientDisconnect, id);
}
stock bool:is_keeper_name_id(id)
{
    new n[32]; get_user_name(id, n, charsmax(n));
    return equal(n, NAME_T) || equal(n, NAME_CT);
}
stock bool:is_keeper_name_edict(ent)
{
    if (!pev_valid(ent)) return false;
    static n[32]; n[0] = 0;
    pev(ent, pev_netname, n, charsmax(n));
    if (!n[0]) return false;
    return equal(n, NAME_T) || equal(n, NAME_CT);
}

// Kick by name (helps if binding was lost but they still look “connected” to queries)
stock sweep_by_name()
{
    server_cmd("kick ^"%s^"", NAME_T);
    server_cmd("kick ^"%s^"", NAME_CT);
    server_exec();
}

// Remove disconnected player-edicts that still carry our keeper names (clears “Game Info”).
stock hardfree_ghost_edicts()
{
    new maxp = get_maxplayers();
    for (new i = 1; i <= maxp; i++)
    {
        if (is_user_connected(i)) continue;
        if (!pev_valid(i)) continue;
        if (!is_keeper_name_edict(i)) continue;
        engfunc(EngFunc_RemoveEntity, i);
        dlog("hardfree ghost edict id=%d", i);
    }
}

// “Full” sweep used on disable/mapchange (and by admin cmd)
stock sweep_full()
{
    // drop any connected keepers (by state and by name)
    new maxp = get_maxplayers();
    if (is_in_game_safe(g_ent[KS_T]))  drop_ent_hard(g_ent[KS_T]);
    if (is_in_game_safe(g_ent[KS_CT])) drop_ent_hard(g_ent[KS_CT]);
    for (new i = 1; i <= maxp; i++)
    {
        if (!is_user_connected(i)) continue;
        if (is_keeper_name_id(i)) drop_ent_hard(i);
    }

    // extra by-name kick (handles edge cases in Xash query cache)
    sweep_by_name();

    // finally, purge disconnected ghost edicts
    hardfree_ghost_edicts();

    reset_all_slots();
}

/* compat wrapper: older code paths referenced this */
stock cleanup_keepers_full()
{
    sweep_full();
}

// Connected de-dup only (safe in normal operation)
stock prune_duplicate_keepers()
{
    new idT = 0, idCT = 0, n[32], maxp = get_maxplayers();

    for (new i = 1; i <= maxp; i++)
    {
        if (!is_user_connected(i)) continue;

        get_user_name(i, n, charsmax(n));
        if (equal(n, NAME_T))
        {
            if (!idT) idT = i; else { dlog("dedup: kick extra T id=%d", i); drop_ent_hard(i); }
        }
        else if (equal(n, NAME_CT))
        {
            if (!idCT) idCT = i; else { dlog("dedup: kick extra CT id=%d", i); drop_ent_hard(i); }
        }
    }

    if (idT)
    {
        g_ent[KS_T]    = idT;
        g_userid[KS_T] = get_user_userid(idT);
        if (g_state[KS_T] == K_NONE) g_state[KS_T] = K_LIVE;
    }
    if (idCT)
    {
        g_ent[KS_CT]    = idCT;
        g_userid[KS_CT] = get_user_userid(idCT);
        if (g_state[KS_CT] == K_NONE) g_state[KS_CT] = K_LIVE;
    }
}

/* ===== svc / debug ===== */
public SrvCmd_RebCleanup()
{
    // admin-triggered hard cleanup
    schedule_disable_cleanup();
}
public Cmd_Status(id, level, cid)
{
    console_print(id, "[REB] enabled=%d dual=%d hide=%d delay=%.2f",
        get_pcvar_num(pEnable), (get_pcvar_num(pTeam)==0), get_pcvar_num(pHide), get_pcvar_float(pDelay));

    for (new i = 0; i < KS_MAX; i++)
    {
        new KeeperSlot:ks = KeeperSlot:i;
        console_print(id, "[REB] slot=%s state=%d id=%d uid=%d last=%d tgt=%d",
            (ks==KS_T)?"T":"CT", g_state[ks], g_ent[ks], g_userid[ks], g_last[ks], g_target[ks]);
    }
}
