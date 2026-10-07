-- session: persistencia de la sesion del gestor de archivos.
-- Archivo: ~/.config/lane-files/session.lua
-- Formato:
--   return {
--       tabs = {
--           { path = "/home/x", view_mode = "icons",
--             sort_by = "mtime", sort_desc = true,
--             show_hidden = false, filter = "" },
--           ...
--       },
--       active_idx = 1,
--   }
--
-- Se escribe al cerrar limpio y se lee al arrancar. Si el archivo
-- no existe o esta corrupto, se ignora sin errores.

local M = {}

local HOME = os.getenv("HOME") or "/"
local DIR  = HOME .. "/.config/lane-files"
local PATH = DIR .. "/session.lua"

-- Carga la sesion persistida. Devuelve la tabla o nil, err.
function M.load()
    local chunk = loadfile(PATH)
    if not chunk then return nil end
    local ok, t = pcall(chunk)
    if not ok or type(t) ~= "table" then return nil end
    if type(t.tabs) ~= "table" or #t.tabs == 0 then return nil end
    return t
end

-- Escribe la sesion. snapshot = { tabs = {...}, active_idx = N }.
function M.save(snapshot)
    if type(snapshot) ~= "table" then return false end
    if type(snapshot.tabs) ~= "table" or #snapshot.tabs == 0 then
        return false
    end
    os.execute("mkdir -p '" .. DIR:gsub("'", "'\\''") .. "'")
    local f = io.open(PATH, "w")
    if not f then return false end

    local function esc(s)
        s = tostring(s)
        s = s:gsub("\\", "\\\\"):gsub('"', '\\"'):gsub("\n", "\\n")
        return s
    end

    f:write("-- Generado por lane-files. No editar a mano.\n")
    f:write("return {\n")
    f:write("    tabs = {\n")
    for _, t in ipairs(snapshot.tabs) do
        f:write("        {\n")
        f:write(string.format('            path        = "%s",\n',
            esc(t.path or "")))
        f:write(string.format('            view_mode   = "%s",\n',
            esc(t.view_mode or "list")))
        f:write(string.format('            sort_by     = "%s",\n',
            esc(t.sort_by or "name")))
        f:write(string.format('            sort_desc   = %s,\n',
            tostring(t.sort_desc == true)))
        f:write(string.format('            show_hidden = %s,\n',
            tostring(t.show_hidden == true)))
        f:write(string.format('            filter      = "%s",\n',
            esc(t.filter or "")))
        f:write("        },\n")
    end
    f:write("    },\n")
    f:write(string.format("    active_idx = %d,\n",
        tonumber(snapshot.active_idx) or 1))
    f:write("}\n")
    f:close()
    return true
end

function M.clear()
    os.remove(PATH)
end

return M
