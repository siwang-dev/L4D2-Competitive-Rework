#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>

#define TEAM_SPECTATOR 1
#define TEAM_SURVIVOR 2
#define TEAM_INFECTED 3

#define MAX_AUTH_LENGTH 64
#define RATING_FILE "data/rating_data.cfg"

ConVar g_cvDefaultRating;
ConVar g_cvMinRoundsForModel;
ConVar g_cvKSurvivorDamage;
ConVar g_cvKCommon;
ConVar g_cvKSIKills;
ConVar g_cvKInfectedDamage;
ConVar g_cvKPins;
ConVar g_cvKFriendlyFire;
ConVar g_cvKIncap;
ConVar g_cvKDeath;
ConVar g_cvDeltaScale;

float g_fRating[MAXPLAYERS + 1];
float g_fBaselineRating[MAXPLAYERS + 1];
float g_fRoundSurvivorDamage[MAXPLAYERS + 1];
float g_fRoundInfectedDamage[MAXPLAYERS + 1];
float g_fRoundFriendlyFire[MAXPLAYERS + 1];
float g_fRoundPerformanceSum[MAXPLAYERS + 1];

int g_iCompletedRounds[MAXPLAYERS + 1];
int g_iRoundCommonKills[MAXPLAYERS + 1];
int g_iRoundSIKills[MAXPLAYERS + 1];
int g_iRoundPins[MAXPLAYERS + 1];
int g_iRoundIncaps[MAXPLAYERS + 1];
int g_iRoundDeaths[MAXPLAYERS + 1];
int g_iTargetTeam[MAXPLAYERS + 1];

bool g_bLoaded[MAXPLAYERS + 1];
bool g_bNewPlayer[MAXPLAYERS + 1];
bool g_bRoundTouched[MAXPLAYERS + 1];

public Plugin myinfo =
{
    name = "L4D2 Versus Rating",
    author = "OpenAI",
    description = "Tracks provisional ratings and balances teams by average rating.",
    version = "1.0.0",
    url = "https://openai.com"
};

public void OnPluginStart()
{
    g_cvDefaultRating = CreateConVar("sm_rating_default", "1000.0", "Default rating for brand new players.");
    g_cvMinRoundsForModel = CreateConVar("sm_rating_model_rounds", "2", "How many completed rounds are required before the performance model fully takes over.", _, true, 1.0, true, 10.0);
    g_cvKSurvivorDamage = CreateConVar("sm_rating_k_survivor_damage", "0.45", "Score weight for survivor damage dealt to SI/tank/witch.");
    g_cvKCommon = CreateConVar("sm_rating_k_common", "0.02", "Score weight for common infected kills.");
    g_cvKSIKills = CreateConVar("sm_rating_k_sikills", "8.0", "Score weight for special infected kills.");
    g_cvKInfectedDamage = CreateConVar("sm_rating_k_infected_damage", "0.35", "Score weight for infected damage dealt to survivors.");
    g_cvKPins = CreateConVar("sm_rating_k_pins", "10.0", "Score weight for successful infected pins.");
    g_cvKFriendlyFire = CreateConVar("sm_rating_k_ff", "0.30", "Penalty weight for friendly fire damage.");
    g_cvKIncap = CreateConVar("sm_rating_k_incap", "18.0", "Penalty weight for survivor incapacitations.");
    g_cvKDeath = CreateConVar("sm_rating_k_death", "25.0", "Penalty weight for deaths.");
    g_cvDeltaScale = CreateConVar("sm_rating_delta_scale", "0.12", "Scale applied to the round performance delta after provisional placement.");

    RegConsoleCmd("sm_rating", Command_ShowRating, "Show your current rating and sample count.");
    RegAdminCmd("sm_balancebyrating", Command_BalanceByRating, ADMFLAG_GENERIC, "Balance survivor/infected teams by average rating.");
    RegAdminCmd("sm_ratingbalance", Command_BalanceByRating, ADMFLAG_GENERIC, "Balance survivor/infected teams by average rating.");

    HookEvent("player_hurt", Event_PlayerHurt, EventHookMode_Post);
    HookEvent("infected_hurt", Event_InfectedHurt, EventHookMode_Post);
    HookEvent("infected_death", Event_InfectedDeath, EventHookMode_Post);
    HookEvent("player_death", Event_PlayerDeath, EventHookMode_Post);
    HookEvent("player_incapacitated_start", Event_PlayerIncapacitated, EventHookMode_Post);
    HookEvent("tongue_grab", Event_PinStart, EventHookMode_Post);
    HookEvent("lunge_pounce", Event_PinStart, EventHookMode_Post);
    HookEvent("jockey_ride", Event_PinStart, EventHookMode_Post);
    HookEvent("charger_pummel_start", Event_PinStart, EventHookMode_Post);
    HookEvent("charger_carry_start", Event_PinStart, EventHookMode_Post);
    HookEvent("round_end", Event_RoundEnd, EventHookMode_PostNoCopy);

    AutoExecConfig(true, "rating");

    for (int client = 1; client <= MaxClients; client++)
    {
        ResetClientState(client);
        if (IsClientInGame(client))
        {
            OnClientPutInServer(client);
            if (HasClientSteamId(client))
            {
                char auth[MAX_AUTH_LENGTH];
                GetClientAuthId(client, AuthId_Steam2, auth, sizeof(auth), true);
                LoadClientRating(client, auth);
            }
        }
    }
}

public void OnClientPutInServer(int client)
{
    ResetRoundStats(client);
    g_iTargetTeam[client] = 0;
}

public void OnClientDisconnect(int client)
{
    SaveClientRating(client);
    ResetClientState(client);
}

public void OnClientAuthorized(int client, const char[] auth)
{
    if (IsFakeClient(client))
    {
        return;
    }

    LoadClientRating(client, auth);
}

public Action Command_ShowRating(int client, int args)
{
    if (!IsValidHuman(client))
    {
        ReplyToCommand(client, "[Rating] 只有玩家本人可以查看 rating。");
        return Plugin_Handled;
    }

    ReplyToCommand(client, "[Rating] 当前 Rating: %.1f | 已完成局数: %d | 状态: %s", g_fRating[client], g_iCompletedRounds[client], g_bNewPlayer[client] ? "新玩家分析中" : "已稳定");
    return Plugin_Handled;
}

public Action Command_BalanceByRating(int client, int args)
{
    int players[MAXPLAYERS];
    int count = CollectActivePlayers(players, sizeof(players));
    if (count < 2)
    {
        ReplyToCommand(client, "[Rating] 在线人数不足，无法平衡队伍。");
        return Plugin_Handled;
    }

    SortPlayersByRating(players, count);

    int survivorTeam[MAXPLAYERS];
    int infectedTeam[MAXPLAYERS];
    int survivorCount = 0;
    int infectedCount = 0;
    float survivorTotal = 0.0;
    float infectedTotal = 0.0;
    int maxPerTeam = (count + 1) / 2;

    for (int i = 0; i < count; i++)
    {
        int targetClient = players[i];
        float rating = g_fRating[targetClient];

        bool putSurvivor = false;
        if (survivorCount >= maxPerTeam)
        {
            putSurvivor = false;
        }
        else if (infectedCount >= maxPerTeam)
        {
            putSurvivor = true;
        }
        else if (survivorCount < infectedCount)
        {
            putSurvivor = true;
        }
        else if (infectedCount < survivorCount)
        {
            putSurvivor = false;
        }
        else
        {
            putSurvivor = survivorTotal <= infectedTotal;
        }

        if (putSurvivor)
        {
            survivorTeam[survivorCount++] = targetClient;
            survivorTotal += rating;
            g_iTargetTeam[targetClient] = TEAM_SURVIVOR;
        }
        else
        {
            infectedTeam[infectedCount++] = targetClient;
            infectedTotal += rating;
            g_iTargetTeam[targetClient] = TEAM_INFECTED;
        }
    }

    for (int i = 0; i < count; i++)
    {
        int targetClient = players[i];
        if (GetClientTeam(targetClient) != g_iTargetTeam[targetClient])
        {
            ChangeClientTeam(targetClient, TEAM_SPECTATOR);
        }
    }

    CreateTimer(0.3, Timer_ApplyBalance, _, TIMER_FLAG_NO_MAPCHANGE);

    float survivorAvg = survivorCount > 0 ? survivorTotal / float(survivorCount) : 0.0;
    float infectedAvg = infectedCount > 0 ? infectedTotal / float(infectedCount) : 0.0;
    PrintToChatAll("[Rating] 已按 Rating 平均分队，生还者均分 %.1f / 感染者均分 %.1f。", survivorAvg, infectedAvg);

    return Plugin_Handled;
}

public Action Timer_ApplyBalance(Handle timer)
{
    for (int client = 1; client <= MaxClients; client++)
    {
        if (!IsValidHuman(client) || g_iTargetTeam[client] == 0)
        {
            continue;
        }

        if (GetClientTeam(client) != g_iTargetTeam[client])
        {
            ChangeClientTeam(client, g_iTargetTeam[client]);
        }

        g_iTargetTeam[client] = 0;
    }

    return Plugin_Stop;
}

public void Event_PlayerHurt(Event event, const char[] name, bool dontBroadcast)
{
    int victim = GetClientOfUserId(event.GetInt("userid"));
    int attacker = GetClientOfUserId(event.GetInt("attacker"));
    int dmg = event.GetInt("dmg_health");

    if (dmg <= 0 || !IsValidHuman(attacker) || !IsValidHuman(victim) || attacker == victim)
    {
        return;
    }

    int attackerTeam = GetClientTeam(attacker);
    int victimTeam = GetClientTeam(victim);

    if (attackerTeam == TEAM_SURVIVOR && victimTeam == TEAM_SURVIVOR)
    {
        g_fRoundFriendlyFire[attacker] += float(dmg);
        g_bRoundTouched[attacker] = true;
    }
    else if (attackerTeam == TEAM_INFECTED && victimTeam == TEAM_SURVIVOR)
    {
        g_fRoundInfectedDamage[attacker] += float(dmg);
        g_bRoundTouched[attacker] = true;
    }
}

public void Event_InfectedHurt(Event event, const char[] name, bool dontBroadcast)
{
    int attacker = GetClientOfUserId(event.GetInt("attacker"));
    int amount = event.GetInt("amount");

    if (amount <= 0 || !IsValidHuman(attacker) || GetClientTeam(attacker) != TEAM_SURVIVOR)
    {
        return;
    }

    g_fRoundSurvivorDamage[attacker] += float(amount);
    g_bRoundTouched[attacker] = true;
}

public void Event_InfectedDeath(Event event, const char[] name, bool dontBroadcast)
{
    int attacker = GetClientOfUserId(event.GetInt("attacker"));
    if (!IsValidHuman(attacker) || GetClientTeam(attacker) != TEAM_SURVIVOR)
    {
        return;
    }

    g_iRoundCommonKills[attacker]++;
    g_bRoundTouched[attacker] = true;
}

public void Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
    int victim = GetClientOfUserId(event.GetInt("userid"));
    int attacker = GetClientOfUserId(event.GetInt("attacker"));

    if (IsValidHuman(attacker) && IsClientInGame(victim) && attacker != victim)
    {
        if (GetClientTeam(attacker) == TEAM_SURVIVOR && GetClientTeam(victim) == TEAM_INFECTED)
        {
            g_iRoundSIKills[attacker]++;
            g_bRoundTouched[attacker] = true;
        }
    }

    if (IsValidHuman(victim) && GetClientTeam(victim) == TEAM_SURVIVOR)
    {
        g_iRoundDeaths[victim]++;
        g_bRoundTouched[victim] = true;
    }
}

public void Event_PlayerIncapacitated(Event event, const char[] name, bool dontBroadcast)
{
    int victim = GetClientOfUserId(event.GetInt("userid"));
    if (!IsValidHuman(victim) || GetClientTeam(victim) != TEAM_SURVIVOR)
    {
        return;
    }

    g_iRoundIncaps[victim]++;
    g_bRoundTouched[victim] = true;
}

public void Event_PinStart(Event event, const char[] name, bool dontBroadcast)
{
    int attacker = GetClientOfUserId(event.GetInt("userid"));
    if (!IsValidHuman(attacker) || GetClientTeam(attacker) != TEAM_INFECTED)
    {
        return;
    }

    g_iRoundPins[attacker]++;
    g_bRoundTouched[attacker] = true;
}

public void Event_RoundEnd(Event event, const char[] name, bool dontBroadcast)
{
    for (int client = 1; client <= MaxClients; client++)
    {
        if (!IsValidHuman(client) || !g_bLoaded[client])
        {
            continue;
        }

        if (!g_bRoundTouched[client])
        {
            ResetRoundStats(client);
            continue;
        }

        float performance = CalculateRoundPerformance(client);
        g_fRoundPerformanceSum[client] += performance;
        g_iCompletedRounds[client]++;
        ApplyRoundRating(client, performance);
        SaveClientRating(client);

        if (g_iCompletedRounds[client] == g_cvMinRoundsForModel.IntValue)
        {
            PrintToChat(client, "[Rating] 已完成 %d 局数据分析，当前 Rating 更新为 %.1f。", g_iCompletedRounds[client], g_fRating[client]);
        }
        else
        {
            PrintToChat(client, "[Rating] 本局表现分 %.1f，当前 Rating %.1f。", performance, g_fRating[client]);
        }

        ResetRoundStats(client);
    }
}

float CalculateRoundPerformance(int client)
{
    float score = 0.0;
    score += g_fRoundSurvivorDamage[client] * g_cvKSurvivorDamage.FloatValue;
    score += float(g_iRoundCommonKills[client]) * g_cvKCommon.FloatValue;
    score += float(g_iRoundSIKills[client]) * g_cvKSIKills.FloatValue;
    score += g_fRoundInfectedDamage[client] * g_cvKInfectedDamage.FloatValue;
    score += float(g_iRoundPins[client]) * g_cvKPins.FloatValue;
    score -= g_fRoundFriendlyFire[client] * g_cvKFriendlyFire.FloatValue;
    score -= float(g_iRoundIncaps[client]) * g_cvKIncap.FloatValue;
    score -= float(g_iRoundDeaths[client]) * g_cvKDeath.FloatValue;
    return score;
}

void ApplyRoundRating(int client, float performance)
{
    int minRounds = g_cvMinRoundsForModel.IntValue;

    if (g_iCompletedRounds[client] <= minRounds)
    {
        float averagePerformance = g_fRoundPerformanceSum[client] / float(g_iCompletedRounds[client]);
        float modeledRating = 1000.0 + averagePerformance * 2.5;
        g_fRating[client] = ClampFloat((g_fBaselineRating[client] * 0.35) + (modeledRating * 0.65), 600.0, 2400.0);
        g_bNewPlayer[client] = g_iCompletedRounds[client] < minRounds;
        return;
    }

    float delta = (performance - 120.0) * g_cvDeltaScale.FloatValue;
    g_fRating[client] = ClampFloat(g_fRating[client] + delta, 600.0, 2400.0);
    g_bNewPlayer[client] = false;
}

void LoadClientRating(int client, const char[] auth)
{
    if (!IsValidHuman(client))
    {
        return;
    }

    KeyValues kv = new KeyValues("Ratings");
    char path[PLATFORM_MAX_PATH];
    BuildPath(Path_SM, path, sizeof(path), RATING_FILE);

    if (FileExists(path))
    {
        kv.ImportFromFile(path);
    }

    if (kv.JumpToKey(auth, false))
    {
        g_fRating[client] = kv.GetFloat("rating", g_cvDefaultRating.FloatValue);
        g_fBaselineRating[client] = kv.GetFloat("baseline", g_fRating[client]);
        g_iCompletedRounds[client] = kv.GetNum("rounds", 0);
        g_fRoundPerformanceSum[client] = kv.GetFloat("performance_sum", 0.0);
        g_bNewPlayer[client] = view_as<bool>(kv.GetNum("provisional", 0));
        g_bLoaded[client] = true;
        delete kv;
        return;
    }

    float baseline = CalculateInitialRating();
    g_fRating[client] = baseline;
    g_fBaselineRating[client] = baseline;
    g_iCompletedRounds[client] = 0;
    g_fRoundPerformanceSum[client] = 0.0;
    g_bLoaded[client] = true;
    g_bNewPlayer[client] = true;

    SaveClientRating(client);

    PrintToChat(client, "[Rating] 首次进入服务器，已根据现有玩家数据为你生成初始 Rating: %.1f。完成 %d 局后会自动按局内数据校准。", baseline, g_cvMinRoundsForModel.IntValue);

    delete kv;
}

void SaveClientRating(int client)
{
    if (!g_bLoaded[client] || IsFakeClient(client))
    {
        return;
    }

    char auth[MAX_AUTH_LENGTH];
    if (!GetClientAuthId(client, AuthId_Steam2, auth, sizeof(auth), true))
    {
        return;
    }

    KeyValues kv = new KeyValues("Ratings");
    char path[PLATFORM_MAX_PATH];
    BuildPath(Path_SM, path, sizeof(path), RATING_FILE);

    if (FileExists(path))
    {
        kv.ImportFromFile(path);
    }

    kv.JumpToKey(auth, true);
    kv.SetFloat("rating", g_fRating[client]);
    kv.SetFloat("baseline", g_fBaselineRating[client]);
    kv.SetNum("rounds", g_iCompletedRounds[client]);
    kv.SetFloat("performance_sum", g_fRoundPerformanceSum[client]);
    kv.SetNum("provisional", g_bNewPlayer[client] ? 1 : 0);
    kv.Rewind();
    kv.ExportToFile(path);
    delete kv;
}

float CalculateInitialRating()
{
    float total = 0.0;
    int count = 0;

    for (int client = 1; client <= MaxClients; client++)
    {
        if (!IsValidHuman(client) || !g_bLoaded[client])
        {
            continue;
        }

        total += g_fRating[client];
        count++;
    }

    if (count == 0)
    {
        return g_cvDefaultRating.FloatValue;
    }

    return total / float(count);
}

int CollectActivePlayers(int[] players, int maxPlayers)
{
    int count = 0;
    for (int client = 1; client <= MaxClients && count < maxPlayers; client++)
    {
        if (!IsValidHuman(client))
        {
            continue;
        }

        int team = GetClientTeam(client);
        if (team != TEAM_SURVIVOR && team != TEAM_INFECTED)
        {
            continue;
        }

        players[count++] = client;
    }

    return count;
}

void SortPlayersByRating(int[] players, int count)
{
    for (int i = 0; i < count - 1; i++)
    {
        for (int j = i + 1; j < count; j++)
        {
            if (g_fRating[players[j]] > g_fRating[players[i]])
            {
                int temp = players[i];
                players[i] = players[j];
                players[j] = temp;
            }
        }
    }
}

bool IsValidHuman(int client)
{
    return client > 0 && client <= MaxClients && IsClientInGame(client) && !IsFakeClient(client);
}

bool HasClientSteamId(int client)
{
    char auth[MAX_AUTH_LENGTH];
    return GetClientAuthId(client, AuthId_Steam2, auth, sizeof(auth), true);
}

void ResetRoundStats(int client)
{
    g_fRoundSurvivorDamage[client] = 0.0;
    g_fRoundInfectedDamage[client] = 0.0;
    g_fRoundFriendlyFire[client] = 0.0;
    g_iRoundCommonKills[client] = 0;
    g_iRoundSIKills[client] = 0;
    g_iRoundPins[client] = 0;
    g_iRoundIncaps[client] = 0;
    g_iRoundDeaths[client] = 0;
    g_bRoundTouched[client] = false;
}

void ResetClientState(int client)
{
    g_fRating[client] = 0.0;
    g_fBaselineRating[client] = 0.0;
    g_fRoundPerformanceSum[client] = 0.0;
    g_iCompletedRounds[client] = 0;
    g_bLoaded[client] = false;
    g_bNewPlayer[client] = false;
    g_iTargetTeam[client] = 0;
    ResetRoundStats(client);
}

float ClampFloat(float value, float minValue, float maxValue)
{
    if (value < minValue)
    {
        return minValue;
    }

    if (value > maxValue)
    {
        return maxValue;
    }

    return value;
}
