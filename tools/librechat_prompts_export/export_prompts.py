#!/usr/bin/env python3
"""Export user prompts (not AI replies) from LibreChat chats, straight from MongoDB.

Usage:
    # one specific chat
    python3 export_prompts.py --chat-id <conversationId> [--out prompts.json]

    # every chat
    python3 export_prompts.py [--out prompts.json]

The cluster's mongo has no auth, so the URI needs no credentials. If you're
running this off-cluster, port-forward first:

    kubectl -n sandbox port-forward svc/mongodb 27017:27017
"""

import argparse
import json

from pymongo import MongoClient


def export_prompts(uri: str, chat_id: str | None) -> list[dict]:
    db = MongoClient(uri).get_database()

    query = {"isCreatedByUser": True}
    if chat_id:
        query["conversationId"] = chat_id

    messages = list(db.messages.find(query).sort("createdAt", 1))

    titles = {
        c["conversationId"]: c.get("title")
        for c in db.conversations.find(
            {"conversationId": {"$in": list({m["conversationId"] for m in messages})}},
            {"conversationId": 1, "title": 1},
        )
    }

    return [
        {
            "conversationId": m["conversationId"],
            "title": titles.get(m["conversationId"]),
            "createdAt": m.get("createdAt"),
            "prompt": m.get("text"),
        }
        for m in messages
    ]


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--uri", default="mongodb://localhost:27017/LibreChat")
    parser.add_argument("--chat-id", help="LibreChat conversationId to limit the export to")
    parser.add_argument("--out", default="prompts.json")
    args = parser.parse_args()

    prompts = export_prompts(args.uri, args.chat_id)

    with open(args.out, "w", encoding="utf-8") as f:
        json.dump(prompts, f, indent=2, default=str, ensure_ascii=False)

    print(f"Exported {len(prompts)} prompts to {args.out}")


if __name__ == "__main__":
    main()
