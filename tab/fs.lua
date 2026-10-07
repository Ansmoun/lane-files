-- fs: operaciones de sistema de archivos del gestor.
-- Listar, navegar rutas, abrir con xdg-open.
-- Las operaciones destructivas (copy, move, delete, rename) viven
-- en módulos aparte cuando se implementen.

local M = {}

-- Une base y nombre respetando la raíz.
function M.join(base, name)
    if base == "/" then return "/" .. name end
    return base .. "/" .. name
end

-- Directorio padre. "/" es su propio padre.
function M.parent(path)
    if not path or path == "/" then return "/" end
    local parent = path:match("^(.+)/[^/]+$")
    if not parent or parent == "" then return "/" end
    return parent
end

-- Nombre base de una ruta.
function M.basename(path)
    return path:match("[^/]+$") or path
end

-- Lista las entradas de un directorio usando ls -la.
-- --time-style=+%s hace que la fecha sea un unix timestamp.
-- Devuelve array de tablas con name, is_dir, is_hidden, size,
-- mtime y path. Ordena: directorios primero, alfabético después.
function M.list_dir(path)
    local entries = {}
    local cmd = string.format(
        "ls -la --time-style=+%%s '%s' 2>/dev/null",
        path:gsub("'", "'\\''"))
    local p = io.popen(cmd)
    if not p then return entries end
    local first = true
    for line in p:lines() do
        if first then
            first = false
        else
            local perms, _, _, _, size, mtime, name =
                line:match("^(%S+)%s+(%d+)%s+(%S+)%s+(%S+)%s+(%d+)%s+(%d+)%s+(.+)$")
            if perms and name then
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
                        path      = M.join(path, name),
                    }
                end
            end
        end
    end
    p:close()
    return entries
end

-- Aplica el criterio de ordenamiento a una lista de entradas.
-- Los directorios siempre van primero, después se aplica el
-- criterio solicitado.
--
-- criterio: "name" | "size" | "mtime" | "type"
-- desc: true para descendente
function M.sort(entries, criterio, desc)
    criterio = criterio or "name"

    -- Extrae la clave de comparación para una entrada.
    local function key(e)
        if criterio == "size"  then return e.size  end
        if criterio == "mtime" then return e.mtime end
        if criterio == "type"  then
            return (e.name:match("%.([^.]+)$") or ""):lower()
        end
        return e.name:lower()
    end

    -- Orden estricto débil. table.sort lo requiere:
    --   - cmp(a, a) siempre false
    --   - antisimetría
    --   - transitividad
    -- Un comparador mal formado lanza "invalid order function".
    local function cmp(a, b)
        -- Carpetas primero, siempre, sin importar el criterio ni
        -- la dirección.
        if a.is_dir ~= b.is_dir then return a.is_dir end

        local ka, kb = key(a), key(b)
        if ka ~= kb then
            if desc then return ka > kb end
            return ka < kb
        end
        -- Desempate por nombre, siempre ascendente.
        return a.name:lower() < b.name:lower()
    end

    table.sort(entries, cmp)
    return entries
end

-- Búsqueda recursiva con fd. Solo se activa cuando el filtro
-- empieza con "**". Devuelve entradas con name = subruta relativa.
function M.list_recursive(root, pattern)
    local entries = {}
    local cmd = string.format(
        "nice -n 19 ionice -c 3 timeout 5 fd --max-depth 5 " ..
        "--max-results 500 --hidden --exclude .git " ..
        "--exclude node_modules --exclude .cache " ..
        "--ignore-case --type f --type d '%s' '%s' 2>/dev/null",
        pattern:gsub("'", "'\\''"), root:gsub("'", "'\\''"))
    local p = io.popen(cmd)
    if not p then return entries end
    for line in p:lines() do
        local abs = line
        if abs:sub(1, 1) ~= "/" then
            abs = root .. "/" .. abs
        end
        local rel = abs:sub(#root + 2)
        if rel ~= "" then
            local name = rel:match("[^/]+$") or rel
            local is_dir = false
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
                    local s, m = out:match("^(%d+) (%d+)$")
                    size = tonumber(s) or 0
                    mtime = tonumber(m) or 0
                end
            end
            entries[#entries + 1] = {
                name      = rel,
                is_dir    = is_dir,
                is_hidden = name:sub(1, 1) == ".",
                size      = size,
                mtime     = mtime,
                path      = abs,
            }
        end
    end
    p:close()
    return entries
end

-- Aplica el filtro de texto y visibilidad de ocultos.
function M.apply_filter(entries, filter, show_hidden)
    if filter == "" then
        if show_hidden then return entries end
        local out = {}
        for _, e in ipairs(entries) do
            if not e.is_hidden then out[#out + 1] = e end
        end
        return out
    end
    local f = filter:lower()
    local out = {}
    for _, e in ipairs(entries) do
        if (show_hidden or not e.is_hidden)
           and e.name:lower():find(f, 1, true) then
            out[#out + 1] = e
        end
    end
    return out
end

-- ¿Existe y es directorio? Una llamada a shell por vez, solo se
-- usa al restaurar sesion. Para validacion en caliente, preferir
-- stat via lib.fs de LaneTK.
function M.is_dir(path)
    if not path or path == "" then return false end
    local p = io.popen("test -d '" .. path:gsub("'", "'\\''") ..
        "' && echo D 2>/dev/null")
    if not p then return false end
    local ok = p:read("*l") == "D"
    p:close()
    return ok
end

-- Abre un archivo con xdg-open en segundo plano.
function M.open(entry)
    if not entry then return end
    os.execute("(xdg-open '" .. entry.path:gsub("'", "'\\''") ..
        "') >/dev/null 2>&1 &")
end

return M
