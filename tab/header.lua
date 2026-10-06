-- header: cabecera de columnas del listado.
-- Cada columna es clickeable: al pulsarla se ordena por ese
-- criterio. Si se pulsa la misma columna dos veces, se invierte
-- el orden.

local Area  = require("lib.area")
local cairo = require("lib.cairo")
local pango = require("lib.pango")
local G     = require("lib.helpers.graphics")

local M = {}

local HEAD_H   = 26
local PAD_LEFT = 24
local FONT     = "DejaVu Sans Bold 9"

-- Definición de las columnas. Los mismos porcentajes que en
-- row.lua (55% / 15% / 20% / 10%). El orden y los criterios
-- están alineados con las columnas del listado.
local COLUMNS = {
    { id = "name",  label = "Nombre",     x_frac = 0 },
    { id = "size",  label = "Tamaño",     x_frac = 0.55 },
    { id = "mtime", label = "Modificado", x_frac = 0.70 },
    { id = "type",  label = "Tipo",       x_frac = 0.90 },
}

local ListHeader = setmetatable({}, { __index = Area })
ListHeader.__index = ListHeader

-- opts:
--   on_sort(column_id)  -- callback cuando se pulsa una columna
function ListHeader.new(theme, opts)
    opts = opts or {}
    local self = setmetatable(Area.new({}), ListHeader)
    self._hover_visual = true
    self.min_h, self.max_h = HEAD_H, HEAD_H
    self.fg     = theme.muted_rgb or { 0.5, 0.5, 0.5 }
    self.accent = theme.accent_rgb or { 0.6, 0.75, 0.55 }
    self.font   = FONT
    self.on_sort = opts.on_sort
    self.sort_by   = "name"
    self.sort_desc = false
    self.hover_idx = nil
    -- Posiciones de cada columna. Se calculan en draw.
    self._cols_x = nil
    return self
end

function ListHeader:set_sort(column, desc)
    if self.sort_by == column and self.sort_desc == desc then
        return
    end
    self.sort_by = column
    self.sort_desc = desc
    self:damage()
end

-- Calcula las posiciones de las columnas en coordenadas LOCALES
-- al header (0..width). El desplazamiento global se suma al
-- dibujar. Sin esto, el hit test falla porque on_mouse_move y
-- on_mouse_press reciben coordenadas locales pero el rango de hit
-- estaba en globales.
function ListHeader:_calc_cols()
    local w = self:getWidth()
    local cols = {}
    for i, c in ipairs(COLUMNS) do
        local x = (i == 1) and PAD_LEFT
                  or math.floor(w * c.x_frac)
        local sw = select(1, pango.measure(c.label .. "  ", self.font))
        cols[i] = {
            id = c.id,
            label = c.label,
            x = x,
            x1 = x + sw,
            hit_x0 = x - 4,
            hit_x1 = x + sw,
        }
    end
    for i = 1, #cols - 1 do
        cols[i].hit_x1 = cols[i + 1].hit_x0
    end
    if cols[#cols] then
        cols[#cols].hit_x1 = w
    end
    self._cols_x = cols
end

function ListHeader:_hit(mx)
    if not self._cols_x then return nil end
    for _, c in ipairs(self._cols_x) do
        if mx >= c.hit_x0 and mx < c.hit_x1 then
            return c.id
        end
    end
    return nil
end

function ListHeader:draw(cr)
    self:_calc_cols()
    local y = self.y0 + (self:getHeight() - 12) / 2
    local cols = self._cols_x
    local x0 = self.x0

    for i, c in ipairs(cols) do
        local is_sorted = (c.id == self.sort_by)
        local is_hover  = (self.hover_idx == i)

        local col
        if is_sorted then
            col = self.accent
        elseif is_hover then
            col = self.accent
        else
            col = self.fg
        end

        local label = c.label
        if is_sorted then
            label = label .. (self.sort_desc and " ▼" or " ▲")
        end

        pango.draw_text(cr, x0 + c.x, y, label, self.font,
            { r = col[1], g = col[2], b = col[3] })
    end
end

function ListHeader:on_mouse_move(mx, my)
    if not self._cols_x then return end
    local new_hover = nil
    for i, c in ipairs(self._cols_x) do
        if mx >= c.hit_x0 and mx < c.hit_x1 then
            new_hover = i
            break
        end
    end
    if new_hover ~= self.hover_idx then
        self.hover_idx = new_hover
        self:damage()
    end
end

function ListHeader:set_hover(v)
    Area.set_hover(self, v)
    if not v and self.hover_idx then
        self.hover_idx = nil
        self:damage()
    end
end

function ListHeader:on_mouse_press(mx, my, button)
    if button ~= 1 then return end
    local id = self:_hit(mx)
    if id and self.on_sort then
        self.on_sort(id)
    end
end

M.new = function(theme, opts)
    return ListHeader.new(theme, opts)
end

return M
