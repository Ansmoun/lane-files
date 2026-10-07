-- image_preview: thumbnails asíncronos.
--
-- Muy simple:
--   - exists(path)   -> bool, el PNG ya está en disco.
--   - request(path)  -> lanza ffmpeg en background (no bloquea).
--   - load(path)     -> devuelve surface si el PNG existe, nil
--                       si todavía no.
--
-- El consumidor llama request() cuando un item se hace visible y
-- load() en cada draw. Cuando load() devuelve la surface, el
-- thumb está listo.

local cairo       = require("lib.cairo")
local log         = require("lib.log")

local M = {}

local THUMB_SIZE = 128
local CACHE_DIR = (os.getenv("HOME") or "/tmp") ..
    "/.cache/lane/thumbs"

local _surface_cache = {}
local _pending = {}  -- set de paths con ffmpeg en vuelo

local IMAGE_EXTS = {
    png = true, jpg = true, jpeg = true, gif = true,
    webp = true, bmp = true, tiff = true, ico = true,
}

local function ext_of(path)
    local e = path:match("%.([^.]+)$")
    return e and e:lower() or ""
end

function M.is_image(path)
    if not path then return false end
    return IMAGE_EXTS[ext_of(path)] == true
end

local function shq(s)
    return "'" .. tostring(s):gsub("'", "'\\''") .. "'"
end

local function hash_path(path)
    local h = 0x811c9dc5
    for i = 1, #path do
        h = h ~ path:byte(i)
        h = (h * 0x01000193) % 0x100000000
    end
    return string.format("%08x", h)
end

function M.thumb_path(path)
    return CACHE_DIR .. "/" .. hash_path(path) .. "_" ..
        THUMB_SIZE .. ".png"
end

local function file_exists(p)
    local f = io.open(p, "r")
    if f then f:close() return true end
    return false
end

-- ¿El thumbnail ya está en disco?
function M.exists(path)
    if not path or not M.is_image(path) then return false end
    return file_exists(M.thumb_path(path))
end

-- Lanza ffmpeg en background. No bloquea. Idempotente.
function M.request(path)
    if not path or not M.is_image(path) then return end
    if M.exists(path) then return end
    if _pending[path] then return end

    os.execute("mkdir -p " .. shq(CACHE_DIR))
    local dst = M.thumb_path(path)
    local tmp = dst .. ".tmp.png"
    local vf = string.format(
        "scale=%d:%d:flags=fast_bilinear:" ..
        "force_original_aspect_ratio=decrease",
        THUMB_SIZE, THUMB_SIZE)
    -- setsid -f: crea una nueva sesión y fork sin esperar. La
    -- app no bloquea. ffmpeg escribe a tmp y renombra al terminar
    -- (mv es atómico en el mismo directorio).
    local cmd = string.format(
        "setsid -f sh -c " ..
        "%s" ..
        " >/dev/null 2>&1",
        shq(string.format(
            "ffmpeg -nostdin -v error -i %s -vf %s -frames:v 1 -y %s " ..
            "&& mv %s %s",
            shq(path), shq(vf), shq(tmp), shq(tmp), shq(dst))))
    os.execute(cmd)
    _pending[path] = true
end

-- Carga el thumbnail si ya está en disco. Devuelve nil si no.
function M.load(path)
    if not path or not M.is_image(path) then return nil end
    local cached = _surface_cache[path]
    if cached ~= nil then
        return cached or nil
    end
    local dst = M.thumb_path(path)
    if not file_exists(dst) then
        -- Todavía no listo. Dejar el pending como estaba.
        return nil
    end
    -- Listo: cargar y limpiar el pending.
    _pending[path] = nil
    local surf = cairo.load_png_cached(dst)
    if not surf then
        _surface_cache[path] = false
        return nil
    end
    _surface_cache[path] = surf
    return surf
end

-- ¿Hay algún job en vuelo? Para que el consumidor decida si
-- seguir polleando.
function M.has_pending()
    for _ in pairs(_pending) do return true end
    return false
end

-- Lista de paths pendientes (para debug).
function M.pending_paths()
    local out = {}
    for p in pairs(_pending) do out[#out + 1] = p end
    return out
end

function M.clear_cache()
    _surface_cache = {}
end

return M
