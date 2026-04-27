-- WASCO MySQL demo data
INSERT INTO branches (branch_name, district, phone, email) VALUES
('Maseru Main', 'Maseru', '+26622310000', 'maseru@wasco.co.ls'),
('Leribe Branch', 'Leribe', '+26622550000', 'leribe@wasco.co.ls'),
('Mafeteng Branch', 'Mafeteng', '+26622990000', 'mafeteng@wasco.co.ls');

INSERT INTO users (full_name, username, email, password_hash, role, status) VALUES
('Admin User', 'admin1', 'admin@wasco.com', 'hashedpass', 'ADMIN', 'ACTIVE'),
('John Customer', 'cust1', 'john@gmail.com', 'hashedpass', 'CUSTOMER', 'ACTIVE'),
('Manager User', 'manager1', 'manager@wasco.com', 'hashedpass', 'MANAGER', 'ACTIVE'),
('Sarah Molefe', 'cust2', 'sarah@gmail.com', 'hashedpass', 'CUSTOMER', 'ACTIVE');

INSERT INTO customers (account_number, user_id, branch_id, full_name, national_id, phone, email, address_line, district, service_type, meter_number, connection_date, account_status) VALUES
('ACC-1001', 2, 1, 'John Customer', '123456789', '+26660000001', 'john@gmail.com', 'Maseru West', 'Maseru', 'DOMESTIC', 'MTR-001', '2024-01-10', 'ACTIVE'),
('ACC-1002', 4, 2, 'Sarah Molefe', '987654321', '+26660000002', 'sarah@gmail.com', 'Hlotse Area', 'Leribe', 'DOMESTIC', 'MTR-002', '2024-02-15', 'ACTIVE');

INSERT INTO billing_rates (service_type, rate_tier, min_units, max_units, cost_per_unit, fixed_charge, effective_from, status) VALUES
('DOMESTIC', 'Tier 1', 0, 15, 3.50, 50.00, '2024-01-01', 'ACTIVE'),
('DOMESTIC', 'Tier 2', 16, 50, 5.00, 50.00, '2024-01-01', 'ACTIVE'),
('COMMERCIAL', 'Commercial Standard', 0, NULL, 5.20, 120.00, '2024-01-01', 'ACTIVE');

INSERT INTO water_usage (customer_id, reading_month, previous_reading, current_reading, units_consumed, recorded_by, notes) VALUES
(1, '2026-03-01', 100.00, 142.00, 42.00, 1, 'Monthly reading captured'),
(2, '2026-03-01', 200.00, 250.00, 50.00, 1, 'Monthly reading captured');

INSERT INTO bills (bill_number, customer_id, usage_id, billing_month, due_date, subtotal_amount, fixed_charge, tax_amount, total_amount, payment_status, generated_by) VALUES
('BILL-1001', 1, 1, '2026-03-01', '2026-03-25', 147.00, 50.00, 0.00, 197.00, 'PENDING', 1),
('BILL-1002', 2, 2, '2026-03-01', '2026-03-25', 250.00, 50.00, 0.00, 300.00, 'PARTIAL', 1);

INSERT INTO payments (bill_id, customer_id, receipt_number, amount_paid, payment_method, payment_reference, payment_date, payment_status, recorded_by) VALUES
(1, 1, 'RCPT-3001', 197.00, 'MOBILE_MONEY', 'MM-1001', '2026-03-20 10:00:00', 'SUCCESS', 1),
(2, 2, 'RCPT-3002', 150.00, 'CASH', 'CS-1002', '2026-03-21 11:30:00', 'PARTIAL', 1);

INSERT INTO notifications (customer_id, bill_id, notification_type, channel, subject, message, sent_status, sent_at) VALUES
(1, 1, 'PAYMENT_CONFIRMATION', 'SMS', 'Payment received', 'Your payment for BILL-1001 has been received.', 'SENT', '2026-03-20 10:05:00'),
(2, 2, 'BILL_REMINDER', 'EMAIL', 'Outstanding balance', 'Your bill BILL-1002 still has an outstanding balance.', 'SENT', '2026-03-22 08:00:00');

INSERT INTO leakage_reports (customer_id, district, location_description, report_description, priority, report_status, assigned_branch_id) VALUES
(1, 'Maseru', 'Maseru West', 'Pipe burst near customer residence', 'HIGH', 'OPEN', 1),
(2, 'Leribe', 'Hlotse Main Road', 'Street-side water leakage reported', 'MEDIUM', 'IN_PROGRESS', 2);

INSERT INTO sync_log (table_name, record_id, operation_type, source_db, target_db, sync_status, sync_message, synced_at) VALUES
('customers', 1, 'INSERT', 'MySQL', 'PostgreSQL', 'SUCCESS', 'Customer mirrored successfully', '2026-03-20 09:30:00'),
('payments', 1, 'INSERT', 'MySQL', 'PostgreSQL', 'SUCCESS', 'Payment mirrored successfully', '2026-03-20 10:10:00');
