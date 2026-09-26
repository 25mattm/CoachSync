# CoachSync Backend

The server-side source of truth for CoachSync. A Spring Boot REST API over MySQL that
the iOS/Mac app syncs through, so coaches on **different Apple IDs** can share one club's
athletes, teams, sessions, and analytics — the cross-Apple-ID sharing CloudKit can't do.

The app stays offline-first (SwiftData); this backend is the shared club store it pushes to
and pulls from. Athlete/session/etc. UUIDs are app-assigned and preserved server-side, so the
two data models line up.

## Tech stack

| | |
|---|---|
| Language | Java 21 (compiles on JDK 25 via `release 21`) |
| Framework | Spring Boot 4.1 (Spring Framework 7, Spring Security 7), Spring Data JPA, Hibernate ORM 7 |
| Build | Maven — use the wrapper `./mvnw` (**there is no global `mvn`**) |
| Database | MySQL at runtime; H2 in-memory for tests only |
| Auth | Sign in with Apple → backend HS256 JWT (see [Authentication](#authentication)) |
| API docs | OpenAPI 3 / Swagger UI via springdoc (see [API documentation](#api-documentation)) |

## Quick start

```bash
cd backend
./mvnw clean test        # build + run the full test suite (H2, no DB needed)
```

> Use `clean` — this repo lives in an iCloud-synced directory, where stale duplicate
> `Filename 2.class` files can otherwise poison `target/`. Don't run `./mvnw` and an Xcode
> build in parallel for the same reason.

### Running locally (needs a MySQL)

`ddl-auto=none` by default (the app never mutates a schema), and H2 is test-scoped, so a live
run needs a real MySQL. The datasource defaults to `jdbc:mysql://localhost:3306/coachsync`
(user `root`, no password), overridable via `COACHSYNC_DB_URL` / `COACHSYNC_DB_USER` /
`COACHSYNC_DB_PASSWORD`. The app serves on **:8080**.

Against an existing local MySQL:

```bash
COACHSYNC_DB_URL=jdbc:mysql://localhost:3306/coachsync \
SPRING_JPA_HIBERNATE_DDL_AUTO=update \
./mvnw spring-boot:run
```

For a disposable instance (used for smoke tests; keeps your real MySQL untouched on :3306):

```bash
mysqld --initialize-insecure --datadir=/tmp/coachsync_smoke_data           # passwordless root
mysqld --datadir=/tmp/coachsync_smoke_data --port=3307 \
       --socket=/tmp/mysql_smoke.sock --mysqlx-port=33070 --mysqlx-socket=/tmp/mysqlx_smoke.sock &
mysql --socket=/tmp/mysql_smoke.sock -u root -e "CREATE DATABASE coachsync_smoke;"
COACHSYNC_DB_URL=jdbc:mysql://127.0.0.1:3307/coachsync_smoke \
COACHSYNC_DB_USER=root SPRING_JPA_HIBERNATE_DDL_AUTO=update ./mvnw spring-boot:run
# teardown: mysqladmin --socket=/tmp/mysql_smoke.sock -u root shutdown && rm -rf /tmp/coachsync_smoke_data
```

> The default `COACHSYNC_ALLOWED_EMAILS` is empty, which **fails closed** — every sign-in
> returns 403 until you set the allowlist. For local API poking, the analytics/CRUD endpoints
> still need a JWT; see [Authentication](#authentication).

## API documentation

springdoc generates a live OpenAPI 3 spec from the controllers. With the app running:

- **Swagger UI** — <http://localhost:8080/swagger-ui.html> (interactive; "Authorize" with a Bearer JWT to try locked endpoints)
- **OpenAPI JSON** — <http://localhost:8080/v3/api-docs>

These are the authoritative, always-current API reference — both paths are permitted without a
token. OpenAPI metadata (title, JWT security scheme) is configured in
[`web/OpenApiConfig.java`](src/main/java/com/coachsync/web/OpenApiConfig.java) and guarded by
`OpenApiDocsTest`.

### Endpoint groups

All under `/api`, JWT-locked except `/api/auth/**`:

| Group | Notes |
|---|---|
| `auth` | `POST /api/auth/apple` — exchange an Apple identity token for a backend JWT (public) |
| `athletes`, `coaches`, `teams` (+ `members`) | CRUD; deletes refuse with 409 when history/references exist; soft-delete via `active`/`archive` |
| `sessions`, `blocks`, `attendance`, `performance` | the practice write-path; block/attendance writes re-run rep-slot reconciliation |
| `notes`, `journal`, `assessments`, `ktc`, `regatta-results`, `fitness-tests`, `heights` | athlete data capture |
| `…/load`, `…/signals`, `analytics/needs-attention`, `…/development-coverage`, `…/growth-velocity`, `…/fitness-benchmarks` | read-only analytics |

## Authentication

Sign in with Apple → backend JWT. `POST /api/auth/apple` verifies the Apple identity token
against Apple's JWKS, links or auto-provisions a `Coach`, and returns an HS256 JWT used as a
`Bearer` token on every `/api/**` call. Wiring lives in `com.coachsync.auth`
([`SecurityConfig`](src/main/java/com/coachsync/auth/SecurityConfig.java),
`AuthService`, `JwtService`, `NimbusAppleTokenVerifier`).

Sign-in is gated by an **approved-email allowlist** (`COACHSYNC_ALLOWED_EMAILS`) that fails
closed — the club holds minors' PII. The JWT secret (`COACHSYNC_JWT_SECRET`) MUST be set in any
real deployment.

## Project layout

```
backend/src/main/java/com/coachsync/
├── domain/        16 JPA @Entity classes + BaseEntity (@MappedSuperclass, assigned-UUID PK)
│   └── enums/     7 enums, persisted as VARCHAR (migration-friendly)
├── repository/    15 Spring Data JpaRepository interfaces
├── service/       per-aggregate services + SlotGenerationService / ReconcileCoordinator
│                  + AthleteHistoryGuard + typed exceptions (404/409/400/...)
├── analytics/     pure, Spring-free helpers (SeasonContext, TrainingLoad, InsightMath)
│                  + analytics services (load, signals, needs-attention, growth, benchmarks)
├── auth/          Sign in with Apple verification, JWT issuance, Spring Security config
└── web/           18 @RestController + GlobalExceptionHandler + OpenApiConfig + dto/ (46 records)
```

Conventions: assigned `UUID` `@Id` (never `@GeneratedValue`); enums as VARCHAR; DTO records for
all request/response bodies (entities never serialized); RFC 9457 `ProblemDetail` errors via one
`@RestControllerAdvice`; `orphanRemoval` only on single-owner aggregates.

## Database schema

The schema is applied **deliberately** (`ddl-auto=none`); the app never alters it.
`deploy/schema-mysql.sql` is a committed snapshot of the Hibernate-generated DDL. Regenerate it
after any entity change:

```bash
./mvnw test -Dtest=SchemaExportTest        # → target/generated-schema-mysql.sql
cp target/generated-schema-mysql.sql deploy/schema-mysql.sql
```

`SchemaExportTest` also acts as a drift guard, deriving expected tables by scanning
`com.coachsync.domain` for `@Entity`.

## Contributing notes — Spring Boot 4 gotchas

- **Jackson 3** — the mapper is `tools.jackson.databind.ObjectMapper`, not `com.fasterxml.jackson.*`; tests prefer JsonPath over autowiring an `ObjectMapper`.
- **Per-module test slices** — `@AutoConfigureMockMvc` lives in `org.springframework.boot.webmvc.test.autoconfigure` (the `spring-boot-webmvc-test` test dep). `@DataJpaTest` is unavailable — use `@SpringBootTest` + `@Transactional`.
- **MockMvc security** — Boot 4's webmvc-test slice no longer auto-applies Spring Security's MockMvc configurer; `TestMockMvcSecurityAutoConfiguration` re-applies it so `@WithMockUser`/`jwt()` work.
- **`src/test/resources/application.properties` replaces the main one** on the test classpath — duplicate any main-only keys (e.g. `spring.mvc.problemdetails.enabled`) there.

## Further reading

- [`../coachsync-training-log-data-model.md`](../coachsync-training-log-data-model.md) — the data-model design spec
- [`../SETUP.md`](../SETUP.md) — unified iOS + backend onboarding
