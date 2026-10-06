-- status: barra inferior. Solo contador y atajos de teclado.

local W = require("lib.widgets")

local M = {}

-- Devuelve { widget = group, count = Text, hint = Text }
function M.new(theme)
    local count = W.Text.new {
        text = "0 elementos",
        font = "DejaVu Sans 9",
        align = "left", valign = "center",
        r = theme.muted_rgb[1],
        g = theme.muted_rgb[2],
        b = theme.muted_rgb[3],
    }

    local hint = W.Text.new {
        text = "F2 renombrar  ·  F5 refrescar  ·  Ctrl+F filtrar  ·  Ctrl+H ocultos  ·  Ctrl+A todo  ·  Doble clic abrir",
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
            { widget = hint,  weight = 1 },
        },
    }

    return {
        widget = bar,
        count  = count,
        hint   = hint,
    }
end

return M
