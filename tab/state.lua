-- state: estado de la vista del gestor de archivos.
-- Mantiene cwd, historial, filtro, visibilidad de ocultos y
-- selección. No conoce widgets ni Cairo. Testeable en aislamiento.

local M = {}

local State = {}
State.__index = State

function M.new(opts)
    opts = opts or {}
    local self = setmetatable({}, State)
    self.cwd          = opts.initial_path or os.getenv("HOME")
    self.entries      = {}      -- entradas visibles tras filtro
    self.history      = { self.cwd }
    self.history_idx  = 1
    self.show_hidden  = false
    self.filter       = ""
    self.selected_idx = 1       -- índice 1-based en entries (foco)
    -- Conjunto de paths seleccionados. Si está vacío, las
    -- operaciones actúan sobre la fila con foco (selected_idx).
    -- Si tiene elementos, actúan sobre el conjunto.
    self.selected_set = {}
    -- Ancla para Shift+click: índice del último click simple.
    self.anchor_idx   = 1
    return self
end

function State:set_cwd(path, push_history)
    if path == self.cwd then return end
    self.cwd = path
    self.filter = ""
    self.selected_idx = 1
    self.anchor_idx = 1
    self.selected_set = {}
    if push_history ~= false then
        -- Truncar el futuro del historial
        while #self.history > self.history_idx do
            table.remove(self.history)
        end
        self.history[#self.history + 1] = path
        self.history_idx = #self.history
    end
end

function State:can_back()
    return self.history_idx > 1
end

function State:can_forward()
    return self.history_idx < #self.history
end

function State:go_back()
    if not self:can_back() then return false end
    self.history_idx = self.history_idx - 1
    self.cwd = self.history[self.history_idx]
    self.filter = ""
    self.selected_idx = 1
    self.anchor_idx = 1
    self.selected_set = {}
    return true
end

function State:go_forward()
    if not self:can_forward() then return false end
    self.history_idx = self.history_idx + 1
    self.cwd = self.history[self.history_idx]
    self.filter = ""
    self.selected_idx = 1
    self.anchor_idx = 1
    self.selected_set = {}
    return true
end

function State:set_entries(entries)
    self.entries = entries or {}
    if self.selected_idx > #self.entries then
        self.selected_idx = #self.entries
    end
    if self.selected_idx < 1 and #self.entries > 0 then
        self.selected_idx = 1
    end
end

function State:selected()
    return self.entries[self.selected_idx]
end

function State:move_selection(delta)
    local n = #self.entries
    if n == 0 then return end
    local new_idx = self.selected_idx + delta
    if new_idx < 1 then new_idx = 1 end
    if new_idx > n then new_idx = n end
    self.selected_idx = new_idx
    self.anchor_idx = new_idx
    -- Las flechas mueven solo el foco, no la multi-selección.
    -- Si el conjunto tiene elementos, se mantiene intacto hasta
    -- que el usuario haga click simple o Escape.
    if next(self.selected_set) == nil then
        local e = self.entries[new_idx]
        self.selected_set = {}
        if e then self.selected_set[e.path] = true end
    end
end

function State:select_first()
    if #self.entries > 0 then self.selected_idx = 1 end
end

function State:select_last()
    if #self.entries > 0 then self.selected_idx = #self.entries end
end

-- ── Multi-selección ─────────────────────────────────────────────

-- Click simple: selecciona solo esa fila, limpia el conjunto.
function State:select_single(idx)
    if not idx or idx < 1 or idx > #self.entries then return end
    self.selected_idx = idx
    self.anchor_idx = idx
    self.selected_set = {}
    local e = self.entries[idx]
    if e then self.selected_set[e.path] = true end
end

-- Ctrl+click: alterna la fila en el conjunto sin mover el foco.
function State:toggle_selection(idx)
    if not idx or idx < 1 or idx > #self.entries then return end
    local e = self.entries[idx]
    if not e then return end
    if self.selected_set[e.path] then
        self.selected_set[e.path] = nil
    else
        self.selected_set[e.path] = true
    end
    self.anchor_idx = idx
end

-- Shift+click: selecciona el rango entre el ancla y idx, sin
-- borrar lo que ya estaba seleccionado con Ctrl+click.
function State:select_range(idx)
    if not idx or idx < 1 or idx > #self.entries then return end
    local a = self.anchor_idx or self.selected_idx
    local b = idx
    if a > b then a, b = b, a end
    for i = a, b do
        local e = self.entries[i]
        if e then self.selected_set[e.path] = true end
    end
    self.selected_idx = idx
end

-- Ctrl+A: selecciona todo lo visible.
function State:select_all()
    self.selected_set = {}
    for _, e in ipairs(self.entries) do
        self.selected_set[e.path] = true
    end
end

-- Devuelve true si el path está en el conjunto.
function State:is_selected(path)
    return self.selected_set[path] == true
end

-- Número de elementos seleccionados.
function State:selection_count()
    local n = 0
    for _ in pairs(self.selected_set) do n = n + 1 end
    return n
end

-- Devuelve una lista de paths seleccionados. Si el conjunto está
-- vacío, devuelve el path de la fila con foco (si hay alguna).
function State:selected_paths()
    local out = {}
    for path, _ in pairs(self.selected_set) do
        out[#out + 1] = path
    end
    if #out == 0 then
        local e = self.entries[self.selected_idx]
        if e then out[1] = e.path end
    end
    table.sort(out)
    return out
end

return M
