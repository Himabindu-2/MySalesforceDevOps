#!groovy
import groovy.json.JsonSlurperClassic

node {
    def BUILD_NUMBER = env.BUILD_NUMBER
    def SERVER_KEY_CREDENTALS_ID = env.SERVER_KEY_CRED_ID  // Set your credential ID for the server key
    def SF_INSTANCE_URL = env.SFDC_HOST_DH   // Salesforce instance URL (like https://login.salesforce.com)
    def SF_CONSUMER_KEY = env.CONNECTED_APP_CONSUMER_KEY_DH   // Salesforce Connected App Consumer Key
    def SF_USERNAME = env.HUB_ORG_DH  // Salesforce Username for the Hub Org
    def toolbelt = tool 'toolbelt'  // Toolbelt for Salesforce CLI

    stage('Checkout Source') {
        checkout scm // Checks out the code from the main branch
    }

    withEnv(["HOME=${env.WORKSPACE}"]) {
        withCredentials([file(credentialsId: SERVER_KEY_CREDENTALS_ID, variable: 'server_key_file')]) {
            
            // Authorize the Dev Hub org with JWT key and give it an alias.
            stage('Authorize DevHub') {
                def rc = bat returnStatus: true, script: """
                    "${toolbelt}" sf org login jwt --instance-url "${SF_INSTANCE_URL}" --client-id "${SF_CONSUMER_KEY}" --username "${SF_USERNAME}" --jwt-key-file "${server_key_file}" --set-default-dev-hub --alias HubOrg
                """
                if (rc != 0) {
                    error 'Salesforce dev hub org authorization failed.'
                } else {
                    echo 'Salesforce Dev Hub org authorized successfully.'
                }
            }

            // Add other stages if necessary, e.g., deploy code, run tests, etc.
            stage('Deploy Code') {
                def deployMessage = bat returnStdout: true, script: """
                    "${toolbelt}" force:source:deploy -x manifest/package.xml -u "${SF_USERNAME}"
                """
                echo deployMessage
            }
        }
    }
}
