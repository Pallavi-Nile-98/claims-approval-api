package io.github.pallavinile98.claims;

import org.junit.jupiter.api.Test;

import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/** The load balancer health check depends on this endpoint, and it needs no identity headers. */
class HealthEndpointIT extends AbstractIntegrationTest {

    @Test
    void healthIsUpWithoutIdentityHeaders() throws Exception {
        mvc.perform(get("/actuator/health"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.status").value("UP"));
    }
}
