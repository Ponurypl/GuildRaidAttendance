local GRA, gra, SYNC = unpack(select(2, ...))
local L = select(2, ...).L

local Compresser = LibStub:GetLibrary("LibCompress")
local Encoder = Compresser:GetAddonEncodeTable()
local Serializer = LibStub:GetLibrary("AceSerializer-3.0")
local Comm = LibStub:GetLibrary("AceComm-3.0")

local CommEvents = {};
CommEvents.Handshake = "GRA_HANDSHAKE";
CommEvents.SendVersionInfo = "GRA_VERSION_INFO";
CommEvents.AskWhoIsSyncLeader = "GRA_LEADER_ASK";
CommEvents.ClaimLeadership = "GRA_IM_LEADER";
CommEvents.PromoteLeadership = "GRA_PROMO_LEADER";
CommEvents.AskForRosterData = "GRA_ROSTER_ASK";
CommEvents.RosterSync = "GRA_ROSTER_SYNC";
CommEvents.RaidlogSync = "GRA_RAIDLOG_SYNC";
CommEvents.RaidlogsSegmentSync = "GRA_SEGMENT_SYNC";
CommEvents.InformAboutRosterVersion = "GRA_ROSTER_INFO";

local sendChannels = {};
sendChannels.whisper = "WHISPER";
sendChannels.guild = "GUILD";

local sendChannel = "RAID";

-- from WeakAuras
local function TableToString(inTable)
    local serialized = Serializer:Serialize(inTable)
    local compressed = Compresser:CompressHuffman(serialized)
    return Encoder:Encode(compressed)
end

local function StringToTable(inString)
    local decoded = Encoder:Decode(inString)
    local decompressed, errorMsg = Compresser:Decompress(decoded)
    if not(decompressed) then
        GRA:Debug("Error decompressing: " .. errorMsg)
        return nil
    end
    local success, deserialized = Serializer:Deserialize(decompressed)
    if not(success) then
        GRA:Debug("Error deserializing: " .. deserialized)
        return nil
    end
    return deserialized
end

local eventFrame = CreateFrame("Frame")
eventFrame:SetScript("OnEvent", function(self, event, ...)
	self[event](self, ...)
end)

eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
function eventFrame:PLAYER_ENTERING_WORLD()
    eventFrame:UnregisterEvent("PLAYER_ENTERING_WORLD")
    if IsInGuild() then
        C_Timer.After(5, function () 
            GRA:Handshake();
        end);
    end
end


local function PrepareSyncHeader()
    local dataToSend = {
        ["name"] = UnitName("player");
        ["version"] = gra.version,
        ["raidVersion"] = _G[GRA_R_Config]["raidVersion"],
        ["rosterVersion"] = _G[GRA_R_Config]["rosterVersion"],
        ["raidEditDate"] = _G[GRA_R_Config]["raidEditDate"],
    }
    
    return TableToString(dataToSend);
end

-----------------------------------------
-- Handshake
-----------------------------------------

function GRA:Handshake()            
    local data = PrepareSyncHeader();
    Comm:SendCommMessage(CommEvents.Handshake, data, sendChannels.guild, nil, "NORMAL");
    GRA:Debug("Send: Handshake");

    C_Timer.After(5, function ()
        GRA:AskWhoIsSyncLeader();
    end)
end

Comm:RegisterComm(CommEvents.Handshake, function(prefix, message, channel, sender)
    if sender == UnitName("player") then return end
    GRA:Debug("Received: Handshake from %s", sender);

    local data = StringToTable(message);
    SYNC:UpsertData(data.name, data.version, data.raidVersion, data.raidEditDate, data.rosterVersion);
    GRA:SendVersionInfo(data.name);
end)


-----------------------------------------
-- SendVersionInfo
-----------------------------------------

function GRA:SendVersionInfo(target)
    if not GRA:CheckIfGuildMemberOnline(target, true) then return end
    
    local data = PrepareSyncHeader();
    Comm:SendCommMessage(CommEvents.SendVersionInfo, data, sendChannels.whisper, target, "NORMAL");
    GRA:Debug("Send: SendVersionInfo to %s", target);
end

Comm:RegisterComm(CommEvents.SendVersionInfo, function(prefix, message, channel, sender)
    if sender == UnitName("player") then return end
    
    local data = StringToTable(message);
    GRA:Debug("Received: SendVersionInfo from %s", sender);
    SYNC:UpsertData(data.name, data.version, data.raidVersion, data.raidEditDate, data.rosterVersion);
end)


-----------------------------------------
-- AskWhoIsSyncLeader
-----------------------------------------

function GRA:AskWhoIsSyncLeader()
    Comm:SendCommMessage(CommEvents.AskWhoIsSyncLeader, " ", sendChannels.guild, nil, "NORMAL");
    GRA:Debug("Send: AskWhoIsSyncLeader");
    C_Timer.After(5, function ()
        GRA:ChooseSyncLeader();
    end);
end

Comm:RegisterComm(CommEvents.AskWhoIsSyncLeader, function(prefix, message, channel, sender)
    if sender == UnitName("player") then return end
    GRA:Debug("Received: AskWhoIsSyncLeader from %s", sender);

    if SYNC:AmITheLeader() then        
        Comm:SendCommMessage(CommEvents.ClaimLeadership, " ", sendChannels.whisper, sender, "ALERT");
        GRA:Debug("Send: ClaimLeadership to %s", sender);
        local status = SYNC:CheckRosterVersionStatus(sender);
        
        if status == "OLD" then 
            GRA:SendRosterData(sender);
        elseif status == "MERGE" then
            GRA:AskForRosterData(sender);
        end
    end
end)

Comm:RegisterComm(CommEvents.ClaimLeadership, function(prefix, message, channel, sender)
    if sender == UnitName("player") then return end
    GRA:Debug("Received: ClaimLeadership from %s", sender);

    SYNC:SetLeader(sender);
end)

-----------------------------------------
-- ChooseSyncLeader
-----------------------------------------

function GRA:ChooseSyncLeader()
    local leader = SYNC:GetLeader();
    if leader == nil or leader == "" then
        leader = SYNC:ChooseNewLeader();
        Comm:SendCommMessage(CommEvents.PromoteLeadership, " ", sendChannels.whisper, leader, "ALERT");
        GRA:Debug("Send: PromoteLeadership to %s", leader);
    end
end

Comm:RegisterComm(CommEvents.PromoteLeadership, function(prefix, message, channel, sender)
    GRA:Debug("Received: PromoteLeadership from %s", sender);
    SYNC:SetLeader(UnitName("player"));
    Comm:SendCommMessage(CommEvents.ClaimLeadership, " ", sendChannels.guild, nil, "ALERT");
    GRA:Debug("Send: ClaimLeadership");
    SYNC:CheckRosterVersions();
end)


-----------------------------------------
-- InformAboutRosterVersion
-----------------------------------------

function GRA:InformAboutRosterVersion()
    local data = TableToString({_G[GRA_R_Config]["rosterVersion"]});

    Comm:SendCommMessage(CommEvents.InformAboutRosterVersion, data, sendChannels.guild, nil, "ALERT"); 
    GRA:Debug("Send: InformAboutRosterVersion - %s", _G[GRA_R_Config]["rosterVersion"]);   
end

Comm:RegisterComm(CommEvents.InformAboutRosterVersion, function(prefix, message, channel, sender)
    local data = StringToTable(message);

    GRA:Debug("Received: InformAboutRosterVersion from %s - %s", sender, data[1]);

    SYNC:UpdateRosterInfo(sender, data[1]);
end)

-----------------------------------------
-- AskForRosterData
-----------------------------------------

function GRA:AskForRosterData(target)
    if not GRA:CheckIfGuildMemberOnline(target, true) then return end

    Comm:SendCommMessage(CommEvents.AskForRosterData, " ", sendChannels.whisper, target, "ALERT");      
    GRA:Debug("Send: AskForRosterData to %s", target);     
end

Comm:RegisterComm(CommEvents.AskForRosterData, function(prefix, message, channel, sender)
    if sender == UnitName("player") then return end 
    GRA:Debug("Received: AskForRosterData from %s", sender);    
    GRA:SendRosterData(sender);
end)

-----------------------------------------
-- SendRosterData
-----------------------------------------

function GRA:SendRosterData(target)
    local roster = {};
    for k, v in pairs(_G[GRA_R_Roster]) do
        roster[k] = { ["class"] = v.class, ["role"] = v.role, ["altOf"] = v.altOf, ["lastchange"] = v.lastchange };
    end
    local data = TableToString({_G[GRA_R_Config]["rosterVersion"], roster, _G[GRA_R_Deleted]});

    if target ~= nil then        
        if not GRA:CheckIfGuildMemberOnline(target, true) then return end

        Comm:SendCommMessage(CommEvents.RosterSync, data, sendChannels.whisper, target, "BULK");
        GRA:Debug("Send: RosterSync to %s", target); 
    else
        Comm:SendCommMessage(CommEvents.RosterSync, data, sendChannels.guild, nil, "BULK"); 
        GRA:Debug("Send: RosterSync"); 
    end   
end

Comm:RegisterComm(CommEvents.RosterSync, function(prefix, message, channel, sender)
    if sender == UnitName("player") then return end    
    GRA:Debug("Received: RosterSync from %s", sender);    
    local data = StringToTable(message);
    
    if sender == SYNC:GetLeader() then
        for k, v in pairs(data[2]) do            
            if _G[GRA_R_Roster][k] == nil then
                _G[GRA_R_Roster][k] = {}
            end

            _G[GRA_R_Roster][k]["class"] = v.class; 
            _G[GRA_R_Roster][k]["role"] = v.role; 
            _G[GRA_R_Roster][k]["altOf"] = v.altOf; 
            _G[GRA_R_Roster][k]["lastchange"] = v.lastchange; 
        end

        for k,v in pairs(data[3]) do
            _G[GRA_R_Roster][k] = nil;
        end

        _G[GRA_R_Deleted] = data[3];        

        _G[GRA_R_Config]["rosterVersion"] = data[1];

        GRA:InformAboutRosterVersion();
        GRA:FireEvent("GRA_R_DONE");

    elseif SYNC:AmITheLeader() and channel == sendChannels.whisper then
        SYNC:MergeRoster(data[1], data[2], data[3]);
    end
end)

-----------------------------------------
-- send roster
-----------------------------------------
local receiveRosterPopup, sendRosterPopup, rosterAccepted, rosterReceived, receivedRoster
local function OnRosterReceived()
    if rosterAccepted and rosterReceived and receivedRoster then
        _G[GRA_R_Roster] = receivedRoster[1]
        _G[GRA_R_Config]["raidInfo"] = receivedRoster[2]

        GRA:FireEvent("GRA_R_DONE")
        wipe(receivedRoster)
    end
end

-- send roster data and raidInfo to raid members
function GRA:SendRosterToRaid()
    Comm:SendCommMessage("GRA_R_ASK", " ", sendChannel, nil, "ALERT")
    sendRosterPopup = nil
    gra.sending = true

    local encoded = TableToString({_G[GRA_R_Roster], _G[GRA_R_Config]["raidInfo"]})
    
    -- send roster
    Comm:SendCommMessage("GRA_R_SEND", encoded, sendChannel, nil, "BULK", function(arg, done, total)
        if not sendRosterPopup then
            sendRosterPopup = GRA:CreateDataTransferPopup(gra.colors.chartreuse.s..L["Sending roster data"], total, function()
                gra.sending = false
            end)
        end
        sendRosterPopup:SetValue(done)
        -- send progress
        Comm:SendCommMessage("GRA_R_PROG", done.."|"..total, sendChannel, nil, "ALERT")
    end)
end

-- whether to revieve
Comm:RegisterComm("GRA_R_ASK", function(prefix, message, channel, sender)
    if sender == UnitName("player") then return end

    rosterAccepted = false
    rosterReceived = false

    GRA:CreateStaticPopup(L["Receive Raid Roster"], L["Receive roster data from %s?"]:format(GRA:GetClassColoredName(sender, select(2, UnitClass(sender)))),
    function()
        rosterAccepted = true
        OnRosterReceived() -- maybe already received

        -- if receving then hide it immediately
        if receiveRosterPopup then receiveRosterPopup:Hide() end
        -- init
        receiveRosterPopup = nil
    end, function()
        rosterAccepted = false
    end)
end)

-- recieve roster finished
Comm:RegisterComm("GRA_R_SEND", function(prefix, message, channel, sender)
    if sender == UnitName("player") then return end
    
    receivedRoster = StringToTable(message)
    rosterReceived = true
    OnRosterReceived()
end)

-- recieve roster progress
Comm:RegisterComm("GRA_R_PROG", function(prefix, message, channel, sender)
    if sender == UnitName("player") then return end
    
    if not rosterAccepted then return end

    local done, total = strsplit("|", message)
    done, total = tonumber(done), tonumber(total)
    if not receiveRosterPopup then
        receiveRosterPopup = GRA:CreateDataTransferPopup(L["Receiving roster data from %s"]:format(GRA:GetClassColoredName(sender, select(2, UnitClass(sender)))), total)
    end
    -- progress bar
    receiveRosterPopup:SetValue(done)
end)

-----------------------------------------
-- send logs
-----------------------------------------
local receiveLogsPopup, sendLogsPopup, logsAccepted, logsReceived, receivedLogs
local dates
local function OnLogsReceived()
    -- TODO: version mismatch warning
    if logsAccepted and logsReceived and receivedLogs then
        for d, tbl in pairs(receivedLogs[1]) do
            _G[GRA_R_RaidLogs][d] = tbl
        end
        -- TODO: send AR only, not all _G[GRA_R_Roster]
        _G[GRA_R_Roster] = receivedLogs[2]
        -- tell addon to show logs
        GRA:FireEvent("GRA_LOGS_DONE", GRA:Getn(receivedLogs[1]), dates)
        wipe(receivedLogs)
    end
end

function GRA:SendLogsToRaid(selectedDates)
    dates = selectedDates
    local encoded = TableToString(selectedDates)
    Comm:SendCommMessage("GRA_LOGS_ASK", encoded, sendChannel, nil, "ALERT")
    sendLogsPopup = nil
    gra.sending = true

    local t = {}
    for _, d in pairs(selectedDates) do
        t[d] = _G[GRA_R_RaidLogs][d]
    end
    -- TODO: send AR only, not all _G[GRA_R_Roster]
    encoded = TableToString({t, _G[GRA_R_Roster]})
    
    -- send logs
    Comm:SendCommMessage("GRA_LOGS_SEND", encoded, sendChannel, nil, "BULK", function(arg, done, total)
        if not sendLogsPopup then
            sendLogsPopup = GRA:CreateDataTransferPopup(gra.colors.chartreuse.s..L["Sending raid logs data"], total, function()
                gra.sending = false
            end)
        end
        sendLogsPopup:SetValue(done)
        -- send progress
        Comm:SendCommMessage("GRA_LOGS_PROG", done.."|"..total, sendChannel, nil, "ALERT")
    end)
end

-- whether to revieve
Comm:RegisterComm("GRA_LOGS_ASK", function(prefix, message, channel, sender)
    if sender == UnitName("player") or GRA_Variables["minimalMode"] then return end

    logsAccepted = false
    logsReceived = false

    dates = StringToTable(message)
    GRA:CreateStaticPopup(L["Receive Raid Logs"], L["Receive raid logs data from %s?"]:format(GRA:GetClassColoredName(sender, select(2, UnitClass(sender)))) .. "\n" ..
    GRA:TableToString(dates), -- TODO: text format
    function()
        logsAccepted = true
        OnLogsReceived()

        -- if receving then hide it immediately
        if receiveLogsPopup then receiveLogsPopup:Hide() end
        -- init
        receiveLogsPopup = nil
    end, function()
        logsAccepted = false
    end)
end)

-- "recieve logs data" finished
Comm:RegisterComm("GRA_LOGS_SEND", function(prefix, message, channel, sender)
    if sender == UnitName("player") then return end

    receivedLogs = StringToTable(message)
    logsReceived = true
    OnLogsReceived()
end)

-- "recieve logs data" progress
Comm:RegisterComm("GRA_LOGS_PROG", function(prefix, message, channel, sender)
    if sender == UnitName("player") then return end

    if not logsAccepted then return end

    local done, total = strsplit("|", message)
    done, total = tonumber(done), tonumber(total)
    if not receiveLogsPopup then
        -- UnitClass(name) is available for raid/party members
        receiveLogsPopup = GRA:CreateDataTransferPopup(L["Receiving raid logs data from %s"]:format(GRA:GetClassColoredName(sender, select(2, UnitClass(sender)))), total)
    end
    -- progress bar
    receiveLogsPopup:SetValue(done)
end)

-----------------------------------------
-- hide data transfer popup when leave group
-----------------------------------------
eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
function eventFrame:GROUP_ROSTER_UPDATE()
    if not IsInGroup("LE_PARTY_CATEGORY_HOME") then
        if receiveRosterPopup then receiveRosterPopup.fadeOut:Play() end
        if receiveLogsPopup then receiveLogsPopup.fadeOut:Play() end
    end
end

-----------------------------------------
-- popup message
-----------------------------------------
function GRA:SendEntryMsg(msgType, name, value, reason)
    if UnitIsConnected(GRA:GetShortName(name)) then
        Comm:SendCommMessage("GRA_MSG", "|cff80FF00" .. msgType .. ":|r " .. value
        .. "  |cff80FF00" .. L["Reason"] .. ":|r " .. reason, "WHISPER", name, "ALERT")
    end
end

Comm:RegisterComm("GRA_MSG", function(prefix, message, channel, sender)
    GRA:CreatePopup(message)
end)
