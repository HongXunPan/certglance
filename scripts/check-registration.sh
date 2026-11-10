#!/bin/bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
cd "${root}"
if [[ "$#" -gt 1 || ( "$#" -eq 1 && "$1" != "--network" && "$1" != "--whois-network" ) ]]; then
  printf '用法：bash scripts/check-registration.sh [--network|--whois-network]\n' >&2
  exit 2
fi
mkdir -p .codex-tmp
temp="$(mktemp -d "${root}/.codex-tmp/registration-check-20261102-XXXXXX")"
trap 'rm -rf "${temp}"' EXIT
xcrun swiftc -swift-version 6 -parse-as-library \
  -module-cache-path "${temp}/SwiftModuleCache" \
  -Xcc "-fmodules-cache-path=${temp}/ClangModuleCache" \
  Shared/DomainModels.swift Shared/ReminderPreferences.swift Shared/SharedStore.swift \
  Shared/RegistrationModels.swift Shared/RegistrationStore.swift \
  Shared/RegistrationParsing.swift Shared/RegistrationHTTP.swift \
  Shared/WHOISClient.swift Shared/RegistrationChecker.swift \
  Shared/NotificationPolicy.swift Shared/NotificationCoordinator.swift Shared/RegistrationNotifications.swift \
  Tests/RegistrationLookupChecks.swift Tests/RegistrationChecks.swift \
  -o "${temp}/RegistrationChecks"
if [[ "$#" -eq 1 ]]; then
  "${temp}/RegistrationChecks" "$1"
elif [[ "$#" -eq 0 ]]; then
  "${temp}/RegistrationChecks" "${temp}"
else
  printf '用法：bash scripts/check-registration.sh [--network|--whois-network]\n' >&2
  exit 2
fi
