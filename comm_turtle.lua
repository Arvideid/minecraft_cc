-- comm_turtle.lua
-- Turtle client for ComputerCraft communication system

-- Load the modem control module
local modem = require("modem_control")

-- Available commands
local COMMANDS = {
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
}

-- Turtle state
local state = {
    running = true,       -- Program running
    busy = false,         -- Currently executing command
    commandQueue = {},    -- Queue of commands to execute
    hubID = nil,          -- Current hub ID
    lastPing = 0,         -- Last ping time
    position = {          -- Current position (if tracking enabled)
        x = 0, y = 0, z = 0,
        facing = 0,       -- 0=north, 1=east, 2=south, 3=west
        tracking = false
    },
    lastCommand = {       -- Last command executed
        name = nil,
        result = nil,
        error = nil
    },
    inventory = {}        -- Current inventory
}

-- Function declarations
local scanInventory, sendCommandResult, sendStatusUpdate, executeCommand, processMessage

-- Scan inventory and return a table of slots
function scanInventory()
    local inventory = {}
    local currentSlot = turtle.getSelectedSlot()
    
    for i = 1, 16 do
        turtle.select(i)
        inventory[i] = turtle.getItemDetail() or {name = "empty", count = 0}
    end
    
    turtle.select(currentSlot)
    return inventory
end

-- Send command result to hub
function sendCommandResult(command, success, result, errorMessage)
    if not state.hubID then return false end
    
    local resultMessage = {
        command = command,
        success = success,
        result = result,
        error = errorMessage
    }
    
    return modem.sendMessage(state.hubID, textutils.serialize(resultMessage), "command_result")
end

-- Send status update to hub
function sendStatusUpdate()
    if not state.hubID then return false end
    
    -- Get current status information
    local status = {
        fuel = turtle.getFuelLevel(),
        position = state.position,
        inventory = state.inventory,
        busy = state.busy,
        lastCommand = state.lastCommand
    }
    
    return modem.sendMessage(state.hubID, textutils.serialize(status), "status_update")
end

-- Execute a turtle command
function executeCommand(command, args)
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
        if args and args[1] and tonumber(args[1]) and args[2] and tonumber(args[2]) then
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
        result = "Available commands: " .. table.concat(COMMANDS, ", ")
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

-- Process incoming messages
function processMessage(senderId, message)
    if not message or not message.type then return end
    
    if message.type == "discovery_ping" then
        -- Respond to discovery ping
        modem.respondToDiscovery(senderId)
        -- Update hub if this is from our hub
        if state.hubID == senderId then
            state.lastPing = os.time()
        end
    elseif message.type == "ping" then
        -- Handle explicit ping message (fixing the ping issue)
        -- Update hub if this is from our hub or make this the hub
        state.lastPing = os.time()
        if not state.hubID then
            state.hubID = senderId
            term.setTextColor(colors.lime)
            print("Connected to hub #" .. senderId .. " (via ping)")
            term.setTextColor(colors.white)
        end
        
        -- Send ping response back
        modem.sendMessage(senderId, "pong", "ping_response")
        
        -- Show ping received
        term.setTextColor(colors.lightBlue)
        print("Ping received from Hub #" .. senderId)
        term.setTextColor(colors.white)
    elseif message.type == "ping_response" then
        -- Handle ping response
        state.lastPing = os.time()
        
        -- Show ping response
        term.setTextColor(colors.lightBlue)
        print("Ping response from Hub #" .. senderId)
        term.setTextColor(colors.white)
    elseif message.type == "message" then
        -- Handle text message
        if message.content == "/ping" then
            modem.sendMessage(senderId, "/ping_response", "message")
            
            -- Show ping received
            term.setTextColor(colors.lightBlue)
            print("Text ping received from Hub #" .. senderId)
            term.setTextColor(colors.white)
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
        if state.hubID == senderId then sender = "Connected Hub" end
        print(sender .. ": " .. message.content)
        term.setTextColor(colors.white)
    elseif message.type == "connect_request" then
        -- Hub wants to connect to this turtle
        state.hubID = senderId
        state.lastPing = os.time()
        
        -- Send acknowledgment and status
        modem.sendMessage(senderId, "Connection accepted", "connect_response")
        sendStatusUpdate()
        
        -- Update terminal
        term.setTextColor(colors.lime)
        print("Connected to hub #" .. senderId)
        term.setTextColor(colors.white)
    elseif message.type == "disconnect_request" then
        -- Hub wants to disconnect
        if state.hubID == senderId then
            state.hubID = nil
            modem.sendMessage(senderId, "Disconnected", "connect_response")
            
            -- Update terminal
            term.setTextColor(colors.red)
            print("Disconnected from hub #" .. senderId)
            term.setTextColor(colors.white)
        end
    end
end

-- Initialize application
local function initialize()
    -- Initialize modem first
    if not modem.init() then
        error("Failed to initialize modem")
    end
    
    -- Draw startup screen
    term.clear()
    term.setCursorPos(1, 1)
    term.setTextColor(colors.yellow)
    print("ComNet Turtle v1.1")
    print("----------------")
    term.setTextColor(colors.white)
    print("Computer ID: " .. modem.deviceID)
    print("Awaiting connection from hub...")
    
    -- Initial inventory scan
    state.inventory = scanInventory()
    
    -- Announce our presence
    modem.broadcastDiscovery()
    
    return true
end

-- Main event loop
local function mainLoop()
    while state.running do
        -- Process command queue
        if #state.commandQueue > 0 and not state.busy then
            local cmd = table.remove(state.commandQueue, 1)
            executeCommand(cmd.cmd, cmd.args)
        end
        
        -- Send periodic ping to hub
        if state.hubID and os.time() - state.lastPing > 15 then
            modem.sendMessage(state.hubID, "ping", "ping")
            state.lastPing = os.time()
        end
        
        -- Broadcast discovery occasionally if not connected
        if not state.hubID and os.time() - modem.lastPingTime > 30 then
            modem.broadcastDiscovery()
        end
        
        -- Listen for events
        local event = {os.pullEvent()}
        
        if event[1] == "rednet_message" then
            local senderId, message, protocol = event[2], event[3], event[4]
            if protocol == modem.config.PROTOCOL then
                processMessage(senderId, message)
            end
        elseif event[1] == "key" and event[2] == keys.q and event[3] then
            -- Allow termination with Ctrl+Q
            print("Terminating ComNet Turtle...")
            state.running = false
        end
    end
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
    term.setTextColor(colors.white)
    term.setCursorPos(1, term.getCursorPos())
    print("ComNet Turtle terminated.")
    
    -- Close modem connections
    modem.close()
end

-- Start the application
main() 