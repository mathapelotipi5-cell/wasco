# WASCO Online Water Billing Management System

A production-ready Flask application for customer water billing, payments, service reporting, administrative management, and operational monitoring.

## Main Features
- Customer portal for bills, usage history, notifications, and leakage reports
- Administrator dashboard for customers, users, billing rates, payments, and reports
- Manager dashboard for service and revenue insights
- Primary cloud database connection through environment variables
- Optional backup database support for service continuity

## Railway Start Command
```bash
gunicorn app:app
```

## Required Environment Variables
```env
DATABASE_URL=your_primary_database_url
SECRET_KEY=your_secret_key
```

## Optional Backup Database Variables
```env
MYSQL_HOST=your_backup_host
MYSQL_PORT=3306
MYSQL_USER=your_backup_user
MYSQL_PASSWORD=your_backup_password
MYSQL_DATABASE=your_backup_database
```

## Requirements
Install packages from `requirements.txt`.
