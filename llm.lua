-- Ensure HTTP is enabled in the ComputerCraft configuration

-- Your Gemini API key
local apiKey = "AIzaSyBovnTYV5SFtsB-Gk5RAQjjPFFKpsZ5SCw"

-- Function to send a prompt to the Gemini API and get a response
function getGeminiResponse(prompt)
    local url = "https://api.gemini.com/v1/llm"  -- Replace with the actual Gemini API endpoint
    local headers = {
        ["Content-Type"] = "application/json",
        ["Authorization"] = "Bearer " .. apiKey
    }
    local body = textutils.serializeJSON({
        prompt = prompt
    })

    local response = http.post(url, body, headers)
    if response then
        local content = response.readAll()
        response.close()
        local data = textutils.unserializeJSON(content)
        return data.response  -- Adjust based on the actual response structure
    else
        print("Failed to fetch data from Gemini API")
        return nil
    end
end

-- Main interactive loop
while true do
    -- Ask the user for a prompt
    print("Enter your prompt (or type 'exit' to quit):")
    local userPrompt = read()

    -- Exit the loop if the user types 'exit'
    if userPrompt == "exit" then
        break
    end

    -- Get the response from the Gemini API
    local response = getGeminiResponse(userPrompt)
    if response then
        print("Gemini API response: " .. response)
    else
        print("No response received.")
    end
end