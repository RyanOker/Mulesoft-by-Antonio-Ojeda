-- =====================================================================
-- Seed data for local development and demos.
-- Fictional "Northwind Home Office" catalogue.
-- =====================================================================

INSERT INTO inventory.products (sku, name, description, category, unit_price, weight_kg) VALUES
    ('DSK-1001', 'Standing Desk Frame',          'Dual-motor height adjustable frame, 70-120 cm',   'FURNITURE',   349.00, 28.500),
    ('DSK-1002', 'Bamboo Desktop 140x70',        'Solid bamboo desktop, 25 mm',                      'FURNITURE',   189.00, 14.000),
    ('CHR-2001', 'Ergonomic Mesh Chair',         'Lumbar support, 4D armrests',                      'FURNITURE',   279.00, 17.200),
    ('CHR-2002', 'Anti-Fatigue Standing Mat',    '90x50 cm, bevelled edges',                         'FURNITURE',    49.00,  2.100),
    ('MON-3001', '27in 4K Monitor',              'IPS, USB-C 65 W power delivery',                   'ELECTRONICS', 399.00,  6.300),
    ('MON-3002', 'Dual Monitor Arm',             'Gas spring, VESA 75/100',                          'ACCESSORIES',  89.00,  4.800),
    ('KBD-4001', 'Mechanical Keyboard TKL',      'Hot-swap switches, white backlight',               'ELECTRONICS', 119.00,  0.900),
    ('MSE-4002', 'Wireless Vertical Mouse',      'Bluetooth + 2.4 GHz, rechargeable',                'ELECTRONICS',  59.00,  0.150),
    ('HUB-5001', 'USB-C Docking Station',        '12-in-1, dual HDMI, 100 W pass-through',           'ELECTRONICS', 149.00,  0.400),
    ('CAM-5002', '1080p Webcam',                 'Auto-focus, privacy shutter, dual mic',            'ELECTRONICS',  79.00,  0.200),
    ('HDS-5003', 'Noise-Cancelling Headset',     'USB-A/USB-C, boom mic',                            'ELECTRONICS', 129.00,  0.300),
    ('LMP-6001', 'LED Desk Lamp',                'Adjustable colour temperature, wireless charger',  'ACCESSORIES',  45.00,  1.200),
    ('CBL-6002', 'Cable Management Tray',        'Under-desk steel tray, 60 cm',                     'ACCESSORIES',  25.00,  1.000),
    ('PLT-6003', 'Desk Plant Pot Set',           'Three ceramic pots with drainage',                 'ACCESSORIES',  32.00,  2.400),
    ('CHR-2099', 'Classic Leather Chair',        'Discontinued model',                               'FURNITURE',   399.00, 21.000);

UPDATE inventory.products SET active = FALSE WHERE sku = 'CHR-2099';

INSERT INTO inventory.stock (sku, quantity_on_hand, quantity_reserved, reorder_level) VALUES
    ('DSK-1001',  42, 1, 10),
    ('DSK-1002',  60, 1, 10),
    ('CHR-2001',  25, 0,  8),
    ('CHR-2002', 120, 0, 20),
    ('MON-3001',  18, 1,  5),
    ('MON-3002',  35, 0, 10),
    ('KBD-4001',  80, 0, 15),
    ('MSE-4002', 150, 0, 25),
    ('HUB-5001',   9, 0, 10),   -- below reorder level: shows up in "needs_reorder"
    ('CAM-5002',  44, 0, 10),
    ('HDS-5003',   0, 0,  5),   -- out of stock: good for testing the "insufficient stock" path
    ('LMP-6001',  70, 0, 15),
    ('CBL-6002', 200, 0, 30),
    ('PLT-6003',  55, 0, 10),
    ('CHR-2099',   3, 0,  0);

-- ---------------------------------------------------------------------
-- Sample orders in different lifecycle states.
-- customer_id values are placeholder Salesforce Contact Ids; replace
-- them with real ones from your Developer Edition org when you connect it.
-- ---------------------------------------------------------------------

INSERT INTO orders.orders (order_id, customer_id, customer_email, status, subtotal, shipping_cost,
                           shipping_address, payment_id, tracking_number, correlation_id)
VALUES
    ('7f0c4c2e-1d2a-4c5e-9a51-0b6f2a7c1001', '003DEMO00000000001', 'maria.lopez@example.com', 'RECEIVED',
     538.00, 0.00,
     '{"line1":"742 Evergreen Terrace","city":"Springfield","state":"IL","postalCode":"62704","country":"US"}',
     NULL, NULL, 'seed-0001'),
    ('7f0c4c2e-1d2a-4c5e-9a51-0b6f2a7c1002', '003DEMO00000000002', 'james.chen@example.com', 'PAID',
     399.00, 15.00,
     '{"line1":"1600 Main St","line2":"Apt 4B","city":"Austin","state":"TX","postalCode":"73301","country":"US"}',
     'pi_demo_000000000000000002', NULL, 'seed-0002');

-- This order is walked through its lifecycle with UPDATEs so that the
-- status-history trigger records every transition.
INSERT INTO orders.orders (order_id, customer_id, customer_email, status, subtotal, shipping_cost,
                           shipping_address, correlation_id)
VALUES
    ('7f0c4c2e-1d2a-4c5e-9a51-0b6f2a7c1003', '003DEMO00000000001', 'maria.lopez@example.com', 'RECEIVED',
     203.00, 9.90,
     '{"line1":"742 Evergreen Terrace","city":"Springfield","state":"IL","postalCode":"62704","country":"US"}',
     'seed-0003');

UPDATE orders.orders SET status = 'STOCK_RESERVED'                                     WHERE order_id = '7f0c4c2e-1d2a-4c5e-9a51-0b6f2a7c1003';
UPDATE orders.orders SET status = 'PAID',    payment_id = 'pi_demo_000000000000000003' WHERE order_id = '7f0c4c2e-1d2a-4c5e-9a51-0b6f2a7c1003';
UPDATE orders.orders SET status = 'SHIPPED', tracking_number = 'FS1Z00000003'          WHERE order_id = '7f0c4c2e-1d2a-4c5e-9a51-0b6f2a7c1003';

INSERT INTO orders.order_items (order_id, line_number, sku, product_name, quantity, unit_price) VALUES
    ('7f0c4c2e-1d2a-4c5e-9a51-0b6f2a7c1001', 1, 'DSK-1001', 'Standing Desk Frame',    1, 349.00),
    ('7f0c4c2e-1d2a-4c5e-9a51-0b6f2a7c1001', 2, 'DSK-1002', 'Bamboo Desktop 140x70',  1, 189.00),
    ('7f0c4c2e-1d2a-4c5e-9a51-0b6f2a7c1002', 1, 'MON-3001', '27in 4K Monitor',        1, 399.00),
    ('7f0c4c2e-1d2a-4c5e-9a51-0b6f2a7c1003', 1, 'KBD-4001', 'Mechanical Keyboard TKL', 1, 119.00),
    ('7f0c4c2e-1d2a-4c5e-9a51-0b6f2a7c1003', 2, 'MSE-4002', 'Wireless Vertical Mouse', 1,  59.00),
    ('7f0c4c2e-1d2a-4c5e-9a51-0b6f2a7c1003', 3, 'CBL-6002', 'Cable Management Tray',   1,  25.00);

-- Open reservations matching the stock.quantity_reserved figures above.
INSERT INTO inventory.reservations (reservation_id, order_id, status) VALUES
    ('a1b2c3d4-0000-4000-8000-000000000001', '7f0c4c2e-1d2a-4c5e-9a51-0b6f2a7c1001', 'RESERVED'),
    ('a1b2c3d4-0000-4000-8000-000000000002', '7f0c4c2e-1d2a-4c5e-9a51-0b6f2a7c1002', 'RESERVED');

INSERT INTO inventory.reservation_items (reservation_id, sku, quantity) VALUES
    ('a1b2c3d4-0000-4000-8000-000000000001', 'DSK-1001', 1),
    ('a1b2c3d4-0000-4000-8000-000000000001', 'DSK-1002', 1),
    ('a1b2c3d4-0000-4000-8000-000000000002', 'MON-3001', 1);

UPDATE orders.orders SET reservation_id = 'a1b2c3d4-0000-4000-8000-000000000001' WHERE order_id = '7f0c4c2e-1d2a-4c5e-9a51-0b6f2a7c1001';
UPDATE orders.orders SET reservation_id = 'a1b2c3d4-0000-4000-8000-000000000002' WHERE order_id = '7f0c4c2e-1d2a-4c5e-9a51-0b6f2a7c1002';
