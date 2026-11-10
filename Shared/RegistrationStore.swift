import Foundation

protocol RegistrationStore: SnapshotStore {
  func registeredDomains() throws -> [RegisteredDomain]
  func registrationSnapshots() throws -> [RegistrationSnapshot]
  func replaceRegisteredDomains(_ domains: [RegisteredDomain]) throws
  func mergeRegistrationSnapshots(_ snapshots: [RegistrationSnapshot]) throws
}

extension FileSnapshotStore: RegistrationStore {
  func registeredDomains() throws -> [RegisteredDomain] {
    let saved = try read(
      [RegisteredDomain].self, from: config.appendingPathComponent("registrations.v1.json"))
    guard Set(saved.map(\.id)).count == saved.count,
      saved.allSatisfy({
        (try? RegistrationInput.parse($0.hostname)) == $0.hostname
          && RegistrationDates.isValidDate($0.addedAt)
      })
    else { throw SharedStoreError.corrupted }
    return saved
  }

  func registrationSnapshots() throws -> [RegistrationSnapshot] {
    let active = Set(try registeredDomains().map(\.id))
    let saved = try read(
      [RegistrationSnapshot].self,
      from: state.appendingPathComponent("registration-snapshots.v1.json"))
    guard Set(saved.map(\.id)).count == saved.count,
      saved.allSatisfy({
        $0.dates.isValid && RegistrationDates.isValidDate($0.checkedAt)
          && ($0.lastSuccessfulCheckAt.map(RegistrationDates.isValidDate) ?? true)
          && ($0.checkState != .available || $0.dates.preferred != nil)
      })
    else { throw SharedStoreError.corrupted }
    return saved.filter { active.contains($0.id) }
  }

  func replaceRegisteredDomains(_ domains: [RegisteredDomain]) throws {
    guard Set(domains.map(\.id)).count == domains.count,
      domains.allSatisfy({
        (try? RegistrationInput.parse($0.hostname)) == $0.hostname
          && RegistrationDates.isValidDate($0.addedAt)
      })
    else { throw SharedStoreError.corrupted }
    try withLock {
      _ = try registeredDomains()
      let active = Set(domains.map(\.id))
      let saved = try registrationSnapshots().filter { active.contains($0.id) }
      try write(saved, to: state.appendingPathComponent("registration-snapshots.v1.json"))
      try write(domains, to: config.appendingPathComponent("registrations.v1.json"))
    }
  }

  func mergeRegistrationSnapshots(_ snapshots: [RegistrationSnapshot]) throws {
    guard
      snapshots.allSatisfy({
        $0.dates.isValid && RegistrationDates.isValidDate($0.checkedAt)
          && ($0.checkState != .available || $0.dates.preferred != nil)
      })
    else { throw SharedStoreError.corrupted }
    try withLock {
      let active = Set(try registeredDomains().map(\.id))
      var indexed = Dictionary(
        uniqueKeysWithValues: try registrationSnapshots().map { ($0.id, $0) })
      for var result in snapshots where active.contains(result.id) {
        let old = indexed[result.id]
        if let old, old.checkedAt >= result.checkedAt { continue }
        if result.checkState == .failed {
          result.dates = old?.dates ?? RegistrationDates()
          result.sources = old?.sources ?? []
          result.lastSuccessfulCheckAt = old?.lastSuccessfulCheckAt
        }
        indexed[result.id] = result
      }
      try write(
        indexed.values.sorted { $0.id < $1.id },
        to: state.appendingPathComponent("registration-snapshots.v1.json"))
    }
  }
}
