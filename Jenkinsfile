pipeline {
    agent any

    environment {
        ARM_CLIENT_ID = credentials('AZURE_CLIENT_ID')
        ARM_TENANT_ID = credentials('AZURE_TENANT_ID')
        ARM_SUBSCRIPTION_ID = credentials('AZURE_SUBSCRIPTION_ID')
        ARM_CLIENT_SECRET = credentials('AZURE_CLIENT_SECRET')
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
    
    post {
        always {
            cleanWs() 
        }
    }
}
