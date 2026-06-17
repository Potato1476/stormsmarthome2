# syntax=docker/dockerfile:1
# Builds the fog-cloud topology JAR.
# The JAR is submitted to the Storm cluster via docker-compose (cloud-topo-submit service).

FROM maven:3.8-openjdk-8 AS builder
WORKDIR /build

# Build TagAwareScheduler first (dependency for nimbus)
COPY tagawarescheduler ./tagawarescheduler
RUN cd tagawarescheduler && mvn package -DskipTests -q

# Build fog-cloud topology
COPY pom.xml .
RUN mvn dependency:go-offline -q
COPY src ./src
RUN mvn package -DskipTests -q
RUN echo "Build complete: $(ls -lh target/fog-cloud-1.0-jar-with-dependencies.jar)"

# Thin image just to hold the JARs — actual execution is in storm:2.1.0 containers
FROM alpine:3.18
COPY --from=builder /build/target/fog-cloud-1.0-jar-with-dependencies.jar /jars/fog-cloud.jar
COPY --from=builder /build/tagawarescheduler/target/tagawarescheduler-1.0.jar /jars/tagawarescheduler.jar
CMD ["sh", "-c", "echo 'JAR image ready. Mount /jars into storm containers.'"]
