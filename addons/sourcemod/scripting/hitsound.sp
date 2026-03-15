#include <sourcemod>
#include <sdktools>

ConVar g_hHitSound;
ConVar g_hHitSoundDebug;
char g_sHitSound[PLATFORM_MAX_PATH];
char g_sHitSoundCommand[PLATFORM_MAX_PATH + 16];

#define DEFAULT_SOUND "ui/littlereward.wav"

public void OnPluginStart()
{
    g_hHitSound = CreateConVar("hitsound_file", DEFAULT_SOUND, "Hit sound sample path. Change this if another plugin blocks the default sample.");
    g_hHitSoundDebug = CreateConVar("hitsound_debug", "0", "Enable debug logging for hitsound (0=off, 1=on).");
    g_hHitSound.GetString(g_sHitSound, sizeof(g_sHitSound));
    FormatEx(g_sHitSoundCommand, sizeof(g_sHitSoundCommand), "play %s", g_sHitSound);
    g_hHitSound.AddChangeHook(OnSoundChanged);

    HookEvent("infected_hurt", Event_InfectedHurt);
    HookEvent("player_hurt", Event_PlayerHurt);
}

public void OnMapStart()
{
    PrecacheSound(g_sHitSound, true);
    FormatEx(g_sHitSoundCommand, sizeof(g_sHitSoundCommand), "play %s", g_sHitSound);

    if (g_hHitSoundDebug.BoolValue)
    {
        PrintToServer("[hitsound] OnMapStart precached: %s", g_sHitSound);
    }
}

public void OnSoundChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
    convar.GetString(g_sHitSound, sizeof(g_sHitSound));
    PrecacheSound(g_sHitSound, true);
    FormatEx(g_sHitSoundCommand, sizeof(g_sHitSoundCommand), "play %s", g_sHitSound);

    if (g_hHitSoundDebug.BoolValue)
    {
        PrintToServer("[hitsound] hitsound_file changed: '%s' -> '%s'", oldValue, g_sHitSound);
    }
}

public Action Event_InfectedHurt(Event event, const char[] name, bool dontBroadcast)
{
    int attacker = GetClientOfUserId(event.GetInt("attacker"));

    if(attacker > 0 && attacker <= MaxClients && IsClientInGame(attacker))
    {
        ClientCommand(attacker, g_sHitSoundCommand);

        if (g_hHitSoundDebug.BoolValue)
        {
            PrintToServer("[hitsound] infected_hurt -> attacker=%N (%d), sound=%s", attacker, attacker, g_sHitSound);
        }
    }

    return Plugin_Continue;
}

public Action Event_PlayerHurt(Event event, const char[] name, bool dontBroadcast)
{
    int attacker = GetClientOfUserId(event.GetInt("attacker"));
    int victim = GetClientOfUserId(event.GetInt("userid"));

    if(attacker > 0 && IsClientInGame(attacker) && victim > 0)
    {
        if(GetClientTeam(victim) == 3)
        {
            ClientCommand(attacker, g_sHitSoundCommand);

            if (g_hHitSoundDebug.BoolValue)
            {
                PrintToServer("[hitsound] player_hurt -> attacker=%N (%d), victim=%N (%d), sound=%s", attacker, attacker, victim, victim, g_sHitSound);
            }
        }
    }

    return Plugin_Continue;
}
