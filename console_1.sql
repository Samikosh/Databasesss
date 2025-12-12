-- ЗАДАНИЕ 1: СОЗДАНИЕ ТАБЛИЦ
CREATE TABLE customers (
    customer_id SERIAL PRIMARY KEY,
    iin VARCHAR(12) UNIQUE NOT NULL CHECK (iin ~ '^\d{12}$'),
    full_name VARCHAR(100) NOT NULL,
    phone VARCHAR(20),
    email VARCHAR(100),
    status VARCHAR(10) DEFAULT 'active' CHECK (status IN ('active', 'blocked', 'frozen')),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    daily_limit_kzt DECIMAL(15,2) DEFAULT 1000000.00
);

CREATE TABLE accounts (
    account_id SERIAL PRIMARY KEY,
    customer_id INTEGER NOT NULL REFERENCES customers(customer_id),
    account_number VARCHAR(34) UNIQUE NOT NULL CHECK (account_number ~ '^KZ\d{2}[A-Z]{4}\d{20}$'),
    currency VARCHAR(3) CHECK (currency IN ('KZT', 'USD', 'EUR', 'RUB')),
    balance DECIMAL(20,2) DEFAULT 0.00,
    is_active BOOLEAN DEFAULT TRUE,
    opened_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    closed_at TIMESTAMP
);

CREATE TABLE exchange_rates (
    rate_id SERIAL PRIMARY KEY,
    from_currency VARCHAR(3) NOT NULL,
    to_currency VARCHAR(3) NOT NULL,
    rate DECIMAL(10,6) NOT NULL,
    valid_from TIMESTAMP NOT NULL,
    valid_to TIMESTAMP
);

CREATE TABLE transactions (
    transaction_id SERIAL PRIMARY KEY,
    from_account_id INTEGER REFERENCES accounts(account_id),
    to_account_id INTEGER REFERENCES accounts(account_id),
    amount DECIMAL(20,2) NOT NULL,
    currency VARCHAR(3),
    exchange_rate DECIMAL(10,6) DEFAULT 1.0,
    amount_kzt DECIMAL(20,2) NOT NULL,
    type VARCHAR(20) CHECK (type IN ('transfer', 'deposit', 'withdrawal')),
    status VARCHAR(20) CHECK (status IN ('pending', 'completed', 'failed', 'reversed')),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    completed_at TIMESTAMP,
    description TEXT
);

CREATE TABLE audit_log (
    log_id SERIAL PRIMARY KEY,
    table_name VARCHAR(50) NOT NULL,
    record_id INTEGER NOT NULL,
    action VARCHAR(10) CHECK (action IN ('INSERT', 'UPDATE', 'DELETE')),
    old_values JSONB,
    new_values JSONB,
    changed_by VARCHAR(100) DEFAULT current_user,
    changed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    ip_address INET
);

INSERT INTO customers (iin, full_name, phone, email, status, daily_limit_kzt) VALUES
('850725300456', 'Shaldarbek Dauren', '+77471234567', 'dauren@example.com', 'active', 5000000.00),
('920518400321', 'Jeon Jungkook', '+77781234568', 'jungkook@example.com', 'active', 8000000.00),
('780330500789', 'Kim Namjoon', '+77021234569', 'namjoon@example.com', 'active', 6000000.00),
('950611600123', 'Urmanova Samira', '+77751234570', 'samira@example.com', 'blocked', 2000000.00),
('880902700456', 'Seitkamal Iliyas', '+77051234571', 'iliyas@example.com', 'active', 4000000.00),
('910407800789', 'Park Jimin', '+77451234572', 'jimin@example.com', 'active', 7000000.00),
('860129900012', 'Min Yoongi', '+77721234573', 'yoongi@example.com', 'frozen', 3000000.00),
('930704100345', 'Kim Taehyun', '+77081234574', 'taehyun@example.com', 'active', 5500000.00),
('890815200678', 'Jeon Hoseok', '+77701234575', 'hoseok@example.com', 'active', 4500000.00),
('940226300901', 'Kim Seokjin', '+77481234576', 'seokjin@example.com', 'active', 9000000.00);

INSERT INTO exchange_rates (from_currency, to_currency, rate, valid_from) VALUES
('USD', 'KZT', 447.50, '2024-01-01'),
('EUR', 'KZT', 488.30, '2024-01-01'),
('RUB', 'KZT', 4.85, '2024-01-01');

INSERT INTO accounts (customer_id, account_number, currency, balance) VALUES
(1, 'KZ12345678901234567890', 'KZT', 2500000.00),
(2, 'KZ09876543210987654321', 'USD', 15000.00),
(3, 'KZ11223344556677889900', 'KZT', 1800000.00),
(4, 'KZ22334455667788990011', 'EUR', 8000.00),
(5, 'KZ33445566778899001122', 'KZT', 1200000.00),
(6, 'KZ44556677889900112233', 'USD', 12000.00),
(7, 'KZ55667788990011223344', 'KZT', 900000.00),
(8, 'KZ66778899001122334455', 'KZT', 2200000.00),
(9, 'KZ77889900112233445566', 'KZT', 1600000.00),
(10, 'KZ88990011223344556677', 'KZT', 3500000.00);

INSERT INTO transactions (from_account_id, to_account_id, amount, currency, amount_kzt, type, status) VALUES
(1, 3, 100000.00, 'KZT', 100000.00, 'transfer', 'completed'),
(2, 4, 2000.00, 'USD', 895000.00, 'transfer', 'completed'),
(NULL, 5, 500000.00, 'KZT', 500000.00, 'deposit', 'completed'),
(6, NULL, 150000.00, 'KZT', 150000.00, 'withdrawal', 'completed'),
(7, 8, 300000.00, 'KZT', 300000.00, 'transfer', 'completed'),
(9, 10, 250000.00, 'KZT', 250000.00, 'transfer', 'completed');

-- ЗАДАНИЕ 2: ПРОЦЕДУРА ПЕРЕВОДА
CREATE OR REPLACE FUNCTION process_transfer(
    from_acc VARCHAR(34),
    to_acc VARCHAR(34),
    trans_amount DECIMAL(20,2),
    trans_currency VARCHAR(3),
    trans_desc TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
AS $$
DECLARE
    from_id INTEGER;
    to_id INTEGER;
    from_cust_id INTEGER;
    from_curr VARCHAR(3);
    from_bal DECIMAL(20,2);
    cust_status VARCHAR(10);
    daily_limit DECIMAL(15,2);
    today_total DECIMAL(20,2);
    conv_rate DECIMAL(10,6);
    kzt_amount DECIMAL(20,2);
    trans_id INTEGER;
BEGIN
    BEGIN
        SELECT a.account_id, a.customer_id, a.currency, a.balance, c.status, c.daily_limit_kzt
        INTO from_id, from_cust_id, from_curr, from_bal, cust_status, daily_limit
        FROM accounts a
        JOIN customers c ON a.customer_id = c.customer_id
        WHERE a.account_number = from_acc
        AND a.is_active = TRUE
        FOR UPDATE;

        IF NOT FOUND THEN
            INSERT INTO audit_log (table_name, record_id, action, new_values)
            VALUES ('transactions', 0, 'INSERT', jsonb_build_object('error', 'TR01'));
            RETURN jsonb_build_object('success', false, 'error', 'TR01');
        END IF;

        IF cust_status != 'active' THEN
            INSERT INTO audit_log (table_name, record_id, action, new_values)
            VALUES ('transactions', 0, 'INSERT', jsonb_build_object('error', 'TR02'));
            RETURN jsonb_build_object('success', false, 'error', 'TR02');
        END IF;

        SELECT account_id INTO to_id
        FROM accounts
        WHERE account_number = to_acc
        AND is_active = TRUE
        FOR UPDATE;

        IF NOT FOUND THEN
            INSERT INTO audit_log (table_name, record_id, action, new_values)
            VALUES ('transactions', 0, 'INSERT', jsonb_build_object('error', 'TR03'));
            RETURN jsonb_build_object('success', false, 'error', 'TR03');
        END IF;

        IF from_bal < trans_amount THEN
            INSERT INTO audit_log (table_name, record_id, action, new_values)
            VALUES ('transactions', 0, 'INSERT', jsonb_build_object('error', 'TR04'));
            RETURN jsonb_build_object('success', false, 'error', 'TR04');
        END IF;

        IF trans_currency = 'KZT' THEN
            kzt_amount := trans_amount;
        ELSE
            SELECT rate INTO conv_rate
            FROM exchange_rates
            WHERE from_currency = trans_currency AND to_currency = 'KZT'
            LIMIT 1;
            kzt_amount := trans_amount * conv_rate;
        END IF;

        SELECT COALESCE(SUM(amount_kzt), 0) INTO today_total
        FROM transactions
        WHERE from_account_id = from_id
        AND status = 'completed'
        AND created_at::DATE = CURRENT_DATE;

        IF (today_total + kzt_amount) > daily_limit THEN
            INSERT INTO audit_log (table_name, record_id, action, new_values)
            VALUES ('transactions', 0, 'INSERT', jsonb_build_object('error', 'TR05'));
            RETURN jsonb_build_object('success', false, 'error', 'TR05');
        END IF;

        SAVEPOINT transfer_sp;

        BEGIN
            INSERT INTO transactions (from_account_id, to_account_id, amount, currency,
                                     amount_kzt, type, status, description)
            VALUES (from_id, to_id, trans_amount, trans_currency, kzt_amount,
                   'transfer', 'pending', trans_desc)
            RETURNING transaction_id INTO trans_id;

            UPDATE accounts SET balance = balance - trans_amount WHERE account_id = from_id;
            UPDATE accounts SET balance = balance + trans_amount WHERE account_id = to_id;

            UPDATE transactions SET status = 'completed', completed_at = CURRENT_TIMESTAMP
            WHERE transaction_id = trans_id;

            RELEASE SAVEPOINT transfer_sp;

            INSERT INTO audit_log (table_name, record_id, action, new_values)
            VALUES ('transactions', trans_id, 'INSERT', jsonb_build_object('status', 'completed'));

            RETURN jsonb_build_object('success', true, 'id', trans_id);

        EXCEPTION
            WHEN OTHERS THEN
                ROLLBACK TO SAVEPOINT transfer_sp;
                INSERT INTO audit_log (table_name, record_id, action, new_values)
                VALUES ('transactions', COALESCE(trans_id, 0), 'INSERT', jsonb_build_object('error', SQLERRM));
                RETURN jsonb_build_object('success', false, 'error', SQLERRM);
        END;

    EXCEPTION
        WHEN OTHERS THEN
            INSERT INTO audit_log (table_name, record_id, action, new_values)
            VALUES ('transactions', 0, 'INSERT', jsonb_build_object('error', SQLERRM));
            RETURN jsonb_build_object('success', false, 'error', SQLERRM);
    END;
END;
$$;

-- ЗАДАНИЕ 3: ПРЕДСТАВЛЕНИЯ
CREATE OR REPLACE VIEW customer_balance_summary AS
WITH customer_data AS (
    SELECT
        c.customer_id,
        c.full_name,
        c.daily_limit_kzt,
        a.currency,
        a.balance,
        CASE a.currency
            WHEN 'KZT' THEN a.balance
            WHEN 'USD' THEN a.balance * 447.50
            WHEN 'EUR' THEN a.balance * 488.30
            WHEN 'RUB' THEN a.balance * 4.85
            ELSE 0
        END AS balance_kzt
    FROM customers c
    JOIN accounts a ON c.customer_id = a.customer_id
    WHERE a.is_active = TRUE
)
SELECT
    customer_id,
    full_name,
    COUNT(*) AS accounts,
    SUM(balance) AS total_balance,
    SUM(balance_kzt) AS total_kzt,
    daily_limit_kzt,
    ROUND((
        COALESCE((
            SELECT SUM(amount_kzt)
            FROM transactions t
            JOIN accounts a ON t.from_account_id = a.account_id
            WHERE a.customer_id = cd.customer_id
            AND t.status = 'completed'
            AND t.created_at::DATE = CURRENT_DATE
        ), 0) / daily_limit_kzt * 100
    ), 2) AS limit_percent,
    RANK() OVER (ORDER BY SUM(balance_kzt) DESC) AS rank
FROM customer_data cd
GROUP BY customer_id, full_name, daily_limit_kzt;

CREATE OR REPLACE VIEW daily_transaction_report AS
WITH daily_stats AS (
    SELECT
        DATE(created_at) AS trans_date,
        type,
        COUNT(*) AS count,
        SUM(amount_kzt) AS volume,
        AVG(amount_kzt) AS average
    FROM transactions
    WHERE status = 'completed'
    GROUP BY DATE(created_at), type
)
SELECT
    trans_date,
    type,
    count,
    volume,
    average,
    SUM(volume) OVER (PARTITION BY type ORDER BY trans_date) AS cumulative,
    LAG(volume) OVER (PARTITION BY type ORDER BY trans_date) AS prev_day,
    CASE
        WHEN LAG(volume) OVER (PARTITION BY type ORDER BY trans_date) > 0
        THEN ROUND(((volume - LAG(volume) OVER (PARTITION BY type ORDER BY trans_date)) /
             LAG(volume) OVER (PARTITION BY type ORDER BY trans_date) * 100), 2)
        ELSE NULL
    END AS growth
FROM daily_stats
ORDER BY trans_date DESC, type;

CREATE OR REPLACE VIEW suspicious_activity_view WITH (security_barrier = true) AS
SELECT
    c.customer_id,
    c.full_name,
    c.iin,
    sa.activity_type,
    sa.details,
    CURRENT_TIMESTAMP AS detected
FROM (
    SELECT
        a.customer_id,
        'LARGE_TRANSFER' AS activity_type,
        jsonb_build_object('amount', t.amount_kzt) AS details
    FROM transactions t
    JOIN accounts a ON t.from_account_id = a.account_id
    WHERE t.amount_kzt > 5000000

    UNION ALL

    SELECT
        a.customer_id,
        'FREQUENT' AS activity_type,
        jsonb_build_object('count', COUNT(*)) AS details
    FROM transactions t
    JOIN accounts a ON t.from_account_id = a.account_id
    GROUP BY a.customer_id, DATE_TRUNC('hour', t.created_at)
    HAVING COUNT(*) > 10

    UNION ALL

    SELECT
        a.customer_id,
        'RAPID' AS activity_type,
        jsonb_build_object('diff', EXTRACT(SECOND FROM (t2.created_at - t1.created_at))) AS details
    FROM transactions t1
    JOIN transactions t2 ON t1.from_account_id = t2.from_account_id
    JOIN accounts a ON t1.from_account_id = a.account_id
    WHERE t1.transaction_id < t2.transaction_id
    AND t2.created_at - t1.created_at < INTERVAL '1 minute'
    AND t1.type = 'transfer'
    AND t2.type = 'transfer'
) sa
JOIN customers c ON sa.customer_id = c.customer_id
WHERE c.status = 'active';

-- ЗАДАНИЕ 4: ИНДЕКСЫ
CREATE INDEX idx_acc_number ON accounts(account_number);
CREATE INDEX idx_trans_acc_date ON transactions(from_account_id, created_at DESC);
CREATE INDEX idx_active_acc ON accounts(account_id) WHERE is_active = TRUE;
CREATE INDEX idx_email_lower ON customers(LOWER(email));
CREATE INDEX idx_audit_json ON audit_log USING GIN(new_values);
CREATE INDEX idx_daily_check ON transactions(from_account_id, status, created_at, amount_kzt);
CREATE INDEX idx_cust_status ON customers USING HASH(status);

-- ЗАДАНИЕ 5: ПАКЕТНАЯ ОБРАБОТКА
CREATE OR REPLACE FUNCTION process_salary_batch(
    company_account VARCHAR(34),
    payments JSONB
)
RETURNS JSONB
LANGUAGE plpgsql
AS $$
DECLARE
    comp_id INTEGER;
    comp_balance DECIMAL(20,2);
    total_amount DECIMAL(20,2) := 0;
    success_count INTEGER := 0;
    fail_count INTEGER := 0;
    fail_details JSONB := '[]'::JSONB;
    payment JSONB;
    result JSONB;
    lock_key BIGINT;
BEGIN
    lock_key := ABS(HASHTEXT(company_account)) % 2147483647;

    IF NOT PG_TRY_ADVISORY_LOCK(lock_key) THEN
        RETURN jsonb_build_object('success', false, 'error', 'BATCH_LOCKED');
    END IF;

    BEGIN
        SELECT account_id, balance INTO comp_id, comp_balance
        FROM accounts WHERE account_number = company_account AND is_active = TRUE;

        IF comp_id IS NULL THEN
            RAISE EXCEPTION 'COMPANY_NOT_FOUND';
        END IF;

        FOR i IN 0..JSONB_ARRAY_LENGTH(payments) - 1 LOOP
            payment := payments -> i;
            total_amount := total_amount + (payment ->> 'amount')::DECIMAL;
        END LOOP;

        IF total_amount > comp_balance THEN
            RAISE EXCEPTION 'INSUFFICIENT_FUNDS';
        END IF;

        FOR i IN 0..JSONB_ARRAY_LENGTH(payments) - 1 LOOP
            BEGIN
                SAVEPOINT salary_sp;
                payment := payments -> i;

                DECLARE
                    emp_account VARCHAR(34);
                    emp_iin VARCHAR(12);
                    salary DECIMAL(20,2);
                BEGIN
                    emp_iin := payment ->> 'iin';
                    salary := (payment ->> 'amount')::DECIMAL;

                    SELECT account_number INTO emp_account
                    FROM accounts a
                    JOIN customers c ON a.customer_id = c.customer_id
                    WHERE c.iin = emp_iin AND a.is_active = TRUE
                    LIMIT 1;

                    IF emp_account IS NULL THEN
                        RAISE EXCEPTION 'EMPLOYEE_NOT_FOUND';
                    END IF;

                    UPDATE customers
                    SET daily_limit_kzt = daily_limit_kzt + 10000000
                    WHERE customer_id = (SELECT customer_id FROM accounts WHERE account_id = comp_id);

                    result := process_transfer(
                        company_account,
                        emp_account,
                        salary,
                        'KZT',
                        COALESCE(payment ->> 'description', 'Salary')
                    );

                    UPDATE customers
                    SET daily_limit_kzt = daily_limit_kzt - 10000000
                    WHERE customer_id = (SELECT customer_id FROM accounts WHERE account_id = comp_id);

                    IF (result ->> 'success')::BOOLEAN THEN
                        success_count := success_count + 1;
                    ELSE
                        RAISE EXCEPTION 'TRANSFER_FAILED';
                    END IF;

                EXCEPTION
                    WHEN OTHERS THEN
                        ROLLBACK TO SAVEPOINT salary_sp;
                        fail_count := fail_count + 1;
                        fail_details := fail_details || jsonb_build_object(
                            'iin', emp_iin,
                            'amount', salary,
                            'error', SQLERRM
                        );
                        CONTINUE;
                END;

                RELEASE SAVEPOINT salary_sp;

            END;
        END LOOP;

        UPDATE accounts SET balance = balance - total_amount WHERE account_id = comp_id;

        INSERT INTO audit_log (table_name, record_id, action, new_values)
        VALUES ('batch', comp_id, 'INSERT',
                jsonb_build_object(
                    'company', company_account,
                    'total', total_amount,
                    'success', success_count,
                    'failed', fail_count,
                    'details', fail_details
                ));

        PERFORM PG_ADVISORY_UNLOCK(lock_key);

        RETURN jsonb_build_object(
            'success', true,
            'total', total_amount,
            'successful', success_count,
            'failed', fail_count,
            'details', fail_details
        );

    EXCEPTION
        WHEN OTHERS THEN
            PERFORM PG_ADVISORY_UNLOCK(lock_key);
            RAISE;
    END;
END;
$$;

CREATE MATERIALIZED VIEW salary_reports AS
SELECT
    DATE(changed_at) AS report_date,
    (new_values ->> 'company') AS company,
    (new_values ->> 'total')::DECIMAL AS total,
    (new_values ->> 'success')::INTEGER AS success,
    (new_values ->> 'failed')::INTEGER AS failed
FROM audit_log
WHERE table_name = 'batch'
ORDER BY changed_at DESC;

CREATE INDEX idx_report_date ON salary_reports(report_date DESC);

-- ТЕСТОВЫЕ ЗАПРОСЫ
SELECT process_transfer('KZ12345678901234567890', 'KZ11223344556677889900', 50000, 'KZT', 'Test transfer');
SELECT process_salary_batch('KZ12345678901234567890',
    '[{"iin": "920518400321", "amount": 250000}, {"iin": "780330500789", "amount": 300000}]'::JSONB);