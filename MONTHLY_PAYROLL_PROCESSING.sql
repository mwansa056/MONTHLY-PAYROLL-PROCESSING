
CREATE TABLE employees (
    employee_id SERIAL PRIMARY KEY,
    full_name VARCHAR(100) NOT NULL,
    basic_salary NUMERIC(10,2) NOT NULL CHECK (basic_salary >= 0),
    allowance NUMERIC(10,2) NOT NULL CHECK (allowance >= 0),
    deduction NUMERIC(10,2) NOT NULL CHECK (deduction >= 0),
    active BOOLEAN NOT NULL
);

CREATE TABLE payroll (
    payroll_id SERIAL PRIMARY KEY,
    employee_id INTEGER NOT NULL REFERENCES employees(employee_id),
    pay_month DATE NOT NULL,
    gross_pay NUMERIC(12,2) NOT NULL,
    net_pay NUMERIC(12,2) NOT NULL,
    UNIQUE (employee_id, pay_month),
    CHECK (pay_month = date_trunc('month', pay_month)::date)
);

CREATE TABLE salary_audit (
    audit_id SERIAL PRIMARY KEY,
    employee_id INTEGER NOT NULL REFERENCES employees(employee_id),
    old_salary NUMERIC(10,2) NOT NULL,
    new_salary NUMERIC(10,2) NOT NULL,
    changed_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

INSERT INTO employees (
    full_name, basic_salary, allowance, deduction, active
)
VALUES
    ('John Banda', 5000.00, 800.00, 300.00, TRUE),
    ('Mary Phiri', 6500.00, 1000.00, 500.00, TRUE),
    ('Peter Zulu', 4000.00, 500.00, 200.00, FALSE);


CREATE OR REPLACE FUNCTION fn_net_pay(
    p_employee_id INTEGER
)
RETURNS NUMERIC(12,2)
LANGUAGE plpgsql
AS $$
DECLARE
    v_basic NUMERIC(10,2);
    v_allowance NUMERIC(10,2);
    v_deduction NUMERIC(10,2);
    v_net NUMERIC(12,2);
BEGIN
    SELECT basic_salary, allowance, deduction
    INTO v_basic, v_allowance, v_deduction
    FROM employees
    WHERE employee_id = p_employee_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Unknown employee';
    END IF;

    v_net := v_basic + v_allowance - v_deduction;

    IF v_net < 0 THEN
        RAISE EXCEPTION 'Computed net pay cannot be negative';
    END IF;

    RETURN v_net;
END;
$$;


CREATE OR REPLACE PROCEDURE pr_process_payroll(
    p_month DATE
)
LANGUAGE plpgsql
AS $$
DECLARE
    emp RECORD;
    v_gross NUMERIC(12,2);
    v_net NUMERIC(12,2);
BEGIN
    IF p_month IS NULL
       OR p_month <> date_trunc('month', p_month)::date
    THEN
        RAISE EXCEPTION 'Pay month must be the first day of a month';
    END IF;

    FOR emp IN
        SELECT employee_id, basic_salary, allowance
        FROM employees
        WHERE active = TRUE
    LOOP
        v_gross := emp.basic_salary + emp.allowance;
        v_net := fn_net_pay(emp.employee_id);

        INSERT INTO payroll (
            employee_id, pay_month, gross_pay, net_pay
        )
        VALUES (
            emp.employee_id, p_month, v_gross, v_net
        )
        ON CONFLICT (employee_id, pay_month)
        DO NOTHING;
    END LOOP;
END;
$$;

CALL pr_process_payroll(DATE '2026-10-01');
CALL pr_process_payroll(DATE '2026-11-01');


CREATE OR REPLACE FUNCTION fn_salary_audit()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    IF OLD.basic_salary IS DISTINCT FROM NEW.basic_salary THEN
        INSERT INTO salary_audit (
            employee_id,
            old_salary,
            new_salary,
            changed_at
        )
        VALUES (
            NEW.employee_id,
            OLD.basic_salary,
            NEW.basic_salary,
            CURRENT_TIMESTAMP
        );
    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_salary_audit
AFTER UPDATE ON employees
FOR EACH ROW
EXECUTE FUNCTION fn_salary_audit();


CREATE OR REPLACE VIEW v_payroll_report AS
SELECT
    e.full_name,
    p.pay_month,
    p.gross_pay,
    p.net_pay
FROM payroll p
JOIN employees e
    ON p.employee_id = e.employee_id;

SELECT * FROM v_payroll_report;


CREATE INDEX idx_payroll_pay_month
ON payroll (pay_month);

EXPLAIN
SELECT *
FROM payroll
WHERE pay_month = DATE '2026-11-01';


CALL pr_process_payroll(
    (date_trunc('month', CURRENT_DATE) - INTERVAL '1 month')::DATE
);

SELECT *
FROM pgagent.pga_job;

SELECT *
FROM pgagent.pga_joblog
ORDER BY jlgstart DESC;
