local M = {}

M.VERSION = "0.0.27"

M.SOURCE_LINE_NAME = "Truck - CD - Hendon"

-- Temporary reference line used to locate the existing
-- EPOD-TD Truck Park native stop.
M.PARK_REFERENCE_LINE_NAME = "EPOD-TD TEST - Alexander"

M.HUB_NAME = "Hendon East"

-- Technical mechanism, not the MASTERPLAN "physical truck parking" non-goal:
-- forces a genuine stop-arrival event to work around a cargo-pickup bug on
-- setLine reassignment. See DECISIONS.md, Decision 12 clarification.
M.PARK_NAME = "EPOD-TD Truck Park"

M.START_DELAY_UPDATES = 120

M.DEBUG = true

return M