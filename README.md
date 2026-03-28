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
<img src="Screen\Screenshot 2026-03-28 160557.png" width="1000" style="border-radius: 12px; box-shadow: 0 8px 24px rgba(0,0,0,0.15);" alt="Landing & Login Page">

### 👑 Owner & Admin Experience

**1. Real-Time Intelligence Dashboard**
*Financial metrics are calculated dynamically, stripping out returns and isolating input/output GST for true profit margins.*
<img src="Screen\Screenshot 2026-03-28 160653.png" width="1000" style="border-radius: 12px; box-shadow: 0 8px 24px rgba(0,0,0,0.15);" alt="Owner Dashboard">

**2. Comprehensive Analytics & Reports**
*Generate custom, vector-based PDF reports for demand forecasting, GST liability, and category revenue.*
<img src="Screen\Screenshot 2026-03-28 160709.png" width="1000" style="border-radius: 12px; box-shadow: 0 8px 24px rgba(0,0,0,0.15);" alt="Reports Page">

**3. Supplier & Procurement Management**
*Track purchase orders, manage vendor relationships, and monitor pending deliveries.*
<img src="Screen\Screenshot 2026-03-28 160736.png" width="1000" style="border-radius: 12px; box-shadow: 0 8px 24px rgba(0,0,0,0.15);" alt="Supplier Management">

**4. Staff Performance Analysis**
*Monitor individual employee sales volume, billing speed, and transaction accuracy.*
<img src="Screen\Screenshot 2026-03-28 160757.png" width="1000" style="border-radius: 12px; box-shadow: 0 8px 24px rgba(0,0,0,0.15);" alt="Staff Analysis">

**5. Store Details & Settings**
*Configure system-wide variables like store name, default GST rates, and UPI payment IDs.*
<img src="Screen\Screenshot 2026-03-28 160812.png" width="1000" style="border-radius: 12px; box-shadow: 0 8px 24px rgba(0,0,0,0.15);" alt="Store Settings">

### 👨‍⚕️ Staff & Pharmacist Experience

**1. High-Speed POS & Billing Engine**
*Zero-latency checkout interface with tri-tier search algorithms and automatic FIFO batch deduction.*
<img src="Screen\Screenshot 2026-03-28 160827.png" width="1000" style="border-radius: 12px; box-shadow: 0 8px 24px rgba(0,0,0,0.15);" alt="Billing POS">

**2. Real-Time Inventory Status**
*Track stock quantities across multiple batches and monitor reorder levels instantly.*
<img src="Screen\Screenshot 2026-03-28 161017.png" width="1000" style="border-radius: 12px; box-shadow: 0 8px 24px rgba(0,0,0,0.15);" alt="Inventory Status">

**3. Expiry & Low Stock Alerts**
*Proactive dashboard warning staff of batches nearing expiration (30/60/90 days) to minimize capital loss.*
<img src="Screen\Screenshot 2026-03-28 161028.png" width="1000" style="border-radius: 12px; box-shadow: 0 8px 24px rgba(0,0,0,0.15);" alt="Expiry Alerts">

**4. Bill Returns & Inventory Restock**
*Process refunds and intelligently restore returned medicine back to the batch with the furthest expiry date.*
<img src="Screen\Screenshot 2026-03-28 161045.png" width="1000" style="border-radius: 12px; box-shadow: 0 8px 24px rgba(0,0,0,0.15);" alt="Bill Returns">

</div>

---
## 🚀 Core Engine Workflows (Powered by `app.py`)

The application is structured into modular routing blocks handling distinct business logic. Below are the core functions and routes driving the system:

### Helper & Utility Functions
* `get_db()`: Establishes and returns the MySQL database connection.
* `get_setting() / get_all_settings()`: Fetches dynamic global configurations from the database.
* `hash_password()`: Secures user credentials using SHA-256 encryption.
* `generate_bill_number() / generate_purchase_number()`: Creates unique identifiers for transactions and POs based on timestamps.
* `calculate_gst() / format_amount()`: Financial utilities for tax calculation and currency formatting.
* `get_quarter_info() / cleanup_old_data()`: Identifies fiscal quarters and purges transactional data older than 6 quarters to maintain performance.

### Authentication & Dashboard Routes
* `login() / logout()`: Handles user sessions and role-based redirects (Owner vs. Staff).
* `dashboard()`: Aggregates real-time metrics (revenue minus refunds, GST liability, pending orders, low stock, staff performance) for the executive view.

### Billing & POS Routes
* `billing() / search_medicine()`: Manages the POS interface. Search uses a tri-tier algorithm (Exact $\rightarrow$ AND $\rightarrow$ OR) to locate medicines.
* `add_to_cart() / update_cart() / remove_from_cart()`: Session-based cart management with strict batch-specific stock validation.
* `checkout()`: Finalizes cash bills immediately or stages UPI payments into `pending_orders`. Triggers `sp_sell_product` for FIFO batch deduction.
* `upi_payment() / approve_payment()`: Polling mechanism and approval workflow for digital payments.
* `invoice()`: Renders the finalized bill for printing.
* `process_return()`: Handles refunds, logs the return, and intelligently adds stock back to the batch with the furthest expiry date.

### Inventory & Batch Management
* `inventory()`: Displays master product catalog with aggregated batch totals.
* `add_product() / edit_product() / delete_product()`: CRUD operations for the master medicine catalog.
* `import_csv() / upload_csv()`: Bulk induction of products via CSV using `io.StringIO`.
* `view_batches() / add_batch() / edit_batch() / delete_batch()`: Granular control over specific supplier batches, cost prices, and expiry dates.
* `low_stock() / expiry_alerts()`: Monitors inventory dropping below `min_stock_level` and flags batches expiring within 30/60/90 days.

### Supplier & Procurement
* `suppliers() / add_supplier() / edit_supplier()`: Vendor management.
* `supplier_purchases() / add_supplier_purchase()`: Creates and tracks purchase orders.
* `update_purchase_status() / receive_purchase()`: Transitions POs to 'received' and automatically generates new batch profiles with updated stock.

---

## 🧠 Advanced Financial & Analytical Reporting

The system generates HTML dashboards and custom vector-based PDFs (via ReportLab) directly from the backend to analyze financial health. 

### PDF Generation Routes
* `download_inventory_report()`: Generates a valuation PDF calculating `Current Stock × Selling Price` categorized by the manufacturer.
* `download_analytics_pdf()`: Produces charts (`Pie`, `VerticalBarChart`, `HorizontalLineChart`) for Category GST liability, Manufacturer Revenue, and Yearly Sales trends.
* `download_detailed_sales_report()`: Generates comprehensive period-based reports (Financial Summary, Product Performance, Transaction History).

### Analytical Dashboards
* `reports()`: Aggregates yearly/monthly revenue, top-selling products, payment method distribution, and hourly sales patterns.
* `executive_reports()`: High-level overview of supplier procurement vs. manufacturer revenue.

---

## 💻 Extensive RESTful API Layer

The frontend interfaces with the database asynchronously through a comprehensive suite of internal JSON APIs mapped to precise SQL queries.

### Transaction & POS APIs
* `GET /api/check_payment_status/<int:order_id>`: Polls real-time approval status for pending UPI transactions.
* `GET /api/search_customers?phone=...`: Autocomplete endpoint for fetching customers by partial phone number.
* `GET /api/customer/<phone>`: Retrieves exact customer details for billing.
* `GET /api/get_bill_items/<bill_number>`: Fetches line items for processing returns.
* `GET /search_medicine_names`: Populates the POS autocomplete datalist.
* `GET /clear_search_cache`: Clears the user's active search session.

### System Administration APIs
* `POST /admin/cleanup_old_data`: Triggers the 6-quarter database purge.
* `GET /admin/quarter_stats`: Retrieves statistical distribution of data across fiscal quarters.

### Data & Analytics APIs (`/api/report/...`)
* `daily_sales_summary`: Hourly sales breakdown, payment methods, and daily staff performance.
* `sales_trend`: 30-day revenue trends and week-over-week growth rates.
* `payment_method_analysis`: Transaction volume by type and average UPI approval times.
* `revenue_by_category`: Revenue breakdown and percentage share by medicine category.
* `stock_valuation`: Calculates potential profit comparing `avg_cost_price` against `selling_price`.
* `fast_slow_moving`: Contrasts high-transaction items against dead stock (sales < 5).
* `batch_expiry_dashboard`: Financial value at risk for expired, 30-day, and 90-day expiring batches.
* `stock_movement`: Tracks quantities purchased, sold, and returned per product.
* `supplier_performance`: Vendor order completion rates and total purchase values.
* `top_customers`: Top 50 clients based on total purchase volume over a given period.
* `customer_ratio`: Walk-in vs. Registered customer revenue comparison.
* `staff_sales_comparison`: Benchmark of bills processed by individual staff members.
* `billing_speed`: Calculates average items per bill and bills processed per day by staff.
* `upi_approval_report`: Tracks pending minutes and average approval times for digital payments.
* `purchase_order_status`: Real-time status of pending, overdue, and completed supplier POs.
* `purchase_vs_sales`: Net difference between units procured vs. units sold.
* `supplier_purchase_summary`: Aggregated PO counts, average order values, and fulfillment states.
* `gst_summary`: Input vs. Output tax collection summaries.
* `cash_collection`: Day-wise physical cash vs. digital payment aggregation.
* `demand_forecasting`: Calculates `avg_monthly_demand` to predict remaining `months_of_stock`.
* `seasonal_analysis`: Month-by-month historical sales volume per product.
* `near_expiry_impact`: Highlights high-risk stock needing urgent liquidation.
* `stockout_report`: Identifies lost revenue from products with historical demand but 0 current stock.
* `low_stock_alert_dashboard`: Suggests exact reorder quantities and estimated reorder costs.
