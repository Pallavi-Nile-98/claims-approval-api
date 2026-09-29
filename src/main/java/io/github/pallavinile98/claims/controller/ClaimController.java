package io.github.pallavinile98.claims.controller;

import io.github.pallavinile98.claims.domain.ClaimStatus;
import io.github.pallavinile98.claims.domain.CurrentUser;
import io.github.pallavinile98.claims.dto.ClaimResponse;
import io.github.pallavinile98.claims.dto.CreateClaimRequest;
import io.github.pallavinile98.claims.dto.PageResponse;
import io.github.pallavinile98.claims.service.ClaimService;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.validation.Valid;
import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.servlet.support.ServletUriComponentsBuilder;

import java.net.URI;

/**
 * Thin HTTP layer: parse the request, call the service, shape the response.
 * No business rules here; see ClaimService.
 *
 * Each transition is its own endpoint (submit / approve / reject) rather than a
 * generic "PATCH status", because each has different permission rules.
 */
@RestController
@RequestMapping("/api/claims")
@Tag(name = "Claims")
public class ClaimController {

    private final ClaimService service;

    public ClaimController(ClaimService service) {
        this.service = service;
    }

    @PostMapping
    @Operation(summary = "Create a claim in DRAFT (SUBMITTER only)")
    public ResponseEntity<ClaimResponse> create(CurrentUser user, @Valid @RequestBody CreateClaimRequest request) {
        ClaimResponse created = service.create(user, request);
        URI location = ServletUriComponentsBuilder.fromCurrentRequest()
                .path("/{id}").buildAndExpand(created.id()).toUri();
        return ResponseEntity.created(location).body(created);
    }

    @GetMapping("/{id}")
    @Operation(summary = "Get a claim (submitters: own claims only)")
    public ClaimResponse get(CurrentUser user, @PathVariable Long id) {
        return service.get(user, id);
    }

    @GetMapping
    @Operation(summary = "List claims, newest first, optionally filtered by status (submitters: own claims only)")
    public PageResponse<ClaimResponse> list(
            CurrentUser user,
            @RequestParam(required = false) ClaimStatus status,
            @RequestParam(defaultValue = "0") @Min(0) int page,
            @RequestParam(defaultValue = "20") @Min(1) @Max(100) int size) {
        return service.list(user, status, page, size);
    }

    @PostMapping("/{id}/submit")
    @Operation(summary = "Submit a DRAFT claim for review (owning SUBMITTER only)")
    public ClaimResponse submit(CurrentUser user, @PathVariable Long id) {
        return service.submit(user, id);
    }

    @PostMapping("/{id}/approve")
    @Operation(summary = "Approve a SUBMITTED claim (APPROVER only, not their own)")
    public ClaimResponse approve(CurrentUser user, @PathVariable Long id) {
        return service.approve(user, id);
    }

    @PostMapping("/{id}/reject")
    @Operation(summary = "Reject a SUBMITTED claim (APPROVER only, not their own)")
    public ClaimResponse reject(CurrentUser user, @PathVariable Long id) {
        return service.reject(user, id);
    }
}
