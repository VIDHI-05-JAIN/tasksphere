pipeline {
    agent any

    environment {
        DOCKER_IMAGE = 'vidhijain15/tasksphere'
        KUBECONFIG = '/var/lib/jenkins/.kube/config'
    }

    stages {
        stage('Checkout') {
            steps {
                checkout scm
            }
        }

        stage('Install & Test') {
            steps {
                sh '''
                    python3 -m venv .venv
                    .venv/bin/pip install --upgrade pip
                    .venv/bin/pip install -r requirements.txt
                    .venv/bin/pytest test_app.py -v
                '''
            }
        }

        stage('Build Image') {
            steps {
                sh '''
                    docker build \
                      -t ${DOCKER_IMAGE}:${BUILD_NUMBER} \
                      -t ${DOCKER_IMAGE}:latest .
                '''
            }
        }

        stage('Push Image') {
            steps {
                withCredentials([usernamePassword(
                    credentialsId: 'dockerhub-creds',
                    usernameVariable: 'DOCKERHUB_USER',
                    passwordVariable: 'DOCKERHUB_TOKEN'
                )]) {
                    sh '''
                        set +x
                        trap 'docker logout >/dev/null 2>&1 || true' EXIT
                        echo "$DOCKERHUB_TOKEN" | docker login \
                          -u "$DOCKERHUB_USER" --password-stdin
                        docker push ${DOCKER_IMAGE}:${BUILD_NUMBER}
                        docker push ${DOCKER_IMAGE}:latest
                    '''
                }
            }
        }

        stage('Deploy') {
            steps {
                sh '''
                    kubectl apply -f k8s/namespace.yaml
                    kubectl apply -f k8s/pvc.yaml
                    kubectl apply -f k8s/deployment.yaml
                    kubectl apply -f k8s/service.yaml
                    kubectl apply -f k8s/ingress.yaml

                    kubectl set image deployment/tasksphere \
                      tasksphere=${DOCKER_IMAGE}:${BUILD_NUMBER} \
                      -n tasksphere

                    kubectl rollout status deployment/tasksphere \
                      -n tasksphere --timeout=180s
                '''
            }
        }

        stage('Verify') {
            steps {
                sh '''
                    echo "=== APPLICATION PODS ==="
                    kubectl get pods -n tasksphere -o wide

                    echo "=== SERVICES AND INGRESS ==="
                    kubectl get svc,ingress,pvc -n tasksphere

                    echo "=== APPLICATION HEALTH ==="
                    curl --retry 10 --retry-delay 5 --retry-connrefused \
                      -fsS -H "Host: tasksphere.43.204.2.109.nip.io" http://localhost/health
                '''
            }
        }
    }
}
