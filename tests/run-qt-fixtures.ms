-- Run isolated Qt acceptance fixtures in a deliberately launched test process.
-- Copyright (c) 2026 Lukianenko Vasyl
-- Project website: https://3dground.net
-- Developed by Lukianenko Vasyl
(
    local fixtureFilePath = (getFilenamePath (getThisScriptFileName())) + "run-qt-fixtures.py"
    python.ExecuteFile fixtureFilePath
)
