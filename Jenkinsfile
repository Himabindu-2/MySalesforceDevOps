#!groovy
node {
    def BUILD_NUMBER = env.BUILD_NUMBER
    def JWT_KEY_CRED_ID = env.JWT_CRED_ID_DH
    def HUB_ORG = env.HUB_ORG_DH
    def SFDC_HOST = env.SFDC_HOST_DH
    def CONNECTED_APP_CONSUMER_KEY = env.CONNECTED_APP_CONSUMER_KEY_DH
    def toolbelt = tool 'toolbelt'

    stage('Checkout Source') {
        checkout scm // Checks out the code from the main branch
    }

    withCredentials([file(credentialsId: JWT_KEY_CRED_ID, variable: 'jwt_key_file')]) {
        stage('Authorize Org') {
            // Print the JWT key file path for debugging purposes (without exposing sensitive data)
            echo "JWT Key file path: ${jwt_key_file}"

            // Using Salesforce CLI (sf) command to authenticate using JWT
            def rc = bat returnStatus: true, script: """
                ${toolbelt} auth:jwt:grant --clientid ${CONNECTED_APP_CONSUMER_KEY} --username ${HUB_ORG} --jwtkeyfile "${jwt_key_file}" --setdefaultdevhubusername --instanceurl ${SFDC_HOST}
            """
            
            // Check for successful authorization
            if (rc != 0) {
                error 'Hub org authorization failed'
            } else {
                echo 'Org authorized successfully'
            }
        }

        stage('Deploy Code') {
            def deployMessage = bat returnStdout: true, script: """
                ${toolbelt} force:source:deploy -x manifest/package.xml -u ${HUB_ORG}
            """
            echo deployMessage
        }
    }
}
