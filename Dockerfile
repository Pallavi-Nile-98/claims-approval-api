# ---- Stage 1: build the jar with a full JDK ----
FROM eclipse-temurin:21-jdk AS build
WORKDIR /workspace

# Copy only the build definition first so the dependency download is cached
# as its own layer and re-used until pom.xml changes.
COPY .mvn/ .mvn/
COPY mvnw pom.xml ./
RUN chmod +x mvnw && ./mvnw -B -q dependency:go-offline

COPY src/ src/
# Tests run in CI (they need Docker for Testcontainers, which a build stage doesn't have).
RUN ./mvnw -B -q package -DskipTests

# ---- Stage 2: runtime image with only a JRE ----
FROM eclipse-temurin:21-jre
RUN groupadd --system app && useradd --system --gid app --uid 10001 app
WORKDIR /app
COPY --from=build /workspace/target/claims-approval-api-*.jar app.jar

# Never run as root inside the container.
USER app
EXPOSE 8080

# Size the heap from the container's memory limit instead of the host's RAM.
ENTRYPOINT ["java", "-XX:MaxRAMPercentage=75", "-jar", "app.jar"]
