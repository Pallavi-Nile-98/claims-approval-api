package io.github.pallavinile98.claims.dto;

import jakarta.validation.constraints.DecimalMin;
import jakarta.validation.constraints.Digits;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;

import java.math.BigDecimal;

/**
 * Only the fields a submitter may set. Status, submitter and approver are decided
 * by the server, so a client cannot create an already-APPROVED claim.
 * Limits mirror the database columns. Messages are written for end users, since the
 * UI and API clients show them as-is next to the field.
 */
public record CreateClaimRequest(
        @NotBlank(message = "Title is required")
        @Size(max = 200, message = "Title must be at most 200 characters")
        String title,

        @Size(max = 2000, message = "Description must be at most 2000 characters")
        String description,

        @NotNull(message = "Amount is required")
        @DecimalMin(value = "0.01", message = "Amount must be at least 0.01")
        @Digits(integer = 10, fraction = 2,
                message = "Amount can have at most 10 digits before and 2 after the decimal point")
        BigDecimal amount
) {
}
