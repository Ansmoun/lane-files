-- icons: mapeo extensión → nombre de icono freedesktop, y
-- formateadores de tamaño y fecha.

local M = {}

-- Mapeo extensión → nombre de mimetype del tema de iconos activo.
-- Los nombres siguen la especificación freedesktop (text-x-generic,
-- image-x-generic, etc.). Los temas Vimix/Papirus/Adwaita los
-- implementan. Si una extensión no está, cae a un genérico.
local MIME_BY_EXT = {
    -- texto plano
    txt = "text-x-generic", md = "text-x-generic",
    log = "text-x-generic", conf = "text-x-generic",
    cfg = "text-x-generic", ini = "text-x-generic",
    toml = "text-x-generic", yml = "text-x-generic",
    yaml = "text-x-generic",
    -- código fuente
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
    -- imágenes
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
    -- binarios
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

-- Devuelve el nombre de icono freedesktop para una entrada.
function M.mime_for(entry)
    if entry.is_dir then return "folder" end
    local ext = entry.name:match("%.([^.]+)$")
    if ext then
        ext = ext:lower()
        return MIME_BY_EXT[ext] or "text-x-generic"
    end
    return "text-x-generic"
end

-- Etiqueta corta de tipo para la columna "Tipo".
function M.type_label(entry)
    if entry.is_dir then return "carpeta" end
    local ext = entry.name:match("%.([^.]+)$")
    if not ext then return "archivo" end
    return ext:lower()
end

-- Tamaño legible: "512 B", "1.5 K", "2.3 M", "1.1 G".
function M.human_size(n)
    if not n or n == 0 then return "—" end
    if n < 1024 then return n .. " B" end
    if n < 1024 * 1024 then return string.format("%.1f K", n / 1024) end
    if n < 1024 * 1024 * 1024 then
        return string.format("%.1f M", n / (1024 * 1024))
    end
    return string.format("%.1f G", n / (1024 * 1024 * 1024))
end

-- Fecha legible: "2026-10-06 14:32".
function M.human_date(mtime)
    if not mtime or mtime == 0 then return "—" end
    return os.date("%Y-%m-%d %H:%M", mtime)
end

return M
