-- icons: resolución de iconos por mimetype.
--
-- Estrategia:
--   1. Detectar el mimetype real del archivo. Con extensión:
--      consulta única por extensión (cache). Sin extensión:
--      consulta única por path (cache).
--   2. Generar variantes del nombre de icono (con y sin x-,
--      con y sin el prefijo de tipo) y elegir el primero que
--      exista en el tema.
--   3. Fallback a la categoría (text-x-generic, image-x-generic,
--      etc.) si ninguna variante específica existe.
--
-- Todos los pasos están cacheados. Después de la primera vuelta
-- por un directorio, el renderizado es O(1) por fila.

local icon_theme = require("lib.icon_theme")

local M = {}

-- Caches persistentes durante la vida del proceso.
local _mime_cache = {}   -- extension -> mime string
local _path_cache = {}   -- path (sin extension) -> mime string
local _name_cache = {}   -- mime -> icon name | false
local _surface_cache = {} -- "mime:size" -> surface | false

-- Aliases puntuales para mimetypes cuyo nombre real difiere del
-- que sigue la convención freedesktop. Se consultan antes que las
-- variantes genéricas.
local ALIASES = {
    ["text/x-lua"]          = { "text-x-script" },
    ["text/x-python"]       = { "text-x-python" },
    ["text/x-java"]         = { "application-java" },
    ["text/x-markdown"]     = { "text-markdown" },
    ["text/markdown"]       = { "text-markdown" },
    ["text/x-shellscript"]  = { "text-x-script" },
    ["application/x-shellscript"] = { "text-x-script" },
    ["application/x-executable"]  = { "application-x-executable" },
    ["application/x-sharedlib"]   = { "application-x-sharedlib" },
    ["application/x-object"]      = { "application-x-object" },
    ["application/octet-stream"]  = { "application-x-generic" },
    ["inode/directory"]           = { "folder" },
}

-- Genera la lista de candidatos en orden de prioridad.
local function generate_candidates(mime)
    local out = {}
    local seen = {}
    local function add(name)
        if name and name ~= "" and not seen[name] then
            seen[name] = true
            out[#out + 1] = name
        end
    end

    -- Nombre directo por convención primero. Vimix y otros temas
    -- tienen text-x-lua, text-x-python, etc. Si probaramos los
    -- aliases antes, taparíamos estos iconos específicos.
    local base = mime:gsub("[/+]", "-"):gsub("%.", "-")
    add(base)

    -- Sin el x- interior: text-x-lua -> text-lua
    add(base:gsub("%-x%-", "-"))

    -- Con x- añadido: text-lua -> text-x-lua
    local type_prefix, rest = base:match("^([^-]+)%-(.+)$")
    if type_prefix and rest then
        add(type_prefix .. "-x-" .. rest)
    end

    -- Aliases como fallback si el nombre directo no existe
    local aliases = ALIASES[mime]
    if aliases then
        for _, a in ipairs(aliases) do add(a) end
    end

    -- Fallback por categoría
    local cat = base:match("^([^-]+)")
    if cat == "image" then
        add("image-x-generic")
    elseif cat == "audio" then
        add("audio-x-generic")
    elseif cat == "video" then
        add("video-x-generic")
    elseif cat == "text" then
        add("text-x-generic")
    elseif cat == "inode" then
        add("folder")
    else
        add("application-x-generic")
        add("application-x-executable")
    end

    return out
end

-- Devuelve el nombre del icono que existe en el tema para el mime
-- dado, o nil si ninguno existe.
function M.icon_name(mime)
    if _name_cache[mime] ~= nil then
        return _name_cache[mime] or nil
    end
    for _, cand in ipairs(generate_candidates(mime)) do
        if icon_theme.find_path(cand, 48) then
            _name_cache[mime] = cand
            return cand
        end
    end
    _name_cache[mime] = false
    return nil
end

-- Consulta el mimetype real de un archivo. Con extensión se
-- consulta una vez y se cachea por extensión. Sin extensión se
-- consulta y se cachea por path.
local function query_mime(path)
    -- gio info como fuente principal. file --mime-type no consulta
    -- las reglas del sistema y devuelve text/plain para todo lo
    -- que sea texto, ignorando .lua, .md, shebangs, etc.
    local safe = path:gsub("'", "'\\''")
    local cmd = io.popen("gio info -a standard::content-type '" ..
        safe .. "' 2>/dev/null | " ..
        "awk -F': ' '/content-type/ {print $2; exit}'")
    if cmd then
        local mime = cmd:read("*l")
        cmd:close()
        if mime and mime ~= "" then
            return mime:gsub("%s+$", "")
        end
    end
    -- Fallback a file si gio no esta disponible
    local cmd2 = io.popen("file --mime-type -b '" .. safe ..
        "' 2>/dev/null")
    if cmd2 then
        local mime2 = cmd2:read("*l")
        cmd2:close()
        if mime2 and mime2 ~= "" then
            return mime2:gsub("%s+$", "")
        end
    end
    return "application/octet-stream"
end

function M.mime_of(entry)
    if entry.is_dir then return "inode/directory" end

    local ext = entry.name:match("%.([^.]+)$")
    if ext then
        ext = ext:lower()
        if _mime_cache[ext] then return _mime_cache[ext] end
        local mime = query_mime(entry.path)
        _mime_cache[ext] = mime
        return mime
    end

    if _path_cache[entry.path] then
        return _path_cache[entry.path]
    end
    local mime = query_mime(entry.path)
    _path_cache[entry.path] = mime
    return mime
end

-- Devuelve la surface de Cairo para el icono de la entrada.
-- Itera los candidatos hasta encontrar uno que resvg pueda
-- cargar. Algunos temas (Vimix, por ejemplo) incluyen SVGs que
-- resvg no sabe parsear (folder-videos.svg, inode-directory.svg).
-- Buscar solo por existencia de archivo no basta: hay que
-- confirmar que la carga funciona.
--
-- Cachea por "mime:size". Después del primer intento por tipo,
-- el renderizado es O(1) sin tocar el disco.
function M.icon_for(entry, size)
    local mime = M.mime_of(entry)
    local key = mime .. ":" .. size

    if _surface_cache[key] ~= nil then
        return _surface_cache[key] or nil
    end

    -- Camino rápido: si ya sabemos el nombre que funciona para
    -- este mime, probarlo primero.
    local known = _name_cache[mime]
    if known and known ~= false then
        local s = icon_theme.resolve(known, size)
        if s then
            _surface_cache[key] = s
            return s
        end
    end

    -- Iterar candidatos hasta que uno cargue
    for _, cand in ipairs(generate_candidates(mime)) do
        local s = icon_theme.resolve(cand, size)
        if s then
            _name_cache[mime] = cand
            _surface_cache[key] = s
            return s
        end
    end

    -- Ninguno cargó. Fallback duro al genérico.
    local fallback = entry.is_dir and "folder" or "text-x-generic"
    if fallback ~= known then
        local s = icon_theme.resolve(fallback, size)
        if s then
            _name_cache[mime] = fallback
            _surface_cache[key] = s
            return s
        end
    end

    _name_cache[mime] = false
    _surface_cache[key] = false
    return nil
end

-- Compat: devuelve el nombre del icono (no la surface).
function M.mime_for(entry)
    local mime = M.mime_of(entry)
    return M.icon_name(mime)
        or (entry.is_dir and "folder" or "text-x-generic")
end

-- ── Formateadores ────────────────────────────────────────────
function M.type_label(entry)
    if entry.is_dir then return "carpeta" end
    local ext = entry.name:match("%.([^.]+)$")
    if not ext then return "archivo" end
    return ext:lower()
end

function M.human_size(n)
    if not n or n == 0 then return "—" end
    if n < 1024 then return n .. " B" end
    if n < 1024 * 1024 then return string.format("%.1f K", n / 1024) end
    if n < 1024 * 1024 * 1024 then
        return string.format("%.1f M", n / (1024 * 1024))
    end
    return string.format("%.1f G", n / (1024 * 1024 * 1024))
end

function M.human_date(mtime)
    if not mtime or mtime == 0 then return "—" end
    return os.date("%Y-%m-%d %H:%M", mtime)
end

return M
