### Writing a simple Koha plugin (inject JS into staff UI)

This is a condensed, up-to-date reference for creating a minimal plugin that injects JavaScript into the staff interface via the `intranet_js` hook.

#### Steps

1. Create the plugin module

Use the scaffold or create a module at `Koha/Plugin/AddHotkeys.pm`:

```perl
package Koha::Plugin::AddHotkeys;

use Modern::Perl;
use base qw(Koha::Plugins::Base);

our $VERSION = '0.1';

our $metadata = {
    name            => 'AddHotkeys',
    author          => 'Your Name',
    date_authored   => '2025-01-01',
    date_updated    => '2025-01-01',
    minimum_version => '19.05.00.000',
    maximum_version => undef,
    version         => $VERSION,
    description     => 'Adds JavaScript hotkeys to addbiblio.pl',
};

sub new {
    my ( $class, $args ) = @_;
    $args->{metadata}           = $metadata;
    $args->{metadata}->{class}  = $class;
    my $self = $class->SUPER::new($args);
    $self->{cgi} = CGI->new();
    return $self;
}

sub intranet_js {
    my ($self) = @_;
    my $cgi          = $self->{cgi};
    my $script_name  = $cgi->script_name;

    my $js = <<'JS';
<script>
  function hotkey(e) {
    if (e.ctrlKey && e.altKey) {
      let next_tab_id;
      if (/^[0-9]$/.test(e.key)) { next_tab_id = e.key; }
      if (e.key === 'ArrowRight' || e.key === 'ArrowLeft') {
        const active = document.querySelector('.toolbar-tabs li.selected a');
        if (!active) return;
        let id = parseInt(active.getAttribute('data-tabid'), 10) || 0;
        id = e.key === 'ArrowRight' ? id + 1 : id - 1;
        if (id < 0) id = 9;
        if (id > 9) id = 0;
        next_tab_id = id;
      }
      if (typeof next_tab_id !== 'undefined') {
        const tab = document.querySelector('.toolbar-tabs li a[data-tabid="' + next_tab_id + '"]');
        if (tab) tab.click();
      }
    }
  }
  document.addEventListener('keyup', hotkey, false);
</script>
JS

    return $script_name =~ /addbiblio\.pl/ ? $js : undef;
}

1;
```

2. Package as `.kpz`

Zip the `Koha/` directory:

```bash
zip -r koha-plugin-addhotkeys.kpz Koha/
```

3. Install and enable

- Ensure plugins are enabled in `koha-conf.xml`
- Upload the `.kpz` via Tools → Plugins
- Activate the plugin

Notes

- Prefer using the scaffold (`templates/[a].pm.tt`, `templates/PLUGIN.yml`) to generate a fully-structured plugin with metadata, install/upgrade scripts, and optional admin UI.
- For OPAC-side injection use `opac_js`/`opac_head` instead.

---

Last updated: 2025-08-13
