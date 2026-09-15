package.path = "./?.lua;./?/init.lua;" .. package.path

local suites = {
    "tests.constants_test",
    "tests.character_identity_test",
    "tests.gear_snapshot_test",
    "tests.storage_test",
    "tests.local_gear_memory_test",
    "tests.main_test",
}

local function modulePath(moduleName)
    return moduleName:gsub("%.", "/") .. ".lua"
end

for _, moduleName in ipairs(suites) do
    local file = io.open(modulePath(moduleName), "r")
    if file then
        file:close()
        require(moduleName)
    end
end

local T = require("tests.testlib")
T.run()
