# About new-package review-config-templates

This folder is not included in the package itself, but should not be removed.

When running `new-package`, the CLI will fetch one of these templates from the
main branch of this repository from GitHub and use the files to create a default
configuration.

The 2.3.0 folder is targeted since the 2.3.0 version of the CLI. If the CLI
somehow changes and needs a new structure, we will create a new folder (3.0.0
for instance) and have versions from that point on target that folder.

If a template disappears, then the `new-package` subcommand will be broken for
all CLI versions that targeted that version. We can remove a template this in
due time, but keeping them probably has little cost. We just need to remember to
not to delete them or the `new-package/review-config-templates` folder.
