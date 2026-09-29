package io.github.pallavinile98.claims.repository;

import io.github.pallavinile98.claims.domain.Claim;
import io.github.pallavinile98.claims.domain.ClaimStatus;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;

// Spring Data generates the SQL from the method names at startup.
public interface ClaimRepository extends JpaRepository<Claim, Long> {

    Page<Claim> findByStatus(ClaimStatus status, Pageable pageable);

    Page<Claim> findBySubmitterId(String submitterId, Pageable pageable);

    Page<Claim> findBySubmitterIdAndStatus(String submitterId, ClaimStatus status, Pageable pageable);
}
