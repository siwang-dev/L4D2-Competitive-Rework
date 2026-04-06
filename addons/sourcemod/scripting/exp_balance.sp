#include <sourcemod>
#include <ripext>

#define COLOR_GREEN "\x04"
#define COLOR_DEFAULT "\x01"
#define COLOR_YELLOW "\x03"
#define COLOR_LGREEN "\x05"

#define EXP_API_HOST "http://你的B服务器IP"
#define EXP_API_PATH "/getexp.php?steamid=%s"
#define EXP_MAX_RETRY 3
#define EXP_RETRY_DELAY 3.0
#define TEAM_SPECTATOR 1
#define TEAM_SURVIVOR 2
#define TEAM_INFECTED 3

HTTPClient g_hClient;
ConVar g_cvSurvivorLimit;
ConVar g_cvInfectedLimit;

float g_fExp[MAXPLAYERS + 1];
int g_iState[MAXPLAYERS + 1];
int g_iRetryCount[MAXPLAYERS + 1];
Handle g_hRetryTimer[MAXPLAYERS + 1];
int g_iTargetTeam[MAXPLAYERS + 1];

// =============================
// 插件启动
// =============================
public void OnPluginStart()
{
    g_hClient = new HTTPClient(EXP_API_HOST);
    g_cvSurvivorLimit = FindConVar("survivor_limit");
    g_cvInfectedLimit = FindConVar("z_max_player_zombies");

    if (g_hClient == null)
    {
        SetFailState("[EXP] HTTPClient 创建失败");
    }

    RegConsoleCmd("sm_exp", Command_Exp, "显示EXP分布，或使用 sm_exp balance 自动分队。");

    for (int i = 1; i <= MaxClients; i++)
    {
        ResetClientState(i);
    }

    PrintToServer("[EXP] 插件加载成功");
}

// =============================
// 玩家进入
// =============================
public void OnClientPostAdminCheck(int client)
{
    if (!IsValidClient(client))
        return;

    ResetClientState(client);
    RequestExp(client);
}

public void OnClientDisconnect(int client)
{
    ResetClientState(client);
}

// =============================
// 请求数据
// =============================
void RequestExp(int client)
{
    if (!IsValidClient(client) || g_hClient == null)
        return;

    if (g_iState[client] == 1)
        return;

    char steam64[32];
    if (!GetSteam64(client, steam64, sizeof(steam64)))
    {
        RetryExp(client, "Steam64 未就绪");
        return;
    }

    g_iState[client] = 1;

    char url[256];
    Format(url, sizeof(url), EXP_API_PATH, steam64);

    PrintToServer("[EXP] 请求 %N -> %s", client, url);

    g_hClient.Get(url, OnResponse, GetClientUserId(client));
}

void RetryExp(int client, const char[] reason)
{
    if (!IsValidClient(client))
        return;

    if (g_iRetryCount[client] >= EXP_MAX_RETRY)
    {
        PrintToServer("[EXP] %N 请求失败：%s（重试已达上限）", client, reason);
        g_iState[client] = 0;
        return;
    }

    g_iRetryCount[client]++;
    g_iState[client] = 0;

    if (g_hRetryTimer[client] != null)
    {
        delete g_hRetryTimer[client];
        g_hRetryTimer[client] = null;
    }

    PrintToServer("[EXP] %N 请求失败：%s，%.1f 秒后进行第 %d/%d 次重试", client, reason, EXP_RETRY_DELAY, g_iRetryCount[client], EXP_MAX_RETRY);

    g_hRetryTimer[client] = CreateTimer(EXP_RETRY_DELAY, Timer_RequestExp, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
}

public Action Timer_RequestExp(Handle timer, any userId)
{
    int client = GetClientOfUserId(userId);

    if (client <= 0 || !IsClientInGame(client))
        return Plugin_Stop;

    g_hRetryTimer[client] = null;
    RequestExp(client);
    return Plugin_Stop;
}

// =============================
// HTTP回调
// =============================
void OnResponse(HTTPResponse response, any userId)
{
    int client = GetClientOfUserId(userId);

    if (client <= 0 || !IsClientInGame(client))
        return;

    if (response.Status != HTTPStatus_OK)
    {
        char err[64];
        Format(err, sizeof(err), "HTTP错误 code=%d", response.Status);
        RetryExp(client, err);
        return;
    }

    if (response.Data == null)
    {
        RetryExp(client, "JSON 为空");
        return;
    }

    JSONObject data = view_as<JSONObject>(response.Data);

    int kills = 0;
    int headshots = 0;
    int hours = 0;

    // 安全读取
    if (data.HasKey("kills"))
        kills = data.GetInt("kills");

    if (data.HasKey("headshots"))
        headshots = data.GetInt("headshots");

    if (data.HasKey("hours"))
        hours = data.GetInt("hours");

    // 调试日志
    char debug[512];
    data.ToString(debug, sizeof(debug));
    PrintToServer("[EXP DEBUG] %N <- %s", client, debug);

    delete data;

    float exp = CalculateExp(kills, headshots, hours);

    g_fExp[client] = exp;
    g_iState[client] = 2;
    g_iRetryCount[client] = 0;

    PrintToChatAll("%s[EXP]%s %s%N%s : %s%.0f%s 经验评分",
        COLOR_GREEN, COLOR_DEFAULT,
        COLOR_YELLOW, client, COLOR_DEFAULT,
        COLOR_LGREEN, exp, COLOR_DEFAULT);
}

// =============================
// EXP算法（无防炸鱼）
// =============================
float CalculateExp(int kills, int headshots, int hours)
{
    float exp = 0.0;

    exp += float(kills) * 0.4;
    exp += float(headshots) * 0.8;
    exp += float(hours) * 12.0;

    return exp;
}

// =============================
// Steam64
// =============================
bool GetSteam64(int client, char[] buffer, int size)
{
    if (!IsClientInGame(client))
        return false;

    char auth[64];
    if (!GetClientAuthId(client, AuthId_SteamID64, auth, sizeof(auth), true))
        return false;

    if (auth[0] == '\0' || StrEqual(auth, "STEAM_ID_STOP_IGNORING_RETVALS", false))
        return false;

    strcopy(buffer, size, auth);
    return true;
}

// =============================
void ResetClientState(int client)
{
    g_fExp[client] = 0.0;
    g_iState[client] = 0;
    g_iRetryCount[client] = 0;

    if (g_hRetryTimer[client] != null)
    {
        delete g_hRetryTimer[client];
        g_hRetryTimer[client] = null;
    }
}

bool IsValidClient(int client)
{
    return (client > 0 && client <= MaxClients && IsClientInGame(client));
}

bool IsValidHuman(int client)
{
    return IsValidClient(client) && !IsFakeClient(client);
}

public Action Command_Exp(int client, int args)
{
    if (args > 0)
    {
        char arg1[32];
        GetCmdArg(1, arg1, sizeof(arg1));
        if (StrEqual(arg1, "balance", false) || StrEqual(arg1, "team", false))
        {
            return Command_BalanceExp(client);
        }
    }

    return Command_ShowExp(client);
}

Action Command_ShowExp(int client)
{
    int survCount = 0;
    int infCount = 0;
    int specCount = 0;
    float survTotal = 0.0;
    float infTotal = 0.0;
    float specTotal = 0.0;

    for (int i = 1; i <= MaxClients; i++)
    {
        if (!IsValidHuman(i))
            continue;

        int team = GetClientTeam(i);
        if (team == TEAM_SURVIVOR)
        {
            survCount++;
            survTotal += g_fExp[i];
        }
        else if (team == TEAM_INFECTED)
        {
            infCount++;
            infTotal += g_fExp[i];
        }
        else
        {
            specCount++;
            specTotal += g_fExp[i];
        }
    }

    float survAvg = survCount > 0 ? survTotal / float(survCount) : 0.0;
    float infAvg = infCount > 0 ? infTotal / float(infCount) : 0.0;
    float specAvg = specCount > 0 ? specTotal / float(specCount) : 0.0;

    if (client > 0 && IsClientInGame(client))
    {
        ReplyToCommand(client, "[EXP] 生还方: %d人(均分%.0f) | 特感方: %d人(均分%.0f) | 旁观: %d人(均分%.0f)", survCount, survAvg, infCount, infAvg, specCount, specAvg);
        ReplyToCommand(client, "[EXP] 输入 sm_exp balance 可按EXP自动分队。");
    }
    else
    {
        PrintToServer("[EXP] 生还方: %d人(均分%.0f) | 特感方: %d人(均分%.0f) | 旁观: %d人(均分%.0f)", survCount, survAvg, infCount, infAvg, specCount, specAvg);
    }

    return Plugin_Handled;
}

Action Command_BalanceExp(int client)
{
    int players[MAXPLAYERS];
    int count = CollectBalancePlayers(players, sizeof(players));
    if (count < 2)
    {
        ReplyToCommand(client, "[EXP] 人数不足，无法分队。");
        return Plugin_Handled;
    }

    SortPlayersByExp(players, count);

    int survivorLimit = g_cvSurvivorLimit != null ? g_cvSurvivorLimit.IntValue : 4;
    int infectedLimit = g_cvInfectedLimit != null ? g_cvInfectedLimit.IntValue : 4;
    int targetSurvivor = (count + 1) / 2;
    int targetInfected = count / 2;

    if (targetSurvivor > survivorLimit)
    {
        targetSurvivor = survivorLimit;
        targetInfected = count - targetSurvivor;
    }

    if (targetInfected > infectedLimit)
    {
        targetInfected = infectedLimit;
        targetSurvivor = count - targetInfected;
        if (targetSurvivor > survivorLimit)
            targetSurvivor = survivorLimit;
    }

    int assigned = targetSurvivor + targetInfected;
    int targetSpectator = count - assigned;

    int survivorCount = 0;
    int infectedCount = 0;
    float survivorTotal = 0.0;
    float infectedTotal = 0.0;

    for (int i = 0; i < count; i++)
    {
        int targetClient = players[i];
        float exp = g_fExp[targetClient];
        bool putSurvivor = false;

        if (survivorCount >= targetSurvivor)
        {
            putSurvivor = false;
        }
        else if (infectedCount >= targetInfected)
        {
            putSurvivor = true;
        }
        else
        {
            putSurvivor = survivorTotal <= infectedTotal;
        }

        if (putSurvivor)
        {
            g_iTargetTeam[targetClient] = TEAM_SURVIVOR;
            survivorCount++;
            survivorTotal += exp;
        }
        else if (infectedCount < targetInfected)
        {
            g_iTargetTeam[targetClient] = TEAM_INFECTED;
            infectedCount++;
            infectedTotal += exp;
        }
        else
        {
            g_iTargetTeam[targetClient] = TEAM_SPECTATOR;
        }
    }

    for (int i = 0; i < count; i++)
    {
        int targetClient = players[i];
        if (GetClientTeam(targetClient) != TEAM_SPECTATOR)
        {
            ChangeClientTeam(targetClient, TEAM_SPECTATOR);
        }
    }

    CreateTimer(0.35, Timer_ApplyExpBalance, _, TIMER_FLAG_NO_MAPCHANGE);

    float survivorAvg = survivorCount > 0 ? survivorTotal / float(survivorCount) : 0.0;
    float infectedAvg = infectedCount > 0 ? infectedTotal / float(infectedCount) : 0.0;
    PrintToChatAll("[EXP] 分队完成: 生还 %d(均分%.0f) / 特感 %d(均分%.0f) / 旁观 %d。", survivorCount, survivorAvg, infectedCount, infectedAvg, targetSpectator);

    if (client > 0 && IsClientInGame(client))
    {
        ReplyToCommand(client, "[EXP] 已执行自动分队。");
    }

    return Plugin_Handled;
}

public Action Timer_ApplyExpBalance(Handle timer)
{
    for (int client = 1; client <= MaxClients; client++)
    {
        if (!IsValidHuman(client) || g_iTargetTeam[client] == 0)
            continue;

        MoveClientToTeamSafe(client, g_iTargetTeam[client]);
        g_iTargetTeam[client] = 0;
    }

    return Plugin_Stop;
}

int CollectBalancePlayers(int[] players, int maxSize)
{
    int count = 0;
    for (int client = 1; client <= MaxClients && count < maxSize; client++)
    {
        if (!IsValidHuman(client))
            continue;

        int team = GetClientTeam(client);
        if (team == TEAM_SURVIVOR || team == TEAM_INFECTED || team == TEAM_SPECTATOR)
        {
            players[count++] = client;
        }
    }

    return count;
}

void SortPlayersByExp(int[] players, int count)
{
    for (int i = 0; i < count - 1; i++)
    {
        int best = i;
        for (int j = i + 1; j < count; j++)
        {
            if (g_fExp[players[j]] > g_fExp[players[best]])
            {
                best = j;
            }
        }

        if (best != i)
        {
            int tmp = players[i];
            players[i] = players[best];
            players[best] = tmp;
        }
    }
}

void MoveClientToTeamSafe(int client, int team)
{
    if (!IsValidHuman(client))
        return;

    if (team == TEAM_SURVIVOR)
    {
        MoveClientToSurvivorSafe(client);
        return;
    }

    if (GetClientTeam(client) != team)
    {
        ChangeClientTeam(client, team);
    }
}

void MoveClientToSurvivorSafe(int client)
{
    if (GetClientTeam(client) == TEAM_SURVIVOR)
        return;

    if (GetClientTeam(client) != TEAM_SPECTATOR)
    {
        ChangeClientTeam(client, TEAM_SPECTATOR);
    }

    int bot = FindAvailableSurvivorBot();
    if (bot > 0)
    {
        int flags = GetCommandFlags("sb_takecontrol");
        SetCommandFlags("sb_takecontrol", flags & ~FCVAR_CHEAT);
        FakeClientCommand(client, "sb_takecontrol");
        SetCommandFlags("sb_takecontrol", flags);
    }
    else
    {
        FakeClientCommand(client, "jointeam 2");
    }

    if (GetClientTeam(client) != TEAM_SURVIVOR)
    {
        ChangeClientTeam(client, TEAM_SURVIVOR);
    }
}

int FindAvailableSurvivorBot()
{
    for (int client = 1; client <= MaxClients; client++)
    {
        if (IsValidClient(client) && IsFakeClient(client) && GetClientTeam(client) == TEAM_SURVIVOR)
        {
            return client;
        }
    }

    return 0;
}
