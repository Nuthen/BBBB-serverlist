Sock    = require 'libs.sock'
Inspect = require 'libs.inspect'

function love.load()
    timeout = 30

    server = Sock.newServer("*", 22123, 64)

    addressList = {}

    server:on("connect", function(data, client, peer)
        -- it is a server
        if data == 1 then
            local clientAddress = string.gsub(tostring(peer), ":.*", "")
            table.insert(addressList, {address = clientAddress, players = 1, beatTime = 0, name = ""})
            print("Server connected: " .. clientAddress)

        -- it is a client
        elseif data == 2 then
            -- send them the address list then disconnect
            client:emit("addressList", addressList)
            print("Sending server list to a client")
        end
    end)

    server:on("identify", function(data, client, peer)
        local clientAddress = string.gsub(tostring(peer), ":.*", "")

        for i = 1, #addressList do
            if addressList[i].address == clientAddress then
                addressList[i].name = data
                print(clientAddress .. " identified as: " .. data)
            end
        end

        server:emitToAll("addressList", addressList)
    end)

    server:on("heartbeat", function(data, client, peer)
        local clientAddress = string.gsub(tostring(peer), ":.*", "")

        print("Heartbeat from " .. clientAddress)

        local playerCount, name = data.playerCount, data.name

        local found = false

        for i = 1, #addressList do
            if addressList[i].address == clientAddress then
                addressList[i].players = playerCount
                addressList[i].beatTime = 0
                found = true
                break
            end
        end

        if not found then
            table.insert(addressList, {address = clientAddress, players = playerCount, beatTime = 0, name = name})
            print("Reconnected: " .. clientAddress)
        end


        server:emitToAll("addressList", addressList)
    end)

    server:on("disconnect", function(data, client, peer)
        local clientAddress = string.gsub(tostring(peer), ":.*", "")

        print("Disconnnected: " .. clientAddress)

        for i = #addressList, 1, -1 do
            if addressList[i].address == clientAddress then
                table.remove(addressList, i)
            end
        end
    end)
end

function love.update(dt)
    server:update()

    for i = #addressList, 1, -1 do
        if addressList[i].beatTime >= timeout then
            table.remove(addressList, i)
            server:emitToAll("addressList", addressList)
        end
    end

    for i = 1, #addressList do
        addressList[i].beatTime = addressList[i].beatTime + dt
    end
end

function love.draw()
    love.graphics.print(Inspect(addressList), 5, 5)

    love.graphics.setColor(255, 255, 255)
    local x, y = 300, 5
    local spacing = 35
    local textMessages = {
        "FPS: "..love.timer.getFPS(),
        "Memory usage: " .. math.floor(collectgarbage("count")/1000) .. "MB",
        ("Total received data: %.2f KB"):format(server:getTotalReceivedData()/1000),
        ("Total sent data: %.2f KB"):format(server:getTotalSentData()/1000),
    }

    for i, text in ipairs(textMessages) do
        love.graphics.setColor(255, 255, 255)
        love.graphics.print(text, math.floor(x), math.floor(y + (i-1)*spacing))
    end
end