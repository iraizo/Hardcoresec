local CTL = _G.ChatThrottleLib
local console_buffer = ""

local function ConsolePrint(msg)
    console_buffer = console_buffer .. msg .. "\n"
    HardcoreSR:Print(msg)
end

local COMM_FIELD_DELIM = "~"
local COMM_COMMAND_DELIM = "$"

local checksum_relay = "ggchecksum"
local checksum_relay_pass = "l33tkekw"

local checksum_queue = {}

-- Connect other griefers with the addon to relay their own checksums to channel to broadcast them together
local function joinRelay()
    JoinChannelByName(checksum_relay, checksum_relay_pass)
    local channel_num = GetChannelName(checksum_relay)
    if channel_num == 0 then
        ConsolePrint("Failed to join griefer relay.")
    else
        ConsolePrint("Successfully joined griefer relay.")
    end
end

local function eventHandler(self, event, ...)
    local arg = { ... }
    if event == "CHAT_MSG_CHANNEL" then
        local channel_num = GetChannelName(checksum_relay)
        if channel_num == 0 then
            joinRelay()
        end

        local _, channel_name = string.split(" ", arg[4])
        if channel_name ~= checksum_relay then return end
        local command, msg = string.split(COMM_COMMAND_DELIM, arg[1])

        -- griefer sent checksum
        if command == "2" then
            ConsolePrint("Added griefer checksum to queue: " .. arg[1])
            table.insert(checksum_queue, msg)
        end
    end
end

-- verify fake death from a griefer by sending it to the channel
local function relayGrieferChecksum()
    local channel_num = GetChannelName("hcdeathalertschannel")
    if channel_num == 0 then
    end -- cba

    if #checksum_queue > 0 then
        CTL:SendChatMessage("BULK", "HCDeathAlerts", "2$" .. checksum_queue[1], "CHANNEL", nil, channel_num)
        table.remove(checksum_queue, 1)
        ConsolePrint("Relayed griefer checksum to channel.")
    end
end

-- Note: We can only send at most 1 message per click, otherwise we get a taint
WorldFrame:HookScript("OnMouseDown", function(self, button)
    relayGrieferChecksum()
end)

-- This binds any key press to send, including hitting enter to type or esc to exit game
local f = Test or CreateFrame("Frame", "Test", UIParent)
f:SetScript("OnKeyDown", relayGrieferChecksum)
f:SetPropagateKeyboardInput(true)

local function fletcher16(_player_data)
    local data = _player_data["name"] .. _player_data["guild"] .. _player_data["level"]
    local sum1 = 0
    local sum2 = 0
    for index = 1, #data do
        sum1 = (sum1 + string.byte(string.sub(data, index, index))) % 255;
        sum2 = (sum2 + sum1) % 255;
    end
    return _player_data["name"] .. "-" .. bit.bor(bit.lshift(sum2, 8), sum1)
end

local function encodeMessage(name, guild, source_id, race_id, class_id, level, instance_id, map_id, map_pos)
    if name == nil then return end
    -- if guild == nil then return end -- TODO
    if tonumber(source_id) == nil then return end
    if tonumber(race_id) == nil then return end
    if tonumber(level) == nil then return end

    local loc_str = ""
    if map_pos then
        loc_str = string.format("%.4f,%.4f", map_pos.x, map_pos.y)
    end
    local comm_message = name ..
        COMM_FIELD_DELIM ..
        (guild or "") ..
        COMM_FIELD_DELIM ..
        source_id ..
        COMM_FIELD_DELIM ..
        race_id ..
        COMM_FIELD_DELIM ..
        class_id ..
        COMM_FIELD_DELIM ..
        level ..
        COMM_FIELD_DELIM ..
        (instance_id or "") .. COMM_FIELD_DELIM .. (map_id or "") .. COMM_FIELD_DELIM .. loc_str .. COMM_FIELD_DELIM
    return comm_message
end

local function generateFakePlayerDataChecksum(data)
    return fletcher16(data);
end

local function generateFakePlayerDataMessage(data)
    return encodeMessage(data.name, data.guild, data.source_id, data.race_id, data.class_id, data.level, data
        .instance_id, data.map_id, data.map_pos);
end

local function sendDeathLog(msg)
    local _, _, race_id = UnitRace("player")
    local _, _, class_id = UnitClass("player")
    local guildName, _, _ = GetGuildInfo("player");
    if guildName == nil then guildName = "" end
    if msg == nil then msg = "" end

    local data = {
        ["name"]       = UnitName("player"),
        ["guild"]      = guildName,
        ["level"]      = UnitLevel("player"),
        ["map_id"]     = 2717,
        ["source_id"]  = 11502,
        ["race_id"]    = race_id,
        ["class_id"]   = class_id,
        ["map_pos"]    = {
            ["x"] = 0.1337,
            ["y"] = 0.1337
        },
        ["date"]       = "2023-05-08 13:02:00",
        ["last_words"] = msg,
    };

    -- BROADCAST_DEATH_PING_CHECKSUM
    --[=====[
    local commMessage = "2" .. COMM_COMMAND_DELIM .. generateFakePlayerDataChecksum(data)
    local channel_num = GetChannelName("hcdeathalertschannel")
    CTL:SendChatMessage("BULK", "HCDeathAlerts", commMessage, "CHANNEL", nil, channel_num)
    --]=====]
    -- BROADCAST_DEATH_PING
    local commMessage = "1" .. COMM_COMMAND_DELIM .. generateFakePlayerDataMessage(data)
    local channel_num = GetChannelName("hcdeathalertschannel")
    CTL:SendChatMessage("BULK", "HCDeathAlerts", commMessage, "CHANNEL", nil, channel_num)
    ConsolePrint("Sent death ping to channel " .. channel_num)

    -- LAST_WORDS
    if msg ~= nil then
        local encoded = generateFakePlayerDataChecksum(data) .. COMM_FIELD_DELIM .. msg .. COMM_FIELD_DELIM
        commMessage = "3" .. COMM_COMMAND_DELIM .. encoded
        CTL:SendChatMessage("BULK", "HCDeathAlerts", commMessage, "CHANNEL", nil, channel_num)
        ConsolePrint("Sent last words to channel " .. channel_num)
    end

    -- BROADCAST_DEATH_PING_CHECKSUM
    commMessage = "2" .. COMM_COMMAND_DELIM .. generateFakePlayerDataChecksum(data)
    channel_num = GetChannelName(checksum_relay)
    CTL:SendChatMessage("BULK", checksum_relay, commMessage, "CHANNEL", nil, channel_num)
end

HardcoreSR = LibStub("AceAddon-3.0"):NewAddon("HardcoreSR", "AceConsole-3.0")
local AceGUI = LibStub("AceGUI-3.0")
function HardcoreSR:OnInitialize()
    --HardcoreSR:CreateUI()

    --hooksecurefunc(Hardcore, "GenerateVerificationString", MyHookedFunction)
    joinRelay()

    local griefer_relay_handler = CreateFrame("Frame")
    griefer_relay_handler:RegisterEvent("CHAT_MSG_CHANNEL")
    griefer_relay_handler:SetScript("OnEvent", eventHandler)

    SLASH_HCSR1 = "/hcsr"
    SlashCmdList["HCSR"] = function(msg)
        HardcoreSR:CreateUI()
    end
end

local function DrawTab1(container)
    local messageInput = AceGUI:Create("EditBox")
    messageInput:SetLabel("Enter last message:")
    messageInput:SetWidth(200)
    messageInput:SetRelativeWidth(0.6)
    local sendButton = AceGUI:Create("Button")
    sendButton:SetText("Send")
    sendButton:SetRelativeWidth(0.4)
    sendButton:SetCallback("OnClick", function() sendDeathLog(messageInput:GetText()) end)

    container:AddChild(messageInput)
    container:AddChild(sendButton)
end

local function DrawTab2(container)
    local desc = AceGUI:Create("Label")
    desc:SetText("TODO")

    container:AddChild(desc)
end

local function DrawTab3(container)
    local console = AceGUI:Create("MultiLineEditBox")
    console:SetText(console_buffer)
    console:SetLabel("Debug Console")
    console:SetMaxLetters(0)
    console:SetFullWidth(true)
    console:SetFullHeight(true)
    console:DisableButton(true)
    container:AddChild(console)
end

local function SelectGroup(container, event, group)
    container:ReleaseChildren()
    container:SetFullHeight(true)
    if group == "tab1" then
        DrawTab1(container)
    elseif group == "tab2" then
        DrawTab2(container)
    elseif group == "tab3" then
        DrawTab3(container)
    end
end

function HardcoreSR:CreateUI()
    -- Create the main frame
    local frame = AceGUI:Create("Frame")
    frame:SetTitle("Hardcore Security Research")
    frame:SetWidth(400)
    frame:SetHeight(300)
    frame:SetLayout("Flow")

    local tab = AceGUI:Create("TabGroup")
    tab:SetLayout("Flow")
    tab:SetTabs({ { text = "Fake death", value = "tab1" }, { text = "Fake verification", value = "tab2" },
        { text = "Debugging",  value = "tab3" } })
    tab:SetFullWidth(true)
    tab:SetCallback("OnGroupSelected", SelectGroup)
    tab:SelectTab("tab1")
    frame:AddChild(tab)
end
