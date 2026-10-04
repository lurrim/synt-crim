-- module-aa.lua
-- Anti-aim (подмена направления взгляда/рук, которое уходит на сервер через MOVZREP)
-- Без UI, управляется через getgenv().AntiAimMod

if getgenv().AntiAimMod then
    return getgenv().AntiAimMod
end

local RunService       = game:GetService("RunService")
local Players          = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LP = Players.LocalPlayer

local M = {
    Enabled      = false,
    UseKey       = false, -- если true, работает только пока KeyActive = true
    KeyActive    = true,  -- сюда UI пишет состояние кейбинда
    OnlyWithTool = true,  -- только когда в руках Tool
    AffectNeck   = true,  -- голова (lookVector)
    AffectArms   = true,  -- руки (mousePoint)
    LocalVisual  = true,  -- видеть эффект у себя в третьем лице
    Pitch = {
        Mode  = "Up",     -- Up | Down | Zero | Custom | Jitter | Random
        Value = 90,       -- для Custom
        Min   = -90,      -- для Jitter / Random
        Max   = 90,
        Speed = 5,        -- смен в секунду (Jitter / Random)
    },
    Yaw = {
        Mode  = "None",   -- None | Custom | Spin | Jitter | Random
        Value = 0,        -- для Custom
        Range = 90,       -- для Jitter / Random (от -Range до Range)
        Speed = 360,      -- градусов/сек для Spin, смен/сек для Jitter / Random
    },
    State = { Pitch = 0, Yaw = nil }, -- текущие вычисленные углы (градусы)
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

-- направление в пространстве HRP (X -> поворот головы, Y -> наклон)
local function buildDir(pitchDeg, yawDeg, origLook)
    local p = math.rad(pitchDeg)
    local y, x, z
    y = math.sin(p)
    if yawDeg then
        local yw = math.rad(yawDeg)
        x = math.sin(yw) * math.cos(p)
        z = -math.cos(yw) * math.cos(p)
    else
        x = origLook and origLook.X or 0
        x = math.clamp(x, -math.cos(p), math.cos(p))
        z = -math.sqrt(math.max(0, 1 - x * x - y * y))
    end
    return Vector3.new(x, y, z).Unit
end

------------------------------------------------------------------
-- Расчёт углов каждый кадр
------------------------------------------------------------------
local pT, yT = 0, 0
local pFlip, yFlip = false, false
local pRand, yRand = 0, 0
local spin = 0

local function stepAngles(dt)
    local P, Y = M.Pitch, M.Yaw

    -- pitch
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

    -- yaw
    local yaw = nil
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
    M.State.Yaw = yaw
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
        if self == MOVZREP and not dead and getnamecallmethod() == "FireServer" and active() then
            local args = { ... }
            local pkg = args[1]
            local data = typeof(pkg) == "table" and pkg[1]
            if typeof(data) == "table" then
                local origin = data[2]
                local orig = typeof(data[3]) == "Vector3" and data[3] or nil
                local root = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
                if typeof(origin) == "Vector3" and root then
                    local dir = buildDir(M.State.Pitch, M.State.Yaw, orig)
                    if M.AffectArms then
                        data[1] = origin + root.CFrame:VectorToWorldSpace(dir) * 100
                    end
                    if M.AffectNeck then
                        data[3] = dir
                    end
                end
            end
            return oldNamecall(self, unpack(args))
        end
        return oldNamecall(self, ...)
    end))
else
    warn("AntiAimMod: MOVZREP или hookmetamethod не найдены")
end

------------------------------------------------------------------
-- Локальный визуал (третье лицо). В первом лице не трогаем,
-- чтобы вьюмодель рук выглядела как обычно.
------------------------------------------------------------------
local TOOL_JOINTS = { "Tool6D_Torso", "Mag6D_Torso", "Mag6D_HRP", "Mag6D2_Torso" }

local function visual()
    if not M.LocalVisual or not active() or isFirstPerson() then return end

    local char = LP.Character
    local torso = char and char:FindFirstChild("Torso")
    local root = char and char:FindFirstChild("HumanoidRootPart")
    if not torso or not root then return end

    local orig = root.CFrame:VectorToObjectSpace(cam().CFrame.LookVector).Unit
    local dir = buildDir(M.State.Pitch, M.State.Yaw, orig)
    local pitch = math.rad(M.State.Pitch)

    if M.AffectNeck then
        local neck = torso:FindFirstChild("Neck")
        if neck then
            neck.C0 = CFrame.new(0, 1, 0)
                * CFrame.Angles(0, -math.asin(dir.X), 0)
                * CFrame.Angles(-math.pi / 2 + math.asin(dir.Y), 0, math.pi)
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
-- API
------------------------------------------------------------------
function M.SetEnabled(state)
    M.Enabled = state
end

function M.SetKeyActive(state)
    M.KeyActive = state
end

function M.Unload()
    dead = true
    M.Enabled = false
    pcall(function() RunService:UnbindFromRenderStep("AAMod_Visual") end)
    if stepConn then stepConn:Disconnect() end
    getgenv().AntiAimMod = nil
end

getgenv().AntiAimMod = M
return M
