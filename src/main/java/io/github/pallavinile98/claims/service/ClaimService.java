package io.github.pallavinile98.claims.service;

import io.github.pallavinile98.claims.domain.Claim;
import io.github.pallavinile98.claims.domain.ClaimStatus;
import io.github.pallavinile98.claims.domain.CurrentUser;
import io.github.pallavinile98.claims.domain.Role;
import io.github.pallavinile98.claims.dto.ClaimResponse;
import io.github.pallavinile98.claims.dto.CreateClaimRequest;
import io.github.pallavinile98.claims.dto.PageResponse;
import io.github.pallavinile98.claims.exception.ClaimNotFoundException;
import io.github.pallavinile98.claims.exception.ForbiddenActionException;
import io.github.pallavinile98.claims.exception.InvalidStateTransitionException;
import io.github.pallavinile98.claims.repository.ClaimRepository;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.PageRequest;
import org.springframework.data.domain.Pageable;
import org.springframework.data.domain.Sort;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * All business rules live here: who may do what, and which status changes are legal.
 * Controllers only translate HTTP to these calls, so the rules hold no matter how
 * the service is invoked.
 *
 * Updates use saveAndFlush so the UPDATE (and its @Version check and updatedAt
 * timestamp) happens before the response is built, not later at commit.
 */
@Service
@Transactional
public class ClaimService {

    private final ClaimRepository claims;

    public ClaimService(ClaimRepository claims) {
        this.claims = claims;
    }

    public ClaimResponse create(CurrentUser user, CreateClaimRequest request) {
        requireRole(user, Role.SUBMITTER, "Only submitters can create claims");
        Claim claim = new Claim(request.title(), request.description(), request.amount(), user.id());
        return ClaimResponse.from(claims.save(claim));
    }

    @Transactional(readOnly = true)
    public ClaimResponse get(CurrentUser user, Long id) {
        Claim claim = findClaim(id);
        if (user.is(Role.SUBMITTER) && !claim.getSubmitterId().equals(user.id())) {
            throw new ForbiddenActionException("Submitters can only view their own claims");
        }
        return ClaimResponse.from(claim);
    }

    @Transactional(readOnly = true)
    public PageResponse<ClaimResponse> list(CurrentUser user, ClaimStatus status, int page, int size) {
        // Newest first; a fixed sort also keeps pages stable between requests.
        Pageable pageable = PageRequest.of(page, size, Sort.by(Sort.Direction.DESC, "createdAt", "id"));

        Page<Claim> result;
        if (user.is(Role.APPROVER)) {
            result = status == null ? claims.findAll(pageable) : claims.findByStatus(status, pageable);
        } else {
            result = status == null
                    ? claims.findBySubmitterId(user.id(), pageable)
                    : claims.findBySubmitterIdAndStatus(user.id(), status, pageable);
        }
        return PageResponse.from(result.map(ClaimResponse::from));
    }

    public ClaimResponse submit(CurrentUser user, Long id) {
        requireRole(user, Role.SUBMITTER, "Only submitters can submit claims");
        Claim claim = findClaim(id);
        if (!claim.getSubmitterId().equals(user.id())) {
            throw new ForbiddenActionException("Submitters can only submit their own claims");
        }
        transition(claim, ClaimStatus.SUBMITTED);
        return ClaimResponse.from(claims.saveAndFlush(claim));
    }

    public ClaimResponse approve(CurrentUser user, Long id) {
        return review(user, id, ClaimStatus.APPROVED);
    }

    public ClaimResponse reject(CurrentUser user, Long id) {
        return review(user, id, ClaimStatus.REJECTED);
    }

    private ClaimResponse review(CurrentUser user, Long id, ClaimStatus decision) {
        requireRole(user, Role.APPROVER, "Only approvers can approve or reject claims");
        Claim claim = findClaim(id);
        // Separation of duties: nobody signs off on their own claim.
        if (claim.getSubmitterId().equals(user.id())) {
            throw new ForbiddenActionException("Approvers cannot review a claim they submitted");
        }
        transition(claim, decision);
        claim.assignApprover(user.id());
        return ClaimResponse.from(claims.saveAndFlush(claim));
    }

    /** The single place a status changes, so the state machine cannot be bypassed. */
    private void transition(Claim claim, ClaimStatus target) {
        if (!claim.getStatus().canTransitionTo(target)) {
            throw new InvalidStateTransitionException(claim.getId(), claim.getStatus(), target);
        }
        claim.changeStatus(target);
    }

    private Claim findClaim(Long id) {
        return claims.findById(id).orElseThrow(() -> new ClaimNotFoundException(id));
    }

    private static void requireRole(CurrentUser user, Role role, String message) {
        if (!user.is(role)) {
            throw new ForbiddenActionException(message);
        }
    }
}
