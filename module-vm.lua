-- module-viewmodel.lua
-- Custom ViewModel + Gun Chams + Arms (только первое лицо). Без UI, всё управляется через getgenv().ViewModelMod

if getgenv().ViewModelMod then
    return getgenv().ViewModelMod
end

local RunService = game:GetService("RunService")
local Players    = game:GetService("Players")
local LP         = Players.LocalPlayer

local function cam()
    return workspace.CurrentCamera
end

local M = {
    ViewModel = {
        Enabled = false,
        Speed   = 0.3, -- сек, плавность перехода Default <-> Aiming
        Default = { X = 0, Y = 0, Z = 0, Pitch = 0, Yaw = 0, Roll = 0 },
        Aiming  = { X = 0, Y = 0, Z = 0, Pitch = 0, Yaw = 0, Roll = 0 },
    },
    GunChams = {
        Enabled             = false,
        Mode                = "Material", -- "Material" | "Highlight"
        Material            = "Neon",
        Color               = Color3.fromRGB(100, 149, 237),
        Transparency        = 0,
        NoTexture           = true,
        Outline             = false, -- только для Highlight
        OutlineColor        = Color3.fromRGB(255, 255, 255),
        OutlineTransparency = 0,
    },
    Arms = {
        Left  = { Enabled = false, Color = Color3.fromRGB(255, 200, 150), Material = "SmoothPlastic", Transparency = 0 },
        Right = { Enabled = false, Color = Color3.fromRGB(255, 200, 150), Material = "SmoothPlastic", Transparency = 0 },
    },
}

local function setp(obj, prop, val)
    if obj[prop] ~= val then
        obj[prop] = val
    end
end

local function mat(name, fallback)
    return Enum.Material[name] or Enum.Material[fallback]
end

------------------------------------------------------------------
-- Custom ViewModel
------------------------------------------------------------------
local VMC = M.ViewModel
local current = { X = 0, Y = 0, Z = 0, Pitch = 0, Yaw = 0, Roll = 0 }
local KEYS = { "X", "Y", "Z", "Pitch", "Yaw", "Roll" }
local savedPivot = nil

local function isAiming()
    local char = LP.Character
    local tool = char and char:FindFirstChildOfClass("Tool")
    local vals = tool and tool:FindFirstChild("Values")
    local aim  = vals and vals:FindFirstChild("AimDown")
    return aim ~= nil and aim.Value == true
end

local function restorePivot()
    if savedPivot then
        local vm = cam():FindFirstChild("ViewModel")
        if vm then vm:PivotTo(savedPivot) end
        savedPivot = nil
    end
end

local function applyViewModel(dt)
    local target = isAiming() and VMC.Aiming or VMC.Default
    local f = VMC.Speed > 0 and (1 - 0.001 ^ (dt / VMC.Speed)) or 1
    for _, k in ipairs(KEYS) do
        current[k] = current[k] + (target[k] - current[k]) * f
    end

    local vm = cam():FindFirstChild("ViewModel")
    if not vm then return end

    savedPivot = vm:GetPivot()
    local camCF = cam().CFrame
    local offset = CFrame.new(current.X, current.Y, current.Z)
        * CFrame.Angles(math.rad(current.Pitch), math.rad(current.Yaw), math.rad(current.Roll))
    vm:PivotTo(camCF * offset * camCF:ToObjectSpace(savedPivot))
end

function M.SetViewModel(state)
    VMC.Enabled = state
    pcall(function() RunService:UnbindFromRenderStep("VMMod_Restore") end)
    pcall(function() RunService:UnbindFromRenderStep("VMMod_Apply") end)
    if state then
        RunService:BindToRenderStep("VMMod_Restore", 100, restorePivot)
        RunService:BindToRenderStep("VMMod_Apply", 3000, applyViewModel)
    else
        restorePivot()
    end
end

------------------------------------------------------------------
-- Gun Chams
------------------------------------------------------------------
local GC = M.GunChams
local gcOrig = setmetatable({}, { __mode = "k" })
local gcHighlight = nil

local function gcParts(root)
    local out = {}
    if root:IsA("BasePart") or root:IsA("SpecialMesh") then
        out[#out + 1] = root
    end
    for _, d in ipairs(root:GetDescendants()) do
        if d:IsA("BasePart") or d:IsA("SpecialMesh") then
            out[#out + 1] = d
        end
    end
    return out
end

local function gcSave(part)
    local o = gcOrig[part]
    if o then return o end
    o = {}
    if part:IsA("BasePart") then
        o.Color = part.Color
        o.Material = part.Material
        o.Transparency = part.Transparency
        o.skipT = part.Transparency >= 0.99 -- уже невидимые части не трогаем
        if part:IsA("MeshPart") then o.TextureID = part.TextureID end
    elseif part:IsA("SpecialMesh") then
        o.TextureId = part.TextureId
    end
    gcOrig[part] = o
    return o
end

local function gcApplyPart(part, forceInvisible)
    local o = gcSave(part)
    pcall(function()
        if part:IsA("BasePart") then
            setp(part, "Color", GC.Color)
            setp(part, "Material", mat(GC.Material, "Neon"))
            if not o.skipT then
                setp(part, "Transparency", forceInvisible and 1 or GC.Transparency)
            end
            if GC.NoTexture and part:IsA("MeshPart") then
                setp(part, "TextureID", "")
            end
        elseif part:IsA("SpecialMesh") and GC.NoTexture then
            setp(part, "TextureId", "")
        end
    end)
end

local function gcRestoreAll()
    for part, o in pairs(gcOrig) do
        pcall(function()
            if part:IsA("BasePart") then
                part.Color = o.Color
                part.Material = o.Material
                if not o.skipT then part.Transparency = o.Transparency end
                if o.TextureID then part.TextureID = o.TextureID end
            elseif part:IsA("SpecialMesh") and o.TextureId then
                part.TextureId = o.TextureId
            end
        end)
        gcOrig[part] = nil
    end
end

local function gcDestroyHighlight()
    if gcHighlight then
        pcall(function() gcHighlight:Destroy() end)
        gcHighlight = nil
    end
end

local function gcRoots()
    local roots = {}

    -- модель оружия во вьюмодели (первое лицо)
    local vm = cam():FindFirstChild("ViewModel")
    local vmTool = vm and vm:FindFirstChild("Tool")
    if vmTool then
        roots[#roots + 1] = { root = vmTool, invisible = false }
    end

    local char = LP.Character
    if char then
        local equipped = {}
        for _, child in ipairs(char:GetChildren()) do
            if child:IsA("Tool") then
                roots[#roots + 1] = { root = child, invisible = false }
                equipped[child.Name] = true
            end
        end

        -- оружие на теле: пока оно в руках, его копию на теле прячем
        local di = char:FindFirstChild("DisplayItems")
        if di then
            for _, weapon in ipairs(di:GetChildren()) do
                local partsFolder = weapon:FindFirstChild("Parts")
                if partsFolder then
                    for _, group in ipairs(partsFolder:GetChildren()) do
                        local model = group:FindFirstChild("Model")
                        local handle = model and (model:FindFirstChild("Handle") or model:FindFirstChildWhichIsA("BasePart"))
                        if handle then
                            roots[#roots + 1] = {
                                root = handle.Parent or handle,
                                invisible = equipped[weapon.Name] == true,
                            }
                        end
                    end
                end
            end
        end
    end

    return roots
end

local function gcStep()
    local roots = gcRoots()

    if GC.Mode == "Material" then
        for _, r in ipairs(roots) do
            for _, p in ipairs(gcParts(r.root)) do
                gcApplyPart(p, r.invisible)
            end
        end
    else
        gcRestoreAll()
    end

    if GC.Mode == "Highlight" then
        local ok = pcall(function()
            if not gcHighlight then
                gcHighlight = Instance.new("Highlight")
                gcHighlight.Name = "GunHighlight"
                gcHighlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
                gcHighlight.Parent = cam()
            end
            setp(gcHighlight, "FillColor", GC.Color)
            setp(gcHighlight, "FillTransparency", GC.Transparency)
            setp(gcHighlight, "OutlineColor", GC.OutlineColor)
            setp(gcHighlight, "OutlineTransparency", GC.Outline and GC.OutlineTransparency or 1)
            local target = roots[1] and roots[1].root or nil
            if gcHighlight.Adornee ~= target then gcHighlight.Adornee = target end
        end)
        if not ok then gcHighlight = nil end
    else
        gcDestroyHighlight()
    end
end

------------------------------------------------------------------
-- Arms (только вьюмодель, т.е. первое лицо)
------------------------------------------------------------------
local armOrig = {}

local function armRestore(side)
    local o = armOrig[side]
    if o and o.part and o.part.Parent then
        pcall(function()
            o.part.Color = o.Color
            o.part.Material = o.Material
            o.part.Transparency = o.Transparency
        end)
    end
    armOrig[side] = nil
end

local function armStep()
    local vm = cam():FindFirstChild("ViewModel")
    for side, cfg in pairs(M.Arms) do
        if cfg.Enabled and vm then
            local p = vm:FindFirstChild(side .. " Arm")
            if p and p:IsA("BasePart") then
                local o = armOrig[side]
                if not o or o.part ~= p then
                    o = { part = p, Color = p.Color, Material = p.Material, Transparency = p.Transparency }
                    armOrig[side] = o
                end
                pcall(function()
                    setp(p, "Color", cfg.Color)
                    setp(p, "Material", mat(cfg.Material, "SmoothPlastic"))
                    if o.Transparency < 0.99 then
                        setp(p, "Transparency", cfg.Transparency)
                    end
                end)
            end
        end
    end
end

------------------------------------------------------------------
-- Общий цикл для Gun Chams и Arms
------------------------------------------------------------------
local loop = nil

local function syncLoop()
    local need = GC.Enabled or M.Arms.Left.Enabled or M.Arms.Right.Enabled
    if need and not loop then
        loop = RunService.RenderStepped:Connect(function()
            if GC.Enabled then gcStep() end
            armStep()
        end)
    elseif not need and loop then
        loop:Disconnect()
        loop = nil
    end
end

function M.SetGunChams(state)
    GC.Enabled = state
    if not state then
        gcRestoreAll()
        gcDestroyHighlight()
    end
    syncLoop()
end

function M.SetArm(side, state) -- side = "Left" | "Right"
    local cfg = M.Arms[side]
    if not cfg then return end
    cfg.Enabled = state
    if not state then armRestore(side) end
    syncLoop()
end

function M.Unload()
    M.SetViewModel(false)
    M.SetGunChams(false)
    M.SetArm("Left", false)
    M.SetArm("Right", false)
    getgenv().ViewModelMod = nil
end

getgenv().ViewModelMod = M
return M
