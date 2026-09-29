package io.github.pallavinile98.claims.repository;

import io.github.pallavinile98.claims.AbstractIntegrationTest;
import io.github.pallavinile98.claims.domain.Claim;
import io.github.pallavinile98.claims.domain.ClaimStatus;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.orm.ObjectOptimisticLockingFailureException;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

/** Guarantees that live in the database schema itself, not in Java code. */
class PersistenceIT extends AbstractIntegrationTest {

    @Autowired
    private JdbcTemplate jdbc;

    /**
     * Simulates two approvers racing: one loads the claim, the other changes it
     * first, then the first saves its now-stale copy. @Version must reject it.
     */
    @Test
    void staleUpdateIsRejectedByOptimisticLocking() throws Exception {
        long id = createClaim("alice", "Taxi");
        Claim staleCopy = repository.findById(id).orElseThrow(); // version 0, detached

        submitClaim("alice", id); // another request wins the race: version -> 1

        staleCopy.changeStatus(ClaimStatus.REJECTED);
        assertThatThrownBy(() -> repository.saveAndFlush(staleCopy))
                .isInstanceOf(ObjectOptimisticLockingFailureException.class);

        assertThat(repository.findById(id).orElseThrow().getStatus()).isEqualTo(ClaimStatus.SUBMITTED);
    }

    /** The CHECK constraint stops invalid statuses even when the application is bypassed. */
    @Test
    void databaseRejectsUnknownStatusEvenFromRawSql() throws Exception {
        long id = createClaim("alice", "Taxi");

        assertThatThrownBy(() -> jdbc.update("UPDATE claims SET status = 'PAID' WHERE id = ?", id))
                .isInstanceOf(DataIntegrityViolationException.class);
    }
}
