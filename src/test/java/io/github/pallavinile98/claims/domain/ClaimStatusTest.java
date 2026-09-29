package io.github.pallavinile98.claims.domain;

import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.CsvSource;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * The full 4x4 transition table, written out by hand. Expected values are
 * deliberately NOT derived from ClaimStatus itself, otherwise the test would
 * just repeat the code under test and could never fail.
 */
class ClaimStatusTest {

    @ParameterizedTest(name = "{0} -> {1} allowed = {2}")
    @CsvSource({
            // from,     to,        allowed
            "DRAFT,      DRAFT,     false",
            "DRAFT,      SUBMITTED, true",
            "DRAFT,      APPROVED,  false",   // must be submitted first
            "DRAFT,      REJECTED,  false",
            "SUBMITTED,  DRAFT,     false",   // no withdrawing back to draft
            "SUBMITTED,  SUBMITTED, false",
            "SUBMITTED,  APPROVED,  true",
            "SUBMITTED,  REJECTED,  true",
            "APPROVED,   DRAFT,     false",   // APPROVED is terminal
            "APPROVED,   SUBMITTED, false",
            "APPROVED,   APPROVED,  false",
            "APPROVED,   REJECTED,  false",
            "REJECTED,   DRAFT,     false",   // REJECTED is terminal
            "REJECTED,   SUBMITTED, false",
            "REJECTED,   APPROVED,  false",
            "REJECTED,   REJECTED,  false",
    })
    void transitionTable(ClaimStatus from, ClaimStatus to, boolean allowed) {
        assertThat(from.canTransitionTo(to)).isEqualTo(allowed);
    }
}
