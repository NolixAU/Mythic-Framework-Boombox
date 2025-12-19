local _boomboxes = {}
local _songPromise = nil
local _volumePromise = nil
local _xsound = nil

AddEventHandler("Boombox:Shared:DependencyUpdate", RetrieveComponents)
function RetrieveComponents()
    Callbacks = exports["mythic-base"]:FetchComponent("Callbacks")
    Targeting = exports["mythic-base"]:FetchComponent("Targeting")
    Input = exports["mythic-base"]:FetchComponent("Input")
    ObjectPlacer = exports["mythic-base"]:FetchComponent("ObjectPlacer")
end

local function getXSound()
    if _xsound ~= nil then
        return _xsound
    end

    local resource = Config.SoundResource or 'xsound'
    _xsound = exports[resource]
    return _xsound
end

local function loadModel(model)
    if not HasModelLoaded(model) then
        RequestModel(model)
        while not HasModelLoaded(model) do
            Wait(10)
        end
    end
end

local function xsoundExists(soundId)
    local xsound = getXSound()
    if not xsound then
        return false
    end

    if xsound.soundExists then
        local ok, exists = pcall(function()
            return xsound:soundExists(soundId)
        end)

        if ok then
            return exists
        end
    end

    if xsound.isPlaying then
        local ok, exists = pcall(function()
            return xsound:isPlaying(soundId)
        end)

        if ok then
            return exists
        end
    end

    return false
end

local function xsoundDistance(soundId, distance)
    local xsound = getXSound()
    if not xsound then
        return
    end

    if xsound.Distance then
        pcall(function()
            xsound:Distance(soundId, distance)
        end)
    elseif xsound.distance then
        pcall(function()
            xsound:distance(soundId, distance)
        end)
    end
end

local function xsoundSetVolume(soundId, volume)
    local xsound = getXSound()
    if not xsound then
        return
    end

    if xsound.setVolumeMax then
        if pcall(function()
            xsound:setVolumeMax(soundId, volume)
        end) then
            return
        end
    end

    if xsound.setVolume then
        if pcall(function()
            xsound:setVolume(soundId, volume)
        end) then
            return
        end
    end

    if xsound.SetVolume then
        pcall(function()
            xsound:SetVolume(soundId, volume)
        end)
    end
end

local function hasControl(owner)
    local char = LocalPlayer.state.Character
    local sid = char and char.GetData and char:GetData("SID")
    return owner ~= nil and (sid == owner or LocalPlayer.state.isAdmin or LocalPlayer.state.isStaff)
end

local function normalizeCoords(coords)
    if coords and coords.x then
        return vector3(coords.x + 0.0, coords.y + 0.0, coords.z + 0.0)
    end

    return coords
end

local function stopBoomboxSound(id)
    local xsound = getXSound()
    if not xsound then
        return
    end

    local soundId = string.format("boombox-%s", id)
    if not xsoundExists(soundId) then
        return
    end

    if xsound.Destroy then
        pcall(function()
            xsound:Destroy(soundId)
        end)
    elseif xsound.destroy then
        pcall(function()
            xsound:destroy(soundId)
        end)
    end
end

local function startBoomboxSound(id)
    local entry = _boomboxes[id]
    if entry == nil or entry.track == nil then
        return
    end

    local xsound = getXSound()
    if not xsound then
        return
    end

    local soundId = string.format("boombox-%s", id)
    local volume = (entry.volume or Config.DefaultVolume) / 100.0

    stopBoomboxSound(id)

    local played = false

    if xsound.PlayUrlPos then
        played = pcall(function()
            xsound:PlayUrlPos(soundId, entry.track, volume, entry.coords, true)
        end)
    elseif xsound.playUrlPos then
        played = pcall(function()
            xsound:playUrlPos(soundId, entry.track, volume, entry.coords, true)
        end)
    elseif xsound.PlayUrl then
        played = pcall(function()
            xsound:PlayUrl(soundId, entry.track, volume, true)
        end)
    elseif xsound.playUrl then
        played = pcall(function()
            xsound:playUrl(soundId, entry.track, volume, true)
        end)
    end

    if not played then
        return
    end

    xsoundDistance(soundId, Config.MaxRange)
    xsoundSetVolume(soundId, volume)
end

local function setupTargeting(id)
    local entry = _boomboxes[id]
    if entry == nil then
        return
    end

    Targeting:AddEntity(entry.entity, "compact-disc", {
        {
            icon = "music",
            text = "Play Music",
            event = "Boombox:Client:PlayPrompt",
            data = { id = id },
            isEnabled = function()
                return hasControl(entry.owner)
            end,
        },
        {
            icon = "stop",
            text = "Stop Music",
            event = "Boombox:Client:StopRequest",
            data = { id = id },
            isEnabled = function()
                return entry.track ~= nil and hasControl(entry.owner)
            end,
        },
        {
            icon = "volume-high",
            text = "Adjust Volume",
            event = "Boombox:Client:VolumePrompt",
            data = { id = id },
            isEnabled = function()
                return entry.track ~= nil and hasControl(entry.owner)
            end,
        },
        {
            icon = "hand",
            text = "Pickup Boombox",
            event = "Boombox:Client:Pickup",
            data = { id = id },
            isEnabled = function()
                return hasControl(entry.owner)
            end,
        },
    })
end

local function spawnBoombox(data)
    if data == nil or _boomboxes[data.id] ~= nil then
        return
    end

    loadModel(Config.BoomboxModel)

    local coords = normalizeCoords(data.coords)
    local obj = CreateObject(Config.BoomboxModel, coords.x, coords.y, coords.z, true, true, false)
    SetEntityHeading(obj, data.rotation + 0.0)
    PlaceObjectOnGroundProperly(obj)
    FreezeEntityPosition(obj, true)

    _boomboxes[data.id] = {
        id = data.id,
        owner = data.owner,
        coords = coords,
        rotation = data.rotation,
        entity = obj,
        track = data.track,
        volume = data.volume or Config.DefaultVolume,
    }

    setupTargeting(data.id)

    if data.track then
        startBoomboxSound(data.id)
    end
end

local function deleteBoombox(id)
    local entry = _boomboxes[id]
    if entry == nil then
        return
    end

    stopBoomboxSound(id)

    if DoesEntityExist(entry.entity) then
        DeleteEntity(entry.entity)
    end

    _boomboxes[id] = nil
end

local function playDropAnimation()
    local ped = PlayerPedId()
    RequestAnimDict("pickup_object")
    while not HasAnimDictLoaded("pickup_object") do
        Wait(10)
    end

    TaskPlayAnim(ped, "pickup_object", "pickup_low", 8.0, -8.0, 1250, 0, 0, false, false, false)
    RemoveAnimDict("pickup_object")
end

local function loadExistingBoomboxes()
    if not Callbacks then
        return
    end

    Callbacks:ServerCallback("Boombox:GetPlaced", {}, function(boomboxes)
        if boomboxes then
            for _, data in pairs(boomboxes) do
                spawnBoombox(data)
            end
        end
    end)
end

AddEventHandler("Core:Shared:Ready", function()
    exports["mythic-base"]:RequestDependencies("Boombox", {
        "Callbacks",
        "Targeting",
        "Input",
        "ObjectPlacer",
    }, function(error)
        if #error > 0 then
            exports["mythic-base"]:FetchComponent("Logger"):Critical("Boombox", "Failed To Load All Dependencies")
            return
        end

        RetrieveComponents()

        loadExistingBoomboxes()
    end)
end)

RegisterNetEvent("Characters:Client:Spawn", function()
    loadExistingBoomboxes()
end)

RegisterNetEvent("Boombox:Client:StartPlacement", function()
    ObjectPlacer:Start(Config.BoomboxModel, "Boombox:Client:FinishPlacement", {}, true, "Boombox:Client:CancelPlacement", true, true)
end)

AddEventHandler("Boombox:Client:FinishPlacement", function(_, placement)
    if placement ~= nil then
        playDropAnimation()
        TriggerServerEvent("Boombox:Server:PlacementFinished", placement)
    else
        TriggerServerEvent("Boombox:Server:PlacementCancelled")
    end
end)

AddEventHandler("Boombox:Client:CancelPlacement", function()
    TriggerServerEvent("Boombox:Server:PlacementCancelled")
end)

RegisterNetEvent("Boombox:Client:Create", function(data)
    spawnBoombox(data)
end)

RegisterNetEvent("Boombox:Client:BulkCreate", function(boomboxes)
    for _, data in pairs(boomboxes or {}) do
        spawnBoombox(data)
    end
end)

RegisterNetEvent("Boombox:Client:Remove", function(id)
    deleteBoombox(id)
end)

RegisterNetEvent("Boombox:Client:Play", function(data)
    local entry = _boomboxes[data.id]
    if entry == nil then
        spawnBoombox(data)
        entry = _boomboxes[data.id]
    end

    if entry == nil then
        return
    end

    stopBoomboxSound(data.id)

    entry.track = data.track
    entry.volume = data.volume or Config.DefaultVolume

    startBoomboxSound(data.id)
end)

RegisterNetEvent("Boombox:Client:UpdateVolume", function(id, volume)
    local entry = _boomboxes[id]
    if entry == nil then
        return
    end

    entry.volume = volume
    xsoundSetVolume(string.format("boombox-%s", id), volume / 100.0)
end)

AddEventHandler("Boombox:Client:PlayPrompt", function(_, data)
    if not data or data.id == nil or _songPromise ~= nil or not hasControl(_boomboxes[data.id]?.owner) then
        return
    end

    _songPromise = data.id

    Input:Show("Boombox", "Youtube Link", {
        {
            id = "link",
            type = "text",
            options = {
                inputProps = {
                    placeholder = "https://youtube.com/watch?v=...",
                },
            },
        },
    }, "Boombox:Client:ReceiveSongInput", {})
end)

AddEventHandler("Boombox:Client:ReceiveSongInput", function(values)
    if _songPromise == nil then
        return
    end

    local link = values?.link
    if link ~= nil and #link > 0 then
        TriggerServerEvent("Boombox:Server:SetTrack", _songPromise, link)
    end

    _songPromise = nil
end)

AddEventHandler("Boombox:Client:VolumePrompt", function(_, data)
    if not data or data.id == nil or _volumePromise ~= nil or not hasControl(_boomboxes[data.id]?.owner) then
        return
    end

    _volumePromise = data.id

    Input:Show("Boombox", "Volume", {
        {
            id = "volume",
            type = "number",
            options = {
                inputProps = {
                    min = Config.MinVolume,
                    max = Config.MaxVolume,
                },
                helperText = "1-100",
            },
        },
    }, "Boombox:Client:ReceiveVolumeInput", {})
end)

AddEventHandler("Boombox:Client:ReceiveVolumeInput", function(values)
    if _volumePromise == nil then
        return
    end

    local volume = tonumber(values?.volume or Config.DefaultVolume)
    TriggerServerEvent("Boombox:Server:SetVolume", _volumePromise, volume)
    _volumePromise = nil
end)

AddEventHandler("Boombox:Client:Pickup", function(_, data)
    if not data or data.id == nil or not hasControl(_boomboxes[data.id]?.owner) then
        return
    end

    TriggerServerEvent("Boombox:Server:Pickup", data.id)
end)

AddEventHandler("Boombox:Client:StopRequest", function(_, data)
    if not data or data.id == nil or not hasControl(_boomboxes[data.id]?.owner) then
        return
    end

    TriggerServerEvent("Boombox:Server:Stop", data.id)
end)

AddEventHandler("Input:Closed", function()
    _songPromise = nil
    _volumePromise = nil
end)

RegisterNetEvent("Characters:Client:Logout", function()
    for id in pairs(_boomboxes) do
        deleteBoombox(id)
    end
end)

RegisterNetEvent("Boombox:Client:Stopped", function(id)
    local entry = _boomboxes[id]
    if entry == nil then
        return
    end

    stopBoomboxSound(id)
    entry.track = nil
end)