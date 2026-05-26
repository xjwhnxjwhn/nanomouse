//
//  RemoteAssetDownloadService.swift
//
//
//  Created by Codex on 2026/5/26.
//

import CloudKit
import Foundation
import HamsterKit
import OSLog

enum RemoteAssetSource: String {
  case cloudKitPublic
  case github
}

struct RemoteAssetManifestEntry: Decodable {
  let id: String
  let fileName: String
  let publishedAt: String
  let sha256: String
  let minSharedSupportVersion: String?
  let title: String?
}

struct RemoteAssetDownloadResult {
  let fileURL: URL
  let source: RemoteAssetSource
}

final class RemoteAssetDownloadService {
  static let shared = RemoteAssetDownloadService()

  private static let recordType = "NanomouseAssetPackage"
  private static let idField = "id"
  private static let fileNameField = "fileName"
  private static let publishedAtField = "publishedAt"
  private static let sha256Field = "sha256"
  private static let minSharedSupportVersionField = "minSharedSupportVersion"
  private static let titleField = "title"
  private static let assetField = "asset"
  private static let resultLimit = 200

  private struct GitHubManifest: Decodable {
    let packages: [RemoteAssetManifestEntry]
  }

  private typealias QueryResult = (
    matchResults: [(CKRecord.ID, Result<CKRecord, Error>)],
    queryCursor: CKQueryOperation.Cursor?
  )

  private let container = CKContainer(identifier: HamsterConstants.iCloudID)
  private lazy var database = container.publicCloudDatabase

  private init() {}

  func fetchManifest() async throws -> [String: RemoteAssetManifestEntry] {
    do {
      let cloudEntries = try await fetchCloudKitManifest()
      if !cloudEntries.isEmpty {
        return cloudEntries.reduce(into: [String: RemoteAssetManifestEntry]()) { result, entry in
          result[entry.id] = entry
        }
      }
    } catch {
      Logger.statistics.error("fetch CloudKit asset manifest failed: \(error.localizedDescription)")
    }

    let githubEntries = try await fetchGitHubManifest()
    return githubEntries.reduce(into: [String: RemoteAssetManifestEntry]()) { result, entry in
      result[entry.id] = entry
    }
  }

  func packageEntry(id: String) async throws -> RemoteAssetManifestEntry? {
    if let cloudEntry = try? await fetchCloudKitManifestEntry(id: id) {
      return cloudEntry
    }
    return try await fetchManifest()[id]
  }

  func downloadAsset(fileName: String, packageID: String? = nil) async throws -> RemoteAssetDownloadResult {
    var cloudKitError: Error?
    do {
      let cloudFileURL = try await downloadCloudKitAsset(fileName: fileName, packageID: packageID)
      return RemoteAssetDownloadResult(fileURL: cloudFileURL, source: .cloudKitPublic)
    } catch {
      cloudKitError = error
      Logger.statistics.error("download CloudKit asset failed: \(fileName), \(error.localizedDescription)")
    }

    do {
      let githubFileURL = try await downloadGitHubAsset(fileName: fileName)
      return RemoteAssetDownloadResult(fileURL: githubFileURL, source: .github)
    } catch {
      let cloudMessage = cloudKitError?.localizedDescription ?? "未尝试"
      throw StringError("下载资源失败：Apple(\(cloudMessage))，GitHub(\(error.localizedDescription))")
    }
  }

  func downloadGitHubAsset(fileName: String) async throws -> URL {
    guard let baseURL = URL(string: HamsterConstants.onDemandInputSchemaZipBaseURL) else {
      throw StringError("GitHub 下载地址无效")
    }
    let remoteURL = baseURL.appendingPathComponent(fileName)
    let (tempURL, response) = try await URLSession.shared.download(from: remoteURL)
    if let httpResponse = response as? HTTPURLResponse,
       !(200...299).contains(httpResponse.statusCode) {
      try? FileManager.default.removeItem(at: tempURL)
      throw StringError("下载失败（HTTP \(httpResponse.statusCode)）")
    }
    return tempURL
  }

  private func fetchGitHubManifest() async throws -> [RemoteAssetManifestEntry] {
    guard let baseURL = URL(string: HamsterConstants.onDemandInputSchemaZipBaseURL) else {
      throw StringError("GitHub 下载地址无效")
    }
    let manifestURL = baseURL.appendingPathComponent(HamsterConstants.onDemandInputSchemaManifestFile)
    let (data, response) = try await URLSession.shared.data(from: manifestURL)
    if let httpResponse = response as? HTTPURLResponse,
       !(200...299).contains(httpResponse.statusCode) {
      throw StringError("获取更新清单失败（HTTP \(httpResponse.statusCode)）")
    }

    return try JSONDecoder().decode(GitHubManifest.self, from: data).packages
  }

  private func fetchCloudKitManifest() async throws -> [RemoteAssetManifestEntry] {
    let query = CKQuery(recordType: Self.recordType, predicate: NSPredicate(value: true))
    let records = try await fetchAllCloudKitRecords(
      query: query,
      desiredKeys: Self.manifestDesiredKeys
    )
    return records.compactMap(Self.manifestEntry(from:))
  }

  private func fetchCloudKitManifestEntry(id: String) async throws -> RemoteAssetManifestEntry? {
    let record = try await fetchCloudKitRecord(
      field: Self.idField,
      value: id,
      desiredKeys: Self.manifestDesiredKeys
    )
    return record.flatMap(Self.manifestEntry(from:))
  }

  private func downloadCloudKitAsset(fileName: String, packageID: String?) async throws -> URL {
    let record = try await fetchCloudKitAssetRecord(fileName: fileName, packageID: packageID)
    guard let asset = record[Self.assetField] as? CKAsset,
          let assetFileURL = asset.fileURL else {
      throw StringError("Apple 资源缺少资产文件：\(fileName)")
    }

    let tempURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("nanomouse-asset-\(UUID().uuidString)-\(fileName)")
    try? FileManager.default.removeItem(at: tempURL)
    try FileManager.default.copyItem(at: assetFileURL, to: tempURL)
    return tempURL
  }

  private func fetchCloudKitAssetRecord(fileName: String, packageID: String?) async throws -> CKRecord {
    let desiredKeys = Self.manifestDesiredKeys + [Self.assetField]
    if let packageID,
       let record = try await fetchCloudKitRecord(
         field: Self.idField,
         value: packageID,
         desiredKeys: desiredKeys
       ) {
      return record
    }

    if let record = try await fetchCloudKitRecord(
      field: Self.fileNameField,
      value: fileName,
      desiredKeys: desiredKeys
    ) {
      return record
    }
    throw StringError("Apple 资源不存在：\(packageID ?? fileName)")
  }

  private func fetchCloudKitRecord(
    field: String,
    value: String,
    desiredKeys: [String]
  ) async throws -> CKRecord? {
    let query = CKQuery(recordType: Self.recordType, predicate: NSPredicate(format: "%K == %@", field, value))
    let result = try await fetchCloudKitPage(query: query, desiredKeys: desiredKeys)
    for (_, recordResult) in result.matchResults {
      if case let .success(record) = recordResult {
        return record
      }
    }
    return nil
  }

  private func fetchAllCloudKitRecords(query: CKQuery, desiredKeys: [String]) async throws -> [CKRecord] {
    var records = [CKRecord]()
    var result = try await fetchCloudKitPage(query: query, desiredKeys: desiredKeys)
    records.append(contentsOf: Self.records(from: result.matchResults))

    while let cursor = result.queryCursor {
      result = try await fetchCloudKitPage(cursor: cursor, desiredKeys: desiredKeys)
      records.append(contentsOf: Self.records(from: result.matchResults))
    }
    return records
  }

  private func fetchCloudKitPage(query: CKQuery, desiredKeys: [String]) async throws -> QueryResult {
    let config = CKOperation.Configuration()
    config.qualityOfService = .userInitiated
    return try await withCheckedThrowingContinuation { continuation in
      database.configuredWith(configuration: config) { db in
        db.fetch(
          withQuery: query,
          desiredKeys: desiredKeys,
          resultsLimit: Self.resultLimit
        ) { result in
          continuation.resume(with: result)
        }
      }
    }
  }

  private func fetchCloudKitPage(
    cursor: CKQueryOperation.Cursor,
    desiredKeys: [String]
  ) async throws -> QueryResult {
    try await withCheckedThrowingContinuation { continuation in
      database.fetch(
        withCursor: cursor,
        desiredKeys: desiredKeys,
        resultsLimit: Self.resultLimit
      ) { result in
        continuation.resume(with: result)
      }
    }
  }

  private static func records(from matchResults: [(CKRecord.ID, Result<CKRecord, Error>)]) -> [CKRecord] {
    matchResults.compactMap { _, result in
      if case let .success(record) = result {
        return record
      }
      return nil
    }
  }

  private static func manifestEntry(from record: CKRecord) -> RemoteAssetManifestEntry? {
    guard let id = record[idField] as? String,
          let fileName = record[fileNameField] as? String,
          let sha256 = record[sha256Field] as? String else {
      return nil
    }

    return RemoteAssetManifestEntry(
      id: id,
      fileName: fileName,
      publishedAt: record[publishedAtField] as? String ?? "",
      sha256: sha256,
      minSharedSupportVersion: record[minSharedSupportVersionField] as? String,
      title: record[titleField] as? String
    )
  }

  private static var manifestDesiredKeys: [String] {
    [
      idField,
      fileNameField,
      publishedAtField,
      sha256Field,
      minSharedSupportVersionField,
      titleField
    ]
  }
}
