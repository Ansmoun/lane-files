-- breadcrumb: ruta navegable con segmentos clickeables.
-- Muestra la ruta actual dividida en partes separadas por "›".
-- Cada segmento navega al prefijo correspondiente al hacer click.
--
-- Si la ruta es muy larga para el ancho disponible, trunca los
-- segmentos intermedios con "…" y conserva el primero y los dos
-- últimos.

local Area  = require("lib.area")
local cairo = require("lib.cairo")
local pango = require("lib.pango")
local G     = require("lib.helpers.graphics")

local M = {}

local FONT       = "DejaVu Sans 10"
local SEP        = " › "
local SEP_W      = pango.measure(SEP, FONT)
local PAD_X      = 8
local ELLIPSIS   = "…"

-- Divide una ruta absoluta en segmentos navegables.
-- "/home/user/proyectos" -> {
--   { label = "/", path = "/" },
--   { label = "home", path = "/home" },
--   { label = "user", path = "/home/user" },
--   { label = "proyectos", path = "/home/user/proyectos" },
-- }
-- Normaliza una ruta introducida por el usuario:
--   - Colapsa barras múltiples: //home// -> /home
--   - Quita la barra final excepto en la raíz
--   - Convierte cadena vacía a "/"
local function normalize_path(path)
    if not path or path == "" then return "/" end
    path = path:gsub("//+", "/")
    if #path > 1 and path:sub(-1) == "/" then
        path = path:sub(1, -2)
    end
    return path
end

M.normalize_path = normalize_path

local function split_path(path)
    if not path or path == "" then return {} end
    if path == "/" then
        return { { label = "/", path = "/" } }
    end
    local segments = {}
    -- Raíz
    segments[1] = { label = "/", path = "/" }
    local acc = ""
    for part in path:gmatch("[^/]+") do
        acc = acc .. "/" .. part
        segments[#segments + 1] = { label = part, path = acc }
    end
    return segments
end

local Breadcrumb = setmetatable({}, { __index = Area })
Breadcrumb.__index = Breadcrumb

-- opts:
--   srv              -- Server (para el timer del click diferido)
--   on_double_click  -- callback con el path del segmento
function Breadcrumb.new(theme, on_navigate, opts)
    opts = opts or {}
    local self = setmetatable(Area.new({}), Breadcrumb)
    self._hover_visual = true
    self.theme = theme
    self.on_navigate = on_navigate
    self.on_double_click = opts.on_double_click
    self.srv = opts.srv
    self.path = "/"
    self.segments = {}
    self.hover_idx = nil
    self.min_h, self.max_h = 26, 26
    self.min_w, self.max_w = 100, 10000
    self._last_click = { time = 0, idx = 0 }
    self._click_timer = nil
    self:_rebuild()
    return self
end

-- Cancelar el timer pendiente. Se llama cuando el consumidor
-- desmonta el breadcrumb o cuando hay que limpiar el estado.
function Breadcrumb:cancel_pending()
    if self._click_timer then
        self._click_timer:cancel()
        self._click_timer = nil
    end
    self._last_click.time = 0
    self._last_click.idx = 0
end

function Breadcrumb:set_path(path)
    if self.path == path then return end
    self.path = path
    self:_rebuild()
    self:damage()
end

function Breadcrumb:_rebuild()
    self.segments = split_path(self.path)
    -- Calcular ancho de cada segmento y posiciones en el momento
    -- del draw (dependen del ancho disponible).
end

-- Devuelve el índice del segmento cuyo rango horizontal contiene x.
function Breadcrumb:_hit(x)
    if not self._segments_x then return nil end
    for i, seg in ipairs(self._segments_x) do
        if x >= seg.x0 and x < seg.x1 then
            return i
        end
    end
    return nil
end

-- Calcula la lista de segmentos visibles según el ancho disponible.
-- Si todos caben, los devuelve. Si no, devuelve el primero, "…" y
-- los dos últimos.
function Breadcrumb:_layout_segments(avail_w)
    -- Medir el ancho de cada segmento
    local widths = {}
    for i, seg in ipairs(self.segments) do
        local w = select(1, pango.measure(seg.label, FONT))
        widths[i] = w
    end
    local sep_w = SEP_W

    -- Ancho total si mostramos todo
    local total = 0
    for i, w in ipairs(widths) do
        total = total + w
        if i < #widths then total = total + sep_w end
    end

    if total <= avail_w then
        return self.segments, false
    end

    -- Hay que truncar. Conservar el primero y los dos últimos.
    if #self.segments <= 3 then
        -- No se puede truncar más. Devolver todo y dejar que el
        -- clip lo corte.
        return self.segments, false
    end

    local first  = self.segments[1]
    local last1  = self.segments[#self.segments - 1]
    local last2  = self.segments[#self.segments]

    local w_first = widths[1]
    local w_l1    = widths[#widths - 1]
    local w_l2    = widths[#widths]
    local w_ell   = select(1, pango.measure(ELLIPSIS, FONT))

    -- 4 segmentos visibles + 3 separadores
    local needed = w_first + w_ell + w_l1 + w_l2 + sep_w * 3
    if needed <= avail_w then
        return {
            first,
            { label = ELLIPSIS, path = nil },
            last1,
            last2,
        }, true
    end

    -- Incluso con elipsis no cabe. Devolver solo el último.
    return { last2 }, false
end

function Breadcrumb:draw(cr)
    local T = self.theme
    local x0 = self.x0
    local y0 = self.y0
    local w  = self:getWidth()
    local h  = self:getHeight()

    local avail = w - PAD_X * 2
    if avail <= 0 then return end

    local visible = self:_layout_segments(avail)

    -- Calcular posiciones en coordenadas LOCALES al breadcrumb.
    -- El desplazamiento global se aplica al dibujar y al hacer
    -- hit test. Guardar posiciones globales rompe el hit porque
    -- on_mouse_press recibe mx ya local.
    local segs_x = {}
    local x = PAD_X
    local sep_w = SEP_W

    for i, seg in ipairs(visible) do
        local sw = select(1, pango.measure(seg.label, FONT))
        segs_x[i] = {
            x0 = x,
            x1 = x + sw,
            seg = seg,
        }
        x = x + sw
        if i < #visible then x = x + sep_w end
    end
    self._segments_x = segs_x

    -- Dibujar
    local fg = T.fg_rgb or { 0.9, 0.9, 0.9 }
    local accent = T.accent_rgb or { 0.6, 0.75, 0.55 }
    local muted = T.muted_rgb or { 0.5, 0.5, 0.5 }

    local ty = y0 + (h - 12) / 2

    for i, entry in ipairs(segs_x) do
        local seg = entry.seg
        local is_hover = (self.hover_idx == i)
        local is_last  = (i == #segs_x)
        local clickable = seg.path ~= nil

        local col
        if not clickable then
            col = muted
        elseif is_hover then
            col = accent
        elseif is_last then
            -- El último segmento es el directorio actual. Se
            -- dibuja con el color de texto normal, ligeramente
            -- más fuerte.
            col = fg
        else
            col = fg
        end

        pango.draw_text(cr, x0 + entry.x0, ty, seg.label, FONT,
            { r = col[1], g = col[2], b = col[3] })

        -- Separador entre segmentos
        if i < #segs_x then
            pango.draw_text(cr, x0 + entry.x1, ty, SEP, FONT,
                { r = muted[1], g = muted[2], b = muted[3] })
        end
    end
end

function Breadcrumb:on_mouse_move(mx, my)
    local idx = self:_hit(mx)
    if idx ~= self.hover_idx then
        self.hover_idx = idx
        self:damage()
    end
end

function Breadcrumb:set_hover(v)
    Area.set_hover(self, v)
    if not v and self.hover_idx then
        self.hover_idx = nil
        self:damage()
    end
end

-- Timer del click diferido: 400ms es el umbral típico de
-- doble click.
local DOUBLE_CLICK_MS = 400

function Breadcrumb:on_mouse_press(mx, my, button)
    if button ~= 1 then return end
    local idx = self:_hit(mx)
    if not idx then return end
    local entry = self._segments_x[idx]
    if not entry or not entry.seg.path then return end

    -- Usar el reloj monótono del sistema si está disponible. Si
    -- no, cae a os.time con resolución de segundo.
    local now
    if self.srv then
        local timer = require("lib.timer")
        now = timer.now_ms()
    else
        now = os.time() * 1000
    end

    local is_double = (self._last_click.idx == idx)
        and (now - self._last_click.time) < DOUBLE_CLICK_MS

    if is_double then
        -- Cancelar el timer pendiente del primer click
        if self._click_timer then
            self._click_timer:cancel()
            self._click_timer = nil
        end
        self._last_click.time = 0
        self._last_click.idx = 0
        if self.on_double_click then
            self.on_double_click(entry.seg.path)
        end
    else
        -- Diferir la navegación. Si llega un segundo click antes
        -- del timeout, cancelamos y abrimos el editor en su lugar.
        self._last_click.time = now
        self._last_click.idx = idx
        local path = entry.seg.path
        local nav = self.on_navigate
        if self.srv and nav then
            if self._click_timer then
                self._click_timer:cancel()
            end
            self._click_timer = self.srv:add_timer(DOUBLE_CLICK_MS,
                function()
                    self._click_timer = nil
                    nav(path)
                end)
        elseif nav then
            nav(path)
        end
    end
end

M.new = Breadcrumb.new

return M
