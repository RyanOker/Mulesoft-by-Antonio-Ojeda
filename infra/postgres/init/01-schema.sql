-- =====================================================================
-- Order-to-Fulfillment Integration Hub - database schema
--
-- Two schemas in one database, each owned by exactly one System API:
--   inventory -> inventory-sys-api (and the supplier-sync batch job)
--   orders    -> order-sys-api
-- No other application should read or write these tables directly.
-- =====================================================================

CREATE EXTENSION IF NOT EXISTS pgcrypto;  -- gen_random_uuid()

CREATE SCHEMA IF NOT EXISTS inventory;
CREATE SCHEMA IF NOT EXISTS orders;

-- Keeps updated_at current on every UPDATE.
CREATE OR REPLACE FUNCTION public.touch_updated_at() RETURNS trigger AS $$
BEGIN
    NEW.updated_at := now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- ---------------------------------------------------------------------
-- inventory schema
-- ---------------------------------------------------------------------

CREATE TABLE inventory.products (
    sku          VARCHAR(32)    PRIMARY KEY,
    name         VARCHAR(200)   NOT NULL,
    description  TEXT,
    category     VARCHAR(50)    NOT NULL,
    unit_price   NUMERIC(10, 2) NOT NULL CHECK (unit_price >= 0),
    currency     CHAR(3)        NOT NULL DEFAULT 'USD',
    weight_kg    NUMERIC(8, 3)  NOT NULL DEFAULT 0 CHECK (weight_kg >= 0),
    active       BOOLEAN        NOT NULL DEFAULT TRUE,
    created_at   TIMESTAMPTZ    NOT NULL DEFAULT now(),
    updated_at   TIMESTAMPTZ    NOT NULL DEFAULT now()
);

CREATE TABLE inventory.stock (
    sku                VARCHAR(32) PRIMARY KEY REFERENCES inventory.products (sku),
    quantity_on_hand   INTEGER     NOT NULL DEFAULT 0 CHECK (quantity_on_hand >= 0),
    quantity_reserved  INTEGER     NOT NULL DEFAULT 0 CHECK (quantity_reserved >= 0),
    reorder_level      INTEGER     NOT NULL DEFAULT 10 CHECK (reorder_level >= 0),
    updated_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT stock_reserved_le_on_hand CHECK (quantity_reserved <= quantity_on_hand)
);

-- Stock held for an order between "order placed" and "order shipped".
CREATE TABLE inventory.reservations (
    reservation_id  UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    order_id        UUID        NOT NULL UNIQUE,  -- one reservation per order (idempotency)
    status          VARCHAR(16) NOT NULL DEFAULT 'RESERVED'
                    CHECK (status IN ('RESERVED', 'COMMITTED', 'RELEASED', 'EXPIRED')),
    expires_at      TIMESTAMPTZ NOT NULL DEFAULT now() + INTERVAL '30 minutes',
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE inventory.reservation_items (
    reservation_id  UUID        NOT NULL REFERENCES inventory.reservations (reservation_id) ON DELETE CASCADE,
    sku             VARCHAR(32) NOT NULL REFERENCES inventory.products (sku),
    quantity        INTEGER     NOT NULL CHECK (quantity > 0),
    PRIMARY KEY (reservation_id, sku)
);

-- Supplier catalogue rows loaded by the supplier-sync batch job.
CREATE TABLE inventory.supplier_items (
    supplier_code       VARCHAR(32)    NOT NULL,
    supplier_sku        VARCHAR(64)    NOT NULL,
    sku                 VARCHAR(32)    NOT NULL REFERENCES inventory.products (sku),
    quantity_available  INTEGER        NOT NULL CHECK (quantity_available >= 0),
    unit_cost           NUMERIC(10, 2) NOT NULL CHECK (unit_cost >= 0),
    currency            CHAR(3)        NOT NULL,
    supplier_updated_at TIMESTAMPTZ    NOT NULL,
    loaded_at           TIMESTAMPTZ    NOT NULL DEFAULT now(),
    PRIMARY KEY (supplier_code, supplier_sku)
);

-- One row per supplier file. Makes the batch job idempotent: a file that
-- was already processed is skipped instead of being loaded twice.
CREATE TABLE inventory.supplier_sync_runs (
    run_id          UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    file_name       VARCHAR(255) NOT NULL,
    file_checksum   VARCHAR(64)  NOT NULL UNIQUE,
    status          VARCHAR(16)  NOT NULL DEFAULT 'RUNNING'
                    CHECK (status IN ('RUNNING', 'COMPLETED', 'COMPLETED_WITH_ERRORS', 'FAILED')),
    records_total   INTEGER      NOT NULL DEFAULT 0,
    records_ok      INTEGER      NOT NULL DEFAULT 0,
    records_failed  INTEGER      NOT NULL DEFAULT 0,
    started_at      TIMESTAMPTZ  NOT NULL DEFAULT now(),
    finished_at     TIMESTAMPTZ
);

CREATE INDEX idx_products_category  ON inventory.products (category) WHERE active;
CREATE INDEX idx_reservations_open  ON inventory.reservations (expires_at) WHERE status = 'RESERVED';

CREATE TRIGGER trg_products_updated     BEFORE UPDATE ON inventory.products     FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();
CREATE TRIGGER trg_stock_updated        BEFORE UPDATE ON inventory.stock        FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();
CREATE TRIGGER trg_reservations_updated BEFORE UPDATE ON inventory.reservations FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();

-- What the API returns for GET /inventory/{sku}.
CREATE VIEW inventory.v_availability AS
SELECT p.sku,
       p.name,
       s.quantity_on_hand,
       s.quantity_reserved,
       s.quantity_on_hand - s.quantity_reserved AS quantity_available,
       (s.quantity_on_hand - s.quantity_reserved) <= s.reorder_level AS needs_reorder,
       s.updated_at
FROM inventory.products p
JOIN inventory.stock s ON s.sku = p.sku
WHERE p.active;

-- ---------------------------------------------------------------------
-- orders schema
-- ---------------------------------------------------------------------

CREATE SEQUENCE orders.order_number_seq START 100001;

CREATE TABLE orders.orders (
    order_id         UUID           PRIMARY KEY DEFAULT gen_random_uuid(),
    order_number     VARCHAR(20)    NOT NULL UNIQUE
                     DEFAULT 'ORD-' || nextval('orders.order_number_seq'),
    customer_id      VARCHAR(18)    NOT NULL,          -- Salesforce Contact Id
    customer_email   VARCHAR(254)   NOT NULL,
    status           VARCHAR(24)    NOT NULL DEFAULT 'RECEIVED'
                     CHECK (status IN ('RECEIVED', 'STOCK_RESERVED', 'PAYMENT_PENDING', 'PAID',
                                       'SHIPPED', 'DELIVERED', 'CANCELLED', 'FAILED')),
    currency         CHAR(3)        NOT NULL DEFAULT 'USD',
    subtotal         NUMERIC(12, 2) NOT NULL DEFAULT 0 CHECK (subtotal >= 0),
    shipping_cost    NUMERIC(12, 2) NOT NULL DEFAULT 0 CHECK (shipping_cost >= 0),
    total            NUMERIC(12, 2) GENERATED ALWAYS AS (subtotal + shipping_cost) STORED,
    shipping_address JSONB          NOT NULL,
    reservation_id   UUID,                             -- inventory.reservations (other API's data, no FK)
    payment_id       VARCHAR(64),                      -- Stripe PaymentIntent id
    tracking_number  VARCHAR(64),                      -- carrier tracking number
    idempotency_key  VARCHAR(64)    UNIQUE,            -- client-supplied, prevents duplicate orders
    correlation_id   VARCHAR(64)    NOT NULL,
    created_at       TIMESTAMPTZ    NOT NULL DEFAULT now(),
    updated_at       TIMESTAMPTZ    NOT NULL DEFAULT now()
);

CREATE TABLE orders.order_items (
    order_id     UUID           NOT NULL REFERENCES orders.orders (order_id) ON DELETE CASCADE,
    line_number  SMALLINT       NOT NULL CHECK (line_number > 0),
    sku          VARCHAR(32)    NOT NULL,
    product_name VARCHAR(200)   NOT NULL,
    quantity     INTEGER        NOT NULL CHECK (quantity > 0),
    unit_price   NUMERIC(10, 2) NOT NULL CHECK (unit_price >= 0),
    line_total   NUMERIC(12, 2) GENERATED ALWAYS AS (quantity * unit_price) STORED,
    PRIMARY KEY (order_id, line_number)
);

-- Audit trail; filled automatically by trigger whenever status changes.
CREATE TABLE orders.order_status_history (
    id           BIGSERIAL   PRIMARY KEY,
    order_id     UUID        NOT NULL REFERENCES orders.orders (order_id) ON DELETE CASCADE,
    from_status  VARCHAR(24),
    to_status    VARCHAR(24) NOT NULL,
    changed_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Webhook / message de-duplication (e.g. Stripe sends the same event more than once).
CREATE TABLE orders.processed_events (
    event_id     VARCHAR(128) PRIMARY KEY,
    source       VARCHAR(32)  NOT NULL,
    event_type   VARCHAR(64)  NOT NULL,
    received_at  TIMESTAMPTZ  NOT NULL DEFAULT now()
);

CREATE INDEX idx_orders_customer ON orders.orders (customer_id, created_at DESC);
CREATE INDEX idx_orders_status   ON orders.orders (status);

CREATE TRIGGER trg_orders_updated BEFORE UPDATE ON orders.orders FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();

CREATE OR REPLACE FUNCTION orders.log_status_change() RETURNS trigger AS $$
BEGIN
    IF TG_OP = 'INSERT' OR NEW.status IS DISTINCT FROM OLD.status THEN
        INSERT INTO orders.order_status_history (order_id, from_status, to_status)
        VALUES (NEW.order_id, CASE WHEN TG_OP = 'UPDATE' THEN OLD.status END, NEW.status);
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_orders_status_history
    AFTER INSERT OR UPDATE OF status ON orders.orders
    FOR EACH ROW EXECUTE FUNCTION orders.log_status_change();

-- ---------------------------------------------------------------------
-- Application users: one per System API, least privilege.
-- (Local-dev passwords only. Real environments use secure properties.)
-- ---------------------------------------------------------------------

CREATE ROLE inventory_api LOGIN PASSWORD 'inventory_api_local';
GRANT USAGE ON SCHEMA inventory TO inventory_api;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA inventory TO inventory_api;

CREATE ROLE orders_api LOGIN PASSWORD 'orders_api_local';
GRANT USAGE ON SCHEMA orders TO orders_api;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA orders TO orders_api;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA orders TO orders_api;
