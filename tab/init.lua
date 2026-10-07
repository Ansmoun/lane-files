-- tab: contenedor del gestor de archivos con pestañas.
--
-- Estructura:
--   ┌──────────────────────────────────────┐
--   │ TabsBar  [tab1][tab2][+]             │
--   ├──────────────────────────────────────┤
--   │ Menubar  Archivo Editar Ver ...      │
--   │ Nav      [<][>][^][🏠] breadcrumb... │
--   ├──────────────────────────────────────┤
--   │ Sidebar  │  Stack de TabView (activa)│
--   ├──────────────────────────────────────┤
--   │ Status   elementos  ·  seleccionado  │
--   └──────────────────────────────────────┘
--
-- Una TabView encapsula el estado (cwd, selección, historial) y
-- las dos vistas intercambiables (lista e iconos). El navbar,
-- sidebar y status son compartidos: se actualizan cuando cambia
-- el cwd o la selección de la pestaña activa.

local W        = require("lib.widgets")
local log      = require("lib.log")
local Stack    = require("lib.widgets.stack")

local TabView    = require("tab.tab_view")
local TabsBar    = require("tab.tabs_bar")
local navbar     = require("tab.navbar")
local Sidebar    = require("tab.sidebar")
local status     = require("tab.status")
local Divider    = require("tab.divider")
local icons      = require("tab.icons")
local config     = require("tab.config")

local M = {}

-- ── Gestor de pestañas ─────────────────────────────────────
local Tabs = {}
Tabs.__index = Tabs

local function new_tabs(opts)
    local self = setmetatable({}, Tabs)
    self.list = {}       -- array de { id, view }
    self.by_id = {}
    self.active_id = nil
    self._next_id = 1
    self.opts = opts or {}
    return self
end

function Tabs:add(initial_path)
    local id = "tab-" .. self._next_id
    self._next_id = self._next_id + 1
    local name = initial_path
        and (initial_path:match("[^/]+$") or initial_path)
        or "Inicio"

    local view = TabView.new(self.srv, self.theme, {
        initial_path    = initial_path,
        view_mode       = self.opts.view_mode,
        icon_size       = self.opts.icon_size,
        on_cwd_change   = function(cwd) self:_on_cwd_change(id, cwd) end,
        on_selection_change = function(st)
            self:_on_selection_change(id, st)
        end,
        on_view_mode_change = function(mode)
            config.set("view_mode", mode)
        end,
        on_icon_size_change = function(sz)
            config.set("icons_size", sz)
        end,
        on_bookmarks_change = function()
            self:_on_bookmarks_change()
        end,
        get_parent_window = function() return self.window end,
    })
    view.tab_id = id
    view.tab_name = name

    local entry = { id = id, view = view, name = name }
    self.list[#self.list + 1] = entry
    self.by_id[id] = entry
    return entry
end

function Tabs:remove(id)
    local idx
    for i, e in ipairs(self.list) do
        if e.id == id then idx = i; break end
    end
    if not idx then return end
    table.remove(self.list, idx)
    self.by_id[id] = nil
end

function Tabs:count() return #self.list end

function Tabs:get(id)
    return self.by_id[id]
end

function Tabs:active()
    local e = self.active_id and self.by_id[self.active_id]
    return e and e.view or nil
end

function Tabs:set_active(id, callbacks)
    if not self.by_id[id] then return end
    self.active_id = id
    -- Notificar a la UI compartida
    local entry = self.by_id[id]
    if callbacks and callbacks.on_activate then
        callbacks.on_activate(entry.view)
    end
end

-- Renombra una pestaña a partir del cwd actual.
function Tabs:_on_cwd_change(id, cwd)
    local e = self.by_id[id]
    if not e then return end
    local name = cwd:match("[^/]+$") or "/"
    if name == "" then name = "/" end
    if e.name ~= name then
        e.name = name
        e.view.tab_name = name
        if self.on_tab_renamed then
            self.on_tab_renamed()
        end
    end
    -- Si es la tab activa, refrescar navbar y sidebar.
    if id == self.active_id and self.on_active_changed then
        self.on_active_changed(e.view)
    end
end

function Tabs:_on_selection_change(id, st)
    if id == self.active_id and self.on_active_selection then
        self.on_active_selection(st)
    end
end

function Tabs:_on_bookmarks_change()
    if self.on_bookmarks_changed then
        self.on_bookmarks_changed()
    end
end

-- ── Constructor público ────────────────────────────────────
function M.new(srv, theme, opts)
    opts = opts or {}
    local self = {}

    -- Estado persistido
    local saved_view = config.get("view_mode", "list")
    if saved_view ~= "list" and saved_view ~= "icons" then
        saved_view = "list"
    end
    local saved_size = config.get("icons_size", nil)
    if type(saved_size) ~= "number" then saved_size = nil end

    local initial_path = opts.initial_path or os.getenv("HOME")
    local pick_mode    = opts.pick_mode       -- nil | "file" | "dir"
    local on_pick      = opts.on_pick         -- function(paths)
    local on_cancel    = opts.on_cancel       -- function()

    local tabs = new_tabs({
        view_mode = saved_view,
        icon_size = saved_size,
    })
    tabs.srv = srv
    tabs.theme = theme

    -- Referencias a la UI compartida
    local tabs_bar
    local navbar_view
    local sidebar_view
    local status_view
    local view_stack

    -- La Window se asigna cuando el contenedor se monta. Los
    -- callbacks get_parent_window la usan.
    local _window
    -- Forward: el layout raíz la intercepta más abajo.
    local set_window
    tabs.window = nil

    -- ── Crear la primera pestaña ────────────────────────────
    local first = tabs:add(initial_path)
    tabs.active_id = first.id

    -- ── Stack de TabView ────────────────────────────────────
    view_stack = Stack.new {}
    view_stack:add(first.id, first.view.widget)
    view_stack.active = first.id

    -- ── Callbacks de navegación que van a la tab activa ────
    local function active()
        return tabs:active()
    end

    local function go_back()
        local v = active(); if v then v.go_back() end
    end
    local function go_forward()
        local v = active(); if v then v.go_forward() end
    end
    local function go_up()
        local v = active(); if v then v.go_up() end
    end
    local function go_home()
        local v = active(); if v then v.go_home() end
    end
    local function do_copy()
        local v = active(); if v then v.do_copy() end
    end
    local function do_cut()
        local v = active(); if v then v.do_cut() end
    end
    local function do_paste()
        local v = active(); if v then v.do_paste() end
    end
    local function do_rename()
        local v = active(); if v then v.do_rename() end
    end
    local function do_trash()
        local v = active(); if v then v.do_trash() end
    end
    local function do_delete()
        local v = active(); if v then v.do_delete() end
    end
    local function do_mkdir()
        local v = active(); if v then v.do_mkdir() end
    end
    local function do_touch()
        local v = active(); if v then v.do_touch() end
    end
    local function do_properties()
        local v = active(); if v then v.do_properties() end
    end
    local function do_open_with()
        local v = active(); if v then v.do_open_with() end
    end
    local function do_terminal()
        local v = active(); if v then v.do_terminal() end
    end
    local function do_open_filter()
        local v = active(); if v then v.do_open_filter() end
    end
    local function do_open_trash()
        local v = active(); if v then v.do_open_trash() end
    end
    local function do_empty_trash()
        local v = active(); if v then v.do_empty_trash() end
    end
    local function do_restore_from_trash()
        local v = active(); if v then v.do_restore_from_trash() end
    end
    local function toggle_bookmark()
        local v = active(); if v then v.toggle_bookmark() end
    end
    local function refresh()
        local v = active(); if v then v.refresh() end
    end

    local function redraw_all()
        if _window then _window:damage_all() end
    end

    -- ── Barra de pestañas ───────────────────────────────────
    local function sync_tabs_bar()
        local list = {}
        for _, e in ipairs(tabs.list) do
            list[#list + 1] = { id = e.id, name = e.name }
        end
        tabs_bar:set_tabs(list, tabs.active_id)
        -- set_tabs ya invoca invalidate_layout internamente. El
        -- layout raíz se re-ejecuta en el próximo ciclo del event
        -- loop y los botones reciben su rect.
    end

    local function switch_to(id)
        if not tabs.by_id[id] then return end
        tabs.active_id = id
        view_stack:set_active(id)
        local e = tabs.by_id[id]
        -- Sincronizar navbar (breadcrumb + botones) y sidebar con
        -- la nueva tab.
        navbar_view.breadcrumb:set_path(e.view.state.cwd)
        navbar_view.back:set_enabled(e.view.state:can_back())
        navbar_view.forward:set_enabled(e.view.state:can_forward())
        sidebar_view:set_active_path(e.view.state.cwd)
        tabs_bar.active_id = id
        sync_tabs_bar()
        if e.view.update_selection_info then
            e.view.update_selection_info()
        end
        redraw_all()
    end

    local function close_tab(id)
        if tabs:count() <= 1 then
            -- Última pestaña: cerrar la ventana.
            if _window then _window:close("última pestaña cerrada") end
            return
        end
        tabs:remove(id)
        view_stack:remove(id)
        if tabs.active_id == id then
            -- Activar la primera disponible
            local next_id = tabs.list[1] and tabs.list[1].id
            if next_id then switch_to(next_id) end
        else
            sync_tabs_bar()
        end
    end

    local function new_tab(path)
        local entry = tabs:add(path or (active() and active().state.cwd)
            or os.getenv("HOME"))
        view_stack:add(entry.id, entry.view.widget)
        switch_to(entry.id)
    end

    tabs.on_tab_renamed = function() sync_tabs_bar() end
    tabs.on_active_changed = function(v)
        navbar_view.breadcrumb:set_path(v.state.cwd)
        navbar_view.back:set_enabled(v.state:can_back())
        navbar_view.forward:set_enabled(v.state:can_forward())
        sidebar_view:set_active_path(v.state.cwd)
    end
    tabs.on_active_selection = function(st)
        -- Actualizar status con la info del seleccionado.
        local entry = st:selected()
        if entry then
            local parts = { entry.name }
            if entry.is_dir then
                parts[#parts + 1] = "Carpeta"
            else
                parts[#parts + 1] = icons.human_size(entry.size)
            end
            parts[#parts + 1] = icons.human_date(entry.mtime)
            if not entry.is_dir then
                parts[#parts + 1] = icons.type_label(entry)
            end
            status_view:set_info(table.concat(parts, "  ·  "))
        else
            status_view:set_info("")
        end
    end
    tabs.on_bookmarks_changed = function()
        sidebar_view:refresh()
    end

    tabs_bar = TabsBar.new(theme, {
        on_select = switch_to,
        on_close  = close_tab,
        on_new    = new_tab,
    })

    -- ── Modo selector ───────────────────────────────────────
    -- En modo pick, el usuario puede aceptar la selección actual
    -- con Enter, doble click o el botón Aceptar. La ruta se pasa
    -- al callback on_pick del consumidor.
    local function do_pick()
        if not pick_mode then return end
        local v = active()
        if not v then return end
        local paths = {}
        -- En modo dir, si hay un directorio seleccionado, se
        -- devuelve ese directorio. Si no, el cwd.
        if pick_mode == "dir" then
            local e = v.state:selected()
            if e and e.is_dir then
                paths[1] = e.path
            else
                paths[1] = v.state.cwd
            end
        else
            -- Modo file: devolver todos los archivos seleccionados
            -- que no sean directorios. Si el seleccionado es
            -- directorio, navegar en lugar de aceptar.
            local sel = v.state:selected_paths()
            for _, p in ipairs(sel) do
                local e = nil
                for _, ent in ipairs(v.state.entries) do
                    if ent.path == p then e = ent; break end
                end
                if e and not e.is_dir then
                    paths[#paths + 1] = p
                end
            end
            if #paths == 0 then
                -- Ningún archivo elegible. No hacer nada.
                return
            end
        end
        if on_pick then on_pick(paths) end
    end

    local function do_cancel_pick()
        if on_cancel then on_cancel() end
    end

    -- ── Sidebar ─────────────────────────────────────────────
    sidebar_view = Sidebar.new(theme,
        function(path)
            local v = active()
            if v then v.navigate_to(path, true) end
        end,
        function(entry, mx, my)
            -- Click derecho en el sidebar.
            local items = {
                { label = "Ir a " .. entry.label,
                  on_click = function()
                      local v = active()
                      if v then v.navigate_to(entry.path, true) end
                  end },
                { label = "Abrir en nueva pestaña",
                  on_click = function() new_tab(entry.path) end },
            }
            if entry.icon == "user-trash" then
                items[#items + 1] = { sep = true }
                items[#items + 1] = {
                    label = "Vaciar papelera",
                    color = { 0.9, 0.3, 0.3 },
                    on_click = function() do_empty_trash() end,
                }
            end
            local ContextMenu_local = require("lib.widgets.contextmenu")
            local cm = ContextMenu_local.new(srv, _window, theme)
            cm:show(mx, my, items)
        end)

    -- ── Status ──────────────────────────────────────────────
    status_view = status.new(theme)

    -- ── Menús ───────────────────────────────────────────────
    local function menu_open_context(anchor, items, on_close)
        local ContextMenu_local = require("lib.widgets.contextmenu")
        local cm = ContextMenu_local.new(srv, _window, theme)
        -- Rect del ancla en coordenadas de la ventana padre. Si el
        -- usuario hace click sobre el mismo botón que abrió el
        -- menú, el click se consume aquí y solo cierra.
        local ar = nil
        if anchor and anchor.x0 and anchor.x1 then
            ar = {
                x = anchor.x0,
                y = anchor.y0,
                w = anchor.x1 - anchor.x0,
                h = anchor.y1 - anchor.y0,
            }
        end
        cm:show(anchor.x0, anchor.y1 + 2, items, {
            on_close = function() if on_close then on_close() end end,
            anchor_rect = ar,
        })
    end

    local function set_view(mode)
        local v = active()
        if v then v.set_view(mode) end
    end

    local function is_in_trash()
        local v = active()
        return v and v.is_in_trash() or false
    end

    local menus = {
        { label = "Archivo", build = function() return {
            { label = "Nueva pestaña",
              on_click = function() new_tab() end },
            { sep = true },
            { label = "Nueva carpeta", on_click = do_mkdir },
            { label = "Nuevo archivo", on_click = do_touch },
            { sep = true },
            { label = "Cerrar pestaña",
              on_click = function()
                  if tabs.active_id then close_tab(tabs.active_id) end
              end },
            { label = "Cerrar ventana",
              on_click = function()
                  if _window then _window:close("menu") end
              end },
        } end },
        { label = "Editar", build = function()
            local v = active()
            local sel_n = v and v.state:selection_count() or 0
            local paths = v and v.state:selected_paths() or {}
            return {
                { label = "Cortar", on_click = do_cut,
                  enabled = #paths > 0 },
                { label = "Copiar", on_click = do_copy,
                  enabled = #paths > 0 },
                { label = "Pegar", on_click = do_paste,
                  enabled = require("tab.clipboard").has_content() },
                { sep = true },
                { label = "Renombrar", on_click = do_rename,
                  enabled = v and v.state:selected() ~= nil },
                { label = "Eliminar", on_click = do_trash,
                  enabled = #paths > 0 },
                { sep = true },
                { label = "Seleccionar todo", on_click = function()
                    if v then v.state:select_all(); v.redraw() end
                end },
                { label = "Filtrar...", on_click = do_open_filter },
            }
        end },
        { label = "Ver", build = function()
            local v = active()
            local mode = v and v.state.view_mode or "list"
            return {
                { label = "Vista de lista",
                  on_click = function() set_view("list") end,
                  enabled = mode ~= "list" },
                { label = "Vista de iconos",
                  on_click = function() set_view("icons") end,
                  enabled = mode ~= "icons" },
                { sep = true },
                { label = (v and v.state.show_hidden
                          and "Ocultar ocultos" or "Mostrar ocultos"),
                  on_click = function()
                      if v then
                          v.state.show_hidden = not v.state.show_hidden
                          v.refresh()
                      end
                  end },
                { sep = true },
                { label = "Refrescar", on_click = refresh },
            }
        end },
        { label = "Ir", build = function()
            local v = active()
            local cb = v and v.state:can_back() or false
            local cf = v and v.state:can_forward() or false
            return {
                { label = "Atrás", on_click = go_back, enabled = cb },
                { label = "Adelante", on_click = go_forward, enabled = cf },
                { label = "Arriba", on_click = go_up },
                { label = "Inicio", on_click = go_home },
                { sep = true },
                { label = "Papelera", on_click = do_open_trash },
                { sep = true },
                { label = "Nueva pestaña aquí",
                  on_click = function()
                      new_tab(v and v.state.cwd or nil)
                  end },
            }
        end },
        { label = "Marcadores", build = function()
            local bookmarks = require("tab.bookmarks")
            local items = {}
            for _, b in ipairs(bookmarks.list()) do
                items[#items + 1] = {
                    label = b.label,
                    on_click = function()
                        local v = active()
                        if v then v.navigate_to(b.path, true) end
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
        { label = "Herramientas", build = function()
            local v = active()
            local items = {
                { label = "Abrir terminal aquí",
                  on_click = do_terminal },
                { label = "Propiedades",
                  on_click = do_properties,
                  enabled = v and v.state:selected() ~= nil },
            }
            if is_in_trash() then
                items[#items + 1] = { sep = true }
                items[#items + 1] = {
                    label = "Restaurar seleccionado",
                    on_click = do_restore_from_trash,
                    enabled = v and v.state:selected() ~= nil,
                }
                items[#items + 1] = {
                    label = "Vaciar papelera",
                    on_click = do_empty_trash,
                }
            end
            return items
        end },
    }

    -- ── Navbar ──────────────────────────────────────────────
    navbar_view = navbar.new(theme, {
        srv     = srv,
        back    = go_back,
        forward = go_forward,
        up      = go_up,
        home    = go_home,
        on_navigate = function(path)
            local v = active()
            if v then v.navigate_to(path, true) end
        end,
        menus = menus,
        open_menu = menu_open_context,
        close_menus = function() end,
        -- Modo compacto: un solo botón hamburguesa en lugar de la
        -- fila completa de menús. Libera ~400px de ancho.
        compact_menubar = true,
    })

    -- ── Layout ──────────────────────────────────────────────
    -- Fila superior: hamburguesa, espacio, pestañas, spacer
    -- absorbente. La hamburguesa es un cuadro compacto de 34px.
    -- Después un pequeño hueco (8px) y a continuación las
    -- pestañas alineadas a la izquierda.
    local tab_menu_row = W.Group.new {
        orientation = "horizontal",
        spacing = 0,
        padding = 0,
        children = {
            { widget = navbar_view.menubar, weight = 0 },
            { widget = W.Text.new { text = "", min_width = 8 }, weight = 0 },
            { widget = tabs_bar,            weight = 0 },
            { widget = W.Text.new { text = "", min_width = 1 }, weight = 1 },
        },
    }

    local content_row = W.Group.new {
        orientation = "horizontal",
        spacing = 0,
        padding = 0,
        children = {
            { widget = sidebar_view, weight = 0 },
            { widget = Divider.new_vertical(theme), weight = 0 },
            { widget = view_stack,   weight = 1 },
        },
    }

    -- En modo pick, construir un status bar alternativo con los
    -- botones Aceptar/Cancelar a la derecha.
    local pick_bar = nil
    if pick_mode then
        local btn_cancel = W.Button.new {
            text = "Cancelar",
            font = "DejaVu Sans 10",
            padding_x = 16, padding_y = 4,
            corner_radius = 4,
            color_normal  = { 0.22, 0.22, 0.28 },
            color_hover   = { 0.30, 0.30, 0.38 },
            color_pressed = { 0.15, 0.15, 0.20 },
            color_border  = { 0.42, 0.42, 0.52 },
            color_text    = { 0.95, 0.95, 0.95 },
            on_click = do_cancel_pick,
        }
        local btn_ok = W.Button.new {
            text = "Aceptar",
            font = "DejaVu Sans Bold 10",
            padding_x = 16, padding_y = 4,
            corner_radius = 4,
            color_normal  = { 0.30, 0.55, 0.35 },
            color_hover   = { 0.38, 0.65, 0.42 },
            color_pressed = { 0.22, 0.42, 0.28 },
            color_border  = { 0.45, 0.65, 0.50 },
            color_text    = { 0.95, 0.95, 0.95 },
            on_click = do_pick,
        }
        pick_bar = W.Group.new {
            orientation = "horizontal",
            spacing = 8,
            padding = 6,
            children = {
                { widget = status_view.widget, weight = 1 },
                { widget = btn_cancel, weight = 0 },
                { widget = btn_ok,     weight = 0 },
            },
        }
    end

    local layout
    if pick_mode then
        -- Sin tab menu row, sin tabs bar. El navbar sigue con
        -- breadcrumb y navegación.
        layout = W.Group.new {
            orientation = "vertical",
            spacing = 0,
            padding = 0,
            children = {
                { widget = navbar_view.widget, weight = 0 },
                { widget = Divider.new(theme), weight = 0 },
                { widget = content_row,        weight = 1 },
                { widget = Divider.new(theme), weight = 0 },
                { widget = pick_bar,           weight = 0 },
            },
        }
    else
        layout = W.Group.new {
            orientation = "vertical",
            spacing = 0,
            padding = 0,
            children = {
                { widget = tab_menu_row,       weight = 0 },
                { widget = Divider.new(theme), weight = 0 },
                { widget = navbar_view.widget, weight = 0 },
                { widget = Divider.new(theme), weight = 0 },
                { widget = content_row,        weight = 1 },
                { widget = Divider.new(theme), weight = 0 },
                { widget = status_view.widget, weight = 0 },
            },
        }
    end

    -- Interceptar set_window del layout raíz. Window:set_root
    -- llama a area:set_window(win) sobre el widget raíz (este
    -- Group). La metatabla de Group propaga el window a los
    -- hijos, pero nuestra función set_window (que actualiza tabs,
    -- sidebar y demás) nunca se llama. Sin esta intercepción,
    -- _window queda nil y los menús que lo usan crashean.
    local _orig_group_set_window = layout.set_window
    layout.set_window = function(self2, win)
        if _orig_group_set_window then
            _orig_group_set_window(self2, win)
        else
            self2.window = win
            for _, c in ipairs(self2.children or {}) do
                if c.set_window then c:set_window(win)
                else c.window = win end
            end
        end
        set_window(win)
    end

    -- ── Ciclo de vida ───────────────────────────────────────
    set_window = function(win)
        _window = win
        tabs.window = win
        tabs_bar.window = win
        sidebar_view:set_window(win)
        if navbar_view.menubar then
            navbar_view.menubar.window = win
        end
        if navbar_view.breadcrumb then
            navbar_view.breadcrumb.window = win
        end
        for _, e in ipairs(tabs.list) do
            if e.view.list then e.view.list.window = win end
            if e.view.icons_view then
                e.view.icons_view.window = win
            end
        end
        -- Sincronizar breadcrumb y sidebar con la tab activa
        local e = tabs.by_id[tabs.active_id]
        if e then
            navbar_view.breadcrumb:set_path(e.view.state.cwd)
            sidebar_view:set_active_path(e.view.state.cwd)
        end
    end

    local function start()
        sync_tabs_bar()
        local e = tabs.by_id[tabs.active_id]
        if e then
            navbar_view.breadcrumb:set_path(e.view.state.cwd)
            sidebar_view:set_active_path(e.view.state.cwd)
        end
    end

    local function on_key(key)
        -- Modo selector: interceptar Enter y Escape antes que el
        -- resto de la cadena.
        if pick_mode and key.pressed and not key.mods.ctrl
           and not key.mods.alt and not key.mods.super then
            if key.name == "Return" or key.name == "KP_Enter" then
                do_pick()
                return true
            end
            if key.name == "Escape" then
                do_cancel_pick()
                return true
            end
        end

        -- Atajos globales del contenedor (no de la tab).
        if key.pressed and key.mods.ctrl then
            if key.name == "t" and not key.mods.shift then
                new_tab()
                return true
            end
            if key.name == "w" then
                if tabs.active_id then close_tab(tabs.active_id) end
                return true
            end
            if key.name == "Tab" then
                -- Ctrl+Tab: siguiente pestaña.
                if tabs:count() <= 1 then return true end
                local idx
                for i, e in ipairs(tabs.list) do
                    if e.id == tabs.active_id then idx = i; break end
                end
                local nxt = (idx % tabs:count()) + 1
                switch_to(tabs.list[nxt].id)
                return true
            end
        end
        -- Delegar a la tab activa.
        local v = active()
        if v and v.on_key then
            return v.on_key(key)
        end
        return false
    end

    return {
        widget    = layout,
        set_window = set_window,
        start     = start,
        stop      = function() end,
        on_key    = on_key,
    }
end

return M
