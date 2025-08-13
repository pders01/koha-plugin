### POD style guide for hook stubs

Use this structure to keep all hook stubs consistent and skimmable.

1. Head and short description

- Use `=head3 <hook_name>`
- One or two sentences describing what the hook does. Keep any important background.

2. Context

- Add a single line starting with “Context:” to anchor when/where the hook runs.
  - Examples:
    - Context: Global JS/HTML injection into OPAC head.
    - Context: Post-CRUD biblio hook. Use to enqueue background jobs.

3. Parameter and return sections

- Wrap sections in an `=over 4` block.
- Use exact headings (no trailing colon):
  - `B<Parameters>`
  - `B<Returns>`
- List parameters with a brief type/role. Prefer inline notation over long prose.
  - Example:
    - `C<$self> - Plugin instance`
    - `C<$action> - 'create' | 'update' | 'delete'`
- Returns should be concise (e.g., “Void”, “Boolean”, “HashRef of variables”). Mention in-place mutation explicitly where applicable.

4. Keep code minimal

- Function bodies should be minimal stubs (return undef/empty where sensible).
- Don’t add business logic to the template stubs.

Example template

```pod
=head3 example_hook

Short description of what the hook does.

Context: When this hook runs and why it is used.

=over 4

=item *

B<Parameters>

=over 8

=item * C<$self> - Plugin instance

=item * C<$params> - HashRef of inputs

=back

=item *

B<Returns>

Void (explain in-place mutation if relevant)

=back
```

Notes

- These stubs are TT includes, not standalone Perl modules, so it’s normal that they lack package/use strict/1;.
- Keep paragraphs wrapped sensibly; avoid trailing whitespace.
