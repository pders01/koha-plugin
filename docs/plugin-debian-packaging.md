# Packaging Koha plugins as Debian packages

Status: design and implementation plan (researched against Koha main on 2026-08-09)

## Goal

Build an `Architecture: all` Debian package from a normal Koha plugin tree, install
or upgrade it with APT, enforce supported Koha versions, and use the same build entry
point locally and on common CI forges.

The Debian package is an additional release artifact. Keep producing the `.kpz` for
sites that use Koha's plugin uploader.

## Findings from Koha and Debian

### Koha has machine-wide code but per-instance plugin state

A package installation can contain several Koha instances. Package-created instances
normally use:

```text
/etc/koha/sites/<instance>/koha-conf.xml
/var/lib/koha/<instance>/plugins
```

`koha-create` substitutes the latter path into `<pluginsdir>`. Koha also accepts
multiple `<pluginsdir>` entries.

Plugin code is discovered with `Module::Pluggable` under `Koha::Plugin`, but Perl
module discovery is not the complete runtime contract. `C4::Templates::badtemplatecheck`
rejects plugin templates unless their absolute path is beneath `intrahtdocs`,
`opachtdocs`, or one of the instance's configured `<pluginsdir>` paths. Local testing
confirmed that `/usr/share/perl5` loads the module and registers all methods but fails
when the plugin renders its templates.

Use one shared, read-only, package-managed plugin directory instead:

```text
/usr/share/koha/plugins/Koha/Plugin/<TLD>/<Org>/<Project>.pm
/usr/share/koha/plugins/Koha/Plugin/<TLD>/<Org>/<Project>/...
```

For every Koha instance, append this as an additional plugin directory while keeping
the normal writable directory first:

```xml
<pluginsdir>/var/lib/koha/<instance>/plugins</pluginsdir>
<pluginsdir>/usr/share/koha/plugins</pluginsdir>
```

This is the compromise between Koha's canonical plugin-path contract and Debian file
ownership:

- Koha treats the shared path as canonical because it is explicitly configured as a
  `pluginsdir`, so template, static-asset, REST, and bundle path checks work.
- `dpkg` owns one machine-wide copy instead of maintainer scripts copying executable
  code into every instance's `/var/lib` tree.
- the first `pluginsdir` remains writable and instance-specific, so normal `.kpz`
  uploads do not try to modify `/usr/share`;
- multiple Koha instances can use the same package files while retaining separate
  plugin state in their databases.

Do not install package code only under `/usr/share/perl5` or Koha's private library:
being in `@INC` is insufficient for plugin templates.

#### Optional per-instance deployment

Installing real files below each
`/var/lib/koha/<instance>/plugins` is worth supporting as an explicit alternative.
It requires no `koha-conf.xml` edit and exactly matches the default plugin path, but
it should not be the default because it changes the Debian ownership model.

A future option could expose `debian_plugin_layout: shared|per-instance`, defaulting
to `shared`. The per-instance implementation must account for these caveats:

- `dpkg` cannot know Koha instance names while assembling the package. It can own a
  pristine payload under `/usr/lib/<package>/payload`, but `postinst` must copy that
  payload into each existing instance. The deployed copies do not appear in
  `dpkg-query -L`, package checksums, or `dpkg -V`.
- Symlinks do not solve this cleanly. `Koha::Plugins::Base` resolves the bundle with
  `abs_path`, so a symlink from the instance directory back into `/usr` can still
  produce an absolute template path outside configured `pluginsdir` and fail
  `badtemplatecheck`.
- Every upgrade becomes a multi-instance deployment. Copies need per-instance
  staging, validation, and atomic rename; a failure after some instances were updated
  leaves a partial fleet upgrade that must be reported and safely rerunnable.
- A package installed before `koha-create` cannot populate the new instance. The
  same post-create sync command required by the shared layout must copy and register
  all installed package plugins.
- Removal must delete only files proven to come from that package. Keep a generated
  manifest and checksums; do not recursively remove a namespace that contains local
  additions or administrator modifications.
- Ownership is a trade-off. Root-owned read-only copies preserve package integrity
  but Koha's UI uninstall can perform destructive database work before file deletion
  fails. Instance-owned copies can be changed or deleted through the UI, causing
  package drift that `dpkg -V` cannot detect. The upstream package-managed uninstall
  guard is required for either choice.
- Executable code is duplicated for every instance, uses more disk, and may drift if
  one copy is edited. A package version still represents one machine-wide release,
  even though deployment can fail or be opted out per instance.
- Long-running Plack and worker processes must be restarted after every successful
  copy, replacement, rollback, or removal.

The per-instance mode is therefore useful for installations that prohibit editing
`koha-conf.xml` or need strict default-path behavior, while the configured shared
`pluginsdir` remains the simpler and more auditable package layout.

The plugin's installation state, enabled flag, registered methods, configuration,
and plugin-owned database tables remain per Koha database. Package maintainer scripts
must consequently initialise or upgrade every plugin-enabled instance.

### Installing code is not enough

Koha's `misc/devel/install_plugins.pl --include <class>` scans the code, constructs
the plugin, runs its `install` or `upgrade` lifecycle through
`Koha::Plugins::Base`, and refreshes `plugin_methods`. It must run with each
instance's `KOHA_CONF` and `PERL5LIB`; `koha-shell`/`koha-foreach` provide that
environment on package installations.

The package should not silently change `<enable_plugins>`. For each existing
instance:

1. Ensure `/usr/share/koha/plugins` occurs exactly once as an additional
   `<pluginsdir>`; preserve the writable instance path as the first entry.
2. Validate the edited XML and preserve the configuration file's ownership, mode,
   and an administrator-recoverable backup on failure.
3. If plugins are enabled, run `install_plugins.pl --include <class>`.
4. If plugins are disabled, leave the code and shared path configured and print a
   clear notice.
5. Reload Plack and restart plugin-aware workers where they are enabled.
6. Fail package configuration if configuration editing or an enabled instance's
   plugin install/upgrade fails.

The operation must be idempotent because `postinst configure` can be rerun.

A Koha instance created after the plugin package was installed does not yet contain
the shared `<pluginsdir>` entry and still needs method registration. The first
implementation should ship a command such as
`koha-plugin-debian-sync <package|--all>` that idempotently adds the shared path and
registers installed package plugins after `koha-create`. A later Koha core
integration could invoke that safe global sync during instance creation.

### Koha metadata does not enforce compatibility

`minimum_version` and `maximum_version` are currently warnings in the staff plugin
page. They are still required for `.kpz` users, but are not an installation guard.
The Debian package must translate them to package relationships.

For example:

```debcontrol
Depends:
 koha-common (>= 24.11),
 koha-common (<< 25.06),
 ${misc:Depends},
 ${perl:Depends}
```

A plugin with `minimum_version: 24.11` and `maximum_version: 25.05` permits all
24.11 through 25.05 package updates and rejects the 25.06 development/release line.
An empty maximum omits the upper bound. Generate the exclusive upper bound by
incrementing the Koha year/month release line, rather than comparing strings.

Koha's official package versions use values such as `25.05.12-1`, so these bounds
sort correctly under Debian version rules. Validate generated bounds with
`dpkg --compare-versions`.

Initially depend on `koha-common`, the normal supported multi-instance package.
Supporting experimental `koha-core`/`koha-full` variants should be a separately
tested feature; expressing the same lower and upper constraints over alternatives is
possible but easy to get wrong.

### Perl and service dependencies must be explicit

`dh_perl` does not turn every Perl `use` statement into the correct Debian package
name. Add explicit Debian runtime dependencies to plugin configuration and verify
them in every supported Debian/Ubuntu suite. Do not infer that a CPAN dependency is
available merely because it exists in the build environment.

Recommended configuration:

```yaml
debian_package_name: koha-plugin-com-example-myplugin
debian_maintainer: "Example Maintainer <maintainer@example.org>"
debian_revision: "1"
debian_dependencies: "libexample-perl"
```

The binary version is `<plugin version>-<revision>`, for example `1.4.0-1`.
`version`, `minimum_version`, and `maximum_version` continue to have one source of
truth in `koha-plugin.yml` and the plugin module metadata.

## Important lifecycle limitation

Koha does not currently distinguish package-managed plugins from uploaded `.kpz`
plugins. The staff interface always offers **Uninstall** to users with the relevant
permission. `Koha::Plugins::Handler->delete` runs the plugin's `uninstall`, removes
its database records, and only then tries to unlink its files.

For root-owned package files, the unlink will fail but destructive database work may
already have happened. Therefore:

- package documentation must say to use `apt remove`, never the Koha **Uninstall**
  action, for a package-managed plugin;
- do not install both the `.kpz` and `.deb` form of the same class on one instance;
- a production-ready design needs a Koha core change that detects a read-only or
  package-managed plugin **before** destructive uninstall and directs the operator to
  the OS package manager.

This is the main gap between a workable package and a fully first-class Koha package
integration. It should be tracked upstream rather than worked around by modifying
Koha CGI files from a plugin package.

## Package lifecycle contract

### Install and upgrade (`postinst configure`)

- Enumerate all instances with `koha-list`.
- Idempotently append `/usr/share/koha/plugins` as a `pluginsdir` without changing
  the existing first/writable plugin directory or the `enable_plugins` value.
- Validate and safely replace `koha-conf.xml`; never use an unstructured text
  substitution for XML.
- Run the versioned Koha `install_plugins.pl --include <class>` through
  `koha-shell` for each enabled instance.
- Preserve a user's enabled/disabled plugin state on upgrades.
- Reload affected long-lived processes after successful registration.
- Report each skipped, upgraded, and failed instance.

Plugin database migrations are not rolled back by downgrading the Debian package.
APT upgrades require the same backup and upgrade testing as `.kpz` upgrades.

### Remove (`prerm remove`)

Before files disappear, remove registered methods and disable the plugin in every
instance **without** invoking destructive plugin uninstall and without deleting
plugin data. Do not do this for `prerm upgrade`.

Do not remove the shared `<pluginsdir>` entry from an instance when one plugin package
is removed: other plugin packages may still depend on it. An empty, root-owned shared
directory entry is harmless. A future common integration package may remove the entry
only after proving no package-managed plugins remain.

### Purge

Default to retaining plugin database state. Automated purge cannot safely assume
that every plugin's `uninstall` is non-destructive or that library data should be
deleted. A future explicit, separately confirmed purge command may delete owned data.

### Duplicate installation

Before configuration, detect the same class under an instance's writable, first
`pluginsdir`. Abort with an actionable message instead of allowing the `.kpz` and
Debian copies of the same Perl class to be loaded in path-dependent order.

## Build layout

Generate Debian metadata in an isolated temporary work tree; do not mutate the
plugin source tree merely to build an artifact.

```text
<work>/
  Koha/...
  debian/
    changelog
    control
    copyright
    install
    postinst
    prerm
    rules
    source/format
    tests/control
    tests/smoke
```

Use:

```text
Build-Depends: debhelper-compat (= 13)
Rules-Requires-Root: no
Architecture: all
```

`debian/install` installs `Koha/` under `/usr/share/koha/plugins`. Package
configuration then registers that shared directory in each existing instance's
`koha-conf.xml`. Build unsigned local
artifacts with `dpkg-buildpackage -us -uc -b`. A forge-neutral command should own the
entire operation, for example:

```sh
koha-plugin package-deb dist/debian
```

The command should:

1. Run `koha-plugin check` and the plugin's tests/build step.
2. Require a clean or explicitly recorded Git revision for release builds.
3. Generate and validate Debian metadata.
4. Build in a pinned Debian container locally, or natively in a Debian CI image.
5. Run `lintian`.
6. Inspect package fields and contents with `dpkg-deb`.
7. Emit SHA-256 checksums plus a provenance file containing source commit, builder
   image digest, command, and test results.

Do not sign or publish during ordinary CI. Signing belongs in a protected release
job after installation tests.

## Local test plan

Use the requested disposable `test-koha-1` container, not a production host.

1. **Build checks**
   - build twice from the same committed source;
   - inspect `dpkg-deb --info`, `--contents`, and fields;
   - run `lintian` and archive its output;
   - verify only the intended `Koha/Plugin/<namespace>` files are present.
2. **Dependency bounds**
   - assert the minimum with `dpkg --compare-versions`;
   - assert the next Koha line is rejected by the upper bound;
   - test APT's resolver, not only direct `dpkg -i`.
3. **Fresh installation**
   - enable plugins on the disposable instance;
   - `apt install ./koha-plugin-..._all.deb`;
   - verify package status, plugin method registration, enabled state, logs, Plack,
     workers, and a representative plugin feature.
4. **Upgrade**
   - install the previous plugin package, seed representative plugin data, then
     upgrade;
   - verify migrations, retained configuration/data, and process reloads.
5. **Disabled plugin and disabled plugin system**
   - upgrades preserve an intentionally disabled plugin;
   - an instance with `enable_plugins=0` is skipped with a useful notice.
6. **Multiple instances**
   - test one enabled, one plugin-disabled, and one disabled Koha instance.
7. **Removal and reinstall**
   - `apt remove` removes code and method registrations without deleting plugin data;
   - reinstall re-registers methods and preserves prior enabled/disabled state;
   - record the deliberate data-retaining behavior of `apt purge`.
8. **Failure recovery**
   - force a plugin migration failure and verify the package remains visibly
     unconfigured, can be fixed, and succeeds when `dpkg --configure -a` is rerun.

Result labels should be: `build failed`, `artifacts built, not installation-tested`,
or `validated for local testing`. Do not call the first successful `.deb` a release
candidate.

### Local validation record: 2026-08-09

The shared-layout proof of concept was validated with:

```text
plugin: Koha::Plugin::Xyz::Paulderscheid::StaffRoster 0.1.0
package: koha-plugin-staff-roster 0.1.0-5 (Architecture: all)
Koha: koha-common 26.06.00-11~git+20260804230115.c267c679-1
instance: kohadev
container architecture: arm64
```

Validated behavior:

- binary package build, SHA-256 output, and clean Lintian result;
- recovery from a failed `postinst` by installing a higher Debian revision;
- enforced minimum `koha-common` package dependency;
- shared package files under `/usr/share/koha/plugins`;
- idempotent secondary `pluginsdir` registration while retaining the writable
  instance directory first;
- restricted backup of the original `koha-conf.xml`;
- fresh plugin registration and repeated idempotent registration;
- 59 registered methods and correct installed/version/enabled lifecycle rows;
- Plack reload and worker restarts after install, upgrade, and removal;
- non-destructive `apt remove`, including code/method removal and retained disabled
  plugin data;
- reinstall with method restoration and preserved disabled state;
- user-reported successful Tool, Configure, Report, and Admin template/static/runtime
  behavior from the shared configured path.

The test also proved that module-only installation under `/usr/share/perl5` is not a
valid full-plugin layout: method discovery succeeds, but Koha rejects templates with
`bad template path` because the bundle is outside configured `pluginsdir` paths.

Still to test before release-candidate status: an actual plugin-version migration,
an APT resolver rejection at a generated maximum Koha bound, multiple instances,
`enable_plugins=0`, deliberate duplicate `.kpz` collision, purge, post-`koha-create`
sync, and the GitHub CI matrix. Current classification: **validated for local
testing**.

## CI/forge design

Keep forge files thin. Every forge invokes the same checked-in build and validation
command.

### GitHub Actions (second phase)

Use an Ubuntu runner with a pinned Debian builder container, or run the job itself in
a Debian container. On pushes and merge requests:

- source/unit tests;
- package build;
- lintian and package-content assertions;
- upload unsigned `.deb`, `.buildinfo`, `.changes`, checksums, and logs as workflow
  artifacts.

On version tags, run the Koha installation/upgrade matrix before creating a release.
Use OIDC artifact attestations where desired, but treat them as provenance rather
than an APT repository signature.

### GitLab/Salsa

A GitLab Docker runner can use the same pinned Debian image directly, avoiding
Docker-in-Docker. Include Salsa CI only if the generated packaging is committed in a
form Salsa CI expects; otherwise call the common build script and reproduce the
relevant lintian/autopkgtest checks. Generic GitLab works the same way.

### Forgejo/Gitea, Woodpecker, CircleCI, Jenkins

- Forgejo/Gitea Actions can adapt the GitHub workflow but must not assume every
  GitHub-specific action exists.
- Woodpecker, CircleCI, and Jenkins should run the same Debian image and build script.
- Store forge syntax separately from package logic.

### Publishing later

A release attachment or generic package registry is not an APT repository. For
`apt update`/`apt install koha-plugin-...`, publish signed `Packages`, `Release`, and
`InRelease` metadata using aptly, reprepro, or a managed Debian repository service.
Use a protected, version-specific suite and signing key; never expose signing keys to
pull-request jobs. Open Build Service is an alternative when building and publishing
for several Debian/Ubuntu releases becomes a requirement.

## Implementation phases

### Phase 1: local proof of concept

- Add Debian package configuration and validation.
- Add a pure metadata generator with unit tests for names, versions, paths, and Koha
  bounds.
- Add `package-deb`, using a pinned Debian builder image.
- Add idempotent `postinst`/`prerm` helpers and `autopkgtest` smoke tests.
- Build and run the complete local test plan in `test-koha-1`.
- File or draft the Koha core package-managed uninstall guard.

### Phase 2: GitHub CI

- Add package build/artifact jobs.
- Add a tag-gated disposable Koha fresh-install and upgrade matrix.
- Record checksums and attestations; still leave APT publication disabled.

### Phase 3: other forges and repository publication

- Add GitLab first, then small wrappers for the forges actually used.
- Add protected signing and APT repository publication only after local and GitHub
  installation matrices are stable.

## Primary references

- Koha plugin discovery and lifecycle:
  <https://github.com/Koha-Community/Koha/blob/main/Koha/Plugins.pm>
- Koha plugin base lifecycle:
  <https://github.com/Koha-Community/Koha/blob/main/Koha/Plugins/Base.pm>
- Koha plugin uninstall handler:
  <https://github.com/Koha-Community/Koha/blob/main/Koha/Plugins/Handler.pm>
- Koha command-line plugin installer:
  <https://github.com/Koha-Community/Koha/blob/main/misc/devel/install_plugins.pl>
- Koha package instance configuration:
  <https://github.com/Koha-Community/Koha/blob/main/debian/scripts/koha-create>
- Koha package configuration template:
  <https://github.com/Koha-Community/Koha/blob/main/debian/templates/koha-conf-site.xml.in>
- Debian package relationship syntax:
  <https://www.debian.org/doc/debian-policy/ch-relationships.html>
- Debian packaging with Git and Salsa CI:
  <https://www.debian.org/doc/manuals/debmake-doc/ch11.en.html>
- Salsa CI pipeline:
  <https://salsa.debian.org/salsa-ci-team/pipeline>
