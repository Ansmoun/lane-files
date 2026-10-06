-- El path inicial viene de arg[1] si existe, si no $HOME.
local App = require("lib.app")
local initial_path = (arg and arg[1]) or os.getenv("HOME")

App.new {
    name  = "files",
    title = "LANE \xe2\x80\x94 Archivos",
    width = 900, height = 600,
    build = function(srv, T)
        return require("tab").new(srv, T, { initial_path = initial_path })
    end,
}:run()
