<div align="center">

# 🏥 MediStore Pro: Enterprise Pharmacy ERP Ecosystem
### **The Gold Standard in Medical Retail, POS, and Inventory Intelligence**

[![Python](https://img.shields.io/badge/Python-3.10+-3776AB?style=for-the-badge&logo=python&logoColor=white)](https://python.org)
[![Flask](https://img.shields.io/badge/Flask-3.0-000000?style=for-the-badge&logo=flask&logoColor=white)](https://flask.palletsprojects.com/)
[![MySQL](https://img.shields.io/badge/MySQL-8.0-4479A1?style=for-the-badge&logo=mysql&logoColor=white)](https://mysql.com)
[![ReportLab](https://img.shields.io/badge/PDF_Engine-ReportLab-red?style=for-the-badge)](https://www.reportlab.com/)
[![VanillaJS](https://img.shields.io/badge/Frontend-Vanilla_JS-F7DF1E?style=for-the-badge&logo=javascript&logoColor=black)]()
[![Status](https://img.shields.io/badge/Status-Production_Ready-success?style=for-the-badge&logo=checkmarx&logoColor=white)]()

<br>

**MediStore Pro** is a comprehensive, high-concurrency **Enterprise Resource Planning (ERP)** system built exclusively for the pharmaceutical industry. From **Demand Forecasting** and **Batch-Specific FIFO Sales** to **Role-Based Access Control (RBAC)** and **Quarterly Fiscal Data Retention**, it bridges the gap between medical logistics and high-speed retail.

---

## ⚡ The Visual Experience
*Experience a UI that rivals modern fintech and enterprise applications.*

### 🌐 High-Conversion Landing Page & Authentication
<img src="Screenshot (3).png" width="1000" style="border-radius: 12px; box-shadow: 0 8px 24px rgba(0,0,0,0.15);" alt="MediStore Pro Landing">

### 📊 Real-Time Intelligence Dashboard
<img src="Screenshot (18).png" width="1000" style="border-radius: 12px; box-shadow: 0 8px 24px rgba(0,0,0,0.15);" alt="MediStore Pro Dashboard">

</div>

---

## 🛒 1. High-Speed POS & Billing Engine

Move from search to receipt in under 10 seconds. Designed to handle peak pharmacy hours with zero lag.

<div align="center">
  <img src="Screenshot (15).png" width="49%" style="border-radius: 8px;" alt="Billing Search">
  <img src="Screenshot (16).png" width="49%" style="border-radius: 8px;" alt="Checkout Transaction">
</div>

* **Precision Search Algorithms:** A 3-tier fallback strategy—Exact Match $\rightarrow$ Multi-term `AND` $\rightarrow$ Broad `OR`.
* **Smart Cart & Batch Override:** Cashiers can let the system automatically deduct stock from the oldest batch (FIFO) via the `sp_sell_product` Stored Procedure.
* **UPI & Digital Payments:** Seamlessly handles digital payments with pending states and background polling.

---

## 🛡️ 2. Inventory Shield & Alerts

Never lose capital to expired medicines or stockouts again.

<div align="center">
  <img src="Screenshot (28).png" width="49%" style="border-radius: 8px;" alt="Low Stock Alerts">
  <img src="Screenshot (29).png" width="49%" style="border-radius: 8px;" alt="Expiry Alerts">
</div>

* **Loss Prevention:** Dual database views trigger a 50-day warning window to prevent dispensing expired drugs.
* **Low Stock Intelligence:** Predictive alerts for items dropping below minimum required thresholds.
* **Intelligent Return-to-Stock:** Processed returns intelligently restore inventory to the batch with the furthest expiry date.

---

## 🧠 3. Data Analytics & "AI-Ready" Logic

Our system computes complex financial metrics on the fly without bogging down the database.

<div align="center">
  <img src="Screenshot (22).png" width="1000" style="border-radius: 12px; box-shadow: 0 8px 24px rgba(0,0,0,0.15);" alt="Sales Reports and Analytics">
</div>

* **Demand Forecasting:** Analyzes 6 months of historical data to calculate average monthly demand and predicts remaining months of stock.
* **Advanced Profit Calculation:** Calculates true margins by stripping out returns and isolating input/output taxes:

$$ \text{Gross Profit} = \text{Net Sales Revenue} - \text{COGS} $$
$$ \text{Net GST Liability} = \text{Output GST Collected} - \text{Input GST Paid} $$

---

## 👥 4. Staff Management & RBAC

<div align="center">
  <img src="Screenshot (21).png" width="1000" style="border-radius: 12px; box-shadow: 0 8px 24px rgba(0,0,0,0.15);" alt="Staff Analysis">
</div>

| Role Level | Permissions | View Access |
| :--- | :--- | :--- |
| **Owner** | Full Access. Modify settings, create staff accounts, view financial reporting, and trigger data wipe. | Dashboard, Reports, Staff Analysis, Settings |
| **Pharmacist** | Inventory management, Purchase Orders, Batch adjustments, and Billing. | Billing, Inventory, Suppliers |
| **Cashier** | Strictly limited to Point of Sale (POS), processing returns, and viewing customer history. | Billing, Customers, All Bills |

---

## 💻 Extensive RESTful API Layer

MediStore Pro includes a rich internal JSON API for seamless async dashboard loading and reporting. Click below to expand the documentation:

<details>
<summary><b>🔥 Click to Expand API Endpoints</b></summary>
<br>

* `GET /api/report/daily_sales_summary` - Hourly sales breakdown & payment methods.
* `GET /api/report/stock_valuation` - Real-time calculation of current stock value vs selling price.
* `GET /api/report/batch_expiry_dashboard` - Capital at risk due to impending expiries.
* `GET /api/report/stock_movement` - Tracks items purchased, sold, and returned.
* `GET /api/report/customer_ratio` - Walk-in vs. Registered customer revenue comparison.
* `GET /api/report/stockout_report` - Identifies products out of stock but with historical demand.
* `GET /api/customer/<phone>` - Instant customer lookup for the POS.

</details>

---

## ⚙️ Engineering & Quick Setup

### 1. Environment Preparation
```bash
# Clone the repository
git clone [https://github.com/your-username/medistore-pro.git](https://github.com/your-username/medistore-pro.git)
cd medistore-pro

# Create and activate virtual environment
python -m venv .venv
source .venv/bin/activate  # On Windows use: .\.venv\Scripts\activate

# Install core dependencies
pip install -r requirements.txt
