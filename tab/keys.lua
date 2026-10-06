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
--   on_copy    -- Ctrl+C sobre la selección
--   on_cut     -- Ctrl+X sobre la selección
--   on_paste   -- Ctrl+V en el cwd
--   on_rename  -- F2 sobre la selección
--   on_trash   -- Delete sobre la selección
--   on_delete  -- Shift+Delete sobre la selección
--   on_mkdir   -- Ctrl+Shift+N en el cwd
--   on_refresh -- F5
--   on_edit_path -- Ctrl+L, enfocar breadcrumb para editar ruta
--   on_focus_filter -- Ctrl+F, enfocar el filtro
--   on_move     -- function(dir) -> bool. Si devuelve true,
--                  consumió el movimiento. Se llama antes de la
--                  navegación lineal. Se usa para la grilla de
--                  iconos.
function M.make_on_key(opts)
    local state     = opts.state
    local refresh   = opts.refresh
    local scroll_to = opts.scroll_to
    local redraw    = opts.redraw
    local open      = opts.open
    local input     = opts.input
    local go_up     = opts.go_up
    local toggle_bm = opts.toggle_bookmark
    local on_copy   = opts.on_copy
    local on_cut    = opts.on_cut
    local on_paste  = opts.on_paste
    local on_rename = opts.on_rename
    local on_trash  = opts.on_trash
    local on_delete = opts.on_delete
    local on_mkdir  = opts.on_mkdir
    local on_refresh = opts.on_refresh
    local on_edit_path = opts.on_edit_path
    local on_focus_filter = opts.on_focus_filter
    local on_move = opts.on_move

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

        -- Ctrl+L: enfocar el breadcrumb para editar la ruta
        if key.name == "l" and key.mods.ctrl then
            if on_edit_path then on_edit_path() end
            return true
        end

        -- Ctrl+A: seleccionar todo lo visible
        if key.name == "a" and key.mods.ctrl then
            state:select_all()
            if redraw then redraw() end
            return true
        end

        -- Ctrl+B: marcar o desmarcar el directorio actual
        if key.name == "b" and key.mods.ctrl then
            if toggle_bm then toggle_bm() end
            return true
        end

        -- Ctrl+Shift+N: crear carpeta
        if key.name == "n" and key.mods.ctrl and key.mods.shift then
            if on_mkdir then on_mkdir() end
            return true
        end

        -- Ctrl+C / Ctrl+X / Ctrl+V: portapapeles interno
        if key.mods.ctrl and not key.mods.shift then
            if key.name == "c" then
                if on_copy then on_copy() end
                return true
            end
            if key.name == "x" then
                if on_cut then on_cut() end
                return true
            end
            if key.name == "v" then
                if on_paste then on_paste() end
                return true
            end
        end

        -- F2: renombrar
        if key.name == "F2" then
            if on_rename then on_rename() end
            return true
        end

        -- F5: refrescar
        if key.name == "F5" then
            if on_refresh then on_refresh() end
            return true
        end

        -- Delete / Shift+Delete
        if key.name == "Delete" then
            if key.mods.shift then
                if on_delete then on_delete() end
            else
                if on_trash then on_trash() end
            end
            return true
        end

        -- Ctrl+F: enfocar el filtro
        if key.name == "f" and key.mods.ctrl then
            if on_focus_filter then on_focus_filter() end
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
            -- Movimientos direccionales. Si el consumidor tiene
            -- una función on_move específica del modo activo
            -- (grilla de iconos, por ejemplo), se le da prioridad.
            -- Si devuelve true, consumió el movimiento.
            local arrow_map = {
                Down     = "down",
                Up       = "up",
                Left     = "left",
                Right    = "right",
            }
            local dir = arrow_map[key.name]
            if dir and on_move and on_move(dir) then
                after_move()
                return true
            end

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
            if key.name == "Left" then
                state:move_selection(-1)
                after_move()
                return true
            end
            if key.name == "Right" then
                state:move_selection(1)
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

        -- Escape: prioridad de capas.
        --   1. Input con foco -> limpiarlo.
        --   2. Conjunto de selección no vacío -> limpiarlo.
        --   3. Sin nada que limpiar -> dejar cerrar la ventana.
        if key.name == "Escape" then
            if input.focused then
                input:set_text("")
                input:set_focused(false)
                state.filter = ""
                refresh()
                return true
            end
            if state:selection_count() > 1
               or (state:selection_count() == 1
                   and next(state.selected_set) ~= nil) then
                state.selected_set = {}
                local e = state.entries[state.selected_idx]
                if e then state.selected_set[e.path] = true end
                if redraw then redraw() end
                return true
            end
            return false
        end

        return false
    end
end

return M
