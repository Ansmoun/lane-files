-- tab: composición del gestor de archivos.
-- Ata state, fs, row, navbar, header, status, sidebar, keys,
-- context y las operaciones en un widget raíz.

local W        = require("lib.widgets")
local log      = require("lib.log")
local timer    = require("lib.timer")

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
local dialog_info = require("tab.dialog_info")
local properties  = require("tab.properties")
local context   = require("tab.context")
local filter_popup = require("tab.filter_popup")
local IconsView    = require("tab.icons_view")
local config       = require("tab.config")

local M = {}

local ROW_H = 26
local DOUBLE_CLICK_MS = 400

function M.new(srv, theme, opts)
    opts = opts or {}
    local state = State.new { initial_path = opts.initial_path }
    -- Modo de vista persistido entre sesiones. Default "list".
    state.view_mode = config.get("view_mode", "list")
    if state.view_mode ~= "list" and state.view_mode ~= "icons" then
        state.view_mode = "list"
    end

    -- ── Forward declarations ─────────────────────────────────
    local list
    local navbar_view
    local status_view
    local sidebar_view
    local refresh
    local navigate_to
    local go_up
    local go_back
    local go_forward
    local go_home
    local open_selected
    local redraw
    local scroll_to_selected
    local _right_click_handler = nil
    local icons_view = nil
    local view_stack = nil

    -- Forward: el menú Ver (definido antes del bloque de layout)
    -- necesita esta función.
    local set_view

    -- Estado del doble click
    local _last_click = { time = 0, idx = 0 }

    -- ── Helpers básicos ──────────────────────────────────────
    scroll_to_selected = function()
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

    redraw = function()
        if list and list.window then
            list.window:damage_all()
        end
    end

    open_selected = function()
        local entry = state:selected()
        if not entry then return end
        if entry.is_dir then
            navigate_to(entry.path, true)
        else
            fs.open(entry)
        end
    end

    -- ── Listado (ScrollView) ─────────────────────────────────
    list = W.ScrollView.new {
        row_height = ROW_H,
        bg_color = nil,
        min_width = 600,
        min_height = ROW_H * 14,
        on_click = function(item, idx)
            if not (item and type(item) == "table"
                    and item.path and item.name) then
                return
            end
            idx = idx or state.selected_idx

            -- Detectar modificadores
            local xcb_ = require("lib.xcb")
            local km = xcb_.query_keymap(srv.conn)
            local ctrl, shift = false, false
            if km then
                ctrl  = xcb_.key_pressed(km, 37)  -- Control_L
                shift = xcb_.key_pressed(km, 50)  -- Shift_L
            end

            if ctrl then
                state:toggle_selection(idx)
                redraw()
                _last_click.time = 0
                return
            end
            if shift then
                state:select_range(idx)
                redraw()
                _last_click.time = 0
                return
            end

            -- Detección de doble click: mismo índice, dentro de la
            -- ventana temporal.
            local now = timer.now_ms()
            local is_double = (_last_click.idx == idx)
                and (now - _last_click.time) < DOUBLE_CLICK_MS

            state:select_single(idx)
            if is_double then
                _last_click.time = 0
                _last_click.idx = 0
                open_selected()
            else
                _last_click.time = now
                _last_click.idx = idx
                redraw()
            end
        end,
        on_right_click = function(item, idx, mx, my)
            if _right_click_handler then
                _right_click_handler(item, idx, mx, my)
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

    -- Vista de iconos. Se pasa la referencia al Server para que
    -- pueda consultar el estado del teclado (Ctrl+rueda para zoom).
    icons_view = IconsView.new(theme, state)
    icons_view.srv = srv

    -- Cargar el tamaño de icono persistido (si existe) y conectar
    -- el callback que lo guarda cada vez que el usuario lo cambia
    -- con Ctrl+rueda.
    local saved_size = config.get("icons_size", nil)
    if type(saved_size) == "number" then
        icons_view:set_icon_size(saved_size)
    end
    icons_view.on_icon_size_change = function(sz)
        config.set("icons_size", sz)
    end

    -- Los callbacks de la vista de iconos son los mismos que los de
    -- la lista. Se reasignan más abajo, después de definir todos los
    -- handlers. Por ahora quedan nil.

    -- ScrollBar para la vista de iconos (barra independiente).
    local icons_slider = W.ScrollBar.new {
        orientation = "vertical",
        width = 12, thickness = 3, handle_r = 4,
        step = 60,
        color_handle = theme.accent,
        color_track = theme.separator,
    }
    W.ScrollLink.link(icons_view, icons_slider)

    -- Dos páginas: lista e iconos. El header de columnas solo
    -- existe en la página de lista. La página de iconos no lo
    -- necesita.
    local list_with_header = W.Group.new {
        orientation = "vertical",
        spacing = 0,
        children = {
            { widget = header.new(theme),  weight = 0 },
            { widget = Divider.new(theme), weight = 0 },
            { widget = W.Group.new {
                orientation = "horizontal",
                spacing = 0,
                children = {
                    { widget = list,   weight = 1 },
                    { widget = slider, weight = 0 },
                },
            }, weight = 1 },
        },
    }

    local page_list = list_with_header

    local page_icons = W.Group.new {
        orientation = "horizontal",
        spacing = 0,
        children = {
            { widget = icons_view,   weight = 1 },
            { widget = icons_slider, weight = 0 },
        },
    }

    local Stack = require("lib.widgets.stack")
    view_stack = Stack.new {}
    view_stack:add("list", page_list)
    view_stack:add("icons", page_icons)
    view_stack.active = state.view_mode

    -- Implementación de set_view. Persiste el modo en config.
    set_view = function(mode)
        if state.view_mode == mode then return end
        state.view_mode = mode
        view_stack.active = mode
        view_stack:invalidate_layout()
        config.set("view_mode", mode)
        redraw()
    end

    local list_area = view_stack

    -- ── Status ───────────────────────────────────────────────
    status_view = status.new(theme)

    -- ── Navegación ───────────────────────────────────────────
    navigate_to = function(path, push_history)
        -- Cancelar cualquier timer pendiente del breadcrumb ANTES
        -- del early return. Si el usuario navega a la misma ruta
        -- que ya está activa, el timer del breadcrumb podría
        -- seguir armado y disparar después, sacándolo de donde
        -- está.
        if navbar_view and navbar_view.cancel_pending then
            navbar_view.cancel_pending()
        end
        if path == state.cwd then return end
        state:set_cwd(path, push_history)
        refresh()
    end

    go_up = function()
        navigate_to(fs.parent(state.cwd), true)
    end

    go_back = function()
        if state:go_back() then refresh() end
    end

    go_forward = function()
        if state:go_forward() then refresh() end
    end

    go_home = function()
        navigate_to(os.getenv("HOME") or "/", true)
    end

    -- ── Operaciones sobre archivos ───────────────────────────
    local function selected_paths()
        return state:selected_paths()
    end

    local function refresh_keep_selection()
        local prev_sel = state:selected()
        refresh()
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
            for _, e in ipairs(errors) do
                log.warn("files", "pegar: %s", e)
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
            parent_win = list.window, srv = srv, theme = theme,
            title = "Renombrar",
            initial = e.name,
            accept_label = "Renombrar",
            on_accept = function(new_name)
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
            parent_win = list.window, srv = srv, theme = theme,
            title = "Borrar permanentemente: " ..
                (target and target.name or "?"),
            initial = "borrar",
            accept_label = "Borrar",
            on_accept = function(confirm)
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
            parent_win = list.window, srv = srv, theme = theme,
            title = "Crear carpeta",
            initial = "",
            placeholder = "nombre de la carpeta",
            accept_label = "Crear",
            on_accept = function(name)
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
            parent_win = list.window, srv = srv, theme = theme,
            title = "Crear archivo",
            initial = "",
            placeholder = "nombre del archivo",
            accept_label = "Crear",
            on_accept = function(name)
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
            parent_win = list.window, srv = srv, theme = theme,
            title = "Propiedades: " .. e.name,
            rows = rows,
        }
    end

    local function copy_path_to_clipboard(path)
        os.execute("printf '%s' " .. string.format("%q", path) ..
            " | xclip -selection clipboard 2>/dev/null &")
        log.info("files", "ruta copiada: %s", path)
    end

    local function do_open_filter()
        filter_popup.show {
            parent_win = list.window, srv = srv, theme = theme,
            initial = state.filter,
            on_change = function(text)
                state.filter = text or ""
                refresh()
            end,
        }
    end

    -- ── Menú contextual ──────────────────────────────────────
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

    _right_click_handler = function(item, idx, mx, my)
        if not mx or not my then return end
        -- Las coordenadas llegan locales a la vista activa. Hay que
        -- sumar la posición de la vista dentro de la ventana.
        local active_widget = (state.view_mode == "icons")
            and icons_view or list
        local wx = active_widget.x0 + mx
        local wy = active_widget.y0 + my
        if item and type(item) == "table"
           and item.path and item.name then
            state.selected_idx = idx or state.selected_idx
            redraw()
            show_context_for_entry(item, wx, wy)
        else
            show_context_for_background(wx, wy)
        end
    end

    -- Conectar los callbacks de la vista de iconos.
    icons_view.on_click = list.opts and list.opts.on_click or function() end
    -- No podemos reusar la closure del list directamente porque
    -- está definida inline. Duplicamos la lógica de click aquí.
    icons_view.on_click = function(item, idx)
        if not (item and type(item) == "table"
                and item.path and item.name) then
            return
        end
        idx = idx or state.selected_idx
        local xcb_ = require("lib.xcb")
        local km = xcb_.query_keymap(srv.conn)
        local ctrl, shift = false, false
        if km then
            ctrl  = xcb_.key_pressed(km, 37)
            shift = xcb_.key_pressed(km, 50)
        end
        if ctrl then
            state:toggle_selection(idx)
            redraw()
            _last_click.time = 0
            return
        end
        if shift then
            state:select_range(idx)
            redraw()
            _last_click.time = 0
            return
        end
        local now = timer.now_ms()
        local is_double = (_last_click.idx == idx)
            and (now - _last_click.time) < DOUBLE_CLICK_MS
        state:select_single(idx)
        if is_double then
            _last_click.time = 0
            _last_click.idx = 0
            open_selected()
        else
            _last_click.time = now
            _last_click.idx = idx
            redraw()
        end
    end

    icons_view.on_right_click = function(item, idx, mx, my)
        if _right_click_handler then
            _right_click_handler(item, idx, mx, my)
        end
    end

    -- ── Marcadores ────────────────────────────────────────────
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

    -- ── Sidebar ───────────────────────────────────────────────
    sidebar_view = Sidebar.new(theme, function(path)
        navigate_to(path, true)
    end)

    -- ── Menú superior ────────────────────────────────────────
    local function menu_open_context(anchor, items, on_close)
        -- Anclar el ContextMenu debajo del item del menubar.
        local cm = ContextMenu.new(srv, list.window, theme)
        cm:show(anchor.x0, anchor.y1 + 2, items, {
            on_close = function()
                if on_close then on_close() end
            end,
        })
    end

    local menus = {
        { label = "Archivo", build = function() return {
            { label = "Nueva carpeta", on_click = do_mkdir },
            { label = "Nuevo archivo", on_click = do_touch },
            { sep = true },
            { label = "Cerrar ventana", on_click = function()
                if list.window then list.window:close("menu") end
            end },
        } end },
        { label = "Editar", build = function() return {
            { label = "Cortar", on_click = do_cut,
              enabled = #state:selected_paths() > 0 },
            { label = "Copiar", on_click = do_copy,
              enabled = #state:selected_paths() > 0 },
            { label = "Pegar", on_click = do_paste,
              enabled = clipboard.has_content() },
            { sep = true },
            { label = "Renombrar", on_click = do_rename,
              enabled = state:selected() ~= nil },
            { label = "Eliminar", on_click = do_trash,
              enabled = #state:selected_paths() > 0 },
            { sep = true },
            { label = "Seleccionar todo", on_click = function()
                state:select_all(); redraw()
            end },
            { label = "Filtrar...", on_click = do_open_filter },
        } end },
        { label = "Ver", build = function() return {
            { label = "Vista de lista",
              on_click = function() set_view("list") end,
              enabled = state.view_mode ~= "list" },
            { label = "Vista de iconos",
              on_click = function() set_view("icons") end,
              enabled = state.view_mode ~= "icons" },
            { sep = true },
            { label = (state.show_hidden and "Ocultar ocultos"
                      or "Mostrar ocultos"),
              on_click = function()
                  state.show_hidden = not state.show_hidden
                  refresh()
              end },
            { sep = true },
            { label = "Refrescar", on_click = refresh },
        } end },
        { label = "Ir", build = function() return {
            { label = "Atrás", on_click = go_back,
              enabled = state:can_back() },
            { label = "Adelante", on_click = go_forward,
              enabled = state:can_forward() },
            { label = "Arriba", on_click = go_up },
            { label = "Inicio", on_click = go_home },
            { sep = true },
            { label = "Editar ruta...", on_click = function()
                log.info("files", "Ctrl+L: edición de ruta (pendiente)")
            end },
        } end },
        { label = "Marcadores", build = function()
            local items = {}
            for _, b in ipairs(bookmarks.list()) do
                items[#items + 1] = {
                    label = b.label,
                    on_click = function()
                        navigate_to(b.path, true)
                    end,
                }
            end
            items[#items + 1] = { sep = true }
            items[#items + 1] = {
                label = "Marcar directorio actual",
                on_click = toggle_bookmark,
            }
            return items
        end },
        { label = "Herramientas", build = function() return {
            { label = "Propiedades", on_click = do_properties,
              enabled = state:selected() ~= nil },
        } end },
    }

    navbar_view = navbar.new(theme, {
        srv     = srv,
        back    = go_back,
        forward = go_forward,
        up      = go_up,
        home    = go_home,
        on_navigate = function(path)
            navigate_to(path, true)
        end,
        menus = menus,
        open_menu = menu_open_context,
        close_menus = function() end,
    })

    -- ── Refresh ──────────────────────────────────────────────
    refresh = function()
        local pattern = state.filter:match("^%*%*%s*(.+)$")
        local all, vis
        if pattern and pattern ~= "" then
            all = fs.list_recursive(state.cwd, pattern)
            vis = all
        else
            all = fs.list_dir(state.cwd)
            vis = fs.apply_filter(all, state.filter, state.show_hidden)
        end

        state:set_entries(vis)

        -- Limpiar del conjunto los paths que ya no son visibles
        local visible_paths = {}
        for _, e in ipairs(vis) do visible_paths[e.path] = true end
        for p, _ in pairs(state.selected_set) do
            if not visible_paths[p] then
                state.selected_set[p] = nil
            end
        end
        if next(state.selected_set) == nil and #vis > 0 then
            local e = vis[state.selected_idx]
            if e then state.selected_set[e.path] = true end
        end

        list:set_items(vis)
        list:set_offset(0)
        icons_view:set_items(vis)
        icons_view:set_offset(0)
        navbar_view.breadcrumb:set_path(state.cwd)
        sidebar_view:set_active_path(state.cwd)
        navbar_view.back:set_enabled(state:can_back())
        navbar_view.forward:set_enabled(state:can_forward())

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

    -- ── Teclado ──────────────────────────────────────────────
    local keys_handler = keys.make_on_key {
        state           = state,
        refresh         = refresh,
        scroll_to       = scroll_to_selected,
        redraw          = redraw,
        open            = open_selected,
        input           = { focused = false },  -- el filtro ya no está en el navbar
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
        on_edit_path    = function()
            log.info("files", "Ctrl+L: edición de ruta (pendiente)")
        end,
        on_focus_filter = do_open_filter,
    }

    -- Envolver el handler para interceptar atajos de vista antes
    -- de pasarlos al manejador general.
    local on_key = function(key)
        if key.pressed and key.mods.ctrl then
            if key.name == "1" then set_view("list");  return true end
            if key.name == "2" then set_view("icons"); return true end
        end
        return keys_handler(key)
    end

    -- ── Layout raíz ──────────────────────────────────────────
    local content_row = W.Group.new {
        orientation = "horizontal",
        spacing = 0,
        padding = 0,
        children = {
            { widget = sidebar_view, weight = 0 },
            { widget = Divider.new_vertical(theme), weight = 0 },
            { widget = list_area,    weight = 1 },
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
