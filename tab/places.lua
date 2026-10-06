-- places: ubicaciones comunes del sistema y marcadores del usuario.
--
-- Lee dos fuentes:
--   1. ~/.config/user-dirs.dirs  (XDG user dirs: Documentos,
--      Descargas, Imágenes, etc.)
--   2. ~/.config/gtk-3.0/bookmarks  (marcadores del usuario,
--      formato estándar compartido con Nautilus, Thunar, etc.)
--
-- Si un directorio no existe o la variable no está definida, se
-- omite del listado. La papelera se añade siempre si existe el
-- directorio ~/.local/share/Trash.

local M = {}

local HOME = os.getenv("HOME") or "/"

-- Extrae las variables XDG_*_DIR de user-dirs.dirs.
-- El formato es: XDG_DOCUMENTS_DIR="$HOME/Documentos"
local function read_xdg_dirs()
    local path = HOME .. "/.config/user-dirs.dirs"
    local f = io.open(path, "r")
    if not f then return {} end
    local dirs = {}
    for line in f:lines() do
        local key, val = line:match('^(XDG_[A-Z_]+)="([^"]+)"')
        if key and val then
            -- Expandir $HOME
            val = val:gsub("^%$HOME", HOME)
            dirs[key] = val
        end
    end
    f:close()
    return dirs
end

-- Comprueba si una ruta existe y es directorio.
local function is_dir(path)
    if not path or path == "" then return false end
    local p = io.open(path, "r")
    if not p then return false end
    -- Leer no sirve para distinguir directorio. Usar test -d.
    p:close()
    local cmd = io.popen("test -d '" .. path:gsub("'", "'\\''") ..
        "' && echo Y")
    if not cmd then return false end
    local out = cmd:read("*l")
    cmd:close()
    return out == "Y"
end

-- Lista de lugares comunes, en orden de presentación.
-- Cada entrada: { label, path, icon }. Solo se incluye si el
-- directorio existe.
function M.common_places()
    local xdg = read_xdg_dirs()
    local candidates = {
        { label = "Inicio",      path = HOME,
          icon = "home" },
        { label = "Escritorio",  path = xdg.XDG_DESKTOP_DIR,
          icon = "user-desktop" },
        { label = "Documentos",  path = xdg.XDG_DOCUMENTS_DIR,
          icon = "folder-documents" },
        { label = "Descargas",   path = xdg.XDG_DOWNLOAD_DIR,
          icon = "folder-download" },
        { label = "Imágenes",    path = xdg.XDG_PICTURES_DIR,
          icon = "folder-pictures" },
        { label = "Música",      path = xdg.XDG_MUSIC_DIR,
          icon = "folder-music" },
        { label = "Vídeos",      path = xdg.XDG_VIDEOS_DIR,
          icon = "folder-videos" },
        { label = "Plantillas",  path = xdg.XDG_TEMPLATES_DIR,
          icon = "folder-templates" },
        { label = "Público",     path = xdg.XDG_PUBLICSHARE_DIR,
          icon = "folder-publicshare" },
    }
    local out = {}
    for _, c in ipairs(candidates) do
        if c.path and is_dir(c.path) then
            out[#out + 1] = c
        end
    end
    -- Papelera al final si existe el directorio.
    local trash = HOME .. "/.local/share/Trash"
    if is_dir(trash) then
        out[#out + 1] = {
            label = "Papelera",
            path  = trash,
            icon  = "user-trash",
        }
    end
    return out
end

-- Lee los marcadores de GTK. Formato:
--   file:///home/user/Proyectos Proyectos
--   file:///home/user/Descargas
-- El segundo campo es el label visible. Si falta, se usa el
-- nombre base del path.
function M.bookmarks()
    local path = HOME .. "/.config/gtk-3.0/bookmarks"
    local f = io.open(path, "r")
    if not f then return {} end
    local out = {}
    for line in f:lines() do
        -- Ignorar comentarios y líneas vacías
        if line ~= "" and line:sub(1, 1) ~= "#" then
            local uri, label = line:match("^(%S+)%s*(.*)$")
            if uri and uri:sub(1, 7) == "file://" then
                -- Quitar file:// y decodificar %XX
                local fs_path = uri:sub(8)
                fs_path = fs_path:gsub("%%(%x%x)", function(h)
                    return string.char(tonumber(h, 16))
                end)
                if fs_path ~= "" then
                    if not label or label == "" then
                        label = fs_path:match("[^/]+$") or fs_path
                    end
                    if is_dir(fs_path) then
                        out[#out + 1] = {
                            label = label,
                            path  = fs_path,
                            icon  = "folder",
                        }
                    end
                end
            end
        end
    end
    f:close()
    return out
end

return M
