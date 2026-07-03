#!/usr/bin/env python3
import json
import os


def main() -> None:
    version = os.environ["VERSION_FULL"]
    artifact = os.environ["ARTIFACT_NAME"]
    artifact_url = os.environ["ARTIFACT_URL"]
    run_url = os.environ["RUN_URL"]
    role_id = os.environ.get("DISCORD_TECH_SQUAD_ROLE_ID", "").strip()

    mention = f"<@&{role_id}>" if role_id else "@Tech Squad"

    content = (
        f"{mention}\n\n"
        f"**Qurany v{version}** — all tests passed ✅\n\n"
        f"• Backend tests: passed\n"
        f"• Flutter tests: passed\n"
        f"• Tag: `{version}`\n"
        f"• **Download APK:** {artifact_url}\n"
        f"  Artifact name: `{artifact}`\n"
        f"• Workflow run: {run_url}"
    )

    payload: dict = {"content": content}
    if role_id:
        payload["allowed_mentions"] = {"parse": [], "roles": [role_id]}

    print(json.dumps(payload))


if __name__ == "__main__":
    main()
