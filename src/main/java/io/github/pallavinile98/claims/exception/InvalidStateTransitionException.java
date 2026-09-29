package io.github.pallavinile98.claims.exception;

import io.github.pallavinile98.claims.domain.ClaimStatus;

/** Maps to 409: the request is valid, but conflicts with the claim's current state. */
public class InvalidStateTransitionException extends RuntimeException {

    public InvalidStateTransitionException(Long claimId, ClaimStatus from, ClaimStatus to) {
        super("Claim " + claimId + " cannot move from " + from + " to " + to
                + "; allowed next states: " + from.allowedNextStates());
    }
}
