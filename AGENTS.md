# Agent instructions

- `docs/USAGE.md` is the project spec for user-facing `lfg` and `worktree` behavior; treat it as the source of truth for runtime behavior and conventions.
- Keep `docs/USAGE.md` focused on actual project functionality. Do not document helper or maintenance scripts such as `install.sh`, release scripts, or test scripts there.
- When changing `lfg` or `worktree` functionality, update `docs/USAGE.md` to match the new behavior.
- When changing helper or maintenance scripts, document them in their dedicated docs, such as `docs/INSTALL.md` or `docs/RELEASE.md`, instead of `docs/USAGE.md`.
- Keep `docs/USAGE.md` and the shell implementations in sync; users rely on the usage docs as the canonical guide for runtime behavior.
