local GRA, gra, SYNC = unpack(select(2, ...))
local L = select(2, ...).L

local syncDb = {};
local oldRosterVersions = {};
local syncLeader = "";
local announcementDate = 0;
local rosterSyncProcess = false;
local rosterMergeProcess = false;
local rosterChanged = false;

local function CheckAddonVersion()
    if time() - announcementDate > 900 then    
        local verNumber = tonumber(strsub(strsplit("-", gra.version), 2));

        for k,v in pairs(syncDb) do
            if verNumber < tonumber(strsub(strsplit("-", v.addon), 2)) then
                GRA:Print("There is new version of GRA addon ("..v.addon.."). Please update your GRA addon.");
                announcementDate = time();
            end
        end   
    end
end

local function GetLeaderRoster()
    local l = SYNC:GetLeader();
    return l, syncDb[l].rosterVersion;
end

function SYNC:Init()
    local playerName = UnitName("player");

    SYNC:UpsertData(playerName, gra.version, _G[GRA_R_Config]["raidVersion"], _G[GRA_R_Config]["raidEditDate"], 
                        _G[GRA_R_Config]["rosterVersion"]);    
end

function SYNC:GetData(player)
    return syncDb[player];    
end

function SYNC:GetAllNames()
    local r = {};
    for k, _ in pairs(syncDb) do
        table.insert(r, k);
    end
    
    return r;
end

function SYNC:UpsertData(player, addonVersion, raidVersion, raidDate, rosterVersion)
    GRA:Debug("SYNC:UpsertData - %s, %s, %s, %s, %s", player, addonVersion, raidVersion, raidDate, rosterVersion);
        
    if syncDb[player] == nil then
        syncDb[player] = {};
    end
    
    syncDb[player].name = player;
    syncDb[player].addon = addonVersion;
    syncDb[player].raidVersion = raidVersion;
    syncDb[player].raidDate = raidDate;
    syncDb[player].rosterVersion = rosterVersion;

    CheckAddonVersion();
    if SYNC:AmITheLeader() and GRA:TContains(oldRosterVersions, rosterVersion) then
        GRA:SendRosterData(player);
    end
    
end

function SYNC:RemoveData(player)
    GRA:Debug("SYNC:RemoveData - %s", player);
    syncDb[player] = nil;
end

function SYNC:UpdateRosterInfo(player, rosterVersion)
    syncDb[player].rosterVersion = rosterVersion;
end

function SYNC:ChooseNewLeader()
    GRA:Debug("SYNC:ChooseNewLeader");
    local raidVersion = "";
    local raidDate = -1;
    local leader = "";
    local candidates = {};
    local guildRank;

    for k,v in pairs(syncDb) do
        if v.raidDate ~= nil then
            if raidDate < v.raidDate then
                raidVersion = v.raidVersion;
                raidDate = v.raidDate;
                leader = k;

                _, _, guildRank = GetGuildInfo(k);
                candidates = { [k] = guildRank };

            elseif raidDate == v.raidDate then
                leader = "";
                _, _, guildRank = GetGuildInfo(k);
                candidates[k] = guildRank;

            end            
        end        
    end

    if leader == "" then
        local sorted = {}
        for k, v in pairs(candidates) do
            table.insert(sorted,{k,v})
        end

        table.sort(sorted, function(a,b) return (a[2] < b[2]) end);
        
        leader = sorted[1][1];
    end

    SYNC:SetLeader(leader);
    return leader;
end

function SYNC:AmITheLeader()
    local l = syncLeader == UnitName("player");
    GRA:Debug("SYNC:AmITheLeader - %s", tostring(l));
    return l;
end

function SYNC:SetLeader(player)
    syncLeader = player;    
end

function SYNC:GetLeader()
    return syncLeader;    
end

function SYNC:CheckRosterVersions()
    GRA:Debug("SYNC:CheckRosterVersions");    

    C_Timer.After(900, function ()
        SYNC:CheckRosterVersions();
    end);

    if GRA:Getn(syncDb) == 1 then
        GRA:Debug("SYNC:CheckRosterVersions - brake since you are alone");
        return;
    end
    rosterSyncProcess = true;

    local alreadyKnownVersions = {};
    local l, rv = GetLeaderRoster();
    table.insert(alreadyKnownVersions, rv);
    
    for _, v in ipairs(oldRosterVersions) do
        table.insert(alreadyKnownVersions, v);
    end

    for k, v in pairs(syncDb) do  
        if not GRA:CheckIfGuildMemberOnline(k, true) then 
            SYNC:RemoveData(k);
        else
            if not GRA:TContains(alreadyKnownVersions, v.rosterVersion) then
                table.insert(alreadyKnownVersions, v.rosterVersion);
                GRA:AskForRosterData(k);
            end
        end        
    end

    C_Timer.After(15, function ()
       SYNC:AnnounceNewRoster(); 
    end)
end

function SYNC:AnnounceNewRoster()
    GRA:Debug("SYNC:AnnounceNewRoster");
    if rosterChanged then
        rosterChanged = false;
        GRA:InformAboutRosterVersion();
        GRA:SendRosterData();
    else
        for k, v in pairs(syncDb) do
            if GRA:TContains(oldRosterVersions, v.rosterVersion) then
                GRA:SendRosterData(k);
            end            
        end
    end  
    rosterSyncProcess = false;  
end

function SYNC:MergeRoster(rosterVersion, rosterData, deletedRoster)
    GRA:Debug("SYNC:MergeRoster - %s", rosterVersion);    
    
    if rosterMergeProcess then
        C_Timer.After(0.5, function ()
            SYNC:MergeRoster(rosterVersion, rosterData, deletedRoster);
        end);
        return;
    end

    rosterMergeProcess = true;
    local changes = false;

    if rosterData == nil or GRA:TableIsEmpty(rosterData) then
        GRA:Debug("Empty roster", k);
        table.insert(oldRosterVersions, rosterVersion);
    else
        for k, v in pairs(rosterData) do
            GRA:Debug("Checking - %s", k);
            if (_G[GRA_R_Roster][k] == nil or _G[GRA_R_Roster][k]["lastchange"] == nil) then                
                _G[GRA_R_Roster][k] = { ["class"] = v.class, ["role"] = v.role, ["altOf"] = v.altOf, ["lastchange"] = v.lastchange };                               
                changes = true;
                GRA:Debug("New entry added - %s", k);
            elseif v.lastchange > _G[GRA_R_Roster][k]["lastchange"] then
                _G[GRA_R_Roster][k]["class"] = v.class; 
                _G[GRA_R_Roster][k]["role"] = v.role; 
                _G[GRA_R_Roster][k]["altOf"] = v.altOf; 
                _G[GRA_R_Roster][k]["lastchange"] = v.lastchange;
                changes = true;
            end
            
            if _G[GRA_R_Roster][k]["lastchange"] == nil then
                _G[GRA_R_Roster][k]["lastchange"] = time();
            end
        end

        for k,v in pairs(deletedRoster) do
            if _G[GRA_R_Deleted][k] == nil or _G[GRA_R_Deleted][k] < v then
                _G[GRA_R_Deleted][k] = v;
                changes = true;            
            end            
        end

        for k, v in pairs(_G[GRA_R_Deleted]) do
            if _G[GRA_R_Roster][k] ~= nil and _G[GRA_R_Roster][k]["lastchange"] > v then
                _G[GRA_R_Deleted][k] = nil;
                changes = true;
            elseif _G[GRA_R_Roster][k] ~= nil and _G[GRA_R_Roster][k]["lastchange"] < v then
                _G[GRA_R_Roster][k] = nil;
                changes = true;
            end            
        end 
        table.insert(oldRosterVersions, rosterVersion);       
    end

    if changes then        
        table.insert(oldRosterVersions, _G[GRA_R_Config]["rosterVersion"]);
        _G[GRA_R_Config]["rosterVersion"] = GRA:GenerateSID();
        rosterChanged = true;
    end
    
    rosterMergeProcess = false;
    GRA:Debug("SYNC:MergeRoster End - %s - %s", rosterVersion, tostring(changes));

    if not rosterSyncProcess then
        SYNC:AnnounceNewRoster();
    end    
end

function SYNC:GenerateNewRosterVersion()
    local oldVer = _G[GRA_R_Config]["rosterVersion"];
    _G[GRA_R_Config]["rosterVersion"] = GRA:GenerateSID();
    
    if SYNC:AmITheLeader() then
        rosterChanged = true;
        table.insert(oldRosterVersions, oldVer);
        SYNC:AnnounceNewRoster();
    else
        GRA:SendRosterData(SYNC:GetLeader());
    end    
end

function SYNC:CheckRosterVersionStatus(player)
    local ver = syncDb[player].rosterVersion
    local _, rv = GetLeaderRoster();

    if rv == ver then return "OK" end
    if GRA:TContains(oldRosterVersions, ver) then return "OLD" end
    return "MERGE";
end

