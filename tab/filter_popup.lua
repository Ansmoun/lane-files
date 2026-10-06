-- filter_popup: ventana child flotante con un input de filtro.
-- Se abre desde Ctrl+F o desde el menú Editar. El cambio en el
-- input dispara on_change para filtrar en vivo. Enter cierra
-- manteniendo el filtro. Escape cancela y limpia.

local Window = require("lib.window")
local W      = require("lib.widgets")
local cairo  = require("lib.cairo")
local xcb    = require("lib.xcb")
local log    = require("lib.log")

local M = {}

local _current = nil

-- opts:
--   parent_win  -- Window padre
--   srv         -- Server
--   theme       -- tabla de tema
--   initial     -- texto inicial del input
--   on_change   -- function(text)
--   on_close    -- function(final_text)
function M.show(opts)
    if _current then _current:close() end

    local parent = opts.parent_win
    local srv    = opts.srv
    local theme  = opts.theme
    local T      = theme

    local W_DLG = 420
    local H_DLG = 60

    local px = math.floor((parent.width - W_DLG) / 2)
    local py = 40
    if px < 10 then px = 10 end

    local win

    local function close_dialog(commit)
        if not win or win.destroyed then return end
        local text = input and input:get_text() or ""
        local w = win
        win = nil
        _current = nil
        xcb.ungrab_pointer(srv.conn)
        if not w.destroyed then
            w:close("filter_popup cerrado")
        end
        if not commit then
            -- Cancelar: restaurar filtro anterior
            if opts.on_change then opts.on_change("") end
        end
        if opts.on_close then opts.on_close(commit and text or nil) end
    end

    local input = W.TextInput.new {
        text = opts.initial or "",
        font = "DejaVu Sans 11",
        padding_x = 10, padding_y = 6,
        min_height = 32,
        color_bg = theme.bg_focus,
        color_border = theme.separator,
        corner_radius = 16,
        color_text = theme.fg_rgb,
        color_cursor = theme.accent_rgb,
        placeholder = "Filtrar  ·  ** prefijo = recursivo",
        color_placeholder = theme.muted_rgb,
        on_change = function(text)
            if opts.on_change then opts.on_change(text or "") end
        end,
        on_submit = function() close_dialog(true) end,
        on_cancel = function() close_dialog(false) end,
    }

    win = Window.new(srv, {
        parent_window = parent,
        kind          = "child",
        width  = W_DLG,
        height = H_DLG,
        x      = px,
        y      = py,
        disable_q_close = true,
        title = "Filtrar",
        on_draw = function(cr, cw, ch)
            local bg  = T.bg_card_rgb or T.bg_rgb
            local sep = T.separator_rgb or { 0.2, 0.2, 0.2 }
            cairo.set_rgb(cr, bg[1], bg[2], bg[3])
            cairo.rounded_rect(cr, 0, 0, cw, ch, 6)
            cairo.fill(cr)
            cairo.set_rgb(cr, sep[1], sep[2], sep[3])
            cairo.set_line_width(cr, 1)
            cairo.rounded_rect(cr, 0.5, 0.5, cw - 1, ch - 1, 6)
            cairo.stroke(cr)
        end,
        on_mouse = function(mx, my, button)
            if button ~= 1 then return end
            if mx < 0 or my < 0 or mx >= W_DLG or my >= H_DLG then
                close_dialog(false)
            end
        end,
    })

    local body = W.Group.new {
        orientation = "horizontal",
        padding = 14,
        children = { { widget = input, weight = 1 } },
    }
    win:set_root(body)
    input:set_focused(true)
    xcb.grab_pointer(srv.conn, win.id)

    _current = { close = function() close_dialog(false) end }
    log.info("filter_popup", "abierto")
end

return M
