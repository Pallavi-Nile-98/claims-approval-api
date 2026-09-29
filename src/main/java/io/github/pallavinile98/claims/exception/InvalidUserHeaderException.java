package io.github.pallavinile98.claims.exception;

/** Maps to 400: X-User-Id or X-User-Role is missing or malformed. */
public class InvalidUserHeaderException extends RuntimeException {

    public InvalidUserHeaderException(String message) {
        super(message);
    }
}
