# syntax=docker/dockerfile:1

# --- Build stage: compile the bootable fat jar with the bundled Maven wrapper (no host Maven) ---
FROM eclipse-temurin:21-jdk AS build
WORKDIR /build
# Copy the wrapper + pom first so dependency download caches in its own layer; a code-only
# change then reuses that layer. go-offline is best-effort (package re-fetches anything it misses).
COPY .mvn/ .mvn/
COPY mvnw pom.xml ./
RUN ./mvnw -q -B dependency:go-offline || true
COPY src/ src/
RUN ./mvnw -q -B -DskipTests package

# --- Runtime stage: slim JRE with just the jar, running as a non-root user ---
FROM eclipse-temurin:21-jre AS runtime
WORKDIR /app
RUN useradd --system --uid 1001 --no-create-home coachsync
COPY --from=build /build/target/coachsync-backend-*.jar app.jar
USER coachsync
EXPOSE 8080
# Activate the production profile (tightens logging/schema); override any env at deploy time.
ENV SPRING_PROFILES_ACTIVE=prod
ENTRYPOINT ["java", "-jar", "app.jar"]
