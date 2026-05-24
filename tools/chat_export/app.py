import ast
import shlex
from pathlib import Path
from urllib.parse import urlparse

from curl_cffi import requests


def parse_curl(curl_string):
    tokens = shlex.split(curl_string)
    url = None
    headers = {}
    cookies = {}

    i = 0
    while i < len(tokens):
        if tokens[i] == "-H" and i + 1 < len(tokens):
            key, _, value = tokens[i + 1].partition(": ")
            headers[key.lower()] = value
            i += 1
        elif tokens[i] == "-b" and i + 1 < len(tokens):
            for part in tokens[i + 1].split(";"):
                if "=" in part:
                    name, _, value = part.strip().partition("=")
                    cookies[name.strip()] = value.strip()
            i += 1
        elif tokens[i].startswith("http"):
            url = tokens[i]
        i += 1

    return url, headers, cookies


def read_curl_input():
    print("Paste cURL command from DevTools, then press Enter twice:")
    lines = []
    while True:
        line = input()
        if line == "":
            break
        lines.append(line)
    return " ".join(line.rstrip(" \\") for line in lines)


def build_session(curl_string):
    url, headers, cookies = parse_curl(curl_string)
    parsed = urlparse(url)
    base_url = f"{parsed.scheme}://{parsed.netloc}/hampter/chats"

    session = requests.Session(impersonate="chrome")
    session.headers.update(headers)
    for name, value in cookies.items():
        session.cookies.set(name, value, domain=parsed.netloc)

    return session, base_url


def get_character_ids(session, base_url):
    response = session.get(f"{base_url}/character-chats")
    response.raise_for_status()
    return [c.get("character_id") for c in response.json().get("characters")]


def get_chats_by_character(session, base_url, character_id):
    response = session.get(f"{base_url}/character/{character_id}/chats")
    response.raise_for_status()
    return [chat.get("id") for chat in response.json().get("chats")]


def export_chat(session, base_url, chat_id):
    response = session.get(f"{base_url}/{chat_id}")
    response.raise_for_status()
    data = response.json()

    messages = list(reversed(data.get("chatMessages")))
    character_name = data["character"]["name"]
    summary = data["chat"]["summary"][:200]
    first_message = messages[1]["message"]

    print(f"\n{'='*40}")
    print(f"Character: {character_name}")
    print(f"Summary:   {summary}")
    print(f"Preview:   {first_message}")
    print(f"{'='*40}")
    print()

    chat_name = input("Enter chat name (or leave blank to skip): ").strip()
    if not chat_name:
        return None

    Path("output").mkdir(exist_ok=True)
    output_path = f"output/{chat_name}.txt"

    with open(output_path, "w", encoding="utf-8") as f:
        for msg in messages:
            author = "AI: " if msg["is_bot"] else "User: "
            lines = [line for line in msg["message"].split("\n") if line.strip()]
            f.write(author + "\n".join(lines) + "\n\n")

    return output_path


def main():
    curl_string = read_curl_input()
    session, base_url = build_session(curl_string)

    raw = input("Paste previously processed chat IDs (or leave blank to skip): ").strip()
    processed_ids = ast.literal_eval(raw) if raw else set()

    for character_id in get_character_ids(session, base_url):
        for chat_id in get_chats_by_character(session, base_url, character_id):
            if chat_id in processed_ids:
                continue
            export_chat(session, base_url, chat_id)
            processed_ids.add(chat_id)
            print(f"Processed IDs so far: {processed_ids}")


if __name__ == "__main__":
    try:
        main()
    except requests.HTTPError as e:
        if e.response.status_code in (401, 403):
            print("Invalid or expired session. Grab a fresh cURL from DevTools and try again.")
        else:
            print(f"Request failed: {e}")
    except Exception as e:
        print(f"Something went wrong: {e}")
    finally:
        input("\nDone! Press Enter to close...")