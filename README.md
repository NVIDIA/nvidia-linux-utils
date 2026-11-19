# nvidia-linux-utils

A collection of NVIDIA Linux-specific utilities.

## Overview

This repository contains small, self-contained utilities for configuring and inspecting NVIDIA platforms on Linux. Each utility lives in its own directory.

## Utilities

| Utility | Description |
| --- | --- |
| [nvidia-display-carveout](nvidia-display-carveout/) | Query and change the persistent Display firmware-reserved memory (FRM) carveout size, stored in the `EXPOSED_DISP_FRM` EFI variable, on NVIDIA SoC systems that expose FRM configuration via UEFI variables. |

More utilities may be added over time.

### nvidia-display-carveout

`nvidia-display-carveout.sh` is a shell script with three operations:

- `--get-display-carveout`: show the stored carveout preference, the firmware limits, and the carveout applied on the current boot (unprivileged).
- `--set-display-carveout SIZE_MIB`: set the preference, validated against the firmware limits and increment (privileged).
- `--reset-display-carveout`: restore the firmware default (privileged).

Changes take effect on the next boot. See the [utility README](nvidia-display-carveout/README.md) for full usage, output format, and requirements.

```bash
cd nvidia-display-carveout
./nvidia-display-carveout.sh --get-display-carveout
```

## Security

Do not report security vulnerabilities through public GitHub issues. See [SECURITY.md](SECURITY.md) for the reporting path.

## Contributing

See the contribution guidance of the relevant utility, for example [nvidia-display-carveout/CONTRIBUTING.md](nvidia-display-carveout/CONTRIBUTING.md).

## License

Each utility is licensed under the terms in its own directory. See [nvidia-display-carveout/LICENSE](nvidia-display-carveout/LICENSE) (Apache License 2.0) for `nvidia-display-carveout`.
