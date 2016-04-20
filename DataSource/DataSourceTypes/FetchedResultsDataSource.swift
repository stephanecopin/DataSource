//
//  FetchedResultsDataSource.swift
//  DataSource
//
//  Created by Vadim Yelagin on 14/06/15.
//  Copyright (c) 2015 Fueled. All rights reserved.
//

import Foundation
import ReactiveCocoa
import Result
import CoreData

/// `DataSource` implementation whose items are Core Data managed objects fetched by an `NSFetchedResultsController`.
///
/// Returns names of fetched sections as supplementary items of `UICollectionElementKindSectionHeader` kind.
///
/// Uses `NSFetchedResultsControllerDelegate` protocol internally to observe changes
/// in fetched objects and emit them as its own dataChanges.
public final class FetchedResultsDataSource: DataSource {

	public let changes: Signal<DataChange, NoError>
	private let observer: Observer<DataChange, NoError>

	private let fetchedResultsControllerDelegate: Delegate
	public let fetchedResultsController: NSFetchedResultsController

	public init(fetchRequest: NSFetchRequest, managedObjectContext: NSManagedObjectContext, sectionNameKeyPath: String? = nil, cacheName: String? = nil) throws {
		(self.changes, self.observer) = Signal<DataChange, NoError>.pipe()
		self.fetchedResultsController = NSFetchedResultsController(fetchRequest: fetchRequest, managedObjectContext: managedObjectContext, sectionNameKeyPath: sectionNameKeyPath, cacheName: cacheName)
		self.fetchedResultsControllerDelegate = Delegate(observer: self.observer)
		self.fetchedResultsController.delegate = self.fetchedResultsControllerDelegate

		try self.fetchedResultsController.performFetch()
	}

	deinit {
		self.fetchedResultsController.delegate = nil
		self.observer.sendCompleted()
	}

	private func infoForSection(section: Int) -> NSFetchedResultsSectionInfo {
		return self.fetchedResultsController.sections![section]
	}

	public var numberOfSections: Int {
		return self.fetchedResultsController.sections?.count ?? 0
	}

	public func numberOfItemsInSection(section: Int) -> Int {
		let sectionInfo = self.infoForSection(section)
		return sectionInfo.numberOfObjects
	}

	public func supplementaryItemOfKind(kind: String, inSection section: Int) -> Any? {
		if kind != UICollectionElementKindSectionHeader {
			return nil
		}
		let sectionInfo = self.infoForSection(section)
		return sectionInfo.name
	}

	public func itemAtIndexPath(indexPath: NSIndexPath) -> Any {
		let sectionInfo = self.infoForSection(indexPath.section)
		return sectionInfo.objects![indexPath.item]
	}

	public func leafDataSourceAtIndexPath(indexPath: NSIndexPath) -> (DataSource, NSIndexPath) {
		return (self, indexPath)
	}

	@objc private final class Delegate: NSObject, NSFetchedResultsControllerDelegate {

		let observer: Observer<DataChange, NoError>
		var currentBatch: [DataChange] = []

		init(observer: Observer<DataChange, NoError>) {
			self.observer = observer
		}

		@objc func controllerWillChangeContent(controller: NSFetchedResultsController) {
			self.currentBatch = []
		}

		@objc func controllerDidChangeContent(controller: NSFetchedResultsController) {
			self.observer.sendNext(DataChangeBatch(self.currentBatch))
			self.currentBatch = []
		}

		@objc func controller(controller: NSFetchedResultsController,
			didChangeSection sectionInfo: NSFetchedResultsSectionInfo,
			atIndex sectionIndex: Int,
			forChangeType type: NSFetchedResultsChangeType)
		{
			switch type {
			case .Insert:
				self.currentBatch.append(DataChangeInsertSections(sectionIndex))
			case .Delete:
				self.currentBatch.append(DataChangeDeleteSections(sectionIndex))
			default:
				break
			}
		}

		@objc func controller(controller: NSFetchedResultsController,
			didChangeObject anObject: AnyObject,
			atIndexPath indexPath: NSIndexPath?,
			forChangeType type: NSFetchedResultsChangeType,
			newIndexPath: NSIndexPath?)
		{
			if type.rawValue == 0 {
				// This happens sometimes and corrupts the DataChangeTarget.
				// This is definitely not a valid NSFetchedResultsChangeType, so not sure why this is happening.
				return
			}
			
			switch type {
			case .Update:
				self.currentBatch.append(DataChangeReloadItems(indexPath!))
			case .Insert:
				self.currentBatch.append(DataChangeInsertItems(newIndexPath!))
			case .Move:
				if indexPath != newIndexPath {
					self.currentBatch.append(DataChangeMoveItem(from: indexPath!, to: newIndexPath!))
				}
			case .Delete:
				self.currentBatch.append(DataChangeDeleteItems(indexPath!))
			}
		}

	}

}
