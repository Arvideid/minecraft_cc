-- Import the LLM module
local llm = require("llm")

-- Function to move the turtle forward
local function moveForward()
    if turtle.forward() then
        print("Moved forward.")
    else
        print("Cannot move forward.")
    end
end

-- Function to turn the turtle left
local function turnLeft()
    turtle.turnLeft()
    print("Turned left.")
end

-- Function to turn the turtle right
local function turnRight()
    turtle.turnRight()
    print("Turned right.")
end

-- Function to check for a barrel in front
local function checkForBarrel()
    local success, data = turtle.inspect()
    if success and data.name == "minecraft:barrel" then
        print("Barrel detected.")
        return true
    else
        print("No barrel detected.")
        return false
    end
end

-- Function to check fuel level and refuel if needed
local function checkFuel()
    if turtle.getFuelLevel() == 0 then
        print("Out of fuel!")
        return false
    end
    return true
end

-- Main function to control the turtle
local function controlTurtle()
    while true do
        -- Check fuel level
        if not checkFuel() then
            print("Please refuel the turtle.")
            os.sleep(2)
        else
            -- Use LLM to decide what to do
            local prompt = "The turtle is ready to move. Provide a single-word command: forward, left, right, or stop."
            local response = llm.getGeminiResponse(prompt)
            if response then
                print("LLM response: " .. response)
                -- Implement actions based on LLM response
                if response == "forward" then
                    moveForward()
                elseif response == "left" then
                    turnLeft()
                elseif response == "right" then
                    turnRight()
                elseif response == "stop" then
                    print("Stopping turtle.")
                    break
                else
                    print("Unknown command from LLM.")
                end
            else
                print("No response from LLM.")
            end
        end

        -- Add a delay to prevent spamming
        os.sleep(2)
    end
end

-- Start the turtle control
controlTurtle()
