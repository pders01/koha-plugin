# Bug TBD-0007: Add `messaging_preferences` plugin hook

## Subject

`Bug TBD: Add messaging_preferences plugin hook to register patron message attributes`

## Summary

Patron messaging preferences live across three lookup tables (`message_attributes`, `message_transports`, `borrower_message_preferences`) and are rendered through a hardcoded SWITCH/CASE label ladder in `opac-messaging.tt` and `members/messaging.tt`. Plugins that want a new opt-in attribute today must:

1. INSERT rows into `message_attributes` and `message_transports` on install.
2. Manage upgrades, additions, and removals manually.
3. Inject row labels via `intranet_js` / `opac_js` because `<span>Unknown</span>` falls through the SWITCH/CASE.

This patch adds a `messaging_preferences` hook so a plugin returns a declarative spec; core handles registration, label rendering, and lifecycle.

## Coding guideline compliance

- **PERL10** — registration code uses `C4::Context->dbh` internally; no `$dbh` parameter.
- **PERL15** — registry lives in `Koha::Patron::MessagePreference::Attributes` (existing module).
- **PERL30** — `Koha::Plugins->call('messaging_preferences', \%context)` passes a reference.
- **PERL31** — `use Koha::Plugins;` at the top of `Koha/Patron/MessagePreference/Attributes.pm`.

## Rationale

The existing data layer is already open (varchar `message_name`, unique key, no enum), but every consumer downstream (form template label, `EnqueueLetter` wiring, admin UI) is closed against unknown attributes. Plugins that try to use it ship two-injector workarounds — one for staff, one for OPAC — to relabel the rows. Centralising registration via a single declarative hook eliminates the SQL lifecycle and the JS injection.

## Files touched

- `Koha/Plugins/Base.pm` — call `_sync_messaging_preferences` on install / upgrade and `_drop_messaging_preferences` on uninstall.
- `Koha/Patron/MessagePreference/Attributes.pm` — read plugin attributes alongside core ones; surface their labels.
- `koha-tmpl/opac-tmpl/bootstrap/en/modules/opac-messaging.tt` and the matching staff template — replace the SWITCH/CASE ladder with `[% messaging_preference.label | html %]` after the include sets it from the registry.
- `t/db_dependent/Koha/Patron/MessagePreference.t` — coverage.

## Hook signature

```perl
sub messaging_preferences {
    my ($self) = @_;
    return [
        {
            message_name => 'Roster_Reminder',
            label        => 'Staff roster shift reminder',
            takes_days   => 1,
            transports   => [
                { type => 'email', letter_module => 'circulation', letter_code => 'STAFFROSTER_REMINDER' },
                { type => 'sms',   letter_module => 'circulation', letter_code => 'STAFFROSTER_REMINDER' },
            ],
        },
    ];
}
```

`label` may be replaced by an i18n hash of `{ lang => 'translated label' }` once Bug TBD-0007a (i18n follow-up) lands. Initial implementation accepts a string.

## Implementation sketch

```perl
# Koha/Plugins/Base.pm — fired by lifecycle.
sub _sync_messaging_preferences {
    my ($self) = @_;
    return if !$self->can('messaging_preferences');
    my $defs = $self->messaging_preferences;
    return if ref $defs ne 'ARRAY' || !@{$defs};
    my $dbh = C4::Context->dbh;

    for my $def ( @{$defs} ) {
        $dbh->do(
            q{INSERT INTO message_attributes (message_name, takes_days)
              VALUES (?, ?)
              ON DUPLICATE KEY UPDATE takes_days = VALUES(takes_days)},
            undef, $def->{message_name}, $def->{takes_days} ? 1 : 0
        );
        my ($attr_id) = $dbh->selectrow_array(
            q{SELECT message_attribute_id FROM message_attributes WHERE message_name = ?},
            undef, $def->{message_name}
        );
        for my $t ( @{ $def->{transports} || [] } ) {
            $dbh->do(
                q{INSERT INTO message_transports
                    (message_attribute_id, message_transport_type, is_digest, letter_module, letter_code, branchcode)
                  VALUES (?, ?, 0, ?, ?, '')
                  ON DUPLICATE KEY UPDATE letter_module = VALUES(letter_module),
                                          letter_code   = VALUES(letter_code)},
                undef, $attr_id, $t->{type}, $t->{letter_module}, $t->{letter_code}
            );
        }
    }
    return;
}

# In the form-rendering layer (opac-messaging.pl + C4/Form/MessagingPreferences.pm):
sub plugin_label_for {
    my ($message_name) = @_;
    return q{} unless C4::Context->config('enable_plugins');
    for my $plugin ( Koha::Plugins->new->GetPlugins({ method => 'messaging_preferences' }) ) {
        try {
            my $defs = $plugin->messaging_preferences;
            for my $def ( @{ $defs || [] } ) {
                return $def->{label} if $def->{message_name} eq $message_name;
            }
        }
        catch { warn "Error calling 'messaging_preferences' on " . $plugin->{class} . " ($_)"; };
    }
    return q{};
}
```

Form templates fall through the SWITCH/CASE to a final `[% CASE %]` arm that reads `messaging_preference.label` (set from the plugin registry). Older translations are preserved for core attribute names.

## Test plan

1. Apply the patch.
2. Enable plugins in `koha-conf.xml`. Configure `EnhancedMessagingPreferences` and `EnhancedMessagingPreferencesOPAC`.
3. Install a plugin that implements `messaging_preferences` and supplies a `Roster_Reminder` attribute with `takes_days => 1` and email + sms transports pointing at a `STAFFROSTER_REMINDER` letter.
4. Confirm `SELECT * FROM message_attributes WHERE message_name = 'Roster_Reminder'` returns one row.
5. Confirm `SELECT * FROM message_transports WHERE message_attribute_id = ?` returns the two transport rows.
6. Open `members/messaging.pl` for a patron. Confirm the new row renders with the human label "Staff roster shift reminder" and a days-in-advance dropdown (because `takes_days => 1`).
7. Open `opac-messaging.pl`. Same row, same label.
8. Toggle the patron's preference to opt in via email. Trigger the plugin's reminder cron. Confirm `EnqueueLetter` fires with `letter_code => 'STAFFROSTER_REMINDER'` and the patron receives the message.
9. Edit the plugin to change the label and bump the version. Re-install. Confirm the description column updates and existing `borrower_message_preferences` rows for the patron remain intact.
10. Uninstall the plugin. Confirm rows in all three tables (`message_attributes`, `message_transports`, `borrower_message_preferences` for that attribute id) are gone.

## Plugin-side example

```perl
package Koha::Plugin::Com::Example::ReminderPlugin;
use base qw(Koha::Plugins::Base);

sub messaging_preferences {
    return [{
        message_name => 'Roster_Reminder',
        label        => 'Staff roster shift reminder',
        takes_days   => 1,
        transports   => [
            { type => 'email', letter_module => 'circulation', letter_code => 'STAFFROSTER_REMINDER' },
        ],
    }];
}
```

## Cross-references

- Survey: `docs/koha-extension-gaps.md` § 2.
- Workaround pattern (current): `docs/plugin-permissions.md` SWITCH/CASE label injector — same shape.
- Composes with Bug TBD-0004 (cron idempotency) — reminder enqueue on the cron path uses `log_action` to mark sent.

## Signed-off-by

(to be filled in during review)
