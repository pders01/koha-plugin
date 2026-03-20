## Koha Plugin Hooks Reference

All hooks listed below have templates in `templates/hooks/` and are selectable during `koha-plugin init`. Hooks are organized by category, matching the order shown in the selection UI.

### Lifecycle

| Hook | Description | Returns |
|------|-------------|---------|
| `install` | One-time setup on first install (e.g., create tables) | Boolean (1 = success) |
| `upgrade` | Run on version upgrade (e.g., ALTER TABLE) | Boolean (1 = success) |
| `uninstall` | Cleanup before removal (e.g., drop tables) | Boolean |

### UI Pages

| Hook | Description | Generates |
|------|-------------|-----------|
| `admin` | Admin-only entry point from Admin page | `admin.tt` page template |
| `configure` | Plugin settings and configuration | `configure.tt` page template |
| `report` | Report generation (HTML/CSV) | `report.tt` page template |
| `tool` | Tool entry point from Tools page | `tool.tt` page template |

When selected during `init`, the corresponding `.tt` template is automatically generated.

### API & Static Files

| Hook | Description | Notes |
|------|-------------|-------|
| `api` | Extend the Koha REST API | Bundle: emits `api_namespace` + `api_routes`, creates empty `openapi.json`. Use `koha-plugin add api-route` to compose routes. |
| `static` | Serve static files through the API | Creates `staticapi.json` from template. Use `koha-plugin staticapi` to regenerate. |

The `api_routes` hook reads `openapi.json` via `$self->mbf_read('openapi.json')`. The spec follows OpenAPI 2.0 (Swagger) — paths only, not a full spec. Koha merges it into its own API definition.

### Staff Interface

| Hook | Description | Returns |
|------|-------------|---------|
| `intranet_head` | Inject CSS into staff interface (all pages) | HTML string |
| `intranet_js` | Inject JavaScript into staff interface (all pages) | HTML string |
| `intranet_catalog_biblio_enhancements_toolbar_button` | Add button to biblio detail toolbar | HTML string |
| `intranet_catalog_biblio_tab` | Add tabs to biblio detail page | ArrayRef of `Koha::Plugins::Tab` |
| `intranet_cover_images` | Provide cover images in staff interface | See [BDS Covers plugin](https://github.com/PTFS-Europe/koha-plugin-addBDSCovers) |

### OPAC

| Hook | Description | Returns |
|------|-------------|---------|
| `opac_head` | Inject CSS into OPAC (all pages) | HTML string |
| `opac_js` | Inject JavaScript into OPAC (all pages) | HTML string |
| `opac_detail_xslt_variables` | Add variables for OPAC detail XSLT | HashRef |
| `opac_results_xslt_variables` | Add variables for OPAC results XSLT | HashRef |
| `opac_cover_images` | Provide cover images in OPAC | See [BDS Covers plugin](https://github.com/PTFS-Europe/koha-plugin-addBDSCovers) |
| `opac_online_payment` | Bundle: payment + begin/end/threshold | See below |

**OPAC Payment bundle:** Selecting `opac_online_payment` includes all four payment hooks:
- `opac_online_payment` — enable payment capability
- `opac_online_payment_begin` — initialize payment
- `opac_online_payment_end` — finalize payment
- `opac_online_payment_threshold` — minimum allowed payment amount

### Patron

| Hook | Description | Returns |
|------|-------------|---------|
| `check_password` | Custom password strength validation | Boolean or error message |
| `patron_barcode_transform` | Transform patron barcodes on scan | Modified barcode (in-place) |
| `patron_generate_userid` | Generate userid on patron creation | String |
| `patron_consent_type` | Add consent type for OPAC account page | HashRef |
| `auth_client_get_user` | Map authenticated user to patron data | Patron data |

### Catalog CRUD

| Hook | Description | Receives |
|------|-------------|----------|
| `before_biblio_action` | Before biblio create/update/delete | `$action`, `$biblio` |
| `after_biblio_action` | After biblio create/update/delete | `$action`, `$biblio` |
| `after_item_action` | After item create/update/delete | `$action`, `$item` |
| `after_authority_action` | After authority create/update/delete | `$action`, `$authority` |

### Circulation

| Hook | Description |
|------|-------------|
| `after_circ_action` | After add renewal, issue, or return |
| `after_hold_create` | After a hold is placed |
| `after_hold_action` | On hold status changes (fill, cancel, suspend, resume, transfer, waiting) |
| `after_recall_action` | On recall actions |
| `after_account_action` | On account actions (payment, writeoff, etc.) |

### Notices & Messaging

| Hook | Description | Returns |
|------|-------------|---------|
| `notices_content` | Add data to notices template context | HashRef |
| `transform_prepared_letter` | Modify letter data before delivery | Modified letter |
| `before_send_messages` | Pre-process messages before sending | Void |

### ILL (Interlibrary Loan)

| Hook | Description | Returns |
|------|-------------|---------|
| `ill_backend` | Register as an ILL backend | String (backend name) |
| `new_ill_backend` | Return ILL backend class | Class name or ref |
| `ill_availability_services` | Intercept ILL creation, show availabilities | Service data |

`ill_backend` and `new_ill_backend` target different ILL framework versions. Most new plugins should implement both.

### Background & Scheduling

| Hook | Description | Returns |
|------|-------------|---------|
| `background_tasks` | Register custom background job types | HashRef mapping task name to class |
| `cronjob_nightly` | Execute tasks via `plugins_nightly.pl` | Void |

**Note:** After installing a plugin with `background_tasks`, restart `background_jobs_worker.pl` — it caches plugin code.

### Miscellaneous

| Hook | Description |
|------|-------------|
| `edifact` | Add vendor to EDIFACT module |
| `to_marc` | Convert arbitrary files to MARC from staging tool |
| `item_barcode_transform` | Transform item barcodes on scan |
| `template_include_paths` | Add Template::Toolkit include paths |
| `framework_defaults_override` | Fine-grained framework defaults |
| `before_orderline_create` | Before creating orderline from MARC file |
| `overwrite_calc_fine` | Customize graduated fine calculation |
| `elasticsearch_to_document` | Modify document before sending to Elasticsearch |

### Under Development (not yet in stable Koha)

These hooks exist in Koha source but are not yet in a stable release:
- `addbiblio_check_record` — validate MARC on save
- `checkpw` — authentication plugins
- `after_patron_action` — after patron create/modify/delete
- `object_store_pre/post` — around `Koha::Object` store
- `before_authority_action` — pre add/mod/del authority
- `before_index_action` — before ES index update

### References

- [Kitchen Sink plugin](https://github.com/bywatersolutions/dev-koha-plugin-kitchen-sink) — implements every hook
- [Koha wiki: Plugin Hooks](https://wiki.koha-community.org/wiki/Koha_Plugin_Hooks) — canonical hook list
- [LMSCloud plugin utils](https://github.com/LMSCloudPaulD/koha-plugin-lmscloud-util) — shared utilities for migrations, pages, i18n
