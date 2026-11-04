"""GitLab -> Mattermost relay.

GitLab sends project webhooks (push, tag_push, pipeline) here. This script checks the
shared secret in X-Gitlab-Token, formats a short markdown message and posts it to a
Mattermost incoming webhook. Only the standard library is used.

Env:
  MM_WEBHOOK_URL     Mattermost incoming webhook URL (secret: the hook id is the key)
  GITLAB_HOOK_TOKEN  value GitLab sends back in X-Gitlab-Token (set as the hook secret)
  LISTEN_PORT        default 8070
"""
import hmac
import json
import os
import sys
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

MM_WEBHOOK_URL = os.environ.get("MM_WEBHOOK_URL", "")
HOOK_TOKEN = os.environ.get("GITLAB_HOOK_TOKEN", "")
PORT = int(os.environ.get("LISTEN_PORT", "8070"))

# A pipeline is announced only when it finishes; running/pending would spam the channel.
PIPELINE_FINAL = {
    "success": "✅",
    "failed": "❌",
    "canceled": "⏹️",
}
ZERO_SHA = "0" * 40


def short(sha):
    return (sha or "")[:8]


def format_push(p):
    project = p["project"]["name"]
    branch = p.get("ref", "").removeprefix("refs/heads/")
    who = p.get("user_name", "?")
    url = p["project"]["web_url"]
    if p.get("before") == ZERO_SHA:
        return f"🌱 **{who}** created branch `{branch}` in `{project}`"
    if p.get("after") == ZERO_SHA:
        return f"🗑️ **{who}** deleted branch `{branch}` in `{project}`"
    commits = p.get("commits", [])
    lines = [f"⬆️ **{who}** pushed {len(commits)} commit(s) to `{project}` on `{branch}`"]
    for c in commits[-5:]:
        title = c["message"].splitlines()[0]
        lines.append(f"- `{short(c['id'])}` {title} ({c['author']['name']})")
    lines.append(f"[{url}/-/tree/{branch}]({url}/-/tree/{branch})")
    return "\n".join(lines)


def format_tag(p):
    project = p["project"]["name"]
    tag = p.get("ref", "").removeprefix("refs/tags/")
    msg = (p.get("message") or "").strip()
    text = f"🏷️ **{p.get('user_name', '?')}** pushed tag `{tag}` in `{project}`"
    if msg:
        text += f"\n> {msg}"
    return text


def format_pipeline(p):
    attrs = p["object_attributes"]
    status = attrs.get("status")
    if status not in PIPELINE_FINAL:
        return None
    project = p["project"]
    pid = attrs["id"]
    url = f"{project['web_url']}/-/pipelines/{pid}"
    who = (p.get("user") or {}).get("name", "?")
    commit = p.get("commit") or {}
    title = (commit.get("message") or "").splitlines()[0:1]
    dur = attrs.get("duration")
    dur_txt = f", {dur}s" if dur is not None else ""
    return (
        f"{PIPELINE_FINAL[status]} Pipeline **#{pid}** `{status}` in `{project['name']}` "
        f"on `{attrs.get('ref', '?')}` ({short(attrs.get('sha'))}{dur_txt}) by {who}\n"
        f"{('> ' + title[0]) if title else ''}\n[Open pipeline]({url})"
    ).strip()


def format_event(p):
    kind = p.get("object_kind")
    if kind == "push":
        return format_push(p)
    if kind == "tag_push":
        return format_tag(p)
    if kind == "pipeline":
        return format_pipeline(p)
    return None


def post_to_mattermost(text):
    body = json.dumps({"username": "GitLab", "icon_emoji": "fox_face", "text": text}).encode()
    req = urllib.request.Request(
        MM_WEBHOOK_URL, data=body, headers={"Content-Type": "application/json"}, method="POST"
    )
    with urllib.request.urlopen(req, timeout=10) as resp:
        return resp.status


class Handler(BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        sys.stderr.write("relay: " + (fmt % args) + "\n")

    def _reply(self, code, text=""):
        self.send_response(code)
        self.send_header("Content-Type", "text/plain")
        self.end_headers()
        self.wfile.write(text.encode())

    def do_POST(self):
        token = self.headers.get("X-Gitlab-Token", "")
        if not HOOK_TOKEN or not hmac.compare_digest(token, HOOK_TOKEN):
            return self._reply(401, "bad token")
        length = int(self.headers.get("Content-Length", "0"))
        try:
            payload = json.loads(self.rfile.read(length) or b"{}")
        except json.JSONDecodeError:
            return self._reply(400, "bad json")
        text = format_event(payload)
        if text is None:
            return self._reply(200, "ignored")
        try:
            post_to_mattermost(text)
        except Exception as exc:  # report, but do not make GitLab retry forever
            sys.stderr.write(f"relay: mattermost post failed: {exc}\n")
            return self._reply(502, "mattermost unavailable")
        return self._reply(200, "ok")

    def do_GET(self):
        self._reply(200, "gitlab-relay ok")


if __name__ == "__main__":
    if not MM_WEBHOOK_URL or not HOOK_TOKEN:
        sys.exit("MM_WEBHOOK_URL and GITLAB_HOOK_TOKEN must be set")
    print(f"listening on :{PORT}", flush=True)
    ThreadingHTTPServer(("0.0.0.0", PORT), Handler).serve_forever()
