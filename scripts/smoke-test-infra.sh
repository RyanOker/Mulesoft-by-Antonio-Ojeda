#!/usr/bin/env bash
# Checks that every service in docker-compose.yml is up and seeded correctly.
#   docker compose up -d && scripts/smoke-test-infra.sh
set -uo pipefail
cd "$(dirname "$0")/.."

CARRIER="http://localhost:${CARRIER_MOCK_PORT:-8089}"
RABBIT="http://localhost:${RABBITMQ_UI_PORT:-15672}"
failures=0

check() {  # check "description" "expected" "actual"
    if [ "$2" = "$3" ]; then
        printf '  \033[32mPASS\033[0m %s\n' "$1"
    else
        printf '  \033[31mFAIL\033[0m %s (expected "%s", got "%s")\n' "$1" "$2" "$3"
        failures=$((failures + 1))
    fi
}

psql_as() {  # psql_as user password "sql"
    docker compose exec -T -e PGPASSWORD="$2" postgres \
        psql -h localhost -U "$1" -d fulfillment -tAc "$3" 2>&1 | head -1
}

echo "Waiting for containers to be healthy..."
for _ in $(seq 1 60); do
    healthy=$(docker compose ps --format '{{.Service}} {{.Health}}' | grep -c ' healthy$')
    [ "$healthy" -ge 4 ] && break
    sleep 2
done
check "4 services healthy" "4" "$healthy"

echo "PostgreSQL"
check "15 products seeded"                  "15" "$(psql_as inventory_api inventory_api_local 'select count(*) from inventory.products')"
check "3 seed orders"                       "3"  "$(psql_as orders_api orders_api_local "select count(*) from orders.orders where correlation_id like 'seed-%'")"
check "status history recorded by trigger"  "4"  "$(psql_as orders_api orders_api_local "select count(*) from orders.order_status_history h join orders.orders o using (order_id) where o.order_number = 'ORD-100003'")"
check "inventory_api cannot read orders"    "ERROR:  permission denied for schema orders" \
                                                 "$(psql_as inventory_api inventory_api_local 'select 1 from orders.orders limit 1')"

echo "SFTP"
check "supplier files waiting in inbound/"  "2" "$(docker compose exec -T sftp sh -c 'ls /home/supplier/inbound/*.csv | wc -l' | tr -d ' ')"
check "inbound/ owned by the sftp user"     "supplier" "$(docker compose exec -T sftp stat -c %U /home/supplier/inbound)"

echo "RabbitMQ"
check "guest user disabled"                 "401" "$(curl -s -o /dev/null -w '%{http_code}' -u guest:guest "$RABBIT/api/overview")"
check "4 queues in vhost fulfillment"       "4"   "$(curl -s -u mule:mule_local "$RABBIT/api/queues/fulfillment" | grep -o '"name":"[a-z-]*"' | grep -cE 'order-notifications|payment-events|shipment-events|fulfillment-dlq')"
check "order.* routes to a queue"           '{"routed":true}' \
    "$(curl -s -u mule:mule_local -H 'content-type: application/json' \
        -d '{"properties":{},"routing_key":"order.smoke-test","payload":"{}","payload_encoding":"string"}' \
        "$RABBIT/api/exchanges/fulfillment/fulfillment.events/publish")"
# Remove the test message again.
curl -s -o /dev/null -u mule:mule_local -X DELETE "$RABBIT/api/queues/fulfillment/order-notifications/contents"

echo "Carrier mock (WireMock)"
key='X-Api-Key: fastship-local-key'
check "no API key -> 401"                   "401" "$(curl -s -o /dev/null -w '%{http_code}' -X POST "$CARRIER/v1/rates")"
check "rates -> 200"                        "200" "$(curl -s -o /dev/null -w '%{http_code}' -H "$key" -X POST "$CARRIER/v1/rates")"
check "create shipment -> 201"              "201" "$(curl -s -o /dev/null -w '%{http_code}' -H "$key" -H 'Content-Type: application/json' \
                                                    -d '{"reference":"ORD-1","destination":{"postal_code":"62704"}}' -X POST "$CARRIER/v1/shipments")"
check "bad postal code -> 422"              "422" "$(curl -s -o /dev/null -w '%{http_code}' -H "$key" -H 'Content-Type: application/json' \
                                                    -d '{"reference":"ORD-1","destination":{"postal_code":"00000"}}' -X POST "$CARRIER/v1/shipments")"
curl -s -o /dev/null -X POST "$CARRIER/__admin/scenarios/reset"
flaky=""
for _ in 1 2 3; do
    flaky+="$(curl -s -o /dev/null -w '%{http_code}' -H 'X-Mock-Scenario: flaky' -H 'Content-Type: application/json' \
              -d '{"reference":"ORD-1"}' -X POST "$CARRIER/v1/shipments") "
done
check "flaky scenario: 503, 503, then 201"  "503 503 201 " "$flaky"

echo
if [ "$failures" -eq 0 ]; then
    echo "All checks passed."
else
    echo "$failures check(s) failed."
    exit 1
fi
