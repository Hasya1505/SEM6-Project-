import mysql.connector
import random
from datetime import datetime

# Database Configuration
db_config = {
    "host": "localhost",
    "user": "root",
    "password": "", 
    "database": "medical_store"
}

def update_billing_times():
    try:
        conn = mysql.connector.connect(**db_config)
        cursor = conn.cursor(buffered=True)
        
        # 1. Fetch all bill IDs and their current dates
        cursor.execute("SELECT id, bill_date FROM bills")
        bills = cursor.fetchall()
        
        print(f"Updating {len(bills)} bills...")
        
        for b_id, b_date in bills:
            # 2. Keep the date, but change the time randomly between 08:00 and 11:59
            new_hour = random.randint(8, 23)
            new_minute = random.randint(0, 59)
            new_second = random.randint(0, 59)
            
            # Create the new datetime object
            updated_date = b_date.replace(hour=new_hour, minute=new_minute, second=new_second)
            
            # 3. Apply the update
            cursor.execute("UPDATE bills SET bill_date = %s WHERE id = %s", (updated_date, b_id))
            
        conn.commit()
        print("✅ Success: All bill times shifted to 8 AM - 12 PM window.")

    except Exception as e:
        print(f"❌ Error: {e}")
    finally:
        conn.close()

if __name__ == "__main__":
    update_billing_times()