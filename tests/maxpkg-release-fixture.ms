-- Enter the explicitly isolated MaxPkg release fixture.
-- Copyright (c) 2026 Lukianenko Vasyl
-- Project website: https://3dground.net
-- Developed by Lukianenko Vasyl
(
    global MaxUltraReleaseFixturePath = (getFilenamePath (getThisScriptFileName())) + "maxpkg-release-fixture.py"
    python.Execute "import runpy, pymxs; runpy.run_path(str(pymxs.runtime.MaxUltraReleaseFixturePath))"
    MaxUltraReleaseFixturePath = undefined
)
