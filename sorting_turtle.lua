-- Define the sorting turtle module
local sortingTurtle = {}

-- Import the LLM module
local llm = require("llm")

-- Configuration
sortingTurtle.config = {
    SCAN_INTERVAL = 300,  -- Rescan every 5 minutes
    MIN_FUEL_LEVEL = 100,  -- Minimum fuel level before refueling
    MAX_STEPS = 16,  -- Maximum steps to search for barrels
    FUEL_ITEMS = {  -- Items that can be used as fuel
        ["minecraft:coal"] = true,
        ["minecraft:charcoal"] = true,
        ["minecraft:coal_block"] = true,
        ["minecraft:lava_bucket"] = true
    },
    INITIAL_FUEL_CHECK = true  -- Flag to track if initial fuel check has been done
}

-- Store information about discovered barrels
sortingTurtle.barrels = {}
sortingTurtle.numBarrels = 0
sortingTurtle.lastScanTime = 0
sortingTurtle.position = { x = 0, y = 0, z = 0, facing = 0 }  -- 0=north, 1=east, 2=south, 3=west
sortingTurtle.moveHistory = {}  -- Track movement history

-- Runtime-only category system
sortingTurtle.categories = {}  -- Will store category definitions
sortingTurtle.barrelAssignments = {}  -- Will store barrel -> category mappings

-- Add after sortingTurtle initialization
sortingTurtle.problematicItems = {}  -- Track items that couldn't be sorted

-- Function to add movement to history
function sortingTurtle.addToHistory(movement)
    table.insert(sortingTurtle.moveHistory, movement)
end

-- Function to get reverse movement
function sortingTurtle.getReverseMovement(movement)
    if movement == "forward" then return "back"
    elseif movement == "back" then return "forward"
    elseif movement == "turnLeft" then return "turnRight"
    elseif movement == "turnRight" then return "turnLeft"
    elseif movement == "up" then return "down"
    elseif movement == "down" then return "up"
    else return nil end
end

-- Function to return to initial position using movement history
function sortingTurtle.returnToInitial()
    print("Returning to initial position...")
    
    -- Reverse through movement history
    for i = #sortingTurtle.moveHistory, 1, -1 do
        local reverseMove = sortingTurtle.getReverseMovement(sortingTurtle.moveHistory[i])
        if reverseMove then
            if not turtle[reverseMove]() then
                print("Warning: Could not complete reverse movement!")
                break
            end
            -- Update position for the reverse movement
            if reverseMove == "forward" or reverseMove == "back" or 
               reverseMove == "up" or reverseMove == "down" or
               reverseMove == "turnLeft" or reverseMove == "turnRight" then
                sortingTurtle.updatePosition(reverseMove)
            end
        end
    end
    
    -- Clear movement history after returning
    sortingTurtle.moveHistory = {}
    print("Returned to initial position")
end

-- After the configuration section, add new environment tracking
sortingTurtle.environment = {
    blocks = {},  -- Will store block information in a 3D grid
    lastScan = {},  -- Last scan results
    SCAN_RADIUS = 4  -- How far to scan in each direction
}

-- Function to check if a block is a barrel
function sortingTurtle.isBarrel()
    local success, data = turtle.inspect()
    if success and data then
        return data.name == "minecraft:barrel" or 
               data.name:find("barrel") or 
               data.name:find("storage")
    end
    return false
end

-- Function to read barrel contents
function sortingTurtle.readBarrel()
    local contents = {
        items = {},
        isEmpty = true
    }
    
    -- Save current selected slot
    local currentSlot = turtle.getSelectedSlot()
    
    -- First, try to suck one item to check if barrel is empty
    if not turtle.suck() then
        turtle.select(currentSlot)
        return contents  -- Barrel is empty
    end
    turtle.drop()  -- Put it back
    
    print("Reading barrel contents...")
    
    -- First phase: Get ALL items from the barrel
    local startingEmptySlots = sortingTurtle.countEmptySlots()
    local itemsGrabbed = false
    
    -- Keep sucking until we can't get any more items or inventory is full
    while turtle.suck() do
        itemsGrabbed = true
        -- If inventory is full, stop
        if sortingTurtle.countEmptySlots() == 0 then
            break
        end
    end
    
    if itemsGrabbed then
        contents.isEmpty = false
        
        -- Second phase: Scan our inventory for unique items
        for slot = 1, 16 do
            local item = turtle.getItemDetail(slot)
        if item then
                -- Check if we already have this item type recorded
                local found = false
                for _, existingItem in ipairs(contents.items) do
                    if existingItem.name == item.name then
                        found = true
                        break
        end
    end
    
                -- If it's a new item type, add it to our list
                if not found then
                    table.insert(contents.items, {
                        name = item.name,
                        displayName = item.displayName or item.name
                    })
                    print("Found item type:", item.displayName or item.name)
                end
            end
        end
        
        -- Third phase: Return ALL items to the barrel
        for slot = 1, 16 do
            if turtle.getItemCount(slot) > 0 then
                turtle.select(slot)
                turtle.drop()
            end
        end
    end
    
    -- Restore original selected slot
    turtle.select(currentSlot)
    
    -- Debug output
    if not contents.isEmpty then
        print("\nBarrel contains:")
        for _, item in ipairs(contents.items) do
            print("- " .. (item.displayName or item.name))
        end
    else
        print("Barrel is empty")
    end
    
    return contents
end

-- Function to categorize items (helps with grouping similar items)
function sortingTurtle.getItemCategory(itemName)
    if not itemName then return "unknown" end
    
    -- Convert itemName to lowercase for case-insensitive matching
    itemName = string.lower(itemName)
    
    -- Extract mod prefix and base name
    local modPrefix, baseName = itemName:match("^([^:]+):(.+)$")
    if not modPrefix then return "unknown" end
    
    -- Just return the mod prefix and base name for the LLM to handle categorization
    return modPrefix .. "_" .. baseName
end

-- Function to check and maintain fuel levels
function sortingTurtle.checkFuel()
    local fuelLevel = turtle.getFuelLevel()
    if fuelLevel == "unlimited" then return true end
    
    -- Only print fuel level during initial check
    if sortingTurtle.config.INITIAL_FUEL_CHECK then
        print(string.format("Initial fuel level: %d", fuelLevel))
        sortingTurtle.config.INITIAL_FUEL_CHECK = false
    end
    
    if fuelLevel < sortingTurtle.config.MIN_FUEL_LEVEL then
        print("Fuel level low, attempting to refuel...")
        -- Check inventory for fuel items
        for slot = 1, 16 do
            turtle.select(slot)
            local item = turtle.getItemDetail()
            if item and sortingTurtle.config.FUEL_ITEMS[item.name] then
                if turtle.refuel(1) then
                    print(string.format("Refueled with %s", item.name))
                    return true
                end
            end
        end
        print("WARNING: No fuel items found!")
        return false
    end
    return true
end

-- Function to detect surroundings
function sortingTurtle.detectSurroundings()
    local surroundings = {
        front = { exists = turtle.detect(), block = nil },
        up = { exists = turtle.detectUp(), block = nil },
        down = { exists = turtle.detectDown(), block = nil }
    }
    
    -- Get block information
    if surroundings.front.exists then
        local success, data = turtle.inspect()
        if success then surroundings.front.block = data end
    end
    if surroundings.up.exists then
        local success, data = turtle.inspectUp()
        if success then surroundings.up.block = data end
    end
    if surroundings.down.exists then
        local success, data = turtle.inspectDown()
        if success then surroundings.down.block = data end
    end
    
    return surroundings
end

-- Function to update position after movement
function sortingTurtle.updatePosition(movement)
    if movement == "forward" then
        if sortingTurtle.position.facing == 0 then
            sortingTurtle.position.z = sortingTurtle.position.z - 1
        elseif sortingTurtle.position.facing == 1 then
            sortingTurtle.position.x = sortingTurtle.position.x + 1
        elseif sortingTurtle.position.facing == 2 then
            sortingTurtle.position.z = sortingTurtle.position.z + 1
        else
            sortingTurtle.position.x = sortingTurtle.position.x - 1
        end
    elseif movement == "back" then
        if sortingTurtle.position.facing == 0 then
            sortingTurtle.position.z = sortingTurtle.position.z + 1
        elseif sortingTurtle.position.facing == 1 then
            sortingTurtle.position.x = sortingTurtle.position.x - 1
        elseif sortingTurtle.position.facing == 2 then
            sortingTurtle.position.z = sortingTurtle.position.z - 1
        else
            sortingTurtle.position.x = sortingTurtle.position.x + 1
        end
    elseif movement == "up" then
        sortingTurtle.position.y = sortingTurtle.position.y + 1
    elseif movement == "down" then
        sortingTurtle.position.y = sortingTurtle.position.y - 1
    elseif movement == "turnRight" then
        sortingTurtle.position.facing = (sortingTurtle.position.facing + 1) % 4
    elseif movement == "turnLeft" then
        sortingTurtle.position.facing = (sortingTurtle.position.facing - 1) % 4
    end
end

-- Optimized movement function with minimal scanning
function sortingTurtle.safeMove(movement)
    if not sortingTurtle.checkFuel() then
        print("Cannot move: Insufficient fuel!")
        return false
    end
    
    local success = false
    if movement == "forward" then
        success = turtle.forward()
    elseif movement == "back" then
        success = turtle.back()
    elseif movement == "up" then
        success = turtle.up()
    elseif movement == "down" then
        success = turtle.down()
    elseif movement == "turnRight" then
        turtle.turnRight()
        success = true
    elseif movement == "turnLeft" then
        turtle.turnLeft()
        success = true
    end
    
    if success then
        sortingTurtle.updatePosition(movement)
        sortingTurtle.addToHistory(movement)
        return true
    end
    return false
end

-- Function to return to home position
function sortingTurtle.returnHome()
    print("Returning to home position...")
    
    -- First, handle Y position
    while sortingTurtle.position.y > 0 do
        if not sortingTurtle.safeMove("down") then break end
    end
    while sortingTurtle.position.y < 0 do
        if not sortingTurtle.safeMove("up") then break end
    end
    
    -- Turn to face the right direction for X movement
    if sortingTurtle.position.x > 0 then
        while sortingTurtle.position.facing ~= 3 do  -- Face west
            sortingTurtle.safeMove("turnLeft")
        end
    elseif sortingTurtle.position.x < 0 then
        while sortingTurtle.position.facing ~= 1 do  -- Face east
            sortingTurtle.safeMove("turnLeft")
        end
    end
    
    -- Move in X direction
    while sortingTurtle.position.x ~= 0 do
        if sortingTurtle.position.x > 0 then
            if not sortingTurtle.safeMove("forward") then break end
        else
            if not sortingTurtle.safeMove("forward") then break end
        end
    end
    
    -- Turn to face the right direction for Z movement
    if sortingTurtle.position.z > 0 then
        while sortingTurtle.position.facing ~= 0 do  -- Face north
            sortingTurtle.safeMove("turnLeft")
        end
    elseif sortingTurtle.position.z < 0 then
        while sortingTurtle.position.facing ~= 2 do  -- Face south
            sortingTurtle.safeMove("turnLeft")
        end
    end
    
    -- Move in Z direction
    while sortingTurtle.position.z ~= 0 do
        if sortingTurtle.position.z > 0 then
            if not sortingTurtle.safeMove("forward") then break end
        else
            if not sortingTurtle.safeMove("forward") then break end
        end
    end
    
    -- Face north (default position)
    while sortingTurtle.position.facing ~= 0 do
        sortingTurtle.safeMove("turnLeft")
    end
    
    if sortingTurtle.position.x == 0 and sortingTurtle.position.y == 0 and 
       sortingTurtle.position.z == 0 and sortingTurtle.position.facing == 0 then
        print("Successfully returned home!")
        return true
    else
        print("Warning: Could not return to exact home position!")
        print(string.format("Current position: x=%d, y=%d, z=%d, facing=%d",
            sortingTurtle.position.x, sortingTurtle.position.y,
            sortingTurtle.position.z, sortingTurtle.position.facing))
        return false
    end
end

-- Function to check inventory space
function sortingTurtle.hasInventorySpace()
    for slot = 1, 16 do
        if turtle.getItemCount(slot) == 0 then
            return true
        end
    end
    return false
end

-- Function to count empty slots
function sortingTurtle.countEmptySlots()
    local count = 0
    for slot = 1, 16 do
        if turtle.getItemCount(slot) == 0 then
            count = count + 1
        end
    end
    return count
end

-- Function to get total items in inventory
function sortingTurtle.getTotalItems()
    local total = 0
    for slot = 1, 16 do
        total = total + turtle.getItemCount(slot)
    end
    return total
end

-- Function to perform a 360-degree scan
function sortingTurtle.scan360()
    local scan = {
        north = {},
        east = {},
        south = {},
        west = {},
        up = turtle.detectUp(),
        down = turtle.detectDown(),
        upBlock = nil,
        downBlock = nil
    }
    
    -- Get up/down block data
    if scan.up then
        local success, data = turtle.inspectUp()
        if success then scan.upBlock = data end
    end
    if scan.down then
        local success, data = turtle.inspectDown()
        if success then scan.downBlock = data end
    end
    
    -- Store original facing direction
    local originalFacing = sortingTurtle.position.facing
    
    -- Scan in all four directions
    for i = 0, 3 do
        local direction = ({"north", "east", "south", "west"})[i + 1]
        local success, data = turtle.inspect()
        scan[direction] = {
            exists = success,
            block = data
        }
        sortingTurtle.safeMove("turnRight")
    end
    
    -- Return to original facing direction
    while sortingTurtle.position.facing ~= originalFacing do
        sortingTurtle.safeMove("turnRight")
    end
    
    sortingTurtle.lastScan = scan
    return scan
end

-- Function to analyze surroundings and find interesting blocks
function sortingTurtle.analyzeSurroundings()
    local scan = sortingTurtle.scan360()
    local findings = {
        barrels = {},
        chests = {},
        obstacles = {},
        interesting = {}
    }
    
    -- Helper function to categorize a block
    local function categorizeBlock(block, direction, distance)
        if not block then return end  -- Early return if block is nil
        
        -- Create info table with safe access to block properties
        local info = {
            name = block.name or "unknown",
            direction = direction or "unknown",
            distance = distance or 1
        }
        
        -- Skip processing if we don't have a valid name
        if not info.name or info.name == "unknown" then
            return
        end
        
        -- Check for storage blocks
        if string.find(info.name, "barrel") or string.find(info.name, "storage") then
            table.insert(findings.barrels, info)
        elseif string.find(info.name, "chest") then
            table.insert(findings.chests, info)
        elseif info.name ~= "minecraft:air" then
            table.insert(findings.obstacles, info)
        end
        
        -- Check for special blocks
        if string.find(info.name, "diamond") or string.find(info.name, "chest") or
           string.find(info.name, "furnace") or string.find(info.name, "crafting") then
            table.insert(findings.interesting, info)
        end
    end
    
    -- Analyze each direction with nil checks
    for direction, data in pairs(scan) do
        if direction ~= "up" and direction ~= "down" then
            if type(data) == "table" and data.block then  -- Add type check
                categorizeBlock(data.block, direction)
            end
        end
    end
    
    -- Analyze up/down with nil checks
    if scan.upBlock then 
        categorizeBlock(scan.upBlock, "up") 
    end
    if scan.downBlock then 
        categorizeBlock(scan.downBlock, "down") 
    end
    
    return findings
end

-- Function to map current position
function sortingTurtle.mapPosition()
    local surroundings = sortingTurtle.analyzeSurroundings()
    local pos = sortingTurtle.position
    local key = string.format("%d,%d,%d", pos.x, pos.y, pos.z)
    
    sortingTurtle.environment.blocks[key] = {
        position = {x = pos.x, y = pos.y, z = pos.z},
        surroundings = surroundings,
        timestamp = os.epoch("local")
    }
    
    return surroundings
end

-- Add a new function for step-by-step movement with 360 scanning
function sortingTurtle.moveWithScan(movement)
    -- Only scan if we're moving forward, not for turns
    local needsScan = (movement == "forward")
    
    -- Perform the movement first
    local success = sortingTurtle.safeMove(movement)
    
    if success and needsScan then
        -- Do a single scan after moving forward
        local scan = sortingTurtle.mapPosition()
        
        -- Report only if we found something
        if #scan.barrels > 0 or #scan.obstacles > 0 or #scan.interesting > 0 then
            print("Environment scan results:")
            if #scan.barrels > 0 then print("  - Found " .. #scan.barrels .. " barrels") end
            if #scan.obstacles > 0 then print("  - Found " .. #scan.obstacles .. " obstacles") end
            if #scan.interesting > 0 then print("  - Found " .. #scan.interesting .. " interesting blocks") end
        end
    end
    
    return success
end

-- Function to move to a specific barrel position
function sortingTurtle.moveToBarrel(barrelNumber)
    -- Turn left to face the barrels if not already facing them
    while sortingTurtle.position.facing ~= 3 do  -- 3 is west (left)
        turtle.turnLeft()
        sortingTurtle.addToHistory("turnLeft")
        sortingTurtle.updatePosition("turnLeft")
    end
    
    -- Move forward one step to be in line with barrels
    if not turtle.forward() then
        print("Cannot move forward to barrel line!")
        return false
    end
    sortingTurtle.addToHistory("forward")
    sortingTurtle.updatePosition("forward")
    
    -- Move to position in front of the target barrel
    local stepsNeeded = sortingTurtle.barrels[barrelNumber].position
    local currentStep = 0
    
    while currentStep < stepsNeeded do
        if turtle.forward() then
            sortingTurtle.addToHistory("forward")
            sortingTurtle.updatePosition("forward")
            currentStep = currentStep + 1
        else
            return false
        end
    end

    -- Turn right to face the barrel
    turtle.turnRight()
    sortingTurtle.addToHistory("turnRight")
    sortingTurtle.updatePosition("turnRight")
    
    return true
end

-- Function to return to the input chest
function sortingTurtle.returnToChest()
    -- First turn back to face the path (west)
    while sortingTurtle.position.facing ~= 3 do  -- 3 is west (left)
        turtle.turnLeft()
        sortingTurtle.updatePosition("turnLeft")
    end
    
    -- Move back to the chest position
    while sortingTurtle.position.x < 0 do
        if turtle.forward() then
            sortingTurtle.updatePosition("forward")
        else
            break
        end
    end
    
    -- Move back one step to be behind the input storage
    turtle.back()
    sortingTurtle.updatePosition("back")
    
    -- Turn to face the input storage (north)
    while sortingTurtle.position.facing ~= 0 do
        turtle.turnLeft()
        sortingTurtle.updatePosition("turnLeft")
    end
end

-- Function to get LLM analysis of barrel contents
function sortingTurtle.analyzeBarrelContents(barrel)
    if not barrel or not barrel.contents then return nil end
    
    local prompt = string.format([[
Analyze this Minecraft barrel's contents to determine its purpose and suggest what other items would fit well in it.

Current Contents:
Name: %s
Display Name: %s
Category: %s

Consider:
1. What is the main theme/purpose of this barrel?
2. What types of items would logically belong here?
3. Are there related items from the same mod that should go here?
4. What crafting or gameplay relationships exist with these items?

Return a brief, one-line description of the barrel's purpose.]], 
        barrel.contents.name,
        barrel.contents.displayName,
        barrel.contents.category)
    
    return llm.getGeminiResponse(prompt)
end

-- Function to analyze all barrels at once using LLM
function sortingTurtle.analyzeBulkBarrels()
    if #sortingTurtle.barrels == 0 then return end
    
    -- Create a detailed context of all barrels and their contents
    local barrelContext = "Current barrel setup and contents:\n"
    for i, barrel in ipairs(sortingTurtle.barrels) do
        barrelContext = barrelContext .. string.format("\nBarrel %d:", i)
        if barrel.contents.isEmpty then
            barrelContext = barrelContext .. " EMPTY"
        else
            barrelContext = barrelContext .. "\nContains:"
            for _, item in ipairs(barrel.contents.items) do
                -- Include more detailed item information
                local itemName = item.name or "unknown"
                local modPrefix = itemName:match("^([^:]+):")
                local baseName = itemName:match(":(.+)$")
                
                barrelContext = barrelContext .. string.format("\n- Name: %s\n  Mod: %s\n  Base: %s\n  Display: %s",
                    itemName,
                    modPrefix or "minecraft",
                    baseName or itemName,
                    item.displayName or itemName)
            end
        end
    end
        
    -- Create a structured analysis prompt with enhanced pattern recognition
    local prompt = string.format([[
You are a Minecraft storage system analyzer with expertise in pattern recognition and item relationships.
Analyze this storage system's contents to identify logical groupings and patterns.

%s

Analysis Requirements:
1. PATTERN RECOGNITION:
   - Identify common prefixes/suffixes in item names
   - Look for items from the same mod
   - Find items with similar crafting ingredients
   - Group items used in similar game mechanics
   - Consider item progression chains

2. RELATIONSHIP TYPES:
   - Direct: Items that directly craft into each other
   - Functional: Items used for similar purposes
   - Mod-based: Items from the same mod/feature
   - Material: Items made of similar materials
   - Usage: Items commonly used together
   - Processing: Items involved in same processes

3. CONTEXTUAL GROUPING:
   - Consider existing barrel contents as hints
   - Look for established patterns
   - Identify theme consistency
   - Respect game progression
   - Account for player convenience

Response Format (STRICT JSON):
[
  {
    "barrel": <number>,
    "purpose": "<single line description>",
    "patterns": [
      "<identified pattern 1>",
      "<identified pattern 2>"
    ],
    "suggested_items": [
      {
        "name": "<item name>",
        "reason": "<brief reason for suggestion>"
      }
    ],
    "relationships": [
      {
        "type": "<relationship type>",
        "description": "<brief description>"
      }
    ]
  }
]

IMPORTANT:
- Focus on PRACTICAL groupings that make sense for players
- Consider both early-game and late-game items
- Account for mod integration patterns
- Prioritize frequently accessed items
- Think about crafting efficiency

Return ONLY the JSON array, no additional text.]], barrelContext)

    local response = llm.getGeminiResponse(prompt)
    if response then
        -- Parse the JSON response and update barrel information
        local success, analysisData = pcall(textutils.unserializeJSON, response)
        if success and analysisData then
            for _, analysis in ipairs(analysisData) do
                if analysis.barrel and analysis.purpose then
                    sortingTurtle.barrels[analysis.barrel].analysis = {
                        purpose = analysis.purpose,
                        patterns = analysis.patterns,
                        suggested_items = analysis.suggested_items,
                        relationships = analysis.relationships
                    }
                end
            end
            return true
        end
    end
    return false
end

-- Function to define categories (called only once during initial scan)
function sortingTurtle.defineCategories()
    local prompt = [[
Define a list of Minecraft item categories for sorting items into barrels.
IMPORTANT: The list MUST start with 'unknown' and end with 'problematic_items'.
Use short, simple categories like: wood, stone, ores, metals, tools, redstone, create, food, etc.
Return ONLY category names, one per line, nothing else.
Example response:
unknown
wood
stone
ores
metals
tools
redstone
create
food
problematic_items]]

    print("Requesting categories...")
    local response = llm.getGeminiResponse(prompt)
    
    if not response then
        print("Error: No response received")
        return false
    end
    
    -- Split response into lines and clean each category
    sortingTurtle.categories = {}
    for line in response:gmatch("[^\r\n]+") do
        -- Clean up each line (remove quotes, spaces)
        local category = line:gsub('"', ''):gsub("^%s*(.-)%s*$", "%1")
        if category ~= "" then
            table.insert(sortingTurtle.categories, category)
        end
    end
    
    -- Ensure unknown is first category and problematic_items is last
    local hasUnknown = false
    local hasProblematic = false
    
    for _, category in ipairs(sortingTurtle.categories) do
        if category == "unknown" then hasUnknown = true end
        if category == "problematic_items" then hasProblematic = true end
    end
    
    -- If unknown category is missing, add it at the start
    if not hasUnknown then
        table.insert(sortingTurtle.categories, 1, "unknown")
    end
    
    -- If problematic_items is missing, add it at the end
    if not hasProblematic then
        table.insert(sortingTurtle.categories, "problematic_items")
    end
    
    -- Ensure we have at least these two categories
    if #sortingTurtle.categories < 2 then
        sortingTurtle.categories = {"unknown", "problematic_items"}
    end
    
    print("\nDefined categories:")
    for _, category in ipairs(sortingTurtle.categories) do
        print("- " .. category)
    end
    return true
end

-- Function to assign categories to barrels with enhanced pattern recognition
function sortingTurtle.assignBarrelCategories()
    if sortingTurtle.numBarrels == 0 then return false end
    
    -- Create detailed context with pattern analysis
    local barrelContext = "Barrel contents and patterns:\n"
    for i, barrel in ipairs(sortingTurtle.barrels) do
        barrelContext = barrelContext .. string.format("\nBarrel %d:", i)
        if barrel.contents.isEmpty then
            barrelContext = barrelContext .. " EMPTY"
        else
            barrelContext = barrelContext .. "\nContents:"
            local itemsByMod = {}
            local patterns = {}
            
            for _, item in ipairs(barrel.contents.items) do
                local modPrefix = item.name:match("^([^:]+):")
                itemsByMod[modPrefix] = itemsByMod[modPrefix] or {}
                table.insert(itemsByMod[modPrefix], item)
                
                -- Extract patterns from item names
                local baseName = item.name:match(":(.+)$")
                if baseName then
                    -- Look for common prefixes/suffixes
                    local prefix = baseName:match("^(%w+)_")
                    local suffix = baseName:match("_(%w+)$")
                    if prefix then patterns[prefix] = (patterns[prefix] or 0) + 1 end
                    if suffix then patterns[suffix] = (patterns[suffix] or 0) + 1 end
                end
            end
            
            -- Add mod groupings
            for mod, items in pairs(itemsByMod) do
                barrelContext = barrelContext .. string.format("\nMod '%s' items:", mod)
                for _, item in ipairs(items) do
                    barrelContext = barrelContext .. string.format("\n  - %s", item.displayName or item.name)
                end
            end
            
            -- Add identified patterns
            barrelContext = barrelContext .. "\nPatterns:"
            for pattern, count in pairs(patterns) do
                if count > 1 then
                    barrelContext = barrelContext .. string.format("\n  - '%s' appears %d times", pattern, count)
                end
            end
            
            -- Add existing analysis if available
            if barrel.analysis then
                barrelContext = barrelContext .. "\nPrevious Analysis:"
                if barrel.analysis.patterns then
                    for _, pattern in ipairs(barrel.analysis.patterns) do
                        barrelContext = barrelContext .. string.format("\n  - %s", pattern)
                    end
                end
            end
        end
    end
    
    local categoriesText = table.concat(sortingTurtle.categories, "\n")
    local prompt = string.format([[
You are a Minecraft storage system categorizer with advanced pattern recognition capabilities.
Analyze the barrel contents and assign the most appropriate category to each barrel.

Available Categories:
%s

Current Storage System:
%s

Assignment Rules:
1. Pattern-Based Analysis:
   - Look for common prefixes/suffixes in item names
   - Identify items from the same mod
   - Consider crafting relationships
   - Group by material types
   - Consider game mechanics

2. Category Assignment Priority:
   - Strong patterns in existing contents
   - Mod-based groupings
   - Material consistency
   - Functional relationships
   - Crafting chains
   - Player convenience

3. Special Rules:
   - Barrel 1 MUST be assigned 'unknown' category
   - Use 'problematic_items' only for items causing issues
   - Consider both early and late game progression
   - Account for frequency of access
   - Think about crafting efficiency

Return ONLY category assignments, one per line, matching the number of barrels.
First line MUST be 'unknown'.]], 
        categoriesText, barrelContext)

    local response = llm.getGeminiResponse(prompt)
    if not response then return false end
    
    -- Process and validate assignments as before
    local assignments = {}
    for line in response:gmatch("[^\r\n]+") do
        local category = line:gsub('"', ''):gsub("^%s*(.-)%s*$", "%1")
        table.insert(assignments, category)
    end
    
    -- Ensure first barrel is unknown
    if #assignments > 0 then assignments[1] = "unknown" end
    
    -- Validate and apply assignments
    for i, category in ipairs(assignments) do
        local isValid = false
        for _, validCategory in ipairs(sortingTurtle.categories) do
            if category == validCategory then
                isValid = true
                break
            end
        end
        if not isValid then
            print(string.format("Warning: Invalid category '%s' assigned to barrel %d", category, i))
            return false
        end
    end
    
    -- Apply assignments
    sortingTurtle.barrelAssignments = {}
    for i, category in ipairs(assignments) do
        if i <= sortingTurtle.numBarrels then
            sortingTurtle.barrelAssignments[i] = category
            print(string.format("Barrel %d -> %s", i, category))
        end
    end
    
    return true
end

-- Enhanced getBarrelSlot function that uses category assignments and pattern recognition
function sortingTurtle.getBarrelSlot(itemName, itemDisplayName)
    if sortingTurtle.numBarrels == 0 then return nil end
    
    -- Extract item details for pattern matching
    local modPrefix = itemName:match("^([^:]+):") or "minecraft"
    local baseName = itemName:match(":(.+)$") or itemName
    local prefix = baseName:match("^(%w+)_")
    local suffix = baseName:match("_(%w+)$")
    
    -- Build context with pattern information
    local itemContext = string.format([[
Item Details:
Name: %s
Display Name: %s
Mod: %s
Base Name: %s
Prefix: %s
Suffix: %s

Current Barrel Setup:]], 
        itemName,
        itemDisplayName,
        modPrefix,
        baseName,
        prefix or "none",
        suffix or "none")
    
    -- Add barrel information with pattern analysis
    for i, barrel in ipairs(sortingTurtle.barrels) do
        if not barrel.contents.isEmpty then
            itemContext = itemContext .. string.format("\n\nBarrel %d (%s):", i, sortingTurtle.barrelAssignments[i] or "unassigned")
            
            -- Group items by mod and collect patterns
            local modItems = {}
            local patterns = {}
            
            for _, item in ipairs(barrel.contents.items) do
                local itemMod = item.name:match("^([^:]+):") or "minecraft"
                modItems[itemMod] = modItems[itemMod] or {}
                table.insert(modItems[itemMod], item)
                
                local itemBase = item.name:match(":(.+)$") or item.name
                local itemPrefix = itemBase:match("^(%w+)_")
                local itemSuffix = itemBase:match("_(%w+)$")
                
                if itemPrefix then patterns[itemPrefix] = (patterns[itemPrefix] or 0) + 1 end
                if itemSuffix then patterns[itemSuffix] = (itemSuffix or 0) + 1 end
            end
            
            -- Add mod-based groupings
            for mod, items in pairs(modItems) do
                itemContext = itemContext .. string.format("\nMod '%s' items:", mod)
                for _, item in ipairs(items) do
                    itemContext = itemContext .. string.format("\n  - %s", item.displayName or item.name)
                end
            end
            
            -- Add pattern information
            itemContext = itemContext .. "\nPatterns:"
            for pattern, count in pairs(patterns) do
                if count > 1 then
                    itemContext = itemContext .. string.format("\n  - '%s' appears %d times", pattern, count)
                end
            end
            
            -- Add existing analysis if available
            if barrel.analysis then
                itemContext = itemContext .. "\nAnalysis:"
                if barrel.analysis.patterns then
                    for _, pattern in ipairs(barrel.analysis.patterns) do
                        itemContext = itemContext .. string.format("\n  - %s", pattern)
                    end
                end
            end
        end
    end
    
    local categoriesText = table.concat(sortingTurtle.categories, "\n")
    local prompt = string.format([[
You are a Minecraft item categorization expert with advanced pattern recognition capabilities.
Determine the most appropriate barrel for this item based on patterns, relationships, and existing contents.

Available Categories:
%s

%s

Analysis Requirements:
1. Pattern Matching:
   - Check for matching mod prefixes
   - Look for common name patterns (prefixes/suffixes)
   - Consider item name similarities
   - Analyze material types
   - Check crafting relationships

2. Priority Factors:
   - Exact mod matches
   - Strong pattern matches
   - Similar item groupings
   - Logical gameplay relationships
   - Crafting efficiency
   - Player convenience

3. Special Rules:
   - If no clear match is found, use Barrel 1 (unknown)
   - Consider both early and late game items
   - Account for mod integration
   - Think about frequency of access
   - Respect existing barrel patterns

Return ONLY the barrel number (1-%d).
If unsure, return 1 (unknown barrel).]], 
        categoriesText,
        itemContext,
        sortingTurtle.numBarrels)
    
    local response = llm.getGeminiResponse(prompt)
    if not response then 
        print("No category response received, defaulting to unknown")
        return 1
    end
    
    -- Clean up and validate the response
    local barrelNumber = tonumber(response:match("^%s*(%d+)%s*$"))
    if not barrelNumber or barrelNumber < 1 or barrelNumber > sortingTurtle.numBarrels then
        print(string.format("Invalid barrel number received: %s, using unknown", response))
        return 1
    end
    
    print(string.format("Selected barrel %d for item %s", barrelNumber, itemDisplayName or itemName))
    return barrelNumber
end

-- Function to check if block in front is a valid storage
function sortingTurtle.isValidInputStorage()
    local success, data = turtle.inspect()
    if success and data then
        return data.name == "minecraft:chest" or 
               data.name == "minecraft:barrel" or 
               data.name:find("chest") or 
               data.name:find("barrel") or 
               data.name:find("storage")
    end
    return false
end

-- Function to handle problematic items by assigning them to the problematic_items category
function sortingTurtle.handleProblematicItem(itemName, itemDisplayName)
    print(string.format("\nHandling problematic item: %s", itemDisplayName or itemName))
    
    -- Find a barrel assigned to problematic_items category
    for barrelNum, category in pairs(sortingTurtle.barrelAssignments) do
        if category == "problematic_items" then
            -- Add item to problematic items list if not already there
            if not sortingTurtle.problematicItems[itemName] then
                sortingTurtle.problematicItems[itemName] = {
                    name = itemName,
                    displayName = itemDisplayName,
                    attempts = 1
                }
            end
            
            print(string.format("Assigning to problematic items barrel %d", barrelNum))
            return true
        end
    end
    
    -- If no problematic_items barrel found, try to find an empty barrel to assign
    for barrelNum, barrel in ipairs(sortingTurtle.barrels) do
        if barrel.contents.isEmpty then
            -- Assign this barrel to problematic_items category
            sortingTurtle.barrelAssignments[barrelNum] = "problematic_items"
            print(string.format("Assigned empty barrel %d to problematic items", barrelNum))
            return true
        end
    end
    
    print("No available barrel for problematic items!")
    return false
end

-- Modify sortItems function to handle problematic items
function sortingTurtle.sortItems()
    -- Clear movement history before starting to sort
    sortingTurtle.moveHistory = {}
    
    -- Do initial scan if we haven't done one yet
    if sortingTurtle.numBarrels == 0 then
        sortingTurtle.scanBarrels()
        if sortingTurtle.numBarrels == 0 then 
            print("Error: No barrels found during scan!")
            return 
        end
    end
    
    print("\nChecking input storage...")
    
    -- Check if we're facing a valid storage block
    if not sortingTurtle.isValidInputStorage() then
        print("No chest or barrel detected in front! Please ensure the turtle is facing the input storage.")
        return
    end

    -- Try to access the storage
    local hasItems = false
    for slot = 1, 16 do
        if turtle.suck() then
            hasItems = true
            turtle.drop() -- Put it back for now
            break
        end
    end

    -- If no items to sort, return to initial position
    if not hasItems then
        print("No items found in input storage.")
        return
    end

    print("Found items to sort!")
    
    -- Process items in the storage
    local itemsMoved = false
    local itemsSorted = 0
    local itemsToUnknown = 0
    
    while true do
        -- Clear movement history before processing each item
        sortingTurtle.moveHistory = {}
        
        -- Try to get an item
        if not turtle.suck() then
            break  -- No more items to sort
        end
        
        local itemDetail = turtle.getItemDetail()
        if itemDetail then
            local itemCategory = sortingTurtle.getItemCategory(itemDetail.name)
            print(string.format("\nProcessing: %s (Category: %s)", 
                itemDetail.displayName or itemDetail.name,
                itemCategory))
            
            local barrelSlot = sortingTurtle.getBarrelSlot(itemDetail.name, itemDetail.displayName)
            -- barrelSlot will always be valid now (at minimum it will be 1 for unknown)
            
            print(string.format("Moving to barrel %d...", barrelSlot))
            -- Move to barrel and drop item
            if sortingTurtle.moveToBarrel(barrelSlot) then
                if turtle.drop() then
                    itemsMoved = true
                    if barrelSlot == 1 then
                        itemsToUnknown = itemsToUnknown + 1
                    else
                        itemsSorted = itemsSorted + 1
                    end
                    print(string.format("Stored in barrel %d", barrelSlot))
                else
                    print("Warning: Could not store item in barrel!")
                    -- If we can't store in target barrel, use unknown barrel
                    sortingTurtle.returnToInitial()
                    if sortingTurtle.moveToBarrel(1) then
                        if turtle.drop() then
                            itemsToUnknown = itemsToUnknown + 1
                            print("Stored in unknown barrel")
                        else
                            print("Error: Could not store in unknown barrel!")
                        end
                    end
                end
            end
            
            -- Return to initial position using movement history
            sortingTurtle.returnToInitial()
        end
        
        -- Check if there are more items to process
        local hasMoreItems = false
        for slot = 1, 16 do
            if turtle.suck() then
                hasMoreItems = true
                turtle.drop() -- Put it back for now
                break
            end
        end
        
        -- If no more items, break the loop
        if not hasMoreItems then
            break
        end
    end
    
    -- Print summary
    if itemsMoved then
        print("\nSorting complete:")
        print(string.format("- Items sorted to categories: %d", itemsSorted))
        print(string.format("- Items sent to unknown: %d", itemsToUnknown))
    else
        print("\nNo items were sorted")
    end
end

-- Function to check if there are items in the input storage without taking them
function sortingTurtle.hasItemsInStorage()
    -- Try to detect items without actually taking them
    local success, data = turtle.inspect()
    if success and data then
        -- Check if it's a valid storage block
        if data.name == "minecraft:chest" or 
           data.name == "minecraft:barrel" or 
           data.name:find("chest") or 
           data.name:find("barrel") or 
           data.name:find("storage") then
            
            -- Peek at the inventory without removing items
            if turtle.suck() then
                turtle.drop()  -- Put it right back
                return true
            end
        end
    end
    return false
end

-- Optimized scan function that only scans in the direction of barrels
function sortingTurtle.scanBarrels()
    print("\n=== Starting Barrel Scan ===")
    sortingTurtle.barrels = {}
    sortingTurtle.numBarrels = 0
    local steps = 0
    
    -- Clear movement history at start of scan
    sortingTurtle.moveHistory = {}
    
    -- Check fuel before starting
    if not sortingTurtle.checkFuel() then
        print("Cannot scan: Insufficient fuel!")
        return
    end
    
    -- Turn left to face the path (no need to back away)
    while sortingTurtle.position.facing ~= 3 do  -- 3 is west (left)
        turtle.turnLeft()
        sortingTurtle.addToHistory("turnLeft")
        sortingTurtle.updatePosition("turnLeft")
    end
    
    -- Move forward one step to be in line with the barrels
    if turtle.forward() then
        sortingTurtle.addToHistory("forward")
        sortingTurtle.updatePosition("forward")
    else
        print("Cannot move forward to start scanning!")
        return
    end
    
    -- Single pass: Move and scan barrels
    print("Scanning for barrels...")
    while steps < sortingTurtle.config.MAX_STEPS do
        -- Turn right to face potential barrel
        turtle.turnRight()
        sortingTurtle.addToHistory("turnRight")
        sortingTurtle.updatePosition("turnRight")
        
        -- Check for barrel
        local success, data = turtle.inspect()
        if success and data then
            if string.find(data.name or "", "barrel") or string.find(data.name or "", "storage") then
                -- Read barrel contents immediately
                local contents = sortingTurtle.readBarrel()
                local barrelInfo = {
                    position = steps,
                    contents = contents,
                    blockData = data
                }
                
                table.insert(sortingTurtle.barrels, barrelInfo)
                sortingTurtle.numBarrels = sortingTurtle.numBarrels + 1
                
                -- Print basic barrel info
                print(string.format("\nFound barrel %d:", sortingTurtle.numBarrels))
                print(string.format("- Contents: %s", contents.isEmpty and "EMPTY" or "Items present"))
            end
        end
        
        -- Turn back to face the path
        turtle.turnLeft()
        sortingTurtle.addToHistory("turnLeft")
        sortingTurtle.updatePosition("turnLeft")
        
        -- Try to move forward
        if turtle.forward() then
            sortingTurtle.addToHistory("forward")
            sortingTurtle.updatePosition("forward")
            steps = steps + 1
        else
            break
        end
    end
    
    -- Return to initial position using movement history
    sortingTurtle.returnToInitial()
    
    -- Print barrel summary
    if sortingTurtle.numBarrels > 0 then
        print(string.format("\nFound %d barrels", sortingTurtle.numBarrels))
        
        -- Define categories if this is the first scan (categories table is empty)
        if next(sortingTurtle.categories) == nil then
            print("\nDefining storage categories...")
            if sortingTurtle.defineCategories() then
                print("Categories defined successfully!")
            else
                print("Error: Could not define categories!")
                return
            end
        end
        
        -- Assign categories to barrels
        print("\nAssigning categories to barrels...")
        if sortingTurtle.assignBarrelCategories() then
            print("Category assignment complete!")
            -- Print category assignments
            for barrel, category in pairs(sortingTurtle.barrelAssignments) do
                print(string.format("Barrel %d: %s", barrel, category))
            end
        else
            print("Warning: Could not assign categories to barrels")
        end
    else
        print("\nNo barrels found! Please set up barrels and restart.")
    end
    
    sortingTurtle.lastScanTime = os.epoch("local")
end

-- Main loop
print("=== Smart Sorting Turtle v2.9 ===")
print("Setup Instructions:")
print("1. Place input storage (chest or barrel)")
print("2. Place sorting barrels in a line to the left of the input storage")
print("3. Place turtle directly behind the input storage, facing it")
print("4. Ensure all barrels are accessible")
print("\nLayout should look like this:")
print("[S][B][B][B]...")
print("[T]")
print("Where: T=Turtle (facing up), S=Input Storage, B=Sorting Barrels")

-- Do initial barrel scan
print("\nPerforming initial barrel scan...")
sortingTurtle.scanBarrels()

if sortingTurtle.numBarrels == 0 then
    print("\nNo barrels found! Please set up barrels and restart the program.")
    return sortingTurtle
end

print("\nReady to sort items!")
print("Waiting for items in input storage...")

local lastCheckTime = 0
local IDLE_CHECK_INTERVAL = 2  -- Check for items every 2 seconds when idle

while true do
    local currentTime = os.epoch("local")
    
    -- Check if there are items to sort
    if sortingTurtle.hasItemsInStorage() then
        print("\nDetected items in storage!")
        
        -- Scan barrels and update categories every time we find new items
        print("Scanning barrels and updating categories...")
        sortingTurtle.scanBarrels()
        if sortingTurtle.numBarrels == 0 then
            print("Error: No barrels found during scan!")
            print("Please check barrel setup and restart the program.")
            break
        end
        
        -- Sort the items
        sortingTurtle.sortItems()
        print("\nWaiting for more items...")
        lastCheckTime = currentTime
    else
        -- If we haven't checked recently, update the idle message
        if currentTime - lastCheckTime > 30 then  -- Show message every 30 seconds
            print("Waiting for items... (Press Ctrl+T to exit)")
            lastCheckTime = currentTime
        end
        os.sleep(IDLE_CHECK_INTERVAL)  -- Wait before checking again
    end
end

return sortingTurtle

