# daemon
Utility to help you write daemonized producers/consumers.

- Authors: https://gitlab.com/shellm/daemon/AUTHORS.md
- Changelog: https://gitlab.com/shellm/daemon/CHANGELOG.md
- Contributing: https://gitlab.com/shellm/daemon/CONTRIBUTING.md
- Documentation: https://gitlab.com/shellm/daemon/wiki
- License: ISC - https://gitlab.com/shellm/daemon/LICENSE

## Installation
Installation with [basher](https://github.com/basherpm/basher):
```bash
basher install shellm/daemon
```

Installation from source:
```bash
git clone https://gitlab.com/shellm/daemon
cd daemon
sudo ./install.sh
```

## Usage
Command-line:
```
daemon -h
```

As a library:
```bash
# with basher's include
include shellm/daemon lib/daemon.sh
# with shellm's include
shellm-source shellm/daemon lib/daemon.sh
```
