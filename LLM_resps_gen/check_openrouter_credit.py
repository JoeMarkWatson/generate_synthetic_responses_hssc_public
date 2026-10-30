import os
import requests

api_key = os.getenv("OPENROUTER_API_KEY")

if not api_key:
    print("❌ Error: OPENROUTER_API_KEY environment variable is missing!")
else:
    # Safely clean up any invisible wrapping whitespaces/quotes from PyCharm env variables
    api_key = api_key.strip().replace('"', '').replace("'", "")
    print(f"Key loaded (starts with: {api_key[:8]}...)")

    headers = {
        "Authorization": f"Bearer {api_key}",
        "Content-Type": "application/json",
        "Accept": "application/json"
    }

    # 1. Fetch Key Info Safely
    print("\n📡 Fetching Key Metadata...")
    try:
        key_resp = requests.get("https://openrouter.ai/api/v1/key", headers=headers)

        if key_resp.status_code == 200:
            key_data = key_resp.json().get("data", {})
            limit = key_data.get("limit")
            remaining_limit = key_data.get("limit_remaining")

            print("--- API KEY SETTINGS ---")
            if limit is None:
                print("Key Restriction: Unlimited (No custom cap set on this key)")
                print("Key Status:      Active")
            else:
                is_active = key_data.get("is_active", False)
                print(f"Key Status:      {'Active' if is_active else 'Inactive'}")
                print(f"Remaining Limit: ${remaining_limit:.2f} out of ${limit:.2f}")
        else:
            print(f"❌ Key status check failed. HTTP Error: {key_resp.status_code}")
            print(f"Response: {key_resp.text or '[Empty]'}")

    except Exception as e:
        print(f"⚠️ Network error while fetching key details: {e}")

    # 2. Fetch Account Credits Safely
    print("\n📡 Fetching Account-wide Balance...")
    try:
        credits_resp = requests.get("https://openrouter.ai/api/v1/credits", headers=headers)

        if credits_resp.status_code == 200:
            credits_data = credits_resp.json().get("data", {})
            total_credits = credits_data.get("total_credits", 0.0)
            total_usage = credits_data.get("total_usage", 0.0)
            remaining_balance = total_credits - total_usage

            print("bytes --- ACCOUNT BALANCE ---")
            print(f"Total Deposited: ${total_credits:.2f}")
            print(f"Total Spent:     ${total_usage:.2f}")
            print(f"Available Funds: ${remaining_balance:.2f} ✅")
        elif credits_resp.status_code == 403:
            print("❌ Account credits check failed. HTTP Error: 403 (Forbidden)")
            print("👉 OpenRouter might only allow 'Management Keys' to access the global /credits endpoint.")
        else:
            print(f"❌ Credits check failed. HTTP Error: {credits_resp.status_code}")
            print(f"Response: {credits_resp.text or '[Empty]'}")

    except Exception as e:
        print(f"⚠️ Network error while fetching account credits: {e}")
