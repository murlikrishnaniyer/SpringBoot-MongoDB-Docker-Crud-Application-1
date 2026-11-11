# SpringBoot-MongoDB-Docker-Crud-Application
A CRUD application using Spring Boot, MongoDB, Docker and Kubernetes

# Requirements
Docker, Minikube and Kubernetes

# Execute the application 
docker login

docker push tekpie/spring-mongodb-crud-application

# Deploy on Kubernetes
minikube start

minikube dashboard

cd K8s/mongodb

kubectl create -f mongo-service.yml

kubectl create -f mongo-controller.yml

cd K8s

kubectl create -f deployment.yml

kubectl create -f service.yml

kubectl describe service spring-mongodb-crud-application
The service is at http://127.0.0.1:50571. Let me test it:

minikube service spring-mongodb-crud-application
minikube kubectl -- port-forward -n default svc/spring-mongodb-crud-application 8080:8080

this will launch the application in your browser

Finally, to stop, use:
minikube stop

************* Steps to run the application in AWS ECS using Terraform *************


docker build -t tekpie/springboot-mongodb-docker-crud-application-app:latest .

# Run the Application
docker run -tty --publish 8080:8080 tekpie/springboot-mongodb-docker-crud-application-app:latest

#Push the Application:
docker push tekpie/springboot-mongodb-docker-crud-application-app:latest


#List Images
docker images

#tag the image with ur docker id
#docker tag mongo:7.0 tekpie/mongo:7.0


aws ecs describe-task-definition \ --springboot-mongodb-docker-crud-application-app

#test if the application is successfully running in Docker:
docker run -p 8080:8080 \  -e SPRING_DATA_MONGODB_HOST=host.docker.internal \  -e SPRING_DATA_MONGODB_PORT=27017 \  -e SPRING_DATA_MONGODB_DATABASE=BookStore \  spring-mongodb-crud-application:0.0.1-SNAPSHOT


*****************Terraform*******************

## Jenkins and GitHub Terraform module

The separate `modules/jenkins-github` module configures a GitHub push webhook,
stores its shared secret as a Jenkins credential, and creates a Jenkins
Pipeline job for this repository's `Jenkinsfile`. The example Terraform root
under `terraform/jenkins-github` can be applied independently of the AWS ECS
infrastructure.

The existing Jenkins server must be publicly reachable over HTTPS and have the
GitHub, Pipeline, Git, and Docker Pipeline plugins installed. The Docker
Pipeline plugin is needed by this repository's `Jenkinsfile`. Set these
environment variables in the same PowerShell session before initializing:

```powershell
$env:GITHUB_TOKEN = "<GitHub token with permission to manage repository webhooks>"
$env:JENKINS_URL = "https://jenkins.example.com"
$env:JENKINS_USERNAME = "<Jenkins username>"
$env:JENKINS_PASSWORD = "<Jenkins API token>"
$env:TF_VAR_jenkins_url = $env:JENKINS_URL
$env:TF_VAR_github_webhook_secret = "<random secret of at least 32 characters>"
```

Then run:

```powershell
terraform -chdir=terraform/jenkins-github init
terraform -chdir=terraform/jenkins-github plan
terraform -chdir=terraform/jenkins-github apply
```

On the Jenkins server, load the `jenkins_github_plugin_casc_fragment` Terraform
output into Jenkins Configuration as Code (JCasC), or configure the GitHub
plugin's hook URL and shared-secret credential in **Manage Jenkins → System**.
The output refers to the Jenkins secret credential created by Terraform.
Use encrypted, access-controlled Terraform state: both GitHub and Jenkins
credential resources contain the webhook secret in state. For a private
repository, create a Jenkins SCM credential and set
`TF_VAR_jenkins_scm_credentials_id` to its ID before applying.

terraform init

terraform plan

# Push environment variable updates to AWS
terraform apply

# Force Fargate to recycle the container instantly
aws ecs update-service --cluster fargate-cluster --service spring-service --force-new-deployment --region ap-south-2

Step 4: Stream Live Logs in your Terminal
aws logs filter-log-events --log-group-name "/ecs/spring-app" --region ap-south-2 --interleaved --limit 100

# remove the resources from aws using terraform
terraform destroy -auto-approve

*****************Terraform*******************
