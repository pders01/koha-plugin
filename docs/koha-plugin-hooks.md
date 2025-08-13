### Koha plugin hooks: coverage and usage

This document summarizes Koha’s plugin hooks and whether the `koha-plugin` scaffold provides a template for each. Use it to decide which hooks your plugin can implement out of the box and where you may need to add templates.

Legend

- **Supported**: A corresponding template exists under `templates/hooks/` (or related) in this scaffold
- **Missing**: No template yet; add if required by your plugin

#### Core hooks

- **report**: Run a report from the plugins home page. — Supported (`templates/hooks/report.pl`)
- **tool**: Run a tool page from the plugins home page. — Supported (`templates/hooks/tool.pl`)
- **to_marc**: Convert arbitrary files to MARC for the staging tool. — Supported (`templates/hooks/to_marc.pl`)
- **edifact**: Add a vendor to EDIFACT module. — Missing
- **opac_online_payment**: Add a payment method in OPAC account. — Supported (`templates/hooks/opac_online_payment.pl` with `opac_online_payment_begin.pl`/`end.pl`)
- **intranet_catalog_biblio_enhancements_toolbar_button**: Add a button to intranet biblio toolbar. — Supported (`templates/hooks/intranet_catalog_biblio_enhancements_toolbar_button.pl`)
- **api_namespace + api_routes**: Extend Koha REST API via plugins. — Supported (`templates/hooks/api_namespace.pl`, `templates/hooks/api_routes.pl`)
- **static_routes**: Serve static files via API. — Supported (`templates/hooks/static_routes.pl`)
- **opac_head + opac_js**: Add CSS/JS to OPAC globally. — Supported (`templates/hooks/opac_head.pl`, `templates/hooks/opac_js.pl`)
- **intranet_head + intranet_js**: Add CSS/JS to staff globally. — Supported (`templates/hooks/intranet_head.pl`, `templates/hooks/intranet_js.pl`)
- **after_biblio_action**: Post-CRUD biblio hook. — Missing
- **after_item_action**: Post-CRUD item hook. — Missing
- **check_password**: Validate password strength on set/update. — Missing
- **intranet_catalog_biblio_tab**: Add tabs to intranet biblio detail. — Supported (`templates/hooks/intranet_catalog_biblio_tab.pl`)
- **opac_online_payment_threshold**: Minimum allowed payment amount. — Missing
- **before_send_messages**: Pre-process messages before sending. — Supported (`templates/hooks/before_send_messages.pl`)
- **ill_availability_services**: Intercept ILL creation and show availabilities. — Missing
- **ill_backend**: Register ILL backend (returns backend name). — Missing
- **new_ill_backend**: Return ILL backend class. — Missing
- **opac_detail_xslt_variables**: Add variables for OPAC detail XSLT. — Supported (`templates/hooks/opac_detail_xslt_variables.pl`)
- **opac_results_xslt_variables**: Add variables for OPAC results XSLT. — Supported (`templates/hooks/opac_results_xslt_variables.pl`)
- **after_hold_create**: After a hold is placed. — Missing
- **after_circ_action**: After add renewal/issue/return. — Missing
- **cronjob_nightly**: Run daily background tasks. — Supported (`templates/hooks/cronjob_nightly.pl`)
- **item_barcode_transform**: Transform scanned item barcode. — Supported (`templates/hooks/item_barcode_transform.pl`)
- **patron_barcode_transform**: Transform scanned patron barcode. — Supported (`templates/hooks/patron_barcode_transform.pl`)
- **after_authority_action**: After add/mod/del authority. — Missing
- **after_hold_action**: On hold status changes (fill, cancel, ...). — Missing
- **background_tasks**: Register plugin background tasks. — Supported (`templates/hooks/background_tasks.pl`)
- **after_recall_action**: On recall actions. — Missing
- **after_account_action**: On account actions. — Missing
- **patron_generate_userid**: Generate `userid` on patron creation. — Missing
- **intranet_cover_images**: Provide cover images in staff. — Missing
- **opac_cover_images**: Provide cover images in OPAC. — Missing
- **patron_consent_type**: Add consent type for OPAC account page. — Missing
- **template_include_paths**: Add Template::Toolkit include paths. — Missing
- **before_biblio_action**: Pre-CRUD biblio hook. — Missing
- **auth_client_get_user**: Map authenticated user to patron data. — Missing
- **transform_prepared_letter**: Modify prepared letter data before return. — Supported (`templates/hooks/transform_prepared_letter.pl`)
- **framework_defaults_override**: Fine-grained framework defaults. — Missing
- **before_orderline_create**: Before creating orderline from MARC file. — Missing
- **overwrite_calc_fine**: Customize graduated fine calculation. — Missing
- **elasticsearch_to_document**: Modify document sent to Elasticsearch. — Missing
- **notices_content**: Add data to notices context. — Missing

Additional methods seen in Koha source

- **opac_online_payment_begin/end**: Lifecycle wrappers for OPAC payments — Supported (`templates/hooks/opac_online_payment_begin.pl`, `..._end.pl`)
- **provides_api**: Used by ILL metadata enrichment (availability) — Missing

#### Non-hook scripts/templates included in scaffold

- `templates/hooks/install.pl`, `uninstall.pl`, `upgrade.pl`: Lifecycle scripts
- `templates/hooks/admin.pl`: Optional plugin admin page
- `templates/sites/action.tt`: Minimal TT page template
- `templates/PLUGIN.yml`: Plugin metadata template

#### Next steps to reach full coverage

- Add new templates under `templates/hooks/` for the hooks marked Missing.
- Update `templates/[a].pm.tt` to include empty stub methods for new hooks as desired.
- Consider adding test coverage for hook discovery and minimal execution.

Reference

- Kitchen Sink plugin implements most hooks; review it for examples.
- Grep in Koha for `GetPlugins({ method => '...' })` to discover new/changed hooks.

#### Plugin background jobs

Requirements

- Your plugin metadata must include a `namespace` key (`$plugin->get_metadata->{namespace}`).
- Implement `background_tasks` to map task codes to implementing classes:

```perl
sub background_tasks {
    return {
        foo => 'MyPlugin::Class::Foo',
        bar => 'MyPlugin::Class::Bar',
    };
}
```

Caveats

- No default template for job detail views yet.
- After installing a plugin that registers background tasks, restart `background_jobs_worker.pl` processes; they cache plugin code and task mappings.

#### Under development hooks (reference)

- **addbiblio_check_record**: Validate MARC on save; return values block save.
- **capture_raw_password**: Capture raw passwords on create/edit.
- **checkpw**: Authentication plugins.
- **after_patron_action**: After patron create/modify/delete.
- **object_store_pre/post**: Around `Koha::Object` store.
- **before_authority_action**: Pre add/mod/del authority.
- **before_index_action**: Before ES index update on biblio records.

---

Last updated: 2025-08-13
