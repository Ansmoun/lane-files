-- sidebar: panel lateral con lugares comunes y marcadores.
-- Los iconos se dibujan con cairo vía place_icons (formas
-- geométricas), sin depender del tema del sistema.

local Area        = require("lib.area")
local cairo       = require("lib.cairo")
local pango       = require("lib.pango")
local G           = require("lib.helpers.graphics")
local places      = require("tab.places")
local place_icons = require("tab.place_icons")

local M = {}

local WIDTH     = 180
local HEADER_H  = 26
local ROW_H     = 28
local PAD_X     = 12
local ICON_SIZE = 18

-- ── Item ────────────────────────────────────────────────────
local Item = setmetatable({}, { __index = Area })
Item.__index = Item

function Item.new(theme, entry, on_click, on_right_click)
    local self = setmetatable(Area.new({}), Item)
    self._hover_visual = true
    self.entry = entry
    self.on_click = on_click
    self.on_right_click = on_right_click
    self.theme = theme
    self.is_active = false
    self.min_h, self.max_h = ROW_H, ROW_H
    self.min_w, self.max_w = WIDTH, WIDTH
    return self
end

function Item:set_active(v)
    v = v and true or false
    if self.is_active == v then return end
    self.is_active = v
    self:damage()
end

function Item:draw(cr)
    local x, y = self.x0, self.y0
    local w, h = self:getWidth(), self:getHeight()
    local T = self.theme

    -- Fondo según estado
    if self.is_active then
        local r, g, b = G.hex_to_rgba(T.accent or "#8ec07c")
        cairo.set_rgba(cr, r, g, b, 0.25)
        cairo.rectangle(cr, x, y, w, h)
        cairo.fill(cr)
        cairo.set_rgb(cr, r, g, b)
        cairo.rectangle(cr, x, y, 3, h)
        cairo.fill(cr)
    elseif self.hover then
        local r, g, b = G.hex_to_rgba(T.bg_focus or "#3c3836")
        cairo.set_rgba(cr, r, g, b, 0.55)
        cairo.rectangle(cr, x, y, w, h)
        cairo.fill(cr)
    end

    -- Icono dibujado con cairo
    local icon_x = x + PAD_X
    local icon_y = y + (h - ICON_SIZE) / 2
    local col
    if self.is_active then
        col = { G.hex_to_rgba(T.accent or "#8ec07c") }
    else
        col = T.fg_rgb or { 0.9, 0.9, 0.9 }
    end
    place_icons.draw(cr, icon_x, icon_y, ICON_SIZE, self.entry.icon,
        col[1], col[2], col[3])

    -- Label con truncado
    local label_x = icon_x + ICON_SIZE + 10
    local avail_w = w - label_x - PAD_X
    local label = self.entry.label

    local tw = pango.measure(label, "DejaVu Sans 10")
    if tw > avail_w then
        local guard = 0
        while #label > 1 and guard < 50 do
            guard = guard + 1
            label = label:sub(1, #label - 1)
            tw = pango.measure(label .. "…", "DejaVu Sans 10")
            if tw <= avail_w then
                label = label .. "…"
                break
            end
        end
    end

    local fg
    if self.is_active then
        fg = { G.hex_to_rgba(T.accent or "#8ec07c") }
    else
        fg = T.fg_rgb or { 0.9, 0.9, 0.9 }
    end
    local _, lh = pango.measure(label, "DejaVu Sans 10")
    pango.draw_text(cr, label_x, y + (h - lh) / 2,
        label, "DejaVu Sans 10",
        { r = fg[1], g = fg[2], b = fg[3] })
end

function Item:on_mouse_press(mx, my, button)
    if self.window and self.window.server
       and self.window.server.is_input_blocked
       and self.window.server:is_input_blocked() then
        return
    end

    if button == 1 and self.on_click then
        self.on_click(self.entry)
    elseif button == 3 and self.on_right_click then
        -- Pasar mx, my en coordenadas globales de la ventana.
        -- El consumidor usa esto para anclar el ContextMenu.
        local gx = self.x0 + mx
        local gy = self.y0 + my
        self.on_right_click(self.entry, gx, gy)
    end
end

-- ── Sidebar ─────────────────────────────────────────────────
local Sidebar = setmetatable({}, { __index = Area })
Sidebar.__index = Sidebar

function Sidebar.new(theme, on_navigate, on_item_context)
    local self = setmetatable(Area.new({}), Sidebar)
    self.theme = theme
    self.on_navigate = on_navigate
    self.on_item_context = on_item_context
    self.items = {}
    self.min_w, self.max_w = WIDTH, WIDTH
    self.min_h, self.max_h = 100, 10000
    self:rebuild()
    return self
end

function Sidebar:rebuild()
    self.items = {}

    for _, entry in ipairs(places.common_places()) do
        self.items[#self.items + 1] = {
            section = "Lugares",
            entry   = entry,
        }
    end

    for _, entry in ipairs(places.bookmarks()) do
        -- Marcadores con icono distintivo (cinta) en lugar de
        -- carpeta genérica.
        entry.icon = "bookmark"
        self.items[#self.items + 1] = {
            section = "Marcadores",
            entry   = entry,
        }
    end

    local nav = self.on_navigate
    local ctx = self.on_item_context
    for _, row in ipairs(self.items) do
        row.widget = Item.new(self.theme, row.entry,
            function(entry)
                if nav then nav(entry.path) end
            end,
            function(entry, mx, my)
                if ctx then ctx(entry, mx, my) end
            end)
        row.widget.window = self.window
    end
end

function Sidebar:refresh()
    self:rebuild()
    self:invalidate_layout()
end

function Sidebar:set_window(win)
    self.window = win
    for _, row in ipairs(self.items) do
        row.widget.window = win
    end
end

function Sidebar:set_active_path(path)
    for _, row in ipairs(self.items) do
        row.widget:set_active(row.entry.path == path)
    end
end

function Sidebar:askMinMax(minw, minh, maxw, maxh)
    local h = 0
    local last_section = nil
    for _, row in ipairs(self.items) do
        if row.section ~= last_section then
            h = h + HEADER_H
            last_section = row.section
        end
        h = h + ROW_H
    end
    return minw + WIDTH, minh + h, maxw + WIDTH, maxh + h
end

function Sidebar:layout(x0, y0, x1, y1)
    Area.layout(self, x0, y0, x1, y1)
    local y = y0
    local last_section = nil
    for _, row in ipairs(self.items) do
        if row.section ~= last_section then
            row.header_y = y
            y = y + HEADER_H
            last_section = row.section
        else
            row.header_y = nil
        end
        row.widget:layout(x0, y, x1, y + ROW_H)
        y = y + ROW_H
    end
end

function Sidebar:draw(cr)
    local T = self.theme
    local bg = T.bg_card_rgb or T.bg_rgb or { 0.1, 0.1, 0.1 }
    cairo.set_rgb(cr, bg[1], bg[2], bg[3])
    cairo.rectangle(cr, self.x0, self.y0,
        self:getWidth(), self:getHeight())
    cairo.fill(cr)

    local muted = T.muted_rgb or { 0.5, 0.5, 0.5 }
    for _, row in ipairs(self.items) do
        if row.header_y then
            local _, hh = pango.measure("X", "DejaVu Sans Bold 8")
            pango.draw_text(cr, self.x0 + PAD_X,
                row.header_y + (HEADER_H - hh) / 2,
                row.section:upper(),
                "DejaVu Sans Bold 8",
                { r = muted[1], g = muted[2], b = muted[3] })
        end
    end

    for _, row in ipairs(self.items) do
        row.widget:draw(cr)
    end
end

function Sidebar:getByXY(x, y)
    if x < self.x0 or x >= self.x1 or y < self.y0 or y >= self.y1 then
        return nil
    end
    for _, row in ipairs(self.items) do
        local hit = row.widget:getByXY(x, y)
        if hit then return hit end
    end
    return self
end

M.Item    = Item
M.Sidebar = Sidebar

M.new = function(theme, on_navigate, on_item_context)
    return Sidebar.new(theme, on_navigate, on_item_context)
end

return M
