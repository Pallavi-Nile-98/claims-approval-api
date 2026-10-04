package io.github.pallavinile98.claims;

import org.junit.jupiter.api.Test;
import org.springframework.http.MediaType;

import static org.hamcrest.Matchers.containsString;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.content;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.forwardedUrl;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * The UI is plain static files packaged in the jar (src/main/resources/static), so these
 * tests guard that they are actually served, and without identity headers, which only
 * the /api endpoints require.
 */
class StaticUiIT extends AbstractIntegrationTest {

    @Test
    void rootServesTheUiPage() throws Exception {
        mvc.perform(get("/"))
                .andExpect(status().isOk())
                .andExpect(forwardedUrl("index.html"));
    }

    @Test
    void pageAndAssetsAreServedWithoutIdentityHeaders() throws Exception {
        mvc.perform(get("/index.html"))
                .andExpect(status().isOk())
                .andExpect(content().contentTypeCompatibleWith(MediaType.TEXT_HTML))
                .andExpect(content().string(containsString("<title>Claims Approval</title>")));

        mvc.perform(get("/app.js"))
                .andExpect(status().isOk())
                .andExpect(content().string(containsString("X-User-Id")));

        mvc.perform(get("/styles.css"))
                .andExpect(status().isOk())
                .andExpect(content().contentTypeCompatibleWith("text/css"));
    }
}
