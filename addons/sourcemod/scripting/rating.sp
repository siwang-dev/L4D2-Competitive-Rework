#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>

#define TEAM_SPECTATOR 1
#define TEAM_SURVIVOR 2
#define TEAM_INFECTED 3

#define L4D2_APPID 550
#define MAX_AUTH_LENGTH 64
#define MAX_NAME_LENGTH_EXTENDED 128
#define MAX_HTTP_BODY_LENGTH 32768
#define RATING_FILE "data/rating_data.cfg"

enum EHTTPMethod
{
    k_EHTTPMethodInvalid = 0,
    k_EHTTPMethodGET,
    k_EHTTPMethodHEAD,
    k_EHTTPMethodPOST,
    k_EHTTPMethodPUT,
    k_EHTTPMethodDELETE,
    k_EHTTPMethodOPTIONS,
    k_EHTTPMethodPATCH
};

enum EHTTPStatusCode
{
    k_EHTTPStatusCodeInvalid = 0,
    k_EHTTPStatusCode200OK = 200
};

typeset SteamWorksHTTPRequestCompleted
{
    function void (Handle hRequest, bool bFailure, bool bRequestSuccessful, EHTTPStatusCode eStatusCode);
    function void (Handle hRequest, bool bFailure, bool bRequestSuccessful, EHTTPStatusCode eStatusCode, any data1);
    function void (Handle hRequest, bool bFailure, bool bRequestSuccessful, EHTTPStatusCode eStatusCode, any data1, any data2);
};

native bool SteamWorks_IsLoaded();
native Handle SteamWorks_CreateHTTPRequest(EHTTPMethod method, const char[] sURL);
native bool SteamWorks_SetHTTPRequestContextValue(Handle hHandle, any data1, any data2 = 0);
native bool SteamWorks_SetHTTPRequestNetworkActivityTimeout(Handle hHandle, int timeout);
native bool SteamWorks_SetHTTPRequestUserAgentInfo(Handle hHandle, const char[] sUserAgentInfo);
native bool SteamWorks_SetHTTPCallbacks(Handle hHandle, SteamWorksHTTPRequestCompleted fCompleted = INVALID_FUNCTION, Function fHeaders = INVALID_FUNCTION, Function fData = INVALID_FUNCTION, Handle hCalling = INVALID_HANDLE);
native bool SteamWorks_SendHTTPRequest(Handle hRequest);
native bool SteamWorks_GetHTTPResponseBodySize(Handle hRequest, int &size);
native bool SteamWorks_GetHTTPResponseBodyData(Handle hRequest, char[] sBody, int length);

public Extension __ext_SteamWorks =
{
    name = "SteamWorks",
    file = "SteamWorks.ext",
#if defined AUTOLOAD_EXTENSIONS
    autoload = 1,
#else
    autoload = 0,
#endif
#if defined REQUIRE_EXTENSIONS
    required = 1,
#else
    required = 0,
#endif
};

#if !defined REQUIRE_EXTENSIONS
public void __ext_SteamWorks_SetNTVOptional()
{
    MarkNativeAsOptional("SteamWorks_IsLoaded");
    MarkNativeAsOptional("SteamWorks_CreateHTTPRequest");
    MarkNativeAsOptional("SteamWorks_SetHTTPRequestContextValue");
    MarkNativeAsOptional("SteamWorks_SetHTTPRequestNetworkActivityTimeout");
    MarkNativeAsOptional("SteamWorks_SetHTTPRequestUserAgentInfo");
    MarkNativeAsOptional("SteamWorks_SetHTTPCallbacks");
    MarkNativeAsOptional("SteamWorks_SendHTTPRequest");
    MarkNativeAsOptional("SteamWorks_GetHTTPResponseBodySize");
    MarkNativeAsOptional("SteamWorks_GetHTTPResponseBodyData");
}
#endif

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
ConVar g_cvSteamApiKey;
ConVar g_cvSteamStatWeight;
ConVar g_cvSteamAnchorScale;

float g_fRating[MAXPLAYERS + 1];
float g_fBaselineRating[MAXPLAYERS + 1];
float g_fRoundSurvivorDamage[MAXPLAYERS + 1];
float g_fRoundInfectedDamage[MAXPLAYERS + 1];
float g_fRoundFriendlyFire[MAXPLAYERS + 1];
float g_fRoundPerformanceSum[MAXPLAYERS + 1];
float g_fSteamSeedRating[MAXPLAYERS + 1];

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
bool g_bSteamStatsRequested[MAXPLAYERS + 1];
bool g_bSteamStatsReady[MAXPLAYERS + 1];

public Plugin myinfo =
{
    name = "L4D2 Versus Rating",
    author = "OpenAI",
    description = "Tracks ratings, imports Steam stats, and balances teams by average rating.",
    version = "1.1.0",
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
    g_cvSteamApiKey = CreateConVar("sm_rating_steam_api_key", "", "Steam Web API key used for ISteamUserStats/GetUserStatsForGame lookups. Leave empty to disable Steam stat import.", FCVAR_PROTECTED);
    g_cvSteamStatWeight = CreateConVar("sm_rating_steam_weight", "0.30", "How strongly imported Steam lifetime stats influence provisional placement and steady-state anchoring.", _, true, 0.0, true, 1.0);
    g_cvSteamAnchorScale = CreateConVar("sm_rating_steam_anchor_scale", "0.01", "Per-round anchor factor pulling ratings toward the imported Steam seed after provisional placement.", _, true, 0.0, true, 0.05);

    RegConsoleCmd("sm_rating", Command_ShowRating, "Show all active players' ratings.");
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
        if (!IsClientInGame(client))
        {
            continue;
        }

        OnClientPutInServer(client);
        if (!HasClientSteamId(client))
        {
            continue;
        }

        char auth[MAX_AUTH_LENGTH];
        GetClientAuthId(client, AuthId_Steam2, auth, sizeof(auth), true);
        LoadClientRating(client, auth);
        RequestSteamStatsIfPossible(client);
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
    RequestSteamStatsIfPossible(client);
}

public Action Command_ShowRating(int client, int args)
{
    int players[MAXPLAYERS];
    int count = CollectActivePlayers(players, sizeof(players));
    SortPlayersByRating(players, count);

    if (client > 0)
    {
        ReplyToCommand(client, "[Rating] 场上玩家 Rating 列表已输出到你的控制台。共 %d 人。", count);
        PrintToConsole(client, "================ L4D2 Rating =================");
    }
    else
    {
        PrintToServer("================ L4D2 Rating =================");
    }

    if (count == 0)
    {
        ReplyConsoleLine(client, "[Rating] 当前场上没有生还者/感染者玩家。", 0);
        return Plugin_Handled;
    }

    for (int i = 0; i < count; i++)
    {
        int targetClient = players[i];
        char playerName[MAX_NAME_LENGTH_EXTENDED];
        GetClientName(targetClient, playerName, sizeof(playerName));

        char teamName[16];
        GetReadableTeamName(targetClient, teamName, sizeof(teamName));

        char stability[24];
        Format(stability, sizeof(stability), "%s", g_bNewPlayer[targetClient] ? "分析中" : "稳定");

        if (g_bSteamStatsReady[targetClient])
        {
            ReplyConsoleLine(client, "#%d [%s] %s | Rating %.1f | 局数 %d | SteamSeed %.1f | %s", i + 1, teamName, playerName, g_fRating[targetClient], g_iCompletedRounds[targetClient], g_fSteamSeedRating[targetClient], stability);
        }
        else
        {
            ReplyConsoleLine(client, "#%d [%s] %s | Rating %.1f | 局数 %d | SteamSeed 未就绪 | %s", i + 1, teamName, playerName, g_fRating[targetClient], g_iCompletedRounds[targetClient], stability);
        }
    }

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
            survivorCount++;
            survivorTotal += rating;
            g_iTargetTeam[targetClient] = TEAM_SURVIVOR;
        }
        else
        {
            infectedCount++;
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
    float steamWeight = g_bSteamStatsReady[client] ? g_cvSteamStatWeight.FloatValue : 0.0;

    if (g_iCompletedRounds[client] <= minRounds)
    {
        float averagePerformance = g_fRoundPerformanceSum[client] / float(g_iCompletedRounds[client]);
        float modeledRating = 1000.0 + averagePerformance * 2.5;

        if (steamWeight > 0.0)
        {
            modeledRating = (modeledRating * (1.0 - steamWeight)) + (g_fSteamSeedRating[client] * steamWeight);
        }

        g_fRating[client] = ClampFloat((g_fBaselineRating[client] * 0.35) + (modeledRating * 0.65), 600.0, 2400.0);
        g_bNewPlayer[client] = g_iCompletedRounds[client] < minRounds;
        return;
    }

    float delta = (performance - 120.0) * g_cvDeltaScale.FloatValue;
    if (steamWeight > 0.0)
    {
        float anchorDelta = ClampFloat((g_fSteamSeedRating[client] - g_fRating[client]) * g_cvSteamAnchorScale.FloatValue, -6.0, 6.0);
        delta += anchorDelta;
    }

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
        g_fSteamSeedRating[client] = kv.GetFloat("steam_seed", 0.0);
        g_bSteamStatsReady[client] = g_fSteamSeedRating[client] > 0.0;
        g_bNewPlayer[client] = view_as<bool>(kv.GetNum("provisional", 0));
        g_bLoaded[client] = true;

        if (g_bSteamStatsReady[client])
        {
            ApplySteamSeedToRating(client, false);
        }

        delete kv;
        return;
    }

    float baseline = CalculateInitialRating();
    g_fRating[client] = baseline;
    g_fBaselineRating[client] = baseline;
    g_iCompletedRounds[client] = 0;
    g_fRoundPerformanceSum[client] = 0.0;
    g_fSteamSeedRating[client] = 0.0;
    g_bSteamStatsReady[client] = false;
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
    kv.SetFloat("steam_seed", g_fSteamSeedRating[client]);
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

void RequestSteamStatsIfPossible(int client)
{
    if (!IsValidHuman(client) || !g_bLoaded[client] || g_bSteamStatsRequested[client])
    {
        return;
    }

    char apiKey[128];
    g_cvSteamApiKey.GetString(apiKey, sizeof(apiKey));
    if (apiKey[0] == '\0')
    {
        return;
    }

    if (!SteamWorks_IsLoaded())
    {
        LogMessage("[Rating] SteamWorks extension not loaded; skipping Steam stat import for client %N.", client);
        return;
    }

    char steamId64[32];
    if (!GetClientAuthId(client, AuthId_SteamID64, steamId64, sizeof(steamId64), true))
    {
        return;
    }

    char url[256];
    Format(url, sizeof(url), "https://api.steampowered.com/ISteamUserStats/GetUserStatsForGame/v2/?appid=%d&key=%s&steamid=%s", L4D2_APPID, apiKey, steamId64);

    Handle request = SteamWorks_CreateHTTPRequest(k_EHTTPMethodGET, url);
    if (request == null)
    {
        LogMessage("[Rating] Failed to create Steam stats HTTP request for %N.", client);
        return;
    }

    int userid = GetClientUserId(client);
    SteamWorks_SetHTTPRequestContextValue(request, userid, 0);
    SteamWorks_SetHTTPRequestNetworkActivityTimeout(request, 10);
    SteamWorks_SetHTTPRequestUserAgentInfo(request, "L4D2-Competitive-Rework-Rating/1.1");
    SteamWorks_SetHTTPCallbacks(request, OnSteamStatsRequestComplete);

    if (!SteamWorks_SendHTTPRequest(request))
    {
        LogMessage("[Rating] Failed to dispatch Steam stats HTTP request for %N.", client);
        delete request;
        return;
    }

    g_bSteamStatsRequested[client] = true;
}

public void OnSteamStatsRequestComplete(Handle hRequest, bool bFailure, bool bRequestSuccessful, EHTTPStatusCode eStatusCode, any data1, any data2)
{
    int client = GetClientOfUserId(data1);
    if (client <= 0)
    {
        delete hRequest;
        return;
    }

    g_bSteamStatsRequested[client] = false;

    if (bFailure || !bRequestSuccessful || eStatusCode != k_EHTTPStatusCode200OK)
    {
        LogMessage("[Rating] Steam stats request failed for %N (failure=%d success=%d status=%d).", client, bFailure, bRequestSuccessful, eStatusCode);
        delete hRequest;
        return;
    }

    int size = 0;
    if (!SteamWorks_GetHTTPResponseBodySize(hRequest, size) || size <= 0 || size >= MAX_HTTP_BODY_LENGTH)
    {
        LogMessage("[Rating] Invalid Steam stats body size for %N: %d", client, size);
        delete hRequest;
        return;
    }

    char[] body = new char[size + 1];
    if (!SteamWorks_GetHTTPResponseBodyData(hRequest, body, size + 1))
    {
        LogMessage("[Rating] Failed to read Steam stats response body for %N.", client);
        delete hRequest;
        return;
    }

    float seedRating = BuildSteamSeedRatingFromBody(body);
    if (seedRating <= 0.0)
    {
        LogMessage("[Rating] Steam stats response for %N did not contain usable stat pairs.", client);
        delete hRequest;
        return;
    }

    g_fSteamSeedRating[client] = seedRating;
    g_bSteamStatsReady[client] = true;
    ApplySteamSeedToRating(client, true);

    PrintToChat(client, "[Rating] 已导入 Steam 数据，计算得到 SteamSeed %.1f，当前 Rating %.1f。", g_fSteamSeedRating[client], g_fRating[client]);

    delete hRequest;
}

float BuildSteamSeedRatingFromBody(const char[] body)
{
    float score = 0.0;
    int offset = 0;
    int pairs = 0;

    char statName[128];
    float statValue = 0.0;
    int nextOffset = 0;

    while (pairs < 512 && ExtractNextSteamStat(body, offset, statName, sizeof(statName), statValue, nextOffset))
    {
        score += ScoreSteamStat(statName, statValue);
        offset = nextOffset;
        pairs++;
    }

    if (pairs == 0)
    {
        return 0.0;
    }

    return ClampFloat(g_cvDefaultRating.FloatValue + score, 600.0, 2400.0);
}

float ScoreSteamStat(const char[] statName, float rawValue)
{
    float scaled = SquareRoot(FloatAbs(rawValue));
    float score = 0.0;

    bool hasKill = ContainsToken(statName, "kill") || ContainsToken(statName, "kills") || ContainsToken(statName, "killed") || ContainsToken(statName, "slain");
    bool hasCommon = ContainsToken(statName, "common") || ContainsToken(statName, "infected") || ContainsToken(statName, "zombie");
    bool hasSpecial = ContainsToken(statName, "special") || ContainsToken(statName, "smoker") || ContainsToken(statName, "boomer") || ContainsToken(statName, "hunter") || ContainsToken(statName, "spitter") || ContainsToken(statName, "jockey") || ContainsToken(statName, "charger");
    bool hasBoss = ContainsToken(statName, "tank") || ContainsToken(statName, "witch");

    if (hasKill)
    {
        if (hasBoss)
        {
            score += scaled * 8.0;
        }
        else if (hasSpecial)
        {
            score += scaled * 6.0;
        }
        else if (hasCommon)
        {
            score += scaled * 0.35;
        }
        else
        {
            score += scaled * 1.0;
        }
    }

    if (ContainsToken(statName, "damage"))
    {
        if (ContainsToken(statName, "surviv") || ContainsToken(statName, "teammate") || ContainsToken(statName, "friendly"))
        {
            score -= scaled * 1.8;
        }
        else if (hasBoss)
        {
            score += scaled * 1.3;
        }
        else
        {
            score += scaled * 0.6;
        }
    }

    if (ContainsToken(statName, "revive") || ContainsToken(statName, "defib") || ContainsToken(statName, "rescue") || ContainsToken(statName, "heal") || ContainsToken(statName, "protect"))
    {
        score += scaled * 4.0;
    }

    if (ContainsToken(statName, "death") || ContainsToken(statName, "dead"))
    {
        score -= scaled * 5.0;
    }

    if (ContainsToken(statName, "incap"))
    {
        score -= scaled * 3.5;
    }

    if (ContainsToken(statName, "friendly") || ContainsToken(statName, "teamkill"))
    {
        score -= scaled * 4.5;
    }

    return score;
}

void ApplySteamSeedToRating(int client, bool saveAfter)
{
    if (!g_bLoaded[client] || !g_bSteamStatsReady[client])
    {
        return;
    }

    float steamWeight = g_cvSteamStatWeight.FloatValue;
    float baselineBlend = 0.20 + (steamWeight * 0.40);
    baselineBlend = ClampFloat(baselineBlend, 0.20, 0.60);

    g_fBaselineRating[client] = ClampFloat((g_fBaselineRating[client] * (1.0 - baselineBlend)) + (g_fSteamSeedRating[client] * baselineBlend), 600.0, 2400.0);

    if (g_iCompletedRounds[client] == 0)
    {
        float currentBlend = 0.50 + (steamWeight * 0.30);
        g_fRating[client] = ClampFloat((g_fRating[client] * (1.0 - currentBlend)) + (g_fSteamSeedRating[client] * currentBlend), 600.0, 2400.0);
    }
    else if (g_iCompletedRounds[client] < g_cvMinRoundsForModel.IntValue)
    {
        g_fRating[client] = ClampFloat((g_fRating[client] * 0.75) + (g_fSteamSeedRating[client] * 0.25), 600.0, 2400.0);
    }

    if (saveAfter)
    {
        SaveClientRating(client);
    }
}

bool ExtractNextSteamStat(const char[] body, int offset, char[] statName, int statNameLen, float &statValue, int &nextOffset)
{
    int nameField = FindSubstringFrom(body, "\"name\"", offset);
    if (nameField == -1)
    {
        return false;
    }

    int nameColon = FindNextChar(body, ':', nameField);
    if (nameColon == -1)
    {
        return false;
    }

    int nameStartQuote = FindNextChar(body, '"', nameColon + 1);
    if (nameStartQuote == -1)
    {
        return false;
    }

    int nameEndQuote = FindNextChar(body, '"', nameStartQuote + 1);
    if (nameEndQuote == -1)
    {
        return false;
    }

    CopySlice(body, nameStartQuote + 1, nameEndQuote, statName, statNameLen);

    int valueField = FindSubstringFrom(body, "\"value\"", nameEndQuote);
    if (valueField == -1)
    {
        return false;
    }

    int valueColon = FindNextChar(body, ':', valueField);
    if (valueColon == -1)
    {
        return false;
    }

    int valueStart = valueColon + 1;
    while (body[valueStart] != '\0' && IsJsonWhitespace(body[valueStart]))
    {
        valueStart++;
    }

    int valueEnd = valueStart;
    while (body[valueEnd] != '\0' && IsJsonNumberChar(body[valueEnd]))
    {
        valueEnd++;
    }

    if (valueEnd == valueStart)
    {
        return false;
    }

    char valueBuffer[32];
    CopySlice(body, valueStart, valueEnd, valueBuffer, sizeof(valueBuffer));
    TrimString(valueBuffer);
    statValue = StringToFloat(valueBuffer);
    nextOffset = valueEnd;
    return true;
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

void ReplyConsoleLine(int client, const char[] format, any ...)
{
    char buffer[256];
    VFormat(buffer, sizeof(buffer), format, 3);

    if (client > 0)
    {
        PrintToConsole(client, "%s", buffer);
    }
    else
    {
        PrintToServer("%s", buffer);
    }
}

void GetReadableTeamName(int client, char[] buffer, int maxlen)
{
    switch (GetClientTeam(client))
    {
        case TEAM_SURVIVOR:
        {
            strcopy(buffer, maxlen, "Survivor");
        }
        case TEAM_INFECTED:
        {
            strcopy(buffer, maxlen, "Infected");
        }
        default:
        {
            strcopy(buffer, maxlen, "Spec");
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
    g_fSteamSeedRating[client] = 0.0;
    g_iCompletedRounds[client] = 0;
    g_bLoaded[client] = false;
    g_bNewPlayer[client] = false;
    g_bSteamStatsRequested[client] = false;
    g_bSteamStatsReady[client] = false;
    g_iTargetTeam[client] = 0;
    ResetRoundStats(client);
}

bool ContainsToken(const char[] text, const char[] token)
{
    return StrContains(text, token, false) != -1;
}

int FindSubstringFrom(const char[] text, const char[] pattern, int start)
{
    int textLen = strlen(text);
    int patternLen = strlen(pattern);

    if (patternLen == 0 || start < 0 || start >= textLen)
    {
        return -1;
    }

    for (int i = start; i <= textLen - patternLen; i++)
    {
        bool matched = true;
        for (int j = 0; j < patternLen; j++)
        {
            if (text[i + j] != pattern[j])
            {
                matched = false;
                break;
            }
        }

        if (matched)
        {
            return i;
        }
    }

    return -1;
}

int FindNextChar(const char[] text, char needle, int start)
{
    int textLen = strlen(text);
    for (int i = start; i < textLen; i++)
    {
        if (text[i] == needle)
        {
            return i;
        }
    }

    return -1;
}

void CopySlice(const char[] text, int start, int end, char[] buffer, int maxlen)
{
    int length = end - start;
    if (length < 0)
    {
        length = 0;
    }

    if (length >= maxlen)
    {
        length = maxlen - 1;
    }

    for (int i = 0; i < length; i++)
    {
        buffer[i] = text[start + i];
    }

    buffer[length] = '\0';
}

bool IsJsonWhitespace(char value)
{
    return value == ' ' || value == '\t' || value == '\r' || value == '\n';
}

bool IsJsonNumberChar(char value)
{
    return (value >= '0' && value <= '9') || value == '-' || value == '.';
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
