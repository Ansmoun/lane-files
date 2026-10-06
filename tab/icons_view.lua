-- icons_view: vista en cuadrícula de iconos grandes con scroll.
-- Expone una interfaz compatible con ScrollView para que
-- ScrollLink funcione igual: set_offset, get_offset,
-- get_offset_max, on_change.
--
-- El tamaño de los iconos es dinámico. Se ajusta con
-- set_icon_size (Ctrl+rueda desde el consumidor).

local Area       = require("lib.area")
local cairo      = require("lib.cairo")
local pango      = require("lib.pango")
local G          = require("lib.helpers.graphics")
local icon_theme = require("lib.icon_theme")
local icons      = require("tab.icons")

local M = {}

-- Tamaños por defecto.
local DEFAULT_SZ = 52
local SZ_MIN     = 32
local SZ_MAX     = 128
local GAP        = 8

local IconsView = setmetatable({}, { __index = Area })
IconsView.__index = IconsView

function IconsView.new(theme, state)
    local self = setmetatable(Area.new({}), IconsView)
    self.theme = theme
    self.state = state

    self.items      = {}
    self.offset     = 0
    self.offset_max = 0
    self.cols       = 1
    self.hover_idx  = -1
    self.change_cbs = {}

    -- Tamaño del icono y de la celda. Se actualizan en bloque con
    -- set_icon_size.
    self.icon_size = DEFAULT_SZ
    self:_update_cell_dims()

    self.on_click       = nil
    self.on_right_click = nil

    self.min_w = 300
    self.min_h = 100
    self.max_w = 10000
    self.max_h = 10000
    return self
end

-- Recalcula el ancho y alto de la celda a partir del tamaño del
-- icono. La celda es 1.85x el icono de ancho, 2x de alto, para
-- dejar espacio al nombre debajo.
function IconsView:_update_cell_dims()
    local sz = self.icon_size
    -- La celda es 1.6x el icono de ancho y 1.85x de alto. Más
    -- compacto que antes. El gap y el padding del icono también
    -- escalan con el tamaño para que la densidad sea uniforme a
    -- cualquier zoom.
    self.cell_w  = math.floor(sz * 1.6)
    self.cell_h  = math.floor(sz * 1.85)
    self.gap     = math.max(4, math.floor(sz * 0.12))
    self.pad_top = math.max(6, math.floor(sz * 0.15))
    if self.cell_w < 56 then self.cell_w = 56 end
    if self.cell_h < 56 then self.cell_h = 56 end
end

-- Cambia el tamaño del icono. Recalcula la grilla y fuerza un
-- relayout. Devuelve true si el tamaño cambió.
-- Callback opcional. El consumidor lo usa para persistir el
-- tamaño entre sesiones.
IconsView.on_icon_size_change = nil

function IconsView:set_icon_size(sz)
    if sz < SZ_MIN then sz = SZ_MIN end
    if sz > SZ_MAX then sz = SZ_MAX end
    if sz == self.icon_size then return false end
    self.icon_size = sz
    self:_update_cell_dims()
    self:_recalc()
    self:damage()
    if self.on_icon_size_change then
        self.on_icon_size_change(sz)
    end
    return true
end

function IconsView:get_icon_size()
    return self.icon_size
end

-- ── API tipo ScrollView ──────────────────────────────────────
function IconsView:on_change(fn)
    self.change_cbs[#self.change_cbs + 1] = fn
end

function IconsView:_notify(silent)
    if silent then return end
    for _, fn in ipairs(self.change_cbs) do
        fn(self.offset, self.offset_max)
    end
end

function IconsView:set_offset(px, silent)
    if px < 0 then px = 0 end
    if px > self.offset_max then px = self.offset_max end
    if math.abs(px - self.offset) < 0.01 then return end
    self.offset = px
    self:damage()
    self:_notify(silent)
end

function IconsView:get_offset()     return self.offset end
function IconsView:get_offset_max() return self.offset_max end
function IconsView:get_count()      return #self.items end

function IconsView:set_items(items)
    self.items = items or {}
    self.hover_idx = -1
    self:_recalc()
    self:damage()
end

function IconsView:_recalc()
    local w = self:getWidth()
    if w <= 0 then return end
    self.cols = math.max(1,
        math.floor((w + self.gap) / (self.cell_w + self.gap)))
    local rows = math.ceil(#self.items / self.cols)
    local total_h = rows * (self.cell_h + self.gap)
    local view_h = self:getHeight()
    self.offset_max = math.max(0, total_h - view_h)
    if self.offset > self.offset_max then
        self.offset = self.offset_max
    end
    self:_notify()
end

function IconsView:layout(x0, y0, x1, y1)
    Area.layout(self, x0, y0, x1, y1)
    self:_recalc()
end

function IconsView:set_window(win)
    self.window = win
end

-- ── Cálculo de posiciones ────────────────────────────────────
function IconsView:_cell_rect(i)
    local col = (i - 1) % self.cols
    local row = math.floor((i - 1) / self.cols)
    local x = self.x0 + col * (self.cell_w + self.gap)
    local y = self.y0 + row * (self.cell_h + self.gap) - self.offset
    return x, y
end

-- Mueve la selección por la grilla. direction es "up", "down",
-- "left" o "right". Devuelve true si la selección cambió.
function IconsView:move_selection(direction)
    local n = #self.items
    if n == 0 then return false end
    local cols = self.cols
    if cols < 1 then cols = 1 end

    local idx = self.state.selected_idx
    if idx < 1 then idx = 1 end
    if idx > n then idx = n end

    local new_idx
    if direction == "up" then
        new_idx = idx - cols
        if new_idx < 1 then new_idx = idx end
    elseif direction == "down" then
        new_idx = idx + cols
        if new_idx > n then new_idx = idx end
    elseif direction == "left" then
        new_idx = idx - 1
        if new_idx < 1 then new_idx = idx end
    elseif direction == "right" then
        new_idx = idx + 1
        if new_idx > n then new_idx = idx end
    else
        return false
    end

    if new_idx == idx then return false end

    self.state.selected_idx = new_idx
    self.state.anchor_idx = new_idx
    if self.state:selection_count() <= 1 then
        self.state.selected_set = {}
        local e = self.items[new_idx]
        if e then self.state.selected_set[e.path] = true end
    end

    -- Scroll vertical si la fila queda fuera de la vista
    local row = math.floor((new_idx - 1) / cols)
    local cell_y = row * (self.cell_h + self.gap)
    local view_h = self:getHeight()
    if cell_y < self.offset then
        self:set_offset(cell_y)
    elseif cell_y + self.cell_h > self.offset + view_h then
        self:set_offset(cell_y + self.cell_h - view_h)
    end

    self:damage()
    return true
end

function IconsView:_idx_at(mx, my)
    if mx < 0 or my < 0
       or mx >= self:getWidth() or my >= self:getHeight() then
        return -1
    end
    local col = math.floor(mx / (self.cell_w + self.gap))
    if col < 0 or col >= self.cols then return -1 end
    local row_px = my + self.offset
    local row = math.floor(row_px / (self.cell_h + self.gap))
    local i = row * self.cols + col + 1
    if i < 1 or i > #self.items then return -1 end
    return i
end

-- ── Draw ─────────────────────────────────────────────────────
function IconsView:draw(cr)
    cairo.save(cr)
    cairo.rectangle(cr, self.x0, self.y0,
        self:getWidth(), self:getHeight())
    cairo.clip(cr)

    local T = self.theme
    local fg = T.fg_rgb or { 0.9, 0.9, 0.9 }

    for i, item in ipairs(self.items) do
        local x, y = self:_cell_rect(i)
        if y + self.cell_h < self.y0 then goto continue end
        if y > self.y1 then break end

        local is_focus = (i == self.state.selected_idx)
        local in_set   = self.state.selected_set
                         and self.state.selected_set[item.path]
        local is_hover = (i == self.hover_idx)

        if is_focus then
            local r, g, b = G.hex_to_rgba(T.accent or "#8ec07c")
            cairo.set_rgba(cr, r, g, b, 0.30)
            cairo.rounded_rect(cr, x, y,
                self.cell_w, self.cell_h, 6)
            cairo.fill(cr)
            cairo.set_rgb(cr, r, g, b)
            cairo.rectangle(cr, x, y, self.cell_w, 3)
            cairo.fill(cr)
        elseif in_set then
            local r, g, b = G.hex_to_rgba(T.accent or "#8ec07c")
            cairo.set_rgba(cr, r, g, b, 0.15)
            cairo.rounded_rect(cr, x, y,
                self.cell_w, self.cell_h, 6)
            cairo.fill(cr)
        elseif is_hover then
            local r, g, b = G.hex_to_rgba(T.bg_focus or "#3c3836")
            cairo.set_rgba(cr, r, g, b, 0.55)
            cairo.rounded_rect(cr, x, y,
                self.cell_w, self.cell_h, 6)
            cairo.fill(cr)
        end

        local s = icons.icon_for(item, self.icon_size)
        local icon_y = y + self.pad_top
        if s then
            cairo.draw_surface(cr, s,
                x + (self.cell_w - self.icon_size) / 2, icon_y,
                self.icon_size, self.icon_size)
        end

        local label = item.name
        local avail = self.cell_w - 8
        local font = "DejaVu Sans 9"
        local tw = select(1, pango.measure(label, font))
        if tw > avail then
            local guard = 0
            while #label > 1 and guard < 60 do
                guard = guard + 1
                label = label:sub(1, #label - 1)
                tw = select(1, pango.measure(label .. "…", font))
                if tw <= avail then
                    label = label .. "…"
                    break
                end
            end
        end
        -- El nombre va justo debajo del icono, no al fondo de la
        -- celda. Esto evita el hueco visible cuando el icono es
        -- chico y la celda es más alta que el conjunto icono+label.
        local _, lh = pango.measure(label, font)
        local label_y = icon_y + self.icon_size + 4
        pango.draw_text(cr, x + (self.cell_w - tw) / 2,
            label_y, label, font,
            { r = fg[1], g = fg[2], b = fg[3] })

        ::continue::
    end

    cairo.restore(cr)
end

-- ── Eventos ──────────────────────────────────────────────────
function IconsView:on_mouse_move(mx, my)
    local idx = self:_idx_at(mx, my)
    if idx ~= self.hover_idx then
        self.hover_idx = idx
        self:damage()
    end
end

function IconsView:set_hover(v)
    Area.set_hover(self, v)
    if not v and self.hover_idx ~= -1 then
        self.hover_idx = -1
        self:damage()
    end
end

function IconsView:on_mouse_press(mx, my, button)
    local idx = self:_idx_at(mx, my)
    if idx < 0 then
        if button == 3 and self.on_right_click then
            self.on_right_click(nil, nil, mx, my)
        end
        return
    end
    if button == 1 and self.on_click then
        self.on_click(self.items[idx], idx)
    elseif button == 3 and self.on_right_click then
        self.on_right_click(self.items[idx], idx, mx, my)
    end
end

-- Zoom: pasos de 8px por click de rueda. Con Ctrl pulsado, la
-- rueda cambia el tamaño del icono en lugar de hacer scroll.
local ZOOM_STEP = 8

function IconsView:on_wheel(direction)
    -- Detectar Ctrl con el keymap. El evento de rueda no trae el
    -- estado de modificadores.
    local ctrl = false
    if self.srv and self.srv.conn then
        local xcb = require("lib.xcb")
        local km = xcb.query_keymap(self.srv.conn)
        if km then
            ctrl = xcb.key_pressed(km, 37)  -- Control_L
        end
    end

    if ctrl then
        -- Cambio de tamaño. Arriba (4) agranda, abajo (5) achica.
        local delta = (direction == 4) and ZOOM_STEP or -ZOOM_STEP
        self:set_icon_size(self.icon_size + delta)
        return
    end

    -- Sin Ctrl: scroll normal.
    local delta = (direction == 4) and -60 or 60
    self:set_offset(self.offset + delta)
end

M.new = function(theme, state)
    return IconsView.new(theme, state)
end

return M
