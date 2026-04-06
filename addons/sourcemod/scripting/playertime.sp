 public PlVers:__version =
{
	version = 5,
	filevers = "1.11.0.6825",
	date = "04/17/2024",
	time = "21:26:12"
};
new Float:NULL_VECTOR[3];
new String:NULL_STRING[16];
public Extension:__ext_core =
{
	name = "Core",
	file = "core",
	autoload = 0,
	required = 0,
};
new MaxClients;
public Extension:__ext_rip =
{
	name = "REST in Pawn",
	file = "rip.ext",
	autoload = 1,
	required = 1,
};
new String:CTag[][48];
new String:CTagCode[8][48] =
{
	"ive}总游玩时间:{green}%.1f小时{olive}(实际:{green}%.1f小时{olive}),最近两周时间:{green}%.1f小时",
	"��玩时间:{green}%.1f小时{olive}(实际:{green}%.1f小时{olive}),最近两周时间:{green}%.1f小时",
	"间:{green}%.1f小时{olive}(实际:{green}%.1f小时{olive}),最近两周时间:{green}%.1f小时",
	"en}%.1f小时{olive}(实际:{green}%.1f小时{olive}),最近两周时间:{green}%.1f小时",
	"��时{olive}(实际:{green}%.1f小时{olive}),最近两周时间:{green}%.1f小时",
	"ive}(实际:{green}%.1f小时{olive}),最近两周时间:{green}%.1f小时",
	"际:{green}%.1f小时{olive}),最近两周时间:{green}%.1f小时",
	"en}%.1f小时{olive}),最近两周时间:{green}%.1f小时"
};
new bool:CTagReqSayText2[12] =
{
	0, 0, 0, 1, 1, 1, 0, 0, 0, 0, 0, 0
};
new bool:CEventIsHooked;
new bool:CSkipList[66];
new bool:CProfile_Colors[12] =
{
	1, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0
};
new bool:CProfile_SayText2;
new CProfile_TeamIndex[10] =
{
	-1, ...
};
new <enumstruct0>:player[66] =
{
	3720, 3736, 3752, 3768, 3784, 3800, 3816, 3832, 3848, 3864, 3880, 3896, 3912, 3928, 3944, 3960, 3976, 3992, 4008, 4024, 4040, 4056, 4072, 4088, 4104, 4120, 4136, 4152, 4168, 4184, 4200, 4216, 4232, 4248, 4264, 4280, 4296, 4312, 4328, 4344, 4360, 4376, 4392, 4408, 4424, 4440, 4456, 4472, 4488, 4504, 4520, 4536, 4552, 4568, 4584, 4600, 4616, 4632, 4648, 4664, 4680, 4696, 4712, 4728, 4744, 4760
};
public Plugin:myinfo =
{
	name = "[L4D2]时长检测",
	description = "display time",
	author = "奈",
	version = "1.3",
	url = "https://github.com/NanakaNeko/l4d2_plugins_coop"
};
void:Event_MapStart(Event:_arg0, String:_arg1[], bool:_arg2)
{
	CSetupProfile();
	new i = 1;
	while (i <= MaxClients)
	{
		CSkipList[i] = 0;
		i++;
	}
	return 0;
}


/* ERROR! null */
 function "DisplayTime" (number 1)

/* ERROR! null */
 function "DisplayTime2" (number 2)
void:GetPlayerTime(_arg0)
{
	decl String:authId64[1040];
	decl String:URL[16384];
	GetClientAuthId(_arg0, 3, authId64, 65, true);
	if (StrEqual(authId64, "STEAM_ID_STOP_IGNORING_RETVALS", true))
	{
		return 0;
	}
	new HTTPClient:httpClient = 5568;
	Format(URL, 1024, "%s&key=%s&steamid=%s", "IPlayerService/GetOwnedGames/v1/?format=json&appids_filter[0]=550", "C7B3FC46E6E6D5C87700963F0688FCB4", authId64);

/* ERROR! unknown load SysReq */
 function "GetPlayerTime" (number 3)
bool:IsValidClient(_arg0)
{
	new var1;
	return _arg0 > 0 && _arg0 <= MaxClients && IsClientInGame(_arg0);
}

Float:/(_arg0, Float:_arg1)
{
	return float(_arg0) / _arg1;
}

bool:StrEqual(String:_arg0[], String:_arg1[], bool:_arg2)
{
	return strcmp(_arg0[0], _arg1[0], _arg2) == 0;
}

Handle:StartMessageOne(String:_arg0[], _arg1, _arg2)
{
	new players[1] = _arg1;
	return StartMessage(_arg0[0], players, 1, _arg2);
}


/* ERROR! null */
 function "CPrintToChat" (number 8)
void:CPrintToChatAll(String:_arg0[], any:_arg1)
{
	decl String:szBuffer[4000];
	new i = 1;
	while (i <= MaxClients)
	{
		if (IsClientInGame(i))
		{
			if (IsFakeClient(i))
			{
				if (IsClientSourceTV(i))
				{
				}
			}
			if (!CSkipList[i])
			{
				SetGlobalTransTarget(i);
				VFormat(szBuffer, 250, _arg0[0], 2);
				CPrintToChat(i, "%s", szBuffer);
			}
		}
		CSkipList[i] = 0;
		i++;
	}
	return 0;
}

CFormat(String:_arg0[], _arg1, _arg2)
{
	decl String:szGameName[480];
	GetGameFolderName(szGameName, 30);
	if (!CEventIsHooked)
	{
		CSetupProfile();
		HookEvent("server_spawn", 1, 2);
		CEventIsHooked = true;
	}
	new iRandomPlayer = -1;
	if (StrEqual(szGameName, "csgo", false))
	{
		Format(_arg0[0], _arg1, " \x01\x0B\x01%s", _arg0[0]);
	}
	if (_arg2 != -1)
	{
		if (CProfile_SayText2)
		{
			ReplaceString(_arg0[0], _arg1, "{teamcolor}", "\x03", false);
			iRandomPlayer = _arg2;
		}
		else
		{
			ReplaceString(_arg0[0], _arg1, "{teamcolor}", CTagCode[2], false);
		}
	}
	else
	{
		ReplaceString(_arg0[0], _arg1, "{teamcolor}", "", false);
	}
	new i;
	while (i < 12)
	{
		if (!(StrContains(_arg0[0], CTag[i], false) == -1))
		{
			if (CProfile_Colors[i])
			{
				if (CTagReqSayText2[i])
				{
					if (CProfile_SayText2)
					{
						if (iRandomPlayer == -1)
						{
							iRandomPlayer = CFindRandomPlayerByTeam(CProfile_TeamIndex[i]);
							if (iRandomPlayer == -2)
							{
								ReplaceString(_arg0[0], _arg1, CTag[i], CTagCode[2], false);
							}
							else
							{
								ReplaceString(_arg0[0], _arg1, CTag[i], CTagCode[i], false);
							}
						}
						ThrowError("Using two team colors in one message is not allowed");
					}
					ReplaceString(_arg0[0], _arg1, CTag[i], CTagCode[2], false);
				}
				ReplaceString(_arg0[0], _arg1, CTag[i], CTagCode[i], false);
			}
			ReplaceString(_arg0[0], _arg1, CTag[i], CTagCode[2], false);
		}
		i++;
	}
	return iRandomPlayer;
}

CFindRandomPlayerByTeam(_arg0)
{
	if (_arg0 == 0)
	{
		return 0;
	}
	new i = 1;
	while (i <= MaxClients)
	{
		if (IsClientInGame(i))
		{
			if (_arg0 == GetClientTeam(i))
			{
				return i;
			}
		}
		i++;
	}
	return -2;
}


/* ERROR! null */
 function "CSayText2" (number 12)
void:CSetupProfile()
{
	decl String:szGameName[480];
	GetGameFolderName(szGameName, 30);
	if (strcmp(szGameName, "cstrike", false) == 0)
	{
		CProfile_Colors[3] = 1;
		CProfile_Colors[4] = 1;
		CProfile_Colors[5] = 1;
		CProfile_Colors[6] = 1;
		CProfile_TeamIndex[3] = 0;
		CProfile_TeamIndex[4] = 2;
		CProfile_TeamIndex[5] = 3;
		CProfile_SayText2 = true;
		return 0;
	}
	if (strcmp(szGameName, "csgo", false) == 0)
	{
		CProfile_Colors[4] = 1;
		CProfile_Colors[5] = 1;
		CProfile_Colors[6] = 1;
		CProfile_Colors[1] = 1;
		CProfile_Colors[7] = 1;
		CProfile_Colors[8] = 1;
		CProfile_Colors[9] = 1;
		CProfile_Colors[10] = 1;
		CProfile_Colors[11] = 1;
		CProfile_TeamIndex[4] = 2;
		CProfile_TeamIndex[5] = 3;
		CProfile_SayText2 = true;
		return 0;
	}
	if (strcmp(szGameName, "tf", false) == 0)
	{
		CProfile_Colors[3] = 1;
		CProfile_Colors[4] = 1;
		CProfile_Colors[5] = 1;
		CProfile_Colors[6] = 1;
		CProfile_TeamIndex[3] = 0;
		CProfile_TeamIndex[4] = 2;
		CProfile_TeamIndex[5] = 3;
		CProfile_SayText2 = true;
		return 0;
	}
	if (!(strcmp(szGameName, "left4dead", false) == 0))
	{
		if (!(strcmp(szGameName, "left4dead2", false) == 0))
		{
			if (strcmp(szGameName, "hl2mp", false) == 0)
			{
				static ConVar:hCvarMpTeamPlay;
				if (hCvarMpTeamPlay == 0)
				{
					hCvarMpTeamPlay = FindConVar("mp_teamplay");
				}
				if (ConVar.BoolValue.get(hCvarMpTeamPlay))
				{
					CProfile_Colors[4] = 1;
					CProfile_Colors[5] = 1;
					CProfile_Colors[6] = 1;
					CProfile_TeamIndex[4] = 3;
					CProfile_TeamIndex[5] = 2;
					CProfile_SayText2 = true;
				}
				else
				{
					CProfile_SayText2 = false;
					CProfile_Colors[6] = 1;
				}
				return 0;
			}
			if (strcmp(szGameName, "dod", false) == 0)
			{
				CProfile_Colors[6] = 1;
				CProfile_SayText2 = false;
				return 0;
			}
			if (GetUserMessageId("SayText2") == -1)
			{
				CProfile_SayText2 = false;
				return 0;
			}
			CProfile_Colors[4] = 1;
			CProfile_Colors[5] = 1;
			CProfile_TeamIndex[4] = 2;
			CProfile_TeamIndex[5] = 3;
			CProfile_SayText2 = true;
			return 0;
		}
	}
	CProfile_Colors[3] = 1;
	CProfile_Colors[4] = 1;
	CProfile_Colors[5] = 1;
	CProfile_Colors[6] = 1;
	CProfile_TeamIndex[3] = 0;
	CProfile_TeamIndex[4] = 3;
	CProfile_TeamIndex[5] = 2;
	CProfile_SayText2 = true;
	return 0;
}

public Action:Display_AllTime(_arg0, _arg1)
{
	new i = 1;
	while (i <= MaxClients)
	{
		if (IsValidClient(i))
		{
			if (!(IsFakeClient(i)))
			{
				GetPlayerTime(i);
				DisplayTime2(_arg0, i);
			}
		}
		i++;
	}
	return 3;
}

public Action:Display_Time(_arg0, _arg1)
{
	if (IsValidClient(_arg0))
	{
		if (!(IsFakeClient(_arg0)))
		{
			GetPlayerTime(_arg0);
			DisplayTime(_arg0);
		}
	}
	return 3;
}

public void:Event_PlayerDisconnect(Event:_arg0, String:_arg1[], bool:_arg2)
{
	new client;
	new client = GetClientOfUserId(GetEventInt(_arg0, "userid", client));
	if (1 <= client <= MaxClients)
	{
		if (IsFakeClient(client))
		{
			return 0;
		}
		player[client] = 0;
		player[client][1] = 0;
		player[client][2] = 0;
		player[client][3] = 0;
		return 0;
	}
	return 0;
}

public Action:GetRealTime(Handle:_arg0, _arg1)
{
	decl String:authId64[1040];
	decl String:URL[16384];
	GetClientAuthId(_arg1, 3, authId64, 65, true);
	new HTTPClient:httpClient = 5724;
	Format(URL, 1024, "%s&key=%s&steamid=%s", "ISteamUserStats/GetUserStatsForGame/v2/?appid=550", "C7B3FC46E6E6D5C87700963F0688FCB4", authId64);

/* ERROR! unknown load SysReq */
 function "GetRealTime" (number 17)
public void:HTTPResponse_GetOwnedGames(HTTPResponse:_arg0, _arg1)
{
	if (!(HTTPResponse.Status.get(_arg0) != 200))
	{
		if (!(HTTPResponse.Data.get(_arg0) == 0))
		{
			new JSONObject:dataObj = 5928;
			new JSONObject:dataObj = JSONObject.Get(HTTPResponse.Data.get(_arg0), dataObj);
			if (dataObj)
			{
				if (JSONObject.Size.get(dataObj))
				{
					if (JSONObject.HasKey(dataObj, "games"))
					{
						if (!(JSONObject.IsNull(dataObj, "games")))
						{
							new JSONArray:jsonArray = 5956;
							new JSONArray:jsonArray = JSONObject.Get(dataObj, jsonArray);
							CloseHandle(dataObj);
							dataObj = 0;
							dataObj = JSONArray.Get(jsonArray, 0);
							player[_arg1] = JSONObject.GetInt(dataObj, "playtime_forever");
							player[_arg1][2] = JSONObject.GetInt(dataObj, "playtime_2weeks");
							CloseHandle(jsonArray);
							jsonArray = 0;
							CloseHandle(dataObj);
							dataObj = 0;
							return 0;
						}
					}
				}
				player[_arg1] = 0;
				player[_arg1][2] = 0;
				CloseHandle(dataObj);
				dataObj = 0;
				return 0;
			}
			player[_arg1] = 0;
			player[_arg1][2] = 0;
			return 0;
		}
	}
	LogError("Failed to retrieve response (GetOwnedGames) - HTTPStatus: %i", HTTPResponse.Status.get(_arg0));
	return 0;
}

public void:HTTPResponse_GetUserStatsForGame(HTTPResponse:_arg0, _arg1)
{
	if (!(HTTPResponse.Status.get(_arg0) != 200))
	{
		if (!(HTTPResponse.Data.get(_arg0) == 0))
		{
			new JSONObject:dataObj = 6068;
			new JSONObject:dataObj = JSONObject.Get(HTTPResponse.Data.get(_arg0), dataObj);
			if (dataObj)
			{
				if (JSONObject.Size.get(dataObj))
				{
					if (JSONObject.HasKey(dataObj, "stats"))
					{
						if (JSONObject.IsNull(dataObj, "stats"))
						{
						}
						new JSONArray:jsonArray = 6096;
						new JSONArray:jsonArray = JSONObject.Get(dataObj, jsonArray);
						decl String:keyname[1024];
						new i;

/* ERROR! unknown load SysReq */
 function "HTTPResponse_GetUserStatsForGame" (number 19)
public void:OnClientPostAdminCheck(_arg0)
{
	if (IsValidClient(_arg0))
	{
		if (!(IsFakeClient(_arg0)))
		{
			if (!player[_arg0][3])
			{
				GetPlayerTime(_arg0);
				CreateTimer(3.0, 47, _arg0, 0);
			}
		}
	}
	return 0;
}

public void:OnPluginStart()
{
	RegConsoleCmd("sm_time", 31, "查询自己游戏时间", 0);
	RegConsoleCmd("sm_alltime", 29, "查询所有人游戏时间", 0);
	HookEvent("player_disconnect", 33, 0);
	return 0;
}

public void:__ext_core_SetNTVOptional()
{
	MarkNativeAsOptional("GetFeatureStatus");
	MarkNativeAsOptional("RequireFeature");
	MarkNativeAsOptional("AddCommandListener");
	MarkNativeAsOptional("RemoveCommandListener");
	MarkNativeAsOptional("BfWriteBool");
	MarkNativeAsOptional("BfWriteByte");
	MarkNativeAsOptional("BfWriteChar");
	MarkNativeAsOptional("BfWriteShort");
	MarkNativeAsOptional("BfWriteWord");
	MarkNativeAsOptional("BfWriteNum");
	MarkNativeAsOptional("BfWriteFloat");
	MarkNativeAsOptional("BfWriteString");
	MarkNativeAsOptional("BfWriteEntity");
	MarkNativeAsOptional("BfWriteAngle");
	MarkNativeAsOptional("BfWriteCoord");
	MarkNativeAsOptional("BfWriteVecCoord");
	MarkNativeAsOptional("BfWriteVecNormal");
	MarkNativeAsOptional("BfWriteAngles");
	MarkNativeAsOptional("BfReadBool");
	MarkNativeAsOptional("BfReadByte");
	MarkNativeAsOptional("BfReadChar");
	MarkNativeAsOptional("BfReadShort");
	MarkNativeAsOptional("BfReadWord");
	MarkNativeAsOptional("BfReadNum");
	MarkNativeAsOptional("BfReadFloat");
	MarkNativeAsOptional("BfReadString");
	MarkNativeAsOptional("BfReadEntity");
	MarkNativeAsOptional("BfReadAngle");
	MarkNativeAsOptional("BfReadCoord");
	MarkNativeAsOptional("BfReadVecCoord");
	MarkNativeAsOptional("BfReadVecNormal");
	MarkNativeAsOptional("BfReadAngles");
	MarkNativeAsOptional("BfGetNumBytesLeft");
	MarkNativeAsOptional("BfWrite.WriteBool");
	MarkNativeAsOptional("BfWrite.WriteByte");
	MarkNativeAsOptional("BfWrite.WriteChar");
	MarkNativeAsOptional("BfWrite.WriteShort");
	MarkNativeAsOptional("BfWrite.WriteWord");
	MarkNativeAsOptional("BfWrite.WriteNum");
	MarkNativeAsOptional("BfWrite.WriteFloat");
	MarkNativeAsOptional("BfWrite.WriteString");
	MarkNativeAsOptional("BfWrite.WriteEntity");
	MarkNativeAsOptional("BfWrite.WriteAngle");
	MarkNativeAsOptional("BfWrite.WriteCoord");
	MarkNativeAsOptional("BfWrite.WriteVecCoord");
	MarkNativeAsOptional("BfWrite.WriteVecNormal");
	MarkNativeAsOptional("BfWrite.WriteAngles");
	MarkNativeAsOptional("BfRead.ReadBool");
	MarkNativeAsOptional("BfRead.ReadByte");
	MarkNativeAsOptional("BfRead.ReadChar");
	MarkNativeAsOptional("BfRead.ReadShort");
	MarkNativeAsOptional("BfRead.ReadWord");
	MarkNativeAsOptional("BfRead.ReadNum");
	MarkNativeAsOptional("BfRead.ReadFloat");
	MarkNativeAsOptional("BfRead.ReadString");
	MarkNativeAsOptional("BfRead.ReadEntity");
	MarkNativeAsOptional("BfRead.ReadAngle");
	MarkNativeAsOptional("BfRead.ReadCoord");
	MarkNativeAsOptional("BfRead.ReadVecCoord");
	MarkNativeAsOptional("BfRead.ReadVecNormal");
	MarkNativeAsOptional("BfRead.ReadAngles");
	MarkNativeAsOptional("BfRead.BytesLeft.get");
	MarkNativeAsOptional("PbReadInt");
	MarkNativeAsOptional("PbReadFloat");
	MarkNativeAsOptional("PbReadBool");
	MarkNativeAsOptional("PbReadString");
	MarkNativeAsOptional("PbReadColor");
	MarkNativeAsOptional("PbReadAngle");
	MarkNativeAsOptional("PbReadVector");
	MarkNativeAsOptional("PbReadVector2D");
	MarkNativeAsOptional("PbGetRepeatedFieldCount");
	MarkNativeAsOptional("PbSetInt");
	MarkNativeAsOptional("PbSetFloat");
	MarkNativeAsOptional("PbSetBool");
	MarkNativeAsOptional("PbSetString");
	MarkNativeAsOptional("PbSetColor");
	MarkNativeAsOptional("PbSetAngle");
	MarkNativeAsOptional("PbSetVector");
	MarkNativeAsOptional("PbSetVector2D");
	MarkNativeAsOptional("PbAddInt");
	MarkNativeAsOptional("PbAddFloat");
	MarkNativeAsOptional("PbAddBool");
	MarkNativeAsOptional("PbAddString");
	MarkNativeAsOptional("PbAddColor");
	MarkNativeAsOptional("PbAddAngle");
	MarkNativeAsOptional("PbAddVector");
	MarkNativeAsOptional("PbAddVector2D");
	MarkNativeAsOptional("PbRemoveRepeatedFieldValue");
	MarkNativeAsOptional("PbReadMessage");
	MarkNativeAsOptional("PbReadRepeatedMessage");
	MarkNativeAsOptional("PbAddMessage");
	MarkNativeAsOptional("Protobuf.ReadInt");
	MarkNativeAsOptional("Protobuf.ReadInt64");
	MarkNativeAsOptional("Protobuf.ReadFloat");
	MarkNativeAsOptional("Protobuf.ReadBool");
	MarkNativeAsOptional("Protobuf.ReadString");
	MarkNativeAsOptional("Protobuf.ReadColor");
	MarkNativeAsOptional("Protobuf.ReadAngle");
	MarkNativeAsOptional("Protobuf.ReadVector");
	MarkNativeAsOptional("Protobuf.ReadVector2D");
	MarkNativeAsOptional("Protobuf.GetRepeatedFieldCount");
	MarkNativeAsOptional("Protobuf.SetInt");
	MarkNativeAsOptional("Protobuf.SetInt64");
	MarkNativeAsOptional("Protobuf.SetFloat");
	MarkNativeAsOptional("Protobuf.SetBool");
	MarkNativeAsOptional("Protobuf.SetString");
	MarkNativeAsOptional("Protobuf.SetColor");
	MarkNativeAsOptional("Protobuf.SetAngle");
	MarkNativeAsOptional("Protobuf.SetVector");
	MarkNativeAsOptional("Protobuf.SetVector2D");
	MarkNativeAsOptional("Protobuf.AddInt");
	MarkNativeAsOptional("Protobuf.AddInt64");
	MarkNativeAsOptional("Protobuf.AddFloat");
	MarkNativeAsOptional("Protobuf.AddBool");
	MarkNativeAsOptional("Protobuf.AddString");
	MarkNativeAsOptional("Protobuf.AddColor");
	MarkNativeAsOptional("Protobuf.AddAngle");
	MarkNativeAsOptional("Protobuf.AddVector");
	MarkNativeAsOptional("Protobuf.AddVector2D");
	MarkNativeAsOptional("Protobuf.RemoveRepeatedFieldValue");
	MarkNativeAsOptional("Protobuf.ReadMessage");
	MarkNativeAsOptional("Protobuf.ReadRepeatedMessage");
	MarkNativeAsOptional("Protobuf.AddMessage");
	VerifyCoreVersion();
	return 0;
}

public Action:announcetime(Handle:_arg0, _arg1)
{
	if (IsValidClient(_arg1))
	{
		if (!(IsFakeClient(_arg1)))
		{
			DisplayTime(_arg1);
			player[_arg1][3] = 1;
		}
	}
	return 0;
}

 