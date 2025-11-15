#!groovy
node {
    // --- Configuration: adapt these if your Jenkins env uses different names ---
    def TOOLBELT = tool 'toolbelt'                     // Jenkins Global Tool (path to sf/sfdx)
    def JWT_KEY_CRED_ID = env.JWT_CRED_ID_DH           // Secret file credential id (server.key)
    def ORG1_USERNAME = env.HUB_ORG_DH1                // UAT username (ORG1)
    def ORG1_CLIENT_ID = env.CONNECTED_APP_CONSUMER_KEY_DH1
    def ORG2_USERNAME = env.HUB_ORG_DH                 // PROD username (ORG2)
    def ORG2_CLIENT_ID = env.CONNECTED_APP_CONSUMER_KEY_DH
    def SFDC_HOST = env.SFDC_HOST_DH ?: "https://login.salesforce.com"

    // show branch
    def branch = env.BRANCH_NAME ?: ""
    echo "Detected branch: ${branch}"

    // Only allow release/* and main. Skip otherwise.
    if (!(branch == 'main' || branch.startsWith('release/'))) {
        echo "Branch '${branch}' is excluded from this pipeline (only 'release/*' and 'main' run). Exiting."
        currentBuild.result = 'SUCCESS'
        return
    }

    // Ensure we have commit history for diff
    stage('Checkout') {
        checkout scm
        bat '''
            git fetch --all --prune || echo "fetch failed or already full"
            git fetch --unshallow || echo "not shallow or unshallow failed"
        '''
    }

    // Identify changed files from latest commit (fallback to last commit if HEAD~1 not available)
    stage('Identify Latest Commit Changes') {
        def raw = bat(returnStdout: true, script: 'git diff --name-only HEAD~1 HEAD || git log -1 --name-only --pretty=format:""').trim()
        echo "Raw changed files:\n${raw}"
        // Filter only source-format Salesforce files under force-app/
        def changed = []
        if (raw) {
            changed = raw.readLines().findAll { it?.trim() && it.startsWith('force-app/') }
        }
        if (!changed || changed.size() == 0) {
            echo "No Salesforce source changes found in latest commit (under force-app/). Nothing to deploy."
            currentBuild.result = 'SUCCESS'
            return
        }
        echo "Files to deploy:\n${changed.join('\n')}"
        // store for later stages
        env.CHANGED_FILES = changed.join(';')   // semicolon-separated for passing into bat/PS
    }

    // Prepare temp package containing only changed files (preserve directory structure)
    def TMP = "ci_tmp_${env.BUILD_NUMBER ?: '0'}"
    stage('Prepare Temp Package') {
        bat "rmdir /s /q ${TMP} || echo no-temp"
        bat "mkdir ${TMP} || echo mkdir-ok"
        // write PowerShell script to copy files preserving paths
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
        // execute PowerShell passing CHANGED_FILES
        bat """
powershell -ExecutionPolicy Bypass -NoProfile -Command ^
  "& { & '${pwd().toString().replaceAll('\\\\','\\\\\\\\')}\\\\${TMP}\\\\copy_files.ps1' -filesString '${env.CHANGED_FILES}' -tmp '${pwd().toString().replaceAll('\\\\','\\\\\\\\')}\\\\${TMP}'; }"
"""
        // convert to mdapi
        bat """
pushd ${TMP}
IF EXIST mdapi_output rmdir /s /q mdapi_output || echo none
${TOOLBELT} sfdx force:source:convert -r . -d mdapi_output
popd
"""
    }

    // Authenticate and deploy based on branch
    withCredentials([file(credentialsId: JWT_KEY_CRED_ID, variable: 'JWT_KEY_FILE')]) {
        if (branch.startsWith('release/')) {
            // Deploy to ORG1 (UAT)
            stage('Push To ORG1') {
                echo "Authenticating to ORG1 (UAT): ${ORG1_USERNAME}"
                def authCmd = "${TOOLBELT} sf org login jwt --instance-url ${SFDC_HOST} --client-id ${ORG1_CLIENT_ID} --username ${ORG1_USERNAME} --jwt-key-file %JWT_KEY_FILE% --setalias ORG1 || ${TOOLBELT} sfdx auth:jwt:grant --clientid ${ORG1_CLIENT_ID} --jwtkeyfile %JWT_KEY_FILE% --username ${ORG1_USERNAME} --instanceurl ${SFDC_HOST}"
                def rcAuth = bat(returnStatus: true, script: authCmd)
                if (rcAuth != 0) { error "JWT auth to ORG1 failed (rc=${rcAuth})" }
                echo "Authenticated to ORG1"

                stage('Deploy changed to ORG1') {
                    def mdapiPath = "${TMP}\\\\mdapi_output"
                    def deployCmd = "${TOOLBELT} sfdx force:mdapi:deploy -d ${mdapiPath} -u ORG1 -w -1"
                    echo "Deploy command: ${deployCmd}"
                    def rc = bat(returnStatus: true, script: deployCmd)
                    if (rc != 0) { error "Deploy to ORG1 failed (rc=${rc})" } else { echo "Deploy to ORG1 succeeded." }
                }
            }
        }
        else if (branch == 'main') {
            // Deploy to ORG2 (PROD)
            stage('Push To ORG2 (PROD)') {
                echo "Authenticating to ORG2 (PROD): ${ORG2_USERNAME}"
                def authCmd = "${TOOLBELT} sf org login jwt --instance-url ${SFDC_HOST} --client-id ${ORG2_CLIENT_ID} --username ${ORG2_USERNAME} --jwt-key-file %JWT_KEY_FILE% --setalias ORG2 || ${TOOLBELT} sfdx auth:jwt:grant --clientid ${ORG2_CLIENT_ID} --jwtkeyfile %JWT_KEY_FILE% --username ${ORG2_USERNAME} --instanceurl ${SFDC_HOST}"
                def rcAuth = bat(returnStatus: true, script: authCmd)
                if (rcAuth != 0) { error "JWT auth to ORG2 failed (rc=${rcAuth})" }
                echo "Authenticated to ORG2"

                // OPTIONAL: require manual approval for prod - uncomment if needed
                // timeout(time:2, unit:'HOURS') {
                //     input message: "Approve PROD deployment?", submitter: "release-manager,admin"
                // }

                stage('Deploy changed to ORG2') {
                    def mdapiPath = "${TMP}\\\\mdapi_output"
                    // If Apex changes exist in package, you must run tests (-l RunLocalTests). Adjust if needed.
                    def deployCmd = "${TOOLBELT} sfdx force:mdapi:deploy -d ${mdapiPath} -u ORG2 -w -1"
                    echo "Deploy command: ${deployCmd}"
                    def rc = bat(returnStatus: true, script: deployCmd)
                    if (rc != 0) { error "Deploy to ORG2 failed (rc=${rc})" } else { echo "Deploy to ORG2 succeeded." }
                }
            }
        }
    } // withCredentials

    // cleanup
    stage('Cleanup') {
        bat "rmdir /s /q ${TMP} || echo cleanup done"
    }

    echo "Done for branch ${branch}"
}
