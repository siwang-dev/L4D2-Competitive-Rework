#include <sourcemod>
#include <sdktools>

ConVar g_hHitSound;
ConVar g_hHitSoundDebug;
bool g_bUpdatingSoundCvar;
bool g_bHitSoundReady;
char g_sHitSound[PLATFORM_MAX_PATH];

#define DEFAULT_SOUND "ui/pickup_secret01.wav"

static bool TryPrecacheHitSound(const char[] soundPath)
{
    strcopy(g_sHitSound, sizeof(g_sHitSound), soundPath);
    g_bHitSoundReady = PrecacheSound(g_sHitSound, true);
    return g_bHitSoundReady;
}

static void RefreshHitSound()
{
    char configuredSound[PLATFORM_MAX_PATH];
    g_hHitSound.GetString(configuredSound, sizeof(configuredSound));

    if (configuredSound[0] == '\0')
    {
        strcopy(configuredSound, sizeof(configuredSound), DEFAULT_SOUND);
    }

    strcopy(g_sHitSound, sizeof(g_sHitSound), configuredSound);
    g_bHitSoundReady = false;

    if (!IsServerProcessing())
    {
        return;
    }

    if (TryPrecacheHitSound(configuredSound))
    {
        return;
    }

    LogError("[hitsound] Failed to precache '%s'. Falling back to '%s'.", configuredSound, DEFAULT_SOUND);

    if (!StrEqual(configuredSound, DEFAULT_SOUND))
    {
        g_bUpdatingSoundCvar = true;
        g_hHitSound.SetString(DEFAULT_SOUND);
        g_bUpdatingSoundCvar = false;
    }

    if (!TryPrecacheHitSound(DEFAULT_SOUND))
    {
        LogError("[hitsound] Failed to precache fallback sound '%s'. Hitsound playback disabled until a valid sound is configured.", DEFAULT_SOUND);
    }
}

static void PlayHitSound(int client)
{
    if (client <= 0 || client > MaxClients || !IsClientInGame(client) || !g_bHitSoundReady)
    {
        return;
    }

    EmitSoundToClient(client, g_sHitSound);

    if (g_hHitSoundDebug.BoolValue)
    {
        PrintToServer("[hitsound] playback -> client=%N (%d), sound=%s", client, client, g_sHitSound);
    }
}

public void OnPluginStart()
{
    g_hHitSound = CreateConVar("hitsound_file", DEFAULT_SOUND, "Hit sound sample path. Change this if another plugin blocks the default sample.");
    g_hHitSoundDebug = CreateConVar("hitsound_debug", "0", "Enable debug logging for hitsound (0=off, 1=on).");
    g_hHitSound.AddChangeHook(OnSoundChanged);

    RefreshHitSound();

    HookEvent("infected_hurt", Event_InfectedHurt);
    HookEvent("player_hurt", Event_PlayerHurt);
}

public void OnMapStart()
{
    RefreshHitSound();

    if (g_hHitSoundDebug.BoolValue)
    {
        PrintToServer("[hitsound] OnMapStart ready=%d, sound=%s", g_bHitSoundReady, g_sHitSound);
    }
}

public void OnSoundChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
    if (g_bUpdatingSoundCvar)
    {
        return;
    }

    RefreshHitSound();

    if (g_hHitSoundDebug.BoolValue)
    {
        PrintToServer("[hitsound] hitsound_file changed: '%s' -> '%s' (ready=%d)", oldValue, g_sHitSound, g_bHitSoundReady);
    }
}

public Action Event_InfectedHurt(Event event, const char[] name, bool dontBroadcast)
{
    int attacker = GetClientOfUserId(event.GetInt("attacker"));

    if (attacker > 0 && attacker <= MaxClients && IsClientInGame(attacker))
    {
        PlayHitSound(attacker);

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

    if (attacker > 0 && attacker <= MaxClients && IsClientInGame(attacker)
        && victim > 0 && victim <= MaxClients && IsClientInGame(victim))
    {
        if (GetClientTeam(victim) == 3)
        {
            PlayHitSound(attacker);

            if (g_hHitSoundDebug.BoolValue)
            {
                PrintToServer("[hitsound] player_hurt -> attacker=%N (%d), victim=%N (%d), sound=%s", attacker, attacker, victim, victim, g_sHitSound);
            }
        }
    }

    return Plugin_Continue;
}
