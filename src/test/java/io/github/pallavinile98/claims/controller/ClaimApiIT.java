package io.github.pallavinile98.claims.controller;

import io.github.pallavinile98.claims.AbstractIntegrationTest;
import io.github.pallavinile98.claims.domain.ClaimStatus;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.springframework.http.MediaType;

import static org.assertj.core.api.Assertions.assertThat;
import static org.hamcrest.Matchers.containsInAnyOrder;
import static org.hamcrest.Matchers.containsString;
import static org.hamcrest.Matchers.everyItem;
import static org.hamcrest.Matchers.hasSize;
import static org.hamcrest.Matchers.is;
import static org.hamcrest.Matchers.matchesPattern;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.header;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/** The API end to end: HTTP in, real Postgres underneath, JSON out. */
class ClaimApiIT extends AbstractIntegrationTest {

    @Nested
    class HappyPaths {

        @Test
        void createReturns201WithLocationAndDraftStatus() throws Exception {
            mvc.perform(as("alice", "SUBMITTER", post("/api/claims"))
                            .contentType(MediaType.APPLICATION_JSON)
                            .content("{\"title\":\"Taxi\",\"description\":\"Airport\",\"amount\":42.50}"))
                    .andExpect(status().isCreated())
                    .andExpect(header().string("Location", matchesPattern(".*/api/claims/\\d+$")))
                    .andExpect(jsonPath("$.status").value("DRAFT"))
                    .andExpect(jsonPath("$.submitterId").value("alice"))
                    .andExpect(jsonPath("$.amount").value(42.50))
                    .andExpect(jsonPath("$.approverId").doesNotExist());
        }

        @Test
        void claimCanBeSubmittedAndApproved() throws Exception {
            long id = createClaim("alice", "Taxi");
            submitClaim("alice", id);

            mvc.perform(as("bob", "APPROVER", post("/api/claims/{id}/approve", id)))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.status").value("APPROVED"))
                    .andExpect(jsonPath("$.approverId").value("bob"));

            // Read it back to prove the change was persisted, not just returned.
            mvc.perform(as("alice", "SUBMITTER", get("/api/claims/{id}", id)))
                    .andExpect(jsonPath("$.status").value("APPROVED"));
        }

        @Test
        void claimCanBeSubmittedAndRejected() throws Exception {
            long id = createClaim("alice", "Taxi");
            submitClaim("alice", id);

            mvc.perform(as("bob", "APPROVER", post("/api/claims/{id}/reject", id)))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.status").value("REJECTED"))
                    .andExpect(jsonPath("$.approverId").value("bob"));
        }
    }

    @Nested
    class Listing {

        @Test
        void approverFiltersByStatusWithPagination() throws Exception {
            submitClaim("alice", createClaim("alice", "One"));
            submitClaim("alice", createClaim("alice", "Two"));
            createClaim("carol", "Draft only");

            mvc.perform(as("bob", "APPROVER", get("/api/claims"))
                            .param("status", "SUBMITTED").param("page", "0").param("size", "1"))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.content", hasSize(1)))
                    .andExpect(jsonPath("$.content[0].title").value("Two")) // newest first
                    .andExpect(jsonPath("$.totalElements").value(2))
                    .andExpect(jsonPath("$.totalPages").value(2));
        }

        @Test
        void submitterOnlySeesOwnClaims() throws Exception {
            createClaim("alice", "Alice 1");
            createClaim("alice", "Alice 2");
            createClaim("carol", "Carol 1");

            mvc.perform(as("alice", "SUBMITTER", get("/api/claims")))
                    .andExpect(jsonPath("$.totalElements").value(2))
                    .andExpect(jsonPath("$.content[*].submitterId", everyItem(is("alice"))))
                    .andExpect(jsonPath("$.content[*].title", containsInAnyOrder("Alice 1", "Alice 2")));
        }
    }

    @Nested
    class Errors {

        @Test
        void invalidTransitionReturns409AndLeavesClaimUnchanged() throws Exception {
            long id = createClaim("alice", "Taxi");

            mvc.perform(as("bob", "APPROVER", post("/api/claims/{id}/approve", id)))
                    .andExpect(status().isConflict())
                    .andExpect(jsonPath("$.title").value("Invalid state transition"))
                    .andExpect(jsonPath("$.detail", containsString("DRAFT to APPROVED")));

            assertThat(repository.findById(id).orElseThrow().getStatus()).isEqualTo(ClaimStatus.DRAFT);
        }

        @Test
        void validationErrorsListEveryInvalidField() throws Exception {
            mvc.perform(as("alice", "SUBMITTER", post("/api/claims"))
                            .contentType(MediaType.APPLICATION_JSON)
                            .content("{\"title\":\"\",\"amount\":-5}"))
                    .andExpect(status().isBadRequest())
                    .andExpect(jsonPath("$.title").value("Validation failed"))
                    .andExpect(jsonPath("$.errors[*].field", containsInAnyOrder("title", "amount")));

            assertThat(repository.count()).isZero();
        }

        @Test
        void malformedJsonReturns400() throws Exception {
            mvc.perform(as("alice", "SUBMITTER", post("/api/claims"))
                            .contentType(MediaType.APPLICATION_JSON)
                            .content("{\"title\":"))
                    .andExpect(status().isBadRequest())
                    .andExpect(jsonPath("$.status").value(400));
        }

        @Test
        void pageSizeAboveLimitReturns400() throws Exception {
            mvc.perform(as("bob", "APPROVER", get("/api/claims")).param("size", "500"))
                    .andExpect(status().isBadRequest())
                    .andExpect(jsonPath("$.errors[0].field").value("size"));
        }

        @Test
        void missingIdentityHeadersReturn400() throws Exception {
            mvc.perform(get("/api/claims"))
                    .andExpect(status().isBadRequest())
                    .andExpect(jsonPath("$.detail").value("X-User-Id header is required"));
        }

        @Test
        void unknownRoleReturns400() throws Exception {
            mvc.perform(as("eve", "ADMIN", get("/api/claims")))
                    .andExpect(status().isBadRequest())
                    .andExpect(jsonPath("$.detail", containsString("X-User-Role")));
        }

        @Test
        void approverCannotCreateClaim() throws Exception {
            mvc.perform(as("bob", "APPROVER", post("/api/claims"))
                            .contentType(MediaType.APPLICATION_JSON)
                            .content("{\"title\":\"Taxi\",\"amount\":10}"))
                    .andExpect(status().isForbidden());
        }

        @Test
        void approverCannotApproveOwnClaim() throws Exception {
            long id = createClaim("alice", "Taxi");
            submitClaim("alice", id);

            mvc.perform(as("alice", "APPROVER", post("/api/claims/{id}/approve", id)))
                    .andExpect(status().isForbidden())
                    .andExpect(jsonPath("$.detail", containsString("submitted")));
        }

        @Test
        void submitterCannotViewAnotherSubmittersClaim() throws Exception {
            long id = createClaim("alice", "Taxi");

            mvc.perform(as("mallory", "SUBMITTER", get("/api/claims/{id}", id)))
                    .andExpect(status().isForbidden());
        }

        @Test
        void unknownClaimReturns404() throws Exception {
            mvc.perform(as("bob", "APPROVER", get("/api/claims/{id}", 999_999)))
                    .andExpect(status().isNotFound())
                    .andExpect(jsonPath("$.title").value("Claim not found"));
        }
    }
}
