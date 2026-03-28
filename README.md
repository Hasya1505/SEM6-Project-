<div align="center">

# 🏥 MediStore Pro: High-Concurrency Pharmacy ERP
### **Engineered for Precision, Scale, and Real-Time Intelligence**

[![Python](https://img.shields.io/badge/Python-3.10+-3776AB?style=for-the-badge&logo=python&logoColor=white)]()
[![Flask](https://img.shields.io/badge/Flask-3.0-000000?style=for-the-badge&logo=flask&logoColor=white)]()
[![MySQL](https://img.shields.io/badge/MySQL-8.0-4479A1?style=for-the-badge&logo=mysql&logoColor=white)]()
[![ReportLab](https://img.shields.io/badge/ReportLab-PDF_Engine-red?style=for-the-badge)]()
[![Status](https://img.shields.io/badge/Status-Production_Ready-success?style=for-the-badge&logo=checkmarx&logoColor=white)]()

<br>

**MediStore Pro** is a robust, data-driven Enterprise Resource Planning (ERP) system. Built entirely on Flask and MySQL, it goes beyond simple billing by implementing strict **FIFO Batch tracking**, **Digital Payment Polling**, **ReportLab Vector Analytics**, and automated **Quarterly Data Retention**.

---

## ⚡ The Visual Experience

### 🌐 Modern Authentication & Landing
*Secure entry point with role-based routing for Owners, Pharmacists, and Cashiers.*
<img src="Screenshot (3).png" width="1000" style="border-radius: 12px; box-shadow: 0 8px 24px rgba(0,0,0,0.15);" alt="Landing & Login Page">

### 👑 Owner & Admin Experience

**1. Real-Time Intelligence Dashboard**
*Financial metrics are calculated dynamically, stripping out returns and isolating input/output GST for true profit margins.*
<img src="Screenshot (18).png" width="1000" style="border-radius: 12px; box-shadow: 0 8px 24px rgba(0,0,0,0.15);" alt="Owner Dashboard">

**2. Comprehensive Analytics & Reports**
*Generate custom, vector-based PDF reports for demand forecasting, GST liability, and category revenue.*
<img src="Screenshot (22).png" width="1000" style="border-radius: 12px; box-shadow: 0 8px 24px rgba(0,0,0,0.15);" alt="Reports Page">

**3. Supplier & Procurement Management**
*Track purchase orders, manage vendor relationships, and monitor pending deliveries.*
<img src="Screenshot_Supplier.png" width="1000" style="border-radius: 12px; box-shadow: 0 8px 24px rgba(0,0,0,0.15);" alt="Supplier Management">

**4. Staff Performance Analysis**
*Monitor individual employee sales volume, billing speed, and transaction accuracy.*
<img src="Screenshot (21).png" width="1000" style="border-radius: 12px; box-shadow: 0 8px 24px rgba(0,0,0,0.15);" alt="Staff Analysis">

**5. Store Details & Settings**
*Configure system-wide variables like store name, default GST rates, and UPI payment IDs.*
<img src="Screenshot_Settings.png" width="1000" style="border-radius: 12px; box-shadow: 0 8px 24px rgba(0,0,0,0.15);" alt="Store Settings">

### 👨‍⚕️ Staff & Pharmacist Experience

**1. High-Speed POS & Billing Engine**
*Zero-latency checkout interface with tri-tier search algorithms and automatic FIFO batch deduction.*
<img src="Screenshot (15).png" width="1000" style="border-radius: 12px; box-shadow: 0 8px 24px rgba(0,0,0,0.15);" alt="Billing POS">

**2. Real-Time Inventory Status**
*Track stock quantities across multiple batches and monitor reorder levels instantly.*
<img src="Screenshot_Inventory.png" width="1000" style="border-radius: 12px; box-shadow: 0 8px 24px rgba(0,0,0,0.15);" alt="Inventory Status">

**3. Expiry & Low Stock Alerts**
*Proactive dashboard warning staff of batches nearing expiration (30/60/90 days) to minimize capital loss.*
<img src="Screenshot (29).png" width="1000" style="border-radius: 12px; box-shadow: 0 8px 24px rgba(0,0,0,0.15);" alt="Expiry Alerts">

**4. Bill Returns & Inventory Restock**
*Process refunds and intelligently restore returned medicine back to the batch with the furthest expiry date.*
<img src="Screenshot_Returns.png" width="1000" style="border-radius: 12px; box-shadow: 0 8px 24px rgba(0,0,0,0.15);" alt="Bill Returns">

</div>

---

## 🗄️ Database Architecture

MediStore Pro relies on a highly normalized MySQL 8.0+ backend to ensure data integrity during concurrent transactions. Below is the core schema derived from the application engine:

| Table Name | Core Purpose | Key Tracked Data |
| :--- | :--- | :--- |
| **`users`** | Role-Based Access Control | `username`, `hashed_password`, `role` (owner/cashier/pharmacist) |
| **`products`** | Master Medicine Catalog | `name`, `manufacturer`, `price`, `category`, `min_stock_level` |
| **`product_batches`** | Granular Stock & Expiry Tracking | `batch_number`, `quantity`, `expiry_date`, `cost_price` |
| **`bills`** | Finalized Sales Transactions | `bill_number`, `customer_id`, `subtotal`, `gst`, `payment_status` |
| **`bill_items`** | Line Items for Receipts | `bill_id`, `product_id`, `quantity`, `total_amount` |
| **`pending_orders`** | UPI Payment Polling Queue | Temporarily holds `cart_data` JSON until payment is approved. |
| **`returns`** | Refund & Restock Logic | `refund_amount`, `added_to_inventory` (boolean), `processed_by` |
| **`suppliers`** | Vendor CRM | `company_name`, `gstin`, contact details |
| **`supplier_purchases`** | Procurement Lifecycle | Tracks status: `to_be_ordered` $\rightarrow$ `ordered` $\rightarrow$ `received` |
| **`customers`** | Patient CRM | Tracks `total_spent` and allows for quick lookup via phone number. |
| **`regular_purchases`** | Chronic Patient Subscriptions | Links a `customer_id` to a `product_id` with a `default_quantity`. |
| **`settings`** | Dynamic Configuration | Global `setting_key` and `setting_value` (e.g., store name, GST rate). |

---

## 🚀 Core Engine Workflows (Powered by `app.py`)

### 🛒 1. The High-Speed POS & Billing Engine
Our Point-of-Sale is designed for zero-latency checkouts during peak pharmacy hours.

* **Tri-Tier Search Algorithm:** Queries cascade from Exact Match $\rightarrow$ Multi-term `AND` $\rightarrow$ Broad `OR` to guarantee precise medicine retrieval.
* **FIFO Batch Deduction:** Cashiers can manually select a specific batch, or let the system call `sp_sell_product` (Stored Procedure) to automatically deduct stock from the oldest batch first.
* **UPI Polling State Machine:** Digital payments route to a `pending_orders` table. The frontend polls `/api/check_payment_status` until the cashier approves the transaction, safely converting it into a finalized bill.

### 🛡️ 2. Inventory Shield & Smart Returns
Protecting capital from expired stock and managing complex supplier logistics.

* **Intelligent Return-to-Stock:** Processed returns via `/process_return` don't just refund money; they intelligently restore physical inventory to the batch with the **furthest expiry date**, adhering to strict pharmacy best practices.
* **Supplier Procurement Lifecycle:** Purchase orders transition from `to_be_ordered` $\rightarrow$ `ordered` $\rightarrow$ `received`. Upon receipt, `/receive_purchase` automatically generates new batch profiles with accurate `cost_price` and `expiry_date` tracking.
* **Master CSV Induction:** Bulk import thousands of master catalog items instantly via `io.StringIO` and `csv.DictReader`.

---

## 🧠 Advanced Financial & Analytical Reporting

Unlike standard apps, MediStore Pro generates completely custom, vector-based PDF reports directly from the backend using **ReportLab** (`Pie`, `VerticalBarChart`, `HorizontalLineChart`).

| Analytical Module | Description & Logic |
| :--- | :--- |
| **Demand Forecasting** | Analyzes 6 months of historical data to calculate `avg_monthly_demand` and predict exactly how many `months_of_stock` remain. |
| **Dead Stock Detection** | Identifies slow-moving items (sales < 5) to calculate locked capital value. |
| **True Margin Calculation** | Calculates exact Gross Profit by strictly isolating net revenue from actual COGS: |

$$\text{Gross Profit} = (\text{Total Revenue} - \text{Refunds}) - \text{Total Purchase Amount}$$
$$\text{Net GST Liability} = \text{Output GST Collected} - \text{Input GST Paid}$$

---

## 👥 Customer CRM & Staff RBAC

### Role-Based Access Control
MediStore Pro strictly enforces roles using session validation across every route:
* **Owner:** Full system access, staff creation, financial reporting, and database cleanup.
* **Pharmacist:** Inventory management, Supplier POs, and Batch adjustments.
* **Cashier:** Confined to the POS engine, customer lookup, and processing returns.

### Chronic Patient CRM
* **Regular Purchase Plans:** Customers can be assigned default recurring medicines. The `/quick_billing` route instantly populates a cart with their prescribed dosages.
* **Loyalty Stats:** Tracks `total_spent` and `unique_medicines` for targeted customer care.

---

## 💻 Extensive RESTful API Layer

The frontend is powered by a massive internal JSON API suite mapped to precise SQL queries. 

<details>
<summary><b>🔥 Click to Expand API Endpoints</b></summary>
<br>

* `GET /api/report/daily_sales_summary` - Hourly sales breakdown & payment methods.
* `GET /api/report/stock_valuation` - Calculates `potential_profit` based on `avg_cost_price` vs `selling_price`.
* `GET /api/report/batch_expiry_dashboard` - Calculates `value_at_risk` for 30, 60, and 90-day expiry windows.
* `GET /api/report/stockout_report` - Identifies lost revenue from products that have high historical demand but 0 current stock.
* `GET /api/report/customer_ratio` - Walk-in vs. Registered customer revenue comparison.
* `GET /api/customer/<phone>` - Instant POS lookup.
* `GET /admin/quarter_stats` - Prepares data for fiscal archiving.

</details>

---

## ⚙️ Engineering & Deployment

### 1. Database Provisioning & Security
This application relies on a robust MySQL 8.0+ backend. Passwords are mathematically secured via `hashlib.sha256()`. Furthermore, to maintain high DB performance, the application includes a `cleanup_old_data()` function designed to safely purge transactional records older than **6 quarters**.

```python
# config.py Setup
class Config:
    DB_HOST = "127.0.0.1"
    DB_USER = "root"
    DB_PASSWORD = "your_secure_password"
    DB_NAME = "medical_store"
    SECRET_KEY = "your-cryptographic-key"
