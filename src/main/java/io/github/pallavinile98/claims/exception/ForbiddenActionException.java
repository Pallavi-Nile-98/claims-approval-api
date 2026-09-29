package io.github.pallavinile98.claims.exception;

/**
 * Maps to 403: the caller is identified but not allowed to do this.
 * Named to avoid confusion with Spring Security's AccessDeniedException.
 */
public class ForbiddenActionException extends RuntimeException {

    public ForbiddenActionException(String message) {
        super(message);
    }
}
