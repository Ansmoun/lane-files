-- sidebar: panel lateral con lugares, marcadores y dispositivos.
--
-- Cada seccion es colapsable (click en el header). Si el contenido
-- total excede el alto del widget, un ScrollBar a la derecha
-- permite scrollear.
--
-- Estructura:
--   Sidebar (Area)
--   ├── ScrollView (ocupa todo menos el ancho del scrollbar)
--   └── ScrollBar (12px a la derecha)

local Area        = require("lib.area")
local cairo       = require("lib.cairo")
local pango       = require("lib.pango")
local G           = require("lib.helpers.graphics")
local ScrollView  = require("lib.widgets.scrollview")
local ScrollBar   = require("lib.widgets.scrollbar")
local ScrollLink  = require("lib.widgets.scrolllink")
local places      = require("tab.places")
local place_icons = require("tab.place_icons")
local devices     = require("tab.devices")

local M = {}

local WIDTH       = 180
local SCROLLBAR_W = 12
local ROW_H       = 26
local PAD_X       = 12
local ICON_SIZE   = 18

local Sidebar = setmetatable({}, { __index = Area })
Sidebar.__index = Sidebar

function Sidebar.new(theme, on_navigate, on_item_context)
    local self = setmetatable(Area.new({}), Sidebar)
    self.theme = theme
    self.on_navigate = on_navigate
    self.on_item_context = on_item_context

    self.rows = {}       -- lista plana { section, entry }
    self.visible = {}    -- lista plana tras filtrar colapsadas
    self.collapsed = {}  -- section -> true si colapsada
    self.active_path = nil

    -- ScrollView. El ancho util excluye el scrollbar.
    self.scrollview = ScrollView.new {
        row_height = ROW_H,
        min_width  = WIDTH - SCROLLBAR_W,
        min_height = 100,
    }
    self.scrollbar = ScrollBar.new {
        orientation  = "vertical",
        width        = SCROLLBAR_W,
        thickness    = 3,
        handle_r     = 5,
        step         = ROW_H * 3,
        color_handle = theme.accent,
        color_track  = theme.separator,
    }
    ScrollLink.link(self.scrollview, self.scrollbar)

    local sv = self.scrollview
    sv.draw_row = function(cr, item, idx, y, row_h, width, hover)
        self:_draw_row(cr, item, idx, y, row_h, width, hover)
    end
    sv.on_click = function(item, idx)
        self:_on_click(item, idx)
    end
    sv.on_right_click = function(item, idx, mx, my)
        self:_on_right_click(item, idx, mx, my)
    end

    self.min_w, self.max_w = WIDTH, WIDTH
    self.min_h, self.max_h = 100, 10000

    self:rebuild()   -- llena self.rows + llama a _rebuild_visible
    return self
end

-- ── Construccion de la lista ───────────────────────────────

function Sidebar:rebuild()
    self.rows = {}

    for _, entry in ipairs(places.common_places()) do
        entry.is_bookmark = false
        self.rows[#self.rows + 1] = { section = "Lugares", entry = entry }
    end

    for _, entry in ipairs(devices.list()) do
        entry.is_bookmark = false
        entry.is_device = true
        self.rows[#self.rows + 1] = { section = "Dispositivos", entry = entry }
    end

    for _, entry in ipairs(places.bookmarks()) do
        entry.icon = "bookmark"
        entry.is_bookmark = true
        self.rows[#self.rows + 1] = { section = "Marcadores", entry = entry }
    end

    self:_rebuild_visible()
end

-- Aplana self.rows a self.visible segun el estado de colapso. Los
-- headers siempre van; los items se saltan si su seccion esta
-- colapsada.
function Sidebar:_rebuild_visible()
    local vis = {}
    local last_section = nil
    for _, row in ipairs(self.rows) do
        if row.section ~= last_section then
            last_section = row.section
            vis[#vis + 1] = {
                kind = "header",
                section = row.section,
                collapsed = self.collapsed[row.section] or false,
            }
        end
        if not self.collapsed[row.section] then
            vis[#vis + 1] = { kind = "item", entry = row.entry }
        end
    end
    self.visible = vis
    self.scrollview:set_items(vis)
end

function Sidebar:refresh()
    self:rebuild()
    self:invalidate_layout()
end

-- ── Coordenadas y ciclo de vida ────────────────────────────

function Sidebar:set_window(win)
    self.window = win
    self.scrollview:set_window(win)
    -- ScrollBar de LaneTK no expone set_window, solo necesita el
    -- campo .window para dañar. Asignamos directo.
    self.scrollbar.window = win
end

function Sidebar:set_active_path(path)
    self.active_path = path
    self.scrollview:damage()
end

function Sidebar:askMinMax(minw, minh, maxw, maxh)
    return minw + WIDTH, minh + 100, maxw + WIDTH, maxh + 10000
end

function Sidebar:layout(x0, y0, x1, y1)
    Area.layout(self, x0, y0, x1, y1)
    local sv_x1 = x1 - SCROLLBAR_W
    if sv_x1 < x0 then sv_x1 = x0 end
    self.scrollview:layout(x0, y0, sv_x1, y1)
    self.scrollbar:layout(sv_x1, y0, x1, y1)
end

function Sidebar:draw(cr)
    local T = self.theme
    local bg = T.bg_card_rgb or T.bg_rgb or { 0.1, 0.1, 0.1 }
    cairo.set_rgb(cr, bg[1], bg[2], bg[3])
    cairo.rectangle(cr, self.x0, self.y0,
        self:getWidth(), self:getHeight())
    cairo.fill(cr)

    if self.scrollview.draw then self.scrollview:draw(cr) end
    if self.scrollbar.draw   then self.scrollbar:draw(cr)   end
end

function Sidebar:getByXY(x, y)
    if x < self.x0 or x >= self.x1 or y < self.y0 or y >= self.y1 then
        return nil
    end
    -- Scrollbar primero (ocupa el borde derecho).
    if x >= self.scrollbar.x0 and x < self.scrollbar.x1
       and y >= self.scrollbar.y0 and y < self.scrollbar.y1 then
        return self.scrollbar
    end
    if x >= self.scrollview.x0 and x < self.scrollview.x1
       and y >= self.scrollview.y0 and y < self.scrollview.y1 then
        return self.scrollview
    end
    return self
end

-- ── Eventos ────────────────────────────────────────────────

function Sidebar:_on_click(item, idx)
    if item.kind == "header" then
        local sec = item.section
        self.collapsed[sec] = not self.collapsed[sec]
        self:_rebuild_visible()
        return
    end
    if item.kind == "item" and self.on_navigate then
        self.on_navigate(item.entry.path)
    end
end

function Sidebar:_on_right_click(item, idx, mx, my)
    if item.kind ~= "item" then return end
    if not self.on_item_context then return end
    -- El sidebar y el ScrollView comparten x0 (el scrollbar esta
    -- fuera del scrollview), asi que sumar self.x0/y0 alcanza para
    -- pasar a coordenadas de la ventana.
    self.on_item_context(item.entry, self.x0 + mx, self.y0 + my)
end

-- ── Draw de cada fila ──────────────────────────────────────

function Sidebar:_draw_row(cr, item, idx, y, row_h, width, hover)
    local T = self.theme

    if item.kind == "header" then
        -- Banda de fondo
        local bf = T.bg_focus_rgb or { 0.2, 0.2, 0.2 }
        cairo.set_rgba(cr, bf[1], bf[2], bf[3], 0.35)
        cairo.rectangle(cr, 0, y, width, row_h)
        cairo.fill(cr)

        -- Flecha ▶ / ▼
        local cx = PAD_X + 4
        local cy = y + row_h / 2
        local ar, ag, ab
        if hover then
            ar, ag, ab = G.hex_to_rgba(T.accent or "#8ec07c")
        else
            local m = T.muted_rgb or { 0.55, 0.55, 0.55 }
            ar, ag, ab = m[1], m[2], m[3]
        end
        cairo.set_rgb(cr, ar, ag, ab)
        cairo.new_sub_path(cr)
        if item.collapsed then
            cairo.move_to(cr, cx - 3, cy - 4)
            cairo.line_to(cr, cx + 4, cy)
            cairo.line_to(cr, cx - 3, cy + 4)
        else
            cairo.move_to(cr, cx - 4, cy - 2)
            cairo.line_to(cr, cx + 4, cy - 2)
            cairo.line_to(cr, cx, cy + 4)
        end
        cairo.close_path(cr)
        cairo.fill(cr)

        -- Texto
        local muted = T.muted_rgb or { 0.55, 0.55, 0.55 }
        local label = (item.section or ""):upper()
        local _, lh = pango.measure(label, "DejaVu Sans Bold 8")
        pango.draw_text(cr, PAD_X + 16, y + (row_h - lh) / 2,
            label, "DejaVu Sans Bold 8",
            { r = muted[1], g = muted[2], b = muted[3] })
        return
    end

    -- item.kind == "item"
    local entry = item.entry
    local is_active = (self.active_path and entry.path == self.active_path)

    if is_active then
        local r, g, b = G.hex_to_rgba(T.accent or "#8ec07c")
        cairo.set_rgba(cr, r, g, b, 0.25)
        cairo.rectangle(cr, 0, y, width, row_h)
        cairo.fill(cr)
        cairo.set_rgb(cr, r, g, b)
        cairo.rectangle(cr, 0, y, 3, row_h)
        cairo.fill(cr)
    elseif hover then
        local r, g, b = G.hex_to_rgba(T.bg_focus or "#3c3836")
        cairo.set_rgba(cr, r, g, b, 0.55)
        cairo.rectangle(cr, 0, y, width, row_h)
        cairo.fill(cr)
    end

    local icon_x = PAD_X
    local icon_y = y + (row_h - ICON_SIZE) / 2
    local col
    if is_active then
        col = { G.hex_to_rgba(T.accent or "#8ec07c") }
    else
        col = T.fg_rgb or { 0.9, 0.9, 0.9 }
    end
    place_icons.draw(cr, icon_x, icon_y, ICON_SIZE, entry.icon,
        col[1], col[2], col[3])

    local label_x = icon_x + ICON_SIZE + 10
    local avail_w = width - label_x - PAD_X
    local label = entry.label

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
    if is_active then
        fg = { G.hex_to_rgba(T.accent or "#8ec07c") }
    else
        fg = T.fg_rgb or { 0.9, 0.9, 0.9 }
    end
    local _, lh = pango.measure(label, "DejaVu Sans 10")
    pango.draw_text(cr, label_x, y + (row_h - lh) / 2,
        label, "DejaVu Sans 10",
        { r = fg[1], g = fg[2], b = fg[3] })
end

M.new = function(theme, on_navigate, on_item_context)
    return Sidebar.new(theme, on_navigate, on_item_context)
end

return M
