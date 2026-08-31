# UI automation rollout example

This deterministic rollout demonstrates running a script and programmatically operating its controls.

Example agent request:

```text
Use Max Ultra MCP to execute test-ui-rollout.ms in the selected 3ds Max.
Wait for the window titled "Max Ultra MCP UI Automation Test".
Inspect its controls, set the Value field to "controlled by MCP", invoke the
"Apply with MCP" button, then inspect the window again and confirm that the
result label contains "Result: controlled by MCP". Do not use screen coordinates.
```

Expected sequence:

1. `max_run_script_file` with the absolute path to `test-ui-rollout.ms` and `activity: "Open UI automation test rollout"`.
2. `max_ui_wait` with `window.name = "Max Ultra MCP UI Automation Test"`.
3. `max_ui_inspect` to discover the edit and button selectors.
4. `max_ui_set_value` for the edit control.
5. `max_ui_invoke` for the button.
6. `max_ui_inspect` or `max_ui_find` to verify the result label.
7. `max_ui_capture_window` with the exact returned `window.hwnd` to capture only this dialog.
8. `max_ui_diagnostics` with the same HWND when native WinForms geometry or embedded WebBrowser metrics are needed.

The external UI Automation helper revalidates that every selected element belongs to the chosen `3dsmax.exe` PID. This example intentionally does not rely on localized Max menus, global screen coordinates, or toolbar layout.

The automated `tests/ui-automation-helper-test.ps1` fixture launches a temporary synthetic process named `3dsmax.exe`, verifies the direct HWND PNG path and bounded native WinForms tree, then closes the fixture and removes its temporary files. It never launches 3ds Max or touches a scene.
