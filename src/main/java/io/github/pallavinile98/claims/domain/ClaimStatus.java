package io.github.pallavinile98.claims.domain;

import java.util.Set;

/**
 * Claim lifecycle: DRAFT -> SUBMITTED -> APPROVED | REJECTED.
 * APPROVED and REJECTED are terminal. The allowed moves live here, in one table,
 * so they can be unit tested without Spring or a database.
 */
public enum ClaimStatus {
    DRAFT,
    SUBMITTED,
    APPROVED,
    REJECTED;

    public Set<ClaimStatus> allowedNextStates() {
        return switch (this) {
            case DRAFT -> Set.of(SUBMITTED);
            case SUBMITTED -> Set.of(APPROVED, REJECTED);
            case APPROVED, REJECTED -> Set.of();
        };
    }

    public boolean canTransitionTo(ClaimStatus target) {
        return allowedNextStates().contains(target);
    }
}
