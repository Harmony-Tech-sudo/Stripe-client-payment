-- Run once in the Postgres database used by the n8n workflow.

-- Every Stripe event received. The primary key is the dedupe mechanism.
CREATE TABLE IF NOT EXISTS stripe_events (
  event_id      TEXT PRIMARY KEY,
  event_type    TEXT NOT NULL,
  payload       JSONB NOT NULL,                       -- raw event, kept for replay and audit
  status        TEXT NOT NULL DEFAULT 'received',     -- received | processed | exception
  received_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  processed_at  TIMESTAMPTZ
);
CREATE INDEX IF NOT EXISTS idx_stripe_events_status ON stripe_events (status, received_at);

-- Payments that failed validation and need a human.
CREATE TABLE IF NOT EXISTS finance_exceptions (
  id           BIGSERIAL PRIMARY KEY,
  event_id     TEXT NOT NULL REFERENCES stripe_events (event_id),
  invoice_id   TEXT,
  reasons      JSONB NOT NULL,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  resolved_at  TIMESTAMPTZ,
  resolved_by  TEXT,
  resolution   TEXT
);

-- Append-only record of what the automation did.
CREATE TABLE IF NOT EXISTS audit_log (
  id          BIGSERIAL PRIMARY KEY,
  event_id    TEXT NOT NULL,
  invoice_id  TEXT,
  action      TEXT NOT NULL,
  details     JSONB,
  actor       TEXT NOT NULL DEFAULT 'n8n',
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Block edits and deletes on the audit log.
CREATE OR REPLACE FUNCTION audit_log_immutable() RETURNS trigger AS $$
BEGIN
  RAISE EXCEPTION 'audit_log is append-only';
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS audit_log_no_update ON audit_log;
CREATE TRIGGER audit_log_no_update
  BEFORE UPDATE OR DELETE ON audit_log
  FOR EACH ROW EXECUTE FUNCTION audit_log_immutable();

-- Events that never finished (candidates for a "stuck events" alert):
-- SELECT event_id, event_type, received_at FROM stripe_events
--  WHERE status = 'received' AND received_at < now() - interval '15 minutes';
