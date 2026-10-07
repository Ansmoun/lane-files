-- context: menú contextual de click derecho.
-- Construye la lista de items según el objeto bajo el cursor
-- (entrada, fondo) y las acciones disponibles en el portapapeles.

local M = {}

-- Construye los items del menú para una entrada concreta.
-- Devuelve array de tablas compatibles con W.ContextMenu.
--
-- opts:
--   on_open       -- function() abre la entrada
--   on_open_with  -- function() abre con diálogo (opcional, futuro)
--   on_copy       -- function()
--   on_cut        -- function()
--   on_rename     -- function()
--   on_trash      -- function()
--   on_delete     -- function()
--   on_copy_path  -- function()
--   on_properties -- function() (futuro)
--   can_paste     -- bool, hay algo en el portapapeles
--   is_dir        -- bool, la entrada es un directorio
function M.for_entry(opts)
    local items = {}

    items[#items + 1] = {
        label = "Abrir",
        on_click = opts.on_open,
    }
    if opts.is_dir and opts.on_open_new_tab then
        items[#items + 1] = {
            label = "Abrir en nueva ventana",
            on_click = opts.on_open_new_tab,
        }
    end

    items[#items + 1] = { sep = true }

    items[#items + 1] = {
        label = "Copiar",
        on_click = opts.on_copy,
    }
    items[#items + 1] = {
        label = "Cortar",
        on_click = opts.on_cut,
    }
    items[#items + 1] = {
        label = "Renombrar",
        on_click = opts.on_rename,
    }

    items[#items + 1] = { sep = true }

    -- "Abrir con..." solo tiene sentido para archivos, no para
    -- carpetas. En una carpeta la acción natural es navegar, no
    -- elegir aplicación.
    if not opts.is_dir then
        items[#items + 1] = {
            label = "Abrir con...",
            on_click = opts.on_open_with,
        }
    end
    items[#items + 1] = { sep = true }
    items[#items + 1] = {
        label = "Copiar ruta",
        on_click = opts.on_copy_path,
    }
    items[#items + 1] = {
        label = "Propiedades",
        on_click = opts.on_properties,
    }

    items[#items + 1] = { sep = true }

    items[#items + 1] = {
        label = "Enviar a papelera",
        color = { 0.9, 0.5, 0.3 },
        on_click = opts.on_trash,
    }
    items[#items + 1] = {
        label = "Borrar permanentemente",
        color = { 0.9, 0.3, 0.3 },
        on_click = opts.on_delete,
    }

    return items
end

-- Construye los items para el fondo (sin entrada bajo el cursor).
function M.for_background(opts)
    local items = {}

    items[#items + 1] = {
        label = "Pegar",
        enabled = opts.can_paste and true or false,
        on_click = opts.on_paste,
    }

    items[#items + 1] = { sep = true }

    items[#items + 1] = {
        label = "Crear carpeta",
        on_click = opts.on_mkdir,
    }
    items[#items + 1] = {
        label = "Crear archivo",
        on_click = opts.on_touch,
    }

    items[#items + 1] = { sep = true }

    items[#items + 1] = {
        label = "Abrir terminal aquí",
        on_click = opts.on_terminal,
    }

    items[#items + 1] = {
        label = "Refrescar",
        on_click = opts.on_refresh,
    }

    return items
end

return M
