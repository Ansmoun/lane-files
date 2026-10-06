-- Tab Files: file manager minimo.
-- Ventana normal (no daemon). Se abre desde el launcher o sxhkd.

local W       = require("lib.widgets")
local Area    = require("lib.area")
local cairo   = require("lib.cairo")
local pango   = require("lib.pango")
local G       = require("lib.helpers.graphics")
local log     = require("lib.log")
local icon_theme = require("lib.icon_theme")

local M = {}

-- Los iconos de navegacion se resuelven via lib.icons.
-- Los iconos de mimetype usan lib.icon_theme (el tema del sistema).

local ROW_H   = 26
local HEAD_H  = 26
local NAV_H   = 40

-- Mapeo extension -> nombre de mimetype del tema de iconos activo.
-- Los nombres siguen la especificacion freedesktop (text-x-generic,
-- image-x-generic, etc.). Los temas Vimix/Papirus/Adwaita los
-- implementan. Si una extension no esta, cae a un generico.
local MIME_BY_EXT = {
    -- texto plano
    txt = "text-x-generic", md = "text-x-generic",
    log = "text-x-generic", conf = "text-x-generic",
    cfg = "text-x-generic", ini = "text-x-generic",
    toml = "text-x-generic", yml = "text-x-generic",
    yaml = "text-x-generic",
    -- codigo fuente (los temas suelen tener iconos especificos)
    lua  = "text-x-script",
    sh   = "text-x-script",
    py   = "text-x-python",
    c    = "text-x-csrc",
    h    = "text-x-chdr",
    rs   = "text-rust",
    js   = "text-x-javascript",
    ts   = "text-x-javascript",
    go   = "text-x-go",
    html = "text-html",
    htm  = "text-html",
    xml  = "text-xml",
    css  = "text-css",
    json = "application-json",
    -- imagenes
    png  = "image-x-generic", jpg  = "image-x-generic",
    jpeg = "image-x-generic", gif  = "image-x-generic",
    bmp  = "image-x-generic", svg  = "image-x-generic",
    webp = "image-x-generic", ico  = "image-x-generic",
    tiff = "image-x-generic",
    -- video
    mp4 = "video-x-generic", mkv = "video-x-generic",
    webm = "video-x-generic", avi = "video-x-generic",
    mov = "video-x-generic", flv = "video-x-generic",
    mpg = "video-x-generic",
    -- audio
    mp3  = "audio-x-generic", ogg = "audio-x-generic",
    wav  = "audio-x-generic", flac = "audio-x-generic",
    m4a  = "audio-x-generic", opus = "audio-x-generic",
    -- comprimido
    zip = "application-x-archive", tar = "application-x-archive",
    gz  = "application-x-archive", bz2 = "application-x-archive",
    xz  = "application-x-archive", zst = "application-x-archive",
    rar = "application-x-archive",
    ["7z"] = "application-x-archive",
    -- documentos
    pdf = "application-pdf",
    doc = "application-msword", docx = "application-msword",
    xls = "application-vnd.ms-excel",
    xlsx = "application-vnd.ms-excel",
    ppt = "application-vnd.ms-powerpoint",
    pptx = "application-vnd.ms-powerpoint",
    odt = "application-vnd.oasis.opendocument.text",
    ods = "application-vnd.oasis.opendocument.spreadsheet",
    -- ejecutables / binarios
    sh_ = "application-x-executable",  -- placeholder
    so  = "application-x-sharedlib",
    o   = "application-x-object",
    a   = "application-x-archive",
    bin = "application-x-executable",
    deb = "application-x-deb",
    rpm = "application-x-rpm",
    -- varios
    iso = "application-x-cd-image",
    img = "application-x-cd-image",
}

local function mime_for(entry)
    if entry.is_dir then return "folder" end
    local ext = entry.name:match("%.([^.]+)$")
    if ext then
        ext = ext:lower()
        return MIME_BY_EXT[ext] or "text-x-generic"
    end
    return "text-x-generic"
end

local function type_label(entry)
    if entry.is_dir then return "carpeta" end
    local ext = entry.name:match("%.([^.]+)$")
    if not ext then return "archivo" end
    return ext:lower()
end

local function human_size(n)
    if not n or n == 0 then return "—" end
    if n < 1024 then return n .. " B" end
    if n < 1024 * 1024 then return string.format("%.1f K", n / 1024) end
    if n < 1024 * 1024 * 1024 then
        return string.format("%.1f M", n / (1024 * 1024))
    end
    return string.format("%.1f G", n / (1024 * 1024 * 1024))
end

local function human_date(mtime)
    if not mtime or mtime == 0 then return "—" end
    return os.date("%Y-%m-%d %H:%M", mtime)
end

-- Divide una ruta por "/" respetando que empieza con "/"
local function split_path(p)
    local parts = {}
    for part in p:gmatch("[^/]+") do
        parts[#parts + 1] = part
    end
    return parts
end

local function join_path(base, name)
    if base == "/" then return "/" .. name end
    return base .. "/" .. name
end

local function parent_path(p)
    if not p or p == "/" then return "/" end
    local parent = p:match("^(.+)/[^/]+$")
    if not parent or parent == "" then return "/" end
    return parent
end

-- ── Widget Divider ────────────────────────────────────────────────
local Divider = setmetatable({}, { __index = Area })
Divider.__index = Divider

function Divider.new(theme)
    local self = setmetatable(Area.new({}), Divider)
    self.color = theme.separator_rgb or { 0.2, 0.2, 0.2 }
    self.min_h, self.max_h = 1, 1
    return self
end

function Divider:draw(cr)
    local c = self.color
    cairo.set_rgb(cr, c[1], c[2], c[3])
    cairo.rectangle(cr, self.x0, self.y0, self:getWidth(), 1)
    cairo.fill(cr)
end

-- ── Boton chico de la barra de navegacion ─────────────────────────
local NavButton = setmetatable({}, { __index = Area })
NavButton.__index = NavButton

function NavButton.new(theme, icon_name, on_click, opts)
    opts = opts or {}
    local self = setmetatable(Area.new({}), NavButton)
    self._hover_visual = true
    self.on_click = on_click
    self.icon_name = icon_name
    self.icon_surface = require("lib.icons").surface(
        "files/" .. icon_name, opts.size or 24)
    self.size = opts.size or 24
    self.min_w, self.max_w = self.size + 8, self.size + 8
    self.min_h, self.max_h = NAV_H, NAV_H
    self.fg_color = theme.fg_rgb or { 0.9, 0.9, 0.9 }
    self.hover_color = theme.accent_rgb or { 1, 1, 1 }
    return self
end

function NavButton:set_hover(v)
    v = v and true or false
    if self.hover == v then return end
    Area.set_hover(self, v)
end

function NavButton:draw(cr)
    if not self.icon_surface then return end
    local col = self.hover and self.hover_color or self.fg_color
    local x = self.x0 + (self:getWidth() - self.size) / 2
    local y = self.y0 + (self:getHeight() - self.size) / 2
    cairo.draw_surface_tinted(cr, self.icon_surface, x, y,
        self.size, self.size, col[1], col[2], col[3])
end

function NavButton:on_mouse_press(mx, my, button)
    if button == 1 and self.on_click then self.on_click() end
end

-- ── Header del listado ────────────────────────────────────────────
local ListHeader = setmetatable({}, { __index = Area })
ListHeader.__index = ListHeader

function ListHeader.new(theme)
    local self = setmetatable(Area.new({}), ListHeader)
    self.min_h, self.max_h = HEAD_H, HEAD_H
    self.fg = theme.muted_rgb or { 0.5, 0.5, 0.5 }
    self.font = "DejaVu Sans Bold 9"
    return self
end

function ListHeader:draw(cr)
    local w = self:getWidth()
    local col_name = 24
    local col_size = w - 380
    local col_date = w - 260
    local col_type = w - 90
    local c = self.fg
    local opts = { r = c[1], g = c[2], b = c[3] }
    local y = self.y0 + (self:getHeight() - 12) / 2
    pango.draw_text(cr, self.x0 + col_name, y, "Nombre",
        self.font, opts)
    pango.draw_text(cr, self.x0 + col_size, y, "Tamaño",
        self.font, opts)
    pango.draw_text(cr, self.x0 + col_date, y, "Modificado",
        self.font, opts)
    pango.draw_text(cr, self.x0 + col_type, y, "Tipo",
        self.font, opts)
end

-- opts:
--   initial_path  -- default: $HOME
function M.new(srv, theme, opts)
    opts = opts or {}

    local state = {
        cwd          = opts.initial_path or os.getenv("HOME"),
        entries      = {},
        history      = {},
        history_idx  = 0,
        show_hidden  = false,
        filter       = "",
    }

    -- Forwards
    local input
    local list
    local status_lbl
    local path_lbl

    -- ── Listar directorio ─────────────────────────────────────────
    local function list_dir(path)
        local entries = {}
        local cmd = string.format(
            "ls -la --time-style=+%%s '%s' 2>/dev/null", path)
        local p = io.popen(cmd)
        if not p then return entries end
        -- ls -la tiene la cabecera "total N" en la primera linea
        local first = true
        for line in p:lines() do
            if first then
                first = false
            else
                -- Formato: perms links owner group size date name...
                -- --time-style=+%s hace que date sea un unix ts
                local perms, _, _, _, size, mtime, name =
                    line:match("^(%S+)%s+(%d+)%s+(%S+)%s+(%S+)%s+(%d+)%s+(%d+)%s+(.+)$")
                if perms and name then
                    -- ls puede agregar " -> target" para symlinks
                    name = name:gsub(" %-> .*$", "")
                    if name ~= "." and name ~= ".." then
                        local is_dir = perms:sub(1, 1) == "d"
                        local is_hidden = name:sub(1, 1) == "."
                        entries[#entries + 1] = {
                            name      = name,
                            is_dir    = is_dir,
                            is_hidden = is_hidden,
                            size      = tonumber(size) or 0,
                            mtime     = tonumber(mtime) or 0,
                            path      = join_path(path, name),
                        }
                    end
                end
            end
        end
        p:close()

        -- Ordenar: directorios primero, luego alfabetico case-insensitive
        table.sort(entries, function(a, b)
            if a.is_dir ~= b.is_dir then return a.is_dir end
            return a.name:lower() < b.name:lower()
        end)
        return entries
    end

    -- Busqueda recursiva con fd. Solo se activa cuando el filtro
    -- empieza con "**". Devuelve entries con "subpath" para mostrar
    -- la ruta relativa.
    local function list_recursive(pattern)
        local entries = {}
        local cmd = string.format(
            "nice -n 19 ionice -c 3 timeout 5 fd --max-depth 5 " ..
            "--max-results 500 --hidden --exclude .git " ..
            "--exclude node_modules --exclude .cache " ..
            "--ignore-case --type f --type d '%s' '%s' 2>/dev/null",
            pattern:gsub("'", "'\\''"), state.cwd:gsub("'", "'\\''"))
        local p = io.popen(cmd)
        if not p then return entries end
        for line in p:lines() do
            -- fd devuelve paths absolutos o relativos al root.
            -- Los normalizamos a relativos al cwd.
            local abs = line
            if abs:sub(1, 1) ~= "/" then
                abs = state.cwd .. "/" .. abs
            end
            local rel = abs:sub(#state.cwd + 2)  -- quitar prefijo + "/"
            if rel ~= "" then
                local name = rel:match("[^/]+$") or rel
                local is_dir = false
                -- Detectar si es dir con stat
                local st = io.popen("test -d '" ..
                    abs:gsub("'", "'\\''") .. "' && echo D")
                if st and st:read("*l") == "D" then is_dir = true end
                if st then st:close() end
                local size, mtime = 0, 0
                local sp = io.popen("stat -c '%s %Y' '" ..
                    abs:gsub("'", "'\\''") .. "' 2>/dev/null")
                if sp then
                    local out = sp:read("*l")
                    sp:close()
                    if out then
                        size, mtime = out:match("^(%d+) (%d+)$")
                        size = tonumber(size) or 0
                        mtime = tonumber(mtime) or 0
                    end
                end
                entries[#entries + 1] = {
                    name      = rel,  -- mostramos la subruta
                    is_dir    = is_dir,
                    is_hidden = name:sub(1, 1) == ".",
                    size      = size,
                    mtime     = mtime,
                    path      = abs,
                }
            end
        end
        p:close()
        table.sort(entries, function(a, b)
            return a.name:lower() < b.name:lower()
        end)
        return entries
    end

    local function apply_filter(entries)
        if state.filter == "" then
            if state.show_hidden then
                return entries
            end
            local out = {}
            for _, e in ipairs(entries) do
                if not e.is_hidden then out[#out + 1] = e end
            end
            return out
        end
        local f = state.filter:lower()
        local out = {}
        for _, e in ipairs(entries) do
            if (state.show_hidden or not e.is_hidden)
               and e.name:lower():find(f, 1, true) then
                out[#out + 1] = e
            end
        end
        return out
    end

    local function update_status(visible, total)
        if not status_lbl then return end
        local n = #visible
        local txt
        if state.filter ~= "" then
            txt = string.format("%d de %d (filtro)", n, total)
        elseif n == 1 then
            txt = "1 elemento"
        else
            txt = string.format("%d elementos", n)
        end
        status_lbl:set_text(txt)
    end

    local function refresh()
        local all, vis
        -- Modo recursivo si el filtro empieza con "**"
        local pattern = state.filter:match("^%*%*%s*(.+)$")
        if pattern and pattern ~= "" then
            all = list_recursive(pattern)
            vis = all
        else
            all = list_dir(state.cwd)
            vis = apply_filter(all)
        end
        state.entries = vis
        if list then list:set_items(vis) end
        if path_lbl then path_lbl:set_text(state.cwd) end
        update_status(vis, #all)
    end

    -- ── Navegacion ────────────────────────────────────────────────
    local function navigate_to(path, push_history)
        if path == state.cwd then return end
        state.cwd = path
        state.filter = ""
        if input then
            input:set_text("")
            input:set_focused(false)
        end
        if push_history then
            -- truncar el futuro del historial
            while #state.history > state.history_idx do
                table.remove(state.history)
            end
            state.history[#state.history + 1] = path
            state.history_idx = #state.history
        end
        refresh()
    end

    local function go_back()
        if state.history_idx <= 1 then return end
        state.history_idx = state.history_idx - 1
        navigate_to(state.history[state.history_idx], false)
    end

    local function go_forward()
        if state.history_idx >= #state.history then return end
        state.history_idx = state.history_idx + 1
        navigate_to(state.history[state.history_idx], false)
    end

    local function go_up()
        navigate_to(parent_path(state.cwd), true)
    end

    local function go_home()
        navigate_to(os.getenv("HOME"), true)
    end

    local function open_entry(entry)
        if not entry then return end
        if entry.is_dir then
            navigate_to(entry.path, true)
        else
            os.execute("(xdg-open '" .. entry.path ..
                "') >/dev/null 2>&1 &")
        end
    end

    -- ── Listado (ScrollView) ──────────────────────────────────────
    list = W.ScrollView.new {
        row_height = ROW_H,
        bg_color = nil,
        min_width = 600,
        min_height = ROW_H * 14,
        -- El Window tambien dispara opts.on_click en el ButtonRelease
        -- (con el propio ScrollView como primer argumento). Hay que
        -- filtrar: solo aceptar el item real de la fila.
        on_click = function(item, idx)
            if item and type(item) == "table"
               and item.path and item.name then
                open_entry(item)
            end
        end,
    }

    -- Override del wheel: media fila por tick (pixel perfect-ish).
    list.on_wheel = function(self, direction)
        local delta = (direction == 4) and -13 or 13
        self:set_offset(self:get_offset() + delta)
    end

    list.draw_row = function(cr, item, idx, y, rh, width, hover)
        if not item then return end

        -- Siempre pintar el fondo de la fila. Si solo se pinta
        -- cuando hay hover, la fila que deja de estar bajo el mouse
        -- conserva el tinte del frame anterior en el image_surface
        -- (stale pixels, mismo bug que el TabsBar negro).
        local r, g, b
        if hover then
            r, g, b = G.hex_to_rgba(theme.bg_focus)
            cairo.set_rgba(cr, r, g, b, 0.55)
        else
            local bg = theme.bg_rgb
            r, g, b = bg[1], bg[2], bg[3]
            cairo.set_rgb(cr, r, g, b)
        end
        cairo.rectangle(cr, 0, y, width, rh)
        cairo.fill(cr)

        local col_name = 24
        local col_size = width - 380
        local col_date = width - 260
        local col_type = width - 90

        -- icono del tema activo (resvg -> cairo surface en cache)
        local mime = mime_for(item)
        local s = icon_theme.resolve(mime, 22)
        if not s and mime ~= "text-x-generic" then
            s = icon_theme.resolve("text-x-generic", 22)
        end
        if s then
            local ix = 2
            local iy = y + (rh - 18) / 2
            -- Los iconos de tema ya vienen con su color propio.
            -- Los dibujamos tal cual, sin tintar.
            cairo.draw_surface(cr, s, ix, iy, 18, 18)
        end

        local fg = theme.fg_rgb or { 0.9, 0.9, 0.9 }
        local muted = theme.muted_rgb or { 0.5, 0.5, 0.5 }
        local ty = y + (rh - 12) / 2

        -- Nombre
        cairo.save(cr)
        cairo.rectangle(cr, col_name, y, col_size - col_name - 8, rh)
        cairo.clip(cr)
        pango.draw_text(cr, col_name, ty, item.name,
            "DejaVu Sans 10", { r = fg[1], g = fg[2], b = fg[3] })
        cairo.restore(cr)

        -- Tamaño
        local size_str = item.is_dir and "—" or human_size(item.size)
        pango.draw_text(cr, col_size, ty, size_str,
            "DejaVu Sans 10",
            { r = muted[1], g = muted[2], b = muted[3] })

        -- Fecha
        pango.draw_text(cr, col_date, ty, human_date(item.mtime),
            "DejaVu Sans 10",
            { r = muted[1], g = muted[2], b = muted[3] })

        -- Tipo
        pango.draw_text(cr, col_type, ty, type_label(item),
            "DejaVu Sans 10",
            { r = muted[1], g = muted[2], b = muted[3] })

        -- Separador
        cairo.set_rgba(cr, muted[1], muted[2], muted[3], 0.15)
        cairo.rectangle(cr, 0, y + rh - 1, width, 1)
        cairo.fill(cr)
    end

    local slider = W.ScrollBar.new {
        orientation = "vertical",
        width = 12, thickness = 3, handle_r = 4,
        step = 30,
        color_handle = theme.accent,
        color_track = theme.separator,
    }
    W.ScrollLink.link(list, slider)

    local list_area = W.Group.new {
        orientation = "horizontal",
        spacing = 0,
        children = {
            { widget = list,   weight = 1 },
            { widget = slider, weight = 0 },
        },
    }

    -- ── Barra superior de navegacion ──────────────────────────────
    local btn_back    = NavButton.new(theme, "back",
        function() go_back() end)
    local btn_fwd     = NavButton.new(theme, "forward",
        function() go_forward() end)
    local btn_up      = NavButton.new(theme, "up",
        function() go_up() end)
    local btn_home    = NavButton.new(theme, "home",
        function() go_home() end)

    path_lbl = W.Text.new {
        text = state.cwd,
        font = "DejaVu Sans 10",
        align = "left", valign = "center",
        r = theme.fg_rgb[1],
        g = theme.fg_rgb[2],
        b = theme.fg_rgb[3],
    }

    local nav_bar = W.Group.new {
        orientation = "horizontal",
        spacing = 4,
        padding = 6,
        children = {
            { widget = btn_back, weight = 0 },
            { widget = btn_fwd,  weight = 0 },
            { widget = btn_up,   weight = 0 },
            { widget = btn_home, weight = 0 },
            { widget = W.Text.new { text = "" }, weight = 0,
              min_width = 8 },
            { widget = path_lbl, weight = 1 },
        },
    }

    -- ── Barra inferior de status ──────────────────────────────────
    status_lbl = W.Text.new {
        text = "0 elementos",
        font = "DejaVu Sans 9",
        align = "left", valign = "center",
        r = theme.muted_rgb[1],
        g = theme.muted_rgb[2],
        b = theme.muted_rgb[3],
    }

    input = W.TextInput.new {
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
        on_change = function(text)
            state.filter = text or ""
            refresh()
        end,
        on_cancel = function()
            input:set_text("")
            input:set_focused(false)
            state.filter = ""
            refresh()
        end,
    }

    local input_hint = W.Text.new {
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
            { widget = status_lbl, weight = 0 },
            { widget = input,      weight = 1 },
            { widget = input_hint, weight = 0 },
        },
    }

    local header = ListHeader.new(theme)

    -- ── Layout raiz ───────────────────────────────────────────────
    local layout = W.Group.new {
        orientation = "vertical",
        spacing = 0,
        padding = 0,
        children = {
            { widget = nav_bar,   weight = 0 },
            { widget = Divider.new(theme), weight = 0 },
            { widget = header,    weight = 0 },
            { widget = Divider.new(theme), weight = 0 },
            { widget = list_area, weight = 1 },
            { widget = Divider.new(theme), weight = 0 },
            { widget = status_bar, weight = 0 },
        },
    }

    -- ── Teclado ───────────────────────────────────────────────────
    local function on_key(key)
        if not key.pressed then return false end

        -- Ctrl+H toggle ocultos. Comparar por key.name porque con
        -- Ctrl pulsado key.text suele venir vacio.
        if key.name == "h" and key.mods.ctrl then
            state.show_hidden = not state.show_hidden
            refresh()
            return true
        end

        -- "/" enfoca el filtro
        if key.text == "/" and not input.focused then
            input:set_focused(true)
            return true
        end

        if key.name == "BackSpace" then
            go_up()
            return true
        end

        if key.name == "Return" then
            return true  -- el ScrollView maneja Enter con on_click
        end

        if key.name == "Escape" then
            if input.focused then
                input:set_text("")
                input:set_focused(false)
                state.filter = ""
                refresh()
                return true
            end
            return false  -- deja que la ventana cierre
        end

        return false
    end

    -- ── start ─────────────────────────────────────────────────────
    local function start()
        if state.cwd == nil then
            state.cwd = os.getenv("HOME")
        end
        state.history = { state.cwd }
        state.history_idx = 1
        refresh()
    end

    return {
        widget = layout,
        start = start,
        stop = function() end,
        on_key = on_key,
    }
end

return M
