#!/usr/bin/env python3
"""Exercise the actual Maki permission gate with a local fake OpenAI provider.

No real model, external network, credentials, or user configuration is used.
"""
import json
import fcntl
import os
from pathlib import Path
import shutil
import pty
import re
import select
import signal
import struct
import subprocess
import tempfile
import threading
import time
import termios
import unittest
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

ROOT = Path(__file__).resolve().parents[1]
MAKI = shutil.which("maki")


def run_terminal(command, cwd, env, responses):
    """Use a real controlling terminal, answering only specific expected prompts."""
    master, slave = pty.openpty()
    fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 50, 140, 0, 0))
    terminal_env = dict(env, TERM="xterm-256color")
    process = subprocess.Popen(command, cwd=cwd, env=terminal_env, stdin=slave,
                               stdout=slave, stderr=slave, start_new_session=True,
                               preexec_fn=lambda: fcntl.ioctl(slave, termios.TIOCSCTTY, 0))
    os.close(slave)
    output, plain, step, cursor = b"", "", 0, 0
    deadline = time.monotonic() + 25
    try:
        while time.monotonic() < deadline:
            if select.select([master], [], [], 0.1)[0]:
                try:
                    chunk = os.read(master, 65536)
                except OSError:
                    break
                if not chunk:
                    break
                output += chunk
                plain = re.sub(rb"\x1b\[[0-?]*[ -/]*[@-~]", b"", output).decode(errors="replace")
            if step < len(responses):
                pattern, answer = responses[step]
                match = pattern() if callable(pattern) else re.search(pattern, plain[cursor:], re.I)
                if match:
                    os.write(master, answer)
                    if not callable(pattern):
                        cursor += match.end()
                    step += 1
            if process.poll() is not None:
                break
        else:
            os.killpg(process.pid, signal.SIGKILL)
            plain = re.sub(rb"\x1b\[[0-?]*[ -/]*[@-~]", b"", output).decode(errors="replace")
            raise AssertionError(f"Maki terminal timed out at response {step}:\n" + plain[-8000:])
        returncode = process.wait(timeout=3)
        return subprocess.CompletedProcess(command, returncode, output.decode(errors="replace"), ""), step
    finally:
        if process.poll() is None:
            os.killpg(process.pid, signal.SIGKILL)
            process.wait(timeout=10)
        os.close(master)


class NativeTests(unittest.TestCase):
    def run_case(self, *, rule=None, outcome="allow", inspect=False, override=False,
                 malformed=False, timeout=False, project_disabled=False, jit=False,
                 yolo=False, forced_ask=False, trust_project=True, changed_project=False,
                 interactive=False, managed=False, trust_command=False):
        requests = []
        with tempfile.TemporaryDirectory(prefix="maki-auto-approve-") as temporary:
            base = Path(temporary)
            project = base / "project"
            project.mkdir()
            (project / ".maki").mkdir()
            (project / "script.sh").write_text("echo harmless\n")
            config_dir = base / "config" / "maki"
            config_dir.mkdir(parents=True)
            package = base / "data" / "maki" / "site" / "pack" / "tests" / "start" / "maki-auto-approve"
            if not managed:
                package.parent.mkdir(parents=True)
                package.symlink_to(ROOT, target_is_directory=True)

            class Handler(BaseHTTPRequestHandler):
                def log_message(self, *_):
                    pass

                def do_GET(self):
                    body = json.dumps({"data": [{"id": "worker"}, {"id": "reviewer"}]}).encode()
                    self.send_response(200)
                    self.send_header("Content-Type", "application/json")
                    self.send_header("Content-Length", str(len(body)))
                    self.end_headers()
                    self.wfile.write(body)

                def do_POST(self):
                    request = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
                    requests.append(request)
                    messages = request.get("messages", [])
                    is_review = "You review one pending Maki tool call" in json.dumps(messages)
                    has_result = any(message.get("role") == "tool" for message in messages)
                    call = None
                    if is_review:
                        if timeout:
                            time.sleep(0.4)
                        if inspect and not has_result:
                            tool = next(t["function"] for t in request["tools"] if t["function"]["name"] == "auto_approve_read_file")
                            review_id = tool["parameters"]["properties"]["review_id"]["enum"][0]
                            call = ("auto_approve_read_file", {"path": str(project / "script.sh"), "review_id": review_id})
                        else:
                            text = "invalid JSON" if malformed else json.dumps({
                                "risk_level": "low", "user_authorization": "high",
                                "outcome": outcome, "rationale": "The probe is a bounded test operation.",
                            })
                    elif not has_result:
                        call = ("auto_approve_probe", {"value": "once"})
                    else:
                        text = "done"
                    delta = {"role": "assistant"}
                    if call:
                        delta["tool_calls"] = [{"index": 0, "id": "call_" + str(len(requests)),
                            "type": "function", "function": {"name": call[0], "arguments": json.dumps(call[1])}}]
                    else:
                        delta["content"] = text
                    chunks = [
                        {"choices": [{"index": 0, "delta": delta, "finish_reason": None}]},
                        {"choices": [{"index": 0, "delta": {}, "finish_reason": "tool_calls" if call else "stop"}]},
                        {"choices": [], "usage": {"prompt_tokens": 10, "completion_tokens": 10, "total_tokens": 20}},
                    ]
                    self.send_response(200)
                    self.send_header("Content-Type", "text/event-stream")
                    self.send_header("Connection", "close")
                    self.end_headers()
                    try:
                        for chunk in chunks:
                            chunk.update({"id": "mock", "object": "chat.completion.chunk", "created": 0,
                                          "model": request.get("model", "worker")})
                            self.wfile.write(("data: " + json.dumps(chunk) + "\n\n").encode())
                        self.wfile.write(b"data: [DONE]\n\n")
                    except (BrokenPipeError, ConnectionResetError):
                        pass

            server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
            server.daemon_threads = True
            thread = threading.Thread(target=server.serve_forever, daemon=True)
            thread.start()
            port = server.server_address[1]
            (config_dir / "plugin.toml").write_text('[permissions]\nfs_read=true\nfs_write=true\nrun=true\nnet=true\nenv=true\nagent=true\nnet_hosts=["127.0.0.1"]\n')
            (config_dir / "init.lua").write_text('''
maki.provider.register({ slug = "mock", display_name = "Mock", codec = "openai",
  base_url = "http://127.0.0.1:PORT/v1",
  models = {{ prefixes = { "worker", "reviewer" }, tier = "strong", supports_thinking = false }},
  list_models = function() return {{ id = "worker", tier = "strong" }, { id = "reviewer", tier = "strong" }} end,
})
maki.api.register_tool({ name = "auto_approve_probe", description = "Run the local integration-test probe once.",
  schema = { type = "object", properties = { value = { type = "string" } }, required = { "value" } },
  permission = "run", permission_scopes = "value",
  handler = function() maki.fs.write("EXECUTED", "yes"); return "probe executed" end,
})
maki.setup({ ui = { splash_animation = false },
  provider = { default_model = "mock/worker", allowed_models = { "mock/*" },
  max_retries = 0, max_timeout_retries = 0, connect_timeout_secs = 2 },
  net = { allowed_private_hosts = { "127.0.0.1" } } })
'''.replace("PORT", str(port)).replace("EXECUTED", str(project / "executed")))
            if forced_ask:
                with (config_dir / "init.lua").open("a") as init:
                    init.write('\nmaki.api.set_slot("tool.auto_approve_probe.input", function() return nil, { ask = "Human only" } end)\n')
            expected_commit = None
            if managed:
                fixture_repo = base / "package-source"
                shutil.copytree(ROOT, fixture_repo, ignore=shutil.ignore_patterns(".git", "__pycache__"))
                subprocess.run(["git", "init", "-q", "-b", "main"], cwd=fixture_repo, check=True)
                subprocess.run(["git", "add", "."], cwd=fixture_repo, check=True)
                subprocess.run(["git", "-c", "user.name=Maki test", "-c", "user.email=test@example.invalid",
                                "commit", "-qm", "Integration test fixture"], cwd=fixture_repo, check=True)
                subprocess.run(["git", "tag", "v0.1.0"], cwd=fixture_repo, check=True)
                expected_commit = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=fixture_repo, text=True).strip()
                with (config_dir / "init.lua").open("a") as init:
                    init.write('\nmaki.pack.add({{ src = ' + json.dumps(str(fixture_repo)) +
                               ', name = "maki-auto-approve", version = "v0.1.0" }})\n')
            if rule:
                (config_dir / "permissions.toml").write_text('[auto_approve_probe]\n' + rule + '=["*"]\n')
            global_settings = "[reviewer]\ntimeout_ms=" + ("100" if timeout else "5000") + "\n"
            (config_dir / "auto-approve.toml").write_text(global_settings)
            if override:
                (project / ".maki" / "auto-approve.toml").write_text('[reviewer]\nmodel="mock/reviewer"\n')
            if project_disabled:
                (project / ".maki" / "auto-approve.toml").write_text("enabled=false\n")
            if override and trust_project:
                (config_dir / "auto-approve-trust.json").write_text(json.dumps({"version": 1, "projects": {
                    str(project.resolve()): {"text": (project / ".maki" / "auto-approve.toml").read_text()}}}))
            if changed_project:
                with (project / ".maki" / "auto-approve.toml").open("a") as policy:
                    policy.write("# Project changed after consent.\n")
            env = dict(os.environ)
            env["RUST_LOG"] = "info"
            for key, directory in {"XDG_CONFIG_HOME": "config", "XDG_DATA_HOME": "data",
                                   "XDG_STATE_HOME": "state", "XDG_CACHE_HOME": "cache",
                                   "XDG_LOG_HOME": "logs"}.items():
                env[key] = str(base / directory)
            # Only the named mock model is allowed; no real provider is selected.
            try:
                command = [MAKI] + ([] if jit else ["--no-jit"]) + (["--yolo"] if yolo else [])
                if interactive or managed:
                    command += ["--exit-on-done", "-m", "mock/worker"]
                    if not trust_command:
                        command += ["Run auto_approve_probe once for this local test."]
                    responses = []
                    if managed:
                        responses = [(r"Install these packages\?[\s\S]*?\[y/N\]", b"y\n"), (r"\[y/N\]", b"y\n")]
                    elif trust_command:
                        responses = [(r"worker", b"/auto-approve-trust\r"),
                                     (r"Trust project approval policy", b"y"),
                                     (lambda: (config_dir / "auto-approve-trust.json").exists(),
                                      b"Run auto_approve_probe once for this local test.\r")]
                    elif outcome == "deny":
                        responses = [(r"Permission Required", b"y")]
                    process, answered = run_terminal(command, project, env, responses)
                    self.assertEqual(answered, len(responses), process.stdout[-10000:])
                else:
                    command += ["-p", "-m", "mock/worker", "--max-turns", "6", "--output-format", "json",
                                "Run auto_approve_probe once for this local test."]
                    process = subprocess.run(command, cwd=project, env=env, capture_output=True, text=True, timeout=25)
            finally:
                server.shutdown()
                server.server_close()
                thread.join(timeout=2)
            reviews = [r for r in requests if "You review one pending Maki tool call" in json.dumps(r)]
            logs = "\n".join(path.read_text(errors="replace") for path in base.rglob("maki.log*"))
            diagnostic = process.stdout + process.stderr + "\n" + logs[-12000:]
            self.assertEqual(process.returncode, 0, diagnostic)
            self.assertTrue(requests, diagnostic)
            if managed:
                self.assertIn(expected_commit, (config_dir / "pack-lock.json").read_text())
                self.assertTrue((base / "data/maki/site/pack-approvals.json").exists(), diagnostic)
            if trust_command:
                saved = json.loads((config_dir / "auto-approve-trust.json").read_text())
                self.assertEqual(saved["projects"][str(project.resolve())]["text"],
                                 (project / ".maki/auto-approve.toml").read_text())
            return {"executed": (project / "executed").exists(), "reviews": reviews,
                    "diagnostic": diagnostic, "requests": requests}

    def test_pending_call_is_reviewed_and_approved(self):
        result = self.run_case()
        self.assertTrue(result["executed"], result["diagnostic"])
        self.assertEqual(len(result["reviews"]), 1, result["diagnostic"])
        main = next(r for r in result["requests"] if "You review one pending Maki tool call" not in json.dumps(r))
        names = {t["function"]["name"] for t in main.get("tools", [])}
        self.assertNotIn("auto_approve_read_file", names)

    def test_explicit_allow_skips_reviewer(self):
        result = self.run_case(rule="allow")
        self.assertTrue(result["executed"], result["diagnostic"])
        self.assertEqual(len(result["reviews"]), 0)

    def test_explicit_deny_skips_reviewer(self):
        result = self.run_case(rule="deny")
        self.assertFalse(result["executed"], result["diagnostic"])
        self.assertEqual(len(result["reviews"]), 0)

    def test_reviewer_deny_reaches_headless_default_denial(self):
        result = self.run_case(outcome="deny")
        self.assertFalse(result["executed"], result["diagnostic"])
        self.assertEqual(len(result["reviews"]), 1, result["diagnostic"])

    def test_malformed_response_does_not_execute(self):
        result = self.run_case(malformed=True)
        self.assertFalse(result["executed"], result["diagnostic"])
        self.assertEqual(len(result["reviews"]), 1, result["diagnostic"])

    def test_reviewer_can_use_only_restricted_inspection_tools(self):
        result = self.run_case(inspect=True)
        self.assertTrue(result["executed"], result["diagnostic"])
        self.assertEqual(len(result["reviews"]), 2, result["diagnostic"])
        names = {tool["function"]["name"] for tool in result["reviews"][0].get("tools", [])}
        self.assertEqual(names, {"auto_approve_inspect_path", "auto_approve_read_file", "auto_approve_list_directory"})
        self.assertIn("echo harmless", json.dumps(result["reviews"][1]))

    def test_project_model_override(self):
        result = self.run_case(override=True)
        self.assertTrue(result["executed"], result["diagnostic"])
        self.assertEqual(result["reviews"][0]["model"], "reviewer")

    def test_untrusted_project_does_not_start_reviewer(self):
        result = self.run_case(override=True, trust_project=False)
        self.assertFalse(result["executed"], result["diagnostic"])
        self.assertEqual(len(result["reviews"]), 0)

    def test_changed_project_policy_requires_new_trust(self):
        result = self.run_case(override=True, changed_project=True)
        self.assertFalse(result["executed"], result["diagnostic"])
        self.assertEqual(len(result["reviews"]), 0)

    def test_interactive_human_can_approve_after_reviewer_denial(self):
        result = self.run_case(outcome="deny", interactive=True)
        self.assertTrue(result["executed"], result["diagnostic"])
        self.assertEqual(len(result["reviews"]), 1, result["diagnostic"])

    def test_managed_install_prompts_for_install_and_capabilities(self):
        result = self.run_case(managed=True)
        self.assertTrue(result["executed"], result["diagnostic"])
        self.assertEqual(len(result["reviews"]), 1, result["diagnostic"])

    def test_interactive_project_policy_confirmation(self):
        result = self.run_case(override=True, trust_project=False, interactive=True, trust_command=True)
        self.assertTrue(result["executed"], result["diagnostic"])
        self.assertEqual(result["reviews"][0]["model"], "reviewer")

    def test_timeout_returns_to_normal_gate(self):
        result = self.run_case(timeout=True)
        self.assertFalse(result["executed"], result["diagnostic"])
        self.assertEqual(len(result["reviews"]), 1, result["diagnostic"])

    def test_project_can_disable_review(self):
        result = self.run_case(project_disabled=True)
        self.assertFalse(result["executed"], result["diagnostic"])
        self.assertEqual(len(result["reviews"]), 0)

    def test_jit_runtime(self):
        result = self.run_case(inspect=True, jit=True)
        self.assertTrue(result["executed"], result["diagnostic"])
        self.assertEqual(len(result["reviews"]), 2, result["diagnostic"])

    def test_yolo_skips_review(self):
        result = self.run_case(yolo=True)
        self.assertTrue(result["executed"], result["diagnostic"])
        self.assertEqual(len(result["reviews"]), 0)

    def test_forced_human_prompt_skips_review(self):
        result = self.run_case(forced_ask=True)
        self.assertFalse(result["executed"], result["diagnostic"])
        self.assertEqual(len(result["reviews"]), 0)


if __name__ == "__main__":
    if not MAKI:
        raise SystemExit("maki must be on PATH for native integration tests")
    unittest.main(verbosity=2)
