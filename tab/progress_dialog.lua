-- progress_dialog: ventana modal con barra de progreso horizontal.
-- Muestra el estado de un handle de ops_async, actualizado con un
-- timer cada 100 ms. Boton Cancelar y Cerrar (post-completado).
--
-- La barra se dibuja con cairo directo, sin widget de LaneTK.

local Window = require("lib.window")
local W      = require("lib.widgets")
local Area   = require("lib.area")
local cairo  = require("lib.cairo")
local pango  = require("lib.pango")
local log    = require("lib.log")
local xcb    = require("lib.xcb")

local M = {}

local _current = nil

local WIN_W, WIN_H = 480, 210
local PAD = 22

-- ── Barra ──────────────────────────────────────────────────
local Bar = setmetatable({}, { __index = Area })
Bar.__index = Bar

function Bar.new()
    local self = setmetatable(Area.new({}), Bar)
    self.pct = 0
    self.min_h, self.max_h = 14, 14
    self.min_w, self.max_w = 100, 10000
    return self
end

function Bar:set_pct(v)
    if v < 0 then v = 0 end
    if v > 1 then v = 1 end
    if math.abs(v - self.pct) < 0.005 then return end
    self.pct = v
    self:damage()
end

function Bar:draw(cr)
    local x, y = self.x0, self.y0
    local w, h = self:getWidth(), self:getHeight()
    local r = h / 2
    cairo.set_rgb(cr, 0.14, 0.14, 0.17)
    cairo.rounded_rect(cr, x, y, w, h, r)
    cairo.fill(cr)
    local pw = w * self.pct
    if pw > 0 then
        cairo.set_rgb(cr, 0.35, 0.65, 0.45)
        cairo.rounded_rect(cr, x, y, pw, h, r)
        cairo.fill(cr)
    end
    cairo.set_rgb(cr, 0.30, 0.30, 0.36)
    cairo.set_line_width(cr, 1)
    cairo.rounded_rect(cr, x + 0.5, y + 0.5, w - 1, h - 1, r)
    cairo.stroke(cr)
end

-- ── Helpers ────────────────────────────────────────────────
local function human_bytes(n)
    n = n or 0
    if n < 1024 then return n .. " B" end
    if n < 1024 * 1024 then return string.format("%.1f KB", n / 1024) end
    if n < 1024 * 1024 * 1024 then
        return string.format("%.1f MB", n / (1024 * 1024))
    end
    return string.format("%.2f GB", n / (1024 * 1024 * 1024))
end

-- ── M.show ─────────────────────────────────────────────────
-- opts:
--   parent_win  Window padre
--   srv         Server
--   theme       Tabla de tema
--   handle      Handle de ops_async
--   mode        "copy" | "move"
--   on_done(errors)   llamada al terminar (una sola vez)
--   on_cancel()       llamada si el usuario cancela
function M.show(opts)
    if _current then _current:close() end

    local parent  = opts.parent_win
    local srv     = opts.srv
    local theme   = opts.theme
    local T       = theme
    local handle  = opts.handle
    local mode    = opts.mode or "copy"
    local on_done = opts.on_done
    local on_cancel = opts.on_cancel

    local title = (mode == "copy") and "Copiando archivos"
                              or "Moviendo archivos"

    local win
    local bar = Bar.new()
    local state = { done = false }
    local btn_action = "cancel"   -- "cancel" | "close"
    -- Forward declarations. El boton se crea antes que estas
    -- funciones pero las invoca en on_click. Sin el forward, son
    -- globales (nil) al llamarlas y crashean.
    local close_dialog
    local update
    local finish
    local timer

    -- Labels actualizables.
    local pct_lbl = W.Text.new {
        text = "0%",
        font = "DejaVu Sans Bold 12",
        align = "left", valign = "center",
        r = T.fg_rgb[1], g = T.fg_rgb[2], b = T.fg_rgb[3],
    }
    local current_lbl = W.Text.new {
        text = "",
        font = "DejaVu Sans 10",
        align = "left", valign = "center",
        r = T.fg_rgb[1], g = T.fg_rgb[2], b = T.fg_rgb[3],
    }
    local detail_lbl = W.Text.new {
        text = "",
        font = "DejaVu Sans Mono 9",
        align = "left", valign = "center",
        r = T.muted_rgb[1], g = T.muted_rgb[2], b = T.muted_rgb[3],
    }

    local btn = W.Button.new {
        text = "Cancelar",
        font = "DejaVu Sans 10",
        padding_x = 18, padding_y = 6,
        corner_radius = 4,
        color_normal  = { 0.40, 0.18, 0.18 },
        color_hover   = { 0.52, 0.24, 0.24 },
        color_pressed = { 0.28, 0.12, 0.12 },
        color_border  = { 0.62, 0.32, 0.32 },
        color_text    = { 0.95, 0.95, 0.95 },
        on_click = function()
            if btn_action == "close" then
                close_dialog()
            else
                if handle then handle:cancel() end
                if on_cancel then on_cancel() end
                close_dialog()
            end
        end,
    }

    close_dialog = function()
        if timer then timer:cancel() timer = nil end
        _current = nil
        if win and not win.destroyed then
            pcall(xcb.ungrab_pointer, srv.conn)
            win:close("progress")
            win = nil
        end
    end

    update = function()
        if not handle then return end
        local st = handle:tick()
        local pct = 0
        if st.total_bytes and st.total_bytes > 0 then
            pct = math.min(1, st.bytes_done / st.total_bytes)
        elseif st.total_items > 0 then
            pct = math.min(1, st.done_items / st.total_items)
        end
        bar:set_pct(pct)
        pct_lbl:set_text(string.format("%d%%",
            math.floor(pct * 100 + 0.5)))
        local name = st.current or ""
        if #name > 48 then name = name:sub(1, 45) .. "..." end
        current_lbl:set_text(name)
        detail_lbl:set_text(string.format("%d / %d  ·  %s / %s",
            st.done_items or 0, st.total_items or 0,
            human_bytes(st.bytes_done or 0),
            human_bytes(st.total_bytes or 0)))
    end

    finish = function()
        if state.done then return end
        state.done = true
        btn_action = "close"
        btn:set_text("Cerrar")
        btn:set_colors({
            normal  = { 0.30, 0.55, 0.35 },
            hover   = { 0.38, 0.65, 0.42 },
            pressed = { 0.22, 0.42, 0.28 },
            border  = { 0.45, 0.65, 0.50 },
        })
        bar:set_pct(1)
        pct_lbl:set_text("100%")
        if win then win:damage_all() end
        if on_done then
            on_done(handle and handle:status().errors or {})
        end
        -- Cerrar solo despues de un momento para que el usuario vea
        -- el "100%".
        srv:add_timeout(700, function()
            if win and not win.destroyed then close_dialog() end
        end)
    end

    local inner = W.Group.new {
        orientation = "vertical",
        spacing = 12,
        padding = PAD,
        children = {
            { widget = W.Text.new {
                text = title,
                font = "DejaVu Sans Bold 11",
                align = "left", valign = "center",
                r = T.fg_rgb[1], g = T.fg_rgb[2], b = T.fg_rgb[3],
              }, weight = 0 },
            { widget = bar,         weight = 0 },
            { widget = pct_lbl,     weight = 0 },
            { widget = current_lbl, weight = 0 },
            { widget = detail_lbl,  weight = 0 },
            { widget = W.Text.new { text = "", min_height = 1 }, weight = 1 },
            { widget = W.Group.new {
                orientation = "horizontal",
                spacing = 8,
                children = {
                    { widget = W.Text.new { text = "", min_width = 1 }, weight = 1 },
                    { widget = btn, weight = 0 },
                },
              }, weight = 0 },
        },
    }

    local px = math.floor((parent.width  - WIN_W) / 2)
    local py = math.floor((parent.height - WIN_H) / 2)
    if px < 10 then px = 10 end
    if py < 10 then py = 10 end

    win = Window.new(srv, {
        parent_window = parent,
        kind = "child",
        width = WIN_W, height = WIN_H,
        x = px, y = py,
        disable_q_close = true,
        title = title,
        on_draw = function(cr, cw, ch)
            local bg  = T.bg_card_rgb or T.bg_rgb
            local sep = T.separator_rgb or { 0.2, 0.2, 0.2 }
            cairo.set_rgb(cr, bg[1], bg[2], bg[3])
            cairo.rectangle(cr, 0, 0, cw, ch)
            cairo.fill(cr)
            cairo.set_rgb(cr, sep[1], sep[2], sep[3])
            cairo.set_line_width(cr, 1)
            cairo.rectangle(cr, 0.5, 0.5, cw - 1, ch - 1)
            cairo.stroke(cr)
        end,
        on_key = function(key)
            if key.pressed and key.name == "Escape" then
                if btn_action == "close" then
                    close_dialog()
                else
                    if handle then handle:cancel() end
                    if on_cancel then on_cancel() end
                    close_dialog()
                end
            end
        end,
        on_mouse = function(mx, my, button)
            if button ~= 1 then return end
            if mx < 0 or my < 0 or mx >= WIN_W or my >= WIN_H then
                -- Click fuera solo cierra si ya termino. Durante la
                -- operacion no se cierra para no cancelar por
                -- accidente.
                if state.done then close_dialog() end
            end
        end,
    })

    win:set_root(inner)
    xcb.grab_pointer(srv.conn, win.id)

    -- Timer de actualizacion. 100 ms es fluido sin cargar la CPU.
    timer = srv:add_timer(100, function()
        if not win or win.destroyed then
            if timer then timer:cancel() timer = nil end
            return
        end
        if state.done then return end
        update()
        if handle and handle:is_done() then
            finish()
        end
    end)

    update()

    _current = { close = close_dialog }
    log.info("progress", "abierto: %s", title)
end

function M.close_current()
    if _current then _current:close() end
end

return M
