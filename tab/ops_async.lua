-- ops_async: copias/movidas en background con reporte de progreso.
--
-- Escribe un script shell temporal que itera los pares (src, dst),
-- ejecuta cp/mv por cada uno y escribe el progreso en un archivo
-- de estado. Un handle en Lua expone :tick() para leer el estado,
-- :is_done() para saber si termino, y :cancel() para abortar.
--
-- El script corre con setsid -f: sesion nueva, sin terminal, sin
-- heredar el event loop de la app. La UI queda totalmente libre.
--
-- API:
--   handle, err = M.start(mode, paths, dst_dir)
--       mode = "copy" | "move"
--       paths = array de paths origen
--       dst_dir = directorio destino
--   handle:tick()      -> refresca el estado y lo devuelve
--   handle:status()    -> { done_items, total_items, bytes_done,
--                           total_bytes, current, done, errors }
--   handle:is_done()   -> bool
--   handle:cancel()    -> aborta y limpia

local M = {}

local function shq(s)
    return "'" .. tostring(s):gsub("'", "'\\''") .. "'"
end

local function basename(p)
    return p:match("[^/]+$") or p
end

local function join(d, n)
    if d == "/" then return "/" .. n end
    return d .. "/" .. n
end

local function exists(p)
    local f = io.open(p, "r")
    if f then f:close() return true end
    return false
end

local function is_dir(p)
    local h = io.popen("test -d " .. shq(p) .. " && echo Y")
    if not h then return false end
    local out = h:read("*l")
    h:close()
    return out == "Y"
end

-- Nombre unico en dst_dir. Mismo algoritmo que ops.lua (archivo
-- (1).ext, (2).ext, ...). Se calcula aca, ANTES de lanzar el
-- script, para que el shell no tenga que hacerlo.
local function unique_dest(dst_dir, name)
    local candidate = join(dst_dir, name)
    if not exists(candidate) then return candidate end
    local base, ext = name:match("^(.*)(%.[^.]+)$")
    if not base then base = name; ext = "" end
    for i = 1, 100 do
        candidate = join(dst_dir, string.format("%s (%d)%s", base, i, ext))
        if not exists(candidate) then return candidate end
    end
    return nil
end

local function du_bytes(p)
    local h = io.popen("du -sb " .. shq(p) .. " 2>/dev/null | awk '{print $1}'")
    if not h then return 0 end
    local n = tonumber(h:read("*l")) or 0
    h:close()
    return n
end

-- opts (opcional):
--   overwrite = true  -> pisa los archivos existentes en dst
--                        (cp -f / mv -f, mismo nombre).
--   overwrite = false (default) -> unique_dest (archivo (1).ext).
function M.start(mode, paths, dst_dir, opts)
    opts = opts or {}
    if not dst_dir or dst_dir == "" then
        return nil, "directorio destino vacio"
    end
    if not is_dir(dst_dir) then
        return nil, "destino no es directorio: " .. dst_dir
    end
    if mode ~= "copy" and mode ~= "move" then
        return nil, "modo invalido: " .. tostring(mode)
    end

    -- 1) Resolver pares (src, dst) y totales.
    local pairs_ = {}
    local total_bytes = 0
    for _, src in ipairs(paths) do
        local name = basename(src)
        local dst
        if opts.overwrite then
            -- Pisar: usar el nombre original.
            if dst_dir == "/" then dst = "/" .. name
            else dst = dst_dir .. "/" .. name end
        else
            dst = unique_dest(dst_dir, name)
            if not dst then
                return nil, "sin nombre libre para " .. name
            end
        end
        local sz = du_bytes(src)
        pairs_[#pairs_ + 1] = { src = src, dst = dst, size = sz }
        total_bytes = total_bytes + sz
    end

    -- 2) Escribir el archivo de pares (src|dst|size por linea).
    local base = "/tmp/lane-ops-"
        .. tostring(os.time()) .. "-" .. tostring(math.random(1000, 9999))
    local pf = io.open(base .. ".pairs", "w")
    if not pf then return nil, "no se pudo escribir " .. base .. ".pairs" end
    for _, p in ipairs(pairs_) do
        pf:write(p.src .. "|" .. p.dst .. "|" .. tostring(p.size) .. "\n")
    end
    pf:close()

    -- 3) Escribir el script shell.
    local sh_file = base .. ".sh"
    local prog_file = base .. ".prog"
    local done_file = base .. ".done"
    local err_file  = base .. ".errors"
    local f = io.open(sh_file, "w")
    if not f then return nil, "no se pudo escribir " .. sh_file end
    f:write("#!/bin/sh\n")
    f:write("i=0\n")
    f:write("bytes_done=0\n")
    f:write("while IFS='|' read -r src dst sz; do\n")
    if mode == "copy" then
        if opts.overwrite then
            f:write("  cp -rf \"$src\" \"$dst\" 2>/dev/null\n")
        else
            f:write("  cp -r \"$src\" \"$dst\" 2>/dev/null\n")
        end
    else
        if opts.overwrite then
            f:write("  mv -f \"$src\" \"$dst\" 2>/dev/null\n")
        else
            f:write("  mv \"$src\" \"$dst\" 2>/dev/null\n")
        end
    end
    f:write("  rc=$?\n")
    f:write("  i=$((i+1))\n")
    f:write("  bytes_done=$((bytes_done + sz))\n")
    f:write("  name=$(basename \"$src\")\n")
    f:write("  printf '%s\\n%s\\n%s\\n' \"$i\" \"$bytes_done\" \"$name\""
        .. " > " .. shq(prog_file) .. ".tmp\n")
    f:write("  mv " .. shq(prog_file) .. ".tmp " .. shq(prog_file) .. "\n")
    f:write("  if [ $rc -ne 0 ]; then\n")
    f:write("    printf '%s\\n' \"$name\" >> " .. shq(err_file) .. "\n")
    f:write("  fi\n")
    f:write("done < " .. shq(base .. ".pairs") .. "\n")
    f:write("echo done > " .. shq(done_file) .. "\n")
    f:close()
    os.execute("chmod +x " .. shq(sh_file))

    -- 4) Lanzar en background con setsid -f.
    os.execute("setsid -f sh -c "
        .. shq(sh_file .. " >/dev/null 2>&1") .. " &")

    -- 5) Handle.
    local handle = {
        mode = mode,
        total_items = #pairs_,
        total_bytes = total_bytes,
        _prog_file = prog_file,
        _done_file = done_file,
        _err_file  = err_file,
        _base      = base,
        _sh_file   = sh_file,
        _state = {
            done_items = 0, total_items = #pairs_,
            bytes_done = 0, total_bytes = total_bytes,
            current = "", done = false, errors = {},
        },
    }

    function handle:tick()
        if self._state.done then return self._state end
        local f = io.open(self._prog_file, "r")
        if f then
            local i = f:read("*l")
            local bd = f:read("*l")
            local name = f:read("*l")
            f:close()
            if i    then self._state.done_items = tonumber(i) or 0 end
            if bd   then self._state.bytes_done = tonumber(bd) or 0 end
            if name then self._state.current    = name end
        end
        if exists(self._done_file) then
            self._state.done = true
            -- Leer errores.
            local ef = io.open(self._err_file, "r")
            if ef then
                for line in ef:lines() do
                    self._state.errors[#self._state.errors + 1] = line
                end
                ef:close()
            end
            -- Limpieza.
            os.remove(self._prog_file)
            os.remove(self._prog_file .. ".tmp")
            os.remove(self._done_file)
            os.remove(self._err_file)
            os.remove(self._base .. ".pairs")
            os.remove(self._sh_file)
        end
        return self._state
    end

    function handle:status()  return self._state end
    function handle:is_done() return self._state.done end

    function handle:cancel()
        os.execute("pkill -f " .. shq(self._sh_file) .. " 2>/dev/null")
        self._state.done = true
        os.remove(self._prog_file)
        os.remove(self._prog_file .. ".tmp")
        os.remove(self._done_file)
        os.remove(self._err_file)
        os.remove(self._base .. ".pairs")
        os.remove(self._sh_file)
    end

    return handle
end

return M
