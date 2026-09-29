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

_TODO (Phase 1)_

## Tests

_TODO (Phase 2)_

## Deploy to AWS

_TODO (Phase 4)_

## Design decisions

_TODO (Phase 6)_
