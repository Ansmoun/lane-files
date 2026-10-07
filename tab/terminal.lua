-- terminal: abre un emulador de terminal en el directorio indicado.
-- Detecta el primero disponible en PATH entre una lista de
-- candidatos conocidos. El usuario puede sobreescribir con la
-- variable de entorno LANE_FILES_TERMINAL.

local M = {}

-- Candidatos en orden de preferencia. La mayoría aceptan
-- --working-directory <dir> o -d <dir>. El comando se construye
-- por terminal.
local CANDIDATES = {
    { bin = "lxterminal",      args = "--no-remote --working-directory" },
    { bin = "st",              args = "-d" },
    { bin = "foot",            args = "--working-directory" },
    { bin = "wezterm",         args = "start --cwd" },
    { bin = "kitty",           args = "--directory" },
    { bin = "alacritty",       args = "--working-directory" },
    { bin = "xterm",           args = "-e 'cd'" },  -- fallback raro
    { bin = "urxvt",           args = "-cd" },
    { bin = "terminology",     args = "-d" },
    { bin = "gnome-terminal",  args = "--working-directory" },
    { bin = "konsole",         args = "--workdir" },
    { bin = "xfce4-terminal",  args = "--working-directory" },
}

local function shq(s)
    return "'" .. tostring(s):gsub("'", "'\\''") .. "'"
end

-- Devuelve el binario y los args del primer terminal disponible,
-- o nil si no encuentra ninguno. Respeta LANE_FILES_TERMINAL.
function M.detect()
    local override = os.getenv("LANE_FILES_TERMINAL")
    if override and override ~= "" then
        return { bin = override, args = nil }
    end
    for _, t in ipairs(CANDIDATES) do
        local p = io.popen("command -v " .. t.bin .. " 2>/dev/null")
        if p then
            local line = p:read("*l")
            p:close()
            if line and line ~= "" then
                return t
            end
        end
    end
    return nil
end

-- Abre un terminal en la ruta indicada, en segundo plano. Devuelve
-- true si se lanzó, false si no hay terminal disponible.
-- Construye el comando completo para abrir el terminal.
-- Devuelve la cadena lista para os.execute.
function M.build_command(cwd)
    if not cwd or cwd == "" then return nil end
    local t = M.detect()
    if not t then return nil end

    local base
    if t.bin == "xterm" then
        base = string.format("cd %s && %s", shq(cwd), t.bin)
    elseif t.args then
        base = string.format("%s %s %s", t.bin, t.args, shq(cwd))
    else
        base = string.format("%s %s", t.bin, shq(cwd))
    end

    -- setsid desasocia el proceso del grupo de sesión padre. Sin
    -- esto, algunos terminales (lxterminal con su servidor
    -- interno) se comportan como "remote", le pasan el comando a
    -- la instancia existente y la opción --working-directory se
    -- pierde. Con setsid, el proceso no tiene sesión padre común
    -- y arranca limpio.
    --
    -- nohup evita que el proceso muera si la app que lo lanzó se
    -- cierra. `&` lo manda a background. Redirecciones a /dev/null
    -- porque no nos interesa su salida.
    return string.format(
        "setsid -f nohup sh -c %s >/dev/null 2>&1 &",
        shq(base))
end

function M.open(cwd)
    local cmd = M.build_command(cwd)
    if not cmd then return false end
    os.execute(cmd)
    return true
end

-- Nombre del terminal detectado, para menús y mensajes.
function M.name()
    local t = M.detect()
    return t and t.bin or nil
end

return M
