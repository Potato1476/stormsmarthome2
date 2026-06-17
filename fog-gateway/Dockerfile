# syntax=docker/dockerfile:1
# Multi-stage build — produces linux/arm64-compatible image.
# Build: docker buildx build --platform linux/amd64,linux/arm64 -t fog-gateway:latest .

FROM maven:3.8-eclipse-temurin-8 AS builder
WORKDIR /build
COPY pom.xml .
# Cache dependency downloads separately for faster rebuilds
RUN mvn dependency:go-offline -q
COPY src ./src
RUN mvn package -DskipTests -q
RUN echo "Build complete: $(ls -lh target/fog-gateway-1.0-jar-with-dependencies.jar)"

FROM eclipse-temurin:8-jre-jammy
LABEL maintainer="fog-gateway"
WORKDIR /app

COPY --from=builder /build/target/fog-gateway-1.0-jar-with-dependencies.jar /app/fog-gateway.jar

RUN mkdir -p /var/fog-queue /tmp/fog-storm && \
    echo 'storm.metricstore.class: "org.apache.storm.metricstore.NullMetricStore"' > /app/storm.yaml

# Tunable JVM flags — override via JAVA_OPTS env var.
# -Dstorm.conf.file is hardcoded here so it is never accidentally dropped when
# JAVA_OPTS is overridden from docker-compose or .env.gateway.
ENV JAVA_OPTS="-Xmx384m -XX:+UseSerialGC -Djava.awt.headless=true"

# Prometheus metrics port
EXPOSE 9091

ENTRYPOINT ["sh", "-c", "exec java $JAVA_OPTS -Dstorm.conf.file=/app/storm.yaml -jar /app/fog-gateway.jar"]
