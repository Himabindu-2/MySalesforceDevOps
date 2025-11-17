#!groovy
node {

    // Prevent parallel builds
    properties([disableConcurrentBuilds()])

    // ---------------- CONFIG ----------------
    def TOOLBELT         = tool 'toolbelt'
    def JWT_KEY_CRED_ID  = env.JWT_CRED_ID_DH
    def ORG1_USERNAME    = env.HUB_ORG_DH1              // UAT
    def ORG1_CLIENT_ID   = env.CONNECTED_APP_CONSUMER_KEY_DH1
    def ORG2_USERNAME    = env.HUB_ORG_DH               // PROD
    def ORG2_CLIENT_ID   = env.CONNECTED_APP_CONSUMER_KEY_DH
    def SFDC_HOST        = env.SFDC_HOST_DH ?: "https://login.salesforce.com"

    // Detect branch
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

        // Check if repo is shallow
        def isShallow = bat(returnStdout: true, script: "git rev-parse --is-shallow-repository 2>nul || echo false").trim()
        if (isShallow == "true") {
            bat(returnStatus: true, script: "git fetch --unshallow || echo 'unshallow failed'")
        }
    }

    // ---------------- FIND CHANGES ----------------
    stage("Find changed files") {
        def raw = bat(returnStdout: true,
            script: "git diff-tree -r --no-commit-id --name-only HEAD || echo").trim()

        echo "Raw changed files:\n${raw}"

        def changed = []
        if (raw) {
            changed = raw.readLines().findAll { it.startsWith("force-app/") }
        }

        if (!changed || changed.size() == 0) {
            echo "✔ No force-app changes detected. Nothing to deploy."
            currentBuild.result = "SUCCESS"
            return
        }

        echo "Files to deploy:\n${changed.join('\n')}"
        env.CHANGED_FILES = changed.join(";")
    }

    // ---------------- PREPARE PACKAGE ----------------
    def TMP = "ci_tmp_${env.BUILD_NUMBER ?: '0'}"

    stage("Prepare Package") {

        // Safe delete (never fails)
        bat(returnStatus: true, script: """
powershell -NoProfile -Command "Remove-Item -Path '${TMP}' -Recurse -Force -ErrorAction SilentlyContinue"
""")

        bat "mkdir ${TMP}"

        // PowerShell file copier
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

        def pwdEsc = pwd().replaceAll("\\\\", "\\\\\\\\")
        bat """
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
 "& { & '${pwdEsc}\\\\${TMP}\\\\copy.ps1' -filesString '${env.CHANGED_FILES}' -tmp '${pwdEsc}\\\\${TMP}'; }"
"""

        // Convert to MDAPI using latest sf
        def rcConvert = bat(returnStatus: true,
            script: "sf project convert source --root-dir ${TMP} --output-dir ${TMP}\\\\mdapi_output")
        if (rcConvert != 0) error "MDAPI conversion failed"
    }

    // ---------------- DEPLOY ----------------
    def deploySucceeded = false

    withCredentials([file(credentialsId: JWT_KEY_CRED_ID, variable: "JWT_KEY_FILE")]) {

        def isRelease = (branch == "release")
        def isMain = (branch == "main")

        def orgUser   = isRelease ? ORG1_USERNAME : ORG2_USERNAME
        def orgClient = isRelease ? ORG1_CLIENT_ID : ORG2_CLIENT_ID
        def alias     = isRelease ? "ORG1" : "ORG2"

        stage("Deploy to ${alias}") {

            echo "Authenticating to ${alias} as ${orgUser}"

            def authCmd = """
${TOOLBELT} sf org login jwt --instance-url ${SFDC_HOST} --client-id ${orgClient} --username ${orgUser} --jwt-key-file %JWT_KEY_FILE% --setalias ${alias}
"""
            if (bat(returnStatus: true, script: authCmd) != 0)
                error "Authentication failed for ${alias}"

            def deployCmd = """
${TOOLBELT} sf project deploy start --metadata-dir ${TMP}\\\\mdapi_output --target-org ${alias}
"""
            if (bat(returnStatus: true, script: deployCmd) != 0)
                error "Deployment failed to ${alias}"

            echo "✔ Deployment to ${alias} succeeded."
            deploySucceeded = true
        }
    }

    // ---------------- FINAL MESSAGE ----------------
    if (deploySucceeded) {
        if (branch == "release") {
            echo "✔ Deployment completed to ${ORG1_USERNAME}"
        } else if (branch == "main") {
            echo "✔ Deployment completed to ${ORG2_USERNAME}"
        }
    }

    // ---------------- CLEANUP ----------------
    stage("Cleanup") {
        bat(returnStatus: true, script: """
powershell -NoProfile -Command "Remove-Item -Path '${TMP}' -Recurse -Force -ErrorAction SilentlyContinue"
""")
        echo "Workspace cleaned."
    }
}
