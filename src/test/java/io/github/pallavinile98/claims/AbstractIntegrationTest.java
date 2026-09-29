package io.github.pallavinile98.claims;

import com.jayway.jsonpath.JsonPath;
import io.github.pallavinile98.claims.repository.ClaimRepository;
import org.junit.jupiter.api.BeforeEach;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.context.annotation.Import;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.request.MockHttpServletRequestBuilder;

import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * Base for integration tests: the full application context (controllers, header
 * resolver, validation, error handler, service, JPA, Flyway) against real Postgres.
 *
 * Every subclass uses identical configuration, so Spring caches one context and one
 * container for the whole run instead of starting a new database per test class.
 */
@SpringBootTest
@AutoConfigureMockMvc
@Import(TestcontainersConfiguration.class)
public abstract class AbstractIntegrationTest {

    @Autowired
    protected MockMvc mvc;

    @Autowired
    protected ClaimRepository repository;

    // Tests share one database, so each one starts from an empty table.
    @BeforeEach
    void cleanDatabase() {
        repository.deleteAll();
    }

    /** Adds the identity headers our API expects. */
    protected static MockHttpServletRequestBuilder as(String userId, String role,
                                                       MockHttpServletRequestBuilder request) {
        return request.header("X-User-Id", userId).header("X-User-Role", role);
    }

    /** Creates a DRAFT claim through the API and returns its id. */
    protected long createClaim(String submitterId, String title) throws Exception {
        String body = mvc.perform(as(submitterId, "SUBMITTER", post("/api/claims"))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"title\":\"" + title + "\",\"amount\":42.50}"))
                .andExpect(status().isCreated())
                .andReturn().getResponse().getContentAsString();
        return ((Number) JsonPath.read(body, "$.id")).longValue();
    }

    protected void submitClaim(String submitterId, long id) throws Exception {
        mvc.perform(as(submitterId, "SUBMITTER", post("/api/claims/{id}/submit", id)))
                .andExpect(status().isOk());
    }
}
