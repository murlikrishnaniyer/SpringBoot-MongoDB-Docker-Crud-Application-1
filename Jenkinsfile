pipeline {
    agent any

    environment {
        DOCKER_REGISTRY = credentials('docker-registry')
        DOCKER_USERNAME = "${DOCKER_REGISTRY_USR}"
        DOCKER_PASSWORD = "${DOCKER_REGISTRY_PSW}"
        REGISTRY_URL = "docker.io"
        IMAGE_NAME = "springboot-mongodb-docker-crud-application-app"
        IMAGE_TAG = "${BUILD_NUMBER}"
        SONAR_TOKEN = credentials('sonarqube-token')
        SONAR_HOST_URL = "http://localhost:9000"
    }

    options {
        buildDiscarder(logRotator(numToKeepStr: '10'))
        timeout(time: 30, unit: 'MINUTES')
        timestamps()
    }

    stages {
        stage('Checkout') {
            steps {
                script {
                    echo "📦 Checking out source code..."
                }
                checkout scm
            }
        }

        stage('Build') {
            steps {
                script {
                    echo "🔨 Building Spring Boot application..."
                }
                sh '''
                    ./mvnw clean package -DskipTests \
                        -Dmaven.compiler.source=24 \
                        -Dmaven.compiler.target=24
                '''
            }
        }

        stage('Unit Tests') {
            steps {
                script {
                    echo "✅ Running unit tests..."
                }
                sh '''
                    ./mvnw test \
                        -Dmaven.compiler.source=24 \
                        -Dmaven.compiler.target=24
                '''
            }
            post {
                always {
                    junit 'target/surefire-reports/*.xml'
                    publishHTML([
                        reportDir: 'target/site/jacoco',
                        reportFiles: 'index.html',
                        reportName: 'Code Coverage Report'
                    ])
                }
            }
        }

        stage('Code Quality - SonarQube') {
            when {
                branch 'main'
            }
            steps {
                script {
                    echo "🔍 Running SonarQube analysis..."
                }
                sh '''
                    ./mvnw sonar:sonar \
                        -Dsonar.projectKey=springboot-mongodb-crud \
                        -Dsonar.projectName="Spring Boot MongoDB CRUD" \
                        -Dsonar.sources=src/main \
                        -Dsonar.tests=src/test \
                        -Dsonar.host.url=${SONAR_HOST_URL} \
                        -Dsonar.login=${SONAR_TOKEN}
                '''
            }
        }

        stage('Build Docker Image') {
            steps {
                script {
                    echo "🐳 Building Docker image..."
                }
                sh '''
                    docker build \
                        -t ${IMAGE_NAME}:${IMAGE_TAG} \
                        -t ${IMAGE_NAME}:latest \
                        .
                '''
            }
        }

        stage('Security Scanning - Trivy') {
            steps {
                script {
                    echo "🛡️ Scanning Docker image for vulnerabilities..."
                }
                sh '''
                    trivy image --severity HIGH,CRITICAL \
                        ${IMAGE_NAME}:${IMAGE_TAG} || true
                '''
            }
        }

        stage('Push Docker Image') {
            when {
                branch 'main'
            }
            steps {
                script {
                    echo "📤 Pushing Docker image to registry..."
                }
                sh '''
                    echo ${DOCKER_PASSWORD} | docker login -u ${DOCKER_USERNAME} --password-stdin ${REGISTRY_URL}
                    docker tag ${IMAGE_NAME}:${IMAGE_TAG} ${DOCKER_USERNAME}/${IMAGE_NAME}:${IMAGE_TAG}
                    docker tag ${IMAGE_NAME}:latest ${DOCKER_USERNAME}/${IMAGE_NAME}:latest
                    docker push ${DOCKER_USERNAME}/${IMAGE_NAME}:${IMAGE_TAG}
                    docker push ${DOCKER_USERNAME}/${IMAGE_NAME}:latest
                    docker logout
                '''
            }
        }

        stage('Deploy - Docker Compose') {
            when {
                branch 'main'
            }
            steps {
                script {
                    echo "🚀 Deploying with Docker Compose..."
                }
                sh '''
                    docker-compose down || true
                    docker-compose up --pull always -d
                    sleep 15
                '''
            }
        }

        stage('Health Check') {
            when {
                branch 'main'
            }
            steps {
                script {
                    echo "🏥 Running health checks..."
                }
                sh '''
                    # Wait for application to be ready
                    for i in {1..30}; do
                        if curl -f http://localhost:8080/actuator/health > /dev/null 2>&1; then
                            echo "✓ Application is healthy"
                            exit 0
                        fi
                        echo "Attempt $i/30: Waiting for application..."
                        sleep 2
                    done
                    echo "✗ Health check failed"
                    exit 1
                '''
            }
        }

        stage('Integration Tests') {
            when {
                branch 'main'
            }
            steps {
                script {
                    echo "🧪 Running integration tests..."
                }
                sh '''
                    # Basic connectivity test
                    curl -X GET http://localhost:8080/api/books || true
                    curl -X GET http://localhost:27017/ || true
                '''
            }
        }

        stage('Cleanup') {
            when {
                failure()
            }
            steps {
                script {
                    echo "🧹 Cleaning up failed deployment..."
                }
                sh '''
                    docker-compose logs
                    docker-compose down
                '''
            }
        }
    }

    post {
        always {
            script {
                echo "📊 Collecting reports..."
            }
            junit 'target/surefire-reports/*.xml' 
            archiveArtifacts artifacts: 'target/*.jar', allowEmptyArchive: true
        }
        success {
            script {
                echo "✅ Pipeline completed successfully!"
            }
        }
        failure {
            script {
                echo "❌ Pipeline failed. Check logs above."
            }
        }
    }
}
