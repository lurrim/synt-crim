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
    ForceFire = { Enabled = false, Sprint = true },  -- Sprint: разрешить стрельбу в спринте
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
-- Force fire (стрельба без замедления и в спринте)
-- 1) Конфиг оружия: FireSlowDown.Enabled = false (замедление после выстрела).
-- 2) Функция проверки выстрела в GunClient отказывает, пока true её bool-upvalue
--    (спринт/переход бег-idle). Находим по константам (как No Stun) и держим их false.
-- Скан идёт кусками с task.wait(), чтобы не фризить игру.
------------------------------------------------------------------
local ffOrig   = setmetatable({}, { __mode = "k" }) -- FireSlowDown table -> исходный Enabled
local ffChecks = {}                                 -- { {fn, idx}, ... }
local ffConns  = {}
local ffLoop   = nil
local ffBusy, ffQueued = false, false
local ffAcc = 0

local FF_CONSTS = { "CheckIfFlinching", "RagdollCheck", "_USAGEDISABLED", "Right Arm" }

local function ffIsCheckFunc(consts)
    local hit = 0
    for _, want in ipairs(FF_CONSTS) do
        for _, c in ipairs(consts) do
            if c == want then hit += 1; break end
        end
    end
    return hit == #FF_CONSTS
end

local function ffApply()
    for t, orig in pairs(ffOrig) do
        if orig then pcall(rawset, t, "Enabled", false) end
    end
end

local function ffRestore()
    for t, orig in pairs(ffOrig) do
        pcall(rawset, t, "Enabled", orig)
    end
end

local function ffScan()
    if not getgc or ffBusy then return end
    ffBusy = true
    task.spawn(function()
        local found = {}
        pcall(function()
            local gc = getgc(true)
            for i = 1, #gc do
                local v = gc[i]
                local kind = type(v)
                if kind == "table" then
                    if not (isreadonly and isreadonly(v)) then
                        local fsd = rawget(v, "FireSlowDown")
                        if type(fsd) == "table" and rawget(fsd, "Amount") ~= nil and ffOrig[fsd] == nil then
                            ffOrig[fsd] = rawget(fsd, "Enabled") == true
                        end
                    end
                elseif kind == "function" and islclosure(v) then
                    local ok, consts = pcall(debug.getconstants, v)
                    if ok and type(consts) == "table" and ffIsCheckFunc(consts) then
                        local okU, ups = pcall(debug.getupvalues, v)
                        if okU and type(ups) == "table" then
                            for idx, up in pairs(ups) do
                                if type(up) == "boolean" then found[#found + 1] = { v, idx } end
                            end
                        end
                    end
                end
                if i % 1500 == 0 then
                    task.wait()
                    if not M.ForceFire.Enabled then return end
                end
            end
        end)
        if M.ForceFire.Enabled then
            ffChecks = found
            ffApply()
        end
        ffBusy = false
    end)
end

local function ffQueueScan(delay)
    if ffQueued or not M.ForceFire.Enabled then return end
    ffQueued = true
    task.delay(delay or 1, function()
        ffQueued = false
        if M.ForceFire.Enabled then ffScan() end
    end)
end

local function ffStep(dt)
    if not M.ForceFire.Sprint then return end
    ffAcc += dt
    if ffAcc < 0.03 then return end
    ffAcc = 0
    for i = 1, #ffChecks do
        local e = ffChecks[i]
        local ok, val = pcall(debug.getupvalue, e[1], e[2])
        if ok and val == true then
            pcall(debug.setupvalue, e[1], e[2], false)
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
    local function hookBackpack()
        local bp = LP:FindFirstChildOfClass("Backpack")
        if bp then
            ffConns[#ffConns + 1] = bp.ChildAdded:Connect(function(ch)
                if ch:IsA("Tool") then ffQueueScan(1) end
            end)
        end
    end
    -- в руки оружие берётся из рюкзака, замыкание проверки уже существует,
    -- поэтому при экипировке повторный скан не нужен (это и фризило)
    hookBackpack()
    ffConns[#ffConns + 1] = LP.CharacterAdded:Connect(function()
        task.wait(1.5)
        if not M.ForceFire.Enabled then return end
        hookBackpack()
        ffQueueScan(1)
    end)
    ffLoop = RunService.Heartbeat:Connect(ffStep)
end

function M.SetForceFire(state)
    M.ForceFire.Enabled = state
    if state then
        ffHook()
        ffScan()
    else
        ffDisconnect()
        ffRestore()
        ffChecks = {}
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
