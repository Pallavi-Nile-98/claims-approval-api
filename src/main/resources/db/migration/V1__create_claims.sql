CREATE TABLE claims (
    id           BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    title        VARCHAR(200)   NOT NULL,
    description  VARCHAR(2000),
    amount       NUMERIC(12, 2) NOT NULL CHECK (amount > 0),
    status       VARCHAR(20)    NOT NULL
                 CHECK (status IN ('DRAFT', 'SUBMITTED', 'APPROVED', 'REJECTED')),
    submitter_id VARCHAR(100)   NOT NULL,
    approver_id  VARCHAR(100),
    created_at   TIMESTAMPTZ    NOT NULL,
    updated_at   TIMESTAMPTZ    NOT NULL,
    -- Optimistic locking: incremented on every update so concurrent writes are detected.
    version      BIGINT         NOT NULL DEFAULT 0
);

-- The list endpoint filters by status, and submitters only see their own claims.
CREATE INDEX idx_claims_status ON claims (status);
CREATE INDEX idx_claims_submitter_id ON claims (submitter_id);
