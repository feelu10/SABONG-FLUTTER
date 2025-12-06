import csv
import requests
import json

# Set your API info
api_url = "http://192.168.0.102:5000"
username = "angelmae"
endpoint = f"{api_url}/api/teller-bet-history"
headers = {"Content-Type": "application/json"}

# Pagination variables
page = 1
all_bets = []

while True:
    # You may need to use 'offset' instead of 'page' depending on your API!
    payload = {"nickname": username, "page": page}
    response = requests.post(endpoint, headers=headers, data=json.dumps(payload), timeout=10)
    if response.status_code != 200:
        print(f"Failed on page {page}: {response.status_code}")
        break
    data = response.json()
    bets = data.get("bets", [])
    if not bets:
        break
    all_bets.extend(bets)
    print(f"Fetched page {page}, {len(bets)} bets")
    page += 1

if not all_bets:
    print("No bets found for user:", username)
    exit()

# Gather all unique field names
all_fields = set()
for bet in all_bets:
    all_fields.update(bet.keys())
fieldnames = list(all_fields)

# Write all bets to CSV
csv_filename = f"{username}_bet_history.csv"
with open(csv_filename, 'w', newline='', encoding='utf-8') as csvfile:
    writer = csv.DictWriter(csvfile, fieldnames=fieldnames)
    writer.writeheader()
    for bet in all_bets:
        writer.writerow({key: bet.get(key, '') for key in fieldnames})

print(f"Saved {len(all_bets)} bets to {csv_filename}")
