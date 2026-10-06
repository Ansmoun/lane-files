-- status: barra inferior con contador de elementos, input de
-- filtro y hint de teclas.

local W = require("lib.widgets")

local M = {}

-- Devuelve { widget = group, count = Text, input = TextInput }
function M.new(theme, handlers)
    handlers = handlers or {}

    local count = W.Text.new {
        text = "0 elementos",
        font = "DejaVu Sans 9",
        align = "left", valign = "center",
        r = theme.muted_rgb[1],
        g = theme.muted_rgb[2],
        b = theme.muted_rgb[3],
    }

    local input = W.TextInput.new {
        text = "",
        font = "DejaVu Sans 10",
        padding_x = 8, padding_y = 4,
        min_width = 200, min_height = 26,
        color_bg = theme.bg_card,
        color_border = theme.separator,
        corner_radius = 5,
        color_text = theme.fg_rgb,
        color_cursor = theme.accent_rgb,
        placeholder = "Filtrar  ·  ** prefijo = recursivo",
        color_placeholder = theme.muted_rgb,
        on_change = handlers.on_change,
        on_cancel = handlers.on_cancel,
    }

    local hint = W.Text.new {
        text = "Ctrl+H ocultos",
        font = "DejaVu Sans 9",
        align = "right", valign = "center",
        r = theme.muted_rgb[1],
        g = theme.muted_rgb[2],
        b = theme.muted_rgb[3],
    }

    local status_bar = W.Group.new {
        orientation = "horizontal",
        spacing = 8,
        padding = 6,
        children = {
            { widget = count, weight = 0 },
            { widget = input, weight = 1 },
            { widget = hint,  weight = 0 },
        },
    }

    return {
        widget = status_bar,
        count  = count,
        input  = input,
        hint   = hint,
    }
end

return M
