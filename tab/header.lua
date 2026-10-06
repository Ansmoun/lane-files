-- header: cabecera de columnas del listado.
-- Columnas: Nombre, Tamaño, Modificado, Tipo.

local Area  = require("lib.area")
local pango = require("lib.pango")

local M = {}

local HEAD_H = 26

local ListHeader = setmetatable({}, { __index = Area })
ListHeader.__index = ListHeader

function ListHeader.new(theme)
    local self = setmetatable(Area.new({}), ListHeader)
    self.min_h, self.max_h = HEAD_H, HEAD_H
    self.fg   = theme.muted_rgb or { 0.5, 0.5, 0.5 }
    self.font = "DejaVu Sans Bold 9"
    return self
end

function ListHeader:draw(cr)
    local w = self:getWidth()
    local col_name = 24
    local col_size = w - 380
    local col_date = w - 260
    local col_type = w - 90
    local c = self.fg
    local opts = { r = c[1], g = c[2], b = c[3] }
    local y = self.y0 + (self:getHeight() - 12) / 2
    pango.draw_text(cr, self.x0 + col_name, y, "Nombre", self.font, opts)
    pango.draw_text(cr, self.x0 + col_size, y, "Tamaño", self.font, opts)
    pango.draw_text(cr, self.x0 + col_date, y, "Modificado", self.font, opts)
    pango.draw_text(cr, self.x0 + col_type, y, "Tipo", self.font, opts)
end

M.new = ListHeader.new

return M
