/*  RoundEnd Blocker (Xash-safe minimal, safe team-set, v0.9.3)
 *  Keeps invisible, intangible alive fakeclients to prevent team-elimination round ends.
 *  Delays creation so CSDM / bots finish init (avoids module crashes).
 *
 *  CVARs:
 *    reb_enable 1/0   - enable plugin (default 1)
 *    reb_delay  10.0  - seconds after round/map start to ensure keepers
 *    reb_hide   0/1   - if 1, display keepers as SPECTATOR on scoreboard (engine team stays T/CT)
 *    reb_team   0/1   - 0 = one T + one CT (recommended), 1 = single keeper on CT
 *
 *  Requires modules: amxmodx, cstrike, fakemeta, hamsandwich, fun
 */

#include <amxmodx>
#include <cstrike>
#include <fakemeta>
#include <hamsandwich>
#include <fun>

#define PLUGIN  "RoundEnd Blocker (Xash-safe)"
#define VERSION "0.9.3"
#define AUTHOR  "jklenner"

#define NAME_T   "[OS] RoundKeeperT"
#define NAME_CT  "[OS] RoundKeeperCT"

// Use distinct task-id spaces so tasks don't remove each other
const TASK_TEAM   = 10000;
const TASK_SPAWN  = 20000;
const TASK_HEALID = 12345;

// -------- state --------
new bool:g_isKeeper[33];           // marks our own fakeclients
new CsTeams:g_targetTeam[33];      // desired team for each keeper
new CsTeams:g_lastTeam[33];        // last team we actually applied (NEW)
new g_msgTeamInfo;

// CVARs
new pEnable, pDelay, pHide, pTeam;

// -------- helpers --------
stock bool:is_valid_ent(id)       { return (1 <= id <= get_maxplayers()) && pev_valid(id) == 2; }
stock bool:is_in_game_safe(id)    { return is_valid_ent(id) && is_user_connected(id); }

// ------------------------------------------------------------------

public plugin_init()
{
    register_plugin(PLUGIN, VERSION, AUTHOR);

    pEnable = register_cvar("reb_enable", "1");
    pDelay  = register_cvar("reb_delay",  "10.0");
    pHide   = register_cvar("reb_hide",   "1");
    pTeam   = register_cvar("reb_team",   "0");

    // round start (HLTV new round frame)
    register_event("HLTV", "OnRoundStart", "a", "1=0", "2=0");

    g_msgTeamInfo = get_user_msgid("TeamInfo");
    register_message(g_msgTeamInfo, "Msg_TeamInfo");
}

public plugin_cfg()
{
    if (get_pcvar_num(pEnable))
    {
        set_task(get_pcvar_float(pDelay), "Task_EnsureKeepers");
        // periodic self-heal: keep them alive and on the right teams
        set_task(5.0, "Task_KeepAlive", TASK_HEALID, "", 0, "b");
    }
}

public OnRoundStart()
{
    if (get_pcvar_num(pEnable))
        set_task(get_pcvar_float(pDelay), "Task_EnsureKeepers");
}

public plugin_end()
{
    // Optional: remove keepers on shutdown; harmless if they’re already gone
    for (new i = 1; i <= get_maxplayers(); i++)
        if (g_isKeeper[i] && is_user_connected(i)) server_cmd("kick #%d", get_user_userid(i));
}

// AMXX still calls this on Xash; we also provide client_disconnected below.
public client_disconnect(id)
{
    if (g_isKeeper[id])
    {
        g_isKeeper[id] = false;
        g_targetTeam[id] = CS_TEAM_UNASSIGNED;
        g_lastTeam[id]   = CS_TEAM_UNASSIGNED; // reset (NEW)
        if (get_pcvar_num(pEnable))
            set_task(get_pcvar_float(pDelay), "Task_EnsureKeepers");
    }
}

// To appease the deprecation warning. On Xash it may never fire; harmless if it does.
public client_disconnected(id)
{
    client_disconnect(id);
}

// ---------------- scoreboard masking ----------------

public Msg_TeamInfo(msgid, dest, id)
{
    if (!get_pcvar_num(pEnable) || !get_pcvar_num(pHide))
        return PLUGIN_CONTINUE;

    new pid = get_msg_arg_int(1);
    if (1 <= pid <= get_maxplayers() && g_isKeeper[pid])
    {
        // Only visual: show as Spectator on the scoreboard; engine team remains T/CT
        set_msg_arg_string(2, "SPECTATOR");
    }
    return PLUGIN_CONTINUE;
}

// ---------------- main logic ----------------

public Task_EnsureKeepers()
{
    if (!get_pcvar_num(pEnable)) return;

    if (get_pcvar_num(pTeam) == 0)
    {
        ensure_keeper_for(CS_TEAM_T,  NAME_T);
        ensure_keeper_for(CS_TEAM_CT, NAME_CT);
    }
    else
    {
        ensure_keeper_for(CS_TEAM_CT, NAME_CT); // single-keeper mode
    }
}

public Task_KeepAlive()
{
    if (!get_pcvar_num(pEnable)) return;

    if (get_pcvar_num(pTeam) == 0)
    {
        ensure_keeper_for(CS_TEAM_T,  NAME_T);
        ensure_keeper_for(CS_TEAM_CT, NAME_CT);
    }
    else
    {
        ensure_keeper_for(CS_TEAM_CT, NAME_CT);
    }
}

stock ensure_keeper_for(CsTeams:team, const name[])
{
    new id = find_keeper_by_name(name);

    if (id && is_user_connected(id))
    {
        // Put/keep on desired team safely (deferred) — ONLY if changed
        if (g_lastTeam[id] != team) schedule_set_team(id, team);

        // Ensure alive & properties
        if (!is_user_alive(id))
        {
            remove_task(TASK_SPAWN + id);
            set_task(0.40, "Task_SpawnKeeper", TASK_SPAWN + id);
        }
        else
        {
            apply_keeper_props(id);
        }
        return;
    }

    // Create new fakeclient
    id = create_keeper(name);
    if (!id) return;

    g_isKeeper[id]   = true;
    g_lastTeam[id]   = CS_TEAM_UNASSIGNED; // ensure first set happens (NEW)
    schedule_set_team(id, team);           // will set g_targetTeam and defer team set

    // Spawn a tad later (team likely applied by then)
    remove_task(TASK_SPAWN + id);
    set_task(0.45, "Task_SpawnKeeper", TASK_SPAWN + id);
}

stock schedule_set_team(id, CsTeams:team)
{
    g_targetTeam[id] = team;
    remove_task(TASK_TEAM + id);
    set_task(0.25, "Task_SetTeam", TASK_TEAM + id);
}

public Task_SetTeam(taskid)
{
    new id = taskid - TASK_TEAM;
    if (!(1 <= id <= get_maxplayers())) return;
    if (!g_isKeeper[id])
    {
        remove_task(taskid);
        return;
    }

    if (!is_in_game_safe(id))
    {
        // Try again shortly until in-game
        set_task(0.25, "Task_SetTeam", taskid);
        return;
    }

    new CsTeams:team = g_targetTeam[id];
    if (team == CS_TEAM_UNASSIGNED) team = CS_TEAM_CT;

    // Only set if it actually changed (avoids constant model-update path on Xash)
    if (g_lastTeam[id] != team)
    {
        cs_set_user_team(id, team);
        g_lastTeam[id] = team; // remember (NEW)
    }
}

public Task_SpawnKeeper(taskid)
{
    new id = taskid - TASK_SPAWN;
    if (!(1 <= id <= get_maxplayers())) return;
    if (!g_isKeeper[id] || !is_user_connected(id)) return;

    if (!is_user_alive(id))
        ExecuteHamB(Ham_Spawn, id);

    apply_keeper_props(id);
}

// ---------------- low-level ops ----------------

stock create_keeper(const name[])
{
    // Create fake client, connect, put in server
    new id = engfunc(EngFunc_CreateFakeClient, name);
    if (!id) return 0;

    dllfunc(DLLFunc_ClientConnect, id, name, "127.0.0.1", "127.0.0.1");
    dllfunc(DLLFunc_ClientPutInServer, id);

    // basic safety
    set_pev(id, pev_flags, pev(id, pev_flags) | FL_FAKECLIENT);
    return id;
}

stock apply_keeper_props(id)
{
    if (!is_in_game_safe(id)) return;

    // Invisible, intangible, unkillable, non-interactive
    set_pev(id, pev_effects, pev(id, pev_effects) | EF_NODRAW);
    set_pev(id, pev_takedamage, DAMAGE_NO);
    set_pev(id, pev_solid, SOLID_NOT);
    set_pev(id, pev_movetype, MOVETYPE_NOCLIP);
    set_pev(id, pev_flags, pev(id, pev_flags) | FL_NOTARGET);

    // Huge health just in case some plugin toggles takedamage
    set_pev(id, pev_health, 1000000.0);

    // Strip weapons to avoid odd forwards
    strip_user_weapons(id);
}

stock find_keeper_by_name(const name[])
{
    new maxp = get_maxplayers();
    new pname[32];
    for (new i = 1; i <= maxp; i++)
    {
        if (!is_user_connected(i)) continue;
        if (!g_isKeeper[i]) continue;

        get_user_name(i, pname, charsmax(pname));
        if (equal(pname, name)) return i;
    }
    return 0;
}
