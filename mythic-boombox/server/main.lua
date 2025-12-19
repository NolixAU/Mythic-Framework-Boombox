local _boomboxes = {}
local _pendingPlacement = {}
local _nextId = 1

AddEventHandler("Boombox:Shared:DependencyUpdate", RetrieveComponents)
function RetrieveComponents()
    Fetch = exports["mythic-base"]:FetchComponent("Fetch")
    Logger = exports["mythic-base"]:FetchComponent("Logger")
    Callbacks = exports["mythic-base"]:FetchComponent("Callbacks")
    Execute = exports["mythic-base"]:FetchComponent("Execute")
    Inventory = exports["mythic-base"]:FetchComponent("Inventory")
end

local function getVolume(volume)
    volume = math.floor(tonumber(volume) or Config.DefaultVolume)
    volume = math.max(Config.MinVolume, math.min(Config.MaxVolume, volume))
    return volume
end

local function extractYouTubeId(url)
    if not url then
        return nil
    end

    -- Handle youtu.be/<id>
    local shortId = url:match("youtu%.be/([%w%-_]+)")
    if shortId then
        return shortId
    end

    -- Handle shorts/<id>
    local shortsId = url:match("shorts/([%w%-_]+)")
    if shortsId then
        return shortsId
    end

    -- Handle youtube.com/watch?v=<id>
    local queryId = url:match("[?&]v=([%w%-_]+)")
    if queryId then
        return queryId
    end

    -- Handle embed/<id>
    local embedId = url:match("embed/([%w%-_]+)")
    if embedId then
        return embedId
    end

    return nil
end

local function pickAudioStream(audioStreams)
    if type(audioStreams) ~= "table" then
        return nil
    end

    local bestStream = nil

    for _, stream in ipairs(audioStreams) do
        if stream and type(stream) == "table" and stream.url then
            if stream.itag == 140 then
                return stream.url
            end

            if stream.audioOnly == true or (stream.mimeType and stream.mimeType:find("audio/")) then
                local bitrate = tonumber(stream.bitrate) or 0

                if bestStream == nil then
                    bestStream = { url = stream.url, bitrate = bitrate }
                elseif bitrate > bestStream.bitrate then
                    bestStream = { url = stream.url, bitrate = bitrate }
                end
            end

            if bestStream == nil then
                bestStream = { url = stream.url, bitrate = tonumber(stream.bitrate) or 0 }
            end
        end
    end

    return bestStream and bestStream.url or nil
end

local function normalizeTrackUrl(url, cb)
    local videoId = extractYouTubeId(url)
    if not videoId then
        cb(url)
        return
    end

    local apiUrl = ("https://piped.video/api/v1/streams/%s"):format(videoId)

    PerformHttpRequest(apiUrl, function(status, response)
        if status ~= 200 or not response or response == "" then
            cb(url)
            return
        end

        local ok, data = pcall(json.decode, response)
        if not ok or type(data) ~= "table" then
            cb(url)
            return
        end

        local streamUrl = pickAudioStream(data.audioStreams)
        cb(streamUrl or url)
    end, "GET")
end

local function canControlBoombox(source, boombox)
    if boombox == nil then
        return false
    end

    local plyr = Fetch:Source(source)
    local char = plyr?.GetData and plyr:GetData("Character")
    local sid = char?.GetData and char:GetData("SID")

    if sid == nil then
        return false
    end

    return sid == boombox.owner or (plyr.Permissions:IsAdmin() or plyr.Permissions:IsStaff())
end

AddEventHandler("Core:Shared:Ready", function()
    exports["mythic-base"]:RequestDependencies("Boombox", {
        "Fetch",
        "Logger",
        "Callbacks",
        "Execute",
        "Inventory",
    }, function(error)
        if #error > 0 then
            exports["mythic-base"]:FetchComponent("Logger"):Critical("Boombox", "Failed To Load All Dependencies")
            return
        end

        RetrieveComponents()

        Inventory.Items:RegisterUse("boombox", "Boombox", function(source, item)
            if _pendingPlacement[source] ~= nil then
                Execute:Client(source, "Notification", "Error", "Already placing a boombox")
                return
            end

            _pendingPlacement[source] = {
                owner = item.Owner,
                slot = item.Slot,
                invType = item.invType,
                name = item.Name,
            }

            TriggerClientEvent("Boombox:Client:StartPlacement", source)
        end)

        Callbacks:RegisterServerCallback("Boombox:GetPlaced", function(source, data, cb)
            cb(_boomboxes)
        end)
    end)
end)

AddEventHandler("playerDropped", function()
    _pendingPlacement[source] = nil
end)

RegisterNetEvent("Boombox:Server:PlacementCancelled", function()
    _pendingPlacement[source] = nil
end)

RegisterNetEvent("Boombox:Server:PlacementFinished", function(coords)
    local src = source
    local pending = _pendingPlacement[src]
    if pending == nil then
        return
    end

    local removed = Inventory.Items:RemoveSlot(pending.owner, pending.name, 1, pending.slot, pending.invType)
    _pendingPlacement[src] = nil

    if not removed then
        Execute:Client(src, "Notification", "Error", "Unable to place boombox")
        return
    end

    local id = _nextId
    _nextId += 1

    local boombox = {
        id = id,
        owner = pending.owner,
        coords = coords.coords or coords,
        rotation = coords.rotation or 0.0,
        volume = Config.DefaultVolume,
    }

    _boomboxes[id] = boombox

    TriggerClientEvent("Boombox:Client:Create", -1, boombox)
end)

RegisterNetEvent("Boombox:Server:SetTrack", function(id, url)
    local src = source
    local boombox = _boomboxes[id]
    if boombox == nil or url == nil or #url <= 0 or not canControlBoombox(src, boombox) then
        return
    end

    normalizeTrackUrl(url, function(streamUrl)
        if streamUrl == nil then
            Execute:Client(src, "Notification", "Error", "Unable to load that link")
            return
        end

        boombox.track = streamUrl

        TriggerClientEvent("Boombox:Client:Play", -1, boombox)
        Execute:Client(src, "Notification", "Success", "Now playing on boombox")
    end)
end)

RegisterNetEvent("Boombox:Server:SetVolume", function(id, volume)
    local src = source
    local boombox = _boomboxes[id]
    if boombox == nil or not canControlBoombox(src, boombox) then
        return
    end

    boombox.volume = getVolume(volume)

    TriggerClientEvent("Boombox:Client:UpdateVolume", -1, id, boombox.volume)
    Execute:Client(src, "Notification", "Success", ("Volume set to %s"):format(boombox.volume))
end)

RegisterNetEvent("Boombox:Server:Pickup", function(id)
    local src = source
    local boombox = _boomboxes[id]
    if boombox == nil then
        return
    end

    local plyr = Fetch:Source(src)
    local char = plyr?.GetData and plyr:GetData("Character")
    local sid = char?.GetData and char:GetData("SID")

    if sid == nil or not canControlBoombox(src, boombox) then
        Execute:Client(src, "Notification", "Error", "You cannot pick this up")
        return
    end

    _boomboxes[id] = nil

    Inventory:AddItem(sid, "boombox", 1, {}, 1)
    TriggerClientEvent("Boombox:Client:Remove", -1, id)
    Execute:Client(src, "Notification", "Success", "Boombox picked up")
end)

RegisterNetEvent("Boombox:Server:Stop", function(id)
    local src = source
    local boombox = _boomboxes[id]
    if boombox == nil or not canControlBoombox(src, boombox) then
        return
    end

    boombox.track = nil

    TriggerClientEvent("Boombox:Client:Stopped", -1, id)
    Execute:Client(src, "Notification", "Success", "Stopped boombox")
end)