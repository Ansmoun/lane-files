-- keys: manejo de teclado del gestor de archivos.
-- Devuelve on_key(key) listo para pasar a tab.on_key.

local M = {}

-- opts:
--   state      -- instancia de tab/state
--   refresh    -- función que relista el directorio
--   scroll_to  -- función que hace scroll a la fila seleccionada
--   redraw     -- función que daña la ventana para repintar
--   open       -- función que abre la entrada seleccionada
--   input      -- TextInput del filtro
--   go_up      -- función que sube un nivel
--   toggle_bookmark -- función que marca/desmarca el cwd
function M.make_on_key(opts)
    local state     = opts.state
    local refresh   = opts.refresh
    local scroll_to = opts.scroll_to
    local redraw    = opts.redraw
    local open      = opts.open
    local input     = opts.input
    local go_up     = opts.go_up
    local toggle_bm = opts.toggle_bookmark

    local function after_move()
        if scroll_to then scroll_to() end
        if redraw then redraw() end
    end

    return function(key)
        if not key.pressed then return false end

        -- Ctrl+H: toggle ocultos
        if key.name == "h" and key.mods.ctrl then
            state.show_hidden = not state.show_hidden
            refresh()
            return true
        end

        -- Ctrl+B: marcar o desmarcar el directorio actual
        if key.name == "b" and key.mods.ctrl then
            if toggle_bm then toggle_bm() end
            return true
        end

        -- "/" enfoca el filtro
        if key.text == "/" and not input.focused then
            input:set_focused(true)
            return true
        end

        -- Backspace: subir un nivel (si el input no tiene foco)
        if key.name == "BackSpace" and not input.focused then
            go_up()
            return true
        end

        -- Navegación con flechas. Si el input tiene foco, se lo
        -- dejamos a él (para mover el cursor de texto).
        if not input.focused then
            if key.name == "Down" then
                state:move_selection(1)
                after_move()
                return true
            end
            if key.name == "Up" then
                state:move_selection(-1)
                after_move()
                return true
            end
            if key.name == "Home" then
                state:select_first()
                after_move()
                return true
            end
            if key.name == "End" then
                state:select_last()
                after_move()
                return true
            end
            if key.name == "Prior" or key.name == "Page_Up" then
                state:move_selection(-10)
                after_move()
                return true
            end
            if key.name == "Next" or key.name == "Page_Down" then
                state:move_selection(10)
                after_move()
                return true
            end
            if key.name == "Return" or key.name == "KP_Enter" then
                open()
                return true
            end
        end

        -- Escape: si el filtro tiene foco, lo saca y limpia.
        -- Si no, deja que la ventana cierre.
        if key.name == "Escape" then
            if input.focused then
                input:set_text("")
                input:set_focused(false)
                state.filter = ""
                refresh()
                return true
            end
            return false
        end

        return false
    end
end

return M
