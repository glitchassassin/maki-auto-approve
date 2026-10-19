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
VERSION = (ROOT / "VERSION").read_text().strip()


def lua_value(value):
    if isinstance(value, dict):
        return "{" + ", ".join("[" + json.dumps(key) + "] = " + lua_value(item)
                               for key, item in value.items()) + "}"
    if isinstance(value, (list, tuple)):
        return "{" + ", ".join(lua_value(item) for item in value) + "}"
    return json.dumps(value, ensure_ascii=False)


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
            plain = re.sub(rb"\x1b\[[0-?]*[ -/]*[@-~]", b"", output).decode(errors="replace")
            raise AssertionError(f"Maki terminal timed out at response {step}:\n" + plain[-8000:])
        returncode = process.wait(timeout=3)
        return subprocess.CompletedProcess(command, returncode, output.decode(errors="replace"), ""), step
    finally:
        os.close(master)
        if process.poll() is None:
            try:
                process.wait(timeout=2)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait(timeout=5)


class NativeTests(unittest.TestCase):
    def run_case(self, *, rule=None, outcome="allow", risk="low", authorization="high", review_response=None,
                 inspect=False, override=False,
                 malformed=False, timeout=False, project_disabled=False, jit=False,
                 yolo=False, forced_ask=False, trust_project=True, changed_project=False,
                 interactive=False, managed=False, native_trust_command=False,
                 trust_mode="session", global_options=None, project_options=None, global_disabled=False,
                 resume=False, parallel=1, reviewer_delay=0):
        requests = []
        review_activity = {"active": 0, "peak": 0}
        review_lock = threading.Lock()
        seeding = resume
        with tempfile.TemporaryDirectory(prefix="maki-auto-approve-") as temporary:
            base = Path(temporary)
            project = base / "project"
            project.mkdir()
            (project / ".git").mkdir()
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
                        with review_lock:
                            review_activity["active"] += 1
                            review_activity["peak"] = max(review_activity["peak"], review_activity["active"])
                        if reviewer_delay:
                            time.sleep(reviewer_delay)
                        if timeout:
                            time.sleep(0.4)
                        if inspect and not has_result:
                            tool = next(t["function"] for t in request["tools"] if t["function"]["name"] == "auto_approve_read_file")
                            review_id = tool["parameters"]["properties"]["review_id"]["enum"][0]
                            call = ("auto_approve_read_file", {"path": str(project / "script.sh"), "review_id": review_id})
                        else:
                            text = review_response if review_response is not None else "invalid JSON" if malformed else json.dumps({
                                "risk_level": risk, "user_authorization": authorization,
                                "outcome": outcome, "rationale": "The probe is a bounded test operation.",
                            })
                    elif seeding:
                        text = "ready to continue"
                    elif not has_result:
                        call = ("auto_approve_probe", {"value": "once"})
                    else:
                        text = "done"
                    delta = {"role": "assistant"}
                    calls = [call] if call else []
                    if call and not is_review and parallel > 1:
                        calls = [("auto_approve_probe", {"value": f"once-{i}"}) for i in range(parallel)]
                    if calls:
                        delta["tool_calls"] = [{"index": i, "id": f"call_{len(requests)}_{i}",
                            "type": "function", "function": {"name": item[0], "arguments": json.dumps(item[1])}}
                            for i, item in enumerate(calls)]
                    else:
                        delta["content"] = text
                    chunks = [
                        {"choices": [{"index": 0, "delta": delta, "finish_reason": None}]},
                        {"choices": [{"index": 0, "delta": {}, "finish_reason": "tool_calls" if calls else "stop"}]},
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
                    finally:
                        if is_review:
                            with review_lock:
                                review_activity["active"] -= 1

            server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
            server.daemon_threads = True
            thread = threading.Thread(target=server.serve_forever, daemon=True)
            thread.start()
            port = server.server_address[1]
            options = { "reviewer_timeout_ms": 100 if timeout else 5000 }
            options.update(global_options or {})
            if global_disabled:
                options["enabled"] = False
            project_options = dict(project_options or {})
            if override:
                project_options["reviewer_model"] = "mock/reviewer"
            if project_disabled:
                project_options["enabled"] = False
            native_policy = {"paths": [str(project.resolve())]} if trust_mode == "policy" and trust_project else {}
            if native_trust_command:
                native_policy = {"prompt": False}
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
  handler = function(args)
    maki.fs.write("EXECUTED", "yes")
    maki.fs.write("EXECUTED" .. "." .. args.value, "yes")
    return "probe executed"
  end,
})
maki.setup({ ui = { splash_animation = false },
  provider = { default_model = "mock/worker", allowed_models = { "mock/*" },
  max_retries = 0, max_timeout_retries = 0, connect_timeout_secs = 2 },
  net = { allowed_private_hosts = { "127.0.0.1" } },
  plugins = { ["maki-auto-approve"] = __OPTIONS__ }, trust = __TRUST__ })
'''.replace("PORT", str(port)).replace("EXECUTED", str(project / "executed"))
                .replace("__OPTIONS__", lua_value(options)).replace("__TRUST__", lua_value(native_policy)))
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
                subprocess.run(["git", "tag", "v" + VERSION], cwd=fixture_repo, check=True)
                expected_commit = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=fixture_repo, text=True).strip()
                with (config_dir / "init.lua").open("a") as init:
                    init.write('\nmaki.pack.add({{ src = ' + json.dumps(str(fixture_repo)) +
                               ', name = "maki-auto-approve", version = ' + json.dumps("v" + VERSION) + ' }})\n')
            if rule:
                (config_dir / "permissions.toml").write_text('[auto_approve_probe]\n' + rule + '=["*"]\n')
            project_marker = project / "project-config-loaded"
            if project_options:
                (project / ".maki/plugin.toml").write_text("[permissions]\nfs_write=true\n")
                (project / ".maki/init.lua").write_text(
                    "maki.fs.write(" + lua_value(str(project_marker)) + ', "loaded")\n' +
                    'maki.setup({plugins={["maki-auto-approve"]=' + lua_value(project_options) + '}})\n')
            env = dict(os.environ)
            env["RUST_LOG"] = "info"
            for key, directory in {"XDG_CONFIG_HOME": "config", "XDG_DATA_HOME": "data",
                                   "XDG_STATE_HOME": "state", "XDG_CACHE_HOME": "cache",
                                   "XDG_LOG_HOME": "logs"}.items():
                env[key] = str(base / directory)
            if project_options and trust_project and trust_mode == "persisted":
                subprocess.run([MAKI, "trust", "add", "--yes"], cwd=project, env=env,
                               check=True, capture_output=True, text=True, timeout=10)
            if changed_project:
                with (project / ".maki/init.lua").open("a") as init:
                    init.write("-- Project edited after native folder trust.\n")
            # Only the named mock model is allowed; no real provider is selected.
            try:
                command = [MAKI] + ([] if jit else ["--no-jit"]) + (["--yolo"] if yolo else [])
                if project_options and trust_project and trust_mode == "session" and not native_trust_command:
                    command += ["--trust"]
                if resume:
                    seed = subprocess.run(command + ["-p", "-m", "mock/worker", "--output-format", "json",
                        "Run auto_approve_probe once for this local test."], cwd=project, env=env,
                        capture_output=True, text=True, timeout=25)
                    self.assertEqual(seed.returncode, 0, seed.stdout + seed.stderr)
                    session_id = json.loads(seed.stdout)["session_id"]
                    self.assertFalse((project / "executed").exists())
                    seeding = False
                    fresh_input = base / "fresh-input"
                    with (config_dir / "init.lua").open("a") as init:
                        init.write('''
maki.api.set_slot("agent.user_message", function(prev, message, ctx)
  if message.source ~= "plugin" then maki.fs.write(__FRESH_INPUT__, "unexpected") end
  return prev(message, ctx)
end)
maki.api.register_command({ name = "/auto-approve-test-wake", description = "Resume test work using an observation",
  handler = function()
    maki.session.notify("Continue the pending work.", { session = maki.session.current(), wake = true })
  end,
})
'''.replace("__FRESH_INPUT__", lua_value(str(fresh_input))))
                    process, answered = run_terminal(command + ["--resume", session_id, "--exit-on-done", "-m", "mock/worker"],
                        project, env, [(r"ready to continue", b"/auto-approve-test-wake\r")])
                    self.assertEqual(answered, 1, process.stdout[-10000:])
                    self.assertFalse(fresh_input.exists(), "The resumed test must not send a fresh human message")
                elif interactive or managed:
                    command += ["--exit-on-done", "-m", "mock/worker"]
                    if not native_trust_command:
                        command += ["Run auto_approve_probe once for this local test."]
                    responses = []
                    if managed:
                        responses = [(r"Install these packages\?[\s\S]*?\[y/N\]", b"y\n"), (r"\[y/N\]", b"y\n")]
                    elif native_trust_command:
                        # Project configuration loads before the reloaded TUI is
                        # ready for input. Wait for its new prompt after /trust.
                        responses = [(r"\[restricted\]", b"/trust\r"),
                                     (r"Ask maki to [^\r\n]*?\.\.\.",
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
            return {"executed": (project / "executed").exists(), "reviews": reviews,
                    "executed_calls": len(list(project.glob("executed.*"))),
                    "peak_reviews": review_activity["peak"], "logs": logs,
                    "diagnostic": diagnostic, "requests": requests, "project_loaded": project_marker.exists()}

    def test_concurrent_calls_queue_and_all_execute_with_correlated_logs(self):
        for limit in (1, 2):
            with self.subTest(limit=limit):
                result = self.run_case(parallel=4, reviewer_delay=0.2,
                                       global_options={"reviewer_max_concurrent": limit})
                self.assertEqual(result["executed_calls"], 4, result["diagnostic"])
                self.assertEqual(len(result["reviews"]), 4, result["diagnostic"])
                self.assertEqual(result["peak_reviews"], limit, result["diagnostic"])
                lines = [line for line in result["logs"].splitlines() if "auto-approve: session=" in line]
                self.assertEqual(sum(": queued" in line for line in lines), 4 - limit, result["diagnostic"])
                for i in range(4):
                    call_lines = [line for line in lines if f"tool_call_id=call_1_{i} " in line]
                    self.assertEqual(sum(": started" in line for line in call_lines), 1, result["diagnostic"])
                    self.assertEqual(sum(": approved" in line for line in call_lines), 1, result["diagnostic"])
                    self.assertTrue(all(" task=" in line for line in call_lines), result["diagnostic"])
                # Neither the pending input nor its permission scope is logged.
                self.assertFalse(any("once-" in line for line in lines), result["diagnostic"])
                queued = [re.search(r"tool_call_id=(\S+)", line)[1] for line in lines if ": queued" in line]
                started = [re.search(r"tool_call_id=(\S+)", line)[1] for line in lines if ": started" in line]
                self.assertEqual(started[limit:], queued, result["diagnostic"])

    def test_fallback_logs_include_the_reviewed_tool_call_id(self):
        result = self.run_case(outcome="deny")
        self.assertRegex(result["logs"], r"auto-approve: session=\S+ task=\S+ tool_call_id=call_1_0 tool=auto_approve_probe: human review")

    def test_queued_timeout_returns_to_normal_gate(self):
        result = self.run_case(parallel=4, reviewer_delay=0.4,
                               global_options={"reviewer_max_concurrent": 1, "reviewer_timeout_ms": 100})
        self.assertFalse(result["executed"], result["diagnostic"])
        lines = [line for line in result["logs"].splitlines() if "auto-approve: session=" in line]
        self.assertEqual(sum(": queued" in line for line in lines), 3, result["diagnostic"])
        self.assertEqual(sum(": human review" in line for line in lines), 4, result["diagnostic"])
        self.assertTrue(any("timed out while queued" in line for line in lines), result["diagnostic"])

    def test_pending_call_is_reviewed_and_approved(self):
        result = self.run_case()
        self.assertTrue(result["executed"], result["diagnostic"])
        self.assertEqual(len(result["reviews"]), 1, result["diagnostic"])
        main = next(r for r in result["requests"] if "You review one pending Maki tool call" not in json.dumps(r))
        names = {t["function"]["name"] for t in main.get("tools", [])}
        self.assertNotIn("auto_approve_read_file", names)
        system = "\n".join(m["content"] for m in result["reviews"][0]["messages"] if isinstance(m.get("content"), str))
        self.assertIn((ROOT / "vendor/codex/policy.md").read_text(), system)
        self.assertIn('Allow `low` and `medium` risk actions regardless of user authorization', system)

    def test_resumed_chat_reuses_history_without_fresh_user_input(self):
        result = self.run_case(resume=True)
        self.assertTrue(result["executed"], result["diagnostic"])
        self.assertEqual(len(result["reviews"]), 1, result["diagnostic"])
        prompt = next(m["content"] for m in result["reviews"][0]["messages"] if m["role"] == "user")
        payload = json.loads(prompt)
        self.assertEqual([entry["text"] for entry in payload["user_instructions"]],
                         ["Run auto_approve_probe once for this local test."])
        self.assertIn("Continue the pending work.", json.dumps(payload["untrusted_conversation_evidence"]))

    def test_codex_low_and_medium_risk_allows_do_not_require_clear_authorization(self):
        for risk in ("low", "medium"):
            for authorization in ("unknown", "low"):
                with self.subTest(risk=risk, authorization=authorization):
                    result = self.run_case(risk=risk, authorization=authorization)
                    self.assertTrue(result["executed"], result["diagnostic"])
                    self.assertEqual(len(result["reviews"]), 1, result["diagnostic"])

    def test_codex_minimal_allow_response(self):
        result = self.run_case(review_response='{"outcome":"allow"}')
        self.assertTrue(result["executed"], result["diagnostic"])
        self.assertEqual(len(result["reviews"]), 1, result["diagnostic"])

    def test_codex_optional_fields_and_wrapped_json(self):
        for response in ['{"outcome":"allow","risk_level":null,"user_authorization":null,"rationale":null}',
                         'Decision:\n```json\n{"outcome":"allow"}\n```',
                         '{"outcome":"allow","extra":true,"rationale":"  "}',
                         '{"outcome":"allow","extra":1,"extra":2}']:
            with self.subTest(response=response):
                result = self.run_case(review_response=response)
                self.assertTrue(result["executed"], result["diagnostic"])

    def test_codex_invalid_assessment_fields_fall_back(self):
        for response in ['{"risk_level":"low"}', '{"outcome":"allow","risk_level":7}',
                         '{"outcome":"allow","user_authorization":false}',
                         '{"outcome":"allow","rationale":true}',
                         '{"outcome":"deny","outcome":"allow"}',
                         r'{"outcome":"deny","out\u0063ome":"allow"}']:
            with self.subTest(response=response):
                result = self.run_case(review_response=response)
                self.assertFalse(result["executed"], result["diagnostic"])

    def test_high_risk_authorization_denial_falls_back_to_interactive_prompt(self):
        result = self.run_case(outcome="deny", risk="high", authorization="unknown", interactive=True)
        self.assertTrue(result["executed"], result["diagnostic"])
        self.assertEqual(len(result["reviews"]), 1, result["diagnostic"])

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

    def test_untrusted_project_uses_global_model_and_rubric(self):
        result = self.run_case(override=True, trust_project=False,
            global_options={"policy_rubric": "GLOBAL_RUBRIC"}, project_options={"policy_rubric": "PROJECT_RUBRIC"})
        self.assertTrue(result["executed"], result["diagnostic"])
        self.assertEqual(result["reviews"][0]["model"], "worker")
        self.assertIn("GLOBAL_RUBRIC", json.dumps(result["reviews"][0]))
        self.assertNotIn("PROJECT_RUBRIC", json.dumps(result["reviews"][0]))
        self.assertFalse(result["project_loaded"])

    def test_persisted_native_trust_loads_project_settings(self):
        result = self.run_case(override=True, trust_mode="persisted")
        self.assertTrue(result["executed"], result["diagnostic"])
        self.assertEqual(result["reviews"][0]["model"], "reviewer")

    def test_native_trust_policy_loads_project_settings(self):
        result = self.run_case(override=True, trust_mode="policy")
        self.assertTrue(result["executed"], result["diagnostic"])
        self.assertEqual(result["reviews"][0]["model"], "reviewer")

    def test_project_edit_uses_existing_native_folder_trust(self):
        result = self.run_case(override=True, changed_project=True, trust_mode="persisted")
        self.assertTrue(result["executed"], result["diagnostic"])
        self.assertEqual(result["reviews"][0]["model"], "reviewer")

    def test_project_overrides_merge_with_global_package_options(self):
        result = self.run_case(override=True, inspect=True,
            global_options={"policy_rubric": "GLOBAL_ONLY_RUBRIC"},
            project_options={"reviewer_timeout_ms": 3000})
        self.assertTrue(result["executed"], result["diagnostic"])
        self.assertEqual(result["reviews"][0]["model"], "reviewer")
        self.assertIn("GLOBAL_ONLY_RUBRIC", json.dumps(result["reviews"][0]))

    def test_trusted_project_can_replace_rubric(self):
        result = self.run_case(global_options={"policy_rubric": "GLOBAL_RUBRIC"},
            project_options={"policy_rubric": "PROJECT_RUBRIC"})
        self.assertTrue(result["executed"], result["diagnostic"])
        self.assertIn("PROJECT_RUBRIC", json.dumps(result["reviews"][0]))
        self.assertNotIn("GLOBAL_RUBRIC", json.dumps(result["reviews"][0]))

    def test_global_package_toggle_disables_review(self):
        result = self.run_case(global_disabled=True)
        self.assertFalse(result["executed"], result["diagnostic"])
        self.assertEqual(len(result["reviews"]), 0)

    def test_untrusted_project_cannot_change_package_toggle(self):
        result = self.run_case(project_disabled=True, trust_project=False)
        self.assertTrue(result["executed"], result["diagnostic"])
        self.assertEqual(len(result["reviews"]), 1)

    def test_untrusted_project_cannot_enable_globally_disabled_package(self):
        result = self.run_case(global_disabled=True, trust_project=False, project_options={"enabled": True})
        self.assertFalse(result["executed"], result["diagnostic"])
        self.assertEqual(len(result["reviews"]), 0)

    def test_invalid_untrusted_project_options_are_ignored(self):
        result = self.run_case(trust_project=False, project_options={"reviewer_model": 7})
        self.assertTrue(result["executed"], result["diagnostic"])
        self.assertEqual(result["reviews"][0]["model"], "worker")

    def test_invalid_native_options_leave_normal_approval_in_control(self):
        for options in [{"reviewer_timeout_ms": 60000}, {"reviewer_model": 7}, {"unknown": True}]:
            with self.subTest(options=options):
                result = self.run_case(global_options=options)
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

    def test_native_trust_command_loads_project_options(self):
        result = self.run_case(override=True, trust_project=False, interactive=True, native_trust_command=True)
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
