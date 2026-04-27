# WASCO Flask System

A real Flask-based version of the WASCO water billing system built from the UI screens and aligned to the distributed database project brief.

## Features
- Public home page
- Secure login using the `users` table
- Role-based dashboards for Admin, Customer, and Branch Manager
- Customer registration
- Billing rate management
- Payment recording and balance updates
- Customer notifications
- Leakage reporting
- Reports and summaries
- PostgreSQL primary database with MySQL mirror writes for selected transactions
- Sync log monitoring

## Databases
The app is configured for these defaults:
- MySQL database: `wasco_database`
- MySQL password: `123456`
- PostgreSQL database: `wasco_water_billing`
- PostgreSQL password: `12345`

## Setup
1. Create the databases in MySQL and PostgreSQL.
2. Run the reset schema and demo data files from the `sql/` folder.
3. Create a virtual environment and install dependencies:
   - `pip install -r requirements.txt`
4. Optionally copy `.env.example` to `.env` and adjust values.
5. Run the app:
   - `python app.py`
6. Open `http://127.0.0.1:5000`

## Suggested Login Accounts
Use records from the `users` table in your seeded PostgreSQL database. The app checks the selected role against the stored role.

## Important Notes
- PostgreSQL is used as the operational database.
- MySQL is used as the mirror database for distributed functionality.
- If MySQL is unavailable, the Flask app still keeps the primary PostgreSQL workflow running and logs can continue in PostgreSQL.
