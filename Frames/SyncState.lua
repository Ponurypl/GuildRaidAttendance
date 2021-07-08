local GRA, gra, SYNC = unpack(select(2, ...))
local L = select(2, ...).L
local ownerData;

----------------------------------------------------------------------------------
-- sync state
----------------------------------------------------------------------------------
local syncStateFrame = GRA:CreateFrame(L["Sync"], "GRA_SyncStateFrame", gra.mainFrame, 190, gra.mainFrame:GetHeight())
gra.syncStateFrame = syncStateFrame
syncStateFrame:SetPoint("TOPLEFT", gra.mainFrame, "TOPRIGHT", 2, 0)
syncStateFrame.header.closeBtn:SetText("←")
local fontName = GRA_FONT_BUTTON:GetFont()
syncStateFrame.header.closeBtn:GetFontString():SetFont(fontName, 11)
syncStateFrame.header.closeBtn:SetScript("OnClick", function() syncStateFrame:Hide() gra.configFrame:Show() end)

local tip = CreateFrame("Frame", nil, syncStateFrame)
tip:SetSize(syncStateFrame:GetWidth()-10, 15)
tip:SetPoint("TOP", 0, -4)
tip:SetScript("OnEnter", function()
    GRA_Tooltip:SetOwner(tip, "ANCHOR_RIGHT", 12, -45);
    GRA_Tooltip:AddLine(GRA:GetClassColoredName(UnitName("player"), select(2, UnitClass("player"))));
    GRA_Tooltip:AddDoubleLine("|cffa3a3a3Addon version:|r", "|cffa3a3a3"..strsub(ownerData.addon, 1, 8).."|r");
    GRA_Tooltip:AddDoubleLine("|cffa3a3a3Roster rev:|r", "|cffa3a3a3"..strsub(ownerData.rosterVersion, 1, 8).."|r");
    GRA_Tooltip:AddDoubleLine("|cffa3a3a3Raidlog rev:|r", "|cffa3a3a3"..strsub(ownerData.raidVersion, 1, 8).."|r");
    GRA_Tooltip:Show()
end)
tip:SetScript("OnLeave", function() GRA_Tooltip:Hide() end)


local rosterText = tip:CreateFontString(nil, "OVERLAY", "GRA_FONT_SMALL")
rosterText:SetText(gra.colors.chartreuse.s .. L["Hover for more information."])
rosterText:SetPoint("LEFT")

local scroll = GRA:CreateScrollFrame(syncStateFrame, -25, 10)
local LoadRoster

--------------------------------------------------
-- grid
--------------------------------------------------
local mains, availableMains = {}, {}
local function CreatePlayerGrid(name)
    local data = SYNC:GetData(GRA:GetShortName(name));
    local g = CreateFrame("Frame", nil, syncStateFrame.scrollFrame.content, "BackdropTemplate")
    GRA:StylizeFrame(g)
    g:SetSize(syncStateFrame:GetWidth()-15, 20)
    
    local s = g:CreateFontString(nil, "OVERLAY", "GRA_FONT_TEXT")
    g.s = s
    if _G[GRA_R_Roster][name]["altOf"] then
        s:SetText(GRA:GetClassColoredName(name) .. gra.colors.grey.s .. " (" .. L["alt"] .. ")")
    else
        s:SetText(GRA:GetClassColoredName(name))
    end
    s:SetWordWrap(false)
    s:SetJustifyH("LEFT")
    s:SetPoint("LEFT", 5, 0)
    s:SetPoint("RIGHT", -25, 0)

    local addonVersion, rosterVersion, raidVersion = "", "", "";
    if data ~= nil then
        if data.addon ~= nil then
            addonVersion = data.addon;
        end
        if data.rosterVersion ~= nil then
            rosterVersion = data.rosterVersion;
        end
        if data.raidVersion ~= nil then
            raidVersion = data.raidVersion;
        end

        if addonVersion == ownerData.addon then
            addonVersion = "|cffa3a3a3"..addonVersion.."|r"
        else
            addonVersion = "|cffdb1a1a"..addonVersion.."|r"
        end

        if rosterVersion == ownerData.rosterVersion then
            rosterVersion = "|cff3adb1a"..strsub(data.rosterVersion,1,8).."|r"
        else
            rosterVersion = "|cffdb1a1a"..strsub(data.rosterVersion,1,8).."|r"
        end

        if raidVersion == ownerData.raidVersion then
            raidVersion = "|cff3adb1a"..strsub(data.raidVersion,1,8).."|r"
        else
            raidVersion = "|cffdb1a1a"..strsub(data.raidVersion,1,8).."|r"
        end

        g:SetScript("OnEnter", function()
            GRA_Tooltip:SetOwner(g, "ANCHOR_RIGHT", 12, -45);
            GRA_Tooltip:AddLine(GRA:GetClassColoredName(name));
            GRA_Tooltip:AddDoubleLine("|cffa3a3a3Addon version:|r", addonVersion);
            GRA_Tooltip:AddDoubleLine("|cffa3a3a3Roster rev:|r", rosterVersion);
            GRA_Tooltip:AddDoubleLine("|cffa3a3a3Raidlog rev:|r", raidVersion);
            GRA_Tooltip:Show()
        end)
        g:SetScript("OnLeave", function() GRA_Tooltip:Hide() end)
    end
    
    local av = g:CreateFontString(nil, "OVERLAY", "GRA_FONT_TEXT");
    g.av = av;
    av:SetText(addonVersion);
    av:SetWordWrap(false);
    av:SetJustifyH("RIGHT");
    av:SetPoint("RIGHT", -10, 0);

    return g
end

LoadRoster = function()
    scroll:Reset()
    wipe(mains)
    ownerData = SYNC:GetData(UnitName("player"));

    -- sort
    local sorted = {}
    for name, t in pairs(_G[GRA_R_Roster]) do
        if GRA:GetShortName(name) ~= UnitName("player") then
            table.insert(sorted, {name, t["class"]})            
        end        
    end

    for _, playerName in ipairs(SYNC:GetAllNames()) do
        local found = false;
        for name, _ in pairs(_G[GRA_R_Roster]) do
            if GRA:GetShortName(name) == playerName then
                found = true;
            end
        end
        
        if not found then
            table.insert(sorted, {playerName}) 
        end        
    end

    table.sort(sorted, function(a, b)
        return a[1] < b[1]		
	end)

    local last
    for k, t in pairs(sorted) do
        local g = CreatePlayerGrid(t[1])
        -- scroll:SetWidgetAutoWidth(g)

        -- init mains in context menu
        table.insert(mains, {
            ["text"] = GRA:GetClassColoredName(t[1]),
            ["name"] = t[1],
            -- ["onClick"] = function(text)
            -- end
        })

        if last then
            g:SetPoint("TOP", last, "BOTTOM", 0, -5)
        else
            g:SetPoint("TOPLEFT", 5, 0)
        end
        last = g
    end
end

syncStateFrame:SetScript("OnShow", function()    
    LoadRoster()
end)