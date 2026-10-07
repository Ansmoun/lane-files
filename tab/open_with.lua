-- open_with: lista las aplicaciones registradas para un mimetype
-- y permite abrir el archivo con una de ellas.
--
-- Usa gio mime <mime> para consultar los .desktop asociados. gio
-- resuelve los archivos .desktop del sistema sin que tengamos que
-- parsear /usr/share/applications.

local M = {}

local function shq(s)
    return "'" .. tostring(s):gsub("'", "'\\''") .. "'"
end

local function popen_read(cmd)
    local p = io.popen(cmd .. " 2>/dev/null")
    if not p then return nil end
    local out = p:read("*a")
    p:close()
    return out
end

-- Devuelve el mimetype de un archivo.
local function mime_of(path)
    local out = popen_read("gio info -a standard::content-type " ..
        shq(path) .. " | awk -F': ' '/content-type/ {print $2; exit}'")
    if not out or out == "" then return "application/octet-stream" end
    return out:gsub("%s+$", "")
end

-- Lee un campo de un .desktop.
local function desktop_field(path, key)
    local out = popen_read(
        "grep -m1 " .. shq("^" .. key .. "=") .. " " .. shq(path))
    if not out then return nil end
    local v = out:match("^" .. key .. "=(.+)\n?$")
    if not v then return nil end
    return v
end

-- Expande el comando Exec de un .desktop eliminando marcadores
-- como %u, %U, %f, %F, %i, %c, %k.
local function clean_exec(cmd)
    cmd = cmd:gsub("%%[uUfFdDnNickvm]", "")
    cmd = cmd:gsub("%s+", " ")
    return cmd:gsub("^%s+", ""):gsub("%s+$", "")
end

-- Devuelve la lista de aplicaciones registradas para el mimetype
-- dado. Cada entrada: { id, name, exec, icon, desktop_path }.
--
-- gio mime <mime> imprime:
--   Default application for "text/x-lua": archivo.desktop
--   Registered applications:
--           archivo1.desktop
--           archivo2.desktop
--   Recommended applications:
--           ...
function M.apps_for(path)
    local mime = mime_of(path)
    local out = popen_read("gio mime " .. shq(mime))
    if not out then return {} end

    -- Recolectar los nombres de .desktop (una línea por archivo)
    local seen = {}
    local desktops = {}
    for line in out:gmatch("[^\n]+") do
        local d = line:match("([%w%-%._]+%.desktop)")
        if d and not seen[d] then
            seen[d] = true
            desktops[#desktops + 1] = d
        end
    end

    -- Resolver cada .desktop: buscar en los directorios estándar.
    local dirs = {
        "/usr/share/applications/",
        "/usr/local/share/applications/",
        (os.getenv("HOME") or "") .. "/.local/share/applications/",
    }
    local apps = {}
    for _, name in ipairs(desktops) do
        for _, dir in ipairs(dirs) do
            local full = dir .. name
            local f = io.open(full, "r")
            if f then
                f:close()
                local dn = desktop_field(full, "Name") or name
                local ex = desktop_field(full, "Exec")
                local ic = desktop_field(full, "Icon")
                if ex then
                    apps[#apps + 1] = {
                        id = name,
                        name = dn,
                        exec = clean_exec(ex),
                        icon = ic,
                        desktop_path = full,
                    }
                end
                break
            end
        end
    end

    -- Ordenar alfabéticamente por nombre
    table.sort(apps, function(a, b)
        return a.name:lower() < b.name:lower()
    end)
    return apps
end

-- Abre el archivo con la aplicación indicada. La aplicación es
-- una entrada del array devuelto por apps_for.
function M.open(app, path)
    if not app or not app.exec or not path then return false end
    -- El Exec puede tener marcadores ya limpiados. Añadir el
    -- archivo como argumento.
    local cmd = string.format(
        "(%s %s) >/dev/null 2>&1 &",
        app.exec, shq(path))
    os.execute(cmd)
    return true
end

-- Abre el archivo con la aplicación por defecto (xdg-open).
function M.open_default(path)
    if not path then return false end
    os.execute("(xdg-open " .. shq(path) .. ") >/dev/null 2>&1 &")
    return true
end

return M
