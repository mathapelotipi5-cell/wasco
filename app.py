import os
from functools import wraps
from decimal import Decimal
from datetime import date, datetime

from flask import Flask, render_template, request, redirect, url_for, flash, session, abort
from werkzeug.security import check_password_hash, generate_password_hash
import psycopg2
from psycopg2.extras import RealDictCursor
import pymysql


def create_app() -> Flask:
    app = Flask(__name__)
    app.config['SECRET_KEY'] = os.getenv('SECRET_KEY', 'wasco-dev-secret-key')

    class DBConfig:
        MYSQL_HOST = os.getenv('MYSQL_HOST', 'localhost')
        MYSQL_PORT = int(os.getenv('MYSQL_PORT', '3306'))
        MYSQL_USER = os.getenv('MYSQL_USER', 'root')
        MYSQL_PASSWORD = os.getenv('MYSQL_PASSWORD', '123456')
        MYSQL_DATABASE = os.getenv('MYSQL_DATABASE', 'wasco_database')

        POSTGRES_HOST = os.getenv('POSTGRES_HOST', 'localhost')
        POSTGRES_PORT = int(os.getenv('POSTGRES_PORT', '5432'))
        POSTGRES_USER = os.getenv('POSTGRES_USER', 'postgres')
        POSTGRES_PASSWORD = os.getenv('POSTGRES_PASSWORD', '12345')
        POSTGRES_DATABASE = os.getenv('POSTGRES_DATABASE', 'wasco_water_billing')

    class DBService:
        def __init__(self, cfg: DBConfig):
            self.cfg = cfg

        def pg_conn(self):
            return psycopg2.connect(
                host=self.cfg.POSTGRES_HOST,
                port=self.cfg.POSTGRES_PORT,
                user=self.cfg.POSTGRES_USER,
                password=self.cfg.POSTGRES_PASSWORD,
                dbname=self.cfg.POSTGRES_DATABASE,
                cursor_factory=RealDictCursor,
            )

        def my_conn(self):
            return pymysql.connect(
                host=self.cfg.MYSQL_HOST,
                port=self.cfg.MYSQL_PORT,
                user=self.cfg.MYSQL_USER,
                password=self.cfg.MYSQL_PASSWORD,
                database=self.cfg.MYSQL_DATABASE,
                cursorclass=pymysql.cursors.DictCursor,
                autocommit=False,
            )

        def fetch_all(self, sql: str, params=None):
            with self.pg_conn() as conn:
                with conn.cursor() as cur:
                    cur.execute(sql, params or [])
                    return cur.fetchall()

        def fetch_one(self, sql: str, params=None):
            rows = self.fetch_all(sql, params)
            return rows[0] if rows else None

        def execute_pg(self, sql: str, params=None, fetchone=False):
            with self.pg_conn() as conn:
                with conn.cursor() as cur:
                    cur.execute(sql, params or [])
                    result = cur.fetchone() if fetchone else None
                conn.commit()
            return result

        def execute_my(self, sql: str, params=None):
            try:
                conn = self.my_conn()
                with conn.cursor() as cur:
                    cur.execute(sql, params or [])
                conn.commit()
                conn.close()
            except Exception:
                return False
            return True

        def mirror_insert_sync_log(self, table_name: str, record_id, operation: str, message: str, ok: bool = True):
            pg_sql = """
                INSERT INTO sync_log (table_name, record_id, operation_type, source_db, target_db, sync_status, sync_message)
                VALUES (%s, %s, %s, %s, %s, %s, %s)
            """
            my_sql = """
                INSERT INTO sync_log (table_name, record_id, operation_type, source_db, target_db, sync_status, sync_message)
                VALUES (%s, %s, %s, %s, %s, %s, %s)
            """
            status = 'SUCCESS' if ok else 'FAILED'
            params = (table_name, record_id, operation, 'POSTGRESQL', 'MYSQL', status, message)
            self.execute_pg(pg_sql, params)
            self.execute_my(my_sql, params)

        def ping(self):
            mysql_ok = False
            pg_ok = False

            try:
                with self.pg_conn() as conn:
                    with conn.cursor() as cur:
                        cur.execute('SELECT 1')
                        cur.fetchone()
                        pg_ok = True
            except Exception:
                pg_ok = False

            try:
                conn = self.my_conn()
                with conn.cursor() as cur:
                    cur.execute('SELECT 1')
                    cur.fetchone()
                conn.close()
                mysql_ok = True
            except Exception:
                mysql_ok = False

            return {'postgres': pg_ok, 'mysql': mysql_ok}

        def authenticate(self, username: str, password: str):
            user = self.fetch_one(
                """
                SELECT u.user_id, u.full_name, u.username, u.email, u.password_hash, u.role, u.status,
                       c.customer_id, c.account_number, c.branch_id
                FROM users u
                LEFT JOIN customers c ON c.user_id = u.user_id
                WHERE u.username = %s OR u.email = %s OR c.account_number = %s
                """,
                [username, username, username],
            )
            if not user:
                return None

            stored = user['password_hash']
            valid = stored == password
            if not valid:
                try:
                    valid = check_password_hash(stored, password)
                except Exception:
                    valid = False

            if not valid:
                return None

            self.execute_pg(
                'UPDATE users SET last_login_at = CURRENT_TIMESTAMP WHERE user_id = %s',
                [user['user_id']]
            )
            return user

        def get_admin_summary(self):
            return {
                'registered_customers': self.fetch_one('SELECT COUNT(*) AS count FROM customers')['count'],
                'outstanding_bills': self.fetch_one(
                    "SELECT COALESCE(SUM(total_amount),0) AS total FROM bills WHERE payment_status IN ('PENDING','PARTIAL','OVERDUE')"
                )['total'],
                'today_payments': self.fetch_one(
                    'SELECT COALESCE(SUM(amount_paid),0) AS total FROM payments WHERE DATE(payment_date) = CURRENT_DATE'
                )['total'],
                'open_leak_cases': self.fetch_one(
                    "SELECT COUNT(*) AS count FROM leakage_reports WHERE report_status IN ('OPEN','IN_PROGRESS')"
                )['count'],
            }

        def get_customer_dashboard(self, user_id: int, customer_id: int):
            bills = self.fetch_all(
                """
                SELECT bill_id, bill_number, TO_CHAR(billing_month, 'YYYY-MM') AS billing_month,
                       total_amount, payment_status
                FROM bills
                WHERE customer_id = %s
                ORDER BY billing_month DESC
                LIMIT 12
                """,
                [customer_id],
            )
            payments = self.fetch_all(
                """
                SELECT receipt_number, bill_id, amount_paid, payment_method, payment_date
                FROM payments
                WHERE customer_id = %s
                ORDER BY payment_date DESC
                LIMIT 10
                """,
                [customer_id],
            )
            usage = self.fetch_all(
                """
                SELECT TO_CHAR(reading_month, 'YYYY-MM') AS reading_month, current_reading, units_consumed
                FROM water_usage
                WHERE customer_id = %s
                ORDER BY reading_month DESC
                LIMIT 12
                """,
                [customer_id],
            )
            notifications = self.fetch_all(
                """
                SELECT subject, message, sent_status, created_at
                FROM notifications
                WHERE customer_id = %s
                ORDER BY created_at DESC
                LIMIT 10
                """,
                [customer_id],
            )
            account = self.fetch_one('SELECT * FROM customers WHERE customer_id = %s', [customer_id])
            current_balance = self.fetch_one(
                """
                SELECT COALESCE(SUM(total_amount),0) AS total
                FROM bills
                WHERE customer_id = %s
                AND payment_status IN ('PENDING','PARTIAL','OVERDUE')
                """,
                [customer_id],
            )['total']
            last_payment = self.fetch_one(
                """
                SELECT amount_paid
                FROM payments
                WHERE customer_id = %s
                ORDER BY payment_date DESC
                LIMIT 1
                """,
                [customer_id],
            )
            month_usage = self.fetch_one(
                """
                SELECT COALESCE(SUM(units_consumed),0) AS total
                FROM water_usage
                WHERE customer_id = %s
                AND DATE_TRUNC('month', reading_month) = DATE_TRUNC('month', CURRENT_DATE)
                """,
                [customer_id],
            )['total']
            unread_alerts = self.fetch_one(
                """
                SELECT COUNT(*) AS count
                FROM notifications
                WHERE customer_id = %s
                AND sent_status IN ('PENDING','SENT')
                """,
                [customer_id],
            )['count']

            return {
                'bills': bills,
                'payments': payments,
                'usage': usage,
                'notifications': notifications,
                'account': account,
                'current_balance': current_balance,
                'last_payment': last_payment['amount_paid'] if last_payment else Decimal('0.00'),
                'month_usage': month_usage,
                'unread_alerts': unread_alerts,
            }

        def get_manager_summary(self):
            usage_rows = self.fetch_all(
                """
                SELECT TO_CHAR(reading_month, 'Mon') AS month_label,
                       COALESCE(SUM(units_consumed),0) AS units
                FROM water_usage
                GROUP BY DATE_TRUNC('month', reading_month), TO_CHAR(reading_month, 'Mon')
                ORDER BY DATE_TRUNC('month', reading_month) DESC
                LIMIT 6
                """
            )
            usage_rows.reverse()

            return {
                'daily_usage': self.fetch_one(
                    "SELECT COALESCE(SUM(units_consumed),0) AS total FROM water_usage WHERE reading_month = CURRENT_DATE"
                )['total'],
                'weekly_revenue': self.fetch_one(
                    "SELECT COALESCE(SUM(amount_paid),0) AS total FROM payments WHERE payment_date >= CURRENT_DATE - INTERVAL '7 days'"
                )['total'],
                'open_reports': self.fetch_one(
                    "SELECT COUNT(*) AS count FROM leakage_reports WHERE report_status IN ('OPEN','IN_PROGRESS')"
                )['count'],
                'quarter_rate': self.fetch_one(
                    """
                    SELECT COALESCE(
                        ROUND(
                            (SUM(CASE WHEN payment_status = 'PAID' THEN 1 ELSE 0 END)::numeric / NULLIF(COUNT(*),0)) * 100,
                            2
                        ),
                        0
                    ) AS rate
                    FROM bills
                    WHERE billing_month >= CURRENT_DATE - INTERVAL '90 days'
                    """
                )['rate'],
                'usage_trend': usage_rows,
                'leakages': self.fetch_all(
                    """
                    SELECT district, location_description, priority, report_status
                    FROM leakage_reports
                    ORDER BY reported_at DESC
                    LIMIT 10
                    """
                ),
                'sync_health': self.fetch_all(
                    """
                    SELECT source_db, target_db, sync_status, synced_at
                    FROM sync_log
                    ORDER BY synced_at DESC
                    LIMIT 10
                    """
                ),
            }

        def get_admin_lists(self):
            return {
                'customers': self.fetch_all(
                    """
                    SELECT customer_id, account_number, full_name, district, phone, account_status
                    FROM customers
                    ORDER BY customer_id DESC
                    LIMIT 20
                    """
                ),
                'rates': self.fetch_all(
                    """
                    SELECT rate_id, service_type, rate_tier, min_units, max_units, cost_per_unit, fixed_charge, status
                    FROM billing_rates
                    ORDER BY rate_id DESC
                    """
                ),
                'payments': self.fetch_all(
                    """
                    SELECT payment_id, receipt_number, bill_id, customer_id, amount_paid, payment_method, payment_date, payment_status
                    FROM payments
                    ORDER BY payment_date DESC
                    LIMIT 20
                    """
                ),
                'users': self.fetch_all(
                    """
                    SELECT user_id, full_name, username, role, status
                    FROM users
                    ORDER BY user_id DESC
                    LIMIT 20
                    """
                ),
                'sync_logs': self.fetch_all(
                    """
                    SELECT sync_id, table_name, record_id, operation_type, source_db, target_db, sync_status, sync_message, synced_at
                    FROM sync_log
                    ORDER BY synced_at DESC
                    LIMIT 30
                    """
                ),
                'reports': self.fetch_reports(),
            }

        def fetch_reports(self):
            usage_summary = self.fetch_one(
                """
                SELECT district, SUM(units_consumed) AS total_units
                FROM water_usage wu
                JOIN customers c ON c.customer_id = wu.customer_id
                GROUP BY district
                ORDER BY total_units DESC
                LIMIT 1
                """
            )
            growth_branch = self.fetch_one(
                """
                SELECT b.branch_name, COUNT(*) AS total
                FROM customers c
                JOIN branches b ON b.branch_id = c.branch_id
                GROUP BY b.branch_name
                ORDER BY total DESC
                LIMIT 1
                """
            )
            avg_monthly = self.fetch_one(
                "SELECT COALESCE(ROUND(AVG(units_consumed),2),0) AS avg_units FROM water_usage"
            )
            overdue = self.fetch_one(
                "SELECT COUNT(*) AS count FROM bills WHERE payment_status IN ('OVERDUE','PENDING','PARTIAL')"
            )
            affected = self.fetch_one(
                """
                SELECT district, COUNT(*) AS count
                FROM customers c
                JOIN bills b ON b.customer_id = c.customer_id
                WHERE b.payment_status IN ('OVERDUE','PENDING','PARTIAL')
                GROUP BY district
                ORDER BY count DESC
                LIMIT 1
                """
            )

            return {
                'highest_consumption': usage_summary,
                'fastest_growing_branch': growth_branch,
                'avg_monthly': avg_monthly,
                'overdue': overdue,
                'most_affected_branch': affected,
            }

        def create_user(self, form):
            hashed = generate_password_hash(form['password'])
            row = self.execute_pg(
                """
                INSERT INTO users (full_name, username, email, password_hash, role, status)
                VALUES (%s,%s,%s,%s,%s,%s)
                RETURNING user_id
                """,
                [
                    form['full_name'],
                    form['username'],
                    form.get('email') or None,
                    hashed,
                    form['role'].upper(),
                    form['status'].upper()
                ],
                fetchone=True,
            )

            self.execute_my(
                """
                INSERT INTO users (full_name, username, email, password_hash, role, status)
                VALUES (%s,%s,%s,%s,%s,%s)
                """,
                [
                    form['full_name'],
                    form['username'],
                    form.get('email') or None,
                    hashed,
                    form['role'].upper(),
                    form['status'].upper()
                ],
            )
            self.mirror_insert_sync_log('users', row['user_id'], 'INSERT', 'User account created and mirrored.')

        def create_customer(self, form, admin_user_id: int | None = None):
            row = self.execute_pg(
                """
                INSERT INTO customers (
                    account_number, user_id, branch_id, full_name, phone, email,
                    address_line, district, service_type, meter_number, connection_date, account_status
                )
                VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)
                RETURNING customer_id
                """,
                [
                    form['account_number'],
                    form.get('user_id') or None,
                    form['branch_id'],
                    form['full_name'],
                    form.get('phone') or None,
                    form.get('email') or None,
                    form['address_line'],
                    form['district'],
                    form['service_type'].upper(),
                    form.get('meter_number') or None,
                    form.get('connection_date') or None,
                    form['account_status'].upper(),
                ],
                fetchone=True,
            )

            self.execute_my(
                """
                INSERT INTO customers (
                    account_number, user_id, branch_id, full_name, phone, email,
                    address_line, district, service_type, meter_number, connection_date, account_status
                )
                VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)
                """,
                [
                    form['account_number'],
                    form.get('user_id') or None,
                    form['branch_id'],
                    form['full_name'],
                    form.get('phone') or None,
                    form.get('email') or None,
                    form['address_line'],
                    form['district'],
                    form['service_type'].upper(),
                    form.get('meter_number') or None,
                    form.get('connection_date') or None,
                    form['account_status'].upper(),
                ],
            )

            self.mirror_insert_sync_log('customers', row['customer_id'], 'INSERT', 'Customer created and mirrored.')

            if admin_user_id:
                self.execute_pg(
                    """
                    INSERT INTO notifications (customer_id, notification_type, channel, subject, message, sent_status)
                    VALUES (%s,'SERVICE_NOTICE','SYSTEM',%s,%s,'SENT')
                    """,
                    [
                        row['customer_id'],
                        'Welcome to WASCO',
                        'Your customer account has been created successfully.'
                    ],
                )

        def create_billing_rate(self, form):
            row = self.execute_pg(
                """
                INSERT INTO billing_rates (
                    service_type, rate_tier, min_units, max_units, cost_per_unit,
                    fixed_charge, effective_from, effective_to, status
                )
                VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s)
                RETURNING rate_id
                """,
                [
                    form['service_type'].upper(),
                    form['rate_tier'],
                    form['min_units'],
                    form.get('max_units') or None,
                    form['cost_per_unit'],
                    form.get('fixed_charge') or 0,
                    form['effective_from'],
                    form.get('effective_to') or None,
                    form['status'].upper()
                ],
                fetchone=True,
            )

            self.execute_my(
                """
                INSERT INTO billing_rates (
                    service_type, rate_tier, min_units, max_units, cost_per_unit,
                    fixed_charge, effective_from, effective_to, status
                )
                VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s)
                """,
                [
                    form['service_type'].upper(),
                    form['rate_tier'],
                    form['min_units'],
                    form.get('max_units') or None,
                    form['cost_per_unit'],
                    form.get('fixed_charge') or 0,
                    form['effective_from'],
                    form.get('effective_to') or None,
                    form['status'].upper()
                ],
            )

            self.mirror_insert_sync_log('billing_rates', row['rate_id'], 'INSERT', 'Billing rate created and mirrored.')

        def create_leakage_report(self, form, customer_id=None):
            row = self.execute_pg(
                """
                INSERT INTO leakage_reports (
                    customer_id, district, location_description, report_description,
                    priority, report_status, assigned_branch_id
                )
                VALUES (%s,%s,%s,%s,%s,'OPEN',%s)
                RETURNING leakage_id
                """,
                [
                    customer_id,
                    form['district'],
                    form['location_description'],
                    form['report_description'],
                    form['priority'].upper(),
                    form.get('assigned_branch_id') or None
                ],
                fetchone=True,
            )

            self.execute_my(
                """
                INSERT INTO leakage_reports (
                    customer_id, district, location_description, report_description,
                    priority, report_status, assigned_branch_id
                )
                VALUES (%s,%s,%s,%s,%s,'OPEN',%s)
                """,
                [
                    customer_id,
                    form['district'],
                    form['location_description'],
                    form['report_description'],
                    form['priority'].upper(),
                    form.get('assigned_branch_id') or None
                ],
            )

            self.mirror_insert_sync_log('leakage_reports', row['leakage_id'], 'INSERT', 'Leakage report created and mirrored.')

        def create_payment(self, form, admin_user_id: int):
            bill = self.fetch_one('SELECT * FROM bills WHERE bill_id = %s', [form['bill_id']])
            if not bill:
                raise ValueError('Bill not found.')

            row = self.execute_pg(
                """
                INSERT INTO payments (
                    bill_id, customer_id, receipt_number, amount_paid,
                    payment_method, payment_reference, payment_status, recorded_by
                )
                VALUES (%s,%s,%s,%s,%s,%s,%s,%s)
                RETURNING payment_id
                """,
                [
                    form['bill_id'],
                    bill['customer_id'],
                    form['receipt_number'],
                    form['amount_paid'],
                    form['payment_method'].upper(),
                    form.get('payment_reference') or None,
                    form['payment_status'].upper(),
                    admin_user_id
                ],
                fetchone=True,
            )

            self.execute_my(
                """
                INSERT INTO payments (
                    bill_id, customer_id, receipt_number, amount_paid,
                    payment_method, payment_reference, payment_status, recorded_by
                )
                VALUES (%s,%s,%s,%s,%s,%s,%s,%s)
                """,
                [
                    form['bill_id'],
                    bill['customer_id'],
                    form['receipt_number'],
                    form['amount_paid'],
                    form['payment_method'].upper(),
                    form.get('payment_reference') or None,
                    form['payment_status'].upper(),
                    admin_user_id
                ],
            )

            total_paid = self.fetch_one(
                """
                SELECT COALESCE(SUM(amount_paid),0) AS total
                FROM payments
                WHERE bill_id = %s AND payment_status IN ('SUCCESS','PARTIAL')
                """,
                [form['bill_id']]
            )['total']

            if total_paid >= bill['total_amount']:
                new_status = 'PAID'
            elif total_paid > 0:
                new_status = 'PARTIAL'
            else:
                new_status = 'PENDING'

            self.execute_pg(
                'UPDATE bills SET payment_status = %s, updated_at = CURRENT_TIMESTAMP WHERE bill_id = %s',
                [new_status, form['bill_id']]
            )
            self.execute_my(
                'UPDATE bills SET payment_status = %s WHERE bill_id = %s',
                [new_status, form['bill_id']]
            )

            self.execute_pg(
                """
                INSERT INTO notifications (
                    customer_id, bill_id, notification_type, channel,
                    subject, message, sent_status, sent_at
                )
                VALUES (%s,%s,'PAYMENT_CONFIRMATION','SYSTEM',%s,%s,'SENT',CURRENT_TIMESTAMP)
                """,
                [
                    bill['customer_id'],
                    form['bill_id'],
                    'Payment received',
                    f"Payment {form['receipt_number']} was recorded successfully."
                ],
            )

            self.mirror_insert_sync_log('payments', row['payment_id'], 'INSERT', 'Payment created and mirrored.')

    db = DBService(DBConfig)

    def login_required(view):
        @wraps(view)
        def wrapped(*args, **kwargs):
            if 'user_id' not in session:
                flash('Please sign in to continue.', 'warning')
                return redirect(url_for('login'))
            return view(*args, **kwargs)
        return wrapped

    def role_required(*roles):
        def decorator(view):
            @wraps(view)
            def wrapped(*args, **kwargs):
                if 'role' not in session:
                    return redirect(url_for('login'))
                if session['role'] not in roles:
                    abort(403)
                return view(*args, **kwargs)
            return wrapped
        return decorator

    @app.context_processor
    def inject_globals():
        return {
            'current_user': {
                'user_id': session.get('user_id'),
                'username': session.get('username'),
                'full_name': session.get('full_name'),
                'role': session.get('role'),
                'customer_id': session.get('customer_id'),
                'email': session.get('email'),
            },
            'now': datetime.utcnow(),
        }

    @app.template_filter('money')
    def money_filter(value):
        try:
            return f"M {Decimal(value):,.2f}"
        except Exception:
            return f"M {value}"

    @app.template_filter('datefmt')
    def datefmt(value, fmt='%Y-%m-%d'):
        if not value:
            return ''
        if isinstance(value, (datetime, date)):
            return value.strftime(fmt)
        return str(value)

    @app.get('/')
    def home():
        public_stats = {
            'active_customers': db.fetch_one(
                'SELECT COUNT(*) AS count FROM customers WHERE account_status = %s',
                ['ACTIVE']
            )['count'],
            'branches': db.fetch_one('SELECT COUNT(*) AS count FROM branches')['count'],
            'open_reports': db.fetch_one(
                "SELECT COUNT(*) AS count FROM leakage_reports WHERE report_status IN ('OPEN','IN_PROGRESS')"
            )['count'],
        }
        return render_template('index.html', public_stats=public_stats)

    @app.route('/login', methods=['GET', 'POST'])
    def login():
        if request.method == 'POST':
            username = request.form.get('username', '').strip()
            password = request.form.get('password', '').strip()
            selected_role = request.form.get('role', '').strip().upper()

            user = db.authenticate(username, password)
            if not user:
                flash('Invalid username or password.', 'danger')
                return render_template('login.html')

            if user['status'] != 'ACTIVE':
                flash('This account is not active.', 'warning')
                return render_template('login.html')

            if user['role'] != selected_role:
                flash('Selected role does not match your account.', 'warning')
                return render_template('login.html')

            session.clear()
            session.update({
                'user_id': user['user_id'],
                'username': user['username'],
                'email': user.get('email'),
                'full_name': user['full_name'],
                'role': user['role'],
                'customer_id': user.get('customer_id'),
            })

            flash(f"Welcome back, {user['full_name']}.", 'success')

            if user['role'] == 'ADMIN':
                return redirect(url_for('admin_dashboard'))
            if user['role'] == 'CUSTOMER':
                return redirect(url_for('customer_dashboard'))
            if user['role'] == 'MANAGER':
                return redirect(url_for('manager_dashboard'))

        return render_template('login.html')

    @app.get('/logout')
    def logout():
        session.clear()
        flash('You have been signed out.', 'success')
        return redirect(url_for('login'))

    @app.route('/admin', methods=['GET', 'POST'])
    @login_required
    @role_required('ADMIN')
    def admin_dashboard():
        if request.method == 'POST' and request.form.get('form_name') == 'customer':
            try:
                db.create_customer(request.form, session['user_id'])
                flash('Customer created successfully.', 'success')
                return redirect(url_for('admin_dashboard'))
            except Exception as exc:
                flash(f'Could not create customer: {exc}', 'danger')

        lists = db.get_admin_lists()
        branches = db.fetch_all(
            'SELECT branch_id, branch_name, district FROM branches ORDER BY branch_name'
        )

        return render_template(
            'admin.html',
            summary=db.get_admin_summary(),
            customers=lists['customers'],
            branches=branches
        )

    @app.route('/customer', methods=['GET', 'POST'])
    @login_required
    @role_required('CUSTOMER')
    def customer_dashboard():
        cid = session.get('customer_id')
        if not cid:
            linked_customer = db.fetch_one(
                """
                SELECT customer_id
                FROM customers
                WHERE user_id = %s OR email = %s
                ORDER BY customer_id ASC
                LIMIT 1
                """,
                [session.get('user_id'), session.get('email') or session.get('username')],
            )
            if linked_customer:
                cid = linked_customer['customer_id']
                session['customer_id'] = cid
            else:
                flash('Your customer profile is not linked yet. Please contact the administrator.', 'warning')
                return redirect(url_for('home'))

        if request.method == 'POST' and request.form.get('form_name') == 'leakage':
            try:
                db.create_leakage_report(request.form, cid)
                flash('Leakage report submitted.', 'success')
                return redirect(url_for('customer_dashboard') + '#leakage')
            except Exception as exc:
                flash(f'Could not submit leakage report: {exc}', 'danger')

        data = db.get_customer_dashboard(session['user_id'], cid)
        return render_template('customer.html', **data)

    @app.get('/manager')
    @login_required
    @role_required('MANAGER')
    def manager_dashboard():
        return render_template('manager.html', summary=db.get_manager_summary())

    @app.route('/admin/billing-rates', methods=['GET', 'POST'])
    @login_required
    @role_required('ADMIN')
    def billing_rates():
        if request.method == 'POST':
            try:
                db.create_billing_rate(request.form)
                flash('Billing rate saved successfully.', 'success')
                return redirect(url_for('billing_rates'))
            except Exception as exc:
                flash(f'Could not save billing rate: {exc}', 'danger')

        rates = db.fetch_all('SELECT * FROM billing_rates ORDER BY rate_id DESC')
        return render_template('billing-rates.html', rates=rates)

    @app.route('/admin/payments', methods=['GET', 'POST'])
    @login_required
    @role_required('ADMIN')
    def payments_admin():
        if request.method == 'POST':
            try:
                db.create_payment(request.form, session['user_id'])
                flash('Payment recorded successfully.', 'success')
                return redirect(url_for('payments_admin'))
            except Exception as exc:
                flash(f'Could not record payment: {exc}', 'danger')

        payments = db.fetch_all(
            """
            SELECT p.payment_id, p.receipt_number, p.bill_id, c.account_number,
                   p.amount_paid, p.payment_method, p.payment_date, p.payment_status
            FROM payments p
            JOIN customers c ON c.customer_id = p.customer_id
            ORDER BY p.payment_date DESC
            LIMIT 25
            """
        )
        outstanding = db.fetch_all(
            """
            SELECT c.account_number, c.full_name, b.total_amount, b.bill_number, b.payment_status
            FROM bills b
            JOIN customers c ON c.customer_id = b.customer_id
            WHERE b.payment_status IN ('PENDING','PARTIAL','OVERDUE')
            ORDER BY b.total_amount DESC
            LIMIT 25
            """
        )
        bills = db.fetch_all(
            'SELECT bill_id, bill_number, total_amount FROM bills ORDER BY bill_id DESC LIMIT 50'
        )
        summary = db.get_admin_summary()
        disputes = db.fetch_one(
            "SELECT COUNT(*) AS count FROM payments WHERE payment_status IN ('PENDING','FAILED','PARTIAL')"
        )['count']

        return render_template(
            'payments-admin.html',
            payments=payments,
            outstanding=outstanding,
            bills=bills,
            summary=summary,
            disputes=disputes
        )

    @app.get('/admin/reports')
    @login_required
    @role_required('ADMIN')
    def reports():
        reports_data = db.fetch_reports()
        usage_by_period = {
            'daily_usage': db.fetch_one(
                "SELECT COALESCE(SUM(units_consumed),0) AS total FROM water_usage WHERE reading_month = CURRENT_DATE"
            )['total'],
            'weekly_revenue': db.fetch_one(
                "SELECT COALESCE(SUM(amount_paid),0) AS total FROM payments WHERE payment_date >= CURRENT_DATE - INTERVAL '7 days'"
            )['total'],
            'monthly_new_accounts': db.fetch_one(
                "SELECT COUNT(*) AS count FROM customers WHERE created_at >= DATE_TRUNC('month', CURRENT_DATE)"
            )['count'],
            'quarterly_collection_rate': db.fetch_one(
                """
                SELECT COALESCE(
                    ROUND(
                        (SUM(CASE WHEN payment_status = 'PAID' THEN 1 ELSE 0 END)::numeric / NULLIF(COUNT(*),0))*100,
                        2
                    ),
                    0
                ) AS rate
                FROM bills
                WHERE billing_month >= CURRENT_DATE - INTERVAL '90 days'
                """
            )['rate'],
        }

        table_rows = [
            {
                'report_type': 'Usage Report',
                'period': 'Daily',
                'key_result': f"{usage_by_period['daily_usage']} total consumption",
                'status': 'Generated'
            },
            {
                'report_type': 'Revenue Report',
                'period': 'Weekly',
                'key_result': f"{usage_by_period['weekly_revenue']} collected",
                'status': 'Generated'
            },
            {
                'report_type': 'Customer Growth',
                'period': 'Monthly',
                'key_result': f"{usage_by_period['monthly_new_accounts']} new accounts",
                'status': 'Generated'
            },
            {
                'report_type': 'Collection Report',
                'period': 'Quarterly',
                'key_result': f"{usage_by_period['quarterly_collection_rate']}% collection rate",
                'status': 'Review'
            },
        ]

        return render_template(
            'reports.html',
            reports=reports_data,
            usage_by_period=usage_by_period,
            table_rows=table_rows
        )

    @app.route('/admin/users', methods=['GET', 'POST'])
    @login_required
    @role_required('ADMIN')
    def users():
        if request.method == 'POST':
            try:
                db.create_user(request.form)
                flash('User account created.', 'success')
                return redirect(url_for('users'))
            except Exception as exc:
                flash(f'Could not create user: {exc}', 'danger')

        users_list = db.fetch_all(
            'SELECT full_name, username, role, status FROM users ORDER BY user_id DESC'
        )
        return render_template('users.html', users_list=users_list)

    @app.get('/admin/db-sync')
    @login_required
    @role_required('ADMIN')
    def db_sync():
        environments = db.ping()
        sync_logs = db.fetch_all(
            """
            SELECT table_name, record_id, operation_type, source_db, target_db,
                   sync_status, sync_message, synced_at
            FROM sync_log
            ORDER BY synced_at DESC
            LIMIT 30
            """
        )
        return render_template('db-sync.html', environments=environments, sync_logs=sync_logs)

    @app.errorhandler(403)
    def forbidden(_e):
        return render_template('403.html'), 403

    @app.errorhandler(500)
    def server_error(e):
        return render_template('500.html', error=e), 500

    return app


app = create_app()

if __name__ == '__main__':
    app.run(debug=True)