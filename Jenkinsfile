#!groovy
node {
    properties([disableConcurrentBuilds()])

    def TOOLBELT         = tool 'toolbelt'
    def JWT_KEY_CRED_ID  = env.JWT_CRED_ID_DH
    def ORG1_USERNAME    = env.HUB_ORG_DH1
    def ORG1_CLIENT_ID   = env.CONNECTED_APP_CONSUMER_KEY_DH1
    def ORG2_USERNAME    = env.HUB_ORG_DH
    def ORG2_CLIENT_ID   = env.CONNECTED_APP_CONSUMER_KEY_DH
    def SFDC_HOST        = env.SFDC_HOST_DH ?: "https://login.salesforce.com"

    stage('Update Salesforce CLI') {
        bat "sf update"
    }

    def branchRaw = env.BRANCH_NAME ?: ""
    def branch = branchRaw.toLowerCase()
    echo "Branch: ${branchRaw}"

    if (!(branch == "main" || branch == "release")) {
        echo "No deployment for this branch."
        currentBuild.result = "SUCCESS"
        return
    }

    stage("Checkout") {
        checkout scm
        bat(returnStatus: true, script: "git fetch --all --prune")

        def isShallow = bat(returnStdout: true,
            script: "git rev-parse --is-shallow-repository 2>nul || echo false").trim()

        if (isShallow == "true") {
            bat(returnStatus: true, script: "git fetch --unshallow || echo 'unshallow failed'")
        }
    }

    stage("Find changed files") {
        def raw = bat(returnStdout: true,
            script: "git diff-tree -r --no-commit-id --name-only HEAD || echo").trim()

        echo "Raw changed files:\n${raw}"

        def changed = []
        if (raw) changed = raw.readLines().findAll { it.startsWith("force-app/") }

        if (changed.isEmpty()) {
            echo "✔ No force-app changes detected."
            currentBuild.result = "SUCCESS"
            return
        }

        echo "Files to deploy:\n${changed.join('\n')}"
        env.CHANGED_FILES = changed.join(";")
    }

    def TMP = "ci_tmp_${env.BUILD_NUMBER ?: '0'}"

    stage("Prepare Package") {

        bat(returnStatus: true, script: """
powershell -NoProfile -Command "Remove-Item -Path '${TMP}' -Recurse -Force -ErrorAction SilentlyContinue"
""")

        bat "mkdir ${TMP}"

        // IMPORTANT FIX — this block MUST stay EXACT
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

        def rcConvert = bat(returnStatus: true,
            script: "sf project convert source --root-dir ${TMP} --output-dir ${TMP}\\\\mdapi_output")

        if (rcConvert != 0) error "MDAPI conversion failed"
    }

    def deploySucceeded = false

    withCredentials([file(credentialsId: JWT_KEY_CRED_ID, variable: "J_]()
