#pragma semicolon 1
#include <sourcemod>
#include <sdktools>
#include <ripext>

#define TEAM_SPEC 1
#define TEAM_SURV 2
#define TEAM_INF  3

#define COLOR_DEFAULT "\x01"
#define COLOR_RED     "\x02"
#define COLOR_LGREEN  "\x03"
#define COLOR_GREEN   "\x04"
#define COLOR_YELLOW  "\x05"

const int MAX_API_RETRY = 2;

char g_sApiKey[128] = "8EC33C57EC1D4BBC1607035258142287";
float g_fExp[MAXPLAYERS + 1];
int   g_iState[MAXPLAYERS + 1];
int   g_iRetryCount[MAXPLAYERS + 1];
bool  g_bLoadedMap[MAXPLAYERS + 1];

int   g_iLocalPlayTime[MAXPLAYERS + 1];
int   g_iLocalKills[MAXPLAYERS + 1];
int   g_iLocalDeaths[MAXPLAYERS + 1];
bool  g_bUsingLocalExp[MAXPLAYERS + 1];

HTTPClient g_hSteamAPIClient;

bool  g_bMixVoteInProgress = false;
int   g_iMixVoteYes = 0;
int   g_iMixVoteNo = 0;
ArrayList g_alMixSurvivors;
ArrayList g_alMixInfected;

public void OnPluginStart()
{
    RegConsoleCmd("sm_exp", Cmd_Exp);
    RegConsoleCmd("sm_mixexp", Cmd_MixExp);

    g_hSteamAPIClient = new HTTPClient("https://api.steampowered.com");
    if (g_hSteamAPIClient == null)
        PrintToServer("[EXP] 错误：无法创建 HTTPClient");

    HookEvent("player_death", Event_PlayerDeath);
    HookEvent("player_incapacitated", Event_PlayerIncap);
    HookEvent("round_start", Event_RoundStart);

    PrintToServer("[EXP] 插件已加载");
}

public void OnPluginEnd()
{
    if (g_hSteamAPIClient != null)
        delete g_hSteamAPIClient;
}

void Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
    int victim = GetClientOfUserId(event.GetInt("userid"));
    int attacker = GetClientOfUserId(event.GetInt("attacker"));

    if (victim > 0 && !IsFakeClient(victim))
        g_iLocalDeaths[victim]++;

    if (attacker > 0 && !IsFakeClient(attacker) && attacker != victim)
        g_iLocalKills[attacker]++;
}

void Event_PlayerIncap(Event event, const char[] name, bool dontBroadcast)
{
    int victim = GetClientOfUserId(event.GetInt("userid"));
    if (victim > 0 && !IsFakeClient(victim))
        g_iLocalDeaths[victim]++;
}

void Event_RoundStart(Event event, const char[] name, bool dontBroadcast)
{
    for (int i = 1; i <= MaxClients; i++)
    {
        if (IsClientInGame(i) && !IsFakeClient(i))
            g_iLocalPlayTime[i] += 5;
    }
}

bool GetSteam64(int client, char[] buffer, int size)
{
    return GetClientAuthId(client, AuthId_SteamID64, buffer, size);
}

public void OnClientPostAdminCheck(int client)
{
    if (!IsClientInGame(client) || IsFakeClient(client))
        return;

    g_iLocalPlayTime[client] = 0;
    g_iLocalKills[client] = 0;
    g_iLocalDeaths[client] = 0;
    g_bUsingLocalExp[client] = false;

    g_bLoadedMap[client] = false;
    g_iRetryCount[client] = 0;

    CreateTimer(2.0, Timer_LoadEXP, GetClientUserId(client));
}

public Action Timer_LoadEXP(Handle timer, any userid)
{
    int client = GetClientOfUserId(userid);
    if (client > 0 && IsClientInGame(client))
        RequestSteamData(client);

    return Plugin_Stop;
}

public Action Timer_RetryLoadEXP(Handle timer, any userid)
{
    int client = GetClientOfUserId(userid);
    if (client <= 0 || !IsClientInGame(client) || IsFakeClient(client))
        return Plugin_Stop;

    RequestSteamData(client);
    return Plugin_Stop;
}

public void OnMapStart()
{
    for (int i = 1; i <= MaxClients; i++)
    {
        g_iState[i] = 0;
        g_fExp[i] = 0.0;
        g_iRetryCount[i] = 0;
        g_bLoadedMap[i] = false;
        g_bUsingLocalExp[i] = false;
    }

    g_bMixVoteInProgress = false;
    g_iMixVoteYes = 0;
    g_iMixVoteNo = 0;
    CleanupMixArrays();
}

public void OnClientDisconnect(int client)
{
    g_iState[client] = 0;
    g_fExp[client] = 0.0;
    g_iRetryCount[client] = 0;
    g_bLoadedMap[client] = false;
    g_bUsingLocalExp[client] = false;
}

void RequestSteamData(int client)
{
    if (g_bLoadedMap[client] || g_iState[client] == 1)
        return;

    if (g_hSteamAPIClient == null)
    {
        UseLocalExp(client);
        return;
    }

    char steam64[32];
    if (!GetSteam64(client, steam64, sizeof(steam64)))
        return;

    g_iState[client] = 1;

    char url[512];
    Format(url, sizeof(url),
        "ISteamUserStats/GetUserStatsForGame/v0002/?appid=550&key=%s&steamid=%s&format=json",
        g_sApiKey, steam64);

    g_hSteamAPIClient.Get(url, OnSteamResponse, client);
}

void HandleApiFailure(int client, const char[] reason)
{
    if (!IsClientInGame(client))
        return;

    if (g_iRetryCount[client] < MAX_API_RETRY)
    {
        g_iRetryCount[client]++;
        g_iState[client] = 0;

        int userid = GetClientUserId(client);
        float retryDelay = float(g_iRetryCount[client]);

        PrintToServer("%s[EXP 重试]%s %N API失败(%s)，%.1f秒后重试(%d/%d)",
            COLOR_YELLOW, COLOR_DEFAULT, client, reason, retryDelay, g_iRetryCount[client], MAX_API_RETRY);

        CreateTimer(retryDelay, Timer_RetryLoadEXP, userid);
        return;
    }

    PrintToServer("%s[EXP 降级]%s %N API失败次数过多，使用本地数据 (%s)",
        COLOR_RED, COLOR_DEFAULT, client, reason);
    UseLocalExp(client);
}

void OnSteamResponse(HTTPResponse response, any client)
{
    if (!IsClientInGame(client))
        return;

    int status = view_as<int>(response.Status);
    if (status == 0)
    {
        HandleApiFailure(client, "无法连接");
        return;
    }

    if (status != 200 || response.Data == null)
    {
        char reason[64];
        Format(reason, sizeof(reason), "HTTP状态%d", status);
        HandleApiFailure(client, reason);
        return;
    }

    JSONObject root = view_as<JSONObject>(response.Data);
    JSONObject playerstats = view_as<JSONObject>(root.Get("playerstats"));
    if (playerstats == null)
    {
        delete root;
        HandleApiFailure(client, "缺少playerstats");
        return;
    }

    JSONArray stats = view_as<JSONArray>(playerstats.Get("stats"));
    if (stats == null)
    {
        delete playerstats;
        delete root;
        HandleApiFailure(client, "缺少stats");
        return;
    }

    int won = 0, lost = 0, playtime = 0, t1kill = 0;
    for (int i = 0; i < stats.Length; i++)
    {
        JSONObject item = view_as<JSONObject>(stats.Get(i));
        if (item == null)
            continue;

        char name[128];
        item.GetString("name", name, sizeof(name));
        int value = item.GetInt("value");

        if (StrEqual(name, "Stat.GamesWon.Versus"))
            won = value;
        else if (StrEqual(name, "Stat.GamesLost.Versus"))
            lost = value;
        else if (StrEqual(name, "Stat.TotalPlayTime.Total"))
            playtime = value;
        else if (StrContains(name, ".Kills.Total") != -1 || StrContains(name, ".Head.Total") != -1)
            t1kill += value;

        delete item;
    }

    delete stats;
    delete playerstats;
    delete root;

    if (won + lost == 0)
    {
        HandleApiFailure(client, "对战场次为0");
        return;
    }

    float rawExp = (float(won) / float(won + lost)) *
                   (0.55 * (float(playtime) / 3600.0) + 0.005 * float(t1kill));

    g_fExp[client] = float(RoundToFloor(rawExp));
    g_bUsingLocalExp[client] = false;
    g_iState[client] = 2;
    g_bLoadedMap[client] = true;
    g_iRetryCount[client] = 0;

    PrintToChatAll("%s[EXP]%s %s%N%s : %s%d%s经验评分 [API]",
        COLOR_GREEN, COLOR_DEFAULT, COLOR_YELLOW, client, COLOR_DEFAULT,
        COLOR_LGREEN, RoundToFloor(g_fExp[client]), COLOR_DEFAULT);
}

void UseLocalExp(int client)
{
    g_bUsingLocalExp[client] = true;

    float timeExp = float(g_iLocalPlayTime[client]) / 10.0;
    float killExp = float(g_iLocalKills[client]) * 2.0;
    float deathPenalty = float(g_iLocalDeaths[client]) * 0.5;

    float localExp = timeExp + killExp - deathPenalty;
    if (localExp < 100.0) localExp = 100.0;
    if (localExp > 2000.0) localExp = 2000.0;

    g_fExp[client] = localExp;
    g_iState[client] = 2;
    g_bLoadedMap[client] = true;

    PrintToChat(client, "%s[EXP]%s 你的经验值: %s%d%s经验评分 [本地分析]",
        COLOR_GREEN, COLOR_DEFAULT, COLOR_LGREEN, RoundToFloor(g_fExp[client]), COLOR_DEFAULT);
}

public Action Cmd_Exp(int client, int args)
{
    if (client <= 0 || !IsClientInGame(client))
        return Plugin_Handled;

    PrintToChat(client, "%s==========[玩家经验值列表]==========", COLOR_GREEN);

    bool hasPlayer = false;
    hasPlayer |= PrintExpTeamSection(client, TEAM_SURV, "【生还方】");
    hasPlayer |= PrintExpTeamSection(client, TEAM_INF, "【特感方】");
    hasPlayer |= PrintExpTeamSection(client, TEAM_SPEC, "【旁观】");

    if (!hasPlayer)
        PrintToChat(client, "%s当前没有玩家在线", COLOR_DEFAULT);

    PrintToChat(client, "%s================================", COLOR_GREEN);
    return Plugin_Handled;
}

bool PrintExpTeamSection(int receiver, int team, const char[] title)
{
    bool found = false;
    int count = 0;

    PrintToChat(receiver, "%s%s", COLOR_YELLOW, title);

    for (int i = 1; i <= MaxClients; i++)
    {
        if (!IsClientInGame(i) || IsFakeClient(i) || GetClientTeam(i) != team)
            continue;

        found = true;
        count++;

        char status[64];
        if (g_iState[i] == 2)
        {
            char mode[16];
            strcopy(mode, sizeof(mode), g_bUsingLocalExp[i] ? "本地" : "API");
            Format(status, sizeof(status), "%s%d%s经验评分 [%s]",
                COLOR_LGREEN, RoundToFloor(g_fExp[i]), COLOR_DEFAULT, mode);
        }
        else if (g_iState[i] == 1)
        {
            Format(status, sizeof(status), "%s加载中...", COLOR_YELLOW);
        }
        else
        {
            Format(status, sizeof(status), "%s未加载", COLOR_RED);
        }

        PrintToChat(receiver, "%s[EXP]%s %d. %s%N%s : %s",
            COLOR_GREEN, COLOR_DEFAULT, count, COLOR_YELLOW, i, COLOR_DEFAULT, status);
    }

    if (!found)
        PrintToChat(receiver, "%s[EXP]%s 无玩家", COLOR_GREEN, COLOR_DEFAULT);

    return found;
}

public Action Cmd_MixExp(int client, int args)
{
    if (g_bMixVoteInProgress)
    {
        PrintToChat(client, "%s[EXP]%s 经验平衡投票正在进行中...", COLOR_GREEN, COLOR_DEFAULT);
        return Plugin_Handled;
    }

    int realPlayers = 0;
    for (int i = 1; i <= MaxClients; i++)
    {
        if (IsClientInGame(i) && !IsFakeClient(i) && GetClientTeam(i) != TEAM_SPEC)
            realPlayers++;
    }

    if (realPlayers < 2)
    {
        PrintToChat(client, "%s[EXP]%s 玩家数量不足，无法进行平衡", COLOR_GREEN, COLOR_DEFAULT);
        return Plugin_Handled;
    }

    if (!CalculateBalance())
    {
        PrintToChat(client, "%s[EXP]%s 计算平衡方案失败", COLOR_GREEN, COLOR_DEFAULT);
        return Plugin_Handled;
    }

    int[] players = new int[MaxClients];
    int playerCount = 0;
    for (int i = 1; i <= MaxClients; i++)
    {
        if (IsClientInGame(i) && !IsFakeClient(i))
            players[playerCount++] = i;
    }

    if (playerCount == 0)
    {
        PrintToChat(client, "%s[EXP]%s 没有玩家在线，无法开始投票", COLOR_GREEN, COLOR_DEFAULT);
        return Plugin_Handled;
    }

    Menu voteMenu = new Menu(MixVoteHandler);
    voteMenu.SetTitle("根据经验值平衡队伍?");
    voteMenu.AddItem("yes", "同意");
    voteMenu.AddItem("no", "反对");
    voteMenu.ExitButton = false;
    voteMenu.DisplayVote(players, playerCount, 20);

    g_bMixVoteInProgress = true;
    g_iMixVoteYes = 0;
    g_iMixVoteNo = 0;

    PrintToChatAll("%s[EXP]%s %s%N%s 发起了经验平衡投票！", COLOR_GREEN, COLOR_DEFAULT, COLOR_YELLOW, client, COLOR_DEFAULT);
    PrintToChatAll("%s[EXP]%s 按 F1 同意 / F2 反对 (20秒)", COLOR_GREEN, COLOR_DEFAULT);

    return Plugin_Handled;
}

public int MixVoteHandler(Menu menu, MenuAction action, int param1, int param2)
{
    switch (action)
    {
        case MenuAction_Select:
        {
            char info[32];
            menu.GetItem(param2, info, sizeof(info));

            if (StrEqual(info, "yes"))
                g_iMixVoteYes++;
            else if (StrEqual(info, "no"))
                g_iMixVoteNo++;
        }
        case MenuAction_VoteEnd:
        {
            ProcessMixVoteResult();
        }
        case MenuAction_VoteCancel:
        {
            g_bMixVoteInProgress = false;
            CleanupMixArrays();
        }
        case MenuAction_End:
        {
            delete menu;
        }
    }
    return 0;
}

void ProcessMixVoteResult()
{
    int totalVotes = g_iMixVoteYes + g_iMixVoteNo;
    float yesPercent = (totalVotes > 0) ? float(g_iMixVoteYes) / float(totalVotes) : 0.0;

    if (yesPercent > 0.5 && g_iMixVoteYes > 0)
    {
        PrintToChatAll("%s[EXP]%s 投票通过！正在执行队伍平衡...", COLOR_GREEN, COLOR_DEFAULT);
        ExecuteMixBalance();
    }
    else
    {
        PrintToChatAll("%s[EXP]%s 投票未通过！", COLOR_GREEN, COLOR_DEFAULT);
        g_bMixVoteInProgress = false;
        CleanupMixArrays();
    }
}

bool CalculateBalance()
{
    ArrayList allPlayers = new ArrayList(2);

    for (int i = 1; i <= MaxClients; i++)
    {
        if (!IsClientInGame(i) || IsFakeClient(i))
            continue;

        int team = GetClientTeam(i);
        if (team != TEAM_SURV && team != TEAM_INF)
            continue;

        int exp = RoundToFloor(g_fExp[i]);
        if (g_iState[i] != 2)
            exp = 100;

        int data[2];
        data[0] = i;
        data[1] = exp;
        allPlayers.PushArray(data, 2);
    }

    if (allPlayers.Length < 2)
    {
        delete allPlayers;
        return false;
    }

    SortADTArrayCustom(allPlayers, SortByExpDesc);

    if (g_alMixSurvivors != null)
        delete g_alMixSurvivors;
    if (g_alMixInfected != null)
        delete g_alMixInfected;

    g_alMixSurvivors = new ArrayList(1);
    g_alMixInfected = new ArrayList(1);

    float surTotal = 0.0, infTotal = 0.0;
    for (int i = 0; i < allPlayers.Length; i++)
    {
        int data[2];
        allPlayers.GetArray(i, data, 2);
        int target = data[0];
        int exp = data[1];

        if (surTotal <= infTotal)
        {
            g_alMixSurvivors.Push(target);
            surTotal += exp;
        }
        else
        {
            g_alMixInfected.Push(target);
            infTotal += exp;
        }
    }

    delete allPlayers;
    return true;
}

public int SortByExpDesc(int index1, int index2, Handle array, Handle hndl)
{
    ArrayList arr = view_as<ArrayList>(array);
    int data1[2], data2[2];
    arr.GetArray(index1, data1, 2);
    arr.GetArray(index2, data2, 2);

    if (data1[1] > data2[1])
        return -1;
    if (data1[1] < data2[1])
        return 1;
    return 0;
}

void ExecuteMixBalance()
{
    ArrayList moveToSur = new ArrayList(1);
    ArrayList moveToInf = new ArrayList(1);

    for (int i = 0; i < g_alMixSurvivors.Length; i++)
    {
        int target = g_alMixSurvivors.Get(i);
        if (IsClientInGame(target) && GetClientTeam(target) != TEAM_SURV)
            moveToSur.Push(target);
    }

    for (int i = 0; i < g_alMixInfected.Length; i++)
    {
        int target = g_alMixInfected.Get(i);
        if (IsClientInGame(target) && GetClientTeam(target) != TEAM_INF)
            moveToInf.Push(target);
    }

    for (int i = 0; i < moveToInf.Length; i++)
    {
        int target = moveToInf.Get(i);
        if (IsClientInGame(target) && !IsFakeClient(target))
            ChangeClientTeam(target, TEAM_INF);
    }

    for (int i = 0; i < moveToSur.Length; i++)
    {
        int target = moveToSur.Get(i);
        if (IsClientInGame(target) && !IsFakeClient(target))
        {
            FakeClientCommand(target, "jointeam 2");
            CreateTimer(0.8, Timer_TakeOverSurBot, GetClientUserId(target));
        }
    }

    delete moveToSur;
    delete moveToInf;

    PrintToChatAll("%s[EXP]%s 队伍平衡完成！", COLOR_GREEN, COLOR_DEFAULT);
    g_bMixVoteInProgress = false;
    CleanupMixArrays();
}

public Action Timer_TakeOverSurBot(Handle timer, any userid)
{
    int client = GetClientOfUserId(userid);
    if (client <= 0 || !IsClientInGame(client) || IsFakeClient(client))
        return Plugin_Stop;

    if (GetClientTeam(client) != TEAM_SURV)
        return Plugin_Stop;

    int bot = FindAliveSurBot();
    if (bot > 0)
    {
        SetEntProp(client, Prop_Send, "m_iObserverMode", 5);
        SetEntProp(client, Prop_Send, "m_hObserverTarget", bot);
        FakeClientCommand(client, "jointeam 2");
    }

    return Plugin_Stop;
}

int FindAliveSurBot()
{
    for (int i = 1; i <= MaxClients; i++)
    {
        if (IsClientInGame(i) && !IsClientInKickQueue(i) && IsFakeClient(i) &&
            GetClientTeam(i) == TEAM_SURV && IsPlayerAlive(i))
        {
            if (GetIdlePlayerOfBot(i) == 0)
                return i;
        }
    }
    return 0;
}

int GetIdlePlayerOfBot(int client)
{
    if (!HasEntProp(client, Prop_Send, "m_humanSpectatorUserID"))
        return 0;

    return GetClientOfUserId(GetEntProp(client, Prop_Send, "m_humanSpectatorUserID"));
}

void CleanupMixArrays()
{
    if (g_alMixSurvivors != null)
    {
        delete g_alMixSurvivors;
        g_alMixSurvivors = null;
    }

    if (g_alMixInfected != null)
    {
        delete g_alMixInfected;
        g_alMixInfected = null;
    }
}
