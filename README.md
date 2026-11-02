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
