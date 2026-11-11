# Multi-stage Dockerfile - Production Ready
FROM eclipse-temurin:24-jdk as builder

WORKDIR /app

# Copy Maven wrapper and pom
COPY .mvn .mvn
COPY mvnw mvnw.cmd pom.xml ./

# Download dependencies
RUN chmod +x mvnw && ./mvnw dependency:go-offline -B

# Copy source and build
COPY src src
RUN ./mvnw clean package -DskipTests

# Runtime stage - minimal footprint
FROM eclipse-temurin:24-jre-alpine

WORKDIR /app

# Create non-root user for security
RUN addgroup -g 1000 appuser && adduser -D -u 1000 -G appuser appuser

# Copy built JAR from builder
COPY --from=builder /app/target/spring-mongodb-crud-application-0.0.1-SNAPSHOT.jar spring-mongodb-crud-application-0.0.1-SNAPSHOT.jar

# Set ownership
RUN chown -R appuser:appuser /app

# Switch to non-root user
USER appuser

# Health check
HEALTHCHECK --interval=30s --timeout=5s --retries=3 \
  CMD wget --quiet --tries=1 --spider http://localhost:8080/actuator/health || exit 1

# Spring Boot specific JVM flags for containerization
ENV JAVA_OPTS="-Djava.security.egd=file:/dev/./urandom -XX:+UseContainerSupport -XX:MaxRAMPercentage=75.0"

EXPOSE 8080

ENTRYPOINT exec java ${JAVA_OPTS} -jar spring-mongodb-crud-application-0.0.1-SNAPSHOT.jar
