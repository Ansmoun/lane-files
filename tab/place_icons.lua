-- place_icons: dibuja iconos de lugares con primitivas cairo.
-- Evita depender del tema de iconos del sistema, que suele traer
-- SVG monocromo que sin tinte se ven como cuadrados blancos, o
-- SVG que resvg no puede parsear.
--
-- Cada función recibe (cr, x, y, size, r, g, b) y dibuja el icono
-- en el rectángulo (x, y, size, size) con el color dado.

local cairo = require("lib.cairo")

local M = {}

-- Configura el color y limpia el path antes de dibujar.
local function setup(cr, r, g, b)
    cairo.set_rgb(cr, r, g, b)
    cairo.new_path(cr)
end

-- Configura trazo con grosor relativo al tamaño.
local function stroke_style(cr, size)
    cairo.set_line_width(cr, math.max(1.5, size * 0.09))
end

-- ── Iconos ─────────────────────────────────────────────────
local function draw_folder(cr, x, y, s, r, g, b)
    setup(cr, r, g, b)
    local tab = s * 0.35
    local h = s * 0.75
    -- Silueta de carpeta con pestaña
    cairo.move_to(cr, x, y + s * 0.20)
    cairo.line_to(cr, x + tab, y + s * 0.20)
    cairo.line_to(cr, x + tab + s * 0.08, y + s * 0.28)
    cairo.line_to(cr, x + s, y + s * 0.28)
    cairo.line_to(cr, x + s, y + s * 0.85)
    cairo.line_to(cr, x, y + s * 0.85)
    cairo.close_path(cr)
    stroke_style(cr, s)
    cairo.stroke(cr)
end

local function draw_home(cr, x, y, s, r, g, b)
    setup(cr, r, g, b)
    -- Techo
    cairo.move_to(cr, x + s * 0.10, y + s * 0.45)
    cairo.line_to(cr, x + s * 0.50, y + s * 0.10)
    cairo.line_to(cr, x + s * 0.90, y + s * 0.45)
    -- Paredes
    cairo.move_to(cr, x + s * 0.20, y + s * 0.40)
    cairo.line_to(cr, x + s * 0.20, y + s * 0.90)
    cairo.line_to(cr, x + s * 0.80, y + s * 0.90)
    cairo.line_to(cr, x + s * 0.80, y + s * 0.40)
    -- Puerta
    cairo.move_to(cr, x + s * 0.42, y + s * 0.90)
    cairo.line_to(cr, x + s * 0.42, y + s * 0.62)
    cairo.line_to(cr, x + s * 0.58, y + s * 0.62)
    cairo.line_to(cr, x + s * 0.58, y + s * 0.90)
    stroke_style(cr, s)
    cairo.stroke(cr)
end

local function draw_desktop(cr, x, y, s, r, g, b)
    setup(cr, r, g, b)
    -- Monitor
    cairo.rectangle(cr, x + s * 0.10, y + s * 0.15,
        s * 0.80, s * 0.55)
    -- Base
    cairo.move_to(cr, x + s * 0.50, y + s * 0.70)
    cairo.line_to(cr, x + s * 0.50, y + s * 0.85)
    cairo.move_to(cr, x + s * 0.30, y + s * 0.85)
    cairo.line_to(cr, x + s * 0.70, y + s * 0.85)
    stroke_style(cr, s)
    cairo.stroke(cr)
end

local function draw_downloads(cr, x, y, s, r, g, b)
    setup(cr, r, g, b)
    -- Flecha hacia abajo
    cairo.move_to(cr, x + s * 0.50, y + s * 0.15)
    cairo.line_to(cr, x + s * 0.50, y + s * 0.65)
    cairo.move_to(cr, x + s * 0.30, y + s * 0.48)
    cairo.line_to(cr, x + s * 0.50, y + s * 0.68)
    cairo.line_to(cr, x + s * 0.70, y + s * 0.48)
    -- Base
    cairo.move_to(cr, x + s * 0.18, y + s * 0.85)
    cairo.line_to(cr, x + s * 0.82, y + s * 0.85)
    stroke_style(cr, s)
    cairo.stroke(cr)
end

local function draw_documents(cr, x, y, s, r, g, b)
    setup(cr, r, g, b)
    -- Hoja con esquina doblada
    cairo.move_to(cr, x + s * 0.22, y + s * 0.10)
    cairo.line_to(cr, x + s * 0.65, y + s * 0.10)
    cairo.line_to(cr, x + s * 0.80, y + s * 0.28)
    cairo.line_to(cr, x + s * 0.80, y + s * 0.90)
    cairo.line_to(cr, x + s * 0.22, y + s * 0.90)
    cairo.close_path(cr)
    -- Esquina doblada
    cairo.move_to(cr, x + s * 0.65, y + s * 0.10)
    cairo.line_to(cr, x + s * 0.65, y + s * 0.28)
    cairo.line_to(cr, x + s * 0.80, y + s * 0.28)
    -- Líneas de texto
    cairo.move_to(cr, x + s * 0.35, y + s * 0.50)
    cairo.line_to(cr, x + s * 0.65, y + s * 0.50)
    cairo.move_to(cr, x + s * 0.35, y + s * 0.65)
    cairo.line_to(cr, x + s * 0.65, y + s * 0.65)
    stroke_style(cr, s)
    cairo.stroke(cr)
end

local function draw_images(cr, x, y, s, r, g, b)
    setup(cr, r, g, b)
    -- Marco
    cairo.rectangle(cr, x + s * 0.12, y + s * 0.22,
        s * 0.76, s * 0.56)
    -- Sol
    cairo.new_sub_path(cr)
    cairo.arc(cr, x + s * 0.32, y + s * 0.42,
        s * 0.08, 0, 2 * math.pi)
    -- Montañas
    cairo.move_to(cr, x + s * 0.12, y + s * 0.72)
    cairo.line_to(cr, x + s * 0.35, y + s * 0.50)
    cairo.line_to(cr, x + s * 0.55, y + s * 0.65)
    cairo.line_to(cr, x + s * 0.70, y + s * 0.55)
    cairo.line_to(cr, x + s * 0.88, y + s * 0.72)
    stroke_style(cr, s)
    cairo.stroke(cr)
end

local function draw_music(cr, x, y, s, r, g, b)
    setup(cr, r, g, b)
    -- Nota
    cairo.new_sub_path(cr)
    cairo.arc(cr, x + s * 0.32, y + s * 0.72,
        s * 0.14, 0, 2 * math.pi)
    cairo.move_to(cr, x + s * 0.46, y + s * 0.72)
    cairo.line_to(cr, x + s * 0.46, y + s * 0.18)
    cairo.line_to(cr, x + s * 0.78, y + s * 0.25)
    cairo.line_to(cr, x + s * 0.78, y + s * 0.55)
    cairo.new_sub_path(cr)
    cairo.arc(cr, x + s * 0.64, y + s * 0.55,
        s * 0.14, 0, 2 * math.pi)
    stroke_style(cr, s)
    cairo.stroke(cr)
end

local function draw_videos(cr, x, y, s, r, g, b)
    setup(cr, r, g, b)
    -- Marco de película
    cairo.rectangle(cr, x + s * 0.10, y + s * 0.22,
        s * 0.80, s * 0.56)
    -- Triángulo de play
    cairo.move_to(cr, x + s * 0.42, y + s * 0.36)
    cairo.line_to(cr, x + s * 0.42, y + s * 0.64)
    cairo.line_to(cr, x + s * 0.66, y + s * 0.50)
    cairo.close_path(cr)
    stroke_style(cr, s)
    cairo.stroke(cr)
end

local function draw_templates(cr, x, y, s, r, g, b)
    setup(cr, r, g, b)
    -- Tablero de dibujo
    cairo.rectangle(cr, x + s * 0.15, y + s * 0.20,
        s * 0.70, s * 0.60)
    -- Lápiz diagonal
    cairo.move_to(cr, x + s * 0.30, y + s * 0.70)
    cairo.line_to(cr, x + s * 0.35, y + s * 0.78)
    cairo.line_to(cr, x + s * 0.75, y + s * 0.38)
    cairo.line_to(cr, x + s * 0.70, y + s * 0.30)
    cairo.close_path(cr)
    stroke_style(cr, s)
    cairo.stroke(cr)
end

local function draw_public(cr, x, y, s, r, g, b)
    setup(cr, r, g, b)
    -- Globo terráqueo
    cairo.new_sub_path(cr)
    cairo.arc(cr, x + s * 0.50, y + s * 0.50,
        s * 0.36, 0, 2 * math.pi)
    -- Meridiano
    cairo.move_to(cr, x + s * 0.14, y + s * 0.50)
    cairo.line_to(cr, x + s * 0.86, y + s * 0.50)
    -- Curva vertical
    cairo.move_to(cr, x + s * 0.50, y + s * 0.14)
    cairo.line_to(cr, x + s * 0.50, y + s * 0.86)
    stroke_style(cr, s)
    cairo.stroke(cr)
end

local function draw_trash(cr, x, y, s, r, g, b)
    setup(cr, r, g, b)
    -- Tapa
    cairo.move_to(cr, x + s * 0.20, y + s * 0.25)
    cairo.line_to(cr, x + s * 0.80, y + s * 0.25)
    -- Asa
    cairo.move_to(cr, x + s * 0.40, y + s * 0.25)
    cairo.line_to(cr, x + s * 0.40, y + s * 0.15)
    cairo.line_to(cr, x + s * 0.60, y + s * 0.15)
    cairo.line_to(cr, x + s * 0.60, y + s * 0.25)
    -- Cuerpo
    cairo.move_to(cr, x + s * 0.25, y + s * 0.30)
    cairo.line_to(cr, x + s * 0.30, y + s * 0.88)
    cairo.line_to(cr, x + s * 0.70, y + s * 0.88)
    cairo.line_to(cr, x + s * 0.75, y + s * 0.30)
    stroke_style(cr, s)
    cairo.stroke(cr)
end

local function draw_bookmark(cr, x, y, s, r, g, b)
    setup(cr, r, g, b)
    cairo.move_to(cr, x + s * 0.28, y + s * 0.12)
    cairo.line_to(cr, x + s * 0.72, y + s * 0.12)
    cairo.line_to(cr, x + s * 0.72, y + s * 0.88)
    cairo.line_to(cr, x + s * 0.50, y + s * 0.68)
    cairo.line_to(cr, x + s * 0.28, y + s * 0.88)
    cairo.close_path(cr)
    stroke_style(cr, s)
    cairo.stroke(cr)
end

-- ── Dispatch ───────────────────────────────────────────────
local DISPATCH = {
    ["home"]               = draw_home,
    ["user-desktop"]       = draw_desktop,
    ["folder-documents"]   = draw_documents,
    ["folder-download"]    = draw_downloads,
    ["folder-pictures"]    = draw_images,
    ["folder-music"]       = draw_music,
    ["folder-videos"]      = draw_videos,
    ["folder-templates"]   = draw_templates,
    ["folder-publicshare"] = draw_public,
    ["user-trash"]         = draw_trash,
    ["folder"]             = draw_folder,
    ["bookmark"]           = draw_bookmark,
}

function M.draw(cr, x, y, size, name, r, g, b)
    local fn = DISPATCH[name]
    if not fn then fn = draw_folder end
    fn(cr, x, y, size, r, g, b)
end

M.has = function(name)
    return DISPATCH[name] ~= nil
end

return M
