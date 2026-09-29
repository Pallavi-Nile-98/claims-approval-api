package io.github.pallavinile98.claims.controller;

import io.github.pallavinile98.claims.domain.CurrentUser;
import io.github.pallavinile98.claims.domain.Role;
import io.github.pallavinile98.claims.exception.InvalidUserHeaderException;
import org.springframework.core.MethodParameter;
import org.springframework.web.bind.support.WebDataBinderFactory;
import org.springframework.web.context.request.NativeWebRequest;
import org.springframework.web.method.support.HandlerMethodArgumentResolver;
import org.springframework.web.method.support.ModelAndViewContainer;

import java.util.Arrays;
import java.util.Locale;

/**
 * Builds a CurrentUser from the request headers for any controller method that
 * declares a CurrentUser parameter, so header parsing lives in exactly one place.
 */
public class CurrentUserArgumentResolver implements HandlerMethodArgumentResolver {

    public static final String USER_ID_HEADER = "X-User-Id";
    public static final String USER_ROLE_HEADER = "X-User-Role";
    private static final int MAX_USER_ID_LENGTH = 100; // matches submitter_id / approver_id columns

    @Override
    public boolean supportsParameter(MethodParameter parameter) {
        return parameter.getParameterType().equals(CurrentUser.class);
    }

    @Override
    public CurrentUser resolveArgument(MethodParameter parameter, ModelAndViewContainer mavContainer,
                                       NativeWebRequest request, WebDataBinderFactory binderFactory) {
        String id = request.getHeader(USER_ID_HEADER);
        String roleHeader = request.getHeader(USER_ROLE_HEADER);

        if (id == null || id.isBlank()) {
            throw new InvalidUserHeaderException(USER_ID_HEADER + " header is required");
        }
        if (id.length() > MAX_USER_ID_LENGTH) {
            throw new InvalidUserHeaderException(
                    USER_ID_HEADER + " must be at most " + MAX_USER_ID_LENGTH + " characters");
        }
        if (roleHeader == null || roleHeader.isBlank()) {
            throw new InvalidUserHeaderException(USER_ROLE_HEADER + " header is required");
        }

        try {
            Role role = Role.valueOf(roleHeader.trim().toUpperCase(Locale.ROOT));
            return new CurrentUser(id.trim(), role);
        } catch (IllegalArgumentException e) {
            throw new InvalidUserHeaderException(
                    USER_ROLE_HEADER + " must be one of " + Arrays.toString(Role.values()));
        }
    }
}
