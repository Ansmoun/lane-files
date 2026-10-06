-- menubar: barra horizontal de botones que despliegan menús
-- contextuales. Estilo PCManFM: Archivo, Editar, Ver, Ir,
-- Marcadores, Herramientas.
--
-- Cada entrada declara un label y una función build() que
-- devuelve la lista de items del menú cuando el usuario lo abre.
-- Los items siguen el formato de W.ContextMenu.

local Area  = require("lib.area")
local cairo = require("lib.cairo")
local pango = require("lib.pango")
local G     = require("lib.helpers.graphics")

local M = {}

local FONT     = "DejaVu Sans 10"
local PAD_X    = 10
local BAR_H    = 26

-- ── Item del menubar ─────────────────────────────────────────
local MenuItem = setmetatable({}, { __index = Area })
MenuItem.__index = MenuItem

function MenuItem.new(theme, label, on_activate)
    local self = setmetatable(Area.new({}), MenuItem)
    self._hover_visual = true
    self.label = label
    self.theme = theme
    self.on_activate = on_activate
    self.is_open = false

    local tw = select(1, pango.measure(label, FONT))
    self.tw = tw
    self.min_w, self.max_w = tw + PAD_X * 2, tw + PAD_X * 2
    self.min_h, self.max_h = BAR_H, BAR_H
    return self
end

function MenuItem:set_open(v)
    v = v and true or false
    if self.is_open == v then return end
    self.is_open = v
    self:damage()
end

function MenuItem:draw(cr)
    local x, y = self.x0, self.y0
    local w, h = self:getWidth(), self:getHeight()
    local T = self.theme

    -- Fondo según estado
    if self.is_open then
        local r, g, b = G.hex_to_rgba(T.accent or "#8ec07c")
        cairo.set_rgba(cr, r, g, b, 0.30)
        cairo.rectangle(cr, x, y, w, h)
        cairo.fill(cr)
    elseif self.hover then
        local r, g, b = G.hex_to_rgba(T.bg_focus or "#3c3836")
        cairo.set_rgba(cr, r, g, b, 0.55)
        cairo.rectangle(cr, x, y, w, h)
        cairo.fill(cr)
    end

    -- Texto
    local fg = T.fg_rgb or { 0.9, 0.9, 0.9 }
    local _, lh = pango.measure(self.label, FONT)
    pango.draw_text(cr, x + PAD_X, y + (h - lh) / 2,
        self.label, FONT,
        { r = fg[1], g = fg[2], b = fg[3] })
end

function MenuItem:on_mouse_press(mx, my, button)
    if button == 1 and self.on_activate then
        self.on_activate(self)
    end
end

-- ── Menubar ──────────────────────────────────────────────────
local Menubar = setmetatable({}, { __index = Area })
Menubar.__index = Menubar

-- menus: array de { label = "...", build = function() return {...} end }
-- open_menu: function(anchor_item, items) -- callback que abre el menú
-- close_menus: function() -- notifica que se debe cerrar cualquier menú abierto
function Menubar.new(theme, menus, open_menu, close_menus)
    local self = setmetatable(Area.new({}), Menubar)
    self.theme = theme
    self.open_menu = open_menu
    self.close_menus_cb = close_menus
    self.items = {}
    self.current_open = nil
    self.min_h, self.max_h = BAR_H, BAR_H
    self.min_w, self.max_w = 0, 10000

    for _, menu in ipairs(menus) do
        local item = MenuItem.new(theme, menu.label, function(anchor)
            self:_activate(menu, anchor)
        end)
        item.menu_spec = menu
        self.items[#self.items + 1] = item
    end
    return self
end

function Menubar:_activate(menu, anchor)
    -- Cerrar cualquier menú abierto
    if self.current_open and self.current_open ~= anchor then
        self.current_open:set_open(false)
    end
    if self.close_menus_cb then self.close_menus_cb() end

    local items = menu.build and menu.build() or {}
    self.current_open = anchor
    anchor:set_open(true)
    if self.open_menu then
        self.open_menu(anchor, items, function()
            anchor:set_open(false)
            if self.current_open == anchor then
                self.current_open = nil
            end
        end)
    end
end

function Menubar:close_all()
    if self.current_open then
        self.current_open:set_open(false)
        self.current_open = nil
    end
end

function Menubar:set_window(win)
    self.window = win
    for _, it in ipairs(self.items) do it.window = win end
end

function Menubar:askMinMax(minw, minh, maxw, maxh)
    local total_w = 0
    for _, it in ipairs(self.items) do
        total_w = total_w + it.min_w
    end
    return minw + total_w, minh + BAR_H, maxw + total_w, maxh + BAR_H
end

function Menubar:layout(x0, y0, x1, y1)
    Area.layout(self, x0, y0, x1, y1)
    local x = x0
    for _, it in ipairs(self.items) do
        it:layout(x, y0, x + it.min_w, y0 + BAR_H)
        x = x + it.min_w
    end
end

function Menubar:draw(cr)
    for _, it in ipairs(self.items) do
        it:draw(cr)
    end
end

function Menubar:getByXY(x, y)
    if x < self.x0 or x >= self.x1 or y < self.y0 or y >= self.y1 then
        return nil
    end
    for _, it in ipairs(self.items) do
        local hit = it:getByXY(x, y)
        if hit then return hit end
    end
    return self
end

M.new = function(theme, menus, open_menu, close_menus)
    return Menubar.new(theme, menus, open_menu, close_menus)
end

return M
