-- row: render de una fila del listado.
-- Columnas: icono, nombre, tamaño, fecha, tipo.
-- Distingue tres estados: normal, hover y seleccionado.

local cairo       = require("lib.cairo")
local pango       = require("lib.pango")
local G           = require("lib.helpers.graphics")
local icon_theme  = require("lib.icon_theme")
local icons       = require("tab.icons")

local M = {}

local COL_NAME = 24
local COL_SIZE_OFF = 380   -- distancia desde el borde derecho
local COL_DATE_OFF = 260
local COL_TYPE_OFF = 90

-- opts:
--   theme      -- tabla de tema
--   state      -- instancia de tab/state. Se consulta
--                 state.selected_idx y state.selected_set para
--                 decidir cómo pintar cada fila.
--   row_height -- alto de cada fila (default 26)
-- Devuelve función draw_row lista para ScrollView.
function M.make_draw_row(theme, state, row_height)
    row_height = row_height or 26

    return function(cr, item, idx, y, rh, width, hover)
        if not item then return end

        local is_focus = state and (idx == state.selected_idx)
        local in_set   = state and state.selected_set
                             and state.selected_set[item.path]
                             and true or false

        -- Fondo de la fila. Prioridad:
        --   1. Fila con foco -> acento fuerte + barra izquierda
        --   2. Fila en el conjunto -> acento suave
        --   3. Hover -> tinte de hover
        --   4. Normal -> fondo normal
        -- Siempre se pinta el fondo, incluso sin hover ni
        -- selección: si solo se pinta cuando hay hover, la fila
        -- que deja de estar bajo el mouse conserva el tinte
        -- anterior (stale pixels).
        if is_focus then
            local r, g, b = G.hex_to_rgba(theme.accent or "#8ec07c")
            cairo.set_rgba(cr, r, g, b, 0.30)
            cairo.rectangle(cr, 0, y, width, rh)
            cairo.fill(cr)
            -- Barra de acento a la izquierda
            cairo.set_rgb(cr, r, g, b)
            cairo.rectangle(cr, 0, y, 3, rh)
            cairo.fill(cr)
        elseif in_set then
            local r, g, b = G.hex_to_rgba(theme.accent or "#8ec07c")
            cairo.set_rgba(cr, r, g, b, 0.15)
            cairo.rectangle(cr, 0, y, width, rh)
            cairo.fill(cr)
            -- Barra tenue a la izquierda
            cairo.set_rgba(cr, r, g, b, 0.55)
            cairo.rectangle(cr, 0, y, 2, rh)
            cairo.fill(cr)
        elseif hover then
            local r, g, b = G.hex_to_rgba(theme.bg_focus)
            cairo.set_rgba(cr, r, g, b, 0.55)
            cairo.rectangle(cr, 0, y, width, rh)
            cairo.fill(cr)
        else
            local bg = theme.bg_rgb
            cairo.set_rgb(cr, bg[1], bg[2], bg[3])
            cairo.rectangle(cr, 0, y, width, rh)
            cairo.fill(cr)
        end

        -- Distribución proporcional de columnas:
        --   Nombre      -> 55%
        --   Tamaño      -> 15%
        --   Modificado  -> 20%
        --   Tipo        -> 10%
        -- Se calcula desde el borde izquierdo. Así el espacio se
        -- reparte de forma homogénea en cualquier ancho de ventana.
        local col_size = math.floor(width * 0.55)
        local col_date = math.floor(width * 0.70)
        local col_type = math.floor(width * 0.90)

        -- Icono del tema activo. icon_for resuelve el mime real,
        -- busca la variante de icono que existe en el tema y
        -- cachea el resultado. Después del primer frame, O(1).
        local s = icons.icon_for(item, 22)
        if s then
            local ix = 4
            local iy = y + (rh - 18) / 2
            cairo.draw_surface(cr, s, ix, iy, 18, 18)
        end

        local fg    = theme.fg_rgb    or { 0.9, 0.9, 0.9 }
        local muted = theme.muted_rgb or { 0.5, 0.5, 0.5 }
        local ty = y + (rh - 12) / 2

        -- Nombre (con clip al ancho disponible)
        cairo.save(cr)
        cairo.rectangle(cr, COL_NAME, y,
            col_size - COL_NAME - 8, rh)
        cairo.clip(cr)
        pango.draw_text(cr, COL_NAME, ty, item.name,
            "DejaVu Sans 10",
            { r = fg[1], g = fg[2], b = fg[3] })
        cairo.restore(cr)

        -- Tamaño
        local size_str = item.is_dir and "—" or icons.human_size(item.size)
        pango.draw_text(cr, col_size, ty, size_str,
            "DejaVu Sans 10",
            { r = muted[1], g = muted[2], b = muted[3] })

        -- Fecha
        pango.draw_text(cr, col_date, ty, icons.human_date(item.mtime),
            "DejaVu Sans 10",
            { r = muted[1], g = muted[2], b = muted[3] })

        -- Tipo
        pango.draw_text(cr, col_type, ty, icons.type_label(item),
            "DejaVu Sans 10",
            { r = muted[1], g = muted[2], b = muted[3] })

        -- Separador sutil entre filas
        cairo.set_rgba(cr, muted[1], muted[2], muted[3], 0.15)
        cairo.rectangle(cr, 0, y + rh - 1, width, 1)
        cairo.fill(cr)
    end
end

return M
