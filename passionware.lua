--[[
    PASSIONWARE  ·  DARK LIQUID GLASS
    Tabs:  passion  |  settings

    Notes
    * x hides the window. The toggle key (default RightShift) shows and hides it. Change the key in settings.
    * "Unload script" in settings fully removes the UI and disconnects every event.
    * Colour pickers take a hex code or a hue / saturation / brightness slider.
    * Background links: paste an https link, an rbxassetid:// or a plain asset number, then press Set
      or Enter. Https links need writefile + getcustomasset in your executor. Saved links persist to
      LINK_FILE when writefile/readfile exist.
    * URLs marked "CORRUPTED" were corrupted in the .txt. Paste real ones in.
]]

--// SERVICES ---------------------------------------------------------------
local Players            = game:GetService("Players")
local UIS                = game:GetService("UserInputService")
local RunService         = game:GetService("RunService")
local TweenService       = game:GetService("TweenService")
local StarterGui         = game:GetService("StarterGui")
local Lighting           = game:GetService("Lighting")
local TeleportService    = game:GetService("TeleportService")
local HttpService        = game:GetService("HttpService")
local MarketplaceService = game:GetService("MarketplaceService")
local GuiService         = game:GetService("GuiService")
local Stats              = game:GetService("Stats")
local Debris             = game:GetService("Debris")
local CoreGui            = game:GetService("CoreGui")

local lp  = Players.LocalPlayer
local env = (getgenv and getgenv()) or _G

--// CONFIG -----------------------------------------------------------------
local CONFIG = {
    BackgroundImage = "",          -- e.g. "rbxassetid://123456789"
    BackgroundImageTransparency = 0.35,
}

local LINK_FILE = "passionware_links.json"

--// RUN GUARD + CLEANUP ----------------------------------------------------
local MYID = math.random(1, 1000000)
_G.SkidwareId = MYID
local function alive() return _G.SkidwareId == MYID end

local guiParent = (gethui and gethui()) or CoreGui
for _, root in ipairs({ guiParent, CoreGui }) do
    for _, g in ipairs(root:GetChildren()) do
        if g.Name == "SkidwareUI" or g.Name == "VuxLethalUI" or g.Name == "PassionwareUI" then
            pcall(function() g:Destroy() end)
        end
    end
end

local CONNS = {}
local function C(signal, fn)
    local c = signal:Connect(fn)
    table.insert(CONNS, c)
    return c
end

local function notify(title, text, dur)
    pcall(function()
        StarterGui:SetCore("SendNotification", { Title = title, Text = text, Duration = dur or 4 })
    end)
end

--==========================================================================
--  PASSIONWARE CORE
--==========================================================================
local S = {
    Enabled           = true,
    LethalEnabled     = true,
    LethalAnim        = "rbxassetid://10503381238",
    LethalDelay       = 0.36,
    LethalJump        = 1,
    LethalAccuracy    = 13,
    LethalCancelDelay = 0.25,
    LethalMode        = "V1",
    CancelEnabled     = true,
    CooldownActive    = true,
    NoClipEnabled     = true,
    DashRange         = 8,
    TouchMode         = false,
    Platform          = "PC",
    Keybind           = "E",
    CooldownAnims     = { ["10491993682"] = true, ["10479335397"] = true, ["13380255751"] = true },
    CamSmooth         = false,
    CamSmoothSpeed    = 12,
}

local active      = false
local onCooldown  = false
local casting     = false
local cooldownBar, cooldownFill

local function fireDash()
    local char = lp.Character
    if not char then return end
    local remote = char:FindFirstChild("Communicate")
    if remote then
        remote:FireServer({ Dash = Enum.KeyCode.W, Key = Enum.KeyCode.Q, Goal = "KeyPress" })
    end
end

-- Cam Smooth: while a dash is rotating the character, the default camera
-- can snap along with it. When enabled, this takes the camera scriptable
-- for the dash's duration and eases its CFrame toward the character's
-- normal follow position instead of jumping frame to frame. Camera
-- distance/pitch the player already had is preserved, only the sudden
-- rotation is smoothed out.
local camSmoothConn, camOffset
local function camSmoothStop()
    if camSmoothConn then camSmoothConn:Disconnect(); camSmoothConn = nil end
    local cam = workspace.CurrentCamera
    if cam and cam.CameraType == Enum.CameraType.Scriptable then
        cam.CameraType = Enum.CameraType.Custom
    end
end
local function camSmoothStart()
    if not S.CamSmooth then return end
    local char = lp.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    local cam = workspace.CurrentCamera
    if not hrp or not cam then return end
    camOffset = hrp.CFrame:Inverse() * cam.CFrame
    cam.CameraType = Enum.CameraType.Scriptable
    if camSmoothConn then camSmoothConn:Disconnect() end
    camSmoothConn = RunService.RenderStepped:Connect(function(dt)
        if not alive() or not S.CamSmooth or not active then
            camSmoothStop()
            return
        end
        local h = lp.Character and lp.Character:FindFirstChild("HumanoidRootPart")
        local c = workspace.CurrentCamera
        if not h or not c then camSmoothStop() return end
        local target = h.CFrame * camOffset
        local alpha = 1 - math.exp(-S.CamSmoothSpeed * dt)
        c.CFrame = c.CFrame:Lerp(target, alpha)
    end)
end

local function restoreRotate()
    active = false
    camSmoothStop()
    local char = lp.Character
    local hum = char and char:FindFirstChild("Humanoid")
    if hum then hum.AutoRotate = true end
end

local function clearMovers()
    restoreRotate()
    local char = lp.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if hrp then
        for _, v in pairs(hrp:GetChildren()) do
            if v:IsA("BodyVelocity") or v:IsA("LinearVelocity") or v:IsA("Attachment") or v:IsA("BodyAngularVelocity") then
                v:Destroy()
            end
        end
        hrp.AssemblyLinearVelocity = Vector3.zero
    end
end

local function startCooldown(t)
    if not alive() or onCooldown then return end
    onCooldown = true
    if cooldownBar and cooldownFill then
        cooldownBar.Visible = true
        cooldownFill.Size = UDim2.new(1, 0, 1, 0)
        TweenService:Create(cooldownFill, TweenInfo.new(t, Enum.EasingStyle.Linear), { Size = UDim2.new(0, 0, 1, 0) }):Play()
        task.delay(t, function()
            onCooldown = false
            cooldownBar.Visible = false
        end)
    else
        task.delay(t, function() onCooldown = false end)
    end
end

local function nearestTarget()
    local char = lp.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return nil end
    local params = OverlapParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = { char }
    local parts = workspace:GetPartBoundsInRadius(hrp.Position, S.DashRange, params)
    local best, bestDist = nil, S.DashRange
    for _, part in pairs(parts) do
        local model = part:FindFirstAncestorOfClass("Model")
        if model and model:FindFirstChild("Humanoid") and model ~= char then
            local t = model:FindFirstChild("Torso") or model:FindFirstChild("UpperTorso") or model:FindFirstChild("HumanoidRootPart")
            if t then
                local d = (hrp.Position - t.Position).Magnitude
                if d < bestDist then bestDist, best = d, t end
            end
        end
    end
    return best
end

local function lethal()
    if not alive() or casting or onCooldown then return end
    if not S.Enabled or not S.LethalEnabled then return end
    local char = lp.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    local hum = char and char:FindFirstChild("Humanoid")
    if not hrp or not hum then return end

    local target = nearestTarget()
    if not target then restoreRotate() return end

    casting = true
    if not S.TouchMode then task.wait(S.LethalDelay) end
    if not alive() then casting = false return end

    hrp.AssemblyLinearVelocity = Vector3.new(hrp.AssemblyLinearVelocity.X, S.LethalJump, hrp.AssemblyLinearVelocity.Z)
    active = true
    camSmoothStart()
    fireDash()

    local t0, flipped = tick(), false
    local dir  = (target.Position - hrp.Position).Unit
    local side = Vector3.new(-dir.Z, 0, dir.X)

    local bav
    if S.LethalMode == "V1" then
        bav = Instance.new("BodyAngularVelocity")
        bav.MaxTorque = Vector3.new(0, 1000000, 0)
        bav.P = 15000
        bav.Parent = hrp
    end

    local conn
    local function finish(full)
        if bav then bav:Destroy() end
        if full then clearMovers() else restoreRotate() end
        casting = false
        if conn then conn:Disconnect() end
    end

    conn = RunService.Heartbeat:Connect(function()
        if not alive() or not target or not target.Parent or not hrp or not hrp.Parent then
            finish(false)
            return
        end
        local el = tick() - t0
        local tp, mp = target.Position, hrp.Position
        hum.AutoRotate = false

        if S.LethalMode == "V1" then
            local ang = (el / 0.45) * (math.pi / 1.5)
            local rad = S.LethalAccuracy * (1 - math.clamp(el / 0.45, 0, 1))
            local goal = tp + ((side * math.cos(ang)) + (dir * math.sin(ang))) * rad
            local look = CFrame.lookAt(mp, Vector3.new(goal.X, mp.Y, goal.Z))
            local rel = hrp.CFrame:Inverse() * look
            local _, ry, _ = rel:ToEulerAnglesXYZ()
            if bav and bav.Parent then
                bav.AngularVelocity = Vector3.new(0, ry * 30, 0)
            end
        elseif el >= S.LethalAccuracy and not flipped then
            hrp.CFrame = hrp.CFrame * CFrame.Angles(0, math.pi, 0)
            flipped = true
        end

        local flat = (Vector2.new(mp.X, mp.Z) - Vector2.new(tp.X, tp.Z)).Magnitude
        if S.CancelEnabled and el > S.LethalCancelDelay and flat < 2.2 then
            finish(true)
            return
        end
        if not S.Enabled or el > 1.5 then
            finish(false)
            return
        end
    end)
end

-- animation + input hooks
local function hookCharacter(char)
    if not alive() then return end
    local hum = char:WaitForChild("Humanoid")
    hum.AnimationPlayed:Connect(function(track)
        if not alive() then return end
        local id = tostring(track.Animation.AnimationId):match("%d+")
        if S.CooldownActive and S.CooldownAnims[id] then startCooldown(5) end
        if S.TouchMode or not S.Enabled then return end
        if track.Animation.AnimationId == S.LethalAnim then lethal() end
    end)
end

C(UIS.InputBegan, function(input, processed)
    if not alive() or processed then return end
    if S.TouchMode and S.Platform == "PC" then
        local ok, kc = pcall(function() return Enum.KeyCode[S.Keybind:upper()] end)
        if ok and kc and input.KeyCode == kc then lethal() end
    end
end)

C(RunService.Stepped, function()
    if not alive() or not S.NoClipEnabled or not active or not lp.Character then return end
    for _, m in pairs(workspace:GetChildren()) do
        if m:IsA("Model") and m ~= lp.Character and (m:FindFirstChild("Humanoid") or m:FindFirstChildOfClass("Humanoid")) then
            for _, p in pairs(m:GetDescendants()) do
                if p:IsA("BasePart") and p.CanCollide then p.CanCollide = false end
            end
        end
    end
end)

if lp.Character then task.spawn(hookCharacter, lp.Character) end
C(lp.CharacterAdded, hookCharacter)

--==========================================================================
--  DARK LIQUID GLASS UI TOOLKIT
--==========================================================================
local WHITE    = Color3.new(1, 1, 1)
local TEXT     = Color3.fromRGB(232, 236, 240)
local DARK_TXT = Color3.fromRGB(18, 10, 16)
local FONT, FONTB = Enum.Font.GothamMedium, Enum.Font.GothamBold

local Theme = { Color = Color3.fromRGB(255, 170, 200) }
local themeFns = {}

local GCFG = {
    Fill   = 0.85,                              -- glass opacity (higher = more solid)
    Tint   = Color3.fromRGB(12, 16, 20),        -- dark glass tint
    Border = 0.28,                              -- rim strength
    Radius = 22,                                -- main window corner radius
}
local GLASS = setmetatable({}, { __mode = "k" })

local function bind(fn) table.insert(themeFns, fn); pcall(fn, Theme.Color) end
local function bindProp(inst, prop, fn) bind(function(c) inst[prop] = fn(c) end) end
local function same(c) return c end
local function setThemeColor(c)
    Theme.Color = c
    for _, f in ipairs(themeFns) do pcall(f, c) end
end

local function mk(class, props, parent)
    local o = Instance.new(class)
    for k, v in pairs(props) do o[k] = v end
    o.Parent = parent
    return o
end
local function round(p, r) return mk("UICorner", { CornerRadius = UDim.new(0, r or 6) }, p) end

local function paintGlass(f)
    local g = GLASS[f]
    if not g then return end
    local t = math.clamp(1 - GCFG.Fill * g.s, 0, 0.98)
    f.BackgroundColor3 = GCFG.Tint
    f.BackgroundTransparency = t
    g.grad.Color = ColorSequence.new(WHITE)
    g.stroke.Transparency = math.clamp(1 - GCFG.Border, 0, 1)
    local r = UDim.new(0, g.main and GCFG.Radius or g.r)
    g.corner.CornerRadius = r
    g.sc.CornerRadius = r
end

-- s = strength (how solid this surface is), isMain = the window itself
local function glass(f, radius, s, isMain)
    f.BorderSizePixel = 0
    local corner = round(f, radius or 12)
    local grad = mk("UIGradient", { Rotation = 90 }, f)
    local stroke = mk("UIStroke", { Color = WHITE, Thickness = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, f)
    local sheen = mk("Frame", { Size = UDim2.new(1, 0, 0.5, 0), BackgroundColor3 = WHITE, BackgroundTransparency = 0.93,
        BorderSizePixel = 0, ZIndex = 1 }, f)
    local sc = round(sheen, radius or 12)
    mk("UIGradient", { Rotation = 90, Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) }) }, sheen)
    GLASS[f] = { s = s or 0.6, main = isMain, r = radius or 12, corner = corner, grad = grad, stroke = stroke, sheen = sheen, sc = sc }
    paintGlass(f)
    return f
end

local function repaintAll()
    for f in pairs(GLASS) do paintGlass(f) end
end

local orders = setmetatable({}, { __mode = "k" })
local function order(p) orders[p] = (orders[p] or 0) + 1; return orders[p] end

local function text(parent, str, size, bold, props)
    local t = { Text = str, Font = bold and FONTB or FONT, TextSize = size or 12, TextColor3 = TEXT,
        BackgroundTransparency = 1, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 3 }
    for k, v in pairs(props or {}) do t[k] = v end
    return mk("TextLabel", t, parent)
end

local function row(parent, h)
    local f = mk("Frame", { Size = UDim2.new(1, 0, 0, h or 32), LayoutOrder = order(parent) }, parent)
    glass(f, 12, 0.6)
    return f
end

local function group(parent)
    local g = mk("Frame", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1, BorderSizePixel = 0, LayoutOrder = order(parent) }, parent)
    mk("UIListLayout", { Padding = UDim.new(0, 5), SortOrder = Enum.SortOrder.LayoutOrder }, g)
    return g
end

local function body(g, visible)
    local b = mk("Frame", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1, Visible = visible or false, LayoutOrder = 2 }, g)
    mk("UIListLayout", { Padding = UDim.new(0, 5), SortOrder = Enum.SortOrder.LayoutOrder }, b)
    mk("UIPadding", { PaddingLeft = UDim.new(0, 12) }, b)
    return b
end

local function chevron(head, rightOffset, bodyFrame)
    local b = mk("TextButton", { Text = "v", Font = FONTB, TextSize = 13, TextColor3 = TEXT, BackgroundTransparency = 1,
        Size = UDim2.fromOffset(22, 22), AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, rightOffset, 0.5, 0), ZIndex = 3 }, head)
    b.MouseButton1Click:Connect(function()
        bodyFrame.Visible = not bodyFrame.Visible
        TweenService:Create(b, TweenInfo.new(0.2, Enum.EasingStyle.Quint), { Rotation = bodyFrame.Visible and 180 or 0 }):Play()
    end)
    return b
end

local function pulse(b)
    local base = b.BackgroundTransparency
    TweenService:Create(b, TweenInfo.new(0.08), { BackgroundTransparency = math.max(0, base - 0.2) }):Play()
    task.delay(0.09, function()
        if b.Parent then TweenService:Create(b, TweenInfo.new(0.3, Enum.EasingStyle.Elastic), { BackgroundTransparency = base }):Play() end
    end)
end

-- active pill: accent fill with dark text; inactive: back to glass.
-- Labels are separate TextLabels (ZIndex above the sheen) so the names always show.
local function setActive(b, on)
    local lbl = b:FindFirstChild("Label")
    if on then
        b.BackgroundColor3 = Theme.Color
        b.BackgroundTransparency = 0.05
        if lbl then lbl.TextColor3 = DARK_TXT end
    else
        paintGlass(b)
        if lbl then lbl.TextColor3 = TEXT end
    end
end

local UI = {}

function UI.Section(parent, title)
    local f = mk("Frame", { Size = UDim2.new(1, 0, 0, 22), BackgroundTransparency = 1, LayoutOrder = order(parent) }, parent)
    local dot = mk("Frame", { Size = UDim2.fromOffset(6, 6), Position = UDim2.fromOffset(4, 8), BorderSizePixel = 0 }, f)
    round(dot, 3)
    bindProp(dot, "BackgroundColor3", same)
    text(f, title:upper(), 10, true, { Size = UDim2.new(1, -20, 0, 18), Position = UDim2.fromOffset(16, 0) })
    local line = mk("Frame", { Size = UDim2.new(1, 0, 0, 1), Position = UDim2.new(0, 0, 1, -1), BorderSizePixel = 0,
        BackgroundColor3 = WHITE, BackgroundTransparency = 0.7 }, f)
    mk("UIGradient", { Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) }) }, line)
    return f
end

function UI.Toggle(parent, o)
    local g = group(parent)
    local head = row(g, 32); head.LayoutOrder = 1
    local lbl = text(head, o.Name, 12, false, { Size = UDim2.new(1, -90, 1, 0), Position = UDim2.fromOffset(12, 0) })
    local rightPad = o.Expandable and 38 or 12
    local sw = mk("TextButton", { Text = "", AutoButtonColor = false, Size = UDim2.fromOffset(38, 20),
        AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -rightPad, 0.5, 0), BorderSizePixel = 0,
        BackgroundColor3 = WHITE, BackgroundTransparency = 0.85, ZIndex = 3 }, head)
    round(sw, 10)
    mk("UIStroke", { Color = WHITE, Transparency = 0.7, Thickness = 1 }, sw)
    local knob = mk("Frame", { Size = UDim2.fromOffset(16, 16), Position = UDim2.fromOffset(2, 2),
        BackgroundColor3 = WHITE, BorderSizePixel = 0, ZIndex = 4 }, sw)
    round(knob, 8)

    local obj = { Name = o.Name, Row = g, Label = lbl }
    local state = o.Default == true
    local function paint()
        if state then
            sw.BackgroundColor3 = Theme.Color
            sw.BackgroundTransparency = 0.05
        else
            sw.BackgroundColor3 = WHITE
            sw.BackgroundTransparency = 0.85
        end
        TweenService:Create(knob, TweenInfo.new(0.2, Enum.EasingStyle.Quint),
            { Position = state and UDim2.fromOffset(20, 2) or UDim2.fromOffset(2, 2) }):Play()
    end
    bind(function() paint() end)
    function obj.Set(v, silent)
        state = v and true or false
        paint()
        if not silent and o.Callback then pcall(o.Callback, state) end
    end
    function obj.Get() return state end
    sw.MouseButton1Click:Connect(function() obj.Set(not state) end)

    if o.Expandable then
        obj.Body = body(g, false)
        chevron(head, -6, obj.Body)
    end
    return obj
end

function UI.Slider(parent, o)
    local min, max, dec = o.Min, o.Max, o.Decimals or 0
    local f = row(parent, 44)
    text(f, o.Name, 12, false, { Size = UDim2.new(0.6, 0, 0, 18), Position = UDim2.fromOffset(12, 4) })
    local box = mk("TextBox", { Size = UDim2.fromOffset(62, 18), AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 5),
        Font = FONT, TextSize = 11, TextColor3 = TEXT, ClearTextOnFocus = false, BorderSizePixel = 0,
        BackgroundColor3 = WHITE, BackgroundTransparency = 0.88, ZIndex = 3 }, f)
    round(box, 6)
    local hit = mk("TextButton", { Text = "", AutoButtonColor = false, BackgroundTransparency = 1,
        Size = UDim2.new(1, -24, 0, 20), Position = UDim2.new(0, 12, 1, -24), ZIndex = 3 }, f)
    local bar = mk("Frame", { Size = UDim2.new(1, 0, 0, 6), Position = UDim2.new(0, 0, 0.5, -3), BorderSizePixel = 0,
        BackgroundColor3 = WHITE, BackgroundTransparency = 0.8, ZIndex = 3 }, hit)
    round(bar, 3)
    local fill = mk("Frame", { Size = UDim2.new(0, 0, 1, 0), BorderSizePixel = 0, ZIndex = 3 }, bar)
    bindProp(fill, "BackgroundColor3", same)
    round(fill, 3)
    local knob = mk("Frame", { Size = UDim2.fromOffset(14, 14), AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.new(0, 0, 0.5, 0), BackgroundColor3 = WHITE, BorderSizePixel = 0, ZIndex = 4 }, bar)
    round(knob, 7)
    mk("UIStroke", { Color = Color3.new(0, 0, 0), Transparency = 0.6, Thickness = 1 }, knob)

    local value = o.Default or min
    local function fmt(v)
        if dec == 0 then return tostring(math.floor(v + 0.5)) end
        return string.format("%." .. dec .. "f", v)
    end
    local obj = { Row = f }
    local function setValue(v, fire)
        v = math.clamp(v, min, max)
        local m = 10 ^ dec
        v = math.floor(v * m + 0.5) / m
        value = v
        local pct = (v - min) / (max - min)
        fill.Size = UDim2.new(pct, 0, 1, 0)
        knob.Position = UDim2.new(pct, 0, 0.5, 0)
        if not box:IsFocused() then box.Text = fmt(v) end
        if fire and o.Callback then pcall(o.Callback, v) end
    end
    function obj.Set(v, silent) setValue(v, not silent) end
    function obj.Get() return value end
    setValue(value, false)

    local dragging = false
    local function fromPos(pos)
        local rel = (pos.X - bar.AbsolutePosition.X) / math.max(bar.AbsoluteSize.X, 1)
        setValue(min + (max - min) * math.clamp(rel, 0, 1), true)
    end
    hit.InputBegan:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            fromPos(i.Position)
        end
    end)
    C(UIS.InputChanged, function(i)
        if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
            fromPos(i.Position)
        end
    end)
    C(UIS.InputEnded, function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end)
    box.FocusLost:Connect(function()
        local n = tonumber(box.Text)
        if n then setValue(n, true) else box.Text = fmt(value) end
    end)
    return obj
end

function UI.Input(parent, o)
    local f = row(parent, 32)
    local lbl = text(f, o.Name, 12, false, { Size = UDim2.new(0.5, 0, 1, 0), Position = UDim2.fromOffset(12, 0) })
    local box = mk("TextBox", { Size = UDim2.new(0.42, 0, 0, 22), AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, 0),
        Font = FONT, TextSize = 11, TextColor3 = TEXT, ClearTextOnFocus = false, BorderSizePixel = 0,
        PlaceholderText = o.Placeholder or "", PlaceholderColor3 = Color3.fromRGB(140, 150, 160),
        Text = tostring(o.Default or ""), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 3 }, f)
    glass(box, 6, 0.8)
    mk("UIPadding", { PaddingLeft = UDim.new(0, 6) }, box)
    local obj = { Row = f, Label = lbl, Box = box }
    function obj.Set(v) box.Text = tostring(v) end
    box.FocusLost:Connect(function()
        if o.Numeric then
            local n = tonumber(box.Text)
            if n then
                if o.Callback then pcall(o.Callback, n) end
            else
                box.Text = tostring(o.Revert and o.Revert() or o.Default or "")
            end
        elseif o.Callback then
            pcall(o.Callback, box.Text)
        end
    end)
    return obj
end

function UI.Button(parent, o)
    local b = mk("TextButton", { Text = o.Name, Font = FONTB, TextSize = 12, TextColor3 = TEXT, BorderSizePixel = 0,
        Size = UDim2.new(1, 0, 0, 32), LayoutOrder = order(parent), AutoButtonColor = false }, parent)
    glass(b, 12, 0.8)
    b.MouseButton1Click:Connect(function()
        pulse(b)
        if o.Callback then pcall(o.Callback, b) end
    end)
    return b
end

function UI.Info(parent, name, default, onClick)
    local f = row(parent, 28)
    text(f, name, 11, false, { Size = UDim2.new(0.4, 0, 1, 0), Position = UDim2.fromOffset(12, 0) })
    local v
    if onClick then
        v = mk("TextButton", { Text = tostring(default), Font = FONTB, TextSize = 11, TextColor3 = TEXT, BackgroundTransparency = 1,
            TextXAlignment = Enum.TextXAlignment.Right, Size = UDim2.new(0.58, -12, 1, 0), Position = UDim2.new(0.42, 0, 0, 0), ZIndex = 3 }, f)
        v.MouseButton1Click:Connect(function() pcall(onClick) end)
    else
        v = text(f, tostring(default), 11, true, { TextXAlignment = Enum.TextXAlignment.Right,
            Size = UDim2.new(0.58, -12, 1, 0), Position = UDim2.new(0.42, 0, 0, 0) })
    end
    return { Set = function(_, s) v.Text = tostring(s) end }
end

function UI.Dropdown(parent, o)
    local g = group(parent)
    local head = row(g, 32); head.LayoutOrder = 1
    text(head, o.Name, 12, false, { Size = UDim2.new(0.45, 0, 1, 0), Position = UDim2.fromOffset(12, 0) })
    local cur = o.Default or o.Values[1]
    local btn = mk("TextButton", { Text = cur .. "  v", Font = FONTB, TextSize = 11, TextColor3 = TEXT, BorderSizePixel = 0,
        AutoButtonColor = false, Size = UDim2.fromOffset(124, 22), AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, 0), ZIndex = 3 }, head)
    glass(btn, 7, 0.9)
    local list = body(g, false)
    for i, v in ipairs(o.Values) do
        local b = mk("TextButton", { Text = v, Font = FONT, TextSize = 11, TextColor3 = TEXT, BorderSizePixel = 0,
            Size = UDim2.new(1, 0, 0, 26), LayoutOrder = i, AutoButtonColor = false }, list)
        glass(b, 8, 0.8)
        b.MouseButton1Click:Connect(function()
            cur = v
            btn.Text = v .. "  v"
            list.Visible = false
            if o.Callback then pcall(o.Callback, v) end
        end)
    end
    btn.MouseButton1Click:Connect(function() list.Visible = not list.Visible end)
    return { Get = function() return cur end }
end

-- Colour picker: hex code box + swatch on the head row, then hue / saturation / brightness sliders.
local function toHex(c)
    return string.format("%02X%02X%02X", math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5))
end

function UI.ColorPicker(parent, o)
    local g = group(parent)
    local head = row(g, 32); head.LayoutOrder = 1
    text(head, o.Name, 12, false, { Size = UDim2.new(0.4, 0, 1, 0), Position = UDim2.fromOffset(12, 0) })

    local hexBox = mk("TextBox", { Size = UDim2.fromOffset(78, 22), AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -10, 0.5, 0), Font = FONTB, TextSize = 11, TextColor3 = TEXT, ClearTextOnFocus = false,
        BorderSizePixel = 0, BackgroundColor3 = WHITE, BackgroundTransparency = 0.88, Text = "",
        PlaceholderText = "#RRGGBB", PlaceholderColor3 = Color3.fromRGB(140, 150, 160), ZIndex = 3 }, head)
    round(hexBox, 6)
    local swatch = mk("Frame", { Size = UDim2.fromOffset(18, 18), AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -94, 0.5, 0), BorderSizePixel = 0, ZIndex = 3 }, head)
    round(swatch, 5)
    mk("UIStroke", { Color = WHITE, Transparency = 0.4, Thickness = 1 }, swatch)

    local b = body(g, true)
    local start = o.Default or Color3.fromRGB(255, 255, 255)
    local h, s, v = start:ToHSV()
    local cur = start
    local sliders = {}

    local function refresh(fire)
        cur = Color3.fromHSV(h, s, v)
        swatch.BackgroundColor3 = cur
        if not hexBox:IsFocused() then hexBox.Text = "#" .. toHex(cur) end
        if fire and o.Callback then pcall(o.Callback, cur) end
    end

    sliders.H = UI.Slider(b, { Name = "Hue", Min = 0, Max = 360, Default = math.floor(h * 360 + 0.5),
        Callback = function(n) h = n / 360; refresh(true) end })
    sliders.S = UI.Slider(b, { Name = "Saturation", Min = 0, Max = 100, Default = math.floor(s * 100 + 0.5),
        Callback = function(n) s = n / 100; refresh(true) end })
    sliders.V = UI.Slider(b, { Name = "Brightness", Min = 0, Max = 100, Default = math.floor(v * 100 + 0.5),
        Callback = function(n) v = n / 100; refresh(true) end })

    hexBox.FocusLost:Connect(function()
        local hex = hexBox.Text:gsub("#", ""):gsub("%s", "")
        if hex:match("^%x%x%x%x%x%x$") then
            local c = Color3.fromRGB(tonumber(hex:sub(1, 2), 16), tonumber(hex:sub(3, 4), 16), tonumber(hex:sub(5, 6), 16))
            h, s, v = c:ToHSV()
            sliders.H.Set(h * 360, true)
            sliders.S.Set(s * 100, true)
            sliders.V.Set(v * 100, true)
            refresh(true)
        else
            hexBox.Text = "#" .. toHex(cur)
        end
    end)

    refresh(false)
    return {
        Set = function(col)
            h, s, v = col:ToHSV()
            sliders.H.Set(h * 360, true); sliders.S.Set(s * 100, true); sliders.V.Set(v * 100, true)
            refresh(false)
        end,
        Get = function() return cur end,
    }
end

local function page(parent)
    local p = mk("ScrollingFrame", { Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, BorderSizePixel = 0,
        ScrollBarThickness = 2, ScrollBarImageColor3 = WHITE, CanvasSize = UDim2.new(),
        AutomaticCanvasSize = Enum.AutomaticSize.Y, Visible = false }, parent)
    mk("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, p)
    mk("UIPadding", { PaddingRight = UDim.new(0, 8), PaddingBottom = UDim.new(0, 8), PaddingTop = UDim.new(0, 2) }, p)
    return p
end

--==========================================================================
--  WINDOW
--==========================================================================
local W, H = 600, 400
local gui = mk("ScreenGui", { Name = "PassionwareUI", ResetOnSpawn = false, ZIndexBehavior = Enum.ZIndexBehavior.Sibling }, guiParent)

local main = mk("Frame", { Name = "MainFrame", Size = UDim2.fromOffset(W, H), Position = UDim2.new(0.5, -W / 2, 0.5, -H / 2),
    ClipsDescendants = true, BorderSizePixel = 0 }, gui)
glass(main, GCFG.Radius, 0.9, true)
if UIS.TouchEnabled and not UIS.KeyboardEnabled then mk("UIScale", { Scale = 0.8 }, main) end

-- show / hide. The key is changeable in settings.
local uiKey = Enum.KeyCode.RightShift
local function setToggleKey(name)
    local ok, kc = pcall(function() return Enum.KeyCode[name] end)
    if not ok or not kc then
        ok, kc = pcall(function() return Enum.KeyCode[name:sub(1, 1):upper() .. name:sub(2):lower()] end)
    end
    if ok and kc then uiKey = kc; return true end
    return false
end
local function toggleUI() main.Visible = not main.Visible end

-- background image layer (set from the settings tab)
local bgImage = mk("ImageLabel", { Name = "BGImage", Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, ZIndex = 0,
    ScaleType = Enum.ScaleType.Crop, ImageTransparency = CONFIG.BackgroundImageTransparency, Image = CONFIG.BackgroundImage,
    Visible = CONFIG.BackgroundImage ~= "" }, main)
round(bgImage, GCFG.Radius)

-- animated background layer
local fx = mk("Frame", { Name = "FX", Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, ClipsDescendants = true, ZIndex = 2 }, main)
round(fx, GCFG.Radius)

-- title bar
local titleBar = mk("Frame", { Size = UDim2.new(1, 0, 0, 36), BackgroundTransparency = 1, ZIndex = 5 }, main)
text(titleBar, "passionware", 13, true, { Size = UDim2.new(0.6, 0, 1, 0), Position = UDim2.fromOffset(14, 0), ZIndex = 6 })

local closeBtn = mk("TextButton", { Text = "x", Font = FONTB, TextSize = 13, TextColor3 = TEXT, BorderSizePixel = 0,
    Size = UDim2.fromOffset(24, 24), AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, 0), ZIndex = 6,
    AutoButtonColor = false }, titleBar)
glass(closeBtn, 12, 0.9)
local minBtn = mk("TextButton", { Text = "-", Font = FONTB, TextSize = 15, TextColor3 = TEXT, BorderSizePixel = 0,
    Size = UDim2.fromOffset(24, 24), AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -40, 0.5, 0), ZIndex = 6,
    AutoButtonColor = false }, titleBar)
glass(minBtn, 12, 0.9)

-- dragging (title bar)
do
    local dragging, startPos, startUI
    titleBar.InputBegan:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
            dragging, startPos, startUI = true, i.Position, main.Position
        end
    end)
    C(UIS.InputChanged, function(i)
        if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
            local d = i.Position - startPos
            main.Position = UDim2.new(startUI.X.Scale, startUI.X.Offset + d.X, startUI.Y.Scale, startUI.Y.Offset + d.Y)
        end
    end)
    C(UIS.InputEnded, function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then dragging = false end
    end)
end

local minimized = false
minBtn.MouseButton1Click:Connect(function()
    minimized = not minimized
    minBtn.Text = minimized and "+" or "-"
    TweenService:Create(main, TweenInfo.new(0.35, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
        { Size = UDim2.fromOffset(W, minimized and 36 or H) }):Play()
end)

-- x hides the window; the toggle key brings it back
closeBtn.MouseButton1Click:Connect(function() main.Visible = false end)

C(UIS.InputBegan, function(input, processed)
    if not alive() or processed then return end
    if input.KeyCode == uiKey then toggleUI() end
end)

-- tab bar (segmented glass pills)
local tabBar = mk("Frame", { Size = UDim2.new(1, -20, 0, 28), Position = UDim2.fromOffset(10, 40), BackgroundTransparency = 1, ZIndex = 5 }, main)
mk("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, tabBar)

local content = mk("Frame", { Size = UDim2.new(1, -20, 1, -82), Position = UDim2.fromOffset(10, 76), BackgroundTransparency = 1, ZIndex = 4 }, main)

local tabs, tabBtns, activeTab = {}, {}, "passion"
local function styleTabs()
    for name, b in pairs(tabBtns) do setActive(b, name == activeTab) end
end
bind(styleTabs)
local function showTab(name)
    activeTab = name
    for n, p in pairs(tabs) do p.Visible = (n == name) end
    styleTabs()
end
for i, name in ipairs({ "passion", "settings" }) do
    local b = mk("TextButton", { Text = "", BorderSizePixel = 0, Size = UDim2.new(1 / 2, -3, 1, 0),
        LayoutOrder = i, ZIndex = 6, AutoButtonColor = false }, tabBar)
    glass(b, 10, 0.6)
    text(b, name, 12, true, { Name = "Label", Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center,
        TextYAlignment = Enum.TextYAlignment.Center, ZIndex = 8 })
    tabBtns[name] = b
    tabs[name] = page(content)
    b.MouseButton1Click:Connect(function() showTab(name) end)
end

-- cooldown bar
cooldownBar = mk("Frame", { Size = UDim2.new(1, -20, 0, 3), Position = UDim2.new(0, 10, 1, -6), BorderSizePixel = 0,
    BackgroundColor3 = WHITE, BackgroundTransparency = 0.6, Visible = false, ZIndex = 10 }, main)
round(cooldownBar, 2)
cooldownFill = mk("Frame", { Size = UDim2.new(1, 0, 1, 0), BorderSizePixel = 0, ZIndex = 11 }, cooldownBar)
bindProp(cooldownFill, "BackgroundColor3", same)
round(cooldownFill, 2)

--==========================================================================
--  PASSION TAB
--==========================================================================
do
    local p = tabs.passion
    local delayRow, keybindRow, platformBtn, mobileBtn

    UI.Section(p, "controls")
    UI.Toggle(p, { Name = "Status", Default = S.Enabled, Callback = function(v) S.Enabled = v end })

    local modeBtn
    local accuracy
    modeBtn = UI.Button(p, { Name = "Mode Switch: " .. S.LethalMode, Callback = function()
        S.LethalMode = (S.LethalMode == "V1") and "V2" or "V1"
        modeBtn.Text = "Mode Switch: " .. S.LethalMode
        if S.LethalMode == "V2" then
            accuracy.Label.Text = "Flip Delay"
            S.LethalAccuracy = 0.25
        else
            accuracy.Label.Text = "Accuracy / Flip"
            S.LethalAccuracy = 15
        end
        accuracy.Set(S.LethalAccuracy)
    end })

    UI.Toggle(p, { Name = "Cooldown System", Default = S.CooldownActive, Callback = function(v) S.CooldownActive = v end })

    local function refreshTouch()
        delayRow.Row.Visible    = not S.TouchMode
        platformBtn.Visible     = S.TouchMode
        keybindRow.Row.Visible  = S.TouchMode and S.Platform == "PC"
        if mobileBtn then mobileBtn.Visible = S.TouchMode and S.Platform == "Mobile" end
    end

    UI.Toggle(p, { Name = "Touch Mode", Default = false, Callback = function(v) S.TouchMode = v; refreshTouch() end })
    platformBtn = UI.Button(p, { Name = "Platform: " .. S.Platform, Callback = function(b)
        S.Platform = (S.Platform == "PC") and "Mobile" or "PC"
        b.Text = "Platform: " .. S.Platform
        refreshTouch()
    end })

    UI.Section(p, "passionware settings")
    delayRow = UI.Input(p, { Name = "Delay", Default = S.LethalDelay, Numeric = true,
        Revert = function() return S.LethalDelay end, Callback = function(n) S.LethalDelay = n end })
    UI.Input(p, { Name = "Jump Power", Default = S.LethalJump, Numeric = true,
        Revert = function() return S.LethalJump end, Callback = function(n) S.LethalJump = n end })
    accuracy = UI.Input(p, { Name = "Accuracy / Flip", Default = S.LethalAccuracy, Numeric = true,
        Revert = function() return S.LethalAccuracy end, Callback = function(n) S.LethalAccuracy = n end })
    UI.Input(p, { Name = "Dash Range", Default = S.DashRange, Numeric = true,
        Revert = function() return S.DashRange end, Callback = function(n) S.DashRange = n end })
    UI.Input(p, { Name = "Cancel Delay", Default = S.LethalCancelDelay, Numeric = true,
        Revert = function() return S.LethalCancelDelay end, Callback = function(n) S.LethalCancelDelay = n end })
    keybindRow = UI.Input(p, { Name = "Keybind", Default = S.Keybind, Callback = function(s) S.Keybind = s end })

    UI.Section(p, "camera")
    local camSmoothToggle = UI.Toggle(p, { Name = "Cam Smooth", Expandable = true, Default = S.CamSmooth,
        Callback = function(v)
            S.CamSmooth = v
            if not v then camSmoothStop() end
        end })
    UI.Slider(camSmoothToggle.Body, { Name = "Smooth Speed", Min = 1, Max = 30, Default = S.CamSmoothSpeed,
        Callback = function(v) S.CamSmoothSpeed = v end })

    -- floating glass orb for mobile touch mode
    mobileBtn = mk("TextButton", { Text = "PASSION", Font = FONTB, TextSize = 10, TextColor3 = TEXT, BorderSizePixel = 0,
        Size = UDim2.fromOffset(60, 60), Position = UDim2.new(0.7, 0, 0.5, 0), Visible = false, Draggable = true,
        Active = true, AutoButtonColor = false }, gui)
    glass(mobileBtn, 30, 0.9)
    mobileBtn.MouseButton1Click:Connect(function() pulse(mobileBtn); lethal() end)

    refreshTouch()
end

--==========================================================================
--  BACKGROUND ANIMATION ENGINE
--==========================================================================
local FX = { Enabled = false, Style = "Wave" }
local fxRun = 0
local fxConns = {}

local function clearFX()
    fxRun += 1
    for _, c in ipairs(fxConns) do pcall(function() c:Disconnect() end) end
    fxConns = {}
    fx:ClearAllChildren()
    mk("UICorner", { CornerRadius = UDim.new(0, GCFG.Radius) }, fx)
end
local function fxC(sig, fn) local c = sig:Connect(fn); table.insert(fxConns, c); return c end

local function recolorFX()
    for _, d in ipairs(fx:GetDescendants()) do
        if d:GetAttribute("fxc") then
            if d:IsA("UIStroke") then d.Color = Theme.Color else d.BackgroundColor3 = Theme.Color end
        end
    end
end
bind(function() recolorFX() end)

local function inFX(pos)
    local a, s = fx.AbsolutePosition, fx.AbsoluteSize
    return pos.X >= a.X and pos.X <= a.X + s.X and pos.Y >= a.Y and pos.Y <= a.Y + s.Y
end
local function isTap(i) return i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch end

local function circle(props, parent)
    local f = mk("Frame", props, parent)
    f.BorderSizePixel = 0
    mk("UICorner", { CornerRadius = UDim.new(1, 0) }, f)
    return f
end

local styles = {}

styles["Wave"] = function(id)
    task.spawn(function()
        while fxRun == id and alive() do
            local band = mk("Frame", { Size = UDim2.new(0.5, 0, 1, 0), Position = UDim2.new(-0.5, 0, 0, 0),
                BackgroundColor3 = Theme.Color, BorderSizePixel = 0 }, fx)
            band:SetAttribute("fxc", true)
            mk("UIGradient", { Transparency = NumberSequence.new({
                NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.5, 0.7), NumberSequenceKeypoint.new(1, 1) }) }, band)
            TweenService:Create(band, TweenInfo.new(1.6, Enum.EasingStyle.Sine), { Position = UDim2.new(1, 0, 0, 0) }):Play()
            Debris:AddItem(band, 2)
            task.wait(2.5)
        end
    end)
end

styles["Tap Tap"] = function(id)
    fxC(UIS.InputBegan, function(i)
        if not isTap(i) or not inFX(i.Position) then return end
        local rel = Vector2.new(i.Position.X, i.Position.Y) - fx.AbsolutePosition
        local ring = circle({ Size = UDim2.fromOffset(6, 6), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(rel.X, rel.Y),
            BackgroundColor3 = Theme.Color, BackgroundTransparency = 0.6 }, fx)
        local st = mk("UIStroke", { Color = Theme.Color, Thickness = 2, Transparency = 0.3 }, ring)
        TweenService:Create(ring, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
            { Size = UDim2.fromOffset(70, 70), BackgroundTransparency = 1 }):Play()
        TweenService:Create(st, TweenInfo.new(0.5), { Transparency = 1 }):Play()
        Debris:AddItem(ring, 0.6)
    end)
end

styles["Cursor Glow"] = function(id)
    local glow = mk("Frame", { Size = UDim2.fromOffset(220, 220), AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.new(0.5, 0, 0.5, 0), BackgroundTransparency = 1 }, fx)
    for n = 1, 9 do
        local r = circle({ Size = UDim2.fromScale(n / 9, n / 9), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
            BackgroundColor3 = Theme.Color, BackgroundTransparency = 0.92 }, glow)
        r:SetAttribute("fxc", true)
    end
    local target = Vector2.new(fx.AbsoluteSize.X / 2, fx.AbsoluteSize.Y / 2)
    local pos = target
    local function track(i)
        if i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch then
            if inFX(i.Position) then target = Vector2.new(i.Position.X, i.Position.Y) - fx.AbsolutePosition end
        end
    end
    fxC(UIS.InputChanged, track)
    fxC(UIS.InputBegan, track)
    fxC(RunService.RenderStepped, function(dt)
        pos = pos:Lerp(target, math.clamp(dt * 12, 0, 1))
        glow.Position = UDim2.fromOffset(pos.X, pos.Y)
    end)
end

styles["Bubble"] = function(id)
    local bubbles = {}
    local count = 0
    local function pop(b)
        local d = bubbles[b]
        if not d then return end
        bubbles[b] = nil
        count -= 1
        if d.tween then d.tween:Cancel() end
        local center = b.AbsolutePosition - fx.AbsolutePosition + b.AbsoluteSize / 2
        TweenService:Create(b, TweenInfo.new(0.18), { Size = UDim2.fromOffset(d.size * 1.7, d.size * 1.7),
            Position = UDim2.fromOffset(center.X - d.size * 0.85, center.Y - d.size * 0.85), BackgroundTransparency = 1 }):Play()
        if b:FindFirstChildOfClass("UIStroke") then TweenService:Create(b:FindFirstChildOfClass("UIStroke"), TweenInfo.new(0.18), { Transparency = 1 }):Play() end
        for n = 1, 6 do
            local a = (n / 6) * math.pi * 2
            local dot = circle({ Size = UDim2.fromOffset(5, 5), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(center.X, center.Y),
                BackgroundColor3 = Theme.Color, BackgroundTransparency = 0.2 }, fx)
            TweenService:Create(dot, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
                Position = UDim2.fromOffset(center.X + math.cos(a) * d.size, center.Y + math.sin(a) * d.size), BackgroundTransparency = 1 }):Play()
            Debris:AddItem(dot, 0.4)
        end
        Debris:AddItem(b, 0.25)
    end
    fxC(UIS.InputBegan, function(i)
        if not isTap(i) or not inFX(i.Position) then return end
        local p = Vector2.new(i.Position.X, i.Position.Y)
        for b, d in pairs(bubbles) do
            if b.Parent then
                local c = b.AbsolutePosition + b.AbsoluteSize / 2
                if (c - p).Magnitude <= d.size / 2 + 6 then pop(b) break end
            end
        end
    end)
    task.spawn(function()
        while fxRun == id and alive() do
            if count < 18 then
                local size = math.random(14, 40)
                local x = math.random(0, math.max(1, math.floor(fx.AbsoluteSize.X - size)))
                local b = circle({ Size = UDim2.fromOffset(size, size), Position = UDim2.fromOffset(x, fx.AbsoluteSize.Y + size),
                    BackgroundColor3 = Theme.Color, BackgroundTransparency = 0.7 }, fx)
                b:SetAttribute("fxc", true)
                local st = mk("UIStroke", { Color = Theme.Color, Thickness = 1.5, Transparency = 0.3 }, b)
                st:SetAttribute("fxc", true)
                local tw = TweenService:Create(b, TweenInfo.new(math.random(40, 70) / 10, Enum.EasingStyle.Linear),
                    { Position = UDim2.fromOffset(x + math.random(-40, 40), -size - 4) })
                bubbles[b] = { size = size, tween = tw }
                count += 1
                tw:Play()
                tw.Completed:Connect(function(state)
                    if state == Enum.PlaybackState.Completed and bubbles[b] then bubbles[b] = nil; count -= 1; b:Destroy() end
                end)
            end
            task.wait(0.45)
        end
    end)
end

styles["Glow"] = function(id)
    local overlay = mk("Frame", { Size = UDim2.new(1, 0, 1, 0), BackgroundColor3 = Theme.Color, BackgroundTransparency = 0.92, BorderSizePixel = 0 }, fx)
    overlay:SetAttribute("fxc", true)
    mk("UICorner", { CornerRadius = UDim.new(0, GCFG.Radius) }, overlay)
    local st = mk("UIStroke", { Color = Theme.Color, Thickness = 3, Transparency = 0.5 }, overlay)
    st:SetAttribute("fxc", true)
    local info = TweenInfo.new(1.4, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
    TweenService:Create(overlay, info, { BackgroundTransparency = 0.8 }):Play()
    TweenService:Create(st, info, { Thickness = 8, Transparency = 0.2 }):Play()
end

styles["Starfield"] = function(id)
    local DOTS = 55
    local dots = {}
    for n = 1, DOTS do
        local size = math.random(2, 4)
        local d = circle({ Size = UDim2.fromOffset(size, size),
            Position = UDim2.fromScale(math.random(), math.random()),
            BackgroundColor3 = Theme.Color, BackgroundTransparency = math.random(55, 92) / 100 }, fx)
        d:SetAttribute("fxc", true)
        dots[d] = { speed = math.random(6, 18) / 100, phase = math.random() * math.pi * 2, base = d.BackgroundTransparency }
    end
    fxC(RunService.RenderStepped, function(dt)
        local w, h = fx.AbsoluteSize.X, fx.AbsoluteSize.Y
        for d, s in pairs(dots) do
            if d.Parent then
                local pos = d.Position
                local ny = pos.Y.Scale + s.speed * dt
                if ny > 1.02 then ny = -0.02 end
                d.Position = UDim2.fromScale(pos.X.Scale, ny)
                s.phase += dt * 2
                d.BackgroundTransparency = math.clamp(s.base + math.sin(s.phase) * 0.12, 0, 0.97)
            end
        end
    end)
end

styles["Ripple"] = function(id)
    task.spawn(function()
        while fxRun == id and alive() do
            local cx, cy = fx.AbsoluteSize.X / 2, fx.AbsoluteSize.Y / 2
            local ring = circle({ Size = UDim2.fromOffset(0, 0), AnchorPoint = Vector2.new(0.5, 0.5),
                Position = UDim2.fromOffset(cx, cy), BackgroundTransparency = 1 }, fx)
            local st = mk("UIStroke", { Color = Theme.Color, Thickness = 3, Transparency = 0.15 }, ring)
            st:SetAttribute("fxc", true)
            local target = math.max(fx.AbsoluteSize.X, fx.AbsoluteSize.Y) * 0.8
            TweenService:Create(ring, TweenInfo.new(1.8, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
                { Size = UDim2.fromOffset(target, target) }):Play()
            TweenService:Create(st, TweenInfo.new(1.8, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
                { Thickness = 0, Transparency = 1 }):Play()
            Debris:AddItem(ring, 1.9)
            task.wait(1.1)
        end
    end)
end

styles["Confetti"] = function(id)
    task.spawn(function()
        while fxRun == id and alive() do
            local size = math.random(5, 10)
            local x = math.random(0, math.max(1, math.floor(fx.AbsoluteSize.X)))
            local shade = Theme.Color:Lerp(WHITE, math.random(0, 40) / 100)
            local piece = mk("Frame", { Size = UDim2.fromOffset(size, size * 1.6), Position = UDim2.fromOffset(x, -size * 2),
                AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor3 = shade, BorderSizePixel = 0,
                Rotation = math.random(0, 360) }, fx)
            round(piece, 2)
            local h = fx.AbsoluteSize.Y
            local drift = x + math.random(-60, 60)
            local tw = TweenService:Create(piece, TweenInfo.new(math.random(26, 42) / 10, Enum.EasingStyle.Linear),
                { Position = UDim2.fromOffset(drift, h + size * 2), Rotation = piece.Rotation + math.random(180, 540) })
            tw:Play()
            tw.Completed:Connect(function() if piece.Parent then piece:Destroy() end end)
            task.wait(0.12)
        end
    end)
end

local function startFX()
    clearFX()
    if FX.Enabled and styles[FX.Style] then
        styles[FX.Style](fxRun)
    end
end

--==========================================================================
--  BACKGROUND LINKS  (https / rbxassetid / asset number)
--==========================================================================
local BG = { saved = {}, current = "" }
local linkList

local function saveLinks()
    if writefile then pcall(writefile, LINK_FILE, HttpService:JSONEncode(BG.saved)) end
end

local function loadLinks()
    if not (isfile and readfile and isfile(LINK_FILE)) then return end
    local ok, data = pcall(function() return HttpService:JSONDecode(readfile(LINK_FILE)) end)
    if ok and type(data) == "table" then BG.saved = data end
end

-- returns true if the background was applied
local function setBackground(s)
    s = tostring(s or ""):gsub("%s", "")
    if s == "" then
        bgImage.Image = ""
        bgImage.Visible = false
        BG.current = ""
        return true
    end

    local asset
    if s:match("^https?://") then
        if not (writefile and getcustomasset) then
            notify("Background", "Your executor can't load web images.", 4)
            return false
        end
        local ok, data = pcall(game.HttpGet, game, s, true)
        if not ok or not data or #data == 0 then
            notify("Background", "Download failed.", 4)
            return false
        end
        local file = "pw_bg_" .. (HttpService:GenerateGUID(false):gsub("%W", "")) .. ".png"
        if not pcall(writefile, file, data) then
            notify("Background", "Couldn't save the image file.", 4)
            return false
        end
        local ok2, res = pcall(getcustomasset, file)
        if not ok2 then
            notify("Background", "Couldn't load the image.", 4)
            return false
        end
        asset = res
    elseif s:match("^rbxassetid://") then
        asset = s
    elseif s:match("^%d+$") then
        asset = "rbxassetid://" .. s
    else
        notify("Background", "Use an https link, rbxassetid:// or an asset number.", 4)
        return false
    end

    bgImage.Image = asset
    bgImage.Visible = true
    BG.current = s
    return true
end

local renderLinks

local function addLink(s)
    s = tostring(s or ""):gsub("%s", "")
    if s == "" then return end
    if not setBackground(s) then return end
    for i = #BG.saved, 1, -1 do
        if BG.saved[i] == s then table.remove(BG.saved, i) end
    end
    table.insert(BG.saved, 1, s)
    saveLinks()
    renderLinks()
end

renderLinks = function()
    if not linkList then return end
    for _, c in ipairs(linkList:GetChildren()) do
        if c:IsA("Frame") then c:Destroy() end
    end
    for i, s in ipairs(BG.saved) do
        local r = glass(mk("Frame", { Size = UDim2.new(1, 0, 0, 30), LayoutOrder = i }, linkList), 10, 0.7)
        text(r, (#s > 42) and (s:sub(1, 42) .. "...") or s, 11, false,
            { Size = UDim2.new(1, -92, 1, 0), Position = UDim2.fromOffset(10, 0) })

        local use = glass(mk("TextButton", { Text = "use", Font = FONTB, TextSize = 11, TextColor3 = TEXT, BorderSizePixel = 0,
            AutoButtonColor = false, Size = UDim2.fromOffset(40, 20), AnchorPoint = Vector2.new(1, 0.5),
            Position = UDim2.new(1, -44, 0.5, 0), ZIndex = 3 }, r), 6, 0.9)
        local del = glass(mk("TextButton", { Text = "x", Font = FONTB, TextSize = 11, TextColor3 = TEXT, BorderSizePixel = 0,
            AutoButtonColor = false, Size = UDim2.fromOffset(28, 20), AnchorPoint = Vector2.new(1, 0.5),
            Position = UDim2.new(1, -8, 0.5, 0), ZIndex = 3 }, r), 6, 0.9)

        use.MouseButton1Click:Connect(function()
            pulse(use)
            setBackground(s)
        end)
        del.MouseButton1Click:Connect(function()
            table.remove(BG.saved, i)
            saveLinks()
            renderLinks()
        end)
    end
end

loadLinks()

--==========================================================================
--  FULL UNLOAD
--  Disconnects every event, stops background loops and destroys the UI.
--==========================================================================
local function unload()
    _G.SkidwareId = nil
    pcall(clearMovers)
    pcall(camSmoothStop)
    for _, c in ipairs(CONNS) do pcall(function() c:Disconnect() end) end
    CONNS = {}
    pcall(clearFX)
    if env.PassionwareUnload == unload then env.PassionwareUnload = nil end
    if gui then gui:Destroy() end
end
env.PassionwareUnload = unload

--==========================================================================
--  SETTINGS TAB
--==========================================================================
do
    local p = tabs.settings

    UI.Section(p, "accent")
    UI.ColorPicker(p, { Name = "Accent colour", Default = Theme.Color, Callback = function(c) setThemeColor(c) end })

    UI.Section(p, "glass")
    UI.Slider(p, { Name = "Glass opacity", Min = 0, Max = 1, Default = GCFG.Fill, Decimals = 2,
        Callback = function(v) GCFG.Fill = v; repaintAll() end })
    UI.Slider(p, { Name = "Border strength", Min = 0, Max = 1, Default = GCFG.Border, Decimals = 2,
        Callback = function(v) GCFG.Border = v; repaintAll() end })
    UI.Slider(p, { Name = "Corner radius", Min = 0, Max = 40, Default = GCFG.Radius,
        Callback = function(v) GCFG.Radius = rnd(v); repaintAll() end })
    UI.ColorPicker(p, { Name = "Glass tint", Default = GCFG.Tint,
        Callback = function(c) GCFG.Tint = c; repaintAll() end })

    UI.Section(p, "background animation")
    UI.Toggle(p, { Name = "Animate background", Default = false, Callback = function(v) FX.Enabled = v; startFX() end })
    UI.Dropdown(p, { Name = "Animation style", Values = { "Wave", "Tap Tap", "Cursor Glow", "Bubble", "Glow", "Starfield", "Ripple", "Confetti" }, Default = FX.Style,
        Callback = function(v) FX.Style = v; startFX() end })

    UI.Section(p, "background")
    local linkRow = mk("Frame", { Size = UDim2.new(1, 0, 0, 30), BackgroundTransparency = 1, LayoutOrder = order(p) }, p)
    local linkBox = mk("TextBox", { Size = UDim2.new(1, -74, 1, 0), Font = FONT, TextSize = 11, TextColor3 = TEXT,
        ClearTextOnFocus = false, BorderSizePixel = 0, BackgroundColor3 = WHITE, BackgroundTransparency = 0.8,
        PlaceholderText = "https link, rbxassetid:// or asset number", PlaceholderColor3 = Color3.fromRGB(140, 150, 160),
        Text = "", TextXAlignment = Enum.TextXAlignment.Left }, linkRow)
    glass(linkBox, 8, 0.8)
    mk("UIPadding", { PaddingLeft = UDim.new(0, 8) }, linkBox)
    local setBtn = mk("TextButton", { Text = "Set", Font = FONTB, TextSize = 11, TextColor3 = TEXT, BorderSizePixel = 0,
        AutoButtonColor = false, Size = UDim2.new(0, 64, 1, 0), AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 0) }, linkRow)
    glass(setBtn, 8, 0.8)
    local function submit()
        pulse(setBtn)
        addLink(linkBox.Text)
        linkBox.Text = ""
    end
    setBtn.MouseButton1Click:Connect(submit)
    linkBox.FocusLost:Connect(function(enterPressed) if enterPressed then submit() end end)

    UI.Button(p, { Name = "Remove background", Callback = function() setBackground("") end })

    linkList = mk("Frame", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1,
        LayoutOrder = order(p) }, p)
    mk("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }, linkList)
    renderLinks()

    UI.Slider(p, { Name = "Image transparency", Min = 0, Max = 1, Default = CONFIG.BackgroundImageTransparency, Decimals = 2,
        Callback = function(v) bgImage.ImageTransparency = v end })

    UI.Section(p, "script")
    UI.Input(p, { Name = "Show / hide key", Default = "RightShift", Placeholder = "e.g. RightShift",
        Callback = function(s)
            local name = tostring(s):gsub("%s", "")
            if not setToggleKey(name) then
                notify("Key", "Unknown key name: " .. name, 3)
            else
                notify("Key", "Show / hide key set to " .. uiKey.Name, 2)
            end
        end })
    UI.Toggle(p, { Name = "Unload script", Callback = function(v)
        if v then unload() end
    end })
end

--==========================================================================
--  START
--==========================================================================
showTab("passion")
notify("passionware", "loaded. " .. uiKey.Name .. " shows / hides the window.", 4)
