# Godot in the Claude Code workflow

`.github/workflows/claude.yml` cannot be edited by the Claude GitHub App, so a
maintainer must apply this change by hand. It lets Claude run headless Godot
tests (e.g. `godot --headless -s scripts/test198_dash.gd`).

Add before the "Run Claude Code" step:

```yaml
      - name: Install Godot
        run: tools/ci/install-godot.sh 4.5.1
```

And allow the commands in the action's `claude_args`:

```yaml
          claude_args: |
            --allowed-tools "Bash(godot:*),Bash(xvfb-run:*),Bash(ffmpeg:*),Read"
```

Optional: `timeout-minutes: 30` on the job. For screenshots/video, also install
`xvfb ffmpeg libgl1-mesa-dri` via apt and run Godot under `xvfb-run`.

Images in issues are downloaded by the action automatically; just keep `Read` allowed.
