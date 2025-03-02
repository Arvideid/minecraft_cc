if http then
    print("HTTP API is available.")
    local response = http.get("http://www.example.com")
    if response then
        print("HTTP requests are enabled.")
        response.close()
    else
        print("HTTP requests are not enabled.")
    end
else
    print("HTTP API is not available.")
end 