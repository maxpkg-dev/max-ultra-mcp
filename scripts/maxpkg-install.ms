-- Complete focused migration cleanup after the standard MaxPkg confirmation.
-- Copyright (c) 2026 Lukianenko Vasyl
-- Project website: https://3dground.net
-- Developed by Lukianenko Vasyl
(
    local helperPath = (getFilenamePath (getThisScriptFileName())) + "maxpkg-install.py"
    if (not (doesFileExist helperPath)) do throw "Max Ultra MCP install helper is missing"
    python.ExecuteFile helperPath
)
