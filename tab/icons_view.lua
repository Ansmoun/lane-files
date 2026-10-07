-- icons_view: vista en cuadrícula de iconos grandes con scroll.
-- Expone una interfaz compatible con ScrollView para que
-- ScrollLink funcione igual: set_offset, get_offset,
-- get_offset_max, on_change.
--
-- El tamaño de los iconos es dinámico. Se ajusta con
-- set_icon_size (Ctrl+rueda desde el consumidor).
--
-- Para imágenes se dibuja la miniatura real (PNG pre-escalado a
-- 128px generado con lib.thumbs) en lugar del icono del tema.

local Area  = require("lib.area")
local cairo = require("lib.cairo")
local pango = require("lib.pango")
local G     = require("lib.helpers.graphics")
local icons = require("tab.icons")
local image_preview = require("tab.image_preview")

local M = {}

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

    self.icon_size = DEFAULT_SZ
    self:_update_cell_dims()

    -- Cache de surfaces de miniaturas: path -> surface | false.
    self._thumb_cache = {}
    -- Cache de labels truncados. Clave: path .. ":" .. avail.
    self._label_cache = {}

    self.on_click       = nil
    self.on_right_click = nil

    self.min_w = 300
    self.min_h = 100
    self.max_w = 10000
    self.max_h = 10000
    return self
end

-- Recalcula el ancho y alto de la celda a partir del tamaño del
-- icono.
function IconsView:_update_cell_dims()
    local sz = self.icon_size
    self.cell_w  = math.floor(sz * 1.6)
    self.cell_h  = math.floor(sz * 1.85)
    self.gap     = math.max(4, math.floor(sz * 0.12))
    self.pad_top = math.max(6, math.floor(sz * 0.15))
    if self.cell_w < 56 then self.cell_w = 56 end
    if self.cell_h < 56 then self.cell_h = 56 end
end

function IconsView:set_icon_size(sz)
    if sz < SZ_MIN then sz = SZ_MIN end
    if sz > SZ_MAX then sz = SZ_MAX end
    if sz == self.icon_size then return false end
    self.icon_size = sz
    self:_update_cell_dims()
    -- El ancho de celda cambió: invalidar labels cacheados.
    self._label_cache = {}
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

IconsView.on_icon_size_change = nil

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
    items = items or {}
    -- Detectar cambio de directorio comparando el padre del primer
    -- item. Si cambia, limpiar el cache de thumbs (los del
    -- directorio viejo ya no son útiles en memoria).
    local same_dir = true
    if #items == 0 or #self.items == 0 then
        same_dir = (#items == #self.items)
    else
        local a = items[1].path:match("^(.+)/[^/]+$")
        local b = self.items[1] and
            self.items[1].path:match("^(.+)/[^/]+$")
        if a ~= b then same_dir = false end
    end

    self.items = items
    self.hover_idx = -1

    if not same_dir then
        self._thumb_cache = {}
        self._label_cache = {}
    end

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
    -- Arrancar el timer de poll una sola vez. Comprueba cada 300ms
    -- si algún thumbnail pasó de "no listo" a "listo" y daña solo
    -- esas celdas.
    if win and win.server and not self._poll_timer then
        self._poll_timer = win.server:add_timer(100, function()
            self:_poll_thumbs()
        end)
    end
end

-- Recorre los items visibles. Para los que son imágenes y no
-- tienen surface todavía, comprueba si el thumb terminó. Si sí,
-- carga y daña la celda.
function IconsView:_poll_thumbs()
    if not self.window or self.window.destroyed then return end

    -- Presupuesto por tick. La decodificacion ronda los 5-90 ms
    -- por imagen en este hardware; 30 ms deja el resto del tick
    -- (100 ms) para eventos de X y draws. La UI se mantiene
    -- responsiva aunque haya cientos de thumbs por generar.
    local BUDGET_MS = 30
    local start = os.clock()
    local generated = 0

    for i, item in ipairs(self.items) do
        -- Cortamos cuando ya generamos al menos 1 y se acabo el
        -- presupuesto. "Al menos 1" garantiza progreso aunque una
        -- sola imagen tarde mas que el presupuesto entero.
        if generated > 0
           and (os.clock() - start) * 1000 >= BUDGET_MS then
            break
        end

        if item.path and not item.is_dir
           and image_preview.is_image(item.path)
           and not self._thumb_cache[item.path] then
            local x, y = self:_cell_rect(i)
            if y + self.cell_h >= self.y0 and y <= self.y1 then
                -- 1) Cache hit: casi gratis (lee metadata, sin
                --    decodificar). Se hace antes de generar nada
                --    para poblar rapido lo que ya este en disco.
                local surf = image_preview.load(item.path)
                if surf then
                    self._thumb_cache[item.path] = surf
                    self:_damage_cell(i)
                else
                    -- 2) Generar (caro). Despues reintentar load.
                    image_preview.request(item.path)
                    generated = generated + 1
                    surf = image_preview.load(item.path)
                    if surf then
                        self._thumb_cache[item.path] = surf
                        self:_damage_cell(i)
                    end
                end
            end
        end
    end
end

-- ── Cálculo de posiciones ────────────────────────────────────
function IconsView:_cell_rect(i)
    local col = (i - 1) % self.cols
    local row = math.floor((i - 1) / self.cols)
    local x = self.x0 + col * (self.cell_w + self.gap)
    local y = self.y0 + row * (self.cell_h + self.gap) - self.offset
    return x, y
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

-- Daña solo la celda del índice dado. Sin esto, mover el mouse
-- redibuja el widget completo.
function IconsView:_damage_cell(idx)
    if not self.window or idx < 1 then return end
    local col = (idx - 1) % self.cols
    local row = math.floor((idx - 1) / self.cols)
    local x0 = self.x0 + col * (self.cell_w + self.gap)
    local y0 = self.y0 + row * (self.cell_h + self.gap) - self.offset
    local x1 = x0 + self.cell_w
    local y1 = y0 + self.cell_h
    if y1 < self.y0 or y0 > self.y1 then return end
    if x1 < self.x0 or x0 > self.x1 then return end
    self.window:add_damage(x0, y0, x1, y1)
end

-- ── Cache de miniaturas ─────────────────────────────────────
-- Devuelve la surface del thumb si ya esta en disco (cache hit).
-- NO genera: bloquearia el draw. La generacion la maneja el poll
-- timer, a razon de 1 thumbnail por tick.
function IconsView:_thumb_for(item)
    if not item or not item.path then return nil end
    if item.is_dir then return nil end

    local cached = self._thumb_cache[item.path]
    if cached ~= nil then
        return cached or nil
    end
    if not image_preview.is_image(item.path) then
        self._thumb_cache[item.path] = false
        return nil
    end
    local surf = image_preview.load(item.path)
    if surf then
        self._thumb_cache[item.path] = surf
        return surf
    end
    return nil
end

function IconsView:clear_thumb_cache()
    self._thumb_cache = {}
end

-- Libera recursos al cerrar la tab: cancela el timer de poll,
-- destruye las surfaces cairo de la cache (memoria nativa, no
-- liberable por GC), y suelta los items.
function IconsView:destroy()
    if self._poll_timer then
        self._poll_timer:cancel()
        self._poll_timer = nil
    end
    local cairo = require("lib.cairo")
    for _, surf in pairs(self._thumb_cache) do
        if surf and surf ~= false then
            cairo.destroy_surface(surf)
        end
    end
    self._thumb_cache = {}
    self._label_cache = {}
    self.items = {}
    self.window = nil
end

-- Devuelve el label truncado al ancho disponible. Cachea el
-- resultado por (item, ancho). pango.measure crea un PangoLayout
-- cada vez; llamarlo en el draw por cada item es carísimo.
function IconsView:_display_label(item, avail)
    local key = item.path .. ":" .. avail
    local cached = self._label_cache[key]
    if cached then
        return cached.label, cached.w, cached.h
    end

    local label = item.name
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
    local _, th = pango.measure(label, font)
    self._label_cache[key] = { label = label, w = tw, h = th }
    return label, tw, th
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

        local icon_y = y + self.pad_top
        local thumb = self:_thumb_for(item)
        if thumb then
            local nw = cairo.surface_width(thumb)
            local nh = cairo.surface_height(thumb)
            if nw > 0 and nh > 0 then
                local scale = math.min(self.icon_size / nw,
                                       self.icon_size / nh)
                local dw = nw * scale
                local dh = nh * scale
                local ix = x + (self.cell_w - dw) / 2
                local iy = icon_y + (self.icon_size - dh) / 2
                -- Filtro FAST: el thumb ya está pre-escalado a 128.
                cairo.draw_surface_fast(cr, thumb, ix, iy, dw, dh)
            end
        else
            local s = icons.icon_for(item, self.icon_size)
            if s then
                cairo.draw_surface(cr, s,
                    x + (self.cell_w - self.icon_size) / 2, icon_y,
                    self.icon_size, self.icon_size)
            end
        end

        local avail = self.cell_w - 8
        local font = "DejaVu Sans 9"
        local label, tw, lh = self:_display_label(item, avail)
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
        local old = self.hover_idx
        self.hover_idx = idx
        self:_damage_cell(old)
        self:_damage_cell(idx)
    end
end

function IconsView:set_hover(v)
    Area.set_hover(self, v)
    if not v and self.hover_idx ~= -1 then
        local old = self.hover_idx
        self.hover_idx = -1
        self:_damage_cell(old)
    end
end

function IconsView:on_mouse_press(mx, my, button)
    if self.window and self.window.server
       and self.window.server.is_input_blocked
       and self.window.server:is_input_blocked() then
        return
    end

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

function IconsView:on_wheel(direction)
    local ctrl = false
    if self.srv and self.srv.conn then
        local xcb = require("lib.xcb")
        local km = xcb.query_keymap(self.srv.conn)
        if km then
            ctrl = xcb.key_pressed(km, 37)
        end
    end
    if ctrl then
        local delta = (direction == 4) and 8 or -8
        self:set_icon_size(self.icon_size + delta)
        return
    end
    local delta = (direction == 4) and -60 or 60
    self:set_offset(self.offset + delta)
end

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

M.new = function(theme, state)
    return IconsView.new(theme, state)
end

return M
