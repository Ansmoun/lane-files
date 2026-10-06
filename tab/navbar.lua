-- navbar: barra superior con dos filas.
--   Fila 1: menubar (Archivo, Editar, ...)
--   Fila 2: botones de navegación + breadcrumb o input editable
--
-- El breadcrumb tiene dos modos intercambiables mediante un Stack:
--   - "path": breadcrumb clickeable (default)
--   - "edit": TextInput para escribir una ruta
--
-- Doble click sobre cualquier segmento del breadcrumb abre el modo
-- edición con la ruta actual. Enter navega, Escape cancela.

local W        = require("lib.widgets")
local Area     = require("lib.area")
local cairo    = require("lib.cairo")
local icons    = require("lib.icons")
local Stack    = require("lib.widgets.stack")
local Breadcrumb = require("tab.breadcrumb")
local Menubar    = require("tab.menubar")

local M = {}

local NAV_H = 30

-- ── NavButton ─────────────────────────────────────────────────
local NavButton = setmetatable({}, { __index = Area })
NavButton.__index = NavButton

function NavButton.new(theme, icon_name, on_click, opts)
    opts = opts or {}
    local self = setmetatable(Area.new({}), NavButton)
    self._hover_visual = true
    self.on_click = on_click
    self.icon_name = icon_name
    self.size = opts.size or 20
    self.icon_surface = icons.surface("files/" .. icon_name, self.size)
    self.min_w, self.max_w = self.size + 6, self.size + 6
    self.min_h, self.max_h = NAV_H, NAV_H
    self.fg_color    = theme.fg_rgb     or { 0.9, 0.9, 0.9 }
    self.hover_color = theme.accent_rgb or { 1, 1, 1 }
    self.enabled     = true
    return self
end

function NavButton:set_enabled(v)
    v = v and true or false
    if self.enabled == v then return end
    self.enabled = v
    self:damage()
end

function NavButton:set_hover(v)
    v = v and true or false
    if self.hover == v then return end
    Area.set_hover(self, v)
end

function NavButton:draw(cr)
    if not self.icon_surface then return end
    local col
    if not self.enabled then
        col = { 0.35, 0.35, 0.35 }
    elseif self.hover then
        col = self.hover_color
    else
        col = self.fg_color
    end
    local x = self.x0 + (self:getWidth() - self.size) / 2
    local y = self.y0 + (self:getHeight() - self.size) / 2
    cairo.draw_surface_tinted(cr, self.icon_surface, x, y,
        self.size, self.size, col[1], col[2], col[3])
end

function NavButton:on_mouse_press(mx, my, button)
    if button == 1 and self.enabled and self.on_click then
        self.on_click()
    end
end

-- ── Constructor público ───────────────────────────────────────
-- handlers:
--   srv                    -- Server (para timer del breadcrumb)
--   back, forward, up, home
--   on_navigate(path)      -- navegación desde breadcrumb o input
--   menus, open_menu, close_menus
function M.new(theme, handlers)
    handlers = handlers or {}

    local btn_back = NavButton.new(theme, "back",    handlers.back)
    local btn_fwd  = NavButton.new(theme, "forward", handlers.forward)
    local btn_up   = NavButton.new(theme, "up",      handlers.up)
    local btn_home = NavButton.new(theme, "home",    handlers.home)

    local menubar = Menubar.new(theme,
        handlers.menus or {},
        handlers.open_menu,
        handlers.close_menus)

    -- Modo edición del breadcrumb: input alternativo en el Stack.
    local path_input
    local path_stack

    path_input = W.TextInput.new {
        text = "",
        font = "DejaVu Sans 10",
        padding_x = 8, padding_y = 3,
        min_height = 24, max_height = 24,
        color_bg = theme.bg_card,
        color_border = theme.separator,
        corner_radius = 4,
        color_text = theme.fg_rgb,
        color_cursor = theme.accent_rgb,
        placeholder = "/ruta/al/directorio",
        color_placeholder = theme.muted_rgb,
        on_submit = function(text)
            path_input:set_focused(false)
            path_stack:set_active("path")
            -- Normalizar la ruta antes de navegar. Sin esto, una
            -- entrada como "/home/" deja el cwd con barra final,
            -- lo que rompe comparaciones y hace que breadcrumb y
            -- sidebar resuelvan mal.
            local path = Breadcrumb.normalize_path(text or "")
            if path ~= "" and handlers.on_navigate then
                handlers.on_navigate(path)
            end
        end,
        on_cancel = function()
            path_input:set_focused(false)
            path_stack:set_active("path")
        end,
    }

    -- Breadcrumb con detección de doble click para entrar en
    -- modo edición.
    --
    -- La variable se declara primero y se asigna después. Si la
    -- declaración y la asignación fueran una sola línea, la
    -- closure on_double_click referenciaría breadcrumb como un
    -- global (nil en el momento de la evaluación de argumentos).
    local breadcrumb
    breadcrumb = Breadcrumb.new(theme, handlers.on_navigate, {
        srv = handlers.srv,
        on_double_click = function(path)
            breadcrumb:cancel_pending()
            path_input:set_text(path)
            path_stack:set_active("edit")
            path_input:set_focused(true)
        end,
    })

    path_stack = Stack.new {}
    path_stack:add("path", breadcrumb)
    path_stack:add("edit", path_input)
    path_stack.active = "path"

    -- Fila 1: menubar
    local menu_row = W.Group.new {
        orientation = "horizontal",
        spacing = 0,
        padding = 0,
        children = {
            { widget = menubar, weight = 0 },
            { widget = W.Text.new { text = "", min_width = 1 }, weight = 1 },
        },
    }

    -- Fila 2: nav buttons + stack (breadcrumb o input)
    local nav_row = W.Group.new {
        orientation = "horizontal",
        spacing = 4,
        padding = 4,
        children = {
            { widget = btn_back,   weight = 0 },
            { widget = btn_fwd,    weight = 0 },
            { widget = btn_up,     weight = 0 },
            { widget = btn_home,   weight = 0 },
            { widget = W.Text.new { text = "", min_width = 8 }, weight = 0 },
            { widget = path_stack, weight = 1 },
        },
    }

    local nav_bar = W.Group.new {
        orientation = "vertical",
        spacing = 0,
        padding = 0,
        children = {
            { widget = menu_row, weight = 0 },
            { widget = nav_row,  weight = 0 },
        },
    }

    return {
        widget     = nav_bar,
        back       = btn_back,
        forward    = btn_fwd,
        up         = btn_up,
        home       = btn_home,
        breadcrumb = breadcrumb,
        menubar    = menubar,
        path_input = path_input,
        path_stack = path_stack,
        -- Cancela el timer pendiente del breadcrumb. El consumidor
        -- lo llama cada vez que navega a otro sitio para que el
        -- click diferido no lo saque de donde está.
        cancel_pending = function()
            breadcrumb:cancel_pending()
        end,
    }
end

return M
