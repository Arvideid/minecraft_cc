-- comm_hub.lua
-- ComputerCraft Communication Hub with Simplified Terminal Interface

-- Load the modem control module
local modem = require("modem_control")
local scroll_window = require("scroll_window")

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
}

-- App state
local app = {
    running = true,
    devices = {},
    selected = nil,
    history = {},      -- Command history
    historyPos = 0,
    terminal = nil,    -- Scrollable terminal window
}

-- Forward declarations
local logMessage

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

-- Simplified logging function
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
    
    -- Show in scrollable terminal
    if app.terminal then
        app.terminal.setTextColor(color)
        app.terminal.write("[" .. timestamp .. "] ")
        app.terminal.write(message)
        app.terminal.write("\n")
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
        "  Use the scroll wheel to navigate through message history",
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
        -- Clear terminal
        term.clear()
        term.setCursorPos(1, 1)
        
        -- Reinitialize scroll window
        app.terminal = scroll_window.create(term.current())
        app.terminal.setMaxScrollback(500)
        
        logMessage("Terminal cleared", "system")
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

-- Initialize app
local function initialize()
    -- Initialize modem first
    if not modem.init() then
        error("Failed to initialize modem")
    end
    
    -- Clear terminal
    term.clear()
    term.setCursorPos(1, 1)
    
    -- Initialize scroll window
    app.terminal = scroll_window.create(term.current())
    app.terminal.setMaxScrollback(500)  -- Store 500 lines of history
    
    -- Send initial discovery ping
    modem.broadcastDiscovery()
    
    -- Add welcome messages to log
    logMessage("========================================", "title")
    logMessage("         ComNet Hub Terminal v2.0       ", "title")
    logMessage("========================================", "title")
    logMessage("Hub ID: " .. modem.deviceID, "system")
    logMessage("Type /help for a list of commands", "system")
    logMessage("Use mouse wheel to scroll message history", "system")
    logMessage("Scanning for devices...", "system")
    
    return true
end

-- Read user input with basic history support
local function readInput()
    -- Show input prompt at bottom
    local w, h = term.getSize()
    term.setCursorPos(1, h)
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
    term.clearLine()
    term.write("> ")
    
    -- Read input with basic history
    local input = read(nil, app.history, function(text)
        if text:sub(1, 1) == "/" then
            local matches = {}
            for cmd in ("list select send scan name clear status help exit ping"):gmatch("%S+") do
                if "/" .. cmd:sub(1, #text - 1) == text then
                    table.insert(matches, "/" .. cmd)
                end
            end
            return matches
        end
        return nil
    end)
    
    -- Add to history if not empty
    if input ~= "" then
        -- Avoid duplicates
        if #app.history == 0 or app.history[#app.history] ~= input then
            table.insert(app.history, input)
            if #app.history > 50 then table.remove(app.history, 1) end
        end
    end
    
    -- Clear input line
    term.setCursorPos(1, h)
    term.clearLine()
    
    return input
end

-- Main event loop
local function mainLoop()
    -- Network handling function
    local function networkTask()
        while app.running do
            -- Check for device timeouts
            checkDeviceTimeouts()
            
            -- Send periodic discovery pings
            if os.time() - modem.lastPingTime > 30 then
                logMessage("Broadcasting discovery ping...", "system")
                modem.broadcastDiscovery()
            end
            
            -- Process incoming messages (with short timeout)
            local senderId, message = rednet.receive(modem.config.PROTOCOL, 0.5)
            if senderId and message then
                processMessage(senderId, message)
            end
            
            -- Small sleep to prevent CPU usage
            os.sleep(0.1)
        end
    end
    
    -- Input handling function
    local function inputTask()
        while app.running do
            -- Process regular input
            local input = readInput()
            if input and #input > 0 then
                processCommand(input)
            end
            
            -- Make sure terminal UI is up to date
            if app.terminal then
                app.terminal.draw(0)
            end
        end
    end
    
    -- Mouse event handler for scroll wheel
    local function mouseTask()
        while app.running do
            local event, button, x, y = os.pullEvent("mouse_scroll")
            
            -- Pass scroll events to the terminal
            if app.terminal then
                app.terminal.scroll(button) -- button will be 1 for up, -1 for down
                app.terminal.draw(0)
            end
        end
    end
    
    -- Run all tasks in parallel
    parallel.waitForAny(networkTask, inputTask, mouseTask)
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