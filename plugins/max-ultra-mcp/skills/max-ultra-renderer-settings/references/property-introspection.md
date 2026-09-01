# Renderer Property Introspection

## What the inspection returns

`max_renderer_properties_get` executes a bounded equivalent of:

```maxscript
show renderers.current
```

It also enumerates `getPropNames renderers.current` so the response contains:

- active renderer display name;
- exact runtime class name;
- property count and property-name array;
- bounded raw `showOutput` with the values and types exposed by 3ds Max;
- total output length and a `truncated` flag.

If `truncated` is true, call the tool again with a larger `maxChars` value up to its declared limit. Do not use truncated output as proof that a property is absent; check the complete structured property-name array first.

## Building a safe property plan

For each requested renderer option:

1. Match one exact name from `properties`.
2. Read its current representation from `showOutput` or with a bounded getter.
3. Confirm the meaning, unit, valid range, and enum mapping from the renderer/version documentation or an existing verified adapter.
4. Classify it as writable, read-only, ambiguous, or unsupported.
5. Validate the requested value before embedding it as a MaxScript literal.
6. Apply a small related batch and read every property back.

Property introspection is deliberately renderer-instance based. Version strings alone are insufficient because installed hotfixes, renderer modes, and plugin builds can expose different property sets.

## Bounded setter pattern

Use `max_run_script` only after the property plan is approved. The generated script must follow this shape:

```maxscript
(
    local activeRenderer = renderers.current
    if (activeRenderer == undefined) do throw "RENDERER_UNSUPPORTED: no active renderer"
    if ((classOf activeRenderer) != ExpectedRendererClass) do throw "RENDERER_UNSUPPORTED: active renderer changed"
    local propertyName = #verifiedProperty
    if ((findItem (getPropNames activeRenderer) propertyName) == 0) do throw "RENDERER_UNSUPPORTED: property is unavailable"
    local previousValue = getProperty activeRenderer propertyName
    setProperty activeRenderer propertyName verifiedValue
    local appliedValue = getProperty activeRenderer propertyName
    #(propertyName, previousValue, appliedValue)
)
```

Replace the class, property, and value only with reviewed literals. Never use `execute`, string-built property access, or a natural-language fragment. For a multi-property operation, capture all previous values first and attempt rollback when any setter fails. Report rollback failures explicitly because renderer properties are not guaranteed to participate in the normal scene undo stack.

## Verification

After mutation:

- confirm the renderer class has not changed unexpectedly;
- read back every applied property;
- distinguish exact application from renderer-side clamping or coercion;
- re-read common render settings;
- run a bounded preview render only when requested;
- inspect the resulting image and renderer diagnostics;
- report settings that still require a real renderer-version fixture.

Do not treat successful MaxScript evaluation alone as configuration proof. The accepted evidence is the actual read-back value plus, when relevant, a successful preview result.

Official references:

- [MAXScript class and object inspector functions](https://help.autodesk.com/cloudhelp/2022/ENU/MAXScript-Help/files/3ds-Max-Objects-and-Interfaces/Identifying-and-Accessing/GUID-879ECFAD-7928-44B3-BCD7-276D53C89B52.html)
- [MAXScript renderers structure](https://help.autodesk.com/cloudhelp/2022/ENU/MAXScript-Help/files/MAXScript-Tools-and-Interaction/Interacting-with-the-3ds-Max/Render-Scene-Dialog/GUID-5984208E-B730-44F2-8D15-D4BB350F5877.html)
- [MAXScript StringStream values](https://help.autodesk.com/cloudhelp/2022/ENU/MAXScript-Help/files/MAXScript-Language-Reference/Values/Stream-Values/GUID-DB8A8E34-179F-4264-86E3-D0CD9AB836A6.html)
