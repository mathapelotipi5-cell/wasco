-- WASCO PostgreSQL schema
DROP TABLE IF EXISTS sync_log CASCADE;
DROP TABLE IF EXISTS leakage_reports CASCADE;
DROP TABLE IF EXISTS notifications CASCADE;
DROP TABLE IF EXISTS payments CASCADE;
DROP TABLE IF EXISTS bills CASCADE;
DROP TABLE IF EXISTS water_usage CASCADE;
DROP TABLE IF EXISTS billing_rates CASCADE;
DROP TABLE IF EXISTS customers CASCADE;
DROP TABLE IF EXISTS users CASCADE;
DROP TABLE IF EXISTS branches CASCADE;

DROP TYPE IF EXISTS user_role CASCADE;
DROP TYPE IF EXISTS user_status CASCADE;
DROP TYPE IF EXISTS service_type_enum CASCADE;
DROP TYPE IF EXISTS account_status_enum CASCADE;
DROP TYPE IF EXISTS active_status_enum CASCADE;
DROP TYPE IF EXISTS bill_payment_status_enum CASCADE;
DROP TYPE IF EXISTS payment_method_enum CASCADE;
DROP TYPE IF EXISTS payment_status_enum CASCADE;
DROP TYPE IF EXISTS notification_type_enum CASCADE;
DROP TYPE IF EXISTS notification_channel_enum CASCADE;
DROP TYPE IF EXISTS notification_status_enum CASCADE;
DROP TYPE IF EXISTS priority_enum CASCADE;
DROP TYPE IF EXISTS report_status_enum CASCADE;
DROP TYPE IF EXISTS operation_type_enum CASCADE;
DROP TYPE IF EXISTS sync_status_enum CASCADE;

CREATE TYPE user_role AS ENUM ('ADMIN','CUSTOMER','MANAGER');
CREATE TYPE user_status AS ENUM ('ACTIVE','PENDING','SUSPENDED');
CREATE TYPE service_type_enum AS ENUM ('DOMESTIC','COMMERCIAL','INDUSTRIAL');
CREATE TYPE account_status_enum AS ENUM ('ACTIVE','INACTIVE','PENDING','FLAGGED');
CREATE TYPE active_status_enum AS ENUM ('ACTIVE','INACTIVE');
CREATE TYPE bill_payment_status_enum AS ENUM ('PENDING','PARTIAL','PAID','OVERDUE','CANCELLED');
CREATE TYPE payment_method_enum AS ENUM ('CASH','CARD','BANK_TRANSFER','MOBILE_MONEY','ONLINE_GATEWAY');
CREATE TYPE payment_status_enum AS ENUM ('SUCCESS','PENDING','FAILED','PARTIAL');
CREATE TYPE notification_type_enum AS ENUM ('BILL_REMINDER','PAYMENT_CONFIRMATION','USAGE_ALERT','SERVICE_NOTICE');
CREATE TYPE notification_channel_enum AS ENUM ('SMS','EMAIL','SYSTEM');
CREATE TYPE notification_status_enum AS ENUM ('PENDING','SENT','FAILED','READ');
CREATE TYPE priority_enum AS ENUM ('LOW','MEDIUM','HIGH');
CREATE TYPE report_status_enum AS ENUM ('OPEN','IN_PROGRESS','RESOLVED','CLOSED');
CREATE TYPE operation_type_enum AS ENUM ('INSERT','UPDATE','DELETE');
CREATE TYPE sync_status_enum AS ENUM ('PENDING','SUCCESS','FAILED');

CREATE TABLE IF NOT EXISTS branches (
    branch_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    branch_name VARCHAR(100) NOT NULL,
    district VARCHAR(100) NOT NULL,
    phone VARCHAR(30),
    email VARCHAR(150),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uq_branch_name_district UNIQUE (branch_name, district)
);

CREATE TABLE IF NOT EXISTS users (
    user_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    full_name VARCHAR(150) NOT NULL,
    username VARCHAR(60) NOT NULL,
    email VARCHAR(150),
    password_hash VARCHAR(255) NOT NULL,
    role user_role NOT NULL,
    status user_status NOT NULL DEFAULT 'ACTIVE',
    last_login_at TIMESTAMP NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uq_users_username UNIQUE (username),
    CONSTRAINT uq_users_email UNIQUE (email)
);

CREATE TABLE IF NOT EXISTS customers (
    customer_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    account_number VARCHAR(30) NOT NULL,
    user_id BIGINT NULL,
    branch_id BIGINT NOT NULL,
    full_name VARCHAR(150) NOT NULL,
    national_id VARCHAR(50),
    phone VARCHAR(30),
    email VARCHAR(150),
    address_line VARCHAR(255) NOT NULL,
    district VARCHAR(100) NOT NULL,
    service_type service_type_enum NOT NULL DEFAULT 'DOMESTIC',
    meter_number VARCHAR(50),
    connection_date DATE,
    account_status account_status_enum NOT NULL DEFAULT 'ACTIVE',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uq_customers_account_number UNIQUE (account_number),
    CONSTRAINT uq_customers_meter_number UNIQUE (meter_number),
    CONSTRAINT fk_customers_user FOREIGN KEY (user_id) REFERENCES users(user_id)
        ON DELETE SET NULL,
    CONSTRAINT fk_customers_branch FOREIGN KEY (branch_id) REFERENCES branches(branch_id)
        ON DELETE RESTRICT
);

CREATE TABLE IF NOT EXISTS billing_rates (
    rate_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    service_type service_type_enum NOT NULL,
    rate_tier VARCHAR(100) NOT NULL,
    min_units NUMERIC(10,2) NOT NULL,
    max_units NUMERIC(10,2) NULL,
    cost_per_unit NUMERIC(10,2) NOT NULL,
    fixed_charge NUMERIC(10,2) NOT NULL DEFAULT 0.00,
    effective_from DATE NOT NULL,
    effective_to DATE NULL,
    status active_status_enum NOT NULL DEFAULT 'ACTIVE',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT chk_billing_rates_min_units CHECK (min_units >= 0),
    CONSTRAINT chk_billing_rates_max_units CHECK (max_units IS NULL OR max_units >= min_units)
);

CREATE TABLE IF NOT EXISTS water_usage (
    usage_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    customer_id BIGINT NOT NULL,
    reading_month DATE NOT NULL,
    previous_reading NUMERIC(12,2) NOT NULL DEFAULT 0.00,
    current_reading NUMERIC(12,2) NOT NULL,
    units_consumed NUMERIC(12,2) NOT NULL,
    recorded_by BIGINT NULL,
    recorded_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    notes VARCHAR(255),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uq_water_usage_customer_month UNIQUE (customer_id, reading_month),
    CONSTRAINT fk_usage_customer FOREIGN KEY (customer_id) REFERENCES customers(customer_id)
        ON DELETE CASCADE,
    CONSTRAINT fk_usage_user FOREIGN KEY (recorded_by) REFERENCES users(user_id)
        ON DELETE SET NULL,
    CONSTRAINT chk_current_reading CHECK (current_reading >= previous_reading),
    CONSTRAINT chk_units_consumed CHECK (units_consumed >= 0)
);

CREATE TABLE IF NOT EXISTS bills (
    bill_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    bill_number VARCHAR(30) NOT NULL,
    customer_id BIGINT NOT NULL,
    usage_id BIGINT NULL,
    billing_month DATE NOT NULL,
    due_date DATE NOT NULL,
    subtotal_amount NUMERIC(12,2) NOT NULL DEFAULT 0.00,
    fixed_charge NUMERIC(12,2) NOT NULL DEFAULT 0.00,
    tax_amount NUMERIC(12,2) NOT NULL DEFAULT 0.00,
    total_amount NUMERIC(12,2) NOT NULL DEFAULT 0.00,
    payment_status bill_payment_status_enum NOT NULL DEFAULT 'PENDING',
    generated_by BIGINT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uq_bills_bill_number UNIQUE (bill_number),
    CONSTRAINT uq_bills_customer_month UNIQUE (customer_id, billing_month),
    CONSTRAINT fk_bills_customer FOREIGN KEY (customer_id) REFERENCES customers(customer_id)
        ON DELETE CASCADE,
    CONSTRAINT fk_bills_usage FOREIGN KEY (usage_id) REFERENCES water_usage(usage_id)
        ON DELETE SET NULL,
    CONSTRAINT fk_bills_user FOREIGN KEY (generated_by) REFERENCES users(user_id)
        ON DELETE SET NULL,
    CONSTRAINT chk_bill_amounts CHECK (subtotal_amount >= 0 AND fixed_charge >= 0 AND tax_amount >= 0 AND total_amount >= 0)
);

CREATE TABLE IF NOT EXISTS payments (
    payment_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    bill_id BIGINT NOT NULL,
    customer_id BIGINT NOT NULL,
    receipt_number VARCHAR(40) NOT NULL,
    amount_paid NUMERIC(12,2) NOT NULL,
    payment_method payment_method_enum NOT NULL,
    payment_reference VARCHAR(100),
    payment_date TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    payment_status payment_status_enum NOT NULL DEFAULT 'SUCCESS',
    recorded_by BIGINT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uq_payments_receipt_number UNIQUE (receipt_number),
    CONSTRAINT fk_payments_bill FOREIGN KEY (bill_id) REFERENCES bills(bill_id)
        ON DELETE CASCADE,
    CONSTRAINT fk_payments_customer FOREIGN KEY (customer_id) REFERENCES customers(customer_id)
        ON DELETE CASCADE,
    CONSTRAINT fk_payments_user FOREIGN KEY (recorded_by) REFERENCES users(user_id)
        ON DELETE SET NULL,
    CONSTRAINT chk_amount_paid CHECK (amount_paid >= 0)
);

CREATE TABLE IF NOT EXISTS notifications (
    notification_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    customer_id BIGINT NOT NULL,
    bill_id BIGINT NULL,
    notification_type notification_type_enum NOT NULL,
    channel notification_channel_enum NOT NULL DEFAULT 'SYSTEM',
    subject VARCHAR(150),
    message TEXT NOT NULL,
    sent_status notification_status_enum NOT NULL DEFAULT 'PENDING',
    sent_at TIMESTAMP NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_notifications_customer FOREIGN KEY (customer_id) REFERENCES customers(customer_id)
        ON DELETE CASCADE,
    CONSTRAINT fk_notifications_bill FOREIGN KEY (bill_id) REFERENCES bills(bill_id)
        ON DELETE SET NULL
);

CREATE TABLE IF NOT EXISTS leakage_reports (
    leakage_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    customer_id BIGINT NULL,
    district VARCHAR(100) NOT NULL,
    location_description VARCHAR(255) NOT NULL,
    report_description TEXT NOT NULL,
    priority priority_enum NOT NULL DEFAULT 'MEDIUM',
    report_status report_status_enum NOT NULL DEFAULT 'OPEN',
    reported_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    resolved_at TIMESTAMP NULL,
    assigned_branch_id BIGINT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_leakage_customer FOREIGN KEY (customer_id) REFERENCES customers(customer_id)
        ON DELETE SET NULL,
    CONSTRAINT fk_leakage_branch FOREIGN KEY (assigned_branch_id) REFERENCES branches(branch_id)
        ON DELETE SET NULL
);

CREATE TABLE IF NOT EXISTS sync_log (
    sync_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    table_name VARCHAR(100) NOT NULL,
    record_id BIGINT NULL,
    operation_type operation_type_enum NOT NULL,
    source_db VARCHAR(30) NOT NULL,
    target_db VARCHAR(30) NOT NULL,
    sync_status sync_status_enum NOT NULL DEFAULT 'PENDING',
    sync_message VARCHAR(255),
    synced_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
