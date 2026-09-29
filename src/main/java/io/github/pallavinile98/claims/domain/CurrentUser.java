package io.github.pallavinile98.claims.domain;

/**
 * The caller, as identified by the X-User-Id and X-User-Role headers.
 * Real authentication is out of scope; replacing the header resolver with a JWT
 * or Cognito-based one would leave everything that uses this record unchanged.
 */
public record CurrentUser(String id, Role role) {

    public boolean is(Role expected) {
        return role == expected;
    }
}
