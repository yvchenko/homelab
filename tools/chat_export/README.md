
# Chat Export Tool

Export chats from a web platform using an authenticated browser session copied from DevTools.

The script:
- parses a cURL request copied from your browser
- extracts headers and cookies
- authenticates using your existing session
- lists chats by character/profile
- lets you selectively export chats to `.txt` files

---

## Requirements

- Python 3.10+
- An active logged-in browser session

Install dependencies:

```bash
pip install -r requirements.txt
````

---

## requirements.txt

```txt
curl-cffi
```

---

## Usage

Run the script:

```bash
python export_chats.py
```

The script will ask you to paste a cURL command copied from DevTools.

---

## How to Get the cURL Command

1. Open the website in your browser
2. Open DevTools (`F12`)
3. Go to the **Network** tab
4. Refresh the page
5. Find an authenticated API request
6. Right-click the request
7. Select:

```text
Copy -> Copy as cURL
```

8. Paste it into the script terminal
9. Press Enter twice

---

## Processed Chat IDs

The script can skip chats you've already processed.

When prompted:

```text
Paste previously processed chat IDs (or leave blank to skip):
```

You can paste something like:

```python
{12345, 67890}
```

or just press Enter to process everything.

---

## Output

Exported chats are saved in:

```text
./output/
```

Each file is saved as:

```text
<chat_name>.txt
```

Messages are formatted like:

```text
User: hello

AI: hi there
```

---

## Notes

* The script does not bypass authentication.
* It only reuses your existing logged-in browser session.
* Sessions may expire. If you get a `401` or `403` error, copy a fresh cURL command from DevTools.

---

## Disclaimer

This script is intended for personal backup/export purposes only.
Use responsibly and comply with the platform's terms of service.

