-- devices: dispositivos montados (discos, USBs, particiones, MTP).
--
-- Lee /proc/self/mounts y filtra los puntos de montaje que
-- representan algo interesante para el usuario: lo que hay bajo
-- /media, /run/media, /mnt y /run/user/$UID/gvfs (celulares MTP).
--
-- Excluimos los filesystems virtuales (proc, sysfs, tmpfs, cgroup,
-- overlay, efivarfs, ...) y los montajes de sistema tipicos
-- (/boot, /home en particion propia, etc).
--
-- Refresh: se llama a M.list() periodicamente desde init.lua. Si
-- la lista cambia, el sidebar se reconstruye. No usamos udev (mas
-- complejo) ni polling agresivo (cada 5s alcanza).

local M = {}

local HOME = os.getenv("HOME") or "/"
local UID = tostring(os.getenv("UID") or "1000")

-- Los paths de /proc/self/mounts pueden tener escapes tipo \040
-- para espacios, \011 tab, \012 newline, \134 backslash.
local function unescape(s)
    return (s:gsub("\\(%d%d%d)", function(n)
        return string.char(tonumber(n, 8))
    end))
end

-- Filesystems que no nos interesan. SOLO los verdaderamente
-- virtuales del kernel. Un mount de red (sshfs, nfs) o un fuse de
-- usuario bajo /media o /mnt SI debe aparecer — el filtro real lo
-- hace is_user_mount(). Excluir sshfs aca impedia ver el celular
-- montado por red en /media/$USER/xxx.
local VIRTUAL_FS = {
    proc = true, sysfs = true, devtmpfs = true, devpts = true,
    tmpfs = true, cgroup = true, cgroup2 = true, securityfs = true,
    debugfs = true, tracefs = true, configfs = true, fusectl = true,
    pstore = true, bpf = true, mqueue = true, hugetlbfs = true,
    rpc_pipefs = true, autofs = true, nsfs = true, ramfs = true,
    efivarfs = true, binfmt_misc = true,
    -- El gvfs daemon de sesion no es un dispositivo. Los MTP reales
    -- viven bajo /run/user/$UID/gvfs/ y se detectan por is_user_mount.
    ["fuse.gvfsd-fuse"] = true,
}

-- Punto de montaje que representa un "dispositivo de usuario".
-- Solo lo que esta bajo /media, /run/media, /mnt, o el gvfs de
-- MTP del usuario actual.
local function is_user_mount(mnt)
    if mnt:sub(1, 7) == "/media/" then return true end
    if mnt:sub(1, 11) == "/run/media/" then return true end
    if mnt:sub(1, 5) == "/mnt/" then return true end
    if mnt == "/mnt" then return true end
    if mnt == "/media" then return true end
    -- gvfs: /run/user/<uid>/gvfs/<scheme>:host=...
    local prefix = "/run/user/" .. UID .. "/gvfs/"
    if mnt:sub(1, #prefix) == prefix then return true end
    return false
end

-- Nombre "bonito" del dispositivo. Usa el basename del punto de
-- montaje o, si es gvfs, el esquema+host del path.
local function pretty_label(mnt)
    -- gvfs: "mtp:host=XYZ" -> "XYZ (MTP)"
    local gvfs = mnt:match("/gvfs/([^/]+)$")
    if gvfs then
        local scheme, host = gvfs:match("^([^:]+):host=(.+)$")
        if scheme and host then
            return host .. " (" .. scheme:upper() .. ")"
        end
        return gvfs
    end
    local base = mnt:match("([^/]+)/?$") or mnt
    if base == "" then return mnt end
    return base
end

-- Icono segun fs y dispositivo.
local function pick_icon(dev, mnt)
    if mnt:find("/gvfs/", 1, true) then return "phone" end
    if mnt:find("/run/media/", 1, true) then return "drive-removable" end
    if mnt:find("/media/", 1, true) then return "drive-removable" end
    if mnt:find("/mnt/", 1, true) then return "drive-harddisk" end
    return "drive-harddisk"
end

-- Lee /proc/self/mounts y devuelve la lista filtrada.
-- Cada entrada: { label, path, icon, dev, fstype }
function M.list()
    local f = io.open("/proc/self/mounts", "r")
    if not f then return {} end
    local out = {}
    local seen = {}
    for line in f:lines() do
        local dev, mnt, fstype = line:match("^(%S+)%s+(%S+)%s+(%S+)")
        if dev and mnt and fstype then
            mnt = unescape(mnt)
            dev = unescape(dev)
            if not VIRTUAL_FS[fstype] and is_user_mount(mnt) then
                -- Evitar duplicados (a veces una particion se
                -- monta dos veces por bind mounts o similar).
                if not seen[mnt] then
                    seen[mnt] = true
                    out[#out + 1] = {
                        label = pretty_label(mnt),
                        path  = mnt,
                        icon  = pick_icon(dev, mnt),
                        dev   = dev,
                        fstype = fstype,
                    }
                end
            end
        end
    end
    f:close()
    return out
end

return M
