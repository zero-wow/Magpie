# Magpie development

- Treat this checkout as the authoritative source. Keep the installed game copy separate.
- Deploy complete, validated runtime files to a folder named `Magpie` under the selected Retail client's `Interface/AddOns` directory. `Magpie.toc` must match that folder.
- Keep the addon functional without Waffle House or EllesmereUI. Optional integrations may enhance appearance or migrate existing settings.
- Preserve `VignetteRadarDB`, existing binding identifiers, API names, and slash aliases for compatibility. These internal names are intentional.
- Keep `Bindings.xml` at the addon root and out of the TOC.
