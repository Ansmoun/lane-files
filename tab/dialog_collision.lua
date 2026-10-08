-- dialog_collision: modal de tres opciones cuando pegar colisiona
-- con archivos existentes en el destino.
--
-- Opciones:
--   Sobrescribir  -> cp -f / mv -f, pisa los archivos existentes.
--   Renombrar     -> archivo (1).ext, (2).ext, ...
--   Cancelar      -> no hace nada.

local Window = require("lib.window")
local W      = require("lib.widgets")
local cairo  = require("lib.cairo")
local pango  = require("lib.pango")
local log    = require("lib.log")
local xcb    = require("lib.xcb")

local M = {}

local _current = nil

local WIN_W, WIN_H = 460, 180
local PAD = 22

-- opts:
--   parent_win, srv, theme
--   count         -- cantidad de archivos en conflicto
--   on_overwrite  -- callback
--   on_rename     -- callback
--   on_cancel     -- callback
function M.show(opts)
    if _current then _current:close() end

    local parent = opts.parent_win
    local srv    = opts.srv
    local T      = opts.theme
    local count  = opts.count or 1

    local win

    local function close_dialog()
        if not win or win.destroyed then return end
        local w = win
        win = nil
        _current = nil
        xcb.ungrab_pointer(srv.conn)
        if not w.destroyed then w:close("collision cerrado") end
    end

    local function choose(cb)
        close_dialog()
        if cb then cb() end
    end

    local btn_cancel = W.Button.new {
        text = "Cancelar",
        font = "DejaVu Sans 10",
        padding_x = 16, padding_y = 6,
        corner_radius = 4,
        color_normal  = { 0.22, 0.22, 0.28 },
        color_hover   = { 0.30, 0.30, 0.38 },
        color_pressed = { 0.15, 0.15, 0.20 },
        color_border  = { 0.42, 0.42, 0.52 },
        color_text    = { 0.95, 0.95, 0.95 },
        on_click = function() choose(opts.on_cancel) end,
    }
    local btn_rename = W.Button.new {
        text = "Renombrar",
        font = "DejaVu Sans 10",
        padding_x = 16, padding_y = 6,
        corner_radius = 4,
        color_normal  = { 0.30, 0.42, 0.55 },
        color_hover   = { 0.38, 0.52, 0.68 },
        color_pressed = { 0.22, 0.32, 0.42 },
        color_border  = { 0.45, 0.60, 0.75 },
        color_text    = { 0.95, 0.95, 0.95 },
        on_click = function() choose(opts.on_rename) end,
    }
    local btn_over = W.Button.new {
        text = "Sobrescribir",
        font = "DejaVu Sans Bold 10",
        padding_x = 16, padding_y = 6,
        corner_radius = 4,
        color_normal  = { 0.55, 0.20, 0.20 },
        color_hover   = { 0.68, 0.26, 0.26 },
        color_pressed = { 0.40, 0.14, 0.14 },
        color_border  = { 0.75, 0.35, 0.35 },
        color_text    = { 0.95, 0.95, 0.95 },
        on_click = function() choose(opts.on_overwrite) end,
    }

    local msg
    if count == 1 then
        msg = "Ya existe un archivo con el mismo nombre en el destino."
    else
        msg = string.format(
            "Ya existen %d archivos con el mismo nombre en el destino.",
            count)
    end

    local body = W.Group.new {
        orientation = "vertical",
        spacing = 14,
        padding = PAD,
        children = {
            { widget = W.Text.new {
                text = "Conflicto de nombres",
                font = "DejaVu Sans Bold 11",
                align = "left", valign = "center",
                r = T.fg_rgb[1], g = T.fg_rgb[2], b = T.fg_rgb[3],
              }, weight = 0 },
            { widget = W.Text.new {
                text = msg,
                font = "DejaVu Sans 10",
                align = "left", valign = "top",
                r = T.fg_rgb[1], g = T.fg_rgb[2], b = T.fg_rgb[3],
                wrap = true,
              }, weight = 1 },
            { widget = W.Group.new {
                orientation = "horizontal",
                spacing = 8,
                children = {
                    { widget = btn_cancel, weight = 0 },
                    { widget = W.Text.new { text = "", min_width = 1 }, weight = 1 },
                    { widget = btn_rename, weight = 0 },
                    { widget = btn_over,   weight = 0 },
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
        title = "Conflicto de nombres",
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
                choose(opts.on_cancel)
            end
        end,
        on_mouse = function(mx, my, button)
            if button ~= 1 then return end
            if mx < 0 or my < 0 or mx >= WIN_W or my >= WIN_H then
                choose(opts.on_cancel)
            end
        end,
    })

    win:set_root(body)
    xcb.grab_pointer(srv.conn, win.id)
    _current = { close = close_dialog }
    log.info("files", "dialog colision: %d archivos", count)
end

function M.close_current()
    if _current then _current:close() end
end

return M
