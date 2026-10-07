-- Run focused package cleanup through the bundled Max Python runtime.
-- Copyright (c) 2026 Lukianenko Vasyl
-- Project website: https://3dground.net
-- Developed by Lukianenko Vasyl
(
    local helperPath = (getFilenamePath (getThisScriptFileName())) + "maxpkg-uninstall.py"
    if (not (doesFileExist helperPath)) do throw "Max Ultra MCP uninstall helper is missing"
    python.ExecuteFile helperPath
)
