local M = {}

M.initialised = false
M.routeInjected = false

M.sourceLineId = nil
M.parkReferenceLineId = nil
M.parkStationGroupId = nil

M.lastUpdate = 0

M.destinations = {}
M.availableVehicles = {}
M.assignments = {}

function M.reset()
    M.initialised = false
    M.routeInjected = false

    M.sourceLineId = nil
    M.parkReferenceLineId = nil
    M.parkStationGroupId = nil

    M.lastUpdate = 0

    M.destinations = {}
    M.availableVehicles = {}
    M.assignments = {}
end

return M