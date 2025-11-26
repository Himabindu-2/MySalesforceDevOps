#!groovy
node {

    // Prevent parallel builds
    properties([disableConcurrentBuilds()])

    // ---------------- CONFIG ----------------
    def TOOLBELT         = tool 'toolbelt'                       // Jenkins Tool installation name (path to sf)
    def JWT_KEY_CRED_ID  = env.JWT_CRED_ID_DH                    // Jenkins Secret File (server.key)
    def ORG1_USERNAME    = env.HUB_ORG_DH1                       // UAT (release branch)
    def ORG1_CLIENT_ID   = env.CONNECTED_APP_CONSUMER_KEY_DH1
    def ORG2_USERNAME    = env.HUB_ORG_DH                        // PROD (main branch)
    def ORG2_CLIENT_ID   = env.CONNECTED_APP_CONSUMER_KEY_DH
    def SFDC_HOST        = env.SFDC_HOST_DH ?: "https://login.salesforce.com"
    def API_VERSION      = '59.0'                                // package.xml API version
     
    // ---------------- PREP PATH ----------------
    stage('Set PATH for sf') {
        // tool(...) returns the folder path to the tool installation. Prepend to PATH so "sf" is available.
        env.PATH = "${TOOLBELT};${env.PATH}"
        bat 'where sf || echo "sf not found in PATH"'
        // show version (helpful debug)
        bat 'sf --version || echo "sf --version failed"'
    }

    // ---------------- CLI UPDATE ----------------
    stage('Update Salesforce CLI') {
        // run the sfupdate wrapper (so we keep your requested alias)
        bat 'sfupdate.bat'
    }

    // ---------------- BRANCH CHECK ----------------
    def branchRaw = env.BRANCH_NAME ?: ""
    def branch = branchRaw.toLowerCase()
    echo "Branch: ${branchRaw}"

    if (!(branch == "main" || branch == "release")) {
        echo "Skipping: only 'main' and 'release' should run."
        currentBuild.result = "SUCCESS"
        return
    }

    // ---------------- CHECKOUT ----------------
    stage("Checkout") {
        checkout scm
        bat(returnStatus: true, script: "git fetch --all --prune")

        def isShallow = bat(returnStdout: true, script: "git rev-parse --is-shallow-repository 2>nul || echo false").trim()
        if (isShallow == "true") {
            bat(returnStatus: true, script: "git fetch --unshallow || echo 'unshallow failed'")
        }
        // Print workspace for debugging
        bat 'echo PWD=%cd% & dir /b'
    }

    // ---------------- FIND CHANGES (vs last successful commit) ----------------
    stage("Find changed files") {
        // Baseline = last successful Git commit from this job, else HEAD~1
        def baseline = env.GIT_PREVIOUS_SUCCESSFUL_COMMIT
        if (!baseline?.trim()) {
            echo "GIT_PREVIOUS_SUCCESSFUL_COMMIT not set, using HEAD~1 as baseline (first run / no prior success)"
            baseline = "HEAD~1"
        } else {
            echo "Using last successful commit as baseline: ${baseline}"
        }

        // Just for visibility
        echo "Diff range for delta: ${baseline}..HEAD"

        // Best-effort fetch (not critical for local diff)
        bat 'git fetch --all --prune || echo "git fetch failed (non-fatal)"'

        def diffCmd = "git diff --name-only ${baseline} HEAD || echo"
        def raw = bat(returnStdout: true, script: diffCmd).trim()
        echo "Raw changed files vs ${baseline}..HEAD:\n${raw}"

        def changed = []
        if (raw) {
            // Consider only Salesforce source paths
            changed = raw.readLines().findAll {
                it.startsWith("force-app/") || it.startsWith("main/default/") || it.startsWith("src/")
            }
        }

        if (!changed || changed.size() == 0) {
            echo "✔ No force-app/main-default/src changes detected since last successful build. Nothing to deploy."
            currentBuild.result = "SUCCESS"
            return
        }

        echo "Files detected by git (Salesforce scope only):\n${changed.join('\n')}"
        env.CHANGED_RAW = changed.join(";")
    }

    // ---------------- EXPAND CHANGED FILES (bundles, meta.xml, objects) ----------------
    stage("Expand changed files") {
        def rawList = (env.CHANGED_RAW ?: "").split(";") as List
        def expanded = []

        rawList.each { f ->
            if (!f?.trim()) return
            expanded << f

            // normalize path for fileExists checks
            def meta = f + "-meta.xml"
            if (!f.endsWith("-meta.xml") && f.contains(".") && (fileExists(meta) || fileExists("${pwd()}\\\\${meta}"))) {
                expanded << meta
            }

            // LWC bundle: include all files under the bundle folder
            if (f.contains("/lwc/") || f.contains("\\lwc\\")) {
                def parts = f.replaceAll('\\\\','/').split("/")
                def idx = parts.findIndexOf { it == "lwc" }
                if (idx >= 0 && parts.length > idx+1) {
                    def bundle = parts[0..(idx+1)].join("/")
                    def files = findFiles(glob: "${bundle}/**")
                    files.each { expanded << it.path }
                }
            }

            // Aura bundle
            if (f.contains("/aura/") || f.contains("\\aura\\")) {
                def parts = f.replaceAll('\\\\','/').split("/")
                def idx = parts.findIndexOf { it == "aura" }
                if (idx >= 0 && parts.length > idx+1) {
                    def bundle = parts[0..(idx+1)].join("/")
                    def files = findFiles(glob: "${bundle}/**")
                    files.each { expanded << it.path }
                }
            }

            // objects folder -> include entire object folder (fields, recordTypes...)
            if (f.contains("/objects/") || f.contains("\\objects\\")) {
                def normalized = f.replaceAll('\\\\','/')
                def idx = normalized.indexOf("/objects/")
                if (idx >= 0) {
                    // get the object folder path (e.g. force-app/main/default/objects/Account)
                    def remainder = normalized.substring(idx + "/objects/".length())
                    def parts = remainder.split('/')
                    def objFolder = normalized.substring(0, idx + "/objects/".length()) + parts[0]
                    def files = findFiles(glob: "${objFolder}/**")
                    files.each { expanded << it.path }
                }
            }
        }

        expanded = expanded.unique().findAll { it }
        echo "Expanded file list:\n${expanded.join('\n')}"
        env.CHANGED_FILES = expanded.join(";")
    }

    // ---------------- PREPARE DELTA FOLDER ----------------
    def TMP = "ci_tmp_${env.BUILD_NUMBER ?: '0'}"
    stage("Prepare Delta Package") {
        // cleanup
        bat(returnStatus: true, script: """
powershell -NoProfile -Command "Remove-Item -Path '${TMP}' -Recurse -Force -ErrorAction SilentlyContinue"
""")
        bat "mkdir ${TMP}"

        // write copy script (PowerShell)
        def ps = '''
param([string]$filesString, [string]$tmp)
$files = $filesString -split ';' | % { $_.Trim() } | ? { $_ -ne '' }
foreach ($f in $files) {
  if (!(Test-Path $f)) { Write-Host "Missing file: $f"; continue }
  $dest = Join-Path $tmp $f
  $destDir = Split-Path $dest -Parent
  if (!(Test-Path $destDir)) { New-Item -ItemType Directory -Path $destDir -Force | Out-Null }
  Copy-Item $f $dest -Force
}
'''
        writeFile file: "${TMP}\\copy.ps1", text: ps

        // copy expanded changed files into TMP
        def filesString = env.CHANGED_FILES ?: ""
        bat """
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
 "& { & '${pwd().toString().replaceAll('\\\\','\\\\\\\\')}\\\\${TMP}\\\\copy.ps1' -filesString '${filesString}' -tmp '${pwd().toString().replaceAll('\\\\','\\\\\\\\')}\\\\${TMP}'; }"
"""
        // list TMP contents for debugging
        bat "dir ${TMP} /s"
    }

    // ---------------- RESOLVE METADATA TYPES & BUILD package.xml ----------------
    stage("Resolve types & generate package.xml") {
        def files = (env.CHANGED_FILES ?: "").split(";") as List
        def map = [:] // type -> set(names)

        files.each { f ->
            if (!f) return
            // build path to file inside TMP
            def safeF = f.replaceAll('\\\\','/')
            def filePath = "${pwd().toString()}\\\\${TMP}\\\\${safeF.replaceAll('/','\\\\\\\\')}"
            def tmpOutName = safeF.replaceAll(/[\\\\\\/:*?"<>| ]/,'_') + ".json"
            def tmpOut = "${TMP}\\\\${tmpOutName}"

            // Run sf metadata type once and capture output to tmpOut
            def cmd = "${TOOLBELT}\\\\sf metadata type --file \"${filePath}\" --json > \"${tmpOut}\" 2>&1 & echo %ERRORLEVEL%"
            def rcLine = bat(returnStdout: true, script: cmd).trim()
            def rc = 1
            try {
                rc = rcLine.tokenize().last().toInteger()
            } catch (ignored) {}

            def outText = "{}"
            if (fileExists(tmpOut)) outText = readFile(tmpOut)

            if (rc != 0) {
                echo "sf metadata type failed for ${f}. Output:\n${outText}"
            } else {
                echo "sf metadata type succeeded for ${f}. Output file: ${tmpOut}"
            }

            def t = null
            def n = null
            try {
                def parsed = readJSON text: outText
                t = parsed?.result?.metadataType
                n = parsed?.result?.fullName
            } catch (err) {
                // ignore parse error -> fallback heuristics
            }

            // Fallback heuristics if sf couldn't determine type/fullName
            if (!t || !n) {
                if (f.contains("/classes/") && f.endsWith(".cls")) {
                    t = "ApexClass"; n = (new File(f)).getName().replaceAll(/\.cls$/,'')
                } else if (f.contains("/triggers/") && (f.endsWith(".trigger") || f.endsWith(".trigger-meta.xml"))) {
                    t = "ApexTrigger"; n = (new File(f)).getName().replaceAll(/(\.trigger|-meta\.xml)$/,'')
                } else if (f.replaceAll('\\\\','/').contains("/lwc/")) {
                    t = "LightningComponentBundle"
                    def parts = f.replaceAll('\\\\','/').split('/')
                    def idx = parts.findIndexOf { it == 'lwc' }
                    if (idx >= 0 && parts.length > idx+1) n = parts[idx+1]
                } else if (f.replaceAll('\\\\','/').contains("/aura/")) {
                    t = "AuraDefinitionBundle"
                    def parts = f.replaceAll('\\\\','/').split('/')
                    def idx = parts.findIndexOf { it == 'aura' }
                    if (idx >= 0 && parts.length > idx+1) n = parts[idx+1]
                } else {
                    def fname = (new File(f)).getName().replaceAll(/-meta\.xml$/,'').replaceAll(/\..*$/,'')
                    // choose a reasonable default type for unknown items (will be included as members)
                    t = "CustomMetadata"
                    n = fname
                }
            }

            if (t && n) {
                if (!map[t]) map[t] = [] as Set
                map[t] << n
            } else {
                echo "Warning: couldn't resolve metadata for: ${f}"
            }
        }

        // build package.xml
        def xml = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<Package xmlns=\"http://soap.sforce.com/2006/04/metadata\">\n"
        map.each { type, names ->
            xml += "  <types>\n"
            names.each { nm -> xml += "    <members>${nm}</members>\n" }
            xml += "    <name>${type}</name>\n"
            xml += "  </types>\n"
        }
        xml += "  <version>${API_VERSION}</version>\n</Package>\n"

        writeFile file: "${TMP}/package.xml", text: xml
        echo "Generated package.xml:\n${xml}"
    }

    // ---------------- CONVERT TO MDAPI ----------------
    stage("Convert to MDAPI") {
        def rc = bat(returnStatus: true, script: "${TOOLBELT}\\\\sf project convert source --root-dir ${TMP} --output-dir ${TMP}\\\\mdapi_output")
        if (rc != 0) error "MDAPI conversion failed"
        echo "MDAPI output ready at ${TMP}\\\\mdapi_output"
    }

    // ---------------- ZIP the MDAPI ----------------
    stage("Zip MDAPI") {
        bat(returnStatus: true, script: "powershell -NoProfile -Command \"Compress-Archive -Path '${TMP}\\\\mdapi_output\\\\*' -DestinationPath '${TMP}\\\\delta.zip' -Force\"")
        archiveArtifacts artifacts: "${TMP}\\\\delta.zip", fingerprint: true
        echo "Delta zip archived: ${TMP}\\\\delta.zip"

        // list zip contents for debugging
        bat "powershell -NoProfile -Command \"Add-Type -AssemblyName System.IO.Compression.FileSystem; [System.IO.Compression.ZipFile]::OpenRead('${TMP}\\\\delta.zip').Entries | ForEach-Object { Write-Host $_.FullName }\""
    }

    // ---------------- DEPLOY ----------------
    def deploySucceeded = false
    def deployedComponents = []

    withCredentials([file(credentialsId: JWT_KEY_CRED_ID, variable: "JWT_KEY_FILE")]) {

        def isRelease = (branch == "release")
        def orgUser   = isRelease ? ORG1_USERNAME : ORG2_USERNAME
        def orgClient = isRelease ? ORG1_CLIENT_ID : ORG2_CLIENT_ID
        def alias     = isRelease ? "ORG1" : "ORG2"

        stage("Deploy to ${alias}") {

            echo "Authenticating to ${alias} as ${orgUser}"

            def authCmd = """${TOOLBELT}\\\\sf org login jwt --instance-url ${SFDC_HOST} --client-id ${orgClient} --username ${orgUser} --jwt-key-file %JWT_KEY_FILE% --setalias ${alias}"""
            if (bat(returnStatus: true, script: authCmd) != 0) {
                error "Authentication failed for ${alias}"
            }

            // Start deployment and capture JSON report to file (use --wait so report is produced)
            def deployCmd = "${TOOLBELT}\\\\sf project deploy start --zip-file ${TMP}\\\\delta.zip --target-org ${alias} --wait 60 --json > ${TMP}\\\\deployReport.json 2>&1"
            bat returnStatus: true, script: deployCmd // do not immediately fail here so we can read report

            if (!fileExists("${TMP}\\\\deployReport.json")) {
                echo "Deploy report not found at ${TMP}\\\\deployReport.json. Dumping raw sf output for debug:"
                bat "type ${TMP}\\\\deployReport.json || echo 'no deployReport file present'"
                error "Deployment report missing; failing build for visibility."
            }

            def reportText = readFile "${TMP}\\\\deployReport.json"
            echo "Raw deployReport.json:\n${reportText}"

            try {
                def parsed = readJSON text: reportText
                def comps = parsed?.result?.details?.componentSuccesses ?: []
                echo "==== Deployed Components (detailed) ===="
                if (comps.size() == 0) {
                    echo "No componentSuccesses found in report."
                } else {
                    comps.each { c ->
                        def action = (c.created ? "CREATED" : (c.deleted ? "DELETED" : (c.changed ? "MODIFIED" : "UNKNOWN")))
                        def name = c.fullName ?: c.fileName ?: 'n/a'
                        def line = "${c.componentType ?: ''} | ${name} | ${action} | success=${c.success}"
                        echo line
                        deployedComponents << line
                    }
                }

                def status = parsed?.result?.status
                echo "Deployment status: ${status}"
                if (status == "Succeeded" || status == "SucceededPartial") {
                    deploySucceeded = true
                } else {
                    error "Deployment reported status ${status}. See deployReport.json for details."
                }
            } catch (err) {
                echo "Could not parse deploy report JSON: ${err}"
                error "Failed to parse deployment report."
            }
        }
    }
    if (deploySucceeded) {
        if (branch == "release") {
            echo "Deployment completed to ${ORG1_USERNAME}"
        } else if (branch == "main") {
            echo "Deployment completed to ${ORG2_USERNAME}"
        }

        // Print deployed components summary and set build description
        if (deployedComponents.size() > 0) {
            echo "=== SUMMARY: Deployed Components ==="
            deployedComponents.each { echo it }
            try {
                currentBuild.description = "Deployed: " + deployedComponents.take(10).join(", ")
            } catch (e) { /* ignore if Jenkins disallows */ }
        } else {
            echo "No deployed components were recorded in the report."
        }
    }
}
