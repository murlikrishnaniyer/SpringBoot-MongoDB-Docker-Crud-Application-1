FROM eclipse-temurin:21-jdk
ADD target/spring-mongodb-crud-application-0.0.1-SNAPSHOT.jar spring-mongodb-crud-application-0.0.1-SNAPSHOT.jar
ENTRYPOINT ["java","-Djava.security.egd=file:/dev/./urandom","-jar","spring-mongodb-crud-application-0.0.1-SNAPSHOT.jar"]