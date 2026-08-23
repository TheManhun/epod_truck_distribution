local config = require("epod_td.config")

local M = {}

function M.info(message)
    print("[EPOD-TD] " .. tostring(message))
end

function M.debug(message)
    if config.DEBUG then
        print("[EPOD-TD] " .. tostring(message))
    end
end

function M.separator()
    print("[EPOD-TD] ----------------------------------------")
end

function M.header(title)
    print("[EPOD-TD] ========================================")
    print("[EPOD-TD] TF2 Truck Distribution v" .. config.VERSION)
    print("[EPOD-TD] " .. tostring(title))
    print("[EPOD-TD] ========================================")
end

function M.error(message)
    print("[EPOD-TD] ERROR: " .. tostring(message))
end

return M