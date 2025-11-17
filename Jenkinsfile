node {
    // Prevent concurrent deploys for this job
    properties([disableConcurrentBuilds()])

    // ----- CONFIG - update names if your Jenkins uses different ones -----
    def TOOLBELT = tool 'toolbelt'                     // Jenkins global tool name for sf
    def JWT_KEY_CRED_ID = env.JWT_CRED_ID_DH           // credential id for server.key
    def ORG1_USERNAME = env.HUB_ORG_DH1                // UAT username
    def ORG1_CLIENT_ID = env.CONNECTED_APP_CONSUMER_KEY_DH1
    def ORG2_USERNAME = env.HUB_ORG_DH                 // PROD username
    def ORG2_CLIENT_ID = env.CONNECTED_APP_CONSUMER_KEY_DH
    def SFDC_HOST = env.SFDC_HOST_DH ?: "https://login.salesforce.com"

    // detect branch
    def branchRaw = env.BRANCH_NAME ?: ''
    def branch = branchRaw.toLowerCase()
    echo "Branch: ${branchRaw}"

    if (!(branch == 'main' || branch == 'release' || branch.startsWith('release/'))) {
        echo "Only 'main' and 'release/*' pipelines run. Skipping."
        currentBuild.result = 'SUCCESS'
        return
    }

    stage('Checkout') {
        checkout scm

        // try to ensure history exists, but don't fail build if unshallow is unnecessary
        def rcFetchAll = bat(returnStatus: true, script: 'git fetch --all --prune')
        echo "git fetch --all --prune rc=${rcFetchAll}"

        // check if repository is shallow; if so, unshallow (safe)
        def isShallow = bat(returnStdout: true, script: 'git rev-parse --is-shallow-repository 2>nul || echo false').trim()
        echo "is shallow: ${isShallow}"
        if (isShallow == 'true') {
            echo "Repository is shallow -> attempting git fetch --unshallow"
            def rc = bat(returnStatus: true, script: 'git fetch --unshallow')
            echo "git fetch --unshallow rc=${rc}"
        } else {
            echo "Repository not shallow - skipping unshallow"
        }
    }

    // Identify changes since last_deployed tag (branch-specific), fallback to commit diff
    stage('Identify Changes') {
        // fetch tags so tag is visible (non-fatal)
        def rcFetchTags = bat(returnStatus: true, script: 'git fetch --tags')
        echo "git fetch --tags rc=${rcFetchTags}"

        def tagName = branch.startsWith('release/') ? 'last_deployed_release' : (branch == 'main' ? 'last_deployed_main' : 'last_deployed')
        echo "Using tag: ${tagName}"

        // check if tag exists safely (non-fatal)
        def rcTagCheck = bat(returnStatus: true, script: "git rev-parse --verify refs/tags/${tagName} >nul 2>nul")
        def tagExists = (rcTagCheck == 0)
        echo "tagExists: ${tagExists} (rc=${rcTagCheck})"

        def raw = ''
        if (tagExists) {
            raw = bat(returnStdout: true, script: "git diff --name-only refs/tags/${tagName}..HEAD || echo ").trim()
            echo "Changed files since tag ${tagName}:\n${raw}"
        } else {
            echo "Tag ${tagName} not found - falling back to commit-level diff."
        }

        if (!raw?.trim()) {
            echo "Falling back to commit-level diff (diff-tree)"
            // show commit info for debugging
            def commitInfo = bat(returnStdout: true, script: 'git show --name-only --pretty=format:"%H %an %ad %s" HEAD').trim()
            echo "Commit info & files:\n${commitInfo}"

            // use diff-tree to reliably list files in this commit (works for merges)
            raw = bat(returnStdout: true, script: 'git diff-tree -r --no-commit-id --name-only HEAD || git log -1 --name-only --pretty=format:""').trim()
            echo "Raw changed files (commit):\n${raw}"
        }

        def changed = []
        if (raw) {
            changed = raw.readLines().findAll { it?.trim() && it.startsWith('force-app/') }
        }

        if (!changed || changed.size() == 0) {
            echo "No force-app changes detected. Nothing to deploy."
            currentBuild.result = 'SUCCESS'
            return
        }

        echo "Files to deploy (${changed.size()}):\n${changed.join('\n')}"
        env.CHANGED_FILES = changed.join(';')
    }

    // Prepare package and convert
    def TMP = "ci_tmp_${env.BUILD_NUMBER ?: '0'}"
    stage('Prepare Package') {
        def rcRm = bat(returnStatus: true, script: "rmdir /s /q ${TMP} || echo no-temp")
        echo "rmdir rc=${rcRm}"

        def rcMk = bat(returnStatus: true, script: "mkdir ${TMP} || echo mkdir-ok")
        echo "mkdir rc=${rcMk}"

        def ps = '''
param([string]$filesString, [string]$tmp)
$files = $filesString -split ';' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' }
foreach ($f in $files) {
  if (!(Test-Path $f)) { Write-Host "WARNING: file not found: $f"; continue }
  $dest = Join-Path $tmp $f
  $destDir = Split-Path $dest -Parent
  if (!(Test-Path $destDir)) { New-Item -ItemType Directory -Path $destDir -Force | Out-Null }
  Copy-Item -Path $f -Destination $dest -Force
}
'''
        writeFile file: "${TMP}\\copy_files.ps1", text: ps

        def pwdEsc = pwd().toString().replaceAll('\\\\','\\\\\\\\')
        def psCmd = "powershell -ExecutionPolicy Bypass -NoProfile -Command \"& { & '${pwdEsc}\\\\${TMP}\\\\copy_files.ps1' -filesString '${env.CHANGED_FILES}' -tmp '${pwdEsc}\\\\${TMP}'; }\""
        def rcPs = bat(returnStatus: true, script: psCmd)
        echo "copy_files.ps1 rc=${rcPs}"

        def rcListAfterCopy = bat(returnStatus: true, script: "dir /s ${TMP} || echo no-dir")
        echo "dir after copy rc=${rcListAfterCopy}"

        // convert using sf CLI (latest)
        def convertCmd = """pushd ${TMP} & IF EXIST mdapi_output rmdir /s /q mdapi_output || echo none & ${TOOLBELT} sf project convert source --root-dir . --output-dir mdapi_output & popd"""
        def rcConvert = bat(returnStatus: true, script: convertCmd)
        echo "source:convert rc=${rcConvert}"

        def rcListMdapi = bat(returnStatus: true, script: "dir /s ${TMP}\\\\mdapi_output || echo no-mdapi")
        echo "mdapi_output listing rc=${rcListMdapi}"

        if (rcConvert != 0) {
            error "Source conversion failed (rc=${rcConvert}) - stopping build"
        }
    }

    stage('Save package as artifact') {
        // create a zip of mdapi_output
        def zipName = "mdapi_output_${env.BUILD_NUMBER}.zip"
        def pwdEsc2 = pwd().toString().replaceAll('\\\\','\\\\\\\\')
        def zipCmd = "powershell -NoProfile -Command \"If (Test-Path '${pwdEsc2}\\\\${TMP}\\\\mdapi_output') { Compress-Archive -Path '${pwdEsc2}\\\\${TMP}\\\\mdapi_output\\\\*' -DestinationPath '${pwdEsc2}\\\\${zipName}' -Force } else { Write-Error 'mdapi_output not found' }\""
        def rcZip = bat(returnStatus: true, script: zipCmd)
        echo "zip rc=${rcZip}"
        if (rcZip != 0) { error "Failed to create zip (rc=${rcZip})" }

        // Archive artifact so it's downloadable from Jenkins build page
        archiveArtifacts artifacts: "${zipName}", fingerprint: true
        echo "Archived artifact: ${zipName}"
    }

    // Authenticate and deploy
    def deploySucceeded = false
    withCredentials([file(credentialsId: JWT_KEY_CRED_ID, variable: 'JWT_KEY_FILE')]) {
        if (branch.startsWith('release/')) {
            stage('Deploy to ORG1 (UAT)') {
                echo "Authenticating to ORG1 (UAT): ${ORG1_USERNAME}"
                def authCmd = "${TOOLBELT} sf org login jwt --instance-url ${SFDC_HOST} --client-id ${ORG1_CLIENT_ID} --username ${ORG1_USERNAME} --jwt-key-file %JWT_KEY_FILE% --setalias ORG1"
                if (bat(returnStatus: true, script: authCmd) != 0) { error "JWT auth to ORG1 failed" }
                def mdapiPath = "${TMP}\\\\mdapi_output"
                def deployCmd = "${TOOLBELT} sf project deploy start --metadata-dir ${mdapiPath} --target-org ORG1 --wait -1"
                echo "Deploy command: ${deployCmd}"
                if (bat(returnStatus: true, script: deployCmd) != 0) { error "Deploy to ORG1 failed" } else { echo "Deploy to ORG1 succeeded."; deploySucceeded = true }
            }
        } else if (branch == 'main') {
            stage('Deploy to ORG2 (PROD)') {
                echo "Authenticating to ORG2 (PROD): ${ORG2_USERNAME}"
                def authCmd = "${TOOLBELT} sf org login jwt --instance-url ${SFDC_HOST} --client-id ${ORG2_CLIENT_ID} --username ${ORG2_USERNAME} --jwt-key-file %JWT_KEY_FILE% --setalias ORG2"
                if (bat(returnStatus: true, script: authCmd) != 0) { error "JWT auth to ORG2 failed" }
                def mdapiPath = "${TMP}\\\\mdapi_output"
                def deployCmd = "${TOOLBELT} sf project deploy start --metadata-dir ${mdapiPath} --target-org ORG2 --wait -1"
                echo "Deploy command: ${deployCmd}"
                if (bat(returnStatus: true, script: deployCmd) != 0) { error "Deploy to ORG2 failed" } else { echo "Deploy to ORG2 succeeded."; deploySucceeded = true }
            }
        }
    }

    // Mark deployed only on success
    if (deploySucceeded) {
        stage('Mark deployed') {
            def tagName = branch.startsWith('release/') ? 'last_deployed_release' : (branch == 'main' ? 'last_deployed_main' : 'last_deployed')
            def sha = bat(returnStdout: true, script: 'git rev-parse --verify HEAD').trim()

            def rcTag = bat(returnStatus: true, script: "git tag -f ${tagName} ${sha} || echo tag-failed")
            echo "tag create rc=${rcTag}"

            def rcPush = bat(returnStatus: true, script: "git push origin refs/tags/${tagName} --force || echo push-tag-failed")
            echo "tag push rc=${rcPush}"

            if (rcPush != 0) {
                echo "WARNING: tag push failed (rc=${rcPush}). Check CI user permissions for pushing tags."
            } else {
                echo "Tag ${tagName} updated to ${sha}"
            }
        }
    } else {
        echo "Deploy did not succeed; not updating last_deployed tag."
    }

    // cleanup
    stage('Cleanup') {
        def rc = bat(returnStatus: true, script: "rmdir /s /q ${TMP} || echo cleanup done")
        echo "cleanup rc=${rc}"
    }

    echo "Done for branch ${branchRaw}"
}
