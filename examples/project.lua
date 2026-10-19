-- Merge into <project>/.maki/init.lua. Maki's folder trust controls loading it.
-- Omitted options inherit global values. No extra plugin trust step is needed.
maki.setup({
  plugins = {
    ["maki-auto-approve"] = {
      reviewer_timeout_ms = 30000,
      inspection_max_file_bytes = 32768,
      -- reviewer_model = "provider/model-id",
      -- policy_rubric = [=[Your replacement Guardian security policy.]=],
      -- enabled = false, -- Disable the package in this trusted project.
    },
  },
})
