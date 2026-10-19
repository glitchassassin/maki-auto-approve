-- Merge this into the existing maki.setup() call in your global init.lua.
maki.setup({
  plugins = {
    ["maki-auto-approve"] = {
      enabled = true, -- Native Maki package toggle; false leaves normal approvals.
      reviewer_model = "", -- Inherit the calling model; optional "provider/model-id".
      reviewer_thinking = "", -- Inherit; off/minimal/low/medium/high/xhigh/max/adaptive.
      reviewer_timeout_ms = 45000, -- 100–55000; includes queue time within Maki's 60-second hook window.
      reviewer_max_inspections = 8, -- 1–32.
      reviewer_max_concurrent = 2, -- 1–8; excess calls wait in FIFO order.
      context_max_messages = 40, -- 1–200; recent conversation evidence.
      context_max_bytes = 48000, -- 2048–200000.
      context_max_user_bytes = 16000, -- 512–64000; user turns from available history.
      inspection_enabled = true,
      inspection_max_file_bytes = 65536, -- 256–262144.
      inspection_max_directory_entries = 100, -- 1–1000.
      logging_history_size = 50, -- 1–200.
      -- Omit policy_rubric to use Codex Guardian's default security policy.
      -- policy_rubric = [=[Your replacement Guardian security policy.]=],
    },
  },
})
