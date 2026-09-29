package io.github.pallavinile98.claims.domain;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.PrePersist;
import jakarta.persistence.PreUpdate;
import jakarta.persistence.Table;
import jakarta.persistence.Version;

import java.math.BigDecimal;
import java.time.OffsetDateTime;
import java.time.ZoneOffset;
import java.time.temporal.ChronoUnit;

@Entity
@Table(name = "claims")
public class Claim {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(nullable = false, length = 200)
    private String title;

    @Column(length = 2000)
    private String description;

    @Column(nullable = false, precision = 12, scale = 2)
    private BigDecimal amount;

    // Stored as text ("SUBMITTED"), not a number, so reordering the enum can't corrupt rows.
    @Enumerated(EnumType.STRING)
    @Column(nullable = false, length = 20)
    private ClaimStatus status;

    @Column(name = "submitter_id", nullable = false, length = 100)
    private String submitterId;

    @Column(name = "approver_id", length = 100)
    private String approverId;

    @Column(name = "created_at", nullable = false)
    private OffsetDateTime createdAt;

    @Column(name = "updated_at", nullable = false)
    private OffsetDateTime updatedAt;

    @Version
    private long version;

    protected Claim() {
        // required by JPA
    }

    public Claim(String title, String description, BigDecimal amount, String submitterId) {
        this.title = title;
        this.description = description;
        this.amount = amount;
        this.submitterId = submitterId;
        this.status = ClaimStatus.DRAFT;
    }

    @PrePersist
    void onCreate() {
        OffsetDateTime now = now();
        createdAt = now;
        updatedAt = now;
    }

    @PreUpdate
    void onUpdate() {
        updatedAt = now();
    }

    // Postgres TIMESTAMPTZ stores microseconds; truncating here means the value in the
    // response is exactly the value later read back from the database.
    private static OffsetDateTime now() {
        return OffsetDateTime.now(ZoneOffset.UTC).truncatedTo(ChronoUnit.MICROS);
    }

    // No general setters: state only changes through these two methods, which the
    // service layer calls after checking ClaimStatus.canTransitionTo.
    public void changeStatus(ClaimStatus newStatus) {
        this.status = newStatus;
    }

    public void assignApprover(String approverId) {
        this.approverId = approverId;
    }

    public Long getId() { return id; }
    public String getTitle() { return title; }
    public String getDescription() { return description; }
    public BigDecimal getAmount() { return amount; }
    public ClaimStatus getStatus() { return status; }
    public String getSubmitterId() { return submitterId; }
    public String getApproverId() { return approverId; }
    public OffsetDateTime getCreatedAt() { return createdAt; }
    public OffsetDateTime getUpdatedAt() { return updatedAt; }
    public long getVersion() { return version; }
}
