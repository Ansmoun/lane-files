-- dialog_confirm: ventana modal con un mensaje y dos botones
-- (Confirmar / Cancelar). Reemplaza el patrón de "escribe X en un
-- input para confirmar" por un diálogo clásico con botones.

local Window  = require("lib.window")
local W       = require("lib.widgets")
local cairo   = require("lib.cairo")
local pango   = require("lib.pango")
local log     = require("lib.log")
local xcb     = require("lib.xcb")

local M = {}

local _current = nil

-- opts:
--   parent_win    -- Window padre
--   srv           -- Server
--   theme         -- tabla de tema
--   title         -- string (opcional)
--   message       -- string (obligatorio). Acepta \n.
--   confirm_label -- por defecto "Confirmar"
--   cancel_label  -- por defecto "Cancelar"
--   destructive   -- bool. Si true, el botón de confirmar es rojo.
--   on_accept     -- callback
--   on_cancel     -- callback opcional
function M.show(opts)
    if _current then _current:close() end

    local parent = opts.parent_win
    local srv    = opts.srv
    local theme  = opts.theme
    local T      = theme

    -- Ancho fijo, alto calculado a partir del mensaje. Medimos
    -- las líneas del mensaje para calcular el alto total.
    local W_DLG  = 420
    local PAD    = 20
    local title_h = opts.title and 24 or 0
    local FONT   = "DejaVu Sans 10"
    local line_h = select(2, pango.measure("X", FONT))
    local lines = 0
    for _ in (opts.message or ""):gmatch("[^\n]*") do
        lines = lines + 1
    end
    if lines < 1 then lines = 1 end
    local msg_h = lines * line_h
    local btn_row_h = 36
    local H_DLG = PAD + title_h + msg_h + PAD + btn_row_h + PAD

    local px = math.floor((parent.width  - W_DLG) / 2)
    local py = math.floor((parent.height - H_DLG) / 2)
    if px < 10 then px = 10 end
    if py < 10 then py = 10 end

    local win

    local function close_dialog(accepted)
        if not win or win.destroyed then return end
        local w = win
        win = nil
        _current = nil
        xcb.ungrab_pointer(srv.conn)
        if not w.destroyed then
            w:close("dialog_confirm cerrado")
        end
        if accepted then
            if opts.on_accept then opts.on_accept() end
        else
            if opts.on_cancel then opts.on_cancel() end
        end
    end

    -- Botón cancelar
    local btn_cancel = W.Button.new {
        text = opts.cancel_label or "Cancelar",
        font = "DejaVu Sans 10",
        padding_x = 16, padding_y = 6,
        corner_radius = 4,
        color_normal  = { 0.22, 0.22, 0.28 },
        color_hover   = { 0.30, 0.30, 0.38 },
        color_pressed = { 0.15, 0.15, 0.20 },
        color_border  = { 0.42, 0.42, 0.52 },
        color_text    = { 0.95, 0.95, 0.95 },
        on_click = function() close_dialog(false) end,
    }

    -- Botón confirmar. Si destructive, color rojo.
    local conf_colors
    if opts.destructive then
        conf_colors = {
            normal  = { 0.55, 0.20, 0.20 },
            hover   = { 0.68, 0.26, 0.26 },
            pressed = { 0.40, 0.14, 0.14 },
            border  = { 0.75, 0.35, 0.35 },
        }
    else
        conf_colors = {
            normal  = { 0.30, 0.55, 0.35 },
            hover   = { 0.38, 0.65, 0.42 },
            pressed = { 0.22, 0.42, 0.28 },
            border  = { 0.45, 0.65, 0.50 },
        }
    end

    local btn_accept = W.Button.new {
        text = opts.confirm_label or "Confirmar",
        font = "DejaVu Sans Bold 10",
        padding_x = 16, padding_y = 6,
        corner_radius = 4,
        color_normal  = conf_colors.normal,
        color_hover   = conf_colors.hover,
        color_pressed = conf_colors.pressed,
        color_border  = conf_colors.border,
        color_text    = { 0.95, 0.95, 0.95 },
        on_click = function() close_dialog(true) end,
    }

    -- Layout interno: título, mensaje, fila de botones alineados
    -- a la derecha.
    local children = {}
    if opts.title then
        children[#children + 1] = W.Text.new {
            text = opts.title,
            font = "DejaVu Sans Bold 11",
            align = "left", valign = "center",
            r = T.fg_rgb[1],
            g = T.fg_rgb[2],
            b = T.fg_rgb[3],
        }
    end
    children[#children + 1] = W.Text.new {
        text = opts.message or "",
        font = FONT,
        align = "left", valign = "top",
        r = T.fg_rgb[1],
        g = T.fg_rgb[2],
        b = T.fg_rgb[3],
        wrap = true,
    }
    children[#children + 1] = W.Group.new {
        orientation = "horizontal",
        spacing = 8,
        children = {
            { widget = W.Text.new { text = "", min_width = 1 }, weight = 1 },
            { widget = btn_cancel, weight = 0 },
            { widget = btn_accept, weight = 0 },
        },
    }

    local body = W.Group.new {
        orientation = "vertical",
        spacing = 10,
        padding = PAD,
        children = children,
    }

    win = Window.new(srv, {
        parent_window = parent,
        kind          = "child",
        width  = W_DLG,
        height = H_DLG,
        x      = px,
        y      = py,
        disable_q_close = true,
        title = opts.title or "Confirmar",
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
        on_mouse = function(mx, my, button)
            if button ~= 1 then return end
            if mx < 0 or my < 0 or mx >= W_DLG or my >= H_DLG then
                close_dialog(false)
            end
        end,
        on_key = function(key)
            if not key.pressed then return end
            if key.name == "Escape" then
                close_dialog(false)
            elseif key.name == "Return" or key.name == "KP_Enter" then
                close_dialog(true)
            end
        end,
    })

    win:set_root(body)
    xcb.grab_pointer(srv.conn, win.id)

    _current = { close = function() close_dialog(false) end }
    log.info("dialog_confirm", "abierto: %s",
        opts.title or opts.message or "?")
end

-- Cierra el diálogo actual sin aceptar.
function M.close_current()
    if _current then _current:close() end
end

return M
