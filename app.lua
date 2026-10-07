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
while arg_list[i] do
    local a = arg_list[i]
    if a == "--pick-file" then
        pick_mode = "file"
    elseif a == "--pick-dir" then
        pick_mode = "dir"
    elseif a == "-h" or a == "--help" then
        print("Uso: app.lua [--pick-file|--pick-dir] [ruta]")
        os.exit(0)
    else
        initial_path = a
    end
    i = i + 1
end

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
