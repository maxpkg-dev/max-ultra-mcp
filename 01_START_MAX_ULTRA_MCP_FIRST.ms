-- FIRST STEP: Run this file in 3ds Max to start the Python/Qt Max Ultra MCP client.
-- Copyright (c) 2026 Lukianenko Vasyl
-- Project website: https://3dground.net
-- Developed by Lukianenko Vasyl
(
    local bootstrapFilePath = getThisScriptFileName()
    local pythonBootstrap = (getFilenamePath bootstrapFilePath) + @"python\bootstrap.py"
    if (not (doesFileExist pythonBootstrap)) do throw "The Max Ultra MCP Python runtime is missing. Reinstall the complete MZP package."
    python.ExecuteFile pythonBootstrap
)
