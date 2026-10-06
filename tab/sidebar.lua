-- sidebar: panel lateral con lugares comunes y marcadores.
-- Cada item navega al path al hacer click. El item correspondiente
-- al cwd actual se marca como activo.

local Area        = require("lib.area")
local cairo       = require("lib.cairo")
local pango       = require("lib.pango")
local G           = require("lib.helpers.graphics")
local icon_theme  = require("lib.icon_theme")
local icons       = require("lib.icons")
local places      = require("tab.places")

local M = {}

local WIDTH     = 180
local HEADER_H  = 26
local ROW_H     = 28
local PAD_X     = 12

-- Un item de la barra lateral: icono + label.
local Item = setmetatable({}, { __index = Area })
Item.__index = Item

function Item.new(theme, entry, on_click)
    local self = setmetatable(Area.new({}), Item)
    self._hover_visual = true
    self.entry = entry
    self.on_click = on_click
    self.theme = theme
    self.is_active = false
    self.min_h, self.max_h = ROW_H, ROW_H
    self.min_w, self.max_w = WIDTH, WIDTH

    -- Icono: preferir lib.icons (propios del toolkit), fallback a
    -- icon_theme (tema del sistema).
    self.icon_surface = icons.surface("files/" .. entry.icon, 18)
    if not self.icon_surface then
        self.icon_surface = icon_theme.resolve(entry.icon, 18)
    end

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
        -- Barra de acento a la izquierda
        cairo.set_rgb(cr, r, g, b)
        cairo.rectangle(cr, x, y, 3, h)
        cairo.fill(cr)
    elseif self.hover then
        local r, g, b = G.hex_to_rgba(T.bg_focus or "#3c3836")
        cairo.set_rgba(cr, r, g, b, 0.55)
        cairo.rectangle(cr, x, y, w, h)
        cairo.fill(cr)
    end

    -- Icono (con color según estado)
    local icon_x = x + PAD_X
    local icon_y = y + (h - 18) / 2
    if self.icon_surface then
        local col
        if self.is_active then
            col = { G.hex_to_rgba(T.accent or "#8ec07c") }
        else
            col = T.fg_rgb or { 0.9, 0.9, 0.9 }
        end
        cairo.draw_surface_tinted(cr, self.icon_surface,
            icon_x, icon_y, 18, 18, col[1], col[2], col[3])
    end

    -- Label
    local label_x = icon_x + 18 + 10
    local avail_w = w - label_x - PAD_X
    local label = self.entry.label

    -- Truncar si es muy largo
    local tw = pango.measure(label, "DejaVu Sans 10")
    if tw > avail_w then
        -- Truncado con ellipsis. El while tiene un límite duro de
        -- 50 iteraciones para evitar bucles si el ancho disponible
        -- es minúsculo.
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
    if button == 1 and self.on_click then
        self.on_click(self.entry)
    end
end

-- ── Sidebar completo ─────────────────────────────────────────────
local Sidebar = setmetatable({}, { __index = Area })
Sidebar.__index = Sidebar

function Sidebar.new(theme, on_navigate)
    local self = setmetatable(Area.new({}), Sidebar)
    self.theme = theme
    self.on_navigate = on_navigate

    self.items = {}       -- Items visibles (todos son lugares)
    self.rows = {}        -- Filas con su Y calculada en layout

    self.min_w, self.max_w = WIDTH, WIDTH
    self.min_h, self.max_h = 100, 10000

    self:rebuild()
    return self
end

-- Reconstruye la lista de items. Se llama al arrancar y cuando se
-- modifican marcadores.
function Sidebar:rebuild()
    self.items = {}

    -- Sección: Lugares
    for _, entry in ipairs(places.common_places()) do
        self.items[#self.items + 1] = {
            section = "Lugares",
            entry   = entry,
        }
    end

    -- Sección: Marcadores
    for _, entry in ipairs(places.bookmarks()) do
        self.items[#self.items + 1] = {
            section = "Marcadores",
            entry   = entry,
        }
    end

    -- Crear los widgets Item
    local nav = self.on_navigate
    for _, row in ipairs(self.items) do
        row.widget = Item.new(self.theme, row.entry, function(entry)
            if nav then nav(entry.path) end
        end)
        row.widget.window = self.window
    end
end

-- Variante pública que además fuerza el relayout del árbol.
-- Se llama desde fuera cuando se modifican los marcadores.
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

-- Marca como activo el item que corresponde al cwd.
function Sidebar:set_active_path(path)
    for _, row in ipairs(self.items) do
        row.widget:set_active(row.entry.path == path)
    end
end

function Sidebar:askMinMax(minw, minh, maxw, maxh)
    -- Calcular alto: suma de todas las filas + headers de sección
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
    -- Asignar rect a cada Item, con headers de sección intercalados.
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
    -- Fondo del sidebar
    local bg = T.bg_card_rgb or T.bg_rgb or { 0.1, 0.1, 0.1 }
    cairo.set_rgb(cr, bg[1], bg[2], bg[3])
    cairo.rectangle(cr, self.x0, self.y0,
        self:getWidth(), self:getHeight())
    cairo.fill(cr)

    -- Header de secciones
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

    -- Items
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

M.new = function(theme, on_navigate)
    return Sidebar.new(theme, on_navigate)
end

return M
