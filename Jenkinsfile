pipeline {
    agent any

    environment {
        ARM_CLIENT_ID = credentials('azure-client-id-credentials-id')
        ARM_CLIENT_SECRET = credentials('azure-client-secret-credentials-id')
        ARM_TENANT_ID = credentials('azure-tenant-id-credentials-id')
        ARM_SUBSCRIPTION_ID = credentials('azure-subscription-id-credentials-id')
    }

    stages {
        stage('Checkout code') {
            steps {
                git 'https://github.com/Mone19/Hello-World-Jenkins.git'
            }
        }

        stage('Terraform Init and Apply') {
            steps {
                script {
                    sh '''
                    terraform init
                    terraform apply -auto-approve
                    '''
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
