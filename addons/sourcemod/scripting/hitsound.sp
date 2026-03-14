#include <sourcemod>
#include <sdktools>

ConVar g_hHitSound;
char g_sHitSound[PLATFORM_MAX_PATH];

#define DEFAULT_SOUND "player/spitter/spitter_acid_impact.wav"

public void OnPluginStart()
{
    g_hHitSound = CreateConVar("hitsound_file", DEFAULT_SOUND, "Hit sound sample path. Change this if another plugin blocks the default sample.");
    g_hHitSound.GetString(g_sHitSound, sizeof(g_sHitSound));
    g_hHitSound.AddChangeHook(OnSoundChanged);

    HookEvent("infected_hurt", Event_InfectedHurt);
    HookEvent("player_hurt", Event_PlayerHurt);
}

public void OnMapStart()
{
    PrecacheSound(g_sHitSound, true);
}

public void OnSoundChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
    convar.GetString(g_sHitSound, sizeof(g_sHitSound));
    PrecacheSound(g_sHitSound, true);
}

public Action Event_InfectedHurt(Event event, const char[] name, bool dontBroadcast)
{
    int attacker = GetClientOfUserId(event.GetInt("attacker"));

    if(attacker > 0 && attacker <= MaxClients && IsClientInGame(attacker))
    {
        EmitSoundToClient(attacker, g_sHitSound);
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
            EmitSoundToClient(attacker, g_sHitSound);
        }
    }

    return Plugin_Continue;
}
