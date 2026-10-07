-- Punto de entrada de lane-files.
--
-- Uso:
--   app.lua                        Abre en $HOME
--   app.lua /ruta                  Abre en la ruta indicada
--   app.lua --pick-file            Selector de archivo
--   app.lua --pick-dir             Selector de directorio
--   app.lua --pick-file /ruta      Selector con ruta inicial
--
-- En modo selector, la ventana muestra botones Aceptar/Cancelar
-- y Enter sobre un elemento lo selecciona. La ruta elegida se
-- imprime a stdout y el proceso termina con código 0. Si el
-- usuario cancela, termina con código 1.

local App = require("lib.app")

-- Parseo de argumentos
local pick_mode = nil
local initial_path = nil
local arg_list = arg or {}
local i = 1

-- Decodifica un file:// URI a path. Percent-decoding byte a byte
-- para no romper UTF-8 en nombres de archivo.
local function file_uri_to_path(uri)
    local rest = uri:match("^file://(.*)$")
    if not rest then return nil end
    if rest:sub(1, 10) == "localhost/" then
        rest = rest:sub(10)
    elseif rest:sub(1, 1) ~= "/" then
        return nil  -- host remoto, no soportado
    end
    return (rest:gsub("%%(%x%x)", function(h)
        return string.char(tonumber(h, 16))
    end))
end

while arg_list[i] do
    local a = arg_list[i]
    if a == "--pick-file" then
        pick_mode = "file"
    elseif a == "--pick-dir" then
        pick_mode = "dir"
    elseif a == "-h" or a == "--help" then
        print("Uso: app.lua [--pick-file|--pick-dir] [ruta|uri]")
        os.exit(0)
    elseif a:match("^file://") then
        -- Argumento pasado por .desktop (%U). Si el path ya esta
        -- resuelto, no pisar (primer argumento gana).
        if not initial_path then
            initial_path = file_uri_to_path(a)
        end
    else
        if not initial_path then initial_path = a end
    end
    i = i + 1
end

-- ¿Restaurar sesion? Solo si el usuario no pidio un path explicito
-- por CLI ni estamos en modo pick. Si pasa un path, respetamos ese
-- y no tocamos la sesion.
local load_session = (initial_path == nil) and (pick_mode == nil)
initial_path = initial_path or os.getenv("HOME")

local title = "LANE \xe2\x80\x94 Archivos"
if pick_mode == "file" then
    title = "Seleccionar archivo"
elseif pick_mode == "dir" then
    title = "Seleccionar carpeta"
end

App.new {
    name  = "files",
    title = title,
    width = 900, height = 600,
    build = function(srv, T)
        return require("tab").new(srv, T, {
            initial_path = initial_path,
            load_session = load_session,
            pick_mode    = pick_mode,
            on_pick = function(paths)
                -- Escribir la primera ruta a stdout. El resto
                -- queda para futuras versiones multi-selección.
                io.stdout:write(paths[1], "\n")
                io.stdout:flush()
                os.exit(0)
            end,
            on_cancel = function()
                os.exit(1)
            end,
        })
    end,
}:run()
