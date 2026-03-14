#include <sourcemod>
#include <sdktools>

#define SOUND "player/spitter/spitter_acid_impact.wav"

public void OnPluginStart()
{
    HookEvent("infected_hurt", Event_InfectedHurt);
    HookEvent("player_hurt", Event_PlayerHurt);
}

public void OnMapStart()
{
    PrecacheSound(SOUND, true);
}

public Action Event_InfectedHurt(Event event, const char[] name, bool dontBroadcast)
{
    int attacker = GetClientOfUserId(event.GetInt("attacker"));

    if(attacker > 0 && attacker <= MaxClients && IsClientInGame(attacker))
    {
        EmitSoundToClient(attacker, SOUND);
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
            EmitSoundToClient(attacker, SOUND);
        }
    }

    return Plugin_Continue;
}