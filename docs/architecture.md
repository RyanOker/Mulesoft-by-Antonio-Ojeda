# Architecture

## Business scenario

*Northwind Home Office* sells desks, chairs and accessories online. Before
this project every system was integrated point-to-point. The integration hub
replaces that with reusable APIs:

- Customers live in **Salesforce** (as Contacts).
- Products, stock and orders live in **PostgreSQL**.
- Card payments go through **Stripe**.
- Parcels are shipped with the **FastShip** carrier.
- Two suppliers drop a **CSV stock file on SFTP** every night.
- The warehouse and customer service want **notifications** (Slack, e-mail).

## API-led layers

| Layer | Responsibility | Rule |
|-------|----------------|------|
| **System** | Unlock one system of record. Hide its data model, protocol and credentials. | Contains no business process. Only one System API per data store. |
| **Process** | Implement the business process by combining System APIs. | Owns no data. Talks to systems only through System APIs. |
| **Experience** | Shape data for a specific consumer (web, mobile). | Thin. Security policies applied here in API Manager. |

The System APIs can be reused by any future process (returns, B2B portal,
reporting) without touching Salesforce, Stripe or the database again.

## Place-order sequence

```mermaid
sequenceDiagram
    autonumber
    actor C as Web shop
    participant E as orders-exp-api
    participant P as order-process-api
    participant CU as customer-sys-api
    participant I as inventory-sys-api
    participant S as shipping-sys-api
    participant O as order-sys-api
    participant PA as payment-sys-api
    participant MQ as RabbitMQ

    C->>E: POST /orders (Idempotency-Key)
    E->>P: POST /orders
    P->>CU: GET /customers?email=
    alt not found
        P->>CU: POST /customers
    end
    P->>I: GET /products/{sku} (prices from DB, not from client)
    P->>S: POST /rates
    P->>O: POST /orders -> RECEIVED
    P->>I: POST /reservations
    alt insufficient stock
        P->>O: PATCH status FAILED
        P-->>E: 409 INSUFFICIENT_STOCK
    end
    P->>O: PATCH status STOCK_RESERVED
    P->>PA: POST /payments (Idempotency-Key)
    alt card declined
        P->>I: POST /reservations/{id}/release
        P->>O: PATCH status FAILED
        P-->>E: 402 PAYMENT_DECLINED
    end
    P->>O: PATCH status PAID, paymentId
    P->>MQ: publish order.paid
    P-->>E: 201 order
    E-->>C: 201 order (customer-friendly view)

    Note over MQ,P: asynchronously
    MQ->>P: order.paid
    P->>S: POST /shipments (retries on 503)
    P->>I: POST /reservations/{id}/commit
    P->>O: PATCH status SHIPPED, trackingNumber
    P->>MQ: publish order.shipped
```

## Events

Exchange `fulfillment.events` (topic) in vhost `fulfillment`:

| Routing key | Published by | Consumed by (queue) |
|-------------|--------------|---------------------|
| `order.created`, `order.paid`, `order.shipped`, `order.cancelled`, `order.failed` | order-process-api | `order-notifications` (Slack / e-mail); `order.paid` also triggers shipping |
| `payment.succeeded`, `payment.failed`, `payment.refunded` | payment-sys-api (from Stripe webhooks) | `payment-events` → order-process-api |
| `shipment.*` | shipping-sys-api (carrier tracking updates, later phase) | `shipment-events` → order-process-api |

All work queues are quorum queues with `x-delivery-limit: 5`. After five
failed deliveries a message is moved through `fulfillment.dlx` to
`fulfillment-dlq` for manual inspection.

## Data model

```mermaid
erDiagram
    PRODUCTS ||--|| STOCK : has
    PRODUCTS ||--o{ RESERVATION_ITEMS : reserved_in
    RESERVATIONS ||--|{ RESERVATION_ITEMS : contains
    PRODUCTS ||--o{ SUPPLIER_ITEMS : supplied_as
    ORDERS ||--|{ ORDER_ITEMS : contains
    ORDERS ||--|{ ORDER_STATUS_HISTORY : logs

    PRODUCTS {
        varchar sku PK
        varchar name
        numeric unit_price
        boolean active
    }
    STOCK {
        varchar sku PK
        int quantity_on_hand
        int quantity_reserved
    }
    RESERVATIONS {
        uuid reservation_id PK
        uuid order_id UK
        varchar status
    }
    SUPPLIER_ITEMS {
        varchar supplier_code PK
        varchar supplier_sku PK
        int quantity_available
    }
    ORDERS {
        uuid order_id PK
        varchar order_number UK
        varchar customer_id
        varchar status
        varchar idempotency_key UK
    }
    ORDER_ITEMS {
        uuid order_id PK
        smallint line_number PK
        varchar sku
    }
    ORDER_STATUS_HISTORY {
        bigint id PK
        varchar from_status
        varchar to_status
    }
```

`inventory.*` and `orders.*` are separate schemas with separate database
users. There are deliberately **no foreign keys between the two schemas**
(`orders.order_items.sku`, `orders.orders.reservation_id`): they belong to
different APIs and could live in different databases.

Full DDL: [`infra/postgres/init/01-schema.sql`](../infra/postgres/init/01-schema.sql).

## Cross-cutting concerns

| Concern | Approach |
|---------|----------|
| Correlation | `X-Correlation-ID` accepted or generated at the edge, passed to every downstream call and message, written in every log line and every error body. |
| Errors | One `Error` type for all APIs (`shared/raml/common-library.raml`). Global error handler per app maps connector errors to HTTP status codes. |
| Configuration | `config/${env}.yaml` per app, secrets in encrypted secure properties. Nothing environment-specific in flows. |
| Security | Experience layer: Client ID Enforcement + Rate Limiting (API Manager). System layer: not public (CloudHub 2.0 private space / internal ingress). Stripe webhooks verified by signature. |
| Resilience | HTTP timeouts on every requester, Until Successful only for idempotent or keyed calls, dead-letter queue for messages. |
| Testing | MUnit per flow with external systems mocked, 80% coverage enforced in CI (from phase 2). |
