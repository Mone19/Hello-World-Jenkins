pipeline {
    agent any

    environment {
        AZURE_CREDENTIALS_ID = 'e4a472a1-9fcd-4f52-9c12-01fce460c91a'
    }

    stages {
        stage('Checkout code') {
            steps {
                git 'https://github.com/Mone19/Hello-World-Jenkins.git'
            }
        }

        stage('Terraform Init and Apply') {
            steps {
                withCredentials([[
                    $class: 'AzureServicePrincipal', 
                    credentialsId: "${env.AZURE_CREDENTIALS_ID}", 
                    clientIdVariable: 'ARM_CLIENT_ID', 
                    clientSecretVariable: 'ARM_CLIENT_SECRET', 
                    tenantIdVariable: 'ARM_TENANT_ID', 
                    subscriptionIdVariable: 'ARM_SUBSCRIPTION_ID'
                ]]) {
                    script {
                        sh '''
                        terraform init
                        terraform apply \
                            -var "subscription_id=${ARM_SUBSCRIPTION_ID}" \
                            -var "client_id=${ARM_CLIENT_ID}" \
                            -var "client_secret=${ARM_CLIENT_SECRET}" \
                            -var "tenant_id=${ARM_TENANT_ID}" \
                            -auto-approve
                        '''
                    }
                }
            }
        }

        stage('Deploy to Kubernetes') {
            steps {
                script {
                    sh '''
                    az login --service-principal -u $ARM_CLIENT_ID -p $ARM_CLIENT_SECRET --tenant $ARM_TENANT_ID
                    az aks get-credentials --resource-group rg --name aks

                    kubectl apply -f k8s/deployment.yml
                    kubectl apply -f k8s/service.yml
                    kubectl apply -f k8s/ingress.yml
                    kubectl apply -f k8s/hpa.yml
                    kubectl apply -f k8s/configmap.yml
                    '''
                }
            }
        }
    }
}
