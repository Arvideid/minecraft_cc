-- comm_hub.lua
-- ComputerCraft Communication Hub with Terminal Interface

-- Load the modem control module
local modem = require("modem_control")

-- Color settings
local COLORS = {
    TEXT = colors.white,
    TITLE = colors.yellow,
    CONNECTED = colors.lime,
    DISCONNECTED = colors.red,
    MESSAGE_IN = colors.lightGray,
    MESSAGE_OUT = colors.cyan,
    SYSTEM = colors.lightBlue,
    ERROR = colors.red,
    SCROLL_MARKER = colors.gray,
}

-- App state
local app = {
    running = true,
    devices = {},
    selected = nil,
    history = {},  -- Command history
    historyPos = 0,
    messageLog = {},  -- Log of all messages for display
    scrollPos = 0,    -- Scroll position (0 = most recent)
    termHeight = 0,   -- Terminal height (updated on init)
    isScrolling = false, -- Whether we're in scrollback mode
}

-- Forward declarations
local redrawTerminal, logMessage, resetScroll

-- Device management
local function addDevice(id, name, deviceType)
    if not app.devices[id] then
        app.devices[id] = {
            id = id,
            name = name or "Device-" .. id,
            type = deviceType or "unknown",
            lastSeen = os.time(),
            connected = true,
            messages = {}
        }
        
        -- Log new device connection
        logMessage("Device connected: " .. name .. " (ID: " .. id .. ")", "system")
        
        -- Auto-select if we have no selection
        if not app.selected then
            app.selected = id
            logMessage("Auto-selected device: " .. name, "system")
        end
    else
        -- Update existing device
        app.devices[id].lastSeen = os.time()
        app.devices[id].connected = true
        if name then app.devices[id].name = name end
        if deviceType then app.devices[id].type = deviceType end
    end
end

local function checkDeviceTimeouts()
    for id, device in pairs(app.devices) do
        if device.connected and os.time() - device.lastSeen > modem.config.TIMEOUT then
            device.connected = false
            logMessage("Device disconnected: " .. device.name .. " (timeout)", "system")
        end
    end
end

-- Send a message and update history
local function sendMessageToDevice(deviceId, messageText)
    if not deviceId or not app.devices[deviceId] then
        logMessage("Error: No device selected or invalid device", "error")
        return false
    end
    
    local success = modem.sendMessage(deviceId, messageText)
    
    if success then
        -- Add to message history
        if not app.devices[deviceId].messages then
            app.devices[deviceId].messages = {}
        end
        
        table.insert(app.devices[deviceId].messages, {
            content = messageText,
            sender = "me",
            timestamp = os.time()
        })
        
        -- Log to terminal
        logMessage("To " .. app.devices[deviceId].name .. ": " .. messageText, "outgoing")
        
        return true
    else
        logMessage("Failed to send message to " .. app.devices[deviceId].name, "error")
    end
    
    return false
end

-- Process messages from other devices
local function processMessage(senderId, message)
    -- Debug logging
    logMessage("RECEIVED MESSAGE from ID " .. senderId .. " of type: " .. (message.type or "unknown"), "system")
    
    if not message or not message.type then return end
    
    if message.type == "discovery_ping" then
        -- Respond to discovery
        logMessage("Received discovery ping from ID " .. senderId, "system")
        modem.respondToDiscovery(senderId)
        -- Add device to list
        addDevice(senderId, message.name, message.device_type)
    elseif message.type == "discovery_response" then
        -- Add responding device
        logMessage("Received discovery response from ID " .. senderId, "system")
        addDevice(senderId, message.name, message.device_type)
    elseif message.type == "message" then
        -- Add to conversation
        addDevice(senderId)
        
        if not app.devices[senderId].messages then
            app.devices[senderId].messages = {}
        end
        
        table.insert(app.devices[senderId].messages, {
            content = message.content,
            sender = "them",
            timestamp = os.time()
        })
        
        -- Log incoming message
        logMessage("From " .. app.devices[senderId].name .. ": " .. message.content, "incoming")
        
        -- Auto-respond to pings
        if message.content == "/ping" then
            sendMessageToDevice(senderId, "/ping_response")
        end
    elseif message.type == "command_result" then
        -- Handle command result from turtle
        if not app.devices[senderId] then
            addDevice(senderId)
        end
        
        local result = message.content
        if type(result) == "string" then
            -- Try to deserialize if it's a string
            pcall(function()
                result = textutils.unserialize(result)
            end)
        end
        
        if type(result) == "table" then
            local resultMsg = "Command result from " .. app.devices[senderId].name .. ": "
            if result.success then
                resultMsg = resultMsg .. "SUCCESS"
            else
                resultMsg = resultMsg .. "FAILED"
            end
            
            if result.result ~= nil then
                resultMsg = resultMsg .. " - Result: " .. tostring(result.result)
            end
            
            if result.error then
                resultMsg = resultMsg .. " - Error: " .. result.error
            end
            
            logMessage(resultMsg, "system")
        else
            logMessage("Command result from " .. app.devices[senderId].name .. ": " .. tostring(result), "system")
        end
    end
end

-- Terminal display functions
local function drawScrollIndicator()
    if #app.messageLog <= app.termHeight - 2 then return end
    
    -- Only show indicator if we have enough messages to scroll
    local maxScroll = math.max(0, #app.messageLog - (app.termHeight - 2))
    
    if app.scrollPos > 0 then
        local w, h = term.getSize()
        term.setCursorPos(w, 1)
        term.setTextColor(COLORS.SCROLL_MARKER)
        term.write("↑")
        
        if app.scrollPos < maxScroll then
            term.setCursorPos(w, h - 1)
            term.write("↓")
        end
    end
end

-- Redraw the terminal with current scroll position
function redrawTerminal()
    -- Save cursor position
    local oldX, oldY = term.getCursorPos()
    
    -- Clear the terminal
    term.clear()
    term.setCursorPos(1, 1)
    
    -- Calculate visible range from the log
    local startIndex = math.max(1, #app.messageLog - (app.termHeight - 3) + 1 - app.scrollPos)
    local endIndex = math.min(#app.messageLog, startIndex + app.termHeight - 3)
    
    -- Display visible messages
    for i = startIndex, endIndex do
        local msg = app.messageLog[i]
        term.setTextColor(msg.color)
        print("[" .. msg.timestamp .. "] " .. msg.text)
    end
    
    -- Draw scroll indicators if needed
    drawScrollIndicator()
    
    -- Draw input prompt
    term.setCursorPos(1, app.termHeight - 1)
    term.setTextColor(COLORS.TEXT)
    
    -- Show scrollback mode indicator
    if app.isScrolling then
        term.setTextColor(COLORS.SCROLL_MARKER)
        print("-- SCROLLBACK MODE: Press ESC to exit, PageUp/PageDown to scroll --")
        term.setTextColor(COLORS.TEXT)
    end
    
    -- Restore cursor position for input
    term.setCursorPos(oldX, oldY)
end

-- Scroll the terminal display
local function scrollTerminal(amount)
    local maxScroll = math.max(0, #app.messageLog - (app.termHeight - 3))
    app.scrollPos = math.max(0, math.min(maxScroll, app.scrollPos + amount))
    redrawTerminal()
    
    -- Enter scrolling mode if we're not at the bottom
    if app.scrollPos > 0 then
        app.isScrolling = true
    else
        app.isScrolling = false
    end
    
    return true
end

-- Reset scroll position to bottom (most recent messages)
function resetScroll()
    if app.scrollPos > 0 then
        app.scrollPos = 0
        app.isScrolling = false
        redrawTerminal()
    end
end

-- Logging
function logMessage(message, messageType)
    -- Get current time
    local timestamp = textutils.formatTime(os.time(), true)
    
    -- Choose color based on message type
    local color = COLORS.TEXT
    if messageType == "system" then
        color = COLORS.SYSTEM
    elseif messageType == "error" then
        color = COLORS.ERROR
    elseif messageType == "incoming" then
        color = COLORS.MESSAGE_IN
    elseif messageType == "outgoing" then
        color = COLORS.MESSAGE_OUT
    elseif messageType == "title" then
        color = COLORS.TITLE
    end
    
    -- Store in log
    table.insert(app.messageLog, {
        text = message,
        timestamp = timestamp,
        type = messageType,
        color = color
    })
    
    -- Keep log size reasonable
    if #app.messageLog > 500 then
        table.remove(app.messageLog, 1)
    end
    
    -- If not in scrollback mode, auto-scroll to bottom and display
    if not app.isScrolling then
        -- Update the display with the new message
        redrawTerminal()
    end
end

-- List all connected devices
local function listDevices()
    local deviceCount = 0
    local connectedCount = 0
    local sorted = {}
    
    -- Get sorted list of devices
    for _, device in pairs(app.devices) do
        table.insert(sorted, device)
        deviceCount = deviceCount + 1
        if device.connected then
            connectedCount = connectedCount + 1
        end
    end
    
    table.sort(sorted, function(a, b)
        if a.connected ~= b.connected then
            return a.connected
        end
        return a.name < b.name
    end)
    
    -- Log to message history instead of directly printing
    logMessage("=== Connected Devices (" .. connectedCount .. "/" .. deviceCount .. ") ===", "system")
    
    -- Print each device
    for i, device in ipairs(sorted) do
        local prefix = "  "
        if app.selected == device.id then
            prefix = "> " -- Show which device is selected
        end
        
        local status = device.connected and "CONNECTED" or "DISCONNECTED"
        local deviceType = device.type and (" - Type: " .. device.type) or ""
        
        if device.connected then
            logMessage(prefix .. device.name .. " (ID: " .. device.id .. ") - " .. status .. deviceType, "system")
        else
            logMessage(prefix .. device.name .. " (ID: " .. device.id .. ") - " .. status .. deviceType, "error")
        end
    end
end

-- Show help information
local function showHelp()
    local helpMessages = {
        "=== ComNet Hub Command Help ===",
        "Commands:",
        "  /list             - List all connected devices",
        "  /select [id]      - Select a device by ID",
        "  /send [id] [msg]  - Send message to specific device",
        "  /scan             - Scan for devices",
        "  /name [id] [name] - Rename a device",
        "  /clear            - Clear message history",
        "  /status           - Show connection status",
        "  /help             - Show this help",
        "  /exit             - Exit application",
        "",
        "Scrolling:",
        "  PageUp/PageDown   - Scroll through message history",
        "  Home/End          - Jump to start/end of message history",
        "  ESC               - Exit scrollback mode and return to bottom",
        "",
        "Sending Messages:",
        "  - Type a message and press Enter to send to selected device",
        "  - Start message with ! to send a command to a turtle (e.g. !forward)",
        "  - Use /ping to check if a device is responding"
    }
    
    -- Log each help line
    for _, msg in ipairs(helpMessages) do
        logMessage(msg, "system")
    end
end

-- Process a command
local function processCommand(input)
    -- Reset scroll position when user enters a command
    resetScroll()
    
    if input:sub(1, 1) ~= "/" then
        -- Not a command, send as message to selected device
        if app.selected then
            sendMessageToDevice(app.selected, input)
        else
            logMessage("No device selected. Select a device first with /select [id]", "error")
        end
        return
    end
    
    -- Parse command
    local cmd = input:match("^/(%w+)")
    local args = {}
    for arg in input:gmatch("%S+") do
        if arg ~= "/" .. cmd then
            table.insert(args, arg)
        end
    end
    
    -- Process command
    if cmd == "list" then
        listDevices()
    elseif cmd == "select" then
        if args[1] and tonumber(args[1]) then
            local id = tonumber(args[1])
            if app.devices[id] then
                app.selected = id
                logMessage("Selected device: " .. app.devices[id].name, "system")
            else
                logMessage("No device with ID " .. id .. " found", "error")
            end
        else
            logMessage("Usage: /select [device_id]", "error")
        end
    elseif cmd == "send" then
        if args[1] and tonumber(args[1]) then
            local id = tonumber(args[1])
            if app.devices[id] then
                local msg = table.concat(args, " ", 2)
                if msg and #msg > 0 then
                    sendMessageToDevice(id, msg)
                else
                    logMessage("Usage: /send [device_id] [message]", "error")
                end
            else
                logMessage("No device with ID " .. id .. " found", "error")
            end
        else
            logMessage("Usage: /send [device_id] [message]", "error")
        end
    elseif cmd == "scan" or cmd == "refresh" then
        logMessage("Scanning for devices...", "system")
        modem.broadcastDiscovery()
    elseif cmd == "name" then
        if args[1] and tonumber(args[1]) and args[2] then
            local id = tonumber(args[1])
            local newName = table.concat(args, " ", 2)
            if app.devices[id] then
                local oldName = app.devices[id].name
                app.devices[id].name = newName
                logMessage("Renamed device " .. oldName .. " to " .. newName, "system")
            else
                logMessage("No device with ID " .. id .. " found", "error")
            end
        else
            logMessage("Usage: /name [device_id] [new_name]", "error")
        end
    elseif cmd == "clear" then
        -- Clear message log
        app.messageLog = {}
        app.scrollPos = 0
        app.isScrolling = false
        redrawTerminal()
        logMessage("Message history cleared", "system")
    elseif cmd == "status" then
        local deviceCount = 0
        local connectedCount = 0
        for _, device in pairs(app.devices) do
            deviceCount = deviceCount + 1
            if device.connected then
                connectedCount = connectedCount + 1
            end
        end
        
        local selectedName = app.selected and app.devices[app.selected] and app.devices[app.selected].name or "None"
        
        logMessage("Status: " .. connectedCount .. "/" .. deviceCount .. " devices connected", "system")
        logMessage("Selected device: " .. selectedName, "system")
        logMessage("Hub ID: " .. modem.deviceID, "system")
    elseif cmd == "help" then
        showHelp()
    elseif cmd == "exit" or cmd == "quit" then
        app.running = false
    elseif cmd == "ping" then
        if app.selected then
            sendMessageToDevice(app.selected, "/ping")
            logMessage("Ping sent to " .. app.devices[app.selected].name, "system")
        else
            logMessage("No device selected. Select a device first with /select [id]", "error")
        end
    else
        logMessage("Unknown command: " .. cmd, "error")
        logMessage("Type /help for a list of commands", "system")
    end
end

-- Handle keyboard events during scrollback mode
local function handleScrollKeys()
    local event, key = os.pullEvent("key")
    
    if key == keys.pageUp then
        -- Scroll up one page
        scrollTerminal(app.termHeight - 4)
        return true
    elseif key == keys.pageDown then
        -- Scroll down one page
        scrollTerminal(-(app.termHeight - 4))
        return true
    elseif key == keys.home then
        -- Scroll to top
        local maxScroll = math.max(0, #app.messageLog - (app.termHeight - 3))
        scrollTerminal(maxScroll)
        return true
    elseif key == keys.up then
        -- Scroll up one line
        scrollTerminal(1)
        return true
    elseif key == keys.down then
        -- Scroll down one line
        scrollTerminal(-1)
        return true
    elseif key == keys["end"] then
        -- Scroll to bottom (most recent)
        resetScroll()
        return true
    elseif key == keys.escape then
        -- Exit scrollback mode
        resetScroll()
        return false
    end
    
    return true
end

-- Initialize app
local function initialize()
    -- Initialize modem first
    if not modem.init() then
        error("Failed to initialize modem")
    end
    
    -- Get terminal dimensions
    local w, h = term.getSize()
    app.termHeight = h
    
    -- Send initial discovery ping
    modem.broadcastDiscovery()
    
    -- Clear terminal and show welcome message
    term.clear()
    term.setCursorPos(1, 1)
    
    -- Add welcome messages to log
    logMessage("========================================", "title")
    logMessage("         ComNet Hub Terminal v1.1       ", "title")
    logMessage("========================================", "title")
    logMessage("Hub ID: " .. modem.deviceID, "system")
    logMessage("Type /help for a list of commands", "system")
    logMessage("Use PageUp/PageDown to scroll message history", "system")
    logMessage("Scanning for devices...", "system")
    
    return true
end

-- Read user input (with history support)
local function readInput()
    term.setCursorPos(1, app.termHeight - 1)
    term.setTextColor(COLORS.TEXT)
    write("> ")
    
    -- Create a custom event loop to handle scroll keys during input
    local input = ""
    local pos = 1
    local historyPos = #app.history + 1
    local w, h = term.getSize()
    
    -- Draw the cursor
    term.setCursorPos(1 + pos, app.termHeight - 1)
    term.setCursorBlink(true)
    
    while true do
        local event, param1, param2, param3 = os.pullEvent()
        
        if event == "key" then
            if param1 == keys.enter then
                -- Submit input
                term.setCursorBlink(false)
                print() -- Move to next line
                break
                
            elseif param1 == keys.backspace then
                -- Delete character
                if pos > 1 then
                    input = input:sub(1, pos - 2) .. input:sub(pos)
                    pos = pos - 1
                    term.setCursorPos(1, app.termHeight - 1)
                    term.write("> " .. input .. " ") -- Clear any trailing character
                    term.setCursorPos(1 + pos, app.termHeight - 1)
                end
                
            elseif param1 == keys.left then
                -- Move cursor left
                if pos > 1 then
                    pos = pos - 1
                    term.setCursorPos(1 + pos, app.termHeight - 1)
                end
                
            elseif param1 == keys.right then
                -- Move cursor right
                if pos <= #input then
                    pos = pos + 1
                    term.setCursorPos(1 + pos, app.termHeight - 1)
                end
                
            elseif param1 == keys.up then
                -- Previous command in history
                if historyPos > 1 then
                    historyPos = historyPos - 1
                    input = app.history[historyPos]
                    pos = #input + 1
                    term.setCursorPos(1, app.termHeight - 1)
                    term.write("> " .. input .. string.rep(" ", w - #input - 2))
                    term.setCursorPos(1 + pos, app.termHeight - 1)
                end
                
            elseif param1 == keys.down then
                -- Next command in history
                if historyPos < #app.history then
                    historyPos = historyPos + 1
                    input = app.history[historyPos]
                else
                    historyPos = #app.history + 1
                    input = ""
                end
                pos = #input + 1
                term.setCursorPos(1, app.termHeight - 1)
                term.write("> " .. input .. string.rep(" ", w - #input - 2))
                term.setCursorPos(1 + pos, app.termHeight - 1)
                
            elseif param1 == keys.home then
                -- Move to start of input
                pos = 1
                term.setCursorPos(1 + pos, app.termHeight - 1)
                
            elseif param1 == keys.pageUp then
                -- Enter scrollback mode if we have content
                if #app.messageLog > app.termHeight - 3 then
                    term.setCursorBlink(false)
                    app.isScrolling = true
                    scrollTerminal(app.termHeight - 4)
                    
                    -- Handle scroll mode
                    while app.isScrolling do
                        if not handleScrollKeys() then break end
                    end
                    
                    -- Restore input prompt
                    term.setCursorPos(1, app.termHeight - 1)
                    term.write("> " .. input)
                    term.setCursorPos(1 + pos, app.termHeight - 1)
                    term.setCursorBlink(true)
                end
                
            elseif param1 == keys["end"] then
                -- Move to end of input
                pos = #input + 1
                term.setCursorPos(1 + pos, app.termHeight - 1)
            end
            
        elseif event == "char" then
            -- Add character to input
            input = input:sub(1, pos - 1) .. param1 .. input:sub(pos)
            pos = pos + 1
            term.setCursorPos(1, app.termHeight - 1)
            term.write("> " .. input)
            term.setCursorPos(1 + pos, app.termHeight - 1)
            
        elseif event == "term_resize" then
            -- Terminal was resized
            w, h = term.getSize()
            app.termHeight = h
            redrawTerminal()
            
            -- Redraw input
            term.setCursorPos(1, app.termHeight - 1)
            term.write("> " .. input)
            term.setCursorPos(1 + pos, app.termHeight - 1)
        end
    end
    
    -- Add to history if not empty and not a duplicate of the last command
    if input ~= "" and (app.historyPos == 0 or input ~= app.history[app.historyPos]) then
        table.insert(app.history, input)
        if #app.history > 50 then
            table.remove(app.history, 1)
        end
        app.historyPos = #app.history
    end
    
    return input
end

-- Main event loop
local function mainLoop()
    -- Create a parallel execution environment
    parallel.waitForAny(
        -- UI and input handling
        function()
            while app.running do
                local input = readInput()
                if input and #input > 0 then
                    processCommand(input)
                end
            end
        end,
        
        -- Network and background tasks
        function()
            while app.running do
                -- Check for device timeouts
                checkDeviceTimeouts()
                
                -- Send periodic discovery pings
                if os.time() - modem.lastPingTime > 30 then
                    logMessage("Broadcasting discovery ping...", "system")
                    modem.broadcastDiscovery()
                end
                
                -- Process incoming messages
                local senderId, message = rednet.receive(modem.config.PROTOCOL, 1)
                if senderId and message then
                    processMessage(senderId, message)
                end
            end
        end
    )
end

-- Main application entry point
local function main()
    if not initialize() then
        print("Failed to initialize the application. Exiting.")
        return
    end
    
    -- Run the main event loop
    mainLoop()
    
    -- Cleanup
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
    term.clear()
    term.setCursorPos(1,1)
    print("ComNet Hub terminated.")
    
    -- Close modem connections
    modem.close()
end

-- Start the application
main() 