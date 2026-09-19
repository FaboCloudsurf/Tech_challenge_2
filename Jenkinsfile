pipeline {
    agent any

    environment {
        AWS_REGION   = 'us-east-1'
        ACCOUNT_ID   = '730335577638'
        ECR_REPO     = "${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/tech_challenge_2-ecr-app"
        CLUSTER_NAME = 'tech_challenge_2_eks'
        RELEASE_NAME = 'hello'          //helm release name
        IMAGE_TAG    = "${env.BUILD_NUMBER}"
    }

    stages {

        // Pulls down the latest code from whichever branch/repo this pipeline is watching
        stage('Checkout code') {
            steps {
                checkout scm
            }
        }
    // Turn the Dockerfile into an image, tagged with this build's number
    stage('Build Docker image') {
            steps {
                sh 'docker build -t ${ECR_REPO}:${IMAGE_TAG} ./app'
            }
        }
    // ECR is private. Get a temporary token (from the instance role) and log Docker in.
    stage('Authenticate to ECR') {
            steps {
                sh '''
                    aws ecr get-login-password --region $AWS_REGION \
                      | docker login --username AWS --password-stdin $ECR_REPO
                '''
            }
        }
    // Upload the image. Also tag it :latest so the chart's default stays valid.
    stage('Push image to ECR') {
            steps {
                sh '''
                    docker push $ECR_REPO:$IMAGE_TAG
                    docker tag $ECR_REPO:$IMAGE_TAG $ECR_REPO:latest
                    docker push $ECR_REPO:latest
                '''
            }
        }
    // Point kubectl at the cluster, then deploy the chart with this build's image.
    stage('Deploy to EKS with Helm') {
            steps {
                sh '''
                    aws eks update-kubeconfig --region $AWS_REGION --name $CLUSTER_NAME

                    helm upgrade --install $RELEASE_NAME ./helm/hello-world \
                      --set image.repository=$ECR_REPO \
                      --set image.tag=$IMAGE_TAG \
                      --wait --timeout 5m

                    kubectl rollout status deployment/$RELEASE_NAME --timeout=5m
                '''
            }
        }
    }

    post {
        always {
            sh 'docker image prune -f || true'                  // free disk; don't fail on error
            deleteDir()                                         //wipe the cloned repo from the workspace
        }
    }
}