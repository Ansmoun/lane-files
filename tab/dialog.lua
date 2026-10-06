-- dialog: ventana modal pequeña con un campo de texto y dos
-- botones (Aceptar / Cancelar). Se usa para renombrar, crear
-- carpeta, crear archivo y confirmaciones con input.
--
-- Implementación: ventana child del parent_window, con grab de
-- puntero. Mientras está abierta, captura todo el teclado y
-- cualquier click fuera la cierra como cancelación.
--
-- Un único diálogo puede estar abierto a la vez por proceso.

local Window  = require("lib.window")
local W       = require("lib.widgets")
local cairo   = require("lib.cairo")
local pango   = require("lib.pango")
local log     = require("lib.log")
local xcb     = require("lib.xcb")

local M = {}

-- Estado del diálogo actual (uno por proceso).
local _current = nil

-- opts:
--   parent_win  -- Window padre (requerido)
--   srv         -- Server (requerido)
--   theme       -- tabla de tema (requerido)
--   title       -- string (requerido)
--   initial     -- texto inicial del input (opcional)
--   placeholder -- texto placeholder (opcional)
--   on_accept   -- function(text) (requerido)
--   on_cancel   -- function() (opcional)
--   accept_label-- etiqueta del botón aceptar (default "Aceptar")
function M.show(opts)
    if _current then
        -- Solo un diálogo a la vez. Cancelamos el anterior.
        _current:close()
    end

    local parent = opts.parent_win
    local srv    = opts.srv
    local theme  = opts.theme
    local T      = theme

    local W_DLG  = 420
    local H_DLG  = 130
    local PAD    = 16

    -- Centrar en la ventana padre
    local px = math.floor((parent.width  - W_DLG) / 2)
    local py = math.floor((parent.height - H_DLG) / 2)
    if px < 10 then px = 10 end
    if py < 10 then py = 10 end

    local input
    local win

    local function close_dialog(cancelled)
        if not win or win.destroyed then return end
        local text = input and input:get_text() or ""
        local w = win
        win = nil
        _current = nil
        xcb.ungrab_pointer(srv.conn)
        if not w.destroyed then
            w:close("dialog cerrado")
        end
        if cancelled then
            if opts.on_cancel then opts.on_cancel() end
        else
            if opts.on_accept then opts.on_accept(text) end
        end
    end

    local function do_accept()
        close_dialog(false)
    end

    local function do_cancel()
        close_dialog(true)
    end

    -- Botones
    local btn_cancel = W.Button.new {
        text = "Cancelar",
        font = "DejaVu Sans 10",
        padding_x = 14, padding_y = 5,
        corner_radius = 4,
        color_normal  = { 0.20, 0.20, 0.26 },
        color_hover   = { 0.28, 0.28, 0.36 },
        color_pressed = { 0.14, 0.14, 0.20 },
        color_border  = { 0.45, 0.45, 0.55 },
        color_text    = { 0.95, 0.95, 0.95 },
        on_click = function() do_cancel() end,
    }
    local btn_accept = W.Button.new {
        text = opts.accept_label or "Aceptar",
        font = "DejaVu Sans Bold 10",
        padding_x = 14, padding_y = 5,
        corner_radius = 4,
        color_normal  = { 0.30, 0.55, 0.35 },
        color_hover   = { 0.38, 0.65, 0.42 },
        color_pressed = { 0.22, 0.42, 0.28 },
        color_border  = { 0.45, 0.65, 0.50 },
        color_text    = { 0.95, 0.95, 0.95 },
        on_click = function() do_accept() end,
    }

    input = W.TextInput.new {
        text = opts.initial or "",
        font = "DejaVu Sans 11",
        padding_x = 8, padding_y = 6,
        min_height = 30,
        color_bg = theme.bg_focus,
        color_border = theme.separator,
        corner_radius = 4,
        color_text = theme.fg_rgb,
        color_cursor = theme.accent_rgb,
        placeholder = opts.placeholder or "",
        color_placeholder = theme.muted_rgb,
        on_submit = function() do_accept() end,
        on_cancel = function() do_cancel() end,
    }

    -- Layout interno
    local title_lbl = W.Text.new {
        text = opts.title or "",
        font = "DejaVu Sans Bold 11",
        align = "left", valign = "center",
        r = theme.fg_rgb[1],
        g = theme.fg_rgb[2],
        b = theme.fg_rgb[3],
    }

    local buttons = W.Group.new {
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
        children = {
            { widget = title_lbl, weight = 0 },
            { widget = input,     weight = 0 },
            { widget = buttons,   weight = 0 },
        },
    }

    win = Window.new(srv, {
        parent_window = parent,
        kind          = "child",
        width  = W_DLG,
        height = H_DLG,
        x      = px,
        y      = py,
        disable_q_close = true,
        title = opts.title or "dialogo",
        on_mouse = function(mx, my, button)
            if button ~= 1 then return end
            if mx < 0 or my < 0 or mx >= W_DLG or my >= H_DLG then
                do_cancel()
            end
        end,
        on_draw = function(cr, cw, ch)
            -- Fondo
            local bg  = T.bg_card_rgb or T.bg_rgb
            local sep = T.separator_rgb or { 0.2, 0.2, 0.2 }
            cairo.set_rgb(cr, bg[1], bg[2], bg[3])
            cairo.rectangle(cr, 0, 0, cw, ch)
            cairo.fill(cr)
            -- Borde
            cairo.set_rgb(cr, sep[1], sep[2], sep[3])
            cairo.set_line_width(cr, 1)
            cairo.rectangle(cr, 0.5, 0.5, cw - 1, ch - 1)
            cairo.stroke(cr)
        end,
    })

    win:set_root(body)

    -- Foco al input y grab de puntero
    input:set_focused(true)
    xcb.grab_pointer(srv.conn, win.id)

    _current = {
        close = function()
            close_dialog(true)
        end,
    }

    log.info("dialog", "abierto: %s", opts.title or "?")
end

-- Cierra el diálogo actual sin aceptar, si lo hay.
function M.close_current()
    if _current then
        _current:close()
    end
end

return M
