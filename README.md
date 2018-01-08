# daemon
Utility to help you write daemonized producers/consumers.

- Authors: https://github.com/shellm-org/daemon/AUTHORS.md
- Changelog: https://github.com/shellm-org/daemon/CHANGELOG.md
- Contributing: https://github.com/shellm-org/daemon/CONTRIBUTING.md
- Documentation: https://github.com/shellm-org/daemon/wiki
- License: ISC - https://github.com/shellm-org/daemon/LICENSE

## Installation
Installation with [basher](https://github.com/basherpm/basher):
```bash
basher install shellm-org/daemon
```

Installation from source:
```bash
git clone https://github.com/shellm-org/daemon
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
include shellm-org/daemon lib/daemon.sh
# with shellm's include
shellm-include shellm-org/daemon lib/daemon.sh
```
