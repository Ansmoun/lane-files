-- properties: lee información detallada de un archivo o carpeta
-- usando stat (vía /usr/bin/stat) y devuelve filas { label, value }.

local M = {}

local function shq(s)
    return "'" .. tostring(s):gsub("'", "'\\''") .. "'"
end

local function popen_read(cmd)
    local p = io.popen(cmd .. " 2>/dev/null")
    if not p then return nil end
    local out = p:read("*a")
    p:close()
    if not out or out == "" then return nil end
    return out:gsub("%s+$", "")
end

-- Formatea un tamaño en bytes.
local function human_size(n)
    n = tonumber(n) or 0
    if n < 1024 then return n .. " B (" .. n .. " bytes)" end
    if n < 1024 * 1024 then return string.format("%.1f K", n / 1024) end
    if n < 1024 * 1024 * 1024 then
        return string.format("%.1f M", n / (1024 * 1024))
    end
    return string.format("%.2f G", n / (1024 * 1024 * 1024))
end

local function human_date(ts)
    ts = tonumber(ts) or 0
    if ts == 0 then return "—" end
    return os.date("%Y-%m-%d %H:%M:%S", ts)
end

-- Tabla de tipo de archivo (stat %F) a etiqueta legible en
-- español.
local TYPE_LABEL = {
    -- Inglés (LC_ALL=C)
    ["regular file"]              = "Archivo",
    ["regular empty file"]        = "Archivo vacío",
    ["directory"]                 = "Carpeta",
    ["symbolic link"]             = "Enlace simbólico",
    ["character special file"]    = "Dispositivo de caracteres",
    ["block special file"]        = "Dispositivo de bloques",
    ["fifo"]                      = "Tubería FIFO",
    ["socket"]                    = "Socket",
    ["unknown"]                   = "Desconocido",
    -- Español (fallback si no se pudo forzar LC_ALL)
    ["Fichero regular"]           = "Archivo",
    ["Fichero regular vacío"]     = "Archivo vacío",
    ["directorio"]                = "Carpeta",
    ["directorio vacío"]          = "Carpeta",
    ["enlace simbólico"]          = "Enlace simbólico",
    ["dispositivo de caracteres"] = "Dispositivo de caracteres",
    ["dispositivo de bloques"]    = "Dispositivo de bloques",
    ["tubería FIFO"]              = "Tubería FIFO",
    ["socket"]                    = "Socket",
    ["desconocido"]               = "Desconocido",
}

-- Tabla de extensión a categoría. Reusa la lógica de icons.lua
-- pero con etiquetas más humanas.
local CATEGORY_BY_EXT = {
    txt="Texto plano", md="Markdown", log="Log", conf="Configuración",
    cfg="Configuración", ini="Configuración", toml="Configuración",
    yml="YAML", yaml="YAML", json="JSON", xml="XML",
    lua="Script Lua", sh="Script Shell", py="Script Python",
    c="Código C", h="Cabecera C", rs="Código Rust",
    js="JavaScript", ts="TypeScript", go="Código Go",
    html="HTML", htm="HTML", css="CSS",
    png="Imagen PNG", jpg="Imagen JPEG", jpeg="Imagen JPEG",
    gif="Imagen GIF", bmp="Imagen BMP", svg="Imagen SVG",
    webp="Imagen WebP", ico="Icono", tiff="Imagen TIFF",
    mp4="Vídeo MP4", mkv="Vídeo Matroska", webm="Vídeo WebM",
    avi="Vídeo AVI", mov="Vídeo QuickTime", flv="Vídeo Flash",
    mpg="Vídeo MPEG",
    mp3="Audio MP3", ogg="Audio Ogg", wav="Audio WAV",
    flac="Audio FLAC", m4a="Audio M4A", opus="Audio Opus",
    zip="Archivo ZIP", tar="Archivo TAR", gz="Archivo GZip",
    bz2="Archivo BZip2", xz="Archivo XZ", zst="Archivo Zstd",
    rar="Archivo RAR", ["7z"]="Archivo 7z",
    pdf="Documento PDF",
    doc="Documento Word", docx="Documento Word",
    xls="Hoja Excel", xlsx="Hoja Excel",
    ppt="Presentación", pptx="Presentación",
    odt="Documento ODF", ods="Hoja ODF",
    so="Biblioteca compartida", o="Objeto", a="Biblioteca estática",
    bin="Ejecutable", deb="Paquete Debian", rpm="Paquete RPM",
    iso="Imagen ISO", img="Imagen de disco",
}

-- Devuelve una etiqueta de tipo legible a partir del tipo stat y
-- el nombre del archivo.
local function describe_type(stat_type, name)
    local base = TYPE_LABEL[stat_type] or stat_type
    local is_regular =
        stat_type == "regular file"
        or stat_type == "regular empty file"
        or stat_type == "Fichero regular"
        or stat_type == "Fichero regular vacío"
    if is_regular then
        local ext = name:match("%.([^.]+)$")
        if ext then
            ext = ext:lower()
            local cat = CATEGORY_BY_EXT[ext]
            if cat then
                return cat .. " (. " .. ext .. ")"
            end
            return "Archivo ." .. ext
        end
    end
    return base
end

-- Tamaño de directorio con du. Puede tardar si tiene muchos
-- archivos. Se limita a un timeout razonable.
local function dir_size(path)
    local out = popen_read("timeout 3 du -sb " .. shq(path) ..
        " | awk '{print $1}'")
    return out
end

-- Cuenta archivos y subdirectorios en un directorio (nivel 1).
local function dir_counts(path)
    local dirs = popen_read(
        "find " .. shq(path) .. " -mindepth 1 -maxdepth 1 -type d " ..
        "2>/dev/null | wc -l")
    local files = popen_read(
        "find " .. shq(path) .. " -mindepth 1 -maxdepth 1 -type f " ..
        "2>/dev/null | wc -l")
    return tonumber(files) or 0, tonumber(dirs) or 0
end

-- Devuelve array de { label = "...", value = "..." } con la info
-- del path.
function M.rows(path)
    local rows = {}

    -- Nombre y ruta
    local name = path:match("[^/]+$") or path
    rows[#rows + 1] = { label = "Nombre",  value = name }
    rows[#rows + 1] = { label = "Ruta",    value = path }

    -- stat con formato: tipo|tamaño|bloques|inodo|enlaces|uid|gid|
    --                   perms|mtime|atime|ctime
    -- LC_ALL=C fuerza las etiquetas de stat en inglés. Sin esto,
    -- en locale español devuelve "Fichero regular" en lugar de
    -- "regular file" y la tabla de traducción no matchea.
    local fmt = "%F|%s|%b|%i|%h|%u|%g|%A|%Y|%X|%Z"
    local out = popen_read("LC_ALL=C stat -c " .. shq(fmt) .. " " ..
        shq(path))
    if not out then
        rows[#rows + 1] = { label = "Estado", value = "no accesible" }
        return rows
    end

    local tipo, size, blocks, inode, links, uid, gid,
          perms, mtime, atime, ctime =
        out:match("^([^|]+)|([^|]+)|([^|]+)|([^|]+)|([^|]+)|" ..
                  "([^|]+)|([^|]+)|([^|]+)|([^|]+)|([^|]+)|([^|]+)$")

    if tipo then
        rows[#rows + 1] = {
            label = "Tipo",
            value = describe_type(tipo, name),
        }
    end

    if tipo == "directory" then
        local nfiles, ndirs = dir_counts(path)
        rows[#rows + 1] = { label = "Contenido",
            value = string.format("%d archivos, %d carpetas",
                nfiles, ndirs) }
        local sz = dir_size(path)
        if sz then
            rows[#rows + 1] = { label = "Tamaño total",
                value = human_size(sz) }
        end
    else
        if size then
            rows[#rows + 1] = { label = "Tamaño",
                value = human_size(size) }
        end
    end

    if links then
        rows[#rows + 1] = { label = "Enlaces duros", value = links }
    end
    if inode then
        rows[#rows + 1] = { label = "Inodo", value = inode }
    end
    if perms then
        rows[#rows + 1] = { label = "Permisos", value = perms }
    end

    -- Dueño y grupo con nombre (getent passwd/group)
    if uid and gid then
        local uname = popen_read("getent passwd " .. shq(uid) ..
            " | cut -d: -f1") or uid
        local gname = popen_read("getent group " .. shq(gid) ..
            " | cut -d: -f1") or gid
        rows[#rows + 1] = { label = "Dueño",
            value = uname .. " (" .. uid .. ")" }
        rows[#rows + 1] = { label = "Grupo",
            value = gname .. " (" .. gid .. ")" }
    end

    if mtime then
        rows[#rows + 1] = { label = "Modificado",
            value = human_date(mtime) }
    end
    if atime then
        rows[#rows + 1] = { label = "Accedido",
            value = human_date(atime) }
    end
    if ctime then
        rows[#rows + 1] = { label = "Cambiado",
            value = human_date(ctime) }
    end

    return rows
end

return M
