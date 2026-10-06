-- Divider: línea horizontal de 1 píxel.
-- Usado entre secciones de la UI (navbar, header, status bar).

local Area  = require("lib.area")
local cairo = require("lib.cairo")

local M = {}

local Divider = setmetatable({}, { __index = Area })
Divider.__index = Divider

function Divider.new(theme)
    local self = setmetatable(Area.new({}), Divider)
    self.color = theme.separator_rgb or { 0.2, 0.2, 0.2 }
    self.min_h, self.max_h = 1, 1
    return self
end

function Divider:draw(cr)
    local c = self.color
    cairo.set_rgb(cr, c[1], c[2], c[3])
    cairo.rectangle(cr, self.x0, self.y0, self:getWidth(), 1)
    cairo.fill(cr)
end

M.new = Divider.new

return M
