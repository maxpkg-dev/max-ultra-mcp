/*

	ADVANCED CUSTOM INSTALLER OVERRIDE

	Most packages should use this standard MaxPkg installer unchanged.
	For focused project-specific setup, select a separate Custom Install Script
	in MaxPkg Packager. It will run safely from the extracted package folder.

	Advanced authors may replace the installer body inside the existing
	if (MaxPkg == undefined) block with their own installation code.

	Use getThisScriptFileName() to resolve your installer dynamically because
	MaxPkg extracts every package into a dynamic $temp\<GUID> folder.

	Example: run installer\setup.ms only when MaxPkg is not available:

	(
		if (MaxPkg == undefined) do (
			local customInstallerFilePath = (getFilenamePath (getThisScriptFileName())) + "installer\\setup.ms"
			fileIn customInstallerFilePath
		)
	)

*/


struct MaxPkgInstallHookData (
    currScript = getSourceFileName(),
    scriptDir = getFilenamePath currScript,
    manifestFilePath = scriptDir + "manifest.ini",
    settingsFilePath = scriptDir + "maxpkg-packager.ini",
    changelogFilePath = scriptDir + "maxpkg-changelog.ini",
    uninstallHookFilePath = scriptDir + "_uninstall.ms",
    isSafeTempPackageFolder = false,
    isCustomInstallComplete = false,
    isInstallConfirmed = false,
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
    changelogHtml = "",

    fn maxPkgHookNormalizeFolder folderPath = (
        local normalizedFolder = substituteString (folderPath as string) "/" "\\"

        while (normalizedFolder.count > 0 and (substring normalizedFolder normalizedFolder.count 1) == "\\") do (
            normalizedFolder = substring normalizedFolder 1 (normalizedFolder.count - 1)
        )

        return toLower normalizedFolder
    ),

    fn maxPkgHookIsGuid guidContent = (
        local normalizedGuid = toLower (guidContent as string)
        local allowedCharacters = "0123456789abcdef-"

        if (normalizedGuid.count != 36) do return false
        if ((substring normalizedGuid 9 1) != "-" or (substring normalizedGuid 14 1) != "-" or (substring normalizedGuid 19 1) != "-" or (substring normalizedGuid 24 1) != "-") do return false

        for characterIndex in 1 to normalizedGuid.count do (
            if ((findString allowedCharacters (substring normalizedGuid characterIndex 1)) == undefined) do return false
        )

        return true
    ),

    fn maxPkgHookIsSafeTempPackageFolder packageFolder manifestFilePath = (
        if (not (doesFileExist manifestFilePath)) do return false

        local packageGuid = getINISetting manifestFilePath "package" "packageGuid"
        if (not (maxPkgHookIsGuid packageGuid)) do return false

        local expectedFolder = (getDir #temp) + "\\" + packageGuid
        return (maxPkgHookNormalizeFolder packageFolder) == (maxPkgHookNormalizeFolder expectedFolder)
    ),

    fn maxPkgHookStartsWith sourceContent prefixContent = (
        if (sourceContent == undefined or prefixContent == undefined) do return false

        local sourceString = sourceContent as string
        local prefixString = prefixContent as string
        if (sourceString.count < prefixString.count) do return false
        return (substring sourceString 1 prefixString.count) == prefixString
    ),

    fn maxPkgHookRunCustomScript packageFolder manifestFilePath manifestKey = (
        if (not (maxPkgHookIsSafeTempPackageFolder packageFolder manifestFilePath)) do return false

        local relativeScriptFile = getINISetting manifestFilePath "package" manifestKey
        if (relativeScriptFile == undefined or relativeScriptFile == "") do return true
        if ((toLower (getFilenameType relativeScriptFile)) != ".ms") do return false

        try (
            local ioPathClass = dotNetClass "System.IO.Path"
            local packageRoot = maxPkgHookNormalizeFolder (ioPathClass.GetFullPath packageFolder)
            local resolvedScriptFile = maxPkgHookNormalizeFolder (ioPathClass.GetFullPath (packageFolder + relativeScriptFile))
            local packagePrefix = packageRoot + "\\"

            if (not (maxPkgHookStartsWith resolvedScriptFile packagePrefix)) do return false
            if (not (doesFileExist resolvedScriptFile)) do return false
            fileIn resolvedScriptFile
            return true
        ) catch (
            return false
        )
    ),

    fn maxPkgHookEscapeHtml sourceContent = (
        local escapedContent = if sourceContent == undefined then "" else sourceContent as string
        escapedContent = substituteString escapedContent "&" "&amp;"
        escapedContent = substituteString escapedContent "<" "&lt;"
        escapedContent = substituteString escapedContent ">" "&gt;"
        escapedContent = substituteString escapedContent "\"" "&quot;"
        escapedContent = substituteString escapedContent "'" "&#39;"
        return escapedContent
    ),

    fn maxPkgHookReadSetting manifestFilePath settingsFilePath manifestKey settingsKey fallbackContent: "" = (
        local settingContent = ""

        if (doesFileExist manifestFilePath) do settingContent = getINISetting manifestFilePath "package" manifestKey
        if ((settingContent == undefined or settingContent == "") and doesFileExist settingsFilePath) do (
            settingContent = getINISetting settingsFilePath "settings" settingsKey
        )
        if (settingContent == undefined or settingContent == "") do settingContent = fallbackContent
        return settingContent
    ),

    fn maxPkgHookResolveIconFile packageFolder iconContent = (
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

    fn maxPkgHookImageDataUri imageFilePath = (
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

    fn maxPkgHookIsWebAddress addressContent = (
        if (addressContent == undefined or addressContent == "") do return false

        local normalizedAddress = toLower (addressContent as string)
        if (maxPkgHookStartsWith normalizedAddress "https://") do return true
        if (maxPkgHookStartsWith normalizedAddress "http://") do return true
        return false
    ),

    fn maxPkgHookChangelogClass changeTypeContent = (
        local normalizedChangeType = toLower (changeTypeContent as string)

        case normalizedChangeType of (
            "added": return "added"
            "fixed": return "fixed"
            "improved": return "improved"
            "imporoved": return "improved"
            "changed": return "changed"
            "removed": return "removed"
            "deleted": return "removed"
            default: return "default"
        )
    ),

    fn maxPkgHookLucideSvg iconId = (
        case iconId of (
            "circle-check": return "<svg class='ui-icon' viewBox='0 0 24 24' fill='none' stroke='currentColor' stroke-width='2' stroke-linecap='round' stroke-linejoin='round' aria-hidden='true'><circle cx='12' cy='12' r='10'/><path d='m9 12 2 2 4-4'/></svg>"
            "info": return "<svg class='ui-icon' viewBox='0 0 24 24' fill='none' stroke='currentColor' stroke-width='2' stroke-linecap='round' stroke-linejoin='round' aria-hidden='true'><circle cx='12' cy='12' r='10'/><line x1='12' y1='16' x2='12' y2='12'/><line x1='12' y1='8' x2='12.01' y2='8'/></svg>"
            "download": return "<svg class='ui-icon' viewBox='0 0 24 24' fill='none' stroke='currentColor' stroke-width='2' stroke-linecap='round' stroke-linejoin='round' aria-hidden='true'><path d='M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4'/><polyline points='7 10 12 15 17 10'/><line x1='12' y1='15' x2='12' y2='3'/></svg>"
            "trash-2": return "<svg class='ui-icon' viewBox='0 0 24 24' fill='none' stroke='currentColor' stroke-width='2' stroke-linecap='round' stroke-linejoin='round' aria-hidden='true'><polyline points='3 6 5 6 21 6'/><path d='M19 6l-1 14H6L5 6m3 0V4h8v2'/><line x1='10' y1='11' x2='10' y2='17'/><line x1='14' y1='11' x2='14' y2='17'/></svg>"
            "x": return "<svg class='ui-icon' viewBox='0 0 24 24' fill='none' stroke='currentColor' stroke-width='2' stroke-linecap='round' stroke-linejoin='round' aria-hidden='true'><line x1='18' y1='6' x2='6' y2='18'/><line x1='6' y1='6' x2='18' y2='18'/></svg>"
            "external-link": return "<svg class='ui-icon' viewBox='0 0 24 24' fill='none' stroke='currentColor' stroke-width='2' stroke-linecap='round' stroke-linejoin='round' aria-hidden='true'><path d='M15 3h6v6'/><path d='M10 14 21 3'/><path d='M18 13v6a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2h6'/></svg>"
            "home": return "<svg class='ui-icon' viewBox='0 0 24 24' fill='none' stroke='currentColor' stroke-width='2' stroke-linecap='round' stroke-linejoin='round' aria-hidden='true'><path d='m3 9 9-7 9 7v11a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z'/><polyline points='9 22 9 12 15 12 15 22'/></svg>"
            "book-open": return "<svg class='ui-icon' viewBox='0 0 24 24' fill='none' stroke='currentColor' stroke-width='2' stroke-linecap='round' stroke-linejoin='round' aria-hidden='true'><path d='M2 3h6a4 4 0 0 1 4 4v14a3 3 0 0 0-3-3H2z'/><path d='M22 3h-6a4 4 0 0 0-4 4v14a3 3 0 0 1 3-3h7z'/></svg>"
            "circle-help": return "<svg class='ui-icon' viewBox='0 0 24 24' fill='none' stroke='currentColor' stroke-width='2' stroke-linecap='round' stroke-linejoin='round' aria-hidden='true'><circle cx='12' cy='12' r='10'/><path d='M9.09 9a3 3 0 1 1 5.83 1c0 2-3 3-3 3'/><path d='M12 17h.01'/></svg>"
            "file-text": return "<svg class='ui-icon' viewBox='0 0 24 24' fill='none' stroke='currentColor' stroke-width='2' stroke-linecap='round' stroke-linejoin='round' aria-hidden='true'><path d='M14.5 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V7.5z'/><polyline points='14 2 14 8 20 8'/><line x1='16' y1='13' x2='8' y2='13'/><line x1='16' y1='17' x2='8' y2='17'/></svg>"
            "shopping-cart": return "<svg class='ui-icon' viewBox='0 0 24 24' fill='none' stroke='currentColor' stroke-width='2' stroke-linecap='round' stroke-linejoin='round' aria-hidden='true'><circle cx='9' cy='20' r='1'/><circle cx='19' cy='20' r='1'/><path d='M3 4h2l2.4 11.2a2 2 0 0 0 2 1.6h7.7a2 2 0 0 0 2-1.6L21 8H6'/></svg>"
            "package": return "<svg class='ui-icon' viewBox='0 0 24 24' fill='none' stroke='currentColor' stroke-width='2' stroke-linecap='round' stroke-linejoin='round' aria-hidden='true'><path d='M16.5 9.4 7.5 4.2'/><path d='M21 16V8a2 2 0 0 0-1-1.7l-7-4a2 2 0 0 0-2 0l-7 4A2 2 0 0 0 3 8v8a2 2 0 0 0 1 1.7l7 4a2 2 0 0 0 2 0l7-4A2 2 0 0 0 21 16z'/><polyline points='3.3 7 12 12 20.7 7'/><line x1='12' y1='22' x2='12' y2='12'/></svg>"
            default: return ""
        )
    ),

    fn runCustomInstallScript = (
        if isCustomInstallComplete do return true
        if (not isSafeTempPackageFolder) do return false

        isCustomInstallComplete = maxPkgHookRunCustomScript scriptDir manifestFilePath "customInstallScript"
        return isCustomInstallComplete
    ),

    fn maxPkgHookCleanupPackageFolder packageFolder packageGuid = (
        if (not (maxPkgHookIsGuid packageGuid)) do return false

        local expectedFolder = (getDir #temp) + "\\" + packageGuid
        if ((maxPkgHookNormalizeFolder packageFolder) != (maxPkgHookNormalizeFolder expectedFolder)) do return false
        if (not (doesDirectoryExist packageFolder)) do return true

        try (
            (dotNetClass "System.IO.Directory").Delete packageFolder true
            return true
        ) catch (
            return false
        )
    ),

    fn loadPackageData = (
        packageGuid = maxPkgHookReadSetting manifestFilePath settingsFilePath "packageGuid" "packageGuid" fallbackContent: ""
        packageTitle = maxPkgHookReadSetting manifestFilePath settingsFilePath "name" "packageName" fallbackContent: "Package"
        packageVersion = maxPkgHookReadSetting manifestFilePath settingsFilePath "version" "version" fallbackContent: "1.0.0"
        developerTitle = maxPkgHookReadSetting manifestFilePath settingsFilePath "developerName" "developerName" fallbackContent: "Unknown developer"
        homepageUrl = maxPkgHookReadSetting manifestFilePath settingsFilePath "homepage" "homepage" fallbackContent: ""
        documentationUrl = maxPkgHookReadSetting manifestFilePath settingsFilePath "documentation" "documentation" fallbackContent: ""
        supportUrl = maxPkgHookReadSetting manifestFilePath settingsFilePath "support" "support" fallbackContent: ""
        licenseUrl = maxPkgHookReadSetting manifestFilePath settingsFilePath "licenseUrl" "licenseUrl" fallbackContent: ""
        purchaseUrl = maxPkgHookReadSetting manifestFilePath settingsFilePath "purchase" "purchase" fallbackContent: ""
        purchaseButtonLabel = maxPkgHookReadSetting manifestFilePath settingsFilePath "purchaseButtonLabel" "purchaseButtonLabel" fallbackContent: "Buy"

        local packageIconRel = maxPkgHookReadSetting manifestFilePath settingsFilePath "icon" "svgIcon" fallbackContent: ""
        local packageIconFilePath = maxPkgHookResolveIconFile scriptDir packageIconRel
        packageIconDataUri = maxPkgHookImageDataUri packageIconFilePath
        changelogHtml = ""
        isInstallConfirmed = false

        local changelogSectionName = "version_" + packageVersion
        local changelogCount = try ((getINISetting changelogFilePath changelogSectionName "count") as integer) catch(0)
        for changelogIndex in 1 to changelogCount do (
            local itemType = getINISetting changelogFilePath changelogSectionName ((changelogIndex as string) + "_type")
            local itemContent = getINISetting changelogFilePath changelogSectionName ((changelogIndex as string) + "_text")
            if (itemType != undefined and itemType != "" and itemContent != undefined and itemContent != "") do (
                local escapedItemType = maxPkgHookEscapeHtml itemType
                local escapedItemContent = maxPkgHookEscapeHtml itemContent
                local changelogClass = maxPkgHookChangelogClass itemType
                escapedItemContent = substituteString escapedItemContent "\\n" "<br>"
                escapedItemContent = substituteString escapedItemContent "\r\n" "<br>"
                escapedItemContent = substituteString escapedItemContent "\n" "<br>"
                changelogHtml += "<li><span class='change-type change-type-" + changelogClass + "'>" + escapedItemType + "</span><span class='change-content'>" + escapedItemContent + "</span></li>"
            )
        )
        if (changelogHtml == "") do changelogHtml = "<li class='empty-change'>No changelog entries for this version.</li>"
        return true
    ),

    fn buildInstallerHtml = (
        local escapedPackageTitle = maxPkgHookEscapeHtml packageTitle
        local escapedPackageVersion = maxPkgHookEscapeHtml packageVersion
        local escapedDeveloperTitle = maxPkgHookEscapeHtml developerTitle
        local packageInitials = toUpper (substring packageTitle 1 (amin packageTitle.count 2))
        local iconMarkup = "<span class='icon-fallback'>" + (maxPkgHookEscapeHtml packageInitials) + "</span>"
        local modeBadge = if isSafeTempPackageFolder then "" else "<span class='preview-badge'>Preview</span>"
        local contentMarkup = ""
        local resourceLinksMarkup = ""
        local uninstallMarkup = ""
        local primaryLabel = if isInstallConfirmed then "Close" else "Install"
        local primaryIcon = if isInstallConfirmed then maxPkgHookLucideSvg "x" else maxPkgHookLucideSvg "download"
        local bodyClass = if isInstallConfirmed then "installed-state" else "release-state"

        if (packageIconDataUri != "") do iconMarkup = "<img src='" + packageIconDataUri + "' alt='Package icon'>"

        if isInstallConfirmed then (
            if isSafeTempPackageFolder then (
                contentMarkup = "<section class='status-card success-card'><div class='status-mark'>" + (maxPkgHookLucideSvg "circle-check") + "</div><div><h2>Installed successfully</h2><p>The package is ready to use.</p></div></section>" +
                    "<section class='guide-card'><div class='section-label'>Toolbar button</div><h2>Add the package to a toolbar</h2><p>Open <strong>Customize &rarr; Customize User Interface</strong>, select the <strong>MaxPkg</strong> group, then drag and drop the package button onto a toolbar.</p></section>"
            ) else (
                contentMarkup = "<section class='status-card preview-card'><div class='status-mark'>" + (maxPkgHookLucideSvg "info") + "</div><div><h2>Preview mode</h2><p>This hook is running outside its extracted <strong>$temp\\&lt;GUID&gt;</strong> package folder. No installation or file removal was performed.</p></div></section>"
            )
        ) else (
            contentMarkup = "<section class='changelog-card'><div class='section-label'>Release notes</div><h2>What's new in " + escapedPackageVersion + "</h2><ul class='change-list'>" + changelogHtml + "</ul></section>"
        )

        if (maxPkgHookIsWebAddress homepageUrl) do resourceLinksMarkup += "<a class='resource-link' href='" + (maxPkgHookEscapeHtml homepageUrl) + "'>" + (maxPkgHookLucideSvg "home") + "Developer site</a>"
        if (maxPkgHookIsWebAddress documentationUrl) do resourceLinksMarkup += "<a class='resource-link' href='" + (maxPkgHookEscapeHtml documentationUrl) + "'>" + (maxPkgHookLucideSvg "book-open") + "Docs</a>"
        if (maxPkgHookIsWebAddress supportUrl) do resourceLinksMarkup += "<a class='resource-link' href='" + (maxPkgHookEscapeHtml supportUrl) + "'>" + (maxPkgHookLucideSvg "circle-help") + "Support</a>"
        if (maxPkgHookIsWebAddress licenseUrl) do resourceLinksMarkup += "<a class='resource-link' href='" + (maxPkgHookEscapeHtml licenseUrl) + "'>" + (maxPkgHookLucideSvg "file-text") + "License</a>"
        if (maxPkgHookIsWebAddress purchaseUrl) do resourceLinksMarkup += "<a class='resource-link purchase-link' href='" + (maxPkgHookEscapeHtml purchaseUrl) + "'>" + (maxPkgHookLucideSvg "shopping-cart") + (maxPkgHookEscapeHtml purchaseButtonLabel) + "</a>"
        if (resourceLinksMarkup != "") do resourceLinksMarkup = "<nav class='resource-links'>" + resourceLinksMarkup + "</nav>"

        if (not isInstallConfirmed and doesFileExist uninstallHookFilePath) do (
            uninstallMarkup = "<a class='danger-button' href='maxpkg://uninstall'>" + (maxPkgHookLucideSvg "trash-2") + "Uninstall</a>"
        )

        local heroMarkup = "<header class='hero'><div class='package-icon'>" + iconMarkup + "</div><div class='package-meta'><div class='eyebrow'>MaxPkg package " + modeBadge + "</div><h1>" + escapedPackageTitle + "</h1><div class='package-version'>Version " + escapedPackageVersion + "<span class='separator'>&bull;</span>by " + escapedDeveloperTitle + "</div>" + resourceLinksMarkup + "</div></header>"
        local footerMarkup = "<footer class='actions'><a class='maxpkg-link' href='https://maxpkg.dev'>" + (maxPkgHookLucideSvg "package") + "maxpkg.dev</a><div class='button-row'><a class='primary-button' href='maxpkg://primary'>" + primaryIcon + primaryLabel + "</a>" + uninstallMarkup + "</div></footer>"
        local pageMarkup = if isInstallConfirmed then contentMarkup + footerMarkup else heroMarkup + footerMarkup + contentMarkup

        local htmlContent = "<!doctype html><html><head><meta charset='utf-8'><meta http-equiv='X-UA-Compatible' content='IE=edge'>" +
            "<style>" +
            "*{box-sizing:border-box}html,body{margin:0;min-height:100%;background:#20242a;color:#f4f6f8;font-family:'Segoe UI',Arial,sans-serif;font-size:14px}body{padding:8px 14px 14px}.installer{max-width:680px;margin:0 auto}.hero{display:flex;align-items:center;padding:18px;background:#2d333b;border:1px solid #434b56;border-radius:8px}.package-icon{width:112px;height:112px;min-width:112px;margin-right:20px;display:flex;align-items:center;justify-content:center;overflow:hidden;background:#c8d0da;border:1px solid #5c6876;border-radius:8px}.package-icon img{display:block;width:100px;height:100px}.icon-fallback{font-size:30px;font-weight:700;color:#34445e}.package-meta{min-width:0}.eyebrow{margin-bottom:8px;color:#91a0b3;font-size:11px;font-weight:700;text-transform:uppercase;letter-spacing:1px}.package-meta h1{margin:0 0 10px;font-size:25px;line-height:1.2;overflow-wrap:break-word}.package-version{color:#b9c3d0;font-size:14px}.separator{padding:0 7px;color:#657182}.preview-badge{display:inline-block;margin-left:10px;padding:3px 8px;border:1px solid #9d7834;border-radius:10px;color:#f2c66f;font-size:11px;text-transform:uppercase}.changelog-card,.guide-card{margin-top:14px;padding:18px 20px;background:#2a2f36;border:1px solid #404853;border-radius:8px}.section-label{margin-bottom:5px;color:#7fa8ef;font-size:11px;font-weight:700;text-transform:uppercase;letter-spacing:.8px}.changelog-card h2,.guide-card h2,.status-card h2{margin:0 0 10px;font-size:18px}.change-list{margin:0;padding:0;list-style:none;max-height:160px;overflow-y:auto}.change-list li{display:flex;padding:9px 0;border-top:1px solid #3b424c;line-height:1.4}.change-list li:first-child{border-top:0}.change-type{min-width:78px;margin-right:12px;color:#8fb3f4;font-weight:700}.change-content{color:#dce2e9}.empty-change{color:#929eac}.status-card{display:flex;align-items:center;margin-top:14px;padding:19px;border-radius:8px}.success-card{background:#203a2c;border:1px solid #397654}.preview-card{background:#3a3222;border:1px solid #826530}.status-mark{width:44px;height:44px;min-width:44px;margin-right:15px;border:2px solid currentColor;border-radius:50%;font-size:24px;line-height:38px;text-align:center}.status-card h2{margin-bottom:5px}.status-card p,.guide-card p{margin:0;color:#cbd3dc;line-height:1.55}.actions{display:flex;align-items:center;justify-content:space-between;min-height:60px;padding:12px 2px 0}.developer-link{color:#9ebdf4;text-decoration:none}.developer-link:hover{text-decoration:underline}.primary-button{display:inline-block;min-width:126px;padding:11px 24px;border:1px solid #73a0ed;border-radius:5px;background:#4e75b8;color:#fff;font-weight:700;text-align:center;text-decoration:none}.primary-button:hover{background:#5a84ca}@media(max-width:480px){body{padding:6px 10px 10px}.hero{padding:14px}.package-icon{width:96px;height:96px;min-width:96px;margin-right:14px}.package-icon img{width:86px;height:86px}.package-meta h1{font-size:21px}}" +
            "html,body{height:100%;min-height:0;overflow:hidden}body{padding:5px 10px 10px}.installer{height:100%;display:flex;flex-direction:column}.hero{flex:0 0 auto;padding:12px 15px}.package-icon{width:100px;height:100px;min-width:100px;margin-right:17px;background:#242930;border-color:#4b5664}.package-icon img{width:92px;height:92px}.package-meta h1{font-size:23px}.ui-icon{display:inline-block;width:15px;height:15px;margin-right:7px;vertical-align:-3px}.resource-links{display:flex;flex:0 0 auto;align-items:center;flex-wrap:wrap;padding:5px 0 1px}.resource-link{margin-right:5px;padding:4px 7px;border-radius:4px;color:#9ebdf4;font-size:11px;text-decoration:none}.resource-link:hover{background:#303741}.resource-link .ui-icon{width:13px;height:13px;margin-right:5px}.purchase-link{color:#57bd91}.actions{display:flex;flex:0 0 auto;align-items:center;justify-content:space-between;min-height:46px;padding:5px 1px}.maxpkg-link{color:#9da4af;font-size:11px;text-decoration:none}.maxpkg-link:hover{color:#c6ccd5}.maxpkg-link .ui-icon{width:14px;height:14px;margin-right:5px}.button-row{display:flex;align-items:center}.button-row a{margin-left:8px}.danger-button{display:inline-block;min-width:112px;padding:10px 18px;border:1px solid #df7180;border-radius:5px;background:#a94552;color:#fff;font-weight:700;text-align:center;text-decoration:none}.danger-button:hover{background:#bd5260}.primary-button{min-width:112px;padding:10px 18px}.changelog-card{flex:1 1 auto;min-height:0;margin-top:0;padding:11px 14px;display:flex;flex-direction:column;overflow:hidden}.changelog-card .section-label{margin-bottom:2px;font-size:10px}.changelog-card h2{margin-bottom:5px;font-size:15px}.change-list{flex:1 1 auto;min-height:0;overflow-y:auto}.change-list li{align-items:flex-start;padding:5px 0;font-size:12px;line-height:1.3}.change-type{min-width:68px;margin-right:9px;padding:2px 5px;border:1px solid transparent;border-radius:3px;font-size:10px;text-align:center}.change-type-added{border-color:rgba(53,208,127,.3);background:rgba(53,208,127,.12);color:#35d07f}.change-type-fixed{border-color:rgba(247,185,85,.3);background:rgba(247,185,85,.13);color:#f7b955}.change-type-improved{border-color:rgba(124,156,255,.3);background:rgba(124,156,255,.13);color:#7c9cff}.change-type-changed{border-color:rgba(192,132,252,.3);background:rgba(192,132,252,.13);color:#c084fc}.change-type-removed{border-color:rgba(255,107,122,.3);background:rgba(255,107,122,.13);color:#ff6b7a}.change-type-default{border-color:#59616e;background:#414751;color:#c8cdd5}.status-mark{display:flex;align-items:center;justify-content:center;border:0;line-height:normal}.status-mark .ui-icon{width:40px;height:40px;margin:0}.success-card .status-mark{color:#57bd91}.preview-card .status-mark{color:#f7b955}.release-state .installer{display:block;height:auto}.release-state .changelog-card{display:block;height:215px;min-height:215px;max-height:215px}.release-state .change-list{display:block;height:160px;min-height:160px;max-height:160px;overflow-y:auto}.installed-state{overflow-y:auto}.installed-state .installer{height:auto;min-height:100%}.installed-state .status-card{margin-top:0}" +
            "</style></head><body class='" + bodyClass + "'><div class='installer'>" + pageMarkup + "</div></body></html>"

        return htmlContent
    ),

    installerRollout = rollout installerRollout "Install Package" width: 500 height: 420 (
        local hookOwner = if (hookOwner != undefined) do hookOwner
        dotNetControl dncInstallerBrowser "System.Windows.Forms.WebBrowser" width: 500 height: 420 align: #center offset: [0, -4]
        on installerRollout open do (
            dncInstallerBrowser.ScriptErrorsSuppressed = true
            dncInstallerBrowser.IsWebBrowserContextMenuEnabled = false
            dncInstallerBrowser.AllowWebBrowserDrop = false
            dncInstallerBrowser.WebBrowserShortcutsEnabled = false
            dncInstallerBrowser.ScrollBarsEnabled = true
            dncInstallerBrowser.Dock = (dotNetClass "System.Windows.Forms.DockStyle").Fill
            hookOwner.refreshInstallerBrowser()
        )
        on dncInstallerBrowser Navigating eventSender navigationArgs do hookOwner.handleInstallerNavigation navigationArgs
        on dncInstallerBrowser Enter eventSender eventArgs do try (enableAccelerators = false) catch()
        on dncInstallerBrowser Leave eventSender eventArgs do try (enableAccelerators = true) catch()
        on installerRollout close do hookOwner.handleInstallerClose()
    ),

    fn refreshInstallerBrowser = (
        if (installerRollout.dncInstallerBrowser == undefined) do return false
        installerRollout.dncInstallerBrowser.DocumentText = buildInstallerHtml()
        return true
    ),

    fn showInstalledState = (
        isInstallConfirmed = true
        installerRollout.title = if isSafeTempPackageFolder then "Install Complete" else "Installer Preview"
        try (setDialogSize installerRollout [500, 360]) catch()
        refreshInstallerBrowser()
        return true
    ),

    fn handleInstallerNavigation navigationArgs = (
        local targetAddress = try (navigationArgs.Url.AbsoluteUri as string) catch("")
        local normalizedAddress = toLower targetAddress
        if (maxPkgHookStartsWith normalizedAddress "maxpkg://primary") then (
            navigationArgs.Cancel = true
            if isInstallConfirmed then destroyDialog installerRollout else if (not isSafeTempPackageFolder) then showInstalledState() else if (runCustomInstallScript()) then showInstalledState() else messageBox "The custom install script could not be completed. The package was left in place so you can try again." title: "Installation Error"
        ) else if (maxPkgHookStartsWith normalizedAddress "maxpkg://uninstall") then (
            navigationArgs.Cancel = true
            if (doesFileExist uninstallHookFilePath) do try (fileIn uninstallHookFilePath; isInstallConfirmed = true; destroyDialog installerRollout) catch (messageBox ("Could not open the package uninstaller.\n\n" + getCurrentException()) title: "Uninstall Error")
        ) else if (maxPkgHookIsWebAddress targetAddress) then (
            navigationArgs.Cancel = true
            try (shellLaunch targetAddress "") catch()
        )
        return true
    ),

    fn handleInstallerClose = (
        try (enableAccelerators = true) catch()
        if (not isInstallConfirmed and isSafeTempPackageFolder) do maxPkgHookCleanupPackageFolder scriptDir packageGuid
        return true
    ),

    fn showInstaller = (
        try (destroyDialog installerRollout) catch()
        installerRollout.hookOwner = this
        installerRollout.title = "Install " + packageTitle
        createDialog installerRollout width: 500 height: 420 modal: false style: #(#style_titlebar, #style_sysmenu, #style_toolwindow)
        return true
    ),

    fn start = (
        isSafeTempPackageFolder = maxPkgHookIsSafeTempPackageFolder scriptDir manifestFilePath
        if (MaxPkg != undefined and isSafeTempPackageFolder) do if (not (runCustomInstallScript())) do throw "The custom install script could not be completed."
        if (MaxPkg == undefined) do (loadPackageData(); showInstaller())
        return true
    ),

    on create do start()
)

MaxPkgInstallHookData()
