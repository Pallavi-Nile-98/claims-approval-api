package io.github.pallavinile98.claims;

import org.springframework.boot.test.context.TestConfiguration;
import org.springframework.boot.testcontainers.service.connection.ServiceConnection;
import org.springframework.context.annotation.Bean;
import org.testcontainers.containers.PostgreSQLContainer;
import org.testcontainers.utility.DockerImageName;

/**
 * Starts a throwaway PostgreSQL in Docker for integration tests.
 *
 * Same major version as docker-compose and RDS (16), so the tests exercise the real
 * dialect, CHECK constraints and TIMESTAMPTZ behaviour, which H2 would only imitate.
 * @ServiceConnection points the DataSource (and Flyway) at the container
 * automatically, overriding the DB_URL/DB_USERNAME/DB_PASSWORD settings.
 */
@TestConfiguration(proxyBeanMethods = false)
public class TestcontainersConfiguration {

    @Bean
    @ServiceConnection
    PostgreSQLContainer<?> postgres() {
        return new PostgreSQLContainer<>(DockerImageName.parse("postgres:16-alpine"));
    }
}
