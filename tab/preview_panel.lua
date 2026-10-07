-- preview_panel: panel lateral con la previsualización de la
-- imagen seleccionada. Se muestra u oculta con F3.
--
-- Si el elemento seleccionado no es una imagen, muestra un ícono
-- de archivo grande o un mensaje.

local Area  = require("lib.area")
local cairo = require("lib.cairo")
local pango = require("lib.pango")
local G     = require("lib.helpers.graphics")
local icons_mod = require("tab.icons")
local image_preview = require("tab.image_preview")

local M = {}

local WIDTH = 280

local PreviewPanel = setmetatable({}, { __index = Area })
PreviewPanel.__index = PreviewPanel

function PreviewPanel.new(theme)
    local self = setmetatable(Area.new({}), PreviewPanel)
    self.theme = theme
    self.visible = false
    self.current_path = nil
    self.current_surface = nil
    self.current_entry = nil
    self.min_w, self.max_w = WIDTH, WIDTH
    self.min_h, self.max_h = 100, 10000
    return self
end

function PreviewPanel:set_visible(v)
    v = v and true or false
    if self.visible == v then return end
    self.visible = v
    self:invalidate_layout()
end

function PreviewPanel:toggle()
    self:set_visible(not self.visible)
end

-- Actualiza la previsualización para una entrada. Si es la misma
-- que ya estaba mostrada, no hace nada.
function PreviewPanel:set_entry(entry)
    local path = entry and entry.path or nil
    if path == self.current_path then
        self.current_entry = entry
        return
    end
    self.current_path = path
    self.current_entry = entry
    self.current_surface = nil

    if path and not entry.is_dir and image_preview.is_image(path) then
        -- Panel de 280px: pedimos el bucket "large" (256px). El
        -- bucket "normal" (128px) se ve borroso al escalarlo a
        -- ~250px. Si aun no esta cacheado lo generamos aqui mismo
        -- (~60 ms, ocurre solo al cambiar de seleccion).
        local bucket = "large"
        local surf = image_preview.load(path, bucket)
        if not surf then
            image_preview.request(path, bucket)
            surf = image_preview.load(path, bucket)
        end
        if surf then
            self.current_surface = surf
        end
    end
    self:damage()
end

function PreviewPanel:askMinMax(minw, minh, maxw, maxh)
    if not self.visible then
        return minw, minh, maxw, maxh
    end
    return minw + WIDTH, minh + 100, maxw + WIDTH, maxh + 10000
end

function PreviewPanel:layout(x0, y0, x1, y1)
    Area.layout(self, x0, y0, x1, y1)
end

function PreviewPanel:draw(cr)
    if not self.visible then return end
    local T = self.theme
    local x, y = self.x0, self.y0
    local w, h = self:getWidth(), self:getHeight()

    -- Fondo
    local bg = T.bg_card_rgb or T.bg_rgb or { 0.1, 0.1, 0.1 }
    cairo.set_rgb(cr, bg[1], bg[2], bg[3])
    cairo.rectangle(cr, x, y, w, h)
    cairo.fill(cr)

    local entry = self.current_entry
    if not entry then
        local muted = T.muted_rgb or { 0.5, 0.5, 0.5 }
        pango.draw_text(cr, x + 20, y + 20,
            "Sin selección", "DejaVu Sans 10",
            { r = muted[1], g = muted[2], b = muted[3] })
        return
    end

    local pad = 14
    local avail_w = w - pad * 2
    local avail_h = h - pad * 2

    -- Cabecera: nombre truncado
    local fg = T.fg_rgb or { 0.9, 0.9, 0.9 }
    local label = entry.name
    local fw = select(1, pango.measure(label, "DejaVu Sans Bold 10"))
    if fw > avail_w then
        local guard = 0
        while #label > 1 and guard < 60 do
            guard = guard + 1
            label = label:sub(1, #label - 1)
            fw = select(1, pango.measure(label .. "…",
                "DejaVu Sans Bold 10"))
            if fw <= avail_w then
                label = label .. "…"
                break
            end
        end
    end
    pango.draw_text(cr, x + pad, y + pad, label,
        "DejaVu Sans Bold 10",
        { r = fg[1], g = fg[2], b = fg[3] })

    -- Imagen (si aplica)
    if self.current_surface then
        local nw = cairo.surface_width(self.current_surface)
        local nh = cairo.surface_height(self.current_surface)
        if nw > 0 and nh > 0 then
            local scale = math.min(avail_w / nw, (avail_h - 60) / nh)
            local dw, dh = nw * scale, nh * scale
            local ix = x + (w - dw) / 2
            local iy = y + pad + 30 + (avail_h - 60 - dh) / 2
            cairo.draw_surface(cr, self.current_surface, ix, iy, dw, dh)
        end
    elseif entry.is_dir then
        local muted = T.muted_rgb or { 0.5, 0.5, 0.5 }
        pango.draw_text(cr, x + pad, y + pad + 30,
            "Carpeta", "DejaVu Sans 10",
            { r = muted[1], g = muted[2], b = muted[3] })
    else
        -- Archivo no-imagen: mostrar tipo y tamaño
        local muted = T.muted_rgb or { 0.5, 0.5, 0.5 }
        local size_str = icons_mod.human_size(entry.size)
        local type_str = icons_mod.type_label(entry)
        pango.draw_text(cr, x + pad, y + pad + 30,
            type_str .. "  ·  " .. size_str,
            "DejaVu Sans 10",
            { r = muted[1], g = muted[2], b = muted[3] })
    end
end

M.new = function(theme)
    return PreviewPanel.new(theme)
end

return M
