-- trash: operaciones sobre la papelera freedesktop.
-- Lee el contenido real vía ~/.local/share/Trash/info/*.trashinfo
-- para saber de dónde vino cada archivo. Restaurar mueve el
-- archivo de vuelta a su ruta original. Vaciar elimina todo.

local M = {}

local HOME = os.getenv("HOME") or "/"
local TRASH_DIR = HOME .. "/.local/share/Trash"
local FILES_DIR = TRASH_DIR .. "/files"
local INFO_DIR  = TRASH_DIR .. "/info"

local function shq(s)
    return "'" .. tostring(s):gsub("'", "'\\''") .. "'"
end

local function exists(path)
    local f = io.open(path, "r")
    if f then f:close() return true end
    return false
end

-- Devuelve el tamaño de un archivo o directorio en bytes.
local function du_size(path)
    local p = io.popen("du -sb " .. shq(path) ..
        " 2>/dev/null | awk '{print $1}'")
    if not p then return 0 end
    local out = p:read("*l")
    p:close()
    return tonumber(out) or 0
end

-- Lee un archivo .trashinfo y devuelve la ruta original y la
-- fecha de borrado. Formato INI:
--   [Trash Info]
--   Path=/home/user/archivo.txt
--   DeletionDate=2026-10-06T15:30:45
local function parse_trashinfo(path)
    local f = io.open(path, "r")
    if not f then return nil end
    local data = {}
    for line in f:lines() do
        local k, v = line:match("^([%w]+)=(.+)$")
        if k and v then data[k] = v end
    end
    f:close()
    return data.Path, data.DeletionDate
end

-- Lista el contenido de la papelera. Devuelve array de tablas con
-- name, path (nombre en files/), orig_path, date, size, is_dir.
function M.list()
    local out = {}
    local p = io.popen("ls -1 " .. shq(INFO_DIR) ..
        "/*.trashinfo 2>/dev/null")
    if not p then return out end

    for line in p:lines() do
        local info_path = line
        local base = info_path:match("([^/]+)%.trashinfo$")
        if base then
            local orig_path, date = parse_trashinfo(info_path)
            if orig_path then
                local file_path = FILES_DIR .. "/" .. base
                local is_dir = false
                local st = io.popen("test -d " .. shq(file_path) ..
                    " && echo Y")
                if st then
                    if st:read("*l") == "Y" then is_dir = true end
                    st:close()
                end
                out[#out + 1] = {
                    name      = base,
                    path      = file_path,
                    orig_path = orig_path,
                    date      = date,
                    size      = du_size(file_path),
                    is_dir    = is_dir,
                }
            end
        end
    end
    p:close()

    -- Ordenar por fecha de borrado descendente (más reciente primero)
    table.sort(out, function(a, b)
        return (a.date or "") > (b.date or "")
    end)
    return out
end

-- Restaura un elemento de la papelera a su ruta original.
-- Devuelve true si tuvo éxito, false y un mensaje si no.
function M.restore(item)
    if not item or not item.path then return false, "item inválido" end
    if not exists(item.path) then
        return false, "el archivo ya no está en la papelera"
    end
    if not item.orig_path then
        return false, "no se pudo leer la ruta original"
    end

    -- Crear el directorio padre del destino si no existe
    local parent = item.orig_path:match("^(.+)/[^/]+$")
    if parent and parent ~= "" then
        os.execute("mkdir -p " .. shq(parent))
    end

    local _, _, code = os.execute(
        "mv " .. shq(item.path) .. " " .. shq(item.orig_path) ..
        " 2>/dev/null")
    if code ~= 0 and code ~= true then
        return false, "no se pudo mover el archivo"
    end

    -- Eliminar el .trashinfo asociado
    local info_path = INFO_DIR .. "/" .. item.name .. ".trashinfo"
    os.remove(info_path)
    return true
end

-- Vacía la papelera.
--
-- Recrea los directorios files/ e info/ desde cero con rm -rf
-- seguido de mkdir -p. Es más simple y robusto que find -delete:
-- rm -rf borra cualquier cosa (archivos, subdirectorios con
-- espacios, caracteres raros) sin depender del shell.
function M.empty()
    os.execute("rm -rf " .. shq(FILES_DIR) .. " " .. shq(INFO_DIR) ..
        " 2>/dev/null")
    os.execute("mkdir -p " .. shq(FILES_DIR) .. " " .. shq(INFO_DIR) ..
        " 2>/dev/null")
    return true
end

-- Cuenta cuántos elementos hay actualmente.
function M.count_now()
    local p = io.popen("ls -1 " .. shq(INFO_DIR) ..
        "/*.trashinfo 2>/dev/null | wc -l")
    if not p then return 0 end
    local n = tonumber(p:read("*l")) or 0
    p:close()
    return n
end

-- Cuenta cuántos elementos hay en la papelera.
function M.count()
    local p = io.popen("ls -1 " .. shq(INFO_DIR) ..
        "/*.trashinfo 2>/dev/null | wc -l")
    if not p then return 0 end
    local n = tonumber(p:read("*l")) or 0
    p:close()
    return n
end

return M
