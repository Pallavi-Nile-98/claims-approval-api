package io.github.pallavinile98.claims.exception;

/** Maps to 404. */
public class ClaimNotFoundException extends RuntimeException {

    public ClaimNotFoundException(Long id) {
        super("Claim " + id + " was not found");
    }
}
