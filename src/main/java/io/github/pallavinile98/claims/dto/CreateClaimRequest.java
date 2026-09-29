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
 * Limits mirror the database columns.
 */
public record CreateClaimRequest(
        @NotBlank @Size(max = 200) String title,
        @Size(max = 2000) String description,
        @NotNull @DecimalMin("0.01") @Digits(integer = 10, fraction = 2) BigDecimal amount
) {
}
