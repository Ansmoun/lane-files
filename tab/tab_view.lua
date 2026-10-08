-- tab_view: una pestaña del gestor de archivos.
-- Contiene el estado (cwd, selección, historial) y las dos vistas
-- intercambiables (lista e iconos). El navbar, sidebar y status
-- son responsabilidad del contenedor (init.lua).
--
-- Expone:
--   widget         -- Group con el Stack de vistas. Es lo que el
--                     contenedor monta en su layout.
--   state          -- estado del tab (cwd, selección, historial)
--   on_cwd_change  -- callback que el contenedor registra. Se
--                     dispara cada vez que cambia el cwd.
--   on_selection_change -- callback al cambiar la selección.
--   Todos los handlers públicos (do_copy, do_paste, go_back, ...).

local W        = require("lib.widgets")
local log      = require("lib.log")
local timer    = require("lib.timer")

local State    = require("tab.state")
local fs       = require("tab.fs")
local row      = require("tab.row")
local header   = require("tab.header")
local Divider  = require("tab.divider")
local clipboard = require("tab.clipboard")
local ops       = require("tab.ops")
local dialog    = require("tab.dialog")
local dialog_info = require("tab.dialog_info")
local dialog_confirm = require("tab.dialog_confirm")
local properties = require("tab.properties")
local context    = require("tab.context")
local filter_popup = require("tab.filter_popup")
local IconsView  = require("tab.icons_view")
local terminal   = require("tab.terminal")
local open_with  = require("tab.open_with")
local trash_mod  = require("tab.trash")
local icons      = require("tab.icons")
local bookmarks  = require("tab.bookmarks")
local keys       = require("tab.keys")

local M = {}

local ROW_H          = 26
local DOUBLE_CLICK_MS = 400
local TRASH_DIR = (os.getenv("HOME") or "/") ..
    "/.local/share/Trash/files"

local TabView = {}
TabView.__index = TabView

-- opts:
--   initial_path     -- cwd inicial
--   view_mode        -- "list" | "icons"
--   icon_size        -- tamaño de iconos en vista de iconos
--   on_cwd_change    -- callback cuando cambia el cwd
--   on_selection_change -- callback cuando cambia la selección
--   get_parent_window   -- función que devuelve la Window padre
--                         (la necesita el contenedor para
--                         ContextMenu, diálogos, etc.)
function TabView.new(srv, theme, opts)
    opts = opts or {}
    local self = setmetatable({}, TabView)
    self.srv = srv
    self.theme = theme
    self.opts = opts

    self.state = State.new { initial_path = opts.initial_path }

    -- Snapshot restaurado desde session.lua, si lo hay. Precede a
    -- opts.view_mode, pero no al initial_path (que ya lo aplico
    -- State.new). Los valores invalidos se normalizan.
    if opts.snapshot then
        local sn = opts.snapshot
        self.state.view_mode   = sn.view_mode or "list"
        self.state.sort_by     = sn.sort_by or "name"
        self.state.sort_desc   = sn.sort_desc == true
        self.state.show_hidden = sn.show_hidden == true
        self.state.filter      = sn.filter or ""
    else
        self.state.view_mode = opts.view_mode or "list"
    end
    if self.state.view_mode ~= "list"
       and self.state.view_mode ~= "icons" then
        self.state.view_mode = "list"
    end

    -- Forward declarations internas
    local list
    local icons_view
    local view_stack
    local header_view
    local refresh
    local navigate_to
    local go_up
    local go_back
    local go_forward
    local go_home
    local open_selected
    local redraw
    local scroll_to_selected
    local set_view
    local update_selection_info
    local _last_click = { time = 0, idx = 0 }

    -- Referencia al list.window. La obtiene el contenedor después
    -- de crear la Window. Por ahora puede ser nil.
    local function parent_win()
        if opts.get_parent_window then
            return opts.get_parent_window()
        end
        return list and list.window
    end

    -- ── Helpers básicos ──────────────────────────────────────
    scroll_to_selected = function()
        if not list or not list.window then return end
        local off = list:get_offset()
        local vh  = list:getHeight()
        if vh <= 0 then return end
        local first   = math.floor(off / ROW_H)
        local visible = math.max(1, math.floor(vh / ROW_H))
        local last    = first + visible - 1
        local sel0    = self.state.selected_idx - 1
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
        if update_selection_info then update_selection_info() end
    end

    open_selected = function()
        local entry = self.state:selected()
        if not entry then return end
        if entry.is_dir then
            navigate_to(entry.path, true)
        else
            fs.open(entry)
        end
    end

    update_selection_info = function()
        if opts.on_selection_change then
            opts.on_selection_change(self.state)
        end
    end

    -- ── Listado (lista) ─────────────────────────────────────
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
            idx = idx or self.state.selected_idx
            local xcb_ = require("lib.xcb")
            local km = xcb_.query_keymap(srv.conn)
            local ctrl, shift = false, false
            if km then
                ctrl  = xcb_.key_pressed(km, 37)
                shift = xcb_.key_pressed(km, 50)
            end
            if ctrl then
                self.state:toggle_selection(idx)
                redraw()
                _last_click.time = 0
                return
            end
            if shift then
                self.state:select_range(idx)
                redraw()
                _last_click.time = 0
                return
            end
            local now = timer.now_ms()
            local is_double = (_last_click.idx == idx)
                and (now - _last_click.time) < DOUBLE_CLICK_MS
            self.state:select_single(idx)
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
            if self.on_right_click_handler then
                self.on_right_click_handler(item, idx, mx, my)
            end
        end,
    }
    list.draw_row = row.make_draw_row(theme, self.state, ROW_H)
    list.on_wheel = function(s, direction)
        local delta = (direction == 4) and -13 or 13
        s:set_offset(s:get_offset() + delta)
    end

    local slider = W.ScrollBar.new {
        orientation = "vertical",
        width = 12, thickness = 3, handle_r = 4,
        step = 30,
        color_handle = theme.accent,
        color_track = theme.separator,
    }
    W.ScrollLink.link(list, slider)

    -- ── Vista de iconos ─────────────────────────────────────
    icons_view = IconsView.new(theme, self.state)
    icons_view.srv = srv
    if type(opts.icon_size) == "number" then
        icons_view:set_icon_size(opts.icon_size)
    end
    icons_view.on_icon_size_change = opts.on_icon_size_change

    icons_view.on_click = function(item, idx)
        if not (item and type(item) == "table"
                and item.path and item.name) then
            return
        end
        idx = idx or self.state.selected_idx
        local xcb_ = require("lib.xcb")
        local km = xcb_.query_keymap(srv.conn)
        local ctrl, shift = false, false
        if km then
            ctrl  = xcb_.key_pressed(km, 37)
            shift = xcb_.key_pressed(km, 50)
        end
        if ctrl then
            self.state:toggle_selection(idx)
            redraw()
            _last_click.time = 0
            return
        end
        if shift then
            self.state:select_range(idx)
            redraw()
            _last_click.time = 0
            return
        end
        local now = timer.now_ms()
        local is_double = (_last_click.idx == idx)
            and (now - _last_click.time) < DOUBLE_CLICK_MS
        self.state:select_single(idx)
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
        if self.on_right_click_handler then
            self.on_right_click_handler(item, idx, mx, my)
        end
    end

    local icons_slider = W.ScrollBar.new {
        orientation = "vertical",
        width = 12, thickness = 3, handle_r = 4,
        step = 60,
        color_handle = theme.accent,
        color_track = theme.separator,
    }
    W.ScrollLink.link(icons_view, icons_slider)

    -- ── Header (solo en vista de lista) ─────────────────────
    header_view = header.new(theme, {
        on_sort = function(column)
            self.state:set_sort(column)
            refresh()
        end,
    })

    local page_list = W.Group.new {
        orientation = "vertical",
        spacing = 0,
        children = {
            { widget = header_view,        weight = 0 },
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
    view_stack.active = self.state.view_mode

    set_view = function(mode)
        if self.state.view_mode == mode then return end
        self.state.view_mode = mode
        view_stack.active = mode
        view_stack:invalidate_layout()
        if opts.on_view_mode_change then
            opts.on_view_mode_change(mode)
        end
        redraw()
    end
    self.set_view = set_view

    -- ── Navegación ───────────────────────────────────────────
    navigate_to = function(path, push_history)
        if path == self.state.cwd then return end
        self.state:set_cwd(path, push_history)
        refresh()
        if opts.on_cwd_change then
            opts.on_cwd_change(self.state.cwd)
        end
    end

    go_up = function()
        navigate_to(fs.parent(self.state.cwd), true)
    end

    go_back = function()
        if self.state:go_back() then
            refresh()
            if opts.on_cwd_change then
                opts.on_cwd_change(self.state.cwd)
            end
        end
    end

    go_forward = function()
        if self.state:go_forward() then
            refresh()
            if opts.on_cwd_change then
                opts.on_cwd_change(self.state.cwd)
            end
        end
    end

    go_home = function()
        navigate_to(os.getenv("HOME") or "/", true)
    end

    -- ── Operaciones ─────────────────────────────────────────
    local function selected_paths()
        return self.state:selected_paths()
    end

    local function refresh_keep_selection()
        local prev_sel = self.state:selected()
        refresh()
        if prev_sel then
            for i, e in ipairs(self.state.entries) do
                if e.path == prev_sel.path then
                    self.state.selected_idx = i
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
        local dst = self.state.cwd

        -- Detectar colisiones: si algún basename ya existe en dst.
        -- No usamos unique_dest acá, solo comprobamos existencia.
        local collisions = 0
        log.info("files", "paste: cwd=%s, %d origen(es)",
            tostring(dst), #paths)
        for _, src in ipairs(paths) do
            local name = src:match("[^/]+$") or src
            local candidate
            if dst == "/" then candidate = "/" .. name
            else candidate = dst .. "/" .. name end
            local f = io.open(candidate, "r")
            local exists = f and "SI" or "NO"
            if f then
                f:close()
                collisions = collisions + 1
            end
            log.info("files", "  check %s -> %s (%s)",
                src, candidate, exists)
        end
        log.info("files", "colisiones detectadas: %d", collisions)

        local function proceed(overwrite)
            if mode == "cut" then clipboard.clear() end

            local ops_async = require("tab.ops_async")
            local progress_dialog = require("tab.progress_dialog")

            local handle, err = ops_async.start(mode, paths, dst, {
                overwrite = overwrite,
            })
            if not handle then
                log.warn("files", "pegar: %s", tostring(err))
                refresh_keep_selection()
                return
            end

            -- Timer único. Reglas:
            --   - operación total < 1 MB -> NUNCA mostrar diálogo
            --     (cp de 1 MB tarda pocos ms; el diálogo solo
            --     molesta).
            --   - operación grande: mostrar diálogo SOLO si tarda
            --     más de 400 ms (evita el flash cuando termina
            --     rápido pero el setup ya consumió tiempo).
            local timer = require("lib.timer")
            local small_op = (handle.total_bytes or 0) < 1024 * 1024
            local shown = false
            local start_t = timer.now_ms()

            local poll_tm
            poll_tm = srv:add_timer(60, function()
                if handle:is_done() then
                    poll_tm:cancel()
                    -- Refrescar SIEMPRE, sin importar si el
                    -- dialogo aparecio o no. Antes solo se
                    -- refrescaba si !shown; si el dialogo
                    -- aparecia, la unica via de refresh era
                    -- on_done, que no siempre llegaba. Resultado:
                    -- el archivo nuevo no se veia hasta navegar
                    -- a otra carpeta y volver.
                    local errors = handle:status().errors or {}
                    for _, e in ipairs(errors) do
                        log.warn("files", "pegar: %s", e)
                    end
                    refresh_keep_selection()
                    -- Segundo refresh con delay: algunos FS
                    -- tardan unos ms en reflejar el ultimo
                    -- rename. Sin esto, una copia que termina
                    -- exactamente en el boundary del readdir
                    -- puede dejar el item afuera.
                    if self.window then
                        local w = self.window
                        srv:add_timeout(150, function()
                            if w and not w.destroyed then
                                refresh_keep_selection()
                            end
                        end)
                    end
                    return
                end
                if shown then return end
                if small_op then return end
                local now = timer.now_ms()
                if (now - start_t) < 400 then return end
                shown = true
                progress_dialog.show {
                    parent_win = parent_win(),
                    srv        = srv,
                    theme      = theme,
                    handle     = handle,
                    mode       = mode,
                    -- on_done / on_cancel ya no refrescan: el
                    -- poll_tm es la unica fuente.
                }
            end)
        end

        if collisions > 0 then
            require("tab.dialog_collision").show {
                parent_win   = parent_win(),
                srv          = srv,
                theme        = theme,
                count        = collisions,
                on_overwrite = function() proceed(true)  end,
                on_rename    = function() proceed(false) end,
                on_cancel    = function() end,
            }
        else
            proceed(false)
        end
    end

    local function do_rename()
        local e = self.state:selected()
        if not e then return end
        dialog.show {
            parent_win = parent_win(), srv = srv, theme = theme,
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
        local msg
        if #paths == 1 then
            local target = self.state:selected()
            msg = "¿Borrar permanentemente '" ..
                (target and target.name or "?") .. "'?"
        else
            msg = string.format(
                "¿Borrar permanentemente %d elementos?", #paths)
        end
        msg = msg .. "\n\nEsta acción no se puede deshacer."
        dialog_confirm.show {
            parent_win = parent_win(), srv = srv, theme = theme,
            title = "Borrar permanentemente",
            message = msg,
            confirm_label = "Borrar",
            destructive = true,
            on_accept = function()
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
            parent_win = parent_win(), srv = srv, theme = theme,
            title = "Crear carpeta",
            placeholder = "nombre de la carpeta",
            accept_label = "Crear",
            on_accept = function(name)
                if name == "" then return end
                local ok, err = ops.mkdir(self.state.cwd, name)
                if not ok then
                    log.warn("files", "mkdir: %s", tostring(err))
                end
                refresh_keep_selection()
            end,
        }
    end

    local function do_touch()
        dialog.show {
            parent_win = parent_win(), srv = srv, theme = theme,
            title = "Crear archivo",
            placeholder = "nombre del archivo",
            accept_label = "Crear",
            on_accept = function(name)
                if name == "" then return end
                local ok, err = ops.touch(self.state.cwd, name)
                if not ok then
                    log.warn("files", "touch: %s", tostring(err))
                end
                refresh_keep_selection()
            end,
        }
    end

    local function do_properties()
        local e = self.state:selected()
        if not e then return end
        local rows = properties.rows(e.path)
        dialog_info.show {
            parent_win = parent_win(), srv = srv, theme = theme,
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
            parent_win = parent_win(), srv = srv, theme = theme,
            initial = self.state.filter,
            on_change = function(text)
                self.state.filter = text or ""
                refresh()
            end,
        }
    end

    local function do_terminal()
        terminal.open(self.state.cwd)
    end

    local function do_open_with()
        local e = self.state:selected()
        if not e then return end
        local apps = open_with.apps_for(e.path)
        if #apps == 0 then
            log.warn("files", "sin aplicaciones para " .. e.path)
            return
        end
        local items = {}
        for _, app in ipairs(apps) do
            items[#items + 1] = {
                label = app.name,
                on_click = function()
                    open_with.open(app, e.path)
                end,
            }
        end
        items[#items + 1] = { sep = true }
        items[#items + 1] = {
            label = "Aplicación por defecto",
            on_click = function()
                open_with.open_default(e.path)
            end,
        }
        local xcb = require("lib.xcb")
        local gx, gy = xcb.query_pointer(srv.conn)
        local win = parent_win()
        local wx = gx and win and (gx - win.x) or 100
        local wy = gy and win and (gy - win.y) or 100
        local ContextMenu_local = require("lib.widgets.contextmenu")
        local cm = ContextMenu_local.new(srv, win, theme)
        cm:show(wx, wy, items)
    end

    local function is_in_trash()
        return self.state.cwd:sub(1, #TRASH_DIR) == TRASH_DIR
    end

    local function do_open_trash()
        if not ops.is_dir(TRASH_DIR) then
            log.warn("files", "no existe la papelera: " .. TRASH_DIR)
            return
        end
        navigate_to(TRASH_DIR, true)
    end

    local function do_empty_trash()
        local n = trash_mod.count_now()
        local msg
        if n == 0 then
            msg = "La papelera ya está vacía."
        elseif n == 1 then
            msg = "¿Vaciar la papelera?\n\n" ..
                "Se eliminará permanentemente 1 elemento."
        else
            msg = string.format(
                "¿Vaciar la papelera?\n\n" ..
                "Se eliminarán permanentemente %d elementos.", n)
        end
        dialog_confirm.show {
            parent_win = parent_win(), srv = srv, theme = theme,
            title = "Vaciar papelera",
            message = msg,
            confirm_label = "Vaciar",
            destructive = true,
            on_accept = function()
                trash_mod.empty()
                refresh()
            end,
        }
    end

    local function do_restore_from_trash()
        local e = self.state:selected()
        if not e then return end
        for _, item in ipairs(trash_mod.list()) do
            if item.name == e.name then
                local ok, err = trash_mod.restore(item)
                if not ok then
                    log.warn("files", "restaurar: %s", tostring(err))
                end
                refresh()
                return
            end
        end
    end

    local function toggle_bookmark()
        local cwd = self.state.cwd
        if bookmarks.exists(cwd) then
            bookmarks.remove(cwd)
        else
            local label = cwd:match("[^/]+$") or cwd
            bookmarks.add(cwd, label)
        end
        if opts.on_bookmarks_change then
            opts.on_bookmarks_change()
        end
        redraw()
    end

    -- ── Menú contextual ─────────────────────────────────────
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
            on_open_with  = function() do_open_with() end,
        }
        local cm = ContextMenu.new(srv, parent_win(), theme)
        cm:show(mx, my, items)
    end

    local function show_context_for_background(mx, my)
        local items = context.for_background {
            can_paste  = clipboard.has_content(),
            on_paste   = function() do_paste() end,
            on_mkdir   = function() do_mkdir() end,
            on_touch   = function() do_touch() end,
            on_refresh = function() refresh() end,
            on_terminal = function() do_terminal() end,
        }
        local cm = ContextMenu.new(srv, parent_win(), theme)
        cm:show(mx, my, items)
    end

    self.on_right_click_handler = function(item, idx, mx, my)
        if not mx or not my then return end
        local active_widget = (self.state.view_mode == "icons")
            and icons_view or list
        local wx = active_widget.x0 + mx
        local wy = active_widget.y0 + my
        if item and type(item) == "table"
           and item.path and item.name then
            -- Regla de cualquier file manager: click derecho sobre
            -- un item que NO esta en la seleccion actual resetea
            -- el conjunto a solo ese item. Si ya estaba en el
            -- conjunto, se respeta (permite copiar/mover varios
            -- con una sola accion).
            --
            -- Antes solo se actualizaba selected_idx (el foco),
            -- pero selected_set (el conjunto) quedaba con lo que
            -- hubiera antes. Copiar desde el menu contextual
            -- copiaba el conjunto viejo, no el item bajo el cursor.
            local already_selected =
                self.state.selected_set[item.path] == true
            if not already_selected then
                self.state:select_single(idx)
            else
                self.state.selected_idx = idx or self.state.selected_idx
            end
            redraw()
            show_context_for_entry(item, wx, wy)
        else
            show_context_for_background(wx, wy)
        end
    end

    -- ── Refresh ─────────────────────────────────────────────
    refresh = function()
        local pattern = self.state.filter:match("^%*%*%s*(.+)$")
        local all, vis
        if pattern and pattern ~= "" then
            all = fs.list_recursive(self.state.cwd, pattern)
            all = fs.sort(all, self.state.sort_by, self.state.sort_desc)
            vis = all
        else
            all = fs.list_dir(self.state.cwd)
            all = fs.sort(all, self.state.sort_by, self.state.sort_desc)
            vis = fs.apply_filter(all, self.state.filter,
                self.state.show_hidden)
        end
        if header_view then
            header_view:set_sort(self.state.sort_by, self.state.sort_desc)
        end

        self.state:set_entries(vis)
        local visible_paths = {}
        for _, e in ipairs(vis) do visible_paths[e.path] = true end
        for p, _ in pairs(self.state.selected_set) do
            if not visible_paths[p] then
                self.state.selected_set[p] = nil
            end
        end
        if next(self.state.selected_set) == nil and #vis > 0 then
            local e = vis[self.state.selected_idx]
            if e then self.state.selected_set[e.path] = true end
        end

        list:set_items(vis)
        list:set_offset(0)
        icons_view:set_items(vis)
        icons_view:set_offset(0)

        if opts.on_selection_change then
            opts.on_selection_change(self.state)
        end
        redraw()
    end

    -- ── Teclado ─────────────────────────────────────────────
    local keys_handler = keys.make_on_key {
        state           = self.state,
        refresh         = refresh,
        scroll_to       = scroll_to_selected,
        redraw          = redraw,
        open            = open_selected,
        input           = { focused = false },
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
        on_move         = function(dir)
            if self.state.view_mode == "icons" then
                return icons_view:move_selection(dir)
            end
            return false
        end,
    }

    local function on_key(key)
        if key.pressed and key.mods.ctrl then
            if key.name == "1" then set_view("list");  return true end
            if key.name == "2" then set_view("icons"); return true end
            if key.name == "t" and key.mods.shift then
                do_terminal()
                return true
            end
        end
        return keys_handler(key)
    end

    -- ── Widget raíz (solo el Stack de vistas) ───────────────
    local widget = view_stack

    -- ── Exponer API pública ─────────────────────────────────
    self.widget           = widget
    self.list             = list
    self.icons_view       = icons_view
    self.view_stack       = view_stack
    self.header_view      = header_view
    self.navigate_to      = navigate_to
    self.go_back          = go_back
    self.go_forward       = go_forward
    self.go_up            = go_up
    self.go_home          = go_home
    self.open_selected    = open_selected
    self.refresh          = refresh
    self.redraw           = redraw
    self.do_copy          = do_copy
    self.do_cut           = do_cut
    self.do_paste         = do_paste
    self.do_rename        = do_rename
    self.do_trash         = do_trash
    self.do_delete        = do_delete
    self.do_mkdir         = do_mkdir
    self.do_touch         = do_touch
    self.do_properties    = do_properties
    self.do_open_with     = do_open_with
    self.do_terminal      = do_terminal
    self.do_open_filter   = do_open_filter
    self.do_open_trash    = do_open_trash
    self.do_empty_trash   = do_empty_trash
    self.do_restore_from_trash = do_restore_from_trash
    self.toggle_bookmark  = toggle_bookmark
    self.is_in_trash      = is_in_trash
    self.on_key           = on_key
    self.set_view         = set_view
    self.update_selection_info = update_selection_info

    -- Destruye la tab: cancela timers y libera caches. Llamar
    -- antes de remover la tab del stack.
    self.destroy = function()
        if icons_view and icons_view.destroy then
            icons_view:destroy()
        end
    end

    -- Devuelve un snapshot serializable del estado de esta tab.
    -- Lo consume session.save al cerrar limpio.
    self.get_snapshot = function()
        return {
            path        = self.state.cwd,
            view_mode   = self.state.view_mode,
            sort_by     = self.state.sort_by,
            sort_desc   = self.state.sort_desc,
            show_hidden = self.state.show_hidden,
            filter      = self.state.filter,
        }
    end

    -- Start inicial
    self.state.history = { self.state.cwd }
    self.state.history_idx = 1
    refresh()

    return self
end

M.new = function(srv, theme, opts)
    return TabView.new(srv, theme, opts)
end

return M
