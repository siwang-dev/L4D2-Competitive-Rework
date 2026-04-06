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

HTTPClient g_hClient;

float g_fExp[MAXPLAYERS + 1];
int g_iState[MAXPLAYERS + 1];
int g_iRetryCount[MAXPLAYERS + 1];
Handle g_hRetryTimer[MAXPLAYERS + 1];

// =============================
// 插件启动
// =============================
public void OnPluginStart()
{
    g_hClient = new HTTPClient(EXP_API_HOST);

    if (g_hClient == null)
    {
        SetFailState("[EXP] HTTPClient 创建失败");
    }

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
