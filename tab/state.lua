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
    self.selected_idx = 1       -- índice 1-based en entries
    return self
end

function State:set_cwd(path, push_history)
    if path == self.cwd then return end
    self.cwd = path
    self.filter = ""
    self.selected_idx = 1
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
    return true
end

function State:go_forward()
    if not self:can_forward() then return false end
    self.history_idx = self.history_idx + 1
    self.cwd = self.history[self.history_idx]
    self.filter = ""
    self.selected_idx = 1
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
end

function State:select_first()
    if #self.entries > 0 then self.selected_idx = 1 end
end

function State:select_last()
    if #self.entries > 0 then self.selected_idx = #self.entries end
end

return M
