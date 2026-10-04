-- module-aa.lua
-- Anti-aim (подмена направления взгляда/рук, которое уходит на сервер через MOVZREP)
-- + Hide Head (с позицией головы)
-- Без UI, управляется через getgenv().AntiAimMod

if getgenv().AntiAimMod then
    return getgenv().AntiAimMod
end

local RunService        = game:GetService("RunService")
local Players           = game:GetService("Players")
local UserInputService  = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LP = Players.LocalPlayer

local setnm = setnamecallmethod or function() end

local M = {
    Enabled      = false,
    UseKey       = false,
    KeyActive    = true,
    OnlyWithTool = true,
    AffectNeck   = true,
    AffectArms   = true,
    LocalVisual  = true,

    PitchEnabled = true,  -- глобальный тугл pitch (выкл = настоящий pitch)
    YawEnabled   = true,  -- глобальный тугл yaw   (выкл = настоящий yaw)

    HideHead     = false,
    HeadPos = {           -- смещение головы при Hide Head (в студах)
        Height  = 0,      -- + выше / - ниже
        Forward = 0,      -- + вперёд / - назад
        Side    = 0,      -- + вправо / - влево
    },

    Pitch = {
        Mode  = "Up",     -- Up | Down | Zero | Custom | Jitter | Random
        Value = 90,
        Min   = -90,
        Max   = 90,
        Speed = 5,
    },
    Yaw = {
        Mode  = "None",   -- None | Custom | Spin | Jitter | Random
        Value = 0,
        Range = 90,       -- до 180 при Body = true
        Speed = 360,
        Body  = true,     -- вращать тело (полные 360°), голова смотрит по телу
    },
    State = { Pitch = 0, Yaw = nil },
}

local dead = false

------------------------------------------------------------------
-- Вспомогательное
------------------------------------------------------------------
local function cam()
    return workspace.CurrentCamera
end

local function hasTool()
    local char = LP.Character
    return char ~= nil and char:FindFirstChildOfClass("Tool") ~= nil
end

local function isFirstPerson()
    if _G.FP then return true end
    local char = LP.Character
    local head = char and char:FindFirstChild("Head")
    if not head then return false end
    return (cam().CFrame.Position - head.Position).Magnitude <= 1.5
        and UserInputService.MouseBehavior == Enum.MouseBehavior.LockCenter
end

local function active()
    if dead or not M.Enabled then return false end
    if M.UseKey and not M.KeyActive then return false end
    if M.OnlyWithTool and not hasTool() then return false end
    return true
end

local function anyAxis()
    return M.PitchEnabled or M.YawEnabled
end

-- yaw, который уходит в голову (в режиме Body голова смотрит строго по телу)
local function headYaw()
    if M.State.Yaw ~= nil and M.Yaw.Body then
        return 0
    end
    return M.State.Yaw
end

-- направление в пространстве HRP. pitchDeg/yawDeg == nil -> берём из orig
local function buildDir(pitchDeg, yawDeg, orig)
    local y
    if pitchDeg then
        y = math.sin(math.rad(pitchDeg))
    else
        y = orig and orig.Y or 0
    end
    y = math.clamp(y, -1, 1)
    local cp = math.sqrt(math.max(0, 1 - y * y)) -- cos(pitch)

    local x, z
    if yawDeg then
        local yw = math.rad(yawDeg)
        x = math.sin(yw) * cp
        z = -math.cos(yw) * cp
    else
        x = orig and orig.X or 0
        x = math.clamp(x, -cp, cp)
        z = -math.sqrt(math.max(0, 1 - x * x - y * y))
    end
    local v = Vector3.new(x, y, z)
    if v.Magnitude < 1e-4 then
        return Vector3.new(0, 0, -1)
    end
    return v.Unit
end

-- фиксированный пакет для Hide Head (как в оригинальном скрипте)
local function hideHeadPackage()
    return {
        {
            Vector3.new(-5721.2001953125, -5, 971.5162353515625),
            Vector3.new(-4181.38818359375, -6, 11.123311996459961),
            Vector3.new(0.006237113382667303, -6, -0.18136750161647797),
            true,
            true,
            true,
            false,
        },
        false,
        false,
        15.8,
    }
end

------------------------------------------------------------------
-- Расчёт углов каждый кадр + вращение тела
------------------------------------------------------------------
local pT, yT = 0, 0
local pFlip, yFlip = false, false
local pRand, yRand = 0, 0
local spin = 0
local autoRotateSaved = nil

local function bodyStep()
    local char = LP.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    local root = char and char:FindFirstChild("HumanoidRootPart")

    local want = not dead and active() and M.YawEnabled and M.Yaw.Body and M.State.Yaw ~= nil

    if want and hum and root then
        if autoRotateSaved == nil then
            autoRotateSaved = hum.AutoRotate
        end
        hum.AutoRotate = false
        local look = cam().CFrame.LookVector
        local camYaw = math.atan2(-look.X, -look.Z)
        root.CFrame = CFrame.new(root.Position)
            * CFrame.Angles(0, camYaw + math.rad(M.State.Yaw), 0)
    elseif autoRotateSaved ~= nil then
        if hum then hum.AutoRotate = autoRotateSaved end
        autoRotateSaved = nil
    end
end

local function stepAngles(dt)
    local P, Y = M.Pitch, M.Yaw

    -- pitch
    if M.PitchEnabled then
        local pitch = 0
        if P.Mode == "Up" then
            pitch = 90
        elseif P.Mode == "Down" then
            pitch = -90
        elseif P.Mode == "Custom" then
            pitch = P.Value
        elseif P.Mode == "Jitter" or P.Mode == "Random" then
            pT += dt
            if pT >= 1 / math.max(P.Speed, 0.1) then
                pT = 0
                pFlip = not pFlip
                pRand = math.random() * (P.Max - P.Min) + P.Min
            end
            pitch = P.Mode == "Jitter" and (pFlip and P.Max or P.Min) or pRand
        end
        M.State.Pitch = math.clamp(pitch, -90, 90)
    else
        M.State.Pitch = nil
    end

    -- yaw
    local yaw = nil
    if M.YawEnabled then
        if Y.Mode == "Custom" then
            yaw = Y.Value
        elseif Y.Mode == "Spin" then
            spin = (spin + Y.Speed * dt + 180) % 360 - 180
            yaw = spin
        elseif Y.Mode == "Jitter" or Y.Mode == "Random" then
            yT += dt
            if yT >= 1 / math.max(Y.Speed, 0.1) then
                yT = 0
                yFlip = not yFlip
                yRand = (math.random() * 2 - 1) * Y.Range
            end
            yaw = Y.Mode == "Jitter" and (yFlip and Y.Range or -Y.Range) or yRand
        end
    end
    M.State.Yaw = yaw

    bodyStep()
end

local stepConn = RunService.Heartbeat:Connect(stepAngles)

------------------------------------------------------------------
-- Подмена данных для сервера (видят другие игроки)
------------------------------------------------------------------
local MOVZREP
pcall(function()
    MOVZREP = ReplicatedStorage:WaitForChild("Events", 10):WaitForChild("MOVZREP", 10)
end)

local oldNamecall
if MOVZREP and hookmetamethod then
    oldNamecall = hookmetamethod(game, "__namecall", newcclosure(function(self, ...)
        -- ВАЖНО: запоминаем метод сразу, любой другой namecall внутри хука его затирает
        local method = getnamecallmethod()

        if self == MOVZREP and not dead and method == "FireServer" then
            -- Hide Head имеет приоритет над anti-aim
            if M.HideHead then
                setnm(method)
                return oldNamecall(self, hideHeadPackage())
            end

            local args = { ... }
            if anyAxis() and active() then
                pcall(function()
                    local pkg = args[1]
                    local data = typeof(pkg) == "table" and pkg[1]
                    if typeof(data) == "table" then
                        local origin = data[2]
                        local orig = typeof(data[3]) == "Vector3" and data[3] or nil
                        local char = LP.Character
                        local root = char and char:FindFirstChild("HumanoidRootPart")
                        if typeof(origin) == "Vector3" and root then
                            local dir = buildDir(M.State.Pitch, headYaw(), orig)
                            if M.AffectArms then
                                data[1] = origin + root.CFrame:VectorToWorldSpace(dir) * 100
                            end
                            if M.AffectNeck then
                                data[3] = dir
                            end
                        end
                    end
                end)
            end
            setnm(method)
            return oldNamecall(self, unpack(args))
        end

        setnm(method)
        return oldNamecall(self, ...)
    end))
else
    warn("AntiAimMod: MOVZREP или hookmetamethod не найдены")
end

------------------------------------------------------------------
-- Локальный визуал (третье лицо)
------------------------------------------------------------------
local TOOL_JOINTS = { "Tool6D_Torso", "Mag6D_Torso", "Mag6D_HRP", "Mag6D2_Torso" }

local function visual()
    if not M.LocalVisual or not anyAxis() or not active() or isFirstPerson() then return end

    local char = LP.Character
    local torso = char and char:FindFirstChild("Torso")
    local root = char and char:FindFirstChild("HumanoidRootPart")
    if not torso or not root then return end

    local orig = root.CFrame:VectorToObjectSpace(cam().CFrame.LookVector).Unit
    local dir = buildDir(M.State.Pitch, headYaw(), orig)
    local pitch = math.asin(math.clamp(dir.Y, -1, 1))

    if M.AffectNeck then
        local neck = torso:FindFirstChild("Neck")
        if neck then
            neck.C0 = CFrame.new(0, 1, 0)
                * CFrame.Angles(0, -math.asin(math.clamp(dir.X, -1, 1)), 0)
                * CFrame.Angles(-math.pi / 2 + math.asin(math.clamp(dir.Y, -1, 1)), 0, math.pi)
        end
    end

    if M.AffectArms and not char:GetAttribute("NoArmMovement") then
        local ls = torso:FindFirstChild("Left Shoulder")
        local rs = torso:FindFirstChild("Right Shoulder")
        local rightC0
        if ls then
            ls.C0 = CFrame.new(-1, 0.5, 0) * CFrame.Angles(pitch, -1.55, 0)
        end
        if rs then
            rightC0 = CFrame.new(1, 0.5, 0) * CFrame.Angles(pitch, 1.55, 0)
            rs.C0 = rightC0
        end

        local tool = char:FindFirstChildOfClass("Tool")
        if tool and rightC0 then
            pcall(function()
                for _, name in ipairs(TOOL_JOINTS) do
                    local joint = tool:FindFirstChild(name)
                    local default = joint and joint:FindFirstChild("DefaultCF")
                    if default then
                        local offset = joint:FindFirstChild("Offset")
                        joint.C0 = rightC0
                            * CFrame.fromEulerAnglesXYZ(0, -math.pi / 2, 0)
                            * (offset and offset.Value or CFrame.new())
                            * default.Value
                    end
                end
            end)
        end
    end
end

RunService:BindToRenderStep("AAMod_Visual", 3000, visual)

------------------------------------------------------------------
-- Hide Head: локальная фиксация шеи (позиция регулируется HeadPos)
------------------------------------------------------------------
local savedNeckC1 = setmetatable({}, { __mode = "k" })

local function getNeck()
    local char = LP.Character
    local torso = char and char:FindFirstChild("Torso")
    local neck = torso and torso:FindFirstChild("Neck")
    if neck and neck:IsA("Motor6D") then
        return neck
    end
end

local function restoreNeck()
    for neck, c1 in pairs(savedNeckC1) do
        if neck and neck.Parent then
            neck.C1 = c1
        end
        savedNeckC1[neck] = nil
    end
end

local function hideHeadVisual()
    if dead or not M.HideHead then return end
    local neck = getNeck()
    if not neck then return end

    if savedNeckC1[neck] == nil then
        savedNeckC1[neck] = neck.C1
    end

    local hp = M.HeadPos
    -- оригинал: C0 = (0, 0, 0.75). В торсе R6 перёд = -Z, поэтому forward вычитаем
    neck.C0 = CFrame.new(hp.Side, hp.Height, 0.75 - hp.Forward) * CFrame.Angles(math.rad(90), 0, 0)
    neck.C1 = CFrame.new(0, 0.25, 0)
end

RunService:BindToRenderStep("AAMod_HideHead", 3001, hideHeadVisual)

------------------------------------------------------------------
-- API
------------------------------------------------------------------
function M.SetEnabled(state)
    M.Enabled = state
end

function M.SetKeyActive(state)
    M.KeyActive = state
end

function M.SetHideHead(state)
    M.HideHead = state and true or false
    if not M.HideHead then
        restoreNeck()
    end
end

function M.Unload()
    dead = true
    M.Enabled = false
    M.HideHead = false
    pcall(function() RunService:UnbindFromRenderStep("AAMod_Visual") end)
    pcall(function() RunService:UnbindFromRenderStep("AAMod_HideHead") end)
    restoreNeck()
    if stepConn then stepConn:Disconnect() end
    pcall(function()
        local hum = LP.Character and LP.Character:FindFirstChildOfClass("Humanoid")
        if hum and autoRotateSaved ~= nil then hum.AutoRotate = autoRotateSaved end
    end)
    autoRotateSaved = nil
    getgenv().AntiAimMod = nil
end

getgenv().AntiAimMod = M
return M
