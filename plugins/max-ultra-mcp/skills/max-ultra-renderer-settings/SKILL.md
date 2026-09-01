---
name: max-ultra-renderer-settings
description: Inspect and configure the active 3ds Max renderer through Max Ultra MCP using real runtime properties. Use for Corona, V-Ray, Arnold, Scanline, or plugin-renderer resolution, sampling, GI, denoising, displacement, output, VFB, and quality settings. Do not use for merely starting or stopping an already-configured render.
---

# Max Ultra Renderer Settings

Configure the renderer from observed capabilities and properties, never from a guessed version-specific property name. Runtime introspection is the source of truth for what the active renderer instance exposes; official renderer documentation is still required to interpret plugin-specific enum values and side effects.

Read [references/property-introspection.md](references/property-introspection.md) before changing renderer-specific properties.

## Required workflow

1. Call `max_list_instances` and select explicitly when several Max instances are connected.
2. Call `max_get_info`, `max_capabilities`, and `max_render_settings_get`. Record Max version, renderer display name/class, plugin hints, production resolution, frame, and output.
3. Call `max_renderer_properties_get` before planning any renderer-specific change. Inspect both the structured `properties` list and bounded `showOutput` produced by `show renderers.current`.
4. Convert the user's goal into a property plan. For every setting record the exact runtime property name, observed value/type, desired value, evidence for its meaning, and whether the change is common, renderer-specific, unsupported, or ambiguous.
5. Use `max_render_settings_set` for common production width, height, frame, and output-path changes.
6. For an exposed renderer-specific property without a semantic adapter, use one bounded `max_run_script` operation that verifies the active renderer class, checks the property, captures the previous value, sets the validated target, reads it back, and returns before/after evidence.
7. Re-run `max_renderer_properties_get` and `max_render_settings_get` after applying changes. Report exact `applied`, `unchanged`, `unsupported`, and `warnings` lists.
8. Start a preview or final render only when requested. Use `max_render_start`, `max_render_wait`, and `max_render_get_result` so status and cancellation remain available.

## Planning rules

- Separate scene settings from per-machine renderer preferences. Do not modify system-wide or user-profile settings unless explicitly requested.
- Preserve the active renderer unless the user requests a renderer change and an installed, verified class is available.
- Do not infer that similarly named Corona, V-Ray, Arnold, or Scanline properties have equivalent units, ranges, enums, or effects.
- A property appearing in `showOutput` proves discoverability, not that it is writable or safe. Verify read/write behavior and the resulting value.
- Treat sampling, GI, denoising, displacement, memory limits, color management, VFB, and interactive-render settings as renderer-specific unless a semantic tool explicitly owns them.
- Choose quality settings from the user's output type, resolution, noise/time budget, animation/still intent, and hardware constraints. Do not apply an opaque universal preset.
- Keep the inspection output in the live MCP response. It may contain scene paths or plugin data and must not be copied into repository documentation, fixtures, or logs.

## Boundaries

- Do not generate a setter from raw user prose.
- Do not use substring matching to decide which property to mutate when multiple names are plausible.
- Do not claim a property was applied until read-back confirms the actual value.
- Do not silently skip an unsupported property or replace it with an unrelated setting.
- Do not edit plugin configuration files or Windows registry entries as part of ordinary scene configuration.
- Do not save the scene unless the user explicitly requests it.
