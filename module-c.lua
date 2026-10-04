-- module-camera.lua
-- Extended zoom + Smooth FOV (unoverridable) + No camera bobbing + Instant equip + Force fire.
-- Без UI, всё управляется через getgenv().CameraMod

if getgenv().CameraMod then
    return getgenv().CameraMod
end

local RunService = game:GetService("RunService")
local LP         = game:GetService("Players").LocalPlayer

local function cam()
    return workspace.CurrentCamera
end

local M = {
    Zoom      = { Enabled = false, Max = 300 },
    SmoothFOV = { Enabled = false, Value = 90, Speed = 8, PauseOnAim = false },
    NoBob     = { Enabled = false },
    Equip     = { Enabled = false, AnimSpeed = 50 }, -- AnimSpeed не ставить в 0 (EquipM делит на него)
    ForceFire = { Enabled = false },
}

local function isAiming()
    local char = LP.Character
    local tool = char and char:FindFirstChildOfClass("Tool")
    local vals = tool and tool:FindFirstChild("Values")
    local aim  = vals and vals:FindFirstChild("AimDown")
    return aim ~= nil and aim.Value == true
end

------------------------------------------------------------------
-- Extended zoom (колесо назад)
------------------------------------------------------------------
local zoomConn, zoomOrig = nil, nil

function M.SetZoom(state)
    M.Zoom.Enabled = state
    if zoomConn then zoomConn:Disconnect(); zoomConn = nil end
    if state then
        zoomOrig = zoomOrig or LP.CameraMaxZoomDistance
        zoomConn = RunService.RenderStepped:Connect(function()
            if LP.CameraMaxZoomDistance ~= M.Zoom.Max then
                LP.CameraMaxZoomDistance = M.Zoom.Max
            end
        end)
    elseif zoomOrig then
        LP.CameraMaxZoomDistance = zoomOrig
        zoomOrig = nil
    end
end

------------------------------------------------------------------
-- Smooth FOV (чужие записи в Camera.FieldOfView блокируются)
------------------------------------------------------------------
local SF = M.SmoothFOV
local sfCurrent, sfWriting, sfSuspended = nil, false, false
local sfHooked, sfSig, sfSigCam = false, nil, nil

local function sfWrite(v)
    local c = cam()
    if not c then return end
    sfWriting = true
    c.FieldOfView = v
    sfWriting = false
end

local function sfInstallHook()
    if sfHooked or not hookmetamethod then return end
    sfHooked = true
    local old
    old = hookmetamethod(game, "__newindex", (newcclosure or function(f) return f end)(function(self, key, value)
        if SF.Enabled and not sfWriting and not sfSuspended
            and key == "FieldOfView" and self == workspace.CurrentCamera then
            return
        end
        return old(self, key, value)
    end))
end

local function sfBindSignal()
    local c = cam()
    if not c or sfSigCam == c then return end
    if sfSig then sfSig:Disconnect() end
    sfSigCam = c
    -- запасной вариант без hookmetamethod: возвращаем наш FOV сразу после чужой записи
    sfSig = c:GetPropertyChangedSignal("FieldOfView"):Connect(function()
        if SF.Enabled and not sfWriting and not sfSuspended and sfCurrent and c.FieldOfView ~= sfCurrent then
            sfWrite(sfCurrent)
        end
    end)
end

local function sfStep(dt)
    local c = cam()
    if not c then return end
    sfBindSignal()

    if SF.PauseOnAim and isAiming() then
        sfSuspended = true
        sfCurrent = nil
        return
    end
    sfSuspended = false

    if not sfCurrent then sfCurrent = c.FieldOfView end
    sfCurrent = sfCurrent + (SF.Value - sfCurrent) * (1 - math.exp(-SF.Speed * dt))
    if math.abs(SF.Value - sfCurrent) < 0.01 then sfCurrent = SF.Value end
    if c.FieldOfView ~= sfCurrent then sfWrite(sfCurrent) end
end

function M.SetSmoothFOV(state)
    SF.Enabled = state
    pcall(function() RunService:UnbindFromRenderStep("CamMod_SmoothFOV") end)
    if sfSig then sfSig:Disconnect(); sfSig = nil; sfSigCam = nil end
    sfSuspended, sfCurrent = false, nil
    if state then
        sfInstallHook()
        RunService:BindToRenderStep("CamMod_SmoothFOV", Enum.RenderPriority.Last.Value, sfStep)
    else
        local c = cam()
        if c then c.FieldOfView = 70 end -- дальше игра вернёт свой FOV сама
    end
end

------------------------------------------------------------------
-- No camera bobbing (поиск конфиг-таблиц через getgc)
------------------------------------------------------------------
local BOB_KEYS = { "CameraBobbing", "Bobbing", "HeadBobbing", "ViewBobbing", "CameraBob", "HeadBob", "WalkBob", "WalkBobbing" }
local nbList, nbConn, nbCharConn = {}, nil, nil

local function nbRestore()
    for _, e in ipairs(nbList) do
        pcall(rawset, e.t, e.key, e.orig)
    end
    nbList = {}
end

local function nbScan()
    if not getgc then return 0 end
    local n = 0
    pcall(function()
        for _, v in ipairs(getgc(true)) do
            if type(v) == "table" and not (isreadonly and isreadonly(v)) then
                for _, key in ipairs(BOB_KEYS) do
                    local cur = rawget(v, key)
                    if type(cur) == "boolean" then
                        nbList[#nbList + 1] = { t = v, key = key, orig = cur }
                        n += 1
                    end
                end
            end
        end
    end)
    return n
end

-- возвращает количество найденных таблиц (0 = конфиг не найден)
function M.SetNoBob(state)
    M.NoBob.Enabled = state
    if nbConn then nbConn:Disconnect(); nbConn = nil end
    if nbCharConn then nbCharConn:Disconnect(); nbCharConn = nil end
    nbRestore()
    if not state then return 0 end

    local found = nbScan()
    nbConn = RunService.Heartbeat:Connect(function()
        for _, e in ipairs(nbList) do
            if rawget(e.t, e.key) ~= false then
                pcall(rawset, e.t, e.key, false)
            end
        end
    end)
    nbCharConn = LP.CharacterAdded:Connect(function()
        task.wait(1.5)
        if M.NoBob.Enabled then
            nbRestore()
            nbScan()
        end
    end)
    return found
end

------------------------------------------------------------------
-- Instant equip (EquipTime = 0, быстрая анимация)
-- GunClient хранит конфиг в защищённой копии, но внутри это обычная таблица, её находит getgc.
------------------------------------------------------------------
local ieOrig   = setmetatable({}, { __mode = "k" }) -- table -> { EquipTime, EquipAnimSpeed }
local ieByName = {}
local ieConns  = {}
local ieBusy, ieQueued = false, false

local function ieRecord(t)
    local o = ieOrig[t]
    if o then return o end
    local et, es, name = rawget(t, "EquipTime"), rawget(t, "EquipAnimSpeed"), rawget(t, "Name")
    if et == 0 and es == M.Equip.AnimSpeed and name and ieByName[name] then
        o = ieByName[name] -- копия уже пропатченного конфига, оригинал берём по имени оружия
    else
        o = { EquipTime = et, EquipAnimSpeed = es }
        if name and not ieByName[name] then ieByName[name] = o end
    end
    ieOrig[t] = o
    return o
end

local function ieApply()
    for t in pairs(ieOrig) do
        pcall(function()
            rawset(t, "EquipTime", 0)
            if type(rawget(t, "EquipAnimSpeed")) == "number" then
                rawset(t, "EquipAnimSpeed", M.Equip.AnimSpeed)
            end
        end)
    end
end

local function ieScan()
    if not getgc or ieBusy then return end
    ieBusy = true
    pcall(function()
        for _, v in ipairs(getgc(true)) do
            if type(v) == "table" and type(rawget(v, "EquipTime")) == "number"
                and not (isreadonly and isreadonly(v)) then
                ieRecord(v)
            end
        end
    end)
    if M.Equip.Enabled then ieApply() end
    ieBusy = false
end

local function ieRestore()
    for t, o in pairs(ieOrig) do
        pcall(function()
            if o.EquipTime ~= nil then rawset(t, "EquipTime", o.EquipTime) end
            if o.EquipAnimSpeed ~= nil then rawset(t, "EquipAnimSpeed", o.EquipAnimSpeed) end
        end)
    end
end

local function ieQueueScan(delay)
    if ieQueued or not M.Equip.Enabled then return end
    ieQueued = true
    task.delay(delay or 0.4, function()
        ieQueued = false
        if M.Equip.Enabled then ieScan() end
    end)
end

local function ieDisconnect()
    for _, c in ipairs(ieConns) do c:Disconnect() end
    ieConns = {}
end

local function ieHook()
    ieDisconnect()
    local function hookBackpack()
        local bp = LP:FindFirstChildOfClass("Backpack")
        if bp then
            ieConns[#ieConns + 1] = bp.ChildAdded:Connect(function(ch)
                if ch:IsA("Tool") then ieQueueScan(0.5) end
            end)
        end
    end
    local function hookChar(char)
        if not char then return end
        ieConns[#ieConns + 1] = char.ChildAdded:Connect(function(ch)
            if ch:IsA("Tool") then ieQueueScan(0.05) end
        end)
    end
    hookBackpack()
    hookChar(LP.Character)
    ieConns[#ieConns + 1] = LP.CharacterAdded:Connect(function(char)
        task.wait(1)
        if not M.Equip.Enabled then return end
        hookBackpack()
        hookChar(char)
        ieQueueScan(0.5)
    end)
end

-- после включения оружие нужно достать заново
function M.SetInstantEquip(state)
    M.Equip.Enabled = state
    if state then
        ieScan()
        ieHook()
    else
        ieDisconnect()
        ieRestore()
    end
end

------------------------------------------------------------------
-- Force fire (стрельба без замедления и на бегу)
-- Скопировано с No Stun из основного скрипта:
--  * скан getgc кусками по 1500 объектов с task.wait(), запуск через 1 с после появления тула;
--  * функция проверки выстрела в GunClient находится по константам
--    CheckIfFlinching / RagdollCheck / _USAGEDISABLED / Right Arm;
--  * её bool-upvalue (спринт, переход бег-idle и т.д.) каждые 0.05 с сбрасываются в false.
-- Плюс FireSlowDown.Enabled = false в конфиге оружия (замедление после выстрела).
-- Оптимизация: уже проверенные функции запоминаются и повторно не разбираются.
------------------------------------------------------------------
local FF_WEAK   = { __mode = "k" }
local ffSeen    = setmetatable({}, FF_WEAK) -- функции, которые уже проверяли
local ffTargets = setmetatable({}, FF_WEAK) -- fn -> { индексы bool-upvalue }
local ffSlow    = setmetatable({}, FF_WEAK) -- FireSlowDown table -> исходный Enabled
local ffConns   = {}
local ffLoop    = nil
local ffBusy, ffPending = false, false
local ffAcc = 0

local function ffIsCheckFunc(consts)
    local a, b, c, d = false, false, false, false
    for _, k in pairs(consts) do
        if k == "CheckIfFlinching" then a = true
        elseif k == "RagdollCheck" then b = true
        elseif k == "_USAGEDISABLED" then c = true
        elseif k == "Right Arm" then d = true end
    end
    return a and b and c and d
end

local function ffApplySlow()
    for t, orig in pairs(ffSlow) do
        if orig then pcall(rawset, t, "Enabled", false) end
    end
end

local function ffRestoreSlow()
    for t, orig in pairs(ffSlow) do
        pcall(rawset, t, "Enabled", orig)
    end
end

local function ffScan()
    if ffBusy or not getgc then return end
    ffBusy = true
    pcall(function()
        local gc = getgc(true)
        for i = 1, #gc do
            local v = gc[i]
            local kind = type(v)
            if kind == "function" then
                if not ffSeen[v] and islclosure(v) then
                    ffSeen[v] = true
                    local ok, consts = pcall(debug.getconstants, v)
                    if ok and type(consts) == "table" and ffIsCheckFunc(consts) then
                        local okU, ups = pcall(debug.getupvalues, v)
                        if okU and type(ups) == "table" then
                            local idxs = {}
                            for idx, up in pairs(ups) do
                                if type(up) == "boolean" then idxs[#idxs + 1] = idx end
                            end
                            if #idxs > 0 then ffTargets[v] = idxs end
                        end
                    end
                end
            elseif kind == "table" then
                local fsd = rawget(v, "FireSlowDown")
                if type(fsd) == "table" and rawget(fsd, "Amount") ~= nil and ffSlow[fsd] == nil then
                    ffSlow[fsd] = rawget(fsd, "Enabled") == true
                end
            end
            if i % 1500 == 0 then
                task.wait()
                if not M.ForceFire.Enabled then break end
            end
        end
    end)
    ffBusy = false
    if M.ForceFire.Enabled then ffApplySlow() end
end

local function ffRequestScan(delay)
    if ffPending or not M.ForceFire.Enabled then return end
    ffPending = true
    task.delay(delay or 1, function()
        ffPending = false
        if M.ForceFire.Enabled then ffScan() end
    end)
end

local function ffStep(dt)
    ffAcc += dt
    if ffAcc < 0.05 then return end
    ffAcc = 0
    for fn, idxs in pairs(ffTargets) do
        for i = 1, #idxs do
            local ok, a, b = pcall(debug.getupvalue, fn, idxs[i])
            local val = a
            if b ~= nil then val = b end
            if ok and val == true then
                pcall(debug.setupvalue, fn, idxs[i], false)
            end
        end
    end
end

local function ffDisconnect()
    for _, c in ipairs(ffConns) do c:Disconnect() end
    ffConns = {}
    if ffLoop then ffLoop:Disconnect(); ffLoop = nil end
end

local function ffHook()
    ffDisconnect()
    local function hookChar(char)
        if not char then return end
        ffConns[#ffConns + 1] = char.ChildAdded:Connect(function(ch)
            if ch:IsA("Tool") then ffRequestScan(1) end
        end)
    end
    hookChar(LP.Character)
    ffConns[#ffConns + 1] = LP.CharacterAdded:Connect(function(char)
        hookChar(char)
        ffRequestScan(1)
    end)
    ffLoop = RunService.Heartbeat:Connect(ffStep)
end

function M.SetForceFire(state)
    M.ForceFire.Enabled = state
    if state then
        ffHook()
        ffRequestScan(0.1)
    else
        ffDisconnect()
        ffRestoreSlow()
    end
end

------------------------------------------------------------------
function M.Unload()
    M.SetZoom(false)
    M.SetSmoothFOV(false)
    M.SetNoBob(false)
    M.SetInstantEquip(false)
    M.SetForceFire(false)
    getgenv().CameraMod = nil
end

getgenv().CameraMod = M
return M
