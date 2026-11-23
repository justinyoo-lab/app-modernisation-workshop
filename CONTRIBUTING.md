# Contributing

Follow the [Code of Conduct](CODE_OF_CONDUCT.md) when contributing.

## Scope and changes

Keep changes focused on workshop documentation, preparation scripts, and regression tests. Update the relevant documentation when instructions or script behavior change. Do not commit credentials, local configuration, downloaded applications, or generated test output.

Write user-facing script messages in English; keep participant documentation in Korean.

Preserve the download scripts' pinned source commits, `upstream-source.json` records, and `UPSTREAM-*` licenses and notices. Downloads must not modify sample code or target frameworks, create a nested `.git`, or commit or push files.

## Local checks

Run relevant tests from the repository root before opening a pull request. They use isolated fixtures and mocked commands, require no additional test packages, and do not install real tools or change accounts or OS features. Participants should use the [Java](docs/java/00-setup.md) or [.NET](docs/dotnet/00-setup.md) prerequisite checks instead.

### PowerShell

```powershell
pwsh -NoProfile -File ./tests/scripts.tests.ps1
pwsh -NoProfile -File ./tests/dotnet-original.tests.ps1
pwsh -NoProfile -File ./tests/install-prerequisites.tests.ps1
pwsh -NoProfile -File ./tests/windows-prerequisite-updates.tests.ps1
pwsh -NoProfile -File ./tests/azure-actions.tests.ps1
pwsh -NoProfile -File ./tests/powershell-bootstrap.tests.ps1
pwsh -NoProfile -File ./tests/java-tools.tests.ps1
```

The `scripts.tests.ps1` suite also runs `java-deployment.tests.ps1` with mocked Azure, HTTP and PostgreSQL commands. Run the latter directly when changing Java deployment helpers. It does not initialize a real database or deploy an application.

On Windows, repeat these commands with `powershell.exe -NoProfile -File` to check the Windows PowerShell 5.1 entry path and delegation to PowerShell 7. The bootstrap tests use real 5.1 subprocesses with isolated script copies and mocked prerequisites; they do not replace interactive-terminal checks.

Keep `.ps1` files UTF-8 **with BOM** and LF. Entrypoint files must parse in Windows PowerShell 5.1 before delegating to PowerShell 7. Dot-source helpers in PowerShell 7; 5.1 must report an error without exiting the caller. Common helpers must only define functions and variables; `use-java.ps1` may also select the current session's JDK.

Participant instructions use direct script invocation. If needed, allow only `Set-ExecutionPolicy -Scope Process -ExecutionPolicy RemoteSigned`; do not change User/Machine policy or bypass organizational policy.

### Bash

```bash
bash tests/scripts.tests.sh
bash tests/install-prerequisites.tests.sh
bash tests/azure-actions.tests.sh
bash tests/use-java.tests.sh
bash tests/shell-portability.tests.sh
```

The `scripts.tests.sh` suite also runs `java-deployment.tests.sh`; it can be run directly for focused, offline checks.

Run these suites on macOS and Linux. On macOS, use `/bin/bash tests/<suite>.tests.sh` to test the built-in Bash 3.2 rather than Homebrew Bash. Installer tests use the system `script` utility for pseudo-terminal fixtures. The `use-java.sh` tests also require Zsh; install it separately on Ubuntu if absent. See the [CI workflow](.github/workflows/ci.yml) for the platform matrix.

Keep `.sh` files compatible with Bash 3.2 and Bash 5, with LF line endings and BSD/GNU-compatible commands. Guard OS-specific commands. `use-java.sh` must also source correctly in Zsh without leaking helper functions or changing caller options.

Directly executed scripts/tests use `#!/usr/bin/env bash` and Git mode `100755`; source-only helpers such as `use-java.sh`, `terminal-output.sh` and `java-deployment.sh` use `100644`. Check modes with `git ls-files -s scripts tests`, including on Windows where `core.fileMode=false` can hide mode changes.

### Windows VM infrastructure

When changing `infra/` Bicep or setup scripts, run these checks from the repository root before deployment. They package the VM scripts, compile Bicep, and test file delivery and installer behavior without provisioning Azure resources or installing tools. Azure CLI with Bicep is required.

In PowerShell 7 on Windows:

```powershell
./infra/scripts/preprovision.ps1
az bicep build --file ./infra/main.bicep --outfile ./infra/.generated/main.json
./infra/tests/vm-setup.tests.ps1 -CompiledTemplate ./infra/.generated/main.json
```

Check the Windows PowerShell 5.1 entry path and delegation separately:

```powershell
powershell.exe -NoProfile -File ./infra/tests/vm-setup.tests.ps1 -CompiledTemplate ./infra/.generated/main.json
```

On macOS/Linux, with Python 3 available for the tests:

```bash
./infra/scripts/preprovision.sh
az bicep build --file ./infra/main.bicep --outfile ./infra/.generated/main.json
./infra/tests/vm-payload.tests.sh
```

Direct invocation uses the current PowerShell engine or the Bash shebang. Specify an engine only when testing a particular version: on macOS, also run `/bin/bash ./infra/scripts/preprovision.sh` and `/bin/bash ./infra/tests/vm-payload.tests.sh` to cover the built-in Bash 3.2.

Windows tests use temporary registry keys, not the user's PATH. Generated files under `infra/.generated/` and `.azure/` are excluded from Git. Passing local tests does not verify real VM deployment, sign-in, WSL2, Docker, or application builds.

### Results and limits

Tests for missing tools or invalid commits may print `FAIL` or `fatal`. Check the final `PASS` summary and exit code `0`.

Mock tests do not verify real installations, sample runtime, interactive prompts, or Azure deployment. Report those results separately. For alternative-engine procedures, see [Java troubleshooting](docs/java/08-troubleshooting.md#대체-엔진-설정) or [.NET troubleshooting](docs/dotnet/08-troubleshooting.md#대체-엔진-설정).

For documentation-only changes, check relative links, navigation/step order, and `git diff --check`; no application build is required.

## Instructor rehearsal checklist

Record tool versions, model, OS/shell, commands, exit codes, and passed/failed/not-run outcomes. Keep private logs out of the repository. Obtain separate consent for installations, model use, authentication, and cloud/data changes. Never auto-approve these actions in CI or noninteractive sessions.

- [ ] **Windows:** check 5.1 entry and PowerShell 7 delegation, Process-only execution policy, session PATH refresh, and JDK selection. Build and run the Java and .NET originals with the existing helpers; verify browser actions, LocalDB/MSMQ, and cleanup.
- [ ] **macOS:** check the consent-based Homebrew setup, SDKMAN, Modernize cask, Bash 3.2, and Zsh. Source `use-java.sh`, directly run scripts and `startapp.sh`, and execute the modernization plans.
- [ ] **Linux desktop:** check Ubuntu setup, gh repository/keyring, Azure CLI/azd/SDKMAN, Modernize, glibc, and PATH. Run the engine without `sudo`. Check manual guidance on a non-apt distribution where available.
- [ ] **Copilot app terminal:** check keyboard input, Korean/space-containing paths, interruption/reentry, and checkout consistency. Verify status colors, including download preflight, Node/tool-server discovery, and first downloads. Limit missing-tool probes to the test session's PATH.
- [ ] **Modernize, both tracks:** run Full analysis and inspect report/plan/task paths and skill discovery. Review and execute `ws03-baseline`, `ws03-upgrade`, `ws04-azure-code`, and `ws05-azd-assets` separately. Verify tests, commit scope, and effects on global configuration and other sessions; do not delete global directories as a workaround.
- [ ] **Containers:** check Docker/Podman, `linux/amd64` builds, Apple Silicon where used, and `mvnw` line endings. Record image tags/digests.
- [ ] **Azure:** review hooks and azd preview, then check `azd provision`, separately approved DB permissions/migrations, `azd package`, `azd deploy`, features, and `azd down`. Verify Java metadata/worker flows or .NET Data Protection across revisions. Record remaining resources and costs after success or failure.

## Branches and commits

Use `feat/`, `fix/`, or `docs/` prefixes for branches. Use [Conventional Commits](https://www.conventionalcommits.org/), for example `docs: clarify Java workshop setup`.

## Pull requests

Use the [PR template](.github/PULL_REQUEST_TEMPLATE.md). Describe the problem and change, link related issues, and report checks that passed, failed, or could not run. Include tests for script behavior changes and update affected workshop documentation.

Use the [bug report](.github/ISSUE_TEMPLATE/bug_report.yml) or [feature request](.github/ISSUE_TEMPLATE/feature_request.yml) form for those requests.
