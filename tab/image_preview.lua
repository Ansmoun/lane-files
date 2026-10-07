-- image_preview: shim sobre LaneTK/lib.thumbs para lane-files.
--
-- La logica de decodificacion y cache vive en LaneTK (estandar
-- freedesktop, ~/.cache/thumbnails/<bucket>/<md5(uri)>.png).
-- Este modulo solo adapta la API vieja (request/load) a la nueva
-- y expone is_image/thumb_path para compatibilidad con los
-- consumidores actuales (icons_view, preview_panel).
--
-- Contrato:
--   is_image(path)    extension esta en la lista de imagenes
--   thumb_path(path)  path canonico en el cache (sin tocar nada)
--   exists(path)      el PNG cacheado existe y es archivo regular
--   request(path)     genera si hace falta (SINCRONO, 40-70 ms,
--                     usar con moderacion desde un timer)
--   load(path)        si el cache existe, surface; nil si no.
--                     NO genera (para no bloquear el draw)
--   clear_cache()     libera surfaces en memoria (disco intacto)
--   has_pending()     siempre false (no hay jobs en vuelo)
--   pending_paths()   siempre {}

local cairo  = require("lib.cairo")
local fs     = require("lib.fs")
local gp     = require("lib.gdk_pixbuf")
local thumbs = require("lib.thumbs")
local log    = require("lib.log")

local M = {}

-- Bucket por defecto de lane-files. 128px es lo que usaba la
-- version anterior con ffmpeg.
local BUCKET = "normal"

local IMAGE_EXTS = {
    png = true, jpg = true, jpeg = true, gif = true,
    webp = true, bmp = true, tiff = true, ico = true,
    svg = true, svgz = true,
}

local _surface_cache = {}

local function ext_of(path)
    local e = path:match("%.([^.]+)$")
    return e and e:lower() or ""
end

function M.is_image(path)
    if not path then return false end
    return IMAGE_EXTS[ext_of(path)] == true
end

-- Path canonico en el cache. Solo calcula el hash, no mira disco.
function M.thumb_path(path)
    if not path then return nil end
    return thumbs.cache_path(path, BUCKET)
end

function M.exists(path)
    if not path or not M.is_image(path) then return false end
    local p = thumbs.cache_path(path, BUCKET)
    if not p then return false end
    return fs.is_file(p)
end

-- Genera el thumbnail si hace falta. SINCRONO. Pensado para
-- llamarse desde un timer que genera como maximo 1 por tick (ver
-- icons_view:_poll_thumbs). Llamarlo desde el draw congela la UI.
function M.request(path)
    if not path or not M.is_image(path) then return end
    thumbs.ensure(path, BUCKET)
end

-- Cache hit only. Si el PNG existe, lo carga; si no, nil. NO
-- genera. Este es el camino rapido que se llama desde el draw.
function M.load(path)
    if not path or not M.is_image(path) then return nil end
    local cached = _surface_cache[path]
    if cached ~= nil then
        return cached or nil
    end
    local cache_path = thumbs.cache_path(path, BUCKET)
    if not cache_path or not fs.is_file(cache_path) then
        return nil
    end
    local surf, err = gp.load(cache_path)
    if not surf then
        log.warn("image_preview", "cache ilegible: %s (%s)",
            cache_path, err or "?")
        _surface_cache[path] = false
        return nil
    end
    _surface_cache[path] = surf
    return surf
end

function M.has_pending()  return false end
function M.pending_paths() return {} end

-- Libera las surfaces en memoria. El cache en disco queda.
-- No destruimos los surfaces porque pueden estar referenciados
-- por consumidores (icons_view los cachea por path).
function M.clear_cache()
    _surface_cache = {}
end

return M
