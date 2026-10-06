-- ops: operaciones de sistema de archivos del gestor.
-- Todas las funciones devuelven (ok, err) donde ok es booleano
-- y err es un mensaje legible si ok == false.

local M = {}

-- Escapa comillas simples para usar en comandos shell.
local function shq(s)
    return "'" .. tostring(s):gsub("'", "'\\''") .. "'"
end

-- Comprueba si una ruta existe.
local function path_exists(p)
    local cmd = io.popen("test -e " .. shq(p) .. " && echo Y")
    if not cmd then return false end
    local out = cmd:read("*l")
    cmd:close()
    return out == "Y"
end

-- Comprueba si una ruta es directorio.
local function is_dir(p)
    local cmd = io.popen("test -d " .. shq(p) .. " && echo Y")
    if not cmd then return false end
    local out = cmd:read("*l")
    cmd:close()
    return out == "Y"
end

-- Nombre base de una ruta.
local function basename(p)
    return p:match("[^/]+$") or p
end

-- Une directorio y nombre respetando la raíz.
local function join(dir, name)
    if dir == "/" then return "/" .. name end
    return dir .. "/" .. name
end

-- Devuelve una ruta alternativa que no colisione: "archivo (1).ext",
-- "archivo (2).ext", etc. Si no colisiona, devuelve el original.
local function unique_dest(dir, name)
    local candidate = join(dir, name)
    if not path_exists(candidate) then return candidate end

    -- Separar nombre y extensión
    local base, ext = name:match("^(.*)(%.[^.]+)$")
    if not base then
        base = name
        ext  = ""
    end

    for i = 1, 100 do
        local alt = string.format("%s (%d)%s", base, i, ext)
        candidate = join(dir, alt)
        if not path_exists(candidate) then
            return candidate
        end
    end
    return nil
end

-- ── Copiar ───────────────────────────────────────────────────────
-- Copia uno o varios paths al directorio destino. Los nombres de
-- destino se ajustan para evitar colisiones.
-- Devuelve (copiados, errores) donde ambos son listas.
function M.copy(paths, dst_dir)
    if not dst_dir or dst_dir == "" then
        return {}, { "directorio destino vacío" }
    end
    if not is_dir(dst_dir) then
        return {}, { "destino no es un directorio: " .. dst_dir }
    end

    local copied, errors = {}, {}
    for _, src in ipairs(paths) do
        local name = basename(src)
        local dst  = unique_dest(dst_dir, name)
        if not dst then
            errors[#errors + 1] = "no se pudo encontrar un nombre libre para " .. name
        else
            local cmd = "cp -r " .. shq(src) .. " " .. shq(dst) ..
                " 2>/dev/null"
            local ok = os.execute(cmd)
            if ok == true or ok == 0 then
                copied[#copied + 1] = dst
            else
                errors[#errors + 1] = "falló copiar " .. name
            end
        end
    end
    return copied, errors
end

-- ── Mover ────────────────────────────────────────────────────────
function M.move(paths, dst_dir)
    if not dst_dir or dst_dir == "" then
        return {}, { "directorio destino vacío" }
    end
    if not is_dir(dst_dir) then
        return {}, { "destino no es un directorio: " .. dst_dir }
    end

    local moved, errors = {}, {}
    for _, src in ipairs(paths) do
        local name = basename(src)
        local dst  = unique_dest(dst_dir, name)
        if not dst then
            errors[#errors + 1] = "no se pudo encontrar un nombre libre para " .. name
        else
            local cmd = "mv " .. shq(src) .. " " .. shq(dst) ..
                " 2>/dev/null"
            local ok = os.execute(cmd)
            if ok == true or ok == 0 then
                moved[#moved + 1] = dst
            else
                errors[#errors + 1] = "falló mover " .. name
            end
        end
    end
    return moved, errors
end

-- ── Renombrar ────────────────────────────────────────────────────
-- Renombra dentro del mismo directorio. Verifica que el nombre no
-- contenga "/" y que no colisione con otro archivo existente.
function M.rename(path, new_name)
    if not new_name or new_name == "" then
        return false, "nombre vacío"
    end
    if new_name:find("/") then
        return false, "el nombre no puede contener /"
    end

    local parent = path:match("^(.+)/[^/]+$") or "/"
    local dst = join(parent, new_name)
    if dst == path then
        return false, "mismo nombre"
    end
    if path_exists(dst) then
        return false, "ya existe un archivo con ese nombre"
    end

    local ok = os.execute("mv " .. shq(path) .. " " .. shq(dst) ..
        " 2>/dev/null")
    if ok == true or ok == 0 then
        return true
    end
    return false, "mv falló"
end

-- ── Crear directorio ─────────────────────────────────────────────
function M.mkdir(parent, name)
    if not name or name == "" then
        return false, "nombre vacío"
    end
    if name:find("/") then
        return false, "el nombre no puede contener /"
    end

    local dst = join(parent, name)
    if path_exists(dst) then
        return false, "ya existe"
    end

    local ok = os.execute("mkdir " .. shq(dst) .. " 2>/dev/null")
    if ok == true or ok == 0 then
        return true
    end
    return false, "mkdir falló"
end

-- ── Crear archivo vacío ──────────────────────────────────────────
function M.touch(parent, name)
    if not name or name == "" then
        return false, "nombre vacío"
    end
    if name:find("/") then
        return false, "el nombre no puede contener /"
    end

    local dst = join(parent, name)
    if path_exists(dst) then
        return false, "ya existe"
    end

    local ok = os.execute("touch " .. shq(dst) .. " 2>/dev/null")
    if ok == true or ok == 0 then
        return true
    end
    return false, "touch falló"
end

-- ── Enviar a papelera ────────────────────────────────────────────
-- Prefiere gio trash (GNOME, estándar en freedesktop). Cae a
-- trash-put de trash-cli. Si ninguno está, devuelve error para
-- que el consumidor decida qué hacer.
--
-- La búsqueda comprueba rutas absolutas primero. El PATH del
-- usuario no siempre incluye /usr/sbin, donde Void instala gio.
-- Sin este chequeo, command -v fallaba aunque el binario existiera.
local function find_cmd(name, paths)
    for _, p in ipairs(paths) do
        local f = io.open(p, "r")
        if f then
            f:close()
            return p
        end
    end
    -- Fallback: command -v (por si está en el PATH del sistema)
    local handle = io.popen("command -v " .. name .. " 2>/dev/null")
    if handle then
        local out = handle:read("*l")
        handle:close()
        if out and out ~= "" then return out end
    end
    return nil
end

local function trash_cmd()
    -- trash-put primero. Es más robusto: siempre copia el archivo
    -- en lugar de intentar reflink. gio trash intenta reflink
    -- cuando origen y destino están en el mismo dispositivo, y
    -- falla entre puntos de montaje distintos (por ejemplo /tmp
    -- es tmpfs y HOME está en disco).
    local tp = find_cmd("trash-put", {
        "/usr/bin/trash-put", "/usr/sbin/trash-put",
        "/bin/trash-put",     "/sbin/trash-put",
    })
    if tp then return tp end

    -- gio trash con --force: fuerza copia en lugar de reflink.
    -- Cubre sistemas sin trash-cli instalado.
    local gio = find_cmd("gio", {
        "/usr/bin/gio", "/usr/sbin/gio",
        "/bin/gio",     "/sbin/gio",
    })
    if gio then return gio .. " trash --force" end

    return nil
end

function M.trash(paths)
    local cmd_base = trash_cmd()
    if not cmd_base then
        return {}, { "no hay comando de papelera disponible " ..
                        "(instalar gio o trash-cli)" }
    end

    local trashed, errors = {}, {}
    for _, p in ipairs(paths) do
        local _, _, code = os.execute(cmd_base .. " " .. shq(p) ..
            " >/dev/null 2>&1")
        if code == 0 or code == true then
            trashed[#trashed + 1] = p
        else
            errors[#errors + 1] = "falló enviar a papelera " .. basename(p)
        end
    end
    return trashed, errors
end

-- ── Borrar permanente ────────────────────────────────────────────
function M.delete(paths)
    local deleted, errors = {}, {}
    for _, p in ipairs(paths) do
        local ok = os.execute("rm -rf " .. shq(p) .. " 2>/dev/null")
        if ok == true or ok == 0 then
            deleted[#deleted + 1] = p
        else
            errors[#errors + 1] = "falló borrar " .. basename(p)
        end
    end
    return deleted, errors
end

-- ── Helpers públicos ─────────────────────────────────────────────
M.path_exists = path_exists
M.is_dir      = is_dir
M.basename    = basename
M.join        = join

return M
