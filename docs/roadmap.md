# Roadmap

Each phase is small enough to finish in a few evenings and gives you
something to show (and post about) at the end.

## Phase 1: Foundation ✅

- [x] Repository layout, parent POM with all versions in one place
- [x] RAML 1.0 specs for all 7 APIs, shared library of types and traits
- [x] AMF spec validation, run in GitHub Actions
- [x] Docker Compose: PostgreSQL, SFTP, RabbitMQ, carrier mock (WireMock)
- [x] Database schema with separate schemas and users per System API, seed data
- [x] Carrier mock with failure scenarios (slow, down, flaky, invalid address)
- [x] Supplier CSV samples including bad rows
- [x] Infrastructure smoke test

**Before Phase 2:** open the project in Anypoint Studio or Code Builder and
let it suggest the latest connector and runtime versions, then update the
`<properties>` in the root `pom.xml`. The versions there were chosen without
access to the MuleSoft repository and may be behind.

## Phase 2: First System APIs (PostgreSQL + carrier)

- [ ] `inventory-sys-api`: APIkit scaffolding, Database connector, reservations in a transaction, scheduled expiry of old reservations
- [ ] `order-sys-api`: CRUD, status-transition rules in DataWeave, `processed-events`
- [ ] `shipping-sys-api`: HTTP requester with timeout, Until Successful on `503`, mapping of carrier errors
- [ ] Shared global error handler and correlation-id handling (same pattern in every app)
- [ ] MUnit tests with mocked connectors; set `failBuild` to `true` in the parent POM

**Show it:** Postman collection and a short screen recording of the `flaky` scenario being retried.

## Phase 3: Salesforce and Stripe

- [ ] Salesforce Developer Edition: create the org, a connected app or security token
- [ ] `customer-sys-api`: Salesforce connector, SOQL queries, Contact field mapping
- [ ] `payment-sys-api`: Stripe PaymentIntents (form-encoded requests, amounts in cents), refunds, `Idempotency-Key` passthrough
- [ ] Stripe webhook endpoint with signature verification, publish `payment.*` to RabbitMQ
- [ ] Secure properties: encrypt secrets with the Secure Properties Tool

## Phase 4: Process API

- [ ] `order-process-api`: place-order orchestration with compensation (see the spec)
- [ ] `GET /orders/{id}` with Scatter-Gather across order, payment and shipping
- [ ] AMQP listeners: `order.paid` → ship, `payment-events`, notifications to Slack and Mailtrap
- [ ] Idempotency with Object Store on `Idempotency-Key`

## Phase 5: Experience API and batch

- [ ] `orders-exp-api`: customer-facing views, status labels, product caching
- [ ] `supplier-sync`: SFTP listener + Scheduler, Batch Job with validation step, bulk upsert, run log in `supplier_sync_runs`, file moved to `processed/` or `error/`

## Phase 6: Deploy and operate

- [ ] Anypoint Platform trial: publish specs to Exchange (and the shared library as a RAML fragment)
- [ ] Deploy to CloudHub 2.0; System APIs internal only
- [ ] API Manager: Client ID Enforcement and Rate Limiting SLA on the Experience API
- [ ] GitHub Actions: `mvn test` (MUnit) and `mvn deploy` to CloudHub with a Connected App
- [ ] Use a free hosted PostgreSQL (e.g. Neon) and a public SFTP alternative for the cloud deployment
- [ ] Record a 2-3 minute demo video for LinkedIn and this README
