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
            if item and type(item) == "table"
               and item.path and item.name then
                state.selected_idx = idx or 1
                open_selected()
            end
        end,
    }

    list.draw_row = row.make_draw_row(theme, function(idx)
        return idx == state.selected_idx
    end, ROW_H)

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
        local txt
        if state.filter ~= "" then
            txt = string.format("%d de %d (filtro)", n, #all)
        elseif n == 1 then
            txt = "1 elemento"
        else
            txt = string.format("%d elementos", n)
        end
        status_view.count:set_text(txt)

        redraw()
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
