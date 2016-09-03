Sock = require 'libs.sock'

function resetLog()
    logInfo = {
        gcmemory = {min = nil, max = nil, total = 0},
        inData   = {min = nil, max = nil, total = 0, previous = 0},
        outData  = {min = nil, max = nil, total = 0, previous = 0}
    }
end

function setLog()
    -- log garbage collector memory
    local memory = collectgarbage("count")

    logInfo.gcmemory.total = logInfo.gcmemory.total + memory/10

    if not logInfo.gcmemory.min or memory < logInfo.gcmemory.min then
        logInfo.gcmemory.min = memory
    end
    if not logInfo.gcmemory.max or memory > logInfo.gcmemory.max then
        logInfo.gcmemory.max = memory
    end

    -- log received data
    local totalReceivedData = server:getTotalReceivedData()

    local deltaReceived = totalReceivedData - logInfo.inData.previous
    logInfo.inData.previous = totalReceivedData

    logInfo.inData.total = logInfo.inData.total + deltaReceived

    if not logInfo.inData.min or deltaReceived < logInfo.inData.min then
        logInfo.inData.min = deltaReceived
    end

    if not logInfo.inData.max or deltaReceived > logInfo.inData.max then
        logInfo.inData.max = deltaReceived
    end

    -- log sent data
    local totalSentData = server:getTotalSentData()

    local deltaSent = totalSentData - logInfo.outData.previous
    logInfo.outData.previous = totalSentData

    logInfo.outData.total = logInfo.outData.total + deltaSent

    if not logInfo.outData.min or deltaSent < logInfo.outData.min then
        logInfo.outData.min = deltaSent
    end

    if not logInfo.outData.max or deltaSent > logInfo.outData.max then
        logInfo.outData.max = deltaSent
    end
end

-- prints a log of data usage, garbage collector memory, and active servers
-- prints to console and saves to a file
function printLog()
    local gcAvg = logInfo.gcmemory.total / logTime
    local inDataAvg = logInfo.inData.total / logTime
    local outDataAvg = logInfo.outData.total / logTime

    local logMessage

    logMessage = (string.format("Log of the last %.2fs", logTime))
    logMessage = logMessage .. "\r\n" .. (string.format("[%.2fs] Garbage collector memory: Min (%.2fKB), Avg (%.2fKB), Max (%.2fKB)", runTime, logInfo.gcmemory.min, gcAvg, logInfo.gcmemory.max))
    logMessage = logMessage .. "\r\n" .. (string.format("[%.2fs] Received data: Min (%.2fKB), Avg (%.2fKB), Max (%.2fKB), Total (%.2fKB)", runTime, logInfo.inData.min/1024, inDataAvg/1024, logInfo.inData.max/1024, logInfo.inData.total/1024))
    logMessage = logMessage .. "\r\n" .. (string.format("[%.2fs] Sent data: Min (%.2fKB), Avg (%.2fKB), Max (%.2fKB), Total (%.2fKB)", runTime, logInfo.outData.min/1024, outDataAvg/1024, logInfo.outData.max/1024, logInfo.outData.total/1024))
    logMessage = logMessage .. "\r\n" .. (string.format("[%.2fs] Server run time: (%.2fs), Total Received data: (%.2fKB), Total Sent data: (%.2fKB)", runTime, runTime, server:getTotalReceivedData()/1024, server:getTotalSentData()/1024))
    logMessage = logMessage .. "\r\n"

    -- include a list of all connected servers
    for i = 1, #addressList do
        logMessage = logMessage .. " Active servers:"
        logMessage = logMessage .. "\r\n" .. "Name: " .. addressList[i].name .. ", Address: " .. addressList[i].address .. ", Players: " .. addressList[i].players .. ", BeatTime: " .. addressList[i].beatTime 
    end
    logMessage = logMessage .. "\r\n"

    print(logMessage)

    local file, msg = io.open(logPath, "a")
    if file then
        file:write(logMessage)
        file:close()
    else
        print("Could not write to file: " .. msg)
    end
end

-- if an error is thrown, print and save error to file
function love.errhand(errorMsg)
    print("Error detected: " .. errorMsg)

    local file, msg = io.open(logPath, "a")
    if file then
        file:write(errorMsg)
        file:close()
    else
        print("Could not write to file: " .. msg)
    end
end

function love.load()
    logPath = "log.txt"

    -- how often to log in seconds
    logTime = 3600 -- log once every hour
    logTimer = logTime
    -- time for a server to not be heard from before it is removed
    timeout = 30
    -- roughly half of max FPS
    HalfFPSLimit = 5

    runTime = 0

    -- port to bind to and max peers
    server = Sock.newServer("*", 22123, 64)

    addressList = {}
    resetLog()

    -- activated when a server or client connects to the master server
    server:on("connect", function(data, client, peer)
        local clientAddress = string.gsub(tostring(peer), ":.*", "")

        -- it is a server
        if data == 1 then
            print("Server connected: " .. clientAddress)

        -- it is a client
        elseif data == 2 then
            -- send them the address list then disconnect
            client:emit("addressList", addressList)
            print("Sending server list to a client")
        end
    end)

    -- after a server is connected, it will idenfity with a name
    server:on("identify", function(data, client, peer)
        local clientAddress = string.gsub(tostring(peer), ":.*", "")

        -- tostring(peer) is in the format of IP:Port, get the IP from that
        -- once a connected server has identified a username, then add the server to the list
        table.insert(addressList, {address = clientAddress, players = 1, beatTime = 0, name = data})
        print("Server connected: " .. clientAddress)
        print(clientAddress .. " identified as: " .. data)

        server:emitToAll("addressList", addressList)
    end)

    -- servers must routinely send their current playerCount or they are removed from the list
    server:on("heartbeat", function(data, client, peer)
        local clientAddress = string.gsub(tostring(peer), ":.*", "")

        print("Heartbeat from " .. clientAddress)

        local playerCount, name = data.playerCount, data.name

        -- find the server based on clientAddress
        local found = false
        for i = 1, #addressList do
            if addressList[i].address == clientAddress then
                -- update the players and reset timeout
                addressList[i].players = playerCount
                addressList[i].beatTime = 0
                found = true
                break
            end
        end

        if not found then
            -- server exceeded timeout, but is reconnected
            table.insert(addressList, {address = clientAddress, players = playerCount, beatTime = 0, name = name})
            print("Reconnected: " .. clientAddress)
        end

        server:emitToAll("addressList", addressList)
    end)

    -- 
    server:on("disconnect", function(data, client, peer)
        -- it is a client
        if data == 2 then

        -- otherwise, it is a server OR a client which disconnected by abnormal means
        else
            local clientAddress = string.gsub(tostring(peer), ":.*", "")

            print("Disconnnected: " .. clientAddress)

            for i = #addressList, 1, -1 do
                if addressList[i].address == clientAddress then
                    table.remove(addressList, i)
                end
            end
        end
    end)
end

function love.update(dt)
    if dt < 1/HalfFPSLimit then
        love.timer.sleep(1/HalfFPSLimit - dt)
    end

    server:update()

    -- delete a server from the list if it is above timeout threshold
    for i = #addressList, 1, -1 do
        if addressList[i].beatTime >= timeout then
            table.remove(addressList, i)
            server:emitToAll("addressList", addressList)
        end
    end

    -- increment each server's time
    for i = 1, #addressList do
        addressList[i].beatTime = addressList[i].beatTime + dt
    end

    if logTimer <= 0 then
        logTimer = logTime - runTime % logTime
        printLog()
        resetLog()
    end

    logTimer = logTimer - dt
    runTime = runTime + dt

    -- update per-frame log values
    setLog()
end