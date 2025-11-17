#!groovy
node {
    // Configuration (adapt tool/credential names in Jenkins if different)
    def TOOLBELT = tool 'toolbelt'                     // path to sf/sfdx
    def JWT_KEY_CRED_ID = env.JWT_CRED_ID_DH
    def ORG1_USERNAME = env.HUB_ORG_DH1
    def ORG1_CLIENT_ID = env.CONNECTED_APP_CONSUMER_KEY_DH1
    def ORG2_USERNAME = env.HUB_ORG_DH
    def ORG2_CLIENT_ID = env.CONNECTED_APP_CONSUMER_KEY_DH
    def SFDC_HOST = env.SFDC_HOST_DH ?: "https://login.salesforce.com"

    def branch = (env.BRANCH_NAME ?: '').toLowerCase()
    echo "Branch: ${branch}"

    if (!(branch == 'main' || branch == 'release' || branch.startsWith('release/'))) {
        echo "Only 'main' and 'release/*' run. Skipping."
        currentBuild.result = 'SUCCESS'
        return
    }

    stage('Checkout') {
        checkout scm
        // ensure full history so HEAD~1 exists
        bat 'git fetch --all --prune || echo "fetch failed"'
        bat 'git fetch --unshallow || echo "not shallow or unshallow failed"'
    }

    stage('Find changed files') {
        // try diff against previous commit, otherwise list last commit
        def rawChanged = bat(returnStdout: true, script: 'git diff --name-only HEAD~1 HEAD || git log -1 --name-only --pretty=format:""').trim()
        echo "Raw changes:\n${rawChanged}"
        def changed = []
        if (rawChanged) {
            changed = rawChanged.readLines().findAll { it?.trim() && it.startsWith('force-app/') }
        }
        if (!changed) {
            echo "No force-app changes in latest commit. Nothing to deploy."
            currentBuild.result = 'SUCCESS'
            return
        }
        echo "Will deploy ${changed.size()} changed files."
        env.CHANGED_FILES = changed.join(';')
    }

    // create a minimal package with only changed files
    def TMP = "ci_tmp_${env.BUILD_NUMBER ?: '0'}"
    stage('Create package (changed files only)') {
        bat "rmdir /s /q ${TMP} || echo no-temp"
        bat "mkdir ${TMP} || echo mkdir-ok"
        // small PowerShell to copy changed files preserving dirs
        def ps = '''
param([string]$filesString, [string]$tmp)
$files = $filesString -split ';' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' }
foreach ($f in $files) {
  $dest = Join-Path $tmp $f
  $destDir = Split-Path $dest -Parent
  if (!(Test-Path $destDir)) { New-Item -ItemType Directory -Path $destDir -Force | Out-Null }
  Copy-Item -Path $f -Destination $dest -Force
}
'''
        writeFile file: "${TMP}\\copy_files.ps1", text: ps
        bat """
powershell -ExecutionPolicy Bypass -NoProfile -Command ^
 "& { & '${pwd().toString().replaceAll('\\\\','\\\\\\\\')}\\\\${TMP}\\\\copy_files.ps1' -filesString '${env.CHANGED_FILES}' -tmp '${pwd().toString().replaceAll('\\\\','\\\\\\\\')}\\\\${TMP}'; }"
"""
        // convert source to MDAPI (keeps this simple and compatible)
        bat """
pushd ${TMP}
IF EXIST mdapi_output rmdir /s /q mdapi_output || echo none
${TOOLBELT} sfdx force:source:convert -r . -d mdapi_output
popd
"""
    }

    // Authenticate and deploy
    withCredentials([file(credentialsId: JWT_KEY_CRED_ID, variable: 'JWT_KEY_FILE')]) {
        if (branch.startsWith('release/')) {
            stage('Deploy to ORG1 (UAT)') {
                echo "Auth ORG1: ${ORG1_USERNAME}"
                def authCmd = "${TOOLBELT} sf org login jwt --instance-url ${SFDC_HOST} --client-id ${ORG1_CLIENT_ID} --username ${ORG1_USERNAME} --jwt-key-file %JWT_KEY_FILE% --setalias ORG1 || ${TOOLBELT} sfdx auth:jwt:grant --clientid ${ORG1_CLIENT_ID} --jwtkeyfile %JWT_KEY_FILE% --username ${ORG1_USERNAME} --instanceurl ${SFDC_HOST}"
                if (bat(returnStatus: true, script: authCmd) != 0) { error "Auth to ORG1 failed" }
                def mdapiPath = "${TMP}\\\\mdapi_output"
                def deployCmd = "${TOOLBELT} sfdx force:mdapi:deploy -d ${mdapiPath} -u ORG1 -w -1"
                echo "Deploying changed files to ORG1..."
                if (bat(returnStatus: true, script: deployCmd) != 0) { error "Deploy to ORG1 failed" }
                echo "Deploy to ORG1 succeeded."
            }
        } else if (branch == 'main') {
            stage('Deploy to ORG2 (PROD)') {
                echo "Auth ORG2: ${ORG2_USERNAME}"
                def authCmd = "${TOOLBELT} sf org login jwt --instance-url ${SFDC_HOST} --client-id ${ORG2_CLIENT_ID} --username ${ORG2_USERNAME} --jwt-key-file %JWT_KEY_FILE% --setalias ORG2 || ${TOOLBELT} sfdx auth:jwt:grant --clientid ${ORG2_CLIENT_ID} --jwtkeyfile %JWT_KEY_FILE% --username ${ORG2_USERNAME} --instanceurl ${SFDC_HOST}"
                if (bat(returnStatus: true, script: authCmd) != 0) { error "Auth to ORG2 failed" }
                def mdapiPath = "${TMP}\\\\mdapi_output"
                def deployCmd = "${TOOLBELT} sfdx force:mdapi:deploy -d ${mdapiPath} -u ORG2 -w -1"
                echo "Deploying changed files to ORG2..."
                if (bat(returnStatus: true, script: deployCmd) != 0) { error "Deploy to ORG2 failed" }
                echo "Deploy to ORG2 succeeded."
            }
        }
    }

    stage('Cleanup') {
        bat "rmdir /s /q ${TMP} || echo cleanup done"
    }

    echo "Done for branch ${branch}"
}
