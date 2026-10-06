-- bookmarks: gestión de los marcadores del usuario.
-- Escribe en ~/.config/gtk-3.0/bookmarks, formato compartido con
-- Nautilus, Thunar y otros gestores de archivos freedesktop.
--
-- Formato del archivo:
--   file:///home/user/Proyectos Proyectos
--   file:///home/user/Descargas
--
-- Cada línea: URI + espacio + label opcional.

local M = {}

local HOME = os.getenv("HOME") or "/"
local PATH = HOME .. "/.config/gtk-3.0/bookmarks"

-- Codifica caracteres especiales en una ruta para URI.
local function uri_encode(s)
    return (s:gsub("[^%w%-%._~/]", function(c)
        return string.format("%%%02X", c:byte())
    end))
end

-- Lee las líneas del archivo como array de tablas { path, label }.
local function read_lines()
    local f = io.open(PATH, "r")
    if not f then return {} end
    local out = {}
    for line in f:lines() do
        if line ~= "" and line:sub(1, 1) ~= "#" then
            local uri, label = line:match("^(%S+)%s*(.*)$")
            if uri and uri:sub(1, 7) == "file://" then
                local fs_path = uri:sub(8)
                fs_path = fs_path:gsub("%%(%x%x)", function(h)
                    return string.char(tonumber(h, 16))
                end)
                out[#out + 1] = {
                    path  = fs_path,
                    label = (label ~= "" and label) or nil,
                }
            end
        end
    end
    f:close()
    return out
end

-- Reescribe el archivo completo. Crea el directorio si no existe.
local function write_lines(lines)
    os.execute("mkdir -p '" ..
        PATH:gsub("'", "'\\''"):gsub("/[^/]+$", "") .. "'")
    local f = io.open(PATH, "w")
    if not f then return false end
    for _, line in ipairs(lines) do
        local uri = "file://" .. uri_encode(line.path)
        if line.label and line.label ~= "" then
            f:write(uri .. " " .. line.label .. "\n")
        else
            f:write(uri .. "\n")
        end
    end
    f:close()
    return true
end

-- Devuelve la lista de marcadores como array de { path, label }.
function M.list()
    local out = {}
    for _, line in ipairs(read_lines()) do
        local label = line.label
        if not label or label == "" then
            label = line.path:match("[^/]+$") or line.path
        end
        out[#out + 1] = { path = line.path, label = label }
    end
    return out
end

-- Añade un marcador si no existe. Devuelve true si lo añadió.
function M.add(path, label)
    if not path or path == "" then return false end
    local lines = read_lines()
    for _, line in ipairs(lines) do
        if line.path == path then return false end
    end
    lines[#lines + 1] = { path = path, label = label }
    return write_lines(lines)
end

-- Quita el marcador que coincide con el path.
function M.remove(path)
    if not path then return false end
    local lines = read_lines()
    local out = {}
    local found = false
    for _, line in ipairs(lines) do
        if line.path == path then
            found = true
        else
            out[#out + 1] = line
        end
    end
    if not found then return false end
    return write_lines(out)
end

-- Comprueba si un path ya está marcado.
function M.exists(path)
    if not path then return false end
    for _, line in ipairs(read_lines()) do
        if line.path == path then return true end
    end
    return false
end

return M
