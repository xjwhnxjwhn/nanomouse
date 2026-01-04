//
//  PersistentController.swift
//  HamsterApp
//
//  Created by morse on 16/3/2023.
//

import CoreData
import OSLog

struct PersistentController {
  static let shared = PersistentController()

  let container: NSPersistentContainer
  init() {
    let name = "NanomouseApp"

    let container = NSPersistentContainer(name: name)
    if let storeURL = FileManager.default.containerURL(
      forSecurityApplicationGroupIdentifier: HamsterConstants.appGroupName
    )?.appendingPathComponent("\(name).sqlite") {
      let storeDescription = NSPersistentStoreDescription(url: storeURL)
      container.persistentStoreDescriptions = [storeDescription]
    } else {
      Logger.statistics.error("App Group container not found; using default Core Data store location.")
    }

    container.loadPersistentStores { _, error in
      if let error = error as NSError? {
        Logger.statistics.error("Unresolved error \(error), \(error.userInfo)")
      }
    }
    self.container = container
  }
}
