# Claims Approval API

A REST API where submitters create insurance claims and approvers review them.
Claims move through `DRAFT -> SUBMITTED -> APPROVED | REJECTED`, and invalid
transitions are rejected with a clear error. Built with Spring Boot 3 / Java 21,
PostgreSQL, and deployed to AWS (ECS Fargate, RDS, ALB) with Terraform.

> Work in progress. Sections below are filled in as each phase lands.

## Run locally

Requires Java 21 and Docker.

```bash
cp .env.example .env          # then set real passwords in .env
docker compose up -d          # starts PostgreSQL on localhost:5434
./mvnw spring-boot:run        # on Windows: mvnw.cmd spring-boot:run
curl http://localhost:8080/actuator/health
```

## Architecture

_TODO (Phase 6)_

## API

Interactive docs: **Swagger UI** at `http://localhost:8080/swagger-ui.html`
(OpenAPI JSON at `/v3/api-docs`).

| Method | Path | Who | Result |
|---|---|---|---|
| `POST` | `/api/claims` | SUBMITTER | 201, claim in `DRAFT`, `Location` header |
| `GET` | `/api/claims/{id}` | APPROVER, or the owning SUBMITTER | 200 |
| `GET` | `/api/claims?status=&page=0&size=20` | APPROVER sees all, SUBMITTER sees own | 200, newest first, `size` max 100 |
| `POST` | `/api/claims/{id}/submit` | owning SUBMITTER | `DRAFT -> SUBMITTED` |
| `POST` | `/api/claims/{id}/approve` | APPROVER (not the submitter) | `SUBMITTED -> APPROVED` |
| `POST` | `/api/claims/{id}/reject` | APPROVER (not the submitter) | `SUBMITTED -> REJECTED` |

### Identity (demo only)

Every request carries two headers:

```
X-User-Id: alice
X-User-Role: SUBMITTER | APPROVER
```

> **Real authentication is out of scope.** Anyone can send any header, so this
> must never face real users as-is. All header parsing lives in one class
> (`CurrentUserArgumentResolver`); swapping it for JWT/OIDC validation (e.g.
> Amazon Cognito) would leave the controllers and business rules unchanged.

### Errors

All errors use [RFC 9457 Problem Details](https://www.rfc-editor.org/rfc/rfc9457):

```json
{
  "type": "about:blank",
  "title": "Invalid state transition",
  "status": 409,
  "detail": "Claim 1 cannot move from DRAFT to APPROVED; allowed next states: [SUBMITTED]",
  "instance": "/api/claims/1/approve"
}
```

| Status | When |
|---|---|
| 400 | Invalid body or parameters (with a per-field `errors` list), malformed JSON, missing/invalid identity headers |
| 403 | Wrong role, someone else's claim, or an approver reviewing their own claim |
| 404 | Claim does not exist |
| 409 | Illegal status transition, or a concurrent update (optimistic locking via a `version` column) |

### Example

```bash
curl -X POST localhost:8080/api/claims \
  -H "X-User-Id: alice" -H "X-User-Role: SUBMITTER" -H "Content-Type: application/json" \
  -d '{"title":"Taxi to client site","amount":42.50}'
curl -X POST localhost:8080/api/claims/1/submit  -H "X-User-Id: alice" -H "X-User-Role: SUBMITTER"
curl -X POST localhost:8080/api/claims/1/approve -H "X-User-Id: bob"   -H "X-User-Role: APPROVER"
```

## Tests

_TODO (Phase 2)_

## Deploy to AWS

_TODO (Phase 4)_

## Design decisions

_TODO (Phase 6)_
