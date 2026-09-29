package io.github.pallavinile98.claims.dto;

import org.springframework.data.domain.Page;

import java.util.List;

/**
 * Our own page envelope. Serialising Spring's Page directly exposes internal
 * fields whose shape can change between Spring versions (Spring itself warns about it).
 */
public record PageResponse<T>(
        List<T> content,
        int page,
        int size,
        long totalElements,
        int totalPages
) {

    public static <T> PageResponse<T> from(Page<T> page) {
        return new PageResponse<>(
                page.getContent(),
                page.getNumber(),
                page.getSize(),
                page.getTotalElements(),
                page.getTotalPages());
    }
}
