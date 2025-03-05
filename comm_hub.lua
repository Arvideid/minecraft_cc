-- comm_hub.lua
-- ComputerCraft Communication Hub with Terminal Interface

-- Load the modem control module
local modem = require("modem_control")
-- Load the scroll window module
local scrollWindow = require("scroll_window")

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
    window = nil,    -- Scroll window instance
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
    if not message or not message.type then return end
    
    if message.type == "discovery_ping" then
        -- Respond to discovery
        modem.respondToDiscovery(senderId)
        -- Add device to list
        addDevice(senderId, message.name, message.device_type)
    elseif message.type == "discovery_response" then
        -- Add responding device
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
    elseif message.type == "ping" then
        -- Handle explicit ping type (fixing the ping issue)
        if not app.devices[senderId] then
            addDevice(senderId)
        end
        app.devices[senderId].lastSeen = os.time()
        -- Send ping response
        modem.sendMessage(senderId, "pong", "ping_response")
        logMessage("Ping received from " .. app.devices[senderId].name, "system")
    elseif message.type == "ping_response" then
        -- Handle ping response
        if not app.devices[senderId] then
            addDevice(senderId)
        end
        app.devices[senderId].lastSeen = os.time()
        logMessage("Ping response from " .. app.devices[senderId].name, "system")
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

-- Terminal display functions using the scroll window
function redrawTerminal()
    app.window.clear()
    
    -- Draw title
    app.window.setCursorPos(1, 1)
    app.window.setTextColour(COLORS.TITLE)
    app.window.write("ComNet Hub Terminal v1.2 - Connected to " .. #app.devices .. " devices")
    
    -- Draw status line
    local selectedName = app.selected and app.devices[app.selected] and app.devices[app.selected].name or "None"
    app.window.setCursorPos(1, 2)
    app.window.setTextColour(COLORS.SYSTEM)
    app.window.write("Selected: " .. selectedName .. " | Type /help for commands")
    
    -- Draw separator
    app.window.setCursorPos(1, 3)
    app.window.setTextColour(COLORS.SCROLL_MARKER)
    local w, _ = term.getSize()
    app.window.write(string.rep("-", w))
    
    -- Reset cursor for input
    app.window.setCursorPos(1, 4)
    app.window.setTextColour(COLORS.TEXT)
    
    -- Draw the window to screen
    app.window.draw()
    
    -- Draw input prompt on bottom line
    local _, h = term.getSize()
    term.setCursorPos(1, h)
    term.setTextColour(COLORS.TEXT)
    write("> ")
end

-- Log a message to the scroll window
function logMessage(message, messageType)
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
    
    -- Format timestamp
    local timestamp = textutils.formatTime(os.time(), true)
    local formattedMessage = "[" .. timestamp .. "] " .. message
    
    -- Store in message log for history
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
    
    -- Write to scroll window
    app.window.setTextColour(color)
    app.window.setCursorPos(1, app.window.getCursorPos())
    app.window.write(formattedMessage)
    app.window.write("\n")
    
    -- Draw the window
    app.window.draw()
    
    -- Draw input prompt on bottom line
    local _, h = term.getSize()
    term.setCursorPos(1, h)
    term.setTextColour(COLORS.TEXT)
    write("> ")
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
    
    -- Log to message history
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
        "  Up/Down           - Scroll line by line in scrollback mode",
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
        -- Clear message log and reset scroll window
        app.messageLog = {}
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
            -- Send direct ping message instead of text message (fixing the ping issue)
            modem.sendMessage(app.selected, "ping", "ping")
            logMessage("Ping sent to " .. app.devices[app.selected].name, "system")
        else
            logMessage("No device selected. Select a device first with /select [id]", "error")
        end
    else
        logMessage("Unknown command: " .. cmd, "error")
        logMessage("Type /help for a list of commands", "system")
    end
end

-- Read user input (with history support)
local function readInput()
    local w, h = term.getSize()
    term.setCursorPos(1, h)
    term.setTextColor(COLORS.TEXT)
    write("> ")
    
    -- Create a custom event loop to handle scroll keys during input
    local input = ""
    local pos = 1
    local historyPos = #app.history + 1
    
    -- Draw the cursor
    term.setCursorPos(1 + pos, h)
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
                    term.setCursorPos(1, h)
                    term.write("> " .. input .. " ") -- Clear any trailing character
                    term.setCursorPos(1 + pos, h)
                end
                
            elseif param1 == keys.left then
                -- Move cursor left
                if pos > 1 then
                    pos = pos - 1
                    term.setCursorPos(1 + pos, h)
                end
                
            elseif param1 == keys.right then
                -- Move cursor right
                if pos <= #input then
                    pos = pos + 1
                    term.setCursorPos(1 + pos, h)
                end
                
            elseif param1 == keys.up then
                -- Previous command in history
                if historyPos > 1 then
                    historyPos = historyPos - 1
                    input = app.history[historyPos]
                    pos = #input + 1
                    term.setCursorPos(1, h)
                    term.write("> " .. input .. string.rep(" ", w - #input - 2))
                    term.setCursorPos(1 + pos, h)
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
                term.setCursorPos(1, h)
                term.write("> " .. input .. string.rep(" ", w - #input - 2))
                term.setCursorPos(1 + pos, h)
                
            elseif param1 == keys.home then
                -- Move to start of input
                pos = 1
                term.setCursorPos(1 + pos, h)
                
            elseif param1 == keys["end"] then
                -- Move to end of input
                pos = #input + 1
                term.setCursorPos(1 + pos, h)
                
            elseif param1 == keys.pageUp then
                -- Scroll up in the window
                term.setCursorBlink(false)
                app.window.scroll(1)  -- Scroll one line up
                app.window.draw()
                term.setCursorPos(1 + pos, h)
                term.setCursorBlink(true)
                
            elseif param1 == keys.pageDown then
                -- Scroll down in the window
                term.setCursorBlink(false)
                app.window.scroll(-1)  -- Scroll one line down
                app.window.draw()
                term.setCursorPos(1 + pos, h)
                term.setCursorBlink(true)
            end
            
        elseif event == "char" then
            -- Add character to input
            input = input:sub(1, pos - 1) .. param1 .. input:sub(pos)
            pos = pos + 1
            term.setCursorPos(1, h)
            term.write("> " .. input)
            term.setCursorPos(1 + pos, h)
            
        elseif event == "term_resize" then
            -- Terminal was resized
            w, h = term.getSize()
            app.window.updateSize()
            app.window.draw()
            
            -- Redraw input
            term.setCursorPos(1, h)
            term.write("> " .. input)
            term.setCursorPos(1 + pos, h)
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

-- Initialize app
local function initialize()
    -- Initialize modem first
    if not modem.init() then
        error("Failed to initialize modem")
    end
    
    -- Clear terminal 
    term.clear()
    term.setCursorPos(1, 1)
    
    -- Create scroll window (leave bottom line for input)
    local w, h = term.getSize()
    app.window = scrollWindow.create(term.current())
    
    -- Configure scroll window
    app.window.setMaxScrollback(500)  -- Set maximum scrollback lines
    
    -- Send initial discovery ping
    modem.broadcastDiscovery()
    
    -- Draw initial interface
    redrawTerminal()
    
    -- Add welcome messages to log
    logMessage("========================================", "title")
    logMessage("         ComNet Hub Terminal v1.2       ", "title")
    logMessage("========================================", "title")
    logMessage("Hub ID: " .. modem.deviceID, "system")
    logMessage("Type /help for a list of commands", "system")
    logMessage("Use PageUp/PageDown to scroll message history", "system")
    logMessage("Scanning for devices...", "system")
    
    return true
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