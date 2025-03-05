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
}

-- App state
local app = {
    running = true,
    devices = {},
    selected = nil,
    history = {},  -- Command history
    historyPos = 0,
    messageLog = {},  -- Log of all messages for display
}

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
    end
    
    -- Store in log
    table.insert(app.messageLog, {
        text = message,
        timestamp = timestamp,
        type = messageType,
        color = color
    })
    
    -- Keep log size reasonable
    if #app.messageLog > 100 then
        table.remove(app.messageLog, 1)
    end
    
    -- Display immediately
    term.setTextColor(color)
    print("[" .. timestamp .. "] " .. message)
    term.setTextColor(COLORS.TEXT)
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
    
    -- Print header
    print()
    term.setTextColor(COLORS.TITLE)
    print("=== Connected Devices (" .. connectedCount .. "/" .. deviceCount .. ") ===")
    term.setTextColor(COLORS.TEXT)
    
    -- Print each device
    for i, device in ipairs(sorted) do
        local prefix = "  "
        if app.selected == device.id then
            prefix = "> " -- Show which device is selected
        end
        
        if device.connected then
            term.setTextColor(COLORS.CONNECTED)
        else
            term.setTextColor(COLORS.DISCONNECTED)
        end
        
        local status = device.connected and "CONNECTED" or "DISCONNECTED"
        print(prefix .. device.name .. " (ID: " .. device.id .. ") - " .. status .. " - Type: " .. device.type)
    end
    
    term.setTextColor(COLORS.TEXT)
    print()
end

-- Show help information
local function showHelp()
    term.setTextColor(COLORS.TITLE)
    print("\n=== ComNet Hub Command Help ===")
    term.setTextColor(COLORS.TEXT)
    print("Commands:")
    print("  /list             - List all connected devices")
    print("  /select [id]      - Select a device by ID")
    print("  /send [id] [msg]  - Send message to specific device")
    print("  /scan             - Scan for devices")
    print("  /name [id] [name] - Rename a device")
    print("  /clear            - Clear message history")
    print("  /status           - Show connection status")
    print("  /help             - Show this help")
    print("  /exit             - Exit application")
    print("\nSending Messages:")
    print("  - Type a message and press Enter to send to selected device")
    print("  - Start message with ! to send a command to a turtle (e.g. !forward)")
    print("  - Use /ping to check if a device is responding")
    print()
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
        term.clear()
        term.setCursorPos(1, 1)
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
    
    -- Send initial discovery ping
    modem.broadcastDiscovery()
    
    -- Clear terminal and show welcome message
    term.clear()
    term.setCursorPos(1, 1)
    
    term.setTextColor(COLORS.TITLE)
    print("========================================")
    print("         ComNet Hub Terminal v1.0       ")
    print("========================================")
    term.setTextColor(COLORS.TEXT)
    print("Hub ID: " .. modem.deviceID)
    print("Type /help for a list of commands")
    print("Scanning for devices...")
    
    return true
end

-- Read user input (with history support)
local function readInput()
    term.setTextColor(COLORS.TEXT)
    write("> ")
    
    local input = read(nil, app.history)
    
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