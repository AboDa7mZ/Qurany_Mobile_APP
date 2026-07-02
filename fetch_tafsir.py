import http.client
import json

base_url = "api.alquran.cloud"
endpoint = "/v1/surah/1/editions/ar.jalalayn"
headers = {"Accept-Encoding": ""}

conn = http.client.HTTPSConnection(base_url)
conn.request("GET", endpoint, headers=headers)
response = conn.getresponse()
body = response.read().decode()
conn.close()

try:
    data = json.loads(body)
except json.JSONDecodeError:
    print("Failed to parse response as JSON")
    print(body)
    raise

output_file = "al_fatiha_tafsir.json"
with open(output_file, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2, ensure_ascii=False)

print(f"Saved tafsir JSON to {output_file}\n")
print("API endpoint:", endpoint)
print("HTTP status:", response.status, response.reason)
print("Surah:", data.get("data", [{}])[0].get("englishName"))
print("Tafsir edition:", data.get("data", [{}])[0].get("edition", {}).get("englishName"))
print("Number of ayahs fetched:", len(data.get("data", [{}])[0].get("ayahs", [])))
print("\nFirst ayah tafsir data sample:\n")
first_ayah = data.get("data", [{}])[0].get("ayahs", [])[0]
print(json.dumps(first_ayah, indent=2, ensure_ascii=False))