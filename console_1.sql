BEGIN;
DELETE FROM products WHERE shop = 'Joe''s Shop';
INSERT INTO products (shop, product, price) VALUES ('Joe''s Shop', 'Fanta', 3.50);
COMMIT;

-- 3.5
BEGIN;
INSERT INTO products (shop, product, price) VALUES ('Joe''s Shop', 'Sprite', 4.00);
COMMIT;

-- 3.7


BEGIN;
UPDATE products SET price = 99.99
 WHERE product = 'Fanta';
-- Wait here (don't commit yet)
-- Then:
ROLLBACK;

--1
-- Alternative with error:
BEGIN;
UPDATE accounts SET balance = balance - 200.00
WHERE name = 'Bob' AND balance >= 200.00;
-- Check if update happened
IF NOT EXISTS (SELECT 1 FROM accounts WHERE name = 'Bob' AND balance >= 0) THEN
    ROLLBACK;
    RAISE NOTICE 'Insufficient funds';
ELSE
    UPDATE accounts SET balance = balance + 200.00 WHERE name = 'Wally';
    COMMIT;
END IF;


--3
-- (simultaneous):
BEGIN;
SELECT balance FROM accounts WHERE name = 'Alice';
-- Also sees 1000
UPDATE accounts SET balance = balance - 200 WHERE name = 'Alice';
-- This might wait or fail depending on isolation level