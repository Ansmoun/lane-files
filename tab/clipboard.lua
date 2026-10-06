-- clipboard: portapapeles interno del gestor de archivos.
-- Mantiene el modo (copy o cut) y la lista de paths afectados.
--
-- No usa el portapapeles X11. Copiar y pegar archivos es una
-- operación del gestor, no del sistema. El contenido sobrevive
-- mientras el proceso esté vivo. Cada ventana tiene el suyo.

local M = {}

local state = {
    mode  = nil,   -- nil | "copy" | "cut"
    paths = {},
}

-- Guarda una lista de paths en el portapapeles con el modo dado.
-- mode debe ser "copy" o "cut".
function M.set(mode, paths)
    if mode ~= "copy" and mode ~= "cut" then
        error("clipboard: mode invalido: " .. tostring(mode))
    end
    state.mode  = mode
    state.paths = paths or {}
end

-- Devuelve (mode, paths). Copia superficial de la lista.
function M.get()
    return state.mode, { table.unpack(state.paths) }
end

-- Devuelve true si hay contenido para pegar.
function M.has_content()
    return state.mode ~= nil and #state.paths > 0
end

-- Devuelve el modo actual ("copy", "cut" o nil).
function M.mode()
    return state.mode
end

-- Devuelve true si el path está en el portapapeles con modo "cut".
-- Se usa para atenuar los archivos marcados para mover.
function M.is_cut(path)
    if state.mode ~= "cut" then return false end
    for _, p in ipairs(state.paths) do
        if p == path then return true end
    end
    return false
end

-- Limpia el portapapeles.
function M.clear()
    state.mode  = nil
    state.paths = {}
end

return M
