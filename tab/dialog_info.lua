-- dialog_info: ventana modal de solo lectura con filas
-- label:value y un botón Cerrar. Se usa para propiedades.
--
-- Se mantiene separado de dialog.lua (input) para no complicar
-- ese con una variante que no comparte casi nada.

local Window  = require("lib.window")
local W       = require("lib.widgets")
local cairo   = require("lib.cairo")
local log     = require("lib.log")
local xcb     = require("lib.xcb")

local M = {}

local _current = nil

-- opts:
--   parent_win  -- Window padre
--   srv         -- Server
--   theme       -- tabla de tema
--   title       -- string
--   rows        -- array de { label, value }
--   on_close    -- callback opcional
function M.show(opts)
    if _current then _current:close() end

    local parent = opts.parent_win
    local srv    = opts.srv
    local theme  = opts.theme
    local T      = theme
    local rows   = opts.rows or {}

    -- Calcular alto en función de las filas. Mínimo 200, máximo
    -- ajustado a la ventana del parent.
    local W_DLG = 560
    local ROW_H = 22
    local HEAD_H = 40
    local FOOT_H = 56
    local n = #rows
    local H_DLG = HEAD_H + n * ROW_H + FOOT_H + 20
    if H_DLG < 200 then H_DLG = 200 end
    if H_DLG > parent.height - 40 then
        H_DLG = parent.height - 40
    end

    local px = math.floor((parent.width  - W_DLG) / 2)
    local py = math.floor((parent.height - H_DLG) / 2)
    if px < 10 then px = 10 end
    if py < 10 then py = 10 end

    local win

    local function close_dialog()
        if not win or win.destroyed then return end
        local w = win
        win = nil
        _current = nil
        xcb.ungrab_pointer(srv.conn)
        if not w.destroyed then
            w:close("dialog_info cerrado")
        end
        if opts.on_close then opts.on_close() end
    end

    -- Botón Cerrar
    local btn_close = W.Button.new {
        text = "Cerrar",
        font = "DejaVu Sans Bold 10",
        padding_x = 14, padding_y = 5,
        corner_radius = 4,
        color_normal  = { 0.30, 0.55, 0.35 },
        color_hover   = { 0.38, 0.65, 0.42 },
        color_pressed = { 0.22, 0.42, 0.28 },
        color_border  = { 0.45, 0.65, 0.50 },
        color_text    = { 0.95, 0.95, 0.95 },
        on_click = function() close_dialog() end,
    }

    -- Construir las filas como un Group vertical de dos columnas
    -- por fila. Usamos KV de LaneTK si está disponible.
    local kv_rows = {}
    for _, r in ipairs(rows) do
        kv_rows[#kv_rows + 1] = { id = r.label, label = r.label }
    end

    local kv = W.KV.new {
        rows = kv_rows,
        key_width = 130,
        row_height = 20,
        row_spacing = 2,
        key_color = T.muted_rgb or { 0.55, 0.55, 0.60 },
        value_color = T.fg_rgb or { 0.9, 0.9, 0.9 },
        key_font = "DejaVu Sans 10",
        value_font = "DejaVu Sans 10",
        value_align = "left",
        col_gap = 8,
    }
    -- Rellenar los valores
    for _, r in ipairs(rows) do
        kv:set(r.label, r.value)
    end

    -- Título
    local title_lbl = W.Text.new {
        text = opts.title or "Propiedades",
        font = "DejaVu Sans Bold 11",
        align = "left", valign = "center",
        r = T.fg_rgb[1],
        g = T.fg_rgb[2],
        b = T.fg_rgb[3],
    }

    local buttons = W.Group.new {
        orientation = "horizontal",
        spacing = 8,
        children = {
            { widget = W.Text.new { text = "", min_width = 1 }, weight = 1 },
            { widget = btn_close, weight = 0 },
        },
    }

    local body = W.Group.new {
        orientation = "vertical",
        spacing = 10,
        padding = 14,
        children = {
            { widget = title_lbl, weight = 0 },
            { widget = kv,        weight = 1 },
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
        title = opts.title or "Propiedades",
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
                close_dialog()
            end
        end,
        -- Click fuera cierra el diálogo. El grab del puntero
        -- redirige todos los clicks al child; los que caen fuera
        -- del rect llegan con coordenadas negativas o fuera de
        -- rango.
        on_mouse = function(mx, my, button)
            if button ~= 1 then return end
            if mx < 0 or my < 0 or mx >= W_DLG or my >= H_DLG then
                close_dialog()
            end
        end,
    })

    win:set_root(body)
    xcb.grab_pointer(srv.conn, win.id)

    _current = {
        close = close_dialog,
    }

    log.info("dialog_info", "abierto: %s (%d filas)",
        opts.title or "?", #rows)
end

function M.close_current()
    if _current then _current:close() end
end

return M
