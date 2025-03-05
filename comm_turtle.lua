-- CommTurtle - Communication module for turtles
-- Connects to CommCentral hub and allows remote control

-- Constants and configuration
local CONFIG = {
    PROTOCOL = "COMMCENTRAL",  -- protocol name for communications
    PING_INTERVAL = 15,  -- seconds between pings to keep connection alive
    CHANNELS = {
        BROADCAST = 65535,  -- channel for broadcast messages
        DISCOVERY = 64000,  -- channel for device discovery
    },
    COMMANDS = {
        -- Movement commands
        "forward", "back", "up", "down", "turnLeft", "turnRight",
        -- Tool commands
        "dig", "digUp", "digDown", "place", "placeUp", "placeDown",
        -- Inventory commands
        "select", "getItemCount", "getItemDetail", "transferTo",
        -- Information commands
        "detect", "detectUp", "detectDown", "inspect", "inspectUp", "inspectDown",
        -- Other commands
        "getFuelLevel", "refuel", "status", "help"
    },
    MAX_RETRIES = 3
}

-- Application state
local state = {
    modem = nil,             -- modem peripheral
    hubId = nil,             -- computer ID of connected hub
    busy = false,            -- turtle busy executing command
    running = true,          -- application running flag
    lastPing = 0,            -- last time we pinged the hub
    commandQueue = {},       -- queue of commands to execute
    position = {             -- current position (if tracking enabled)
        x = 0, y = 0, z = 0,
        tracking = false
    },
    inventory = {},          -- current inventory state
    lastCommand = {          -- last command executed
        name = nil,
        result = nil,
        error = nil
    }
}

-- Initialize the application
local function initialize()
    -- Find modem
    local modems = {peripheral.find("modem", function(name, modem) return modem.isWireless() end)}
    if #modems == 0 then
        error("No wireless modem found. Please attach a wireless modem.")
    end
    state.modem = modems[1]
    
    -- Open channels
    state.modem.open(CONFIG.CHANNELS.BROADCAST)
    state.modem.open(CONFIG.CHANNELS.DISCOVERY)
    
    -- Start rednet
    local modemSide = peripheral.getName(state.modem)
    rednet.open(modemSide)
    
    -- Display initial information
    term.clear()
    term.setCursorPos(1, 1)
    term.setTextColor(colors.yellow)
    print("CommTurtle v1.0")
    print("----------------")
    term.setTextColor(colors.white)
    print("Computer ID: " .. os.getComputerID())
    print("Awaiting connection from hub...")
    
    -- Send initial announcement
    announcePresence()
end

-- Communication functions
local function announcePresence()
    rednet.broadcast({
        type = "discovery_response",
        sender = os.getComputerID(),
        name = os.getComputerLabel() or "Turtle-" .. os.getComputerID(),
        computer_type = "turtle",
        protocol = CONFIG.PROTOCOL,
    }, CONFIG.PROTOCOL)
end

local function sendMessage(targetId, message, messageType)
    if not targetId then return false end
    
    local payload = {
        type = messageType or "message",
        sender = os.getComputerID(),
        content = message,
        protocol = CONFIG.PROTOCOL,
        timestamp = os.time()
    }
    
    return rednet.send(targetId, payload, CONFIG.PROTOCOL)
end

local function sendCommandResult(command, success, result, errorMessage)
    if not state.hubId then return false end
    
    local resultMessage = {
        command = command,
        success = success,
        result = result,
        error = errorMessage
    }
    
    return sendMessage(state.hubId, textutils.serialize(resultMessage), "command_result")
end

local function sendStatusUpdate()
    if not state.hubId then return false end
    
    -- Get current status information
    local status = {
        fuel = turtle.getFuelLevel(),
        position = state.position,
        inventory = scanInventory(),
        busy = state.busy,
        lastCommand = state.lastCommand
    }
    
    return sendMessage(state.hubId, textutils.serialize(status), "status_update")
end

-- Command execution
local function executeCommand(command, args)
    if state.busy then
        return false, "Turtle is busy"
    end
    
    state.busy = true
    state.lastCommand.name = command
    state.lastCommand.result = nil
    state.lastCommand.error = nil
    
    -- Process command
    local success, result, errorMsg
    
    if command == "forward" then
        success = turtle.forward()
        if success and state.position.tracking then
            if state.position.facing == 0 then state.position.z = state.position.z - 1
            elseif state.position.facing == 1 then state.position.x = state.position.x + 1
            elseif state.position.facing == 2 then state.position.z = state.position.z + 1
            elseif state.position.facing == 3 then state.position.x = state.position.x - 1
            end
        end
    elseif command == "back" then
        success = turtle.back()
        if success and state.position.tracking then
            if state.position.facing == 0 then state.position.z = state.position.z + 1
            elseif state.position.facing == 1 then state.position.x = state.position.x - 1
            elseif state.position.facing == 2 then state.position.z = state.position.z - 1
            elseif state.position.facing == 3 then state.position.x = state.position.x + 1
            end
        end
    elseif command == "up" then
        success = turtle.up()
        if success and state.position.tracking then
            state.position.y = state.position.y + 1
        end
    elseif command == "down" then
        success = turtle.down()
        if success and state.position.tracking then
            state.position.y = state.position.y - 1
        end
    elseif command == "turnLeft" then
        success = turtle.turnLeft()
        if success and state.position.tracking then
            state.position.facing = (state.position.facing - 1) % 4
        end
    elseif command == "turnRight" then
        success = turtle.turnRight()
        if success and state.position.tracking then
            state.position.facing = (state.position.facing + 1) % 4
        end
    elseif command == "dig" then
        success = turtle.dig()
    elseif command == "digUp" then
        success = turtle.digUp()
    elseif command == "digDown" then
        success = turtle.digDown()
    elseif command == "place" then
        success = turtle.place()
    elseif command == "placeUp" then
        success = turtle.placeUp()
    elseif command == "placeDown" then
        success = turtle.placeDown()
    elseif command == "select" then
        if args and args[1] and tonumber(args[1]) then
            success = turtle.select(tonumber(args[1]))
        else
            success = false
            errorMsg = "Invalid slot number"
        end
    elseif command == "getItemCount" then
        result = turtle.getItemCount()
        success = true
    elseif command == "getItemDetail" then
        local slot = args and args[1] and tonumber(args[1])
        if not slot then slot = turtle.getSelectedSlot() end
        result = turtle.getItemDetail(slot)
        success = true
    elseif command == "transferTo" then
        if args and args[1] and tonumber(args[1]) and tonumber(args[2]) then
            success = turtle.transferTo(tonumber(args[1]), tonumber(args[2]))
        else
            success = false
            errorMsg = "Invalid parameters"
        end
    elseif command == "detect" then
        result = turtle.detect()
        success = true
    elseif command == "detectUp" then
        result = turtle.detectUp()
        success = true
    elseif command == "detectDown" then
        result = turtle.detectDown()
        success = true
    elseif command == "inspect" then
        success, result = turtle.inspect()
    elseif command == "inspectUp" then
        success, result = turtle.inspectUp()
    elseif command == "inspectDown" then
        success, result = turtle.inspectDown()
    elseif command == "getFuelLevel" then
        result = turtle.getFuelLevel()
        success = true
    elseif command == "refuel" then
        local count = args and args[1] and tonumber(args[1])
        if count then
            success = turtle.refuel(count)
        else
            success = turtle.refuel()
        end
        result = turtle.getFuelLevel()
    elseif command == "status" then
        success = true
        sendStatusUpdate()
    elseif command == "help" then
        success = true
        result = "Available commands: " .. table.concat(CONFIG.COMMANDS, ", ")
    elseif command == "setPosition" then
        -- Custom command to set position
        if args and #args >= 3 then
            state.position.x = tonumber(args[1]) or 0
            state.position.y = tonumber(args[2]) or 0
            state.position.z = tonumber(args[3]) or 0
            state.position.facing = tonumber(args[4]) or 0
            state.position.tracking = true
            success = true
        else
            success = false
            errorMsg = "Need x, y, z coordinates"
        end
    elseif command == "enableTracking" then
        state.position.tracking = true
        success = true
    elseif command == "disableTracking" then
        state.position.tracking = false
        success = true
    else
        success = false
        errorMsg = "Unknown command: " .. command
    end
    
    -- Update command result
    state.lastCommand.result = result
    state.lastCommand.error = errorMsg
    
    -- Send result back to hub
    sendCommandResult(command, success, result, errorMsg)
    
    -- Update inventory if needed
    if command:match("dig") or command:match("place") or command:match("refuel") or
       command:match("transfer") or command:match("drop") then
        state.inventory = scanInventory()
    end
    
    state.busy = false
    return success, result, errorMsg
end

-- Utility functions
local function scanInventory()
    local inventory = {}
    local currentSlot = turtle.getSelectedSlot()
    
    for i = 1, 16 do
        turtle.select(i)
        inventory[i] = turtle.getItemDetail() or {name = "empty", count = 0}
    end
    
    turtle.select(currentSlot)
    return inventory
end

local function processMessage(senderId, message, protocol)
    if type(message) ~= "table" or message.protocol ~= CONFIG.PROTOCOL then
        return
    end
    
    -- Handle different message types
    if message.type == "discovery_ping" then
        -- Respond to discovery ping
        announcePresence()
        -- Update hub if this is from our hub
        if state.hubId == senderId then
            state.lastPing = os.time()
        end
    elseif message.type == "message" then
        -- Handle text message
        if message.content == "/ping" then
            sendMessage(senderId, "/ping_response")
        elseif message.content:sub(1, 1) == "!" then
            -- Execute command prefixed with !
            local commandStr = message.content:sub(2)
            local command = commandStr:match("^(%S+)")
            local args = {}
            
            for arg in commandStr:gmatch("%S+") do
                if arg ~= command then
                    table.insert(args, arg)
                end
            end
            
            if command then
                -- Add to queue for execution
                table.insert(state.commandQueue, {cmd = command, args = args, sender = senderId})
            end
        end
        
        -- Update terminal with message
        term.setTextColor(colors.lightBlue)
        local sender = "Hub #" .. senderId
        if state.hubId == senderId then sender = "Connected Hub" end
        print(sender .. ": " .. message.content)
        term.setTextColor(colors.white)
    elseif message.type == "connect_request" then
        -- Hub wants to connect to this turtle
        state.hubId = senderId
        state.lastPing = os.time()
        
        -- Send acknowledgment and status
        sendMessage(senderId, "Connection accepted", "connect_response")
        sendStatusUpdate()
        
        -- Update terminal
        term.setTextColor(colors.lime)
        print("Connected to hub #" .. senderId)
        term.setTextColor(colors.white)
    elseif message.type == "disconnect_request" then
        -- Hub wants to disconnect
        if state.hubId == senderId then
            state.hubId = nil
            sendMessage(senderId, "Disconnected", "connect_response")
            
            -- Update terminal
            term.setTextColor(colors.red)
            print("Disconnected from hub #" .. senderId)
            term.setTextColor(colors.white)
        end
    end
end

-- Main event loop
local function eventLoop()
    while state.running do
        -- Process command queue
        if #state.commandQueue > 0 and not state.busy then
            local cmd = table.remove(state.commandQueue, 1)
            executeCommand(cmd.cmd, cmd.args)
        end
        
        -- Send periodic ping to hub
        if state.hubId and os.time() - state.lastPing > CONFIG.PING_INTERVAL then
            sendMessage(state.hubId, "ping", "ping")
            state.lastPing = os.time()
        end
        
        -- Listen for events
        local timeout = 1
        if #state.commandQueue > 0 and not state.busy then
            timeout = 0.05  -- Shorter timeout if we have commands to process
        end
        
        local event = {os.pullEvent()}
        
        if event[1] == "rednet_message" then
            local senderId, message, protocol = event[2], event[3], event[4]
            processMessage(senderId, message, protocol)
        elseif event[1] == "key" and event[2] == keys.q and event[3] then
            -- Allow termination with Ctrl+Q
            print("Terminating CommTurtle...")
            state.running = false
        end
    end
end

-- Application startup
local function main()
    -- Initialize application
    initialize()
    
    -- Run event loop
    eventLoop()
    
    -- Cleanup
    term.setTextColor(colors.white)
    term.setCursorPos(1, term.getCursorPos())
    print("CommTurtle terminated.")
end

-- Start the application
main() 