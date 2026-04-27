-- WASCO MySQL schema
DROP TABLE IF EXISTS sync_log;
DROP TABLE IF EXISTS leakage_reports;
DROP TABLE IF EXISTS notifications;
DROP TABLE IF EXISTS payments;
DROP TABLE IF EXISTS bills;
DROP TABLE IF EXISTS water_usage;
DROP TABLE IF EXISTS billing_rates;
DROP TABLE IF EXISTS customers;
DROP TABLE IF EXISTS users;
DROP TABLE IF EXISTS branches;

CREATE TABLE IF NOT EXISTS branches (
    branch_id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    branch_name VARCHAR(100) NOT NULL,
    district VARCHAR(100) NOT NULL,
    phone VARCHAR(30),
    email VARCHAR(150),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    UNIQUE KEY uq_branch_name_district (branch_name, district)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS users (
    user_id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    full_name VARCHAR(150) NOT NULL,
    username VARCHAR(60) NOT NULL,
    email VARCHAR(150),
    password_hash VARCHAR(255) NOT NULL,
    role ENUM('ADMIN','CUSTOMER','MANAGER') NOT NULL,
    status ENUM('ACTIVE','PENDING','SUSPENDED') NOT NULL DEFAULT 'ACTIVE',
    last_login_at DATETIME NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    UNIQUE KEY uq_users_username (username),
    UNIQUE KEY uq_users_email (email)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS customers (
    customer_id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    account_number VARCHAR(30) NOT NULL,
    user_id BIGINT UNSIGNED NULL,
    branch_id BIGINT UNSIGNED NOT NULL,
    full_name VARCHAR(150) NOT NULL,
    national_id VARCHAR(50),
    phone VARCHAR(30),
    email VARCHAR(150),
    address_line VARCHAR(255) NOT NULL,
    district VARCHAR(100) NOT NULL,
    service_type ENUM('DOMESTIC','COMMERCIAL','INDUSTRIAL') NOT NULL DEFAULT 'DOMESTIC',
    meter_number VARCHAR(50),
    connection_date DATE,
    account_status ENUM('ACTIVE','INACTIVE','PENDING','FLAGGED') NOT NULL DEFAULT 'ACTIVE',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    UNIQUE KEY uq_customers_account_number (account_number),
    UNIQUE KEY uq_customers_meter_number (meter_number),
    CONSTRAINT fk_customers_user FOREIGN KEY (user_id) REFERENCES users(user_id)
        ON DELETE SET NULL ON UPDATE CASCADE,
    CONSTRAINT fk_customers_branch FOREIGN KEY (branch_id) REFERENCES branches(branch_id)
        ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS billing_rates (
    rate_id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    service_type ENUM('DOMESTIC','COMMERCIAL','INDUSTRIAL') NOT NULL,
    rate_tier VARCHAR(100) NOT NULL,
    min_units DECIMAL(10,2) NOT NULL,
    max_units DECIMAL(10,2) NULL,
    cost_per_unit DECIMAL(10,2) NOT NULL,
    fixed_charge DECIMAL(10,2) NOT NULL DEFAULT 0.00,
    effective_from DATE NOT NULL,
    effective_to DATE NULL,
    status ENUM('ACTIVE','INACTIVE') NOT NULL DEFAULT 'ACTIVE',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    CHECK (min_units >= 0),
    CHECK (max_units IS NULL OR max_units >= min_units)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS water_usage (
    usage_id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    customer_id BIGINT UNSIGNED NOT NULL,
    reading_month DATE NOT NULL,
    previous_reading DECIMAL(12,2) NOT NULL DEFAULT 0.00,
    current_reading DECIMAL(12,2) NOT NULL,
    units_consumed DECIMAL(12,2) NOT NULL,
    recorded_by BIGINT UNSIGNED NULL,
    recorded_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    notes VARCHAR(255),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    UNIQUE KEY uq_water_usage_customer_month (customer_id, reading_month),
    CONSTRAINT fk_usage_customer FOREIGN KEY (customer_id) REFERENCES customers(customer_id)
        ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT fk_usage_user FOREIGN KEY (recorded_by) REFERENCES users(user_id)
        ON DELETE SET NULL ON UPDATE CASCADE,
    CHECK (current_reading >= previous_reading),
    CHECK (units_consumed >= 0)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS bills (
    bill_id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    bill_number VARCHAR(30) NOT NULL,
    customer_id BIGINT UNSIGNED NOT NULL,
    usage_id BIGINT UNSIGNED NULL,
    billing_month DATE NOT NULL,
    due_date DATE NOT NULL,
    subtotal_amount DECIMAL(12,2) NOT NULL DEFAULT 0.00,
    fixed_charge DECIMAL(12,2) NOT NULL DEFAULT 0.00,
    tax_amount DECIMAL(12,2) NOT NULL DEFAULT 0.00,
    total_amount DECIMAL(12,2) NOT NULL DEFAULT 0.00,
    payment_status ENUM('PENDING','PARTIAL','PAID','OVERDUE','CANCELLED') NOT NULL DEFAULT 'PENDING',
    generated_by BIGINT UNSIGNED NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    UNIQUE KEY uq_bills_bill_number (bill_number),
    UNIQUE KEY uq_bills_customer_month (customer_id, billing_month),
    CONSTRAINT fk_bills_customer FOREIGN KEY (customer_id) REFERENCES customers(customer_id)
        ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT fk_bills_usage FOREIGN KEY (usage_id) REFERENCES water_usage(usage_id)
        ON DELETE SET NULL ON UPDATE CASCADE,
    CONSTRAINT fk_bills_user FOREIGN KEY (generated_by) REFERENCES users(user_id)
        ON DELETE SET NULL ON UPDATE CASCADE,
    CHECK (subtotal_amount >= 0 AND fixed_charge >= 0 AND tax_amount >= 0 AND total_amount >= 0)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS payments (
    payment_id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    bill_id BIGINT UNSIGNED NOT NULL,
    customer_id BIGINT UNSIGNED NOT NULL,
    receipt_number VARCHAR(40) NOT NULL,
    amount_paid DECIMAL(12,2) NOT NULL,
    payment_method ENUM('CASH','CARD','BANK_TRANSFER','MOBILE_MONEY','ONLINE_GATEWAY') NOT NULL,
    payment_reference VARCHAR(100),
    payment_date DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    payment_status ENUM('SUCCESS','PENDING','FAILED','PARTIAL') NOT NULL DEFAULT 'SUCCESS',
    recorded_by BIGINT UNSIGNED NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    UNIQUE KEY uq_payments_receipt_number (receipt_number),
    CONSTRAINT fk_payments_bill FOREIGN KEY (bill_id) REFERENCES bills(bill_id)
        ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT fk_payments_customer FOREIGN KEY (customer_id) REFERENCES customers(customer_id)
        ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT fk_payments_user FOREIGN KEY (recorded_by) REFERENCES users(user_id)
        ON DELETE SET NULL ON UPDATE CASCADE,
    CHECK (amount_paid >= 0)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS notifications (
    notification_id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    customer_id BIGINT UNSIGNED NOT NULL,
    bill_id BIGINT UNSIGNED NULL,
    notification_type ENUM('BILL_REMINDER','PAYMENT_CONFIRMATION','USAGE_ALERT','SERVICE_NOTICE') NOT NULL,
    channel ENUM('SMS','EMAIL','SYSTEM') NOT NULL DEFAULT 'SYSTEM',
    subject VARCHAR(150),
    message TEXT NOT NULL,
    sent_status ENUM('PENDING','SENT','FAILED','READ') NOT NULL DEFAULT 'PENDING',
    sent_at DATETIME NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    CONSTRAINT fk_notifications_customer FOREIGN KEY (customer_id) REFERENCES customers(customer_id)
        ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT fk_notifications_bill FOREIGN KEY (bill_id) REFERENCES bills(bill_id)
        ON DELETE SET NULL ON UPDATE CASCADE
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS leakage_reports (
    leakage_id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    customer_id BIGINT UNSIGNED NULL,
    district VARCHAR(100) NOT NULL,
    location_description VARCHAR(255) NOT NULL,
    report_description TEXT NOT NULL,
    priority ENUM('LOW','MEDIUM','HIGH') NOT NULL DEFAULT 'MEDIUM',
    report_status ENUM('OPEN','IN_PROGRESS','RESOLVED','CLOSED') NOT NULL DEFAULT 'OPEN',
    reported_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    resolved_at DATETIME NULL,
    assigned_branch_id BIGINT UNSIGNED NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    CONSTRAINT fk_leakage_customer FOREIGN KEY (customer_id) REFERENCES customers(customer_id)
        ON DELETE SET NULL ON UPDATE CASCADE,
    CONSTRAINT fk_leakage_branch FOREIGN KEY (assigned_branch_id) REFERENCES branches(branch_id)
        ON DELETE SET NULL ON UPDATE CASCADE
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS sync_log (
    sync_id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    table_name VARCHAR(100) NOT NULL,
    record_id BIGINT NULL,
    operation_type ENUM('INSERT','UPDATE','DELETE') NOT NULL,
    source_db VARCHAR(30) NOT NULL,
    target_db VARCHAR(30) NOT NULL,
    sync_status ENUM('PENDING','SUCCESS','FAILED') NOT NULL DEFAULT 'PENDING',
    sync_message VARCHAR(255),
    synced_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB;
