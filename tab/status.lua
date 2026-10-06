-- status: barra inferior. Contador de elementos a la izquierda
-- e información del elemento bajo el cursor a la derecha.

local W = require("lib.widgets")

local M = {}

-- Devuelve { widget, count, info, set_info, set_count }
--   count       -- Text con el contador
--   info        -- Text con la info del elemento hover
--   set_info(s) -- actualiza el texto de info
--   set_count(s)-- actualiza el texto de count
function M.new(theme)
    local count = W.Text.new {
        text = "0 elementos",
        font = "DejaVu Sans 9",
        align = "left", valign = "center",
        r = theme.muted_rgb[1],
        g = theme.muted_rgb[2],
        b = theme.muted_rgb[3],
    }

    local info = W.Text.new {
        text = "",
        font = "DejaVu Sans 9",
        align = "right", valign = "center",
        r = theme.muted_rgb[1],
        g = theme.muted_rgb[2],
        b = theme.muted_rgb[3],
    }

    local bar = W.Group.new {
        orientation = "horizontal",
        spacing = 8,
        padding = 6,
        children = {
            { widget = count, weight = 0 },
            { widget = info,  weight = 1 },
        },
    }

    -- Los métodos se llaman con `:` (status_view:set_count(txt)), así
    -- que el primer argumento es self. Declararlos como métodos con
    -- self explícito evita el error de "cannot convert table to string".
    local obj = {
        widget = bar,
        count  = count,
        info   = info,
    }

    function obj:set_info(text)
        self.info:set_text(text or "")
    end

    function obj:set_count(text)
        self.count:set_text(text or "")
    end

    return obj
end

return M
