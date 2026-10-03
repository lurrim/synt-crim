local Workspace  = cloneref(game:GetService("Workspace"))
local RunService = cloneref(game:GetService("RunService"))
local Players    = cloneref(game:GetService("Players"))
local CoreGui    = game:GetService("CoreGui")

local ESP = {
    Enabled = true,
    TeamCheck = true,
    MaxDistance = 200,
    FontSize = 11,
    FadeOut = { OnDistance = true },
    Options = {
        Friendcheck = true, FriendcheckRGB = Color3.fromRGB(0, 255, 0),
    },
    Drawing = {
        Chams = {
            Enabled = true,
            Thermal = true,
            FillRGB = Color3.fromRGB(119, 120, 255),
            Fill_Transparency = 100,
            OutlineRGB = Color3.fromRGB(119, 120, 255),
            Outline_Transparency = 100,
            VisibleCheck = true,
            MaxDistance = 200,
        },
        Names = { Enabled = true },
        Distances = { Enabled = true, Position = "Text" },
        Weapons = { Enabled = true, WeaponTextRGB = Color3.fromRGB(119, 120, 255) },
        Healthbar = {
            Enabled = true,
            HealthText = true, Lerp = false, HealthTextRGB = Color3.fromRGB(119, 120, 255),
            Width = 2.5,
            Smooth = true,       -- плавное изменение полоски
            SmoothSpeed = 8,     -- больше = быстрее
            TextFadeSpeed = 10,  -- скорость появления/исчезновения текста
            Gradient = true,
            GradientRGB1 = Color3.fromRGB(200, 0, 0),
            GradientRGB2 = Color3.fromRGB(60, 60, 125),
            GradientRGB3 = Color3.fromRGB(119, 120, 255),
        },
        Boxes = {
            Animate = true,
            RotationSpeed = 300,
            BlackOutline = true, -- чёрный внешний оутлайн
            Gradient = false, GradientRGB1 = Color3.fromRGB(119, 120, 255), GradientRGB2 = Color3.fromRGB(0, 0, 0),
            GradientFill = true, GradientFillRGB1 = Color3.fromRGB(119, 120, 255), GradientFillRGB2 = Color3.fromRGB(0, 0, 0),
            Filled = { Enabled = true, Transparency = 0.75 },
            Full = { Enabled = true },
        },
    },
}

local lplayer = Players.LocalPlayer
local floor, max, min, sin, cos, atan, pi, exp = math.floor, math.max, math.min, math.sin, math.cos, math.atan, math.pi, math.exp
local fromOffset = UDim2.fromOffset
local RGB = Color3.fromRGB
local WHITE, BLACK = RGB(255, 255, 255), RGB(0, 0, 0)
local OCCLUDED, ALWAYS = Enum.HighlightDepthMode.Occluded, Enum.HighlightDepthMode.AlwaysOnTop

------------------------------------------------------------------
-- Кэш свойств: пишем в Instance только если значение реально изменилось
------------------------------------------------------------------
local cache = setmetatable({}, { __mode = "k" })

local function set(obj, prop, val)
    local c = cache[obj]
    if not c then c = {}; cache[obj] = c end
    if c[prop] ~= val then
        c[prop] = val
        obj[prop] = val
    end
end

local function place(obj, x, y, w, h)
    x, y = floor(x), floor(y)
    local c = cache[obj]
    if not c then c = {}; cache[obj] = c end
    if c.x ~= x or c.y ~= y then
        c.x, c.y = x, y
        obj.Position = fromOffset(x, y)
    end
    if w then
        w, h = floor(w), floor(h)
        if c.w ~= w or c.h ~= h then
            c.w, c.h = w, h
            obj.Size = fromOffset(w, h)
        end
    end
end

local function new(class, props)
    local inst = Instance.new(class)
    for k, v in pairs(props) do inst[k] = v end
    return inst
end

------------------------------------------------------------------
local ScreenGui = new("ScreenGui", {
    Name = "ESPHolder", Parent = CoreGui,
    ZIndexBehavior = Enum.ZIndexBehavior.Sibling, ResetOnSpawn = false,
})

local function newText(parent)
    return new("TextLabel", {
        Parent = parent, Size = UDim2.fromOffset(100, 20), AnchorPoint = Vector2.new(0.5, 0.5),
        BackgroundTransparency = 1, TextColor3 = WHITE, Font = Enum.Font.Code,
        TextSize = ESP.FontSize, TextStrokeTransparency = 0, TextStrokeColor3 = BLACK,
        RichText = true,
    })
end

local list = {}
local idxCounter = 0

local function createESP(plr)
    if list[plr] then return end -- защита от дублей (PlayerAdded + стартовый цикл)

    idxCounter += 1
    local D = ESP.Drawing
    local root = new("Frame", {
        Parent = ScreenGui, Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1,
        BorderSizePixel = 0, Visible = false, Name = plr.Name,
    })

    local e = { root = root, shown = false, idx = idxCounter, conns = {} }

    -- Внешний чёрный оутлайн (под боксом)
    e.BlackOut = new("Frame", {
        Parent = root, ZIndex = 1, BackgroundTransparency = 1, BorderSizePixel = 0, Visible = false,
    })
    e.BlackOutS = new("UIStroke", {
        Parent = e.BlackOut, Color = BLACK, Thickness = 1, LineJoinMode = Enum.LineJoinMode.Miter,
    })

    -- Сам бокс: заливка + белая обводка
    e.Box = new("Frame", {
        Parent = root, ZIndex = 2, BackgroundColor3 = WHITE, BorderSizePixel = 0,
    })
    e.Grad1 = new("UIGradient", {
        Parent = e.Box, Enabled = D.Boxes.GradientFill,
        Color = ColorSequence.new(D.Boxes.GradientFillRGB1, D.Boxes.GradientFillRGB2),
    })
    e.Outline = new("UIStroke", {
        Parent = e.Box, Enabled = true, Transparency = 0, Thickness = 1,
        Color = WHITE, LineJoinMode = Enum.LineJoinMode.Miter,
    })
    e.Grad2 = new("UIGradient", {
        Parent = e.Outline, Enabled = D.Boxes.Gradient,
        Color = ColorSequence.new(D.Boxes.GradientRGB1, D.Boxes.GradientRGB2),
    })

    e.BehindHB = new("Frame", { Parent = root, ZIndex = 1, BackgroundColor3 = BLACK, BorderSizePixel = 0 })
    e.HB = new("Frame", { Parent = root, ZIndex = 2, BackgroundColor3 = WHITE, BorderSizePixel = 0 })
    e.HBGrad = new("UIGradient", {
        Parent = e.HB, Enabled = D.Healthbar.Gradient, Rotation = -90,
        Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0, D.Healthbar.GradientRGB1),
            ColorSequenceKeypoint.new(0.5, D.Healthbar.GradientRGB2),
            ColorSequenceKeypoint.new(1, D.Healthbar.GradientRGB3),
        }),
    })

    e.Name = newText(root)
    e.Distance = newText(root)
    e.Weapon = newText(root)
    e.Weapon.Text = "none"
    e.Weapon.TextColor3 = D.Weapons.WeaponTextRGB
    e.HealthText = newText(root)
    e.HealthText.RichText = false
    -- текст прижат правым краем и стоит слева от полоски
    e.HealthText.AnchorPoint = Vector2.new(1, 0.5)
    e.dispHealth, e.textAlpha = nil, 0

    -- Основной Highlight на настоящем персонаже
    e.Chams = new("Highlight", {
        Parent = root, FillTransparency = 1, OutlineTransparency = 0,
        FillColor = D.Chams.FillRGB, OutlineColor = D.Chams.OutlineRGB,
        DepthMode = ALWAYS, Enabled = false,
    })

    -- Респавн: сразу сбрасываем кэш персонажа, чтобы update переискал части
    e.conns[1] = plr.CharacterAdded:Connect(function()
        e.char, e.hrp, e.hum, e.nextFind = nil, nil, nil, 0
    end)

    -- Друзей проверяем ОДИН раз
    e.friend = false
    if ESP.Options.Friendcheck then
        task.spawn(function()
            local ok, res = pcall(lplayer.IsFriendsWith, lplayer, plr.UserId)
            e.friend = ok and res or false
        end)
    end

    list[plr] = e
end

local function removeESP(plr)
    local e = list[plr]
    if e then
        for _, c in ipairs(e.conns) do c:Disconnect() end
        e.root:Destroy()
        list[plr] = nil
    end
end

local function hide(e)
    if e.shown then
        e.shown = false
        e.root.Visible = false
        e.dispHealth, e.textAlpha = nil, 0 -- при новом появлении без «прокрутки»
        -- через set(), чтобы кэш знал, что Highlight выключен
        set(e.Chams, "Enabled", false)
    end
end

------------------------------------------------------------------
local rotation, frame = -45, 0

local function update(plr, e, camPos, cam, vpY, rot, tickNow, dt)
    -- Персонаж / части. Переискиваем при смене персонажа ИЛИ если части пропали
    -- (при респавне Character появляется раньше, чем HumanoidRootPart)
    local char = plr.Character
    local hrp, hum = e.hrp, e.hum
    if char ~= e.char then
        e.char = char
        e.nextFind = 0
        hrp, hum = nil, nil
        e.hrp, e.hum = nil, nil
        e.Chams.Adornee = char
    end
    if char and (not hrp or not hum or not hrp.Parent or not hum.Parent) and tickNow >= (e.nextFind or 0) then
        e.nextFind = tickNow + 0.25 -- не чаще 4 раз в секунду
        hrp = char:FindFirstChild("HumanoidRootPart")
        hum = char:FindFirstChildOfClass("Humanoid")
        e.hrp, e.hum = hrp, hum
    end
    if not hrp or not hum or not hrp.Parent then return hide(e) end

    -- team check
    if ESP.TeamCheck then
        local lt, pt = lplayer.Team, plr.Team
        if not ((lt ~= pt and pt) or (not lt and not pt)) then return hide(e) end
    end

    local hrpPos = hrp.Position
    local dist = (camPos - hrpPos).Magnitude / 3.5714285714
    if dist > ESP.MaxDistance then return hide(e) end

    local pos, onScreen = cam:WorldToScreenPoint(hrpPos)
    if not onScreen then return hide(e) end

    if not e.shown then
        e.shown = true
        e.root.Visible = true
    end

    local D = ESP.Drawing
    local X, Y = pos.X, pos.Y
    local scale = (hrp.Size.Y * vpY) / (pos.Z * 2)
    local w, h = 3 * scale, 4.5 * scale
    local left, top = X - w / 2, Y - h / 2

    local fade = 0
    if ESP.FadeOut.OnDistance then
        fade = floor((1 - max(0.1, 1 - dist / ESP.MaxDistance)) * 20) / 20
    end

    -- Chams
    do
        local C = D.Chams
        local ch = e.Chams
        local on = C.Enabled and dist <= (C.MaxDistance or ESP.MaxDistance)

        set(ch, "Enabled", on)
        set(ch, "FillColor", C.FillRGB)
        set(ch, "OutlineColor", C.OutlineRGB)
        -- VisibleCheck = true: только когда видно; false: сквозь стены
        set(ch, "DepthMode", C.VisibleCheck and OCCLUDED or ALWAYS)

        if C.Thermal then
            if (frame + e.idx) % 3 == 0 then
                local b = atan(sin(tickNow * 2)) * 2 / pi
                ch.FillTransparency = max(0, C.Fill_Transparency * b * 0.01)
                ch.OutlineTransparency = max(0, C.Outline_Transparency * b * 0.01)
            end
        else
            set(ch, "FillTransparency", C.Fill_Transparency * 0.01)
            set(ch, "OutlineTransparency", C.Outline_Transparency * 0.01)
        end
    end

    -- Box: белый оутлайн + чёрный снаружи
    do
        local B = D.Boxes
        local box = e.Box
        local show = B.Full.Enabled

        place(box, left, top, w, h)
        set(box, "Visible", show)
        local base = (B.Filled.Enabled and B.GradientFill) and B.Filled.Transparency or 1
        set(box, "BackgroundTransparency", base + (1 - base) * fade)
        set(e.Outline, "Transparency", fade)
        set(e.Outline, "Color", WHITE)

        local bo = show and B.BlackOutline
        set(e.BlackOut, "Visible", bo)
        if bo then
            place(e.BlackOut, left - 1, top - 1, w + 2, h + 2)
            set(e.BlackOutS, "Transparency", fade)
        end

        if B.Animate and w > 20 and (frame + e.idx) % 3 == 0 then
            e.Grad1.Rotation = rot
            e.Grad2.Rotation = rot
        end
    end

    -- Healthbar
    do
        local H = D.Healthbar
        local maxHp = hum.MaxHealth
        local target = maxHp > 0 and max(0, min(1, hum.Health / maxHp)) or 0

        -- плавная полоска: быстро в начале, медленно к концу
        if not e.dispHealth or not H.Smooth then
            e.dispHealth = target
        else
            local k = 1 - exp(-dt * H.SmoothSpeed)
            e.dispHealth = e.dispHealth + (target - e.dispHealth) * k
            if math.abs(target - e.dispHealth) < 0.001 then e.dispHealth = target end
        end
        local health = e.dispHealth

        local hbX = left - 6
        set(e.HB, "Visible", H.Enabled)
        set(e.BehindHB, "Visible", H.Enabled)
        place(e.HB, hbX, top + h * (1 - health), H.Width, h * health)
        place(e.BehindHB, hbX, top, H.Width, h)
        set(e.HB, "BackgroundTransparency", fade)
        set(e.BehindHB, "BackgroundTransparency", fade)

        -- плавное появление/исчезновение текста
        local ht = e.HealthText
        local wantText = H.HealthText and target < 1
        local ka = 1 - exp(-dt * H.TextFadeSpeed)
        e.textAlpha = e.textAlpha + ((wantText and 1 or 0) - e.textAlpha) * ka
        if e.textAlpha < 0.01 then e.textAlpha = 0 end

        if e.textAlpha > 0 then
            -- слева от полоски, на уровне верхушки заливки
            place(ht, hbX - 3, top + h * (1 - health))
            set(ht, "Text", tostring(floor(health * 100 + 0.5)))
            set(ht, "Visible", true)
            local tr = fade + (1 - fade) * (1 - e.textAlpha)
            set(ht, "TextTransparency", tr)
            set(ht, "TextStrokeTransparency", tr)
            if H.Lerp then
                set(ht, "TextColor3",
                    target >= 0.75 and RGB(0, 255, 0) or target >= 0.5 and RGB(255, 255, 0)
                    or target >= 0.25 and RGB(255, 170, 0) or RGB(255, 0, 0))
            else
                set(ht, "TextColor3", H.HealthTextRGB)
            end
        else
            set(ht, "Visible", false)
        end
    end

    -- Name + Distance
    do
        local d = floor(dist)
        local mode = D.Distances.Position
        local nm = e.Name
        local textDue = tickNow >= (e.nextText or 0)
        if (textDue and e.lastD ~= d) or e.lastF ~= e.friend or e.lastMode ~= mode then
            e.nextText = tickNow + 0.2
            e.lastD, e.lastF, e.lastMode = d, e.friend, mode
            local prefix
            if ESP.Options.Friendcheck and e.friend then
                local c = ESP.Options.FriendcheckRGB
                prefix = string.format('(<font color="rgb(%d, %d, %d)">F</font>) ', c.R * 255, c.G * 255, c.B * 255)
            else
                prefix = '(<font color="rgb(255, 0, 0)">E</font>) '
            end
            if D.Distances.Enabled and mode == "Text" then
                nm.Text = prefix .. plr.Name .. " [" .. d .. "]"
            else
                nm.Text = prefix .. plr.Name
            end
            e.Distance.Text = d .. " meters"
        end

        set(nm, "Visible", D.Names.Enabled)
        place(nm, X, top - 9)
        set(nm, "TextTransparency", fade)

        local bottom = D.Distances.Enabled and mode == "Bottom"
        set(e.Distance, "Visible", bottom)
        if bottom then
            place(e.Distance, X, top + h + 7)
            set(e.Distance, "TextTransparency", fade)
        end

        local wp = e.Weapon
        set(wp, "Visible", D.Weapons.Enabled)
        place(wp, X, top + h + (bottom and 18 or 8))
        set(wp, "TextTransparency", fade)
    end
end

RunService.RenderStepped:Connect(function(dt)
    frame += 1
    local cam = Workspace.CurrentCamera
    if not cam then return end

    if not ESP.Enabled then
        for _, e in pairs(list) do hide(e) end
        return
    end

    local tickNow = tick()
    rotation += dt * ESP.Drawing.Boxes.RotationSpeed * cos(pi / 4 * tickNow - pi / 2)
    if not ESP.Drawing.Boxes.Animate then rotation = -45 end

    local camPos = cam.CFrame.Position
    local vpY = cam.ViewportSize.Y
    for plr, e in pairs(list) do
        update(plr, e, camPos, cam, vpY, rotation, tickNow, dt)
    end
end)

for _, v in ipairs(Players:GetPlayers()) do
    if v ~= lplayer then createESP(v) end
end
Players.PlayerAdded:Connect(function(v)
    if v ~= lplayer then createESP(v) end
end)
Players.PlayerRemoving:Connect(removeESP)

-- Применяет настройки, которые читались только при создании
function ESP.Refresh()
    local D = ESP.Drawing
    for _, e in pairs(list) do
        e.Grad1.Enabled = D.Boxes.GradientFill
        e.Grad1.Color = ColorSequence.new(D.Boxes.GradientFillRGB1, D.Boxes.GradientFillRGB2)
        e.Grad2.Enabled = D.Boxes.Gradient
        e.Grad2.Color = ColorSequence.new(D.Boxes.GradientRGB1, D.Boxes.GradientRGB2)

        e.HBGrad.Enabled = D.Healthbar.Gradient
        e.HBGrad.Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0, D.Healthbar.GradientRGB1),
            ColorSequenceKeypoint.new(0.5, D.Healthbar.GradientRGB2),
            ColorSequenceKeypoint.new(1, D.Healthbar.GradientRGB3),
        })

        e.Weapon.TextColor3 = D.Weapons.WeaponTextRGB
        for _, t in ipairs({ e.Name, e.Distance, e.Weapon, e.HealthText }) do
            t.TextSize = ESP.FontSize
        end

    end
end

getgenv().ESP = ESP
