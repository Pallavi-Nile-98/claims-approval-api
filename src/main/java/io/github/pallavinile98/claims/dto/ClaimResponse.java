package io.github.pallavinile98.claims.dto;

import io.github.pallavinile98.claims.domain.Claim;
import io.github.pallavinile98.claims.domain.ClaimStatus;

import java.math.BigDecimal;
import java.time.OffsetDateTime;

public record ClaimResponse(
        Long id,
        String title,
        String description,
        BigDecimal amount,
        ClaimStatus status,
        String submitterId,
        String approverId,
        OffsetDateTime createdAt,
        OffsetDateTime updatedAt
) {

    public static ClaimResponse from(Claim claim) {
        return new ClaimResponse(
                claim.getId(),
                claim.getTitle(),
                claim.getDescription(),
                claim.getAmount(),
                claim.getStatus(),
                claim.getSubmitterId(),
                claim.getApproverId(),
                claim.getCreatedAt(),
                claim.getUpdatedAt());
    }
}
