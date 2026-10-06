-- tab: composición del gestor de archivos.
-- Ata los módulos state, fs, icons, row, navbar, header, status,
-- keys y divider en un solo widget raíz.

local W        = require("lib.widgets")
local log      = require("lib.log")

local State    = require("tab.state")
local fs       = require("tab.fs")
local row      = require("tab.row")
local navbar   = require("tab.navbar")
local header   = require("tab.header")
local status   = require("tab.status")
local keys     = require("tab.keys")
local Divider  = require("tab.divider")
local Sidebar  = require("tab.sidebar")
local bookmarks = require("tab.bookmarks")
local clipboard = require("tab.clipboard")
local ops       = require("tab.ops")
local dialog    = require("tab.dialog")
local context   = require("tab.context")
local dialog_info = require("tab.dialog_info")
local properties  = require("tab.properties")

local M = {}

local ROW_H = 26

-- opts:
--   initial_path  -- default: $HOME
function M.new(srv, theme, opts)
    opts = opts or {}

    local state = State.new { initial_path = opts.initial_path }

    -- Forward declarations
    local list
    local navbar_view
    local status_view
    local sidebar_view
    local refresh
    local navigate_to
    local go_up
    local _right_click_handler = nil

    -- ── Scroll a la selección ─────────────────────────────────
    local function scroll_to_selected()
        if not list or not list.window then return end
        local off = list:get_offset()
        local vh  = list:getHeight()
        if vh <= 0 then return end
        local first   = math.floor(off / ROW_H)
        local visible = math.max(1, math.floor(vh / ROW_H))
        local last    = first + visible - 1
        local sel0    = state.selected_idx - 1
        if sel0 < first then
            list:set_offset(sel0 * ROW_H)
        elseif sel0 > last then
            list:set_offset((sel0 - visible + 1) * ROW_H)
        end
    end

    local function redraw()
        if list and list.window then
            list.window:damage_all()
        end
    end

    -- ── Abrir la entrada bajo el cursor ───────────────────────
    local function open_selected()
        local entry = state:selected()
        if not entry then return end
        if entry.is_dir then
            navigate_to(entry.path, true)
        else
            fs.open(entry)
        end
    end

    -- ── Listado (ScrollView) ──────────────────────────────────
    list = W.ScrollView.new {
        row_height = ROW_H,
        bg_color = nil,
        min_width = 600,
        min_height = ROW_H * 14,
        on_click = function(item, idx)
            -- El Window también dispara on_click con el propio
            -- ScrollView como primer argumento. Filtrar por campos.
            if not (item and type(item) == "table"
                    and item.path and item.name) then
                return
            end

            -- Detectar Ctrl y Shift con el estado actual del
            -- teclado. En el ButtonRelease, el evento X11 trae el
            -- campo state pero el ScrollView no lo propaga. Se
            -- consulta el keymap directamente.
            local xcb_ = require("lib.xcb")
            local km = xcb_.query_keymap(srv.conn)
            local ctrl, shift = false, false
            if km then
                -- keycode 37 = Control_L, 50 = Shift_L
                ctrl  = xcb_.key_pressed(km, 37)
                shift = xcb_.key_pressed(km, 50)
            end

            if ctrl then
                state:toggle_selection(idx or state.selected_idx)
                redraw()
            elseif shift then
                state:select_range(idx or state.selected_idx)
                redraw()
            else
                state:select_single(idx or state.selected_idx)
                -- En modo single-click abrimos la entrada. Si el
                -- usuario quiere solo seleccionar sin abrir, puede
                -- usar Ctrl+click.
                open_selected()
            end
        end,
        on_right_click = function(item, idx)
            -- Se llena más abajo, después de definir open_menu_for.
            if _right_click_handler then
                _right_click_handler(item, idx)
            end
        end,
    }

    list.draw_row = row.make_draw_row(theme, state, ROW_H)

    list.on_wheel = function(self, direction)
        local delta = (direction == 4) and -13 or 13
        self:set_offset(self:get_offset() + delta)
    end

    local slider = W.ScrollBar.new {
        orientation = "vertical",
        width = 12, thickness = 3, handle_r = 4,
        step = 30,
        color_handle = theme.accent,
        color_track = theme.separator,
    }
    W.ScrollLink.link(list, slider)

    local list_area = W.Group.new {
        orientation = "horizontal",
        spacing = 0,
        children = {
            { widget = list,   weight = 1 },
            { widget = slider, weight = 0 },
        },
    }

    -- ── Status bar (input, contador, hint) ────────────────────
    status_view = status.new(theme, {
        on_change = function(text)
            state.filter = text or ""
            refresh()
        end,
        on_cancel = function()
            status_view.input:set_text("")
            status_view.input:set_focused(false)
            state.filter = ""
            refresh()
        end,
    })

    -- ── Navegación ────────────────────────────────────────────
    navigate_to = function(path, push_history)
        if path == state.cwd then return end
        state:set_cwd(path, push_history)
        status_view.input:set_text("")
        status_view.input:set_focused(false)
        refresh()
    end

    go_up = function()
        navigate_to(fs.parent(state.cwd), true)
    end

    local function go_back()
        if state:go_back() then
            status_view.input:set_text("")
            refresh()
        end
    end

    local function go_forward()
        if state:go_forward() then
            status_view.input:set_text("")
            refresh()
        end
    end

    local function go_home()
        navigate_to(os.getenv("HOME") or "/", true)
    end

    navbar_view = navbar.new(theme, {
        back    = go_back,
        forward = go_forward,
        up      = go_up,
        home    = go_home,
    })

    -- ── Refresh: relista, filtra, actualiza la UI ─────────────
    refresh = function()
        local pattern = state.filter:match("^%*%*%s*(.+)$")
        local all, vis
        if pattern and pattern ~= "" then
            all = fs.list_recursive(state.cwd, pattern)
            vis = all
        else
            all = fs.list_dir(state.cwd)
            vis = fs.apply_filter(all, state.filter,
                state.show_hidden)
        end

        state:set_entries(vis)
        -- Si el conjunto quedó con paths que ya no están visibles,
        -- limpiarlos. Esto pasa al cambiar de directorio o al
        -- filtrar. Sin esta limpieza, las operaciones seguirían
        -- actuando sobre archivos invisibles.
        local visible_paths = {}
        for _, e in ipairs(vis) do visible_paths[e.path] = true end
        for p, _ in pairs(state.selected_set) do
            if not visible_paths[p] then
                state.selected_set[p] = nil
            end
        end
        -- Si el conjunto quedó vacío, marcar la fila con foco.
        if next(state.selected_set) == nil and #vis > 0 then
            local e = vis[state.selected_idx]
            if e then state.selected_set[e.path] = true end
        end
        list:set_items(vis)
        list:set_offset(0)
        navbar_view.path:set_text(state.cwd)

        -- Sincronizar sidebar (marca el lugar activo si el cwd
        -- coincide con alguno).
        sidebar_view:set_active_path(state.cwd)

        -- Habilitar/deshabilitar botones según historial
        navbar_view.back:set_enabled(state:can_back())
        navbar_view.forward:set_enabled(state:can_forward())

        -- Contador
        local n = #vis
        local sel_count = state:selection_count()
        local txt
        if sel_count > 1 then
            txt = string.format("%d seleccionados", sel_count)
        elseif state.filter ~= "" then
            txt = string.format("%d de %d (filtro)", n, #all)
        elseif n == 1 then
            txt = "1 elemento"
        else
            txt = string.format("%d elementos", n)
        end
        status_view.count:set_text(txt)

        redraw()
    end

    -- ── Portapapeles y operaciones ────────────────────────────
    -- Las operaciones actúan sobre la selección actual. Cuando hay
    -- selección múltiple, se ampliará aquí. Por ahora solo una.
    local function selected_paths()
        return state:selected_paths()
    end

    local function refresh_keep_selection()
        local prev_sel = state:selected()
        refresh()
        -- Intentar mantener la selección por path
        if prev_sel then
            for i, e in ipairs(state.entries) do
                if e.path == prev_sel.path then
                    state.selected_idx = i
                    scroll_to_selected()
                    redraw()
                    return
                end
            end
        end
    end

    local function do_copy()
        local paths = selected_paths()
        if #paths == 0 then return end
        clipboard.set("copy", paths)
        log.info("files", "copiado: %d elementos", #paths)
    end

    local function do_cut()
        local paths = selected_paths()
        if #paths == 0 then return end
        clipboard.set("cut", paths)
        log.info("files", "cortado: %d elementos", #paths)
    end

    local function do_paste()
        local mode, paths = clipboard.get()
        if not mode or #paths == 0 then return end
        local dst = state.cwd

        local result, errors
        if mode == "copy" then
            result, errors = ops.copy(paths, dst)
        else
            result, errors = ops.move(paths, dst)
            clipboard.clear()
        end

        if #errors > 0 then
            log.warn("files", "pegar: %d errores", #errors)
            for _, e in ipairs(errors) do
                log.warn("files", "  %s", e)
            end
        end
        if #result > 0 then
            log.info("files", "pegado: %d elementos", #result)
        end
        refresh_keep_selection()
    end

    local function do_rename()
        local e = state:selected()
        if not e then return end
        dialog.show {
            parent_win = list.window,
            srv        = srv,
            theme      = theme,
            title      = "Renombrar",
            initial    = e.name,
            accept_label = "Renombrar",
            on_accept  = function(new_name)
                local ok, err = ops.rename(e.path, new_name)
                if not ok then
                    log.warn("files", "rename: %s", tostring(err))
                end
                refresh_keep_selection()
            end,
        }
    end

    local function do_trash()
        local paths = selected_paths()
        if #paths == 0 then return end
        local trashed, errors = ops.trash(paths)
        if #errors > 0 then
            for _, err in ipairs(errors) do
                log.warn("files", "trash: %s", err)
            end
        end
        if #trashed > 0 then
            log.info("files", "papelera: %d elementos", #trashed)
        end
        refresh_keep_selection()
    end

    local function do_delete()
        local paths = selected_paths()
        if #paths == 0 then return end
        local target = state:selected()
        dialog.show {
            parent_win = list.window,
            srv        = srv,
            theme      = theme,
            title      = "Borrar permanentemente: " ..
                (target and target.name or "?"),
            initial    = "borrar",
            accept_label = "Borrar",
            on_accept  = function(confirm)
                if confirm ~= "borrar" then return end
                local deleted, errors = ops.delete(paths)
                if #errors > 0 then
                    for _, err in ipairs(errors) do
                        log.warn("files", "delete: %s", err)
                    end
                end
                refresh_keep_selection()
            end,
        }
    end

    local function do_mkdir()
        dialog.show {
            parent_win = list.window,
            srv        = srv,
            theme      = theme,
            title      = "Crear carpeta",
            initial    = "",
            placeholder = "nombre de la carpeta",
            accept_label = "Crear",
            on_accept  = function(name)
                if name == "" then return end
                local ok, err = ops.mkdir(state.cwd, name)
                if not ok then
                    log.warn("files", "mkdir: %s", tostring(err))
                end
                refresh_keep_selection()
            end,
        }
    end

    local function do_touch()
        dialog.show {
            parent_win = list.window,
            srv        = srv,
            theme      = theme,
            title      = "Crear archivo",
            initial    = "",
            placeholder = "nombre del archivo",
            accept_label = "Crear",
            on_accept  = function(name)
                if name == "" then return end
                local ok, err = ops.touch(state.cwd, name)
                if not ok then
                    log.warn("files", "touch: %s", tostring(err))
                end
                refresh_keep_selection()
            end,
        }
    end

    local function do_properties()
        local e = state:selected()
        if not e then return end
        local rows = properties.rows(e.path)
        dialog_info.show {
            parent_win = list.window,
            srv        = srv,
            theme      = theme,
            title      = "Propiedades: " .. e.name,
            rows       = rows,
        }
    end

    local function copy_path_to_clipboard(path)
        -- El portapapeles X11 se maneja con xclip. Lo lanzamos en
        -- segundo plano y le pasamos el path por stdin.
        local cmd = "printf '%s' " ..
            string.format("%q", path) ..
            " | xclip -selection clipboard 2>/dev/null &"
        os.execute(cmd)
        log.info("files", "ruta copiada: %s", path)
    end

    -- ── Menú contextual ───────────────────────────────────────
    local ContextMenu = require("lib.widgets.contextmenu")

    local function show_context_for_entry(entry, mx, my)
        local items = context.for_entry {
            is_dir        = entry.is_dir,
            on_open       = function() open_selected() end,
            on_copy       = function() do_copy() end,
            on_cut        = function() do_cut() end,
            on_rename     = function() do_rename() end,
            on_trash      = function() do_trash() end,
            on_delete     = function() do_delete() end,
            on_copy_path  = function()
                copy_path_to_clipboard(entry.path)
            end,
            on_properties = function() do_properties() end,
        }
        local cm = ContextMenu.new(srv, list.window, theme)
        cm:show(mx, my, items)
    end

    local function show_context_for_background(mx, my)
        local items = context.for_background {
            can_paste  = clipboard.has_content(),
            on_paste   = function() do_paste() end,
            on_mkdir   = function() do_mkdir() end,
            on_touch   = function() do_touch() end,
            on_refresh = function() refresh() end,
        }
        local cm = ContextMenu.new(srv, list.window, theme)
        cm:show(mx, my, items)
    end

    -- Handler del click derecho. Recibe (item, idx) del ScrollView.
    -- Las coordenadas del ratón las obtenemos con xcb.query_pointer.
    -- El ScrollView no las pasa.
    _right_click_handler = function(item, idx)
        local xcb_ = require("lib.xcb")
        local cx, cy = xcb_.query_pointer(srv.conn)
        if not cx then return end
        -- Convertir coordenadas globales a locales del listado.
        -- El ContextMenu usa coordenadas globales de la ventana
        -- padre. Como estamos en un child del list.window, hay que
        -- calcular relativo al parent_win. Esto se complica; el
        -- menu se ancla al cursor de todos modos.
        local mx = cx - list.window.x
        local my = cy - list.window.y

        if item and type(item) == "table"
           and item.path and item.name then
            state.selected_idx = idx or state.selected_idx
            redraw()
            show_context_for_entry(item, mx, my)
        else
            show_context_for_background(mx, my)
        end
    end

    -- ── Marcadores ────────────────────────────────────────────
    -- Ctrl+B marca o desmarca el directorio actual. El sidebar se
    -- reconstruye en el momento. La fila que se añade o se quita
    -- cambia de posición en el layout, así que hay que forzar un
    -- relayout completo del árbol tras el cambio.
    local function toggle_bookmark()
        local cwd = state.cwd
        if bookmarks.exists(cwd) then
            bookmarks.remove(cwd)
        else
            local label = cwd:match("[^/]+$") or cwd
            bookmarks.add(cwd, label)
        end
        sidebar_view:refresh()
        sidebar_view:set_active_path(cwd)
        redraw()
    end

    -- ── Teclado ───────────────────────────────────────────────
    local on_key = keys.make_on_key {
        state           = state,
        refresh         = refresh,
        scroll_to       = scroll_to_selected,
        redraw          = redraw,
        open            = open_selected,
        input           = status_view.input,
        go_up           = go_up,
        toggle_bookmark = toggle_bookmark,
        on_copy         = do_copy,
        on_cut          = do_cut,
        on_paste        = do_paste,
        on_rename       = do_rename,
        on_trash        = do_trash,
        on_delete       = do_delete,
        on_mkdir        = do_mkdir,
        on_refresh      = refresh,
    }

    -- ── Sidebar ───────────────────────────────────────────────
    -- Se crea antes del layout. El callback on_navigate recibe el
    -- path y dispara navigate_to. El sidebar no conoce el estado,
    -- solo emite intención de navegación.
    sidebar_view = Sidebar.new(theme, function(path)
        navigate_to(path, true)
    end)

    -- ── Layout raíz ───────────────────────────────────────────
    -- Estructura:
    --   navbar
    --   divider
    --   [ sidebar | [header, divider, list_area] ]
    --   divider
    --   status
    local content_row = W.Group.new {
        orientation = "horizontal",
        spacing = 0,
        padding = 0,
        children = {
            { widget = sidebar_view, weight = 0 },
            { widget = Divider.new_vertical(theme), weight = 0 },
            { widget = W.Group.new {
                orientation = "vertical",
                spacing = 0,
                children = {
                    { widget = header.new(theme),  weight = 0 },
                    { widget = Divider.new(theme), weight = 0 },
                    { widget = list_area,          weight = 1 },
                },
            }, weight = 1 },
        },
    }

    local layout = W.Group.new {
        orientation = "vertical",
        spacing = 0,
        padding = 0,
        children = {
            { widget = navbar_view.widget, weight = 0 },
            { widget = Divider.new(theme), weight = 0 },
            { widget = content_row,        weight = 1 },
            { widget = Divider.new(theme), weight = 0 },
            { widget = status_view.widget, weight = 0 },
        },
    }

    -- ── start ─────────────────────────────────────────────────
    local function start()
        state.history = { state.cwd }
        state.history_idx = 1
        refresh()
    end

    return {
        widget = layout,
        start  = start,
        stop   = function() end,
        on_key = on_key,
    }
end

return M
