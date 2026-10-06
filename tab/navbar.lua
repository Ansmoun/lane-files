-- navbar: barra superior con botones de navegación y path actual.

local W      = require("lib.widgets")
local Area   = require("lib.area")
local cairo  = require("lib.cairo")
local icons  = require("lib.icons")

local M = {}

local NAV_H = 40

-- ── NavButton: botón cuadrado con icono tintado ──────────────────
local NavButton = setmetatable({}, { __index = Area })
NavButton.__index = NavButton

function NavButton.new(theme, icon_name, on_click, opts)
    opts = opts or {}
    local self = setmetatable(Area.new({}), NavButton)
    self._hover_visual = true
    self.on_click = on_click
    self.icon_name = icon_name
    self.size = opts.size or 24
    self.icon_surface = icons.surface("files/" .. icon_name, self.size)
    self.min_w, self.max_w = self.size + 8, self.size + 8
    self.min_h, self.max_h = NAV_H, NAV_H
    self.fg_color    = theme.fg_rgb     or { 0.9, 0.9, 0.9 }
    self.hover_color = theme.accent_rgb or { 1, 1, 1 }
    self.enabled     = true
    return self
end

function NavButton:set_enabled(v)
    v = v and true or false
    if self.enabled == v then return end
    self.enabled = v
    self:damage()
end

function NavButton:set_hover(v)
    v = v and true or false
    if self.hover == v then return end
    Area.set_hover(self, v)
end

function NavButton:draw(cr)
    if not self.icon_surface then return end
    local col
    if not self.enabled then
        col = { 0.4, 0.4, 0.4 }
    elseif self.hover then
        col = self.hover_color
    else
        col = self.fg_color
    end
    local x = self.x0 + (self:getWidth() - self.size) / 2
    local y = self.y0 + (self:getHeight() - self.size) / 2
    cairo.draw_surface_tinted(cr, self.icon_surface, x, y,
        self.size, self.size, col[1], col[2], col[3])
end

function NavButton:on_mouse_press(mx, my, button)
    if button == 1 and self.enabled and self.on_click then
        self.on_click()
    end
end

-- ── Constructor público ─────────────────────────────────────────
-- handlers = { back = fn, forward = fn, up = fn, home = fn }
-- Devuelve { widget = group, back = btn, forward = btn,
--           up = btn, home = btn, path = Text }
function M.new(theme, handlers)
    local btn_back    = NavButton.new(theme, "back",    handlers.back)
    local btn_fwd     = NavButton.new(theme, "forward", handlers.forward)
    local btn_up      = NavButton.new(theme, "up",      handlers.up)
    local btn_home    = NavButton.new(theme, "home",    handlers.home)

    local path_lbl = W.Text.new {
        text = "",
        font = "DejaVu Sans 10",
        align = "left", valign = "center",
        r = theme.fg_rgb[1],
        g = theme.fg_rgb[2],
        b = theme.fg_rgb[3],
    }

    local nav_bar = W.Group.new {
        orientation = "horizontal",
        spacing = 4,
        padding = 6,
        children = {
            { widget = btn_back, weight = 0 },
            { widget = btn_fwd,  weight = 0 },
            { widget = btn_up,   weight = 0 },
            { widget = btn_home, weight = 0 },
            { widget = W.Text.new { text = "", min_width = 8 }, weight = 0 },
            { widget = path_lbl, weight = 1 },
        },
    }

    return {
        widget   = nav_bar,
        back     = btn_back,
        forward  = btn_fwd,
        up       = btn_up,
        home     = btn_home,
        path     = path_lbl,
    }
end

return M
