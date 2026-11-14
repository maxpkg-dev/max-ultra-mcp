/*

	OPTIONAL MAXPKG UNINSTALL HOOK

	For focused project-specific cleanup, select a separate Custom Uninstall
	Script in MaxPkg Packager. It runs before package files are removed.

	Advanced authors may replace the uninstaller body inside the existing
	if (MaxPkg == undefined) block with their own removal code.

	Keep destructive actions guarded so previewing this file from a project
	folder cannot remove project files.

*/

struct MaxPkgUninstallHookData (
    currScript = getSourceFileName(),
    scriptDir = getFilenamePath currScript,
    manifestFilePath = scriptDir + "manifest.ini",
    settingsFilePath = scriptDir + "maxpkg-packager.ini",
    isSafeTempPackageFolder = false,
    isCustomUninstallComplete = false,
    customUninstallFailureContent = "",
    packageGuid = "",
    packageTitle = "Package",
    packageVersion = "1.0.0",
    developerTitle = "Unknown developer",
    homepageUrl = "",
    documentationUrl = "",
    supportUrl = "",
    licenseUrl = "",
    purchaseUrl = "",
    purchaseButtonLabel = "Buy",
    packageIconDataUri = "",
    isRemovalConfirmed = false,
    isRemovalFailed = false,
    uninstallFailureContent = "",

        fn maxPkgUninstallNormalizeFolder folderPath = (
            local normalizedFolder = substituteString (folderPath as string) "/" "\\"

            while (normalizedFolder.count > 0 and (substring normalizedFolder normalizedFolder.count 1) == "\\") do (
                normalizedFolder = substring normalizedFolder 1 (normalizedFolder.count - 1)
            )

            return toLower normalizedFolder
        ),

        fn maxPkgUninstallIsGuid guidContent = (
            local normalizedGuid = toLower (guidContent as string)
            local allowedCharacters = "0123456789abcdef-"

            if (normalizedGuid.count != 36) do return false
            if ((substring normalizedGuid 9 1) != "-" or (substring normalizedGuid 14 1) != "-" or (substring normalizedGuid 19 1) != "-" or (substring normalizedGuid 24 1) != "-") do return false

            for characterIndex in 1 to normalizedGuid.count do (
                if ((findString allowedCharacters (substring normalizedGuid characterIndex 1)) == undefined) do return false
            )

            return true
        ),

        fn maxPkgUninstallIsSafeTempFolder packageFolder manifestFilePath = (
            if (not (doesFileExist manifestFilePath)) do return false

            local packageGuid = getINISetting manifestFilePath "package" "packageGuid"
            if (not (maxPkgUninstallIsGuid packageGuid)) do return false

            local expectedFolder = (getDir #temp) + "\\" + packageGuid
            return (maxPkgUninstallNormalizeFolder packageFolder) == (maxPkgUninstallNormalizeFolder expectedFolder)
        ),

        fn maxPkgUninstallStartsWith sourceContent prefixContent = (
            if (sourceContent == undefined or prefixContent == undefined) do return false

            local sourceString = sourceContent as string
            local prefixString = prefixContent as string
            if (sourceString.count < prefixString.count) do return false
            return (substring sourceString 1 prefixString.count) == prefixString
        ),

        fn maxPkgUninstallWaitForCustomCleanup waitMilliseconds = (
            local waitStartedAt = timestamp()

            while ((timestamp() - waitStartedAt) < waitMilliseconds) do (
                try (windows.processPostedMessages()) catch()
            )

            return true
        ),

        fn maxPkgUninstallRunCustomScript packageFolder manifestFilePath manifestKey = (
            if (not (maxPkgUninstallIsSafeTempFolder packageFolder manifestFilePath)) do return false

            local relativeScriptFile = getINISetting manifestFilePath "package" manifestKey
            local customScriptError = ""
            local customScriptStage = "resolve custom script"
            local isCustomScriptComplete = false
            if (relativeScriptFile == undefined or relativeScriptFile == "") do return true
            if ((toLower (getFilenameType relativeScriptFile)) != ".ms") do return false

            try (
                local ioPathClass = dotNetClass "System.IO.Path"
                local packageRoot = maxPkgUninstallNormalizeFolder (ioPathClass.GetFullPath packageFolder)
                local resolvedScriptFile = maxPkgUninstallNormalizeFolder (ioPathClass.GetFullPath (packageFolder + relativeScriptFile))
                local packagePrefix = packageRoot + "\\"

                if (not (maxPkgUninstallStartsWith resolvedScriptFile packagePrefix)) do return false
                if (not (doesFileExist resolvedScriptFile)) do return false
                customScriptStage = "execute custom script"
                fileIn resolvedScriptFile
                customScriptStage = "wait for custom cleanup"
                maxPkgUninstallWaitForCustomCleanup 2000
                isCustomScriptComplete = true
            ) catch (
                customScriptError = customScriptStage + ": " + getCurrentException()
            )

            if (customScriptError != "") do throw customScriptError
            return isCustomScriptComplete
        ),

        fn maxPkgUninstallDirectoryExists folderPath = (
            if (folderPath == undefined or folderPath == "") do return false

            try (
                return (dotNetClass "System.IO.Directory").Exists folderPath
            ) catch (
                return false
            )
        ),

        fn maxPkgUninstallDeletePackageFolder packageFolder manifestFilePath = (
            if (not (maxPkgUninstallIsSafeTempFolder packageFolder manifestFilePath)) do return false

            local verifiedPackageFolder = maxPkgUninstallNormalizeFolder packageFolder
            if (not (maxPkgUninstallDirectoryExists verifiedPackageFolder)) do return true

            local deleteCommand = "rmdir /s /q \"" + verifiedPackageFolder + "\""
            local commandExitCode = -1

            try (
                HiddenDOSCommand deleteCommand startpath: (getDir #temp) exitCode: &commandExitCode
            ) catch (
                return false
            )

            return commandExitCode == 0 and not (maxPkgUninstallDirectoryExists verifiedPackageFolder)
        ),

        fn maxPkgUninstallEnsureTrailingSlash folderPath = (
            if (folderPath == undefined or folderPath == "") do return ""
            if ((substring folderPath folderPath.count 1) == "\\") do return folderPath
            return folderPath + "\\"
        ),

        fn maxPkgUninstallDeleteFile ownedFilePath = (
            if (ownedFilePath == undefined or ownedFilePath == "") do return false
            if (not (doesFileExist ownedFilePath)) do return true

            try (
                setFileAttribute ownedFilePath #readOnly false
                deleteFile ownedFilePath
                return not (doesFileExist ownedFilePath)
            ) catch (
                return false
            )
        ),

        fn maxPkgUninstallMacroBelongsToPackage macroFilePath packageGuid = (
            if (macroFilePath == undefined or macroFilePath == "") do return false
            if (not (maxPkgUninstallIsGuid packageGuid)) do return false

            local normalizedGuid = toLower packageGuid
            local macroFileName = toLower (filenameFromPath macroFilePath)
            local generatedFilePrefix = "maxpkg-" + normalizedGuid
            if (maxPkgUninstallStartsWith macroFileName generatedFilePrefix) do return true

            try (
                local macroFileContent = toLower ((dotNetClass "System.IO.File").ReadAllText macroFilePath)
                return (findString macroFileContent ("-- package guid: " + normalizedGuid)) != undefined
            ) catch (
                return false
            )
        ),

        fn maxPkgUninstallStringLiteral sourceContent = (
            local literalContent = sourceContent as string
            literalContent = substituteString literalContent "\\" "\\\\"
            literalContent = substituteString literalContent "\"" "\\\""
            return "\"" + literalContent + "\""
        ),

        fn maxPkgUninstallRemoveQuadMenu packageFolder packageGuid = (
            local helperFilePath = (maxPkgUninstallEnsureTrailingSlash packageFolder) + "maxpkg-quad.ms"
            local startupFilePath = (maxPkgUninstallEnsureTrailingSlash (getDir #userStartupScripts)) + "maxpkg-" + packageGuid + "-quad-startup.ms"
            local isQuadMenuRemoved = true

            if (doesFileExist helperFilePath) do (
                try (
                    fileIn helperFilePath
                    local commandContent = "(MaxPkgQuadMenuManagerData packageFolder: " + (maxPkgUninstallStringLiteral packageFolder) + ").uninstall()"
                    isQuadMenuRemoved = (execute commandContent) == true
                ) catch (
                    isQuadMenuRemoved = false
                )
            )

            if isQuadMenuRemoved do isQuadMenuRemoved = maxPkgUninstallDeleteFile startupFilePath
            return isQuadMenuRemoved
        ),

        fn maxPkgUninstallRemovePackage packageFolder manifestFilePath packageGuid = (
            if (not (maxPkgUninstallIsSafeTempFolder packageFolder manifestFilePath)) do return false
            if (not (maxPkgUninstallIsGuid packageGuid)) do return false
            if (not (maxPkgUninstallRemoveQuadMenu packageFolder packageGuid)) do return false

            local isRemovalSuccessful = true
            local userMacrosFolder = maxPkgUninstallEnsureTrailingSlash (getDir #userMacros)
            local userIconsFolder = maxPkgUninstallEnsureTrailingSlash (getDir #userIcons)
            local userMacroFiles = try (getFiles (userMacrosFolder + "*.mcr")) catch(#())

            for macroFilePath in userMacroFiles do (
                if (maxPkgUninstallMacroBelongsToPackage macroFilePath packageGuid) do (
                    if (not (maxPkgUninstallDeleteFile macroFilePath)) do isRemovalSuccessful = false
                )
            )

            local installedIconFilePath = userIconsFolder + packageGuid + ".svg"
            if (not (maxPkgUninstallDeleteFile installedIconFilePath)) do isRemovalSuccessful = false

            if isRemovalSuccessful do (
                isRemovalSuccessful = maxPkgUninstallDeletePackageFolder packageFolder manifestFilePath
            )

            return isRemovalSuccessful
        ),

        fn maxPkgUninstallEscapeHtml sourceContent = (
            local escapedContent = if sourceContent == undefined then "" else sourceContent as string
            escapedContent = substituteString escapedContent "&" "&amp;"
            escapedContent = substituteString escapedContent "<" "&lt;"
            escapedContent = substituteString escapedContent ">" "&gt;"
            escapedContent = substituteString escapedContent "\"" "&quot;"
            escapedContent = substituteString escapedContent "'" "&#39;"
            return escapedContent
        ),

        fn maxPkgUninstallReadSetting manifestFilePath settingsFilePath manifestKey settingsKey fallbackContent: "" = (
            local settingContent = ""

            if (doesFileExist manifestFilePath) do settingContent = getINISetting manifestFilePath "package" manifestKey
            if ((settingContent == undefined or settingContent == "") and doesFileExist settingsFilePath) do (
                settingContent = getINISetting settingsFilePath "settings" settingsKey
            )
            if (settingContent == undefined or settingContent == "") do settingContent = fallbackContent
            return settingContent
        ),

        fn maxPkgUninstallResolveIconFile packageFolder iconContent = (
            if (iconContent == undefined or iconContent == "") do return ""

            local iconFilePath = iconContent as string
            try (
                if (not ((dotNetClass "System.IO.Path").IsPathRooted iconFilePath)) do iconFilePath = packageFolder + iconFilePath
            ) catch (
                return ""
            )

            if (not (doesFileExist iconFilePath)) do return ""
            return iconFilePath
        ),

        fn maxPkgUninstallImageDataUri imageFilePath = (
            if (imageFilePath == undefined or imageFilePath == "" or not (doesFileExist imageFilePath)) do return ""

            try (
                local imageExtension = toLower (getFilenameType imageFilePath)
                local imageMimeType = case imageExtension of (
                    ".svg": "image/svg+xml"
                    ".png": "image/png"
                    ".jpg": "image/jpeg"
                    ".jpeg": "image/jpeg"
                    ".gif": "image/gif"
                    default: ""
                )
                if (imageMimeType == "") do return ""

                local imageBytes = (dotNetClass "System.IO.File").ReadAllBytes imageFilePath
                local base64Content = (dotNetClass "System.Convert").ToBase64String imageBytes
                return "data:" + imageMimeType + ";base64," + base64Content
            ) catch (
                return ""
            )
        ),

        fn maxPkgUninstallIsWebAddress addressContent = (
            if (addressContent == undefined or addressContent == "") do return false

            local normalizedAddress = toLower (addressContent as string)
            if (maxPkgUninstallStartsWith normalizedAddress "https://") do return true
            if (maxPkgUninstallStartsWith normalizedAddress "http://") do return true
            return false
        ),

        fn maxPkgUninstallLucideSvg iconId = (
            case iconId of (
                "circle-check": return "<svg class='ui-icon' viewBox='0 0 24 24' fill='none' stroke='currentColor' stroke-width='2' stroke-linecap='round' stroke-linejoin='round' aria-hidden='true'><circle cx='12' cy='12' r='10'/><path d='m9 12 2 2 4-4'/></svg>"
                "circle-x": return "<svg class='ui-icon' viewBox='0 0 24 24' fill='none' stroke='currentColor' stroke-width='2' stroke-linecap='round' stroke-linejoin='round' aria-hidden='true'><circle cx='12' cy='12' r='10'/><path d='m15 9-6 6'/><path d='m9 9 6 6'/></svg>"
                "info": return "<svg class='ui-icon' viewBox='0 0 24 24' fill='none' stroke='currentColor' stroke-width='2' stroke-linecap='round' stroke-linejoin='round' aria-hidden='true'><circle cx='12' cy='12' r='10'/><line x1='12' y1='16' x2='12' y2='12'/><line x1='12' y1='8' x2='12.01' y2='8'/></svg>"
                "trash-2": return "<svg class='ui-icon' viewBox='0 0 24 24' fill='none' stroke='currentColor' stroke-width='2' stroke-linecap='round' stroke-linejoin='round' aria-hidden='true'><polyline points='3 6 5 6 21 6'/><path d='M19 6l-1 14H6L5 6m3 0V4h8v2'/><line x1='10' y1='11' x2='10' y2='17'/><line x1='14' y1='11' x2='14' y2='17'/></svg>"
                "x": return "<svg class='ui-icon' viewBox='0 0 24 24' fill='none' stroke='currentColor' stroke-width='2' stroke-linecap='round' stroke-linejoin='round' aria-hidden='true'><line x1='18' y1='6' x2='6' y2='18'/><line x1='6' y1='6' x2='18' y2='18'/></svg>"
                "external-link": return "<svg class='ui-icon' viewBox='0 0 24 24' fill='none' stroke='currentColor' stroke-width='2' stroke-linecap='round' stroke-linejoin='round' aria-hidden='true'><path d='M15 3h6v6'/><path d='M10 14 21 3'/><path d='M18 13v6a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2h6'/></svg>"
                "home": return "<svg class='ui-icon' viewBox='0 0 24 24' fill='none' stroke='currentColor' stroke-width='2' stroke-linecap='round' stroke-linejoin='round' aria-hidden='true'><path d='m3 9 9-7 9 7v11a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z'/><polyline points='9 22 9 12 15 12 15 22'/></svg>"
                "book-open": return "<svg class='ui-icon' viewBox='0 0 24 24' fill='none' stroke='currentColor' stroke-width='2' stroke-linecap='round' stroke-linejoin='round' aria-hidden='true'><path d='M2 3h6a4 4 0 0 1 4 4v14a3 3 0 0 0-3-3H2z'/><path d='M22 3h-6a4 4 0 0 0-4 4v14a3 3 0 0 1 3-3h7z'/></svg>"
                "circle-help": return "<svg class='ui-icon' viewBox='0 0 24 24' fill='none' stroke='currentColor' stroke-width='2' stroke-linecap='round' stroke-linejoin='round' aria-hidden='true'><circle cx='12' cy='12' r='10'/><path d='M9.09 9a3 3 0 1 1 5.83 1c0 2-3 3-3 3'/><path d='M12 17h.01'/></svg>"
                "file-text": return "<svg class='ui-icon' viewBox='0 0 24 24' fill='none' stroke='currentColor' stroke-width='2' stroke-linecap='round' stroke-linejoin='round' aria-hidden='true'><path d='M14.5 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V7.5z'/><polyline points='14 2 14 8 20 8'/><line x1='16' y1='13' x2='8' y2='13'/><line x1='16' y1='17' x2='8' y2='17'/></svg>"
                "shopping-cart": return "<svg class='ui-icon' viewBox='0 0 24 24' fill='none' stroke='currentColor' stroke-width='2' stroke-linecap='round' stroke-linejoin='round' aria-hidden='true'><circle cx='9' cy='20' r='1'/><circle cx='19' cy='20' r='1'/><path d='M3 4h2l2.4 11.2a2 2 0 0 0 2 1.6h7.7a2 2 0 0 0 2-1.6L21 8H6'/></svg>"
                default: return ""
            )
        ),

        fn runCustomUninstallScript = (
            if isCustomUninstallComplete do return true
            if (not isSafeTempPackageFolder) do return false

            customUninstallFailureContent = ""
            try (
                isCustomUninstallComplete = maxPkgUninstallRunCustomScript scriptDir manifestFilePath "customUninstallScript"
            ) catch (
                customUninstallFailureContent = getCurrentException()
                isCustomUninstallComplete = false
            )
            return isCustomUninstallComplete
        ),

        fn loadPackageData = (
            packageGuid = maxPkgUninstallReadSetting manifestFilePath settingsFilePath "packageGuid" "packageGuid" fallbackContent: ""
            packageTitle = maxPkgUninstallReadSetting manifestFilePath settingsFilePath "name" "packageName" fallbackContent: "Package"
            packageVersion = maxPkgUninstallReadSetting manifestFilePath settingsFilePath "version" "version" fallbackContent: "1.0.0"
            developerTitle = maxPkgUninstallReadSetting manifestFilePath settingsFilePath "developerName" "developerName" fallbackContent: "Unknown developer"
            homepageUrl = maxPkgUninstallReadSetting manifestFilePath settingsFilePath "homepage" "homepage" fallbackContent: ""
            documentationUrl = maxPkgUninstallReadSetting manifestFilePath settingsFilePath "documentation" "documentation" fallbackContent: ""
            supportUrl = maxPkgUninstallReadSetting manifestFilePath settingsFilePath "support" "support" fallbackContent: ""
            licenseUrl = maxPkgUninstallReadSetting manifestFilePath settingsFilePath "licenseUrl" "licenseUrl" fallbackContent: ""
            purchaseUrl = maxPkgUninstallReadSetting manifestFilePath settingsFilePath "purchase" "purchase" fallbackContent: ""
            purchaseButtonLabel = maxPkgUninstallReadSetting manifestFilePath settingsFilePath "purchaseButtonLabel" "purchaseButtonLabel" fallbackContent: "Buy"
            local packageIconRel = maxPkgUninstallReadSetting manifestFilePath settingsFilePath "icon" "svgIcon" fallbackContent: ""
            local packageIconFilePath = maxPkgUninstallResolveIconFile scriptDir packageIconRel
            packageIconDataUri = maxPkgUninstallImageDataUri packageIconFilePath
            isRemovalConfirmed = false
            isRemovalFailed = false
            uninstallFailureContent = ""
            return true
        ),

            fn buildUninstallerHtml = (
                local escapedPackageTitle = maxPkgUninstallEscapeHtml packageTitle
                local escapedPackageVersion = maxPkgUninstallEscapeHtml packageVersion
                local escapedDeveloperTitle = maxPkgUninstallEscapeHtml developerTitle
                local packageInitials = toUpper (substring packageTitle 1 (amin packageTitle.count 2))
                local iconMarkup = "<span class='icon-fallback'>" + (maxPkgUninstallEscapeHtml packageInitials) + "</span>"
                local modeBadge = if isSafeTempPackageFolder then "" else "<span class='preview-badge'>Preview</span>"
                local resourceLinksMarkup = ""
                local contentMarkup = ""
                local actionMarkup = ""
                local bodyClass = if (isRemovalConfirmed or isRemovalFailed) then "result-state" else "confirm-state"

                if (packageIconDataUri != "") do iconMarkup = "<img src='" + packageIconDataUri + "' alt='Package icon'>"
                if (maxPkgUninstallIsWebAddress homepageUrl) do resourceLinksMarkup += "<a class='resource-link' href='" + (maxPkgUninstallEscapeHtml homepageUrl) + "'>" + (maxPkgUninstallLucideSvg "home") + "Developer site</a>"
                if (maxPkgUninstallIsWebAddress documentationUrl) do resourceLinksMarkup += "<a class='resource-link' href='" + (maxPkgUninstallEscapeHtml documentationUrl) + "'>" + (maxPkgUninstallLucideSvg "book-open") + "Docs</a>"
                if (maxPkgUninstallIsWebAddress supportUrl) do resourceLinksMarkup += "<a class='resource-link' href='" + (maxPkgUninstallEscapeHtml supportUrl) + "'>" + (maxPkgUninstallLucideSvg "circle-help") + "Support</a>"
                if (maxPkgUninstallIsWebAddress licenseUrl) do resourceLinksMarkup += "<a class='resource-link' href='" + (maxPkgUninstallEscapeHtml licenseUrl) + "'>" + (maxPkgUninstallLucideSvg "file-text") + "License</a>"
                if (maxPkgUninstallIsWebAddress purchaseUrl) do resourceLinksMarkup += "<a class='resource-link purchase-link' href='" + (maxPkgUninstallEscapeHtml purchaseUrl) + "'>" + (maxPkgUninstallLucideSvg "shopping-cart") + (maxPkgUninstallEscapeHtml purchaseButtonLabel) + "</a>"
                if (resourceLinksMarkup != "") do resourceLinksMarkup = "<nav class='resource-links'>" + resourceLinksMarkup + "</nav>"

                if isRemovalFailed then (
                    local escapedFailureContent = maxPkgUninstallEscapeHtml uninstallFailureContent
                    if (escapedFailureContent == "") do escapedFailureContent = "Close 3ds Max tools that use this package and try again."
                    contentMarkup = "<section class='status-card error-card'><div class='status-mark'>" + (maxPkgUninstallLucideSvg "circle-x") + "</div><div><h2>Removal could not be completed.</h2><p>" + escapedFailureContent + "</p></div></section>"
                    actionMarkup = "<a class='secondary-button' href='maxpkg://close'>" + (maxPkgUninstallLucideSvg "x") + "Close</a><a class='danger-button' href='maxpkg://uninstall'>" + (maxPkgUninstallLucideSvg "trash-2") + "Try Again</a>"
                ) else if isRemovalConfirmed then (
                    if isSafeTempPackageFolder then (
                        contentMarkup = "<section class='status-card success-card'><div class='status-mark'>" + (maxPkgUninstallLucideSvg "circle-check") + "</div><h2>" + escapedPackageTitle + " has been completely removed.</h2></section>"
                    ) else (
                        contentMarkup = "<section class='status-card preview-card'><div class='status-mark'>" + (maxPkgUninstallLucideSvg "info") + "</div><div><h2>Preview mode</h2><p>No files were changed or removed.</p></div></section>"
                    )
                    actionMarkup = "<a class='secondary-button' href='maxpkg://close'>" + (maxPkgUninstallLucideSvg "x") + "Close</a>"
                ) else (
                    contentMarkup = "<section class='remove-card'><div class='section-label'>Package removal</div><h2>Remove " + escapedPackageTitle + "?</h2>" +
                        "<div class='warning-note'><strong>Before continuing</strong><span>Save your work and close any tools that use this package.</span></div></section>"
                    actionMarkup = "<a class='secondary-button' href='maxpkg://close'>" + (maxPkgUninstallLucideSvg "x") + "Cancel</a><a class='danger-button' href='maxpkg://uninstall'>" + (maxPkgUninstallLucideSvg "trash-2") + "Uninstall</a>"
                )

                local heroMarkup = "<header class='hero'><div class='package-icon'>" + iconMarkup + "</div><div class='package-meta'><div class='eyebrow'>MaxPkg package " + modeBadge + "</div><h1>" + escapedPackageTitle + "</h1><div class='package-version'>Version " + escapedPackageVersion + "<span class='separator'>&bull;</span>by " + escapedDeveloperTitle + "</div>" + resourceLinksMarkup + "</div></header>"
                local footerMarkup = "<footer class='actions'><div class='button-row'>" + actionMarkup + "</div></footer>"
                local pageMarkup = if isRemovalConfirmed then contentMarkup + footerMarkup else heroMarkup + footerMarkup + contentMarkup

                local htmlContent = "<!doctype html><html><head><meta charset='utf-8'><meta http-equiv='X-UA-Compatible' content='IE=edge'><style>" +
                    "*{box-sizing:border-box}html,body{width:100%;height:100%;margin:0;overflow:hidden;background:#20242a;color:#f4f6f8;font-family:'Segoe UI',Arial,sans-serif;font-size:14px}body{padding:5px 10px 10px}.uninstaller{height:100%;display:flex;flex-direction:column}.hero{display:flex;flex:0 0 auto;align-items:center;padding:12px 15px;background:#2d333b;border:1px solid #434b56;border-radius:8px}.package-icon{width:100px;height:100px;min-width:100px;margin-right:17px;display:flex;align-items:center;justify-content:center;overflow:hidden;background:#242930;border:1px solid #4b5664;border-radius:8px}.package-icon img{display:block;width:92px;height:92px}.icon-fallback{font-size:30px;font-weight:700;color:#9ebcf4}.package-meta{min-width:0}.ui-icon{display:inline-block;width:15px;height:15px;margin-right:7px;vertical-align:-3px}.developer-link .ui-icon{width:14px;height:14px}.eyebrow{margin-bottom:8px;color:#91a0b3;font-size:11px;font-weight:700;text-transform:uppercase;letter-spacing:1px}.package-meta h1{margin:0 0 9px;font-size:23px;line-height:1.2;overflow-wrap:break-word}.package-version{color:#b9c3d0}.separator{padding:0 7px;color:#657182}.preview-badge{display:inline-block;margin-left:10px;padding:3px 8px;border:1px solid #9d7834;border-radius:10px;color:#f2c66f;font-size:11px;text-transform:uppercase}.actions{display:flex;flex:0 0 auto;align-items:center;justify-content:space-between;min-height:50px;padding:7px 1px}.button-row{display:flex;align-items:center}.button-row a{margin-left:8px}.developer-link{color:#9ebdf4;text-decoration:none}.developer-link:hover{text-decoration:underline}.secondary-button,.danger-button{display:inline-block;min-width:112px;padding:10px 18px;border-radius:5px;color:#fff;font-weight:700;text-align:center;text-decoration:none}.secondary-button{border:1px solid #687586;background:#414953}.secondary-button:hover{background:#4c5662}.danger-button{border:1px solid #df7180;background:#a94552}.danger-button:hover{background:#bd5260}.remove-card,.status-card{flex:1 1 auto;min-height:0;padding:17px 19px;background:#2a2f36;border:1px solid #404853;border-radius:8px}.section-label{margin-bottom:4px;color:#ff7b89;font-size:10px;font-weight:700;text-transform:uppercase;letter-spacing:.8px}.remove-card h2,.status-card h2{margin:0 0 8px;font-size:18px}.remove-card p,.status-card p{margin:0;color:#cbd3dc;line-height:1.5}.warning-note{margin-top:16px;padding:11px 13px;border-left:3px solid #ff6b7a;background:#343038}.warning-note strong,.warning-note span{display:block}.warning-note span{margin-top:3px;color:#bfc7d1;font-size:12px}.status-card{display:flex;align-items:center}.success-card{background:#203a2c;border-color:#397654}.preview-card{background:#3a3222;border-color:#826530}.status-mark{width:44px;height:44px;min-width:44px;margin-right:15px;display:flex;align-items:center;justify-content:center}.status-mark .ui-icon{width:40px;height:40px;margin:0}.success-card .status-mark{color:#57bd91}.preview-card .status-mark{color:#f7b955}.status-card h2{margin:0}" +
                    ".resource-links{display:flex;flex:0 0 auto;align-items:center;flex-wrap:wrap;padding:5px 0 1px}.resource-link{margin-right:5px;padding:4px 7px;border-radius:4px;color:#9ebdf4;font-size:11px;text-decoration:none}.resource-link:hover{background:#303741}.resource-link .ui-icon{width:13px;height:13px;margin-right:5px}.purchase-link{color:#57bd91}.actions{justify-content:flex-end;min-height:46px;padding:5px 1px}.status-card{flex:0 0 auto;min-height:90px;padding:14px 18px}.error-card{background:#42262b;border-color:#8f4550}.error-card .status-mark{color:#ff6b7a}" +
                    "</style></head><body class='" + bodyClass + "'><div class='uninstaller'>" + pageMarkup + "</div></body></html>"

                return htmlContent
            ),

    uninstallerRollout = rollout uninstallerRollout "Uninstall Package" width: 500 height: 420 (
        local hookOwner = if (hookOwner != undefined) do hookOwner
        dotNetControl dncUninstallerBrowser "System.Windows.Forms.WebBrowser" width: 500 height: 420 align: #center offset: [0, -4]

        on uninstallerRollout open do (
            dncUninstallerBrowser.ScriptErrorsSuppressed = true
            dncUninstallerBrowser.IsWebBrowserContextMenuEnabled = false
            dncUninstallerBrowser.AllowWebBrowserDrop = false
            dncUninstallerBrowser.WebBrowserShortcutsEnabled = false
            dncUninstallerBrowser.ScrollBarsEnabled = false
            dncUninstallerBrowser.Dock = (dotNetClass "System.Windows.Forms.DockStyle").Fill
            hookOwner.refreshUninstallerBrowser()
        )

        on dncUninstallerBrowser Navigating eventSender navigationArgs do hookOwner.handleUninstallerNavigation navigationArgs
        on dncUninstallerBrowser Enter eventSender eventArgs do try (enableAccelerators = false) catch()
        on dncUninstallerBrowser Leave eventSender eventArgs do try (enableAccelerators = true) catch()
        on uninstallerRollout close do hookOwner.handleUninstallerClose()
    ),

    fn refreshUninstallerBrowser = (
        if (uninstallerRollout.dncUninstallerBrowser == undefined) do return false
        uninstallerRollout.dncUninstallerBrowser.DocumentText = buildUninstallerHtml()
        return true
    ),

    fn showUninstalledState = (
        isRemovalConfirmed = true
        isRemovalFailed = false
        uninstallerRollout.title = if isSafeTempPackageFolder then "Uninstall Complete" else "Uninstaller Preview"
        try (setDialogSize uninstallerRollout [500, 320]) catch()
        refreshUninstallerBrowser()
        return true
    ),

    fn showUninstallFailedState failureContent: "" = (
        isRemovalConfirmed = false
        isRemovalFailed = true
        uninstallFailureContent = failureContent
        uninstallerRollout.title = "Uninstall Failed"
        try (setDialogSize uninstallerRollout [500, 320]) catch()
        refreshUninstallerBrowser()
        return true
    ),

    fn handleUninstallerNavigation navigationArgs = (
        local targetAddress = try (navigationArgs.Url.AbsoluteUri as string) catch("")
        local normalizedAddress = toLower targetAddress

        if (maxPkgUninstallStartsWith normalizedAddress "maxpkg://uninstall") then (
            navigationArgs.Cancel = true
            if isSafeTempPackageFolder then (
                if (runCustomUninstallScript()) then (
                    if (maxPkgUninstallRemovePackage scriptDir manifestFilePath packageGuid) then (
                        showUninstalledState()
                    ) else (
                        showUninstallFailedState failureContent: "The custom cleanup finished, but MaxPkg could not remove the generated macros, icon, or package folder."
                    )
                ) else (
                    local customFailureMessage = "The custom uninstall script could not be completed. Package files were not removed."
                    if (customUninstallFailureContent != "") do customFailureMessage += " Error: " + customUninstallFailureContent
                    showUninstallFailedState failureContent: customFailureMessage
                )
            ) else (
                showUninstalledState()
            )
        ) else if (maxPkgUninstallStartsWith normalizedAddress "maxpkg://close") then (
            navigationArgs.Cancel = true
            destroyDialog uninstallerRollout
        ) else if (maxPkgUninstallIsWebAddress targetAddress) then (
            navigationArgs.Cancel = true
            try (shellLaunch targetAddress "") catch()
        )
        return true
    ),

    fn handleUninstallerClose = (
        try (enableAccelerators = true) catch()
        return true
    ),

    fn showUninstaller = (
        try (destroyDialog uninstallerRollout) catch()
        uninstallerRollout.hookOwner = this
        uninstallerRollout.title = "Uninstall " + packageTitle
        createDialog uninstallerRollout width: 500 height: 420 modal: false style: #(#style_titlebar, #style_sysmenu, #style_toolwindow)
        return true
    ),

    fn start = (
        isSafeTempPackageFolder = maxPkgUninstallIsSafeTempFolder scriptDir manifestFilePath
        if (MaxPkg != undefined and isSafeTempPackageFolder) do (
            if (not (runCustomUninstallScript())) do throw ("The custom uninstall script could not be completed.\n" + customUninstallFailureContent)
        )
        if (MaxPkg == undefined) do (
            loadPackageData()
            showUninstaller()
        )
        return true
    ),

    on create do start()
)

MaxPkgUninstallHookData()
