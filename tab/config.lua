-- config: persistencia de preferencias del gestor.
-- Archivo: ~/.config/lane-files/config.lua
-- Formato: return { clave = valor, ... }

local M = {}

local HOME = os.getenv("HOME") or "/"
local DIR  = HOME .. "/.config/lane-files"
local PATH = DIR .. "/config.lua"

local _cache = nil

-- Lee el archivo y devuelve la tabla. Si no existe, devuelve {}.
-- Los valores se cachean en memoria. Use save() para persistir.
function M.load()
    if _cache then return _cache end
    local chunk = loadfile(PATH)
    if not chunk then
        _cache = {}
        return _cache
    end
    local ok, t = pcall(chunk)
    if not ok or type(t) ~= "table" then
        _cache = {}
        return _cache
    end
    _cache = t
    return _cache
end

function M.get(key, default)
    local t = M.load()
    local v = t[key]
    if v == nil then return default end
    return v
end

function M.set(key, value)
    local t = M.load()
    t[key] = value
    return M.save()
end

function M.save()
    local t = M.load()
    os.execute("mkdir -p '" .. DIR .. "'")
    local f = io.open(PATH, "w")
    if not f then return false end
    f:write("-- Generado automaticamente por lane-files.\n")
    f:write("return {\n")
    -- Ordenar claves para salida determinística
    local keys = {}
    for k in pairs(t) do keys[#keys + 1] = k end
    table.sort(keys)
    for _, k in ipairs(keys) do
        local v = t[k]
        local line
        if type(v) == "number" then
            line = string.format("    %s = %s,\n", k, tostring(v))
        elseif type(v) == "boolean" then
            line = string.format("    %s = %s,\n", k, tostring(v))
        else
            line = string.format("    %s = %q,\n", k, tostring(v))
        end
        f:write(line)
    end
    f:write("}\n")
    f:close()
    return true
end

return M
