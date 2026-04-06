#pragma semicolon 1
#include <sourcemod>
#include <sdktools>
#include <ripext>

// =================
// 队伍定义
// =================
#define TEAM_SPEC 1
#define TEAM_SURV 2
#define TEAM_INF  3

// =================
// SourceMod 颜色代码
// =================
#define COLOR_DEFAULT "\x01"    // 白色/默认
#define COLOR_RED     "\x02"    // 红色
#define COLOR_LGREEN  "\x03"    // 浅绿色（团队色）
#define COLOR_GREEN   "\x04"    // 绿色
#define COLOR_YELLOW  "\x05"    // 黄色/金色

// =================
// 变量
// =================
char g_sApiKey[128] = "8EC33C57EC1D4BBC1607035258142287";
float g_fExp[MAXPLAYERS + 1];
int   g_iState[MAXPLAYERS + 1];  // 0=未加载 1=请求中 2=完成
int   g_iRetryCount[MAXPLAYERS + 1];
bool  g_bLoadedMap[MAXPLAYERS + 1];

// 本地数据分析变量
int   g_iLocalPlayTime[MAXPLAYERS + 1];      // 本地游戏时间（分钟）
int   g_iLocalKills[MAXPLAYERS + 1];         // 本地击杀数
int   g_iLocalDeaths[MAXPLAYERS + 1];        // 本地死亡数
bool  g_bUsingLocalExp[MAXPLAYERS + 1];       // 是否使用本地经验

// HTTPClient（参考时长插件的方式）
HTTPClient g_hSteamAPIClient;

// MixEXP 投票相关
bool  g_bMixVoteInProgress = false;
int   g_iMixVoteYes = 0;
int   g_iMixVoteNo = 0;
float g_fMixStartTime = 0.0;
ArrayList g_alMixSurvivors;
ArrayList g_alMixInfected;

// =================
// 插件启动
// =================
public void OnPluginStart()
{
    RegConsoleCmd("sm_exp", Cmd_Exp);
    RegConsoleCmd("sm_mixexp", Cmd_MixExp);
    
    // 创建 HTTPClient（参考时长插件的方式）
    g_hSteamAPIClient = new HTTPClient("https://api.steampowered.com");
    if (g_hSteamAPIClient == null)
    {
        PrintToServer("[EXP] 错误：无法创建 HTTPClient");
    }
    else
    {
        PrintToServer("[EXP] HTTPClient 创建成功");
    }
    
    // 监听玩家事件用于本地统计
    HookEvent("player_death", Event_PlayerDeath);
    HookEvent("player_incapacitated", Event_PlayerIncap);
    HookEvent("round_start", Event_RoundStart);
    
    PrintToServer("[EXP] 插件已加载 - API失败时将使用本地游戏数据分析");
}

public void OnPluginEnd()
{
    if (g_hSteamAPIClient != null)
        delete g_hSteamAPIClient;
}

// =================
// 事件监听（用于本地数据分析）
// =================
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
        g_iLocalDeaths[victim]++; // 倒地也算一次"死亡"记录
}

void Event_RoundStart(Event event, const char[] name, bool dontBroadcast)
{
    // 每轮更新玩家的本地游戏时间（分钟）
    for (int i = 1; i <= MaxClients; i++)
    {
        if (IsClientInGame(i) && !IsFakeClient(i))
        {
            g_iLocalPlayTime[i] += 5; // 假设每轮平均5分钟
        }
    }
}

// =================
// 获取 Steam64ID
// =================
bool GetSteam64(int client, char[] buffer, int size)
{
    return GetClientAuthId(client, AuthId_SteamID64, buffer, size);
}

// =================
// 自动在玩家加入时请求
// =================
public void OnClientPostAdminCheck(int client)
{
    if (!IsClientInGame(client) || IsFakeClient(client))
        return;

    // 重置本地数据
    g_iLocalPlayTime[client] = 0;
    g_iLocalKills[client] = 0;
    g_iLocalDeaths[client] = 0;
    g_bUsingLocalExp[client] = false;
    
    g_bLoadedMap[client] = false;
    g_iRetryCount[client] = 0;

    CreateTimer(2.0, Timer_LoadEXP, client);
}

public Action Timer_LoadEXP(Handle timer, any client)
{
    if (IsClientInGame(client))
        RequestSteamData(client);

    return Plugin_Stop;
}

// =========================
// 当新图开始时重置状态
// =========================
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
    
    if (g_alMixSurvivors != null)
        delete g_alMixSurvivors;
    if (g_alMixInfected != null)
        delete g_alMixInfected;
}

// =========================
// 玩家断开时清理
// =========================
public void OnClientDisconnect(int client)
{
    g_iState[client] = 0;
    g_fExp[client] = 0.0;
    g_iRetryCount[client] = 0;
    g_bLoadedMap[client] = false;
    g_bUsingLocalExp[client] = false;
}

// =========================
// 请求 Steam API（使用 HTTPClient 方式）
// =========================
void RequestSteamData(int client)
{
    if (g_bLoadedMap[client] || g_iState[client] == 1)
        return;
    
    if (g_hSteamAPIClient == null)
    {
        PrintToServer("[EXP] HTTPClient 未创建，使用本地数据分析");
        UseLocalExp(client);
        return;
    }

    char steam64[32];
    if (!GetSteam64(client, steam64, sizeof(steam64)))
    {
        PrintToServer("%s[EXP]%s 无法获取Steam64ID: %N", COLOR_GREEN, COLOR_DEFAULT, client);
        return;
    }

    g_iState[client] = 1;

    char url[512];
    // 使用相对路径（HTTPClient 已经设置了基础 URL）
    Format(url, sizeof(url),
        "ISteamUserStats/GetUserStatsForGame/v0002/?appid=550&key=%s&steamid=%s&format=json",
        g_sApiKey, steam64);

    PrintToServer("%s[EXP 请求]%s %N URL:%s", COLOR_LGREEN, COLOR_DEFAULT, client, url);

    // 使用 HTTPClient.Get（参考时长插件的方式）
    g_hSteamAPIClient.Get(url, OnSteamResponse, client);
}

// =========================
// Steam API 响应回调
// =========================
void OnSteamResponse(HTTPResponse response, any client)
{
    if (!IsClientInGame(client))
        return;

    int status = view_as<int>(response.Status);
    PrintToServer("%s[EXP 状态]%s %N Code:%d", COLOR_GREEN, COLOR_DEFAULT, client, status);

    // Code:0 表示完全无法连接（网络问题）
    if (status == 0)
    {
        PrintToServer("%s[EXP 错误]%s %N 无法连接到 Steam API，切换到本地数据分析", COLOR_RED, COLOR_DEFAULT, client);
        UseLocalExp(client);
        return;
    }

    // 其他错误
    if (status != 200 || response.Data == null)
    {
        PrintToServer("%s[EXP 错误]%s %N HTTP 错误: %d，切换到本地数据分析", COLOR_RED, COLOR_DEFAULT, client, status);
        UseLocalExp(client);
        return;
    }

    // 解析 JSON
    JSONObject root = view_as<JSONObject>(response.Data);
    JSONObject playerstats = view_as<JSONObject>(root.Get("playerstats"));
    
    if (playerstats == null)
    {
        PrintToServer("%s[EXP JSON错误]%s %N 无法获取 playerstats，使用本地数据", COLOR_GREEN, COLOR_DEFAULT, client);
        delete root;
        UseLocalExp(client);
        return;
    }

    JSONArray stats = view_as<JSONArray>(playerstats.Get("stats"));
    
    if (stats == null)
    {
        PrintToServer("%s[EXP JSON错误]%s %N 无法获取 stats 数组，使用本地数据", COLOR_GREEN, COLOR_DEFAULT, client);
        delete playerstats;
        delete root;
        UseLocalExp(client);
        return;
    }

    int won=0, lost=0, playtime=0, t1kill=0;
    for (int i = 0; i < stats.Length; i++)
    {
        JSONObject item = view_as<JSONObject>(stats.Get(i));
        char name[128];
        item.GetString("name", name, sizeof(name));
        int value = item.GetInt("value");

        if (StrEqual(name, "Stat.GamesWon.Versus"))
            won = value;
        else if (StrEqual(name, "Stat.GamesLost.Versus"))
            lost = value;
        else if (StrEqual(name, "Stat.TotalPlayTime.Total"))
            playtime = value;
        else if (StrContains(name, ".Kills.Total") != -1 ||
                 StrContains(name, ".Head.Total") != -1)
            t1kill += value;

        delete item;
    }

    delete stats;
    delete playerstats;
    delete root;

    // 计算经验值（原始公式）
    if (won + lost == 0)
    {
        PrintToServer("%s[EXP 警告]%s %N 无对战数据，使用本地数据分析", COLOR_YELLOW, COLOR_DEFAULT, client);
        UseLocalExp(client);
        return;
    }
    
    float rawExp = ( float(won) / float(won + lost) ) *
                   ( 0.55 * ( float(playtime) / 3600.0 ) + 0.005 * float(t1kill) );
    g_fExp[client] = float(RoundToFloor(rawExp));
    g_bUsingLocalExp[client] = false;

    g_iState[client] = 2;
    g_bLoadedMap[client] = true;

    PrintToServer("%s[EXP 成功]%s %N API经验值: %d", COLOR_LGREEN, COLOR_DEFAULT, client, RoundToFloor(g_fExp[client]));
    PrintToChatAll("%s[EXP]%s %s%N%s : %s%d%s经验评分 [API]", 
        COLOR_GREEN, COLOR_DEFAULT, COLOR_YELLOW, client, COLOR_DEFAULT, COLOR_LGREEN, RoundToFloor(g_fExp[client]), COLOR_DEFAULT);
}

// =========================
// 使用本地数据分析（当API不可用时）
// =========================
void UseLocalExp(int client)
{
    g_bUsingLocalExp[client] = true;
    
    // 基于本地游戏数据的简单经验公式
    // 经验 = (游戏时间分钟数 / 10) + (击杀数 * 2) - (死亡数 * 0.5)
    // 保底100经验，上限2000
    
    float timeExp = float(g_iLocalPlayTime[client]) / 10.0;
    float killExp = float(g_iLocalKills[client]) * 2.0;
    float deathPenalty = float(g_iLocalDeaths[client]) * 0.5;
    
    float localExp = timeExp + killExp - deathPenalty;
    
    if (localExp < 100.0) localExp = 100.0;
    if (localExp > 2000.0) localExp = 2000.0;
    
    g_fExp[client] = localExp;
    g_iState[client] = 2;
    g_bLoadedMap[client] = true;
    
    PrintToServer("%s[EXP 本地模式]%s %N 游戏时间:%d分钟 击杀:%d 死亡:%d 经验:%d", 
        COLOR_YELLOW, COLOR_DEFAULT, client, 
        g_iLocalPlayTime[client], g_iLocalKills[client], g_iLocalDeaths[client],
        RoundToFloor(g_fExp[client]));
    
    PrintToChat(client, "%s[EXP]%s 你的经验值: %s%d%s经验评分 [本地分析]", 
        COLOR_GREEN, COLOR_DEFAULT, COLOR_LGREEN, RoundToFloor(g_fExp[client]), COLOR_DEFAULT);
}

// =========================
// sm_exp 命令 - 显示所有在场玩家经验值
// =========================
public Action Cmd_Exp(int client, int args)
{
    PrintToChat(client, "%s==========[玩家经验值列表]==========", COLOR_GREEN);
    
    bool hasPlayer = false;
    int count = 0;
    
    for (int i = 1; i <= MaxClients; i++)
    {
        if (!IsClientInGame(i) || IsFakeClient(i))
            continue;
        
        hasPlayer = true;
        count++;
        
        char status[48];
        if (g_iState[i] == 2)
        {
            char mode[16] = "API";
            if (g_bUsingLocalExp[i])
                mode = "本地";
            
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
        
        int team = GetClientTeam(i);
        char teamIcon[4];
        switch (team)
        {
            case TEAM_SURV: teamIcon = "★";
            case TEAM_INF:  teamIcon = "▲";
            case TEAM_SPEC: teamIcon = "◆";
            default:        teamIcon = "○";
        }
        
        PrintToChat(client, "%s[EXP]%s %d. %s%s %s%N%s : %s", 
            COLOR_GREEN, COLOR_DEFAULT, count, COLOR_DEFAULT, teamIcon, COLOR_YELLOW, i, COLOR_DEFAULT, status);
    }
    
    if (!hasPlayer)
    {
        PrintToChat(client, "%s当前没有玩家在线", COLOR_DEFAULT);
    }
    
    PrintToChat(client, "%s================================", COLOR_GREEN);
    
    return Plugin_Handled;
}

// =========================
// sm_mixexp 命令 - 发起经验平衡投票
// =========================
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
        {
            players[playerCount++] = i;
        }
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
    g_fMixStartTime = GetGameTime();
    
    float surTotal = 0.0, infTotal = 0.0;
    for (int i = 0; i < g_alMixSurvivors.Length; i++)
    {
        int target = g_alMixSurvivors.Get(i);
        surTotal += g_fExp[target];
    }
    for (int i = 0; i < g_alMixInfected.Length; i++)
    {
        int target = g_alMixInfected.Get(i);
        infTotal += g_fExp[target];
    }
    
    PrintToChatAll("%s[EXP]%s %s%N%s 发起了经验平衡投票！", COLOR_GREEN, COLOR_DEFAULT, COLOR_YELLOW, client, COLOR_DEFAULT);
    PrintToChatAll("%s[EXP]%s 预览: 生还者总经验 %s%.0f%s vs 感染者总经验 %s%.0f%s", 
        COLOR_GREEN, COLOR_DEFAULT, COLOR_LGREEN, surTotal, COLOR_DEFAULT, COLOR_LGREEN, infTotal, COLOR_DEFAULT);
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
            {
                g_iMixVoteYes++;
                PrintToChat(param1, "%s[EXP]%s 你已投票: 同意", COLOR_GREEN, COLOR_DEFAULT);
            }
            else if (StrEqual(info, "no"))
            {
                g_iMixVoteNo++;
                PrintToChat(param1, "%s[EXP]%s 你已投票: 反对", COLOR_GREEN, COLOR_DEFAULT);
            }
        }
        
        case MenuAction_VoteEnd:
        {
            ProcessMixVoteResult();
        }
        
        case MenuAction_VoteCancel:
        {
            if (param1 == VoteCancel_NoVotes)
            {
                PrintToChatAll("%s[EXP]%s 投票失败：无人参与投票", COLOR_GREEN, COLOR_DEFAULT);
            }
            else
            {
                PrintToChatAll("%s[EXP]%s 投票被取消", COLOR_GREEN, COLOR_DEFAULT);
            }
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
    
    PrintToChatAll("%s[EXP]%s 投票结果: %s%d%s 同意 / %s%d%s 反对 (共%s%d%s票, 需>50%%)", 
        COLOR_GREEN, COLOR_DEFAULT, COLOR_LGREEN, g_iMixVoteYes, COLOR_DEFAULT, 
        COLOR_RED, g_iMixVoteNo, COLOR_DEFAULT, COLOR_YELLOW, totalVotes, COLOR_DEFAULT);
    
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
        
        if (i % 2 == 0)
        {
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
        else
        {
            if (surTotal > infTotal)
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
    else if (data1[1] < data2[1])
        return 1;
    return 0;
}

void ExecuteMixBalance()
{
    PrintToChatAll("%s[EXP]%s 第一步：移动玩家到旁观席...", COLOR_GREEN, COLOR_DEFAULT);
    
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
    
    for (int i = 0; i < moveToSur.Length; i++)
    {
        int target = moveToSur.Get(i);
        if (IsClientInGame(target) && !IsFakeClient(target))
            ChangeClientTeam(target, TEAM_SPEC);
    }
    
    for (int i = 0; i < moveToInf.Length; i++)
    {
        int target = moveToInf.Get(i);
        if (IsClientInGame(target) && !IsFakeClient(target))
            ChangeClientTeam(target, TEAM_SPEC);
    }
    
    DataPack pack = new DataPack();
    pack.WriteCell(moveToSur.Length);
    for (int i = 0; i < moveToSur.Length; i++)
        pack.WriteCell(moveToSur.Get(i));
    pack.WriteCell(moveToInf.Length);
    for (int i = 0; i < moveToInf.Length; i++)
        pack.WriteCell(moveToInf.Get(i));
    
    delete moveToSur;
    delete moveToInf;
    
    CreateTimer(1.5, Timer_MoveToFinalTeam, pack);
}

public Action Timer_MoveToFinalTeam(Handle timer, DataPack pack)
{
    pack.Reset();
    int surCount = pack.ReadCell();
    int[] surClients = new int[surCount];
    for (int i = 0; i < surCount; i++)
        surClients[i] = pack.ReadCell();
    
    int infCount = pack.ReadCell();
    int[] infClients = new int[infCount];
    for (int i = 0; i < infCount; i++)
        infClients[i] = pack.ReadCell();
    delete pack;
    
    PrintToChatAll("%s[EXP]%s 第二步：分配到最终队伍...", COLOR_GREEN, COLOR_DEFAULT);
    
    for (int i = 0; i < surCount; i++)
    {
        int target = surClients[i];
        if (IsClientInGame(target) && !IsFakeClient(target))
        {
            ChangeClientTeam(target, TEAM_SURV);
            CreateTimer(0.5, Timer_TakeOverSurBot, target);
        }
    }
    
    for (int i = 0; i < infCount; i++)
    {
        int target = infClients[i];
        if (IsClientInGame(target) && !IsFakeClient(target))
        {
            ChangeClientTeam(target, TEAM_INF);
        }
    }
    
    PrintToChatAll("%s[EXP]%s 队伍平衡完成！", COLOR_GREEN, COLOR_DEFAULT);
    g_bMixVoteInProgress = false;
    CleanupMixArrays();
    
    return Plugin_Stop;
}

public Action Timer_TakeOverSurBot(Handle timer, any client)
{
    if (!IsClientInGame(client) || IsFakeClient(client))
        return Plugin_Stop;
    
    if (GetClientTeam(client) != TEAM_SURV)
        return Plugin_Stop;
    
    int bot = FindAliveSurBot();
    if (bot)
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