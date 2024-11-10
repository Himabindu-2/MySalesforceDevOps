#!groovy
node {
    def BUILD_NUMBER = env.BUILD_NUMBER
    def RUN_ARTIFACT_DIR="tests/${BUILD_NUMBER}"
    def SFDC
    
    
    def JWT_KEY_CRED_ID = env.JWT_CRED_ID_DH
    def HUB_ORG = env.HUB_ORG_DH
    def SFDC_HOST = env.SFDC_HOST_DH
    def CONNECTED_APP_CONSUMER_KEY = env.CONNECTED_APP_CONSUMER_KEY_DH

    println 'KEY IS' 
    println JWT_KEY_CRED_ID
    println HUB_ORG
    println SFDC_HOST
    println CONNECTED_APP_CONSUMER_KEY

    def toolbelt = tool 'toolbelt'

    stage('Checkout Source') {
        checkout scm // Checks out the code from the main branch
    }

    withCredentials([file(credentialsId: JWT_KEY_CRED_ID, variable: 'jwt_key_file')]) {
        stage('Authorize Org') {
            // Print the JWT key file path for debugging purposes (without exposing sensitive data)
            //echo "JWT Key file path: ${jwt_key_file}"
            // Using Salesforce CLI (sf) command to authenticate using JWT
            echo "SFDC_HOST: ${SFDC_HOST}"

            def rc = bat returnStatus: true, script: "${toolbelt}sf org login jwt --instance-url "${SFDC_HOST}" --client-id "${CONNECTED_APP_CONSUMER_KEY}" --username 'https://login.salesforce.com' --jwt-key-file "${server_key_file}" --setalias 'Devhub'"
                echo "SFDC_HOST: ${SFDC_HOST}"

            // Check for successful authorization
            if (rc != 0) {
                error 'Hub org authorization failed'
            } else {
                echo 'Org authorized successfully'
            }
        }

        stage('Push To DevHub') { 
               rc = bat returnStatus: true, script: "${toolbelt}sf project deploy start --target-org Devhub" 
           if (rc != 0) {
                error 'Salesforce push to DevHub org failed.' 
         }
      }

    }
}
