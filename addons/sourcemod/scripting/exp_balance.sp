#include <sourcemod>
#include <ripext>

#define COLOR_GREEN "\x04"
#define COLOR_DEFAULT "\x01"
#define COLOR_YELLOW "\x03"
#define COLOR_LGREEN "\x05"

HTTPClient g_hClient;

float g_fExp[MAXPLAYERS+1];
int g_iState[MAXPLAYERS+1];

// =============================
// 插件启动
// =============================
public void OnPluginStart()
{
    g_hClient = new HTTPClient("http://你的B服务器IP");

    if (g_hClient == null)
    {
        SetFailState("[EXP] HTTPClient 创建失败");
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

    g_iState[client] = 0;

    RequestExp(client);
}

// =============================
// 请求数据
// =============================
void RequestExp(int client)
{
    if (g_iState[client] == 1)
        return;

    char steam64[32];
    if (!GetSteam64(client, steam64, sizeof(steam64)))
        return;

    g_iState[client] = 1;

    char url[256];
    Format(url, sizeof(url), "/getexp.php?steamid=%s", steam64);

    PrintToServer("[EXP] 请求 %N -> %s", client, url);

    g_hClient.Get(url, OnResponse, client);
}

// =============================
// HTTP回调
// =============================
void OnResponse(HTTPResponse response, any client)
{
    if (!IsValidClient(client))
        return;

    if (response.Status != HTTPStatus_OK)
    {
        PrintToServer("[EXP] HTTP失败 code=%d", response.Status);
        g_iState[client] = 0;
        return;
    }

    if (response.Data == null)
    {
        PrintToServer("[EXP] JSON为空");
        g_iState[client] = 0;
        return;
    }

    JSONObject data = view_as<JSONObject>(response.Data);

    int kills = 0;
    int headshots = 0;
    int hours = 0;

    // ✅ 安全读取（必须这样写）
    if (data.HasKey("kills"))
        kills = data.GetInt("kills");

    if (data.HasKey("headshots"))
        headshots = data.GetInt("headshots");

    if (data.HasKey("hours"))
        hours = data.GetInt("hours");

    // 调试（可删）
    char debug[512];
    data.ToString(debug, sizeof(debug));
    PrintToServer("[EXP DEBUG] %s", debug);

    delete data;

    float exp = CalculateExp(kills, headshots, hours);

    g_fExp[client] = exp;
    g_iState[client] = 2;

    PrintToChatAll("%s[EXP]%s %s%N%s : %s%.0f%s经验评分",
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
    GetClientAuthId(client, AuthId_SteamID64, auth, sizeof(auth), true);

    if (auth[0] == '\0')
        return false;

    strcopy(buffer, size, auth);
    return true;
}

// =============================
bool IsValidClient(int client)
{
    return (client > 0 && client <= MaxClients && IsClientInGame(client));
}