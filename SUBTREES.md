# Git Subtrees

Vendor dependencies managed via `git subtree`. Do **not** edit files under
`vendor/` directly — changes should go upstream and be pulled back.

## Subtree Map

| Prefix | Remote | Branch | Description |
|--------|--------|--------|-------------|
| `vendor/kvmd` | `pikvm-kvmd` | `master` | PiKVM main daemon (kvmd) |
| `vendor/ustreamer` | `pikvm-ustreamer` | `master` | PiKVM video streamer |
| `vendor/os` | `pikvm-os` | `master` | PiKVM OS build system |

## Remotes

```bash
git remote add pikvm-kvmd https://github.com/pikvm/kvmd.git
git remote add pikvm-ustreamer https://github.com/pikvm/ustreamer.git
git remote add pikvm-os https://github.com/pikvm/os.git
```

## Updating a Subtree

Pull the latest from upstream (squashed):

```bash
# Update all
just subtree-update

# Update one
just subtree-update vendor/kvmd
```

Or manually:

```bash
git subtree pull --prefix=vendor/kvmd pikvm-kvmd master --squash
git subtree pull --prefix=vendor/ustreamer pikvm-ustreamer master --squash
git subtree pull --prefix=vendor/os pikvm-os master --squash
```

## Adding a New Subtree

```bash
git remote add <name> <url>
git subtree add --prefix=vendor/<name> <remote> <branch> --squash
```

Then update this file.
