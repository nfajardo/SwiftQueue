//
// Created by Lucas Nelaupe on 11/8/17.
// Copyright (c) 2017 Lucas Nelaupe. All rights reserved.
//

import XCTest
import Dispatch
@testable import SwiftQueue

class TestJob: Job {

    private let withCompletion: JobCompletion
    private let completionTimeout: TimeInterval
    private var withRetry: RetryConstraint

    private var onRunCount = 0
    private var onRetryCount = 0
    private var onCompletedCount = 0
    private var onCanceledCount = 0

    private let onRunSemaphore = DispatchSemaphore(value: 0)
    private let onRemoveSemaphore = DispatchSemaphore(value: 0)

    private var runSemaphoreValue = 0

    private var lastError: Error?

    init(completion: JobCompletion = .success, retry: RetryConstraint = .retry(delay: 0), _ completionTimeout: TimeInterval = 0) {
        self.withCompletion = completion
        self.withRetry = retry
        self.completionTimeout = completionTimeout
    }

    func onRun(callback: JobResult) {
        onRunCount += 1
        if runSemaphoreValue == onRunCount {
            onRunSemaphore.signal()
        }
        runInBackgroundAfter(completionTimeout) {
            callback.done(self.withCompletion)
        }
    }

    func onRetry(error: Error) -> RetryConstraint {
        lastError = error
        onRetryCount += 1
        return withRetry
    }

    func onRemove(result: JobCompletion) {
        switch result {
        case .success:
            onCompletedCount += 1
            onRemoveSemaphore.signal()

        case .fail(let error):
            lastError = error
            onCanceledCount += 1
            onRemoveSemaphore.signal()
        }
    }

    // Wait

    func awaitForRemoval(_ seconds: TimeInterval = TimeInterval(5)) {
        let delta = DispatchTime.now() + Double(Int64(seconds) * Int64(NSEC_PER_SEC)) / Double(NSEC_PER_SEC)
        _ = onRemoveSemaphore.wait(timeout: delta)
    }

    func awaitForRun(value: Int, _ seconds: TimeInterval = TimeInterval(5)) {
        let delta = DispatchTime.now() + Double(Int64(seconds) * Int64(NSEC_PER_SEC)) / Double(NSEC_PER_SEC)
        runSemaphoreValue = value
        _ = onRunSemaphore.wait(timeout: delta)
    }

    // Assertion

    public func assertRunCount(expected: Int, file: StaticString = #file, line: UInt = #line) {
        XCTAssertEqual(expected, onRunCount, file: file, line: line)
    }
    public func assertRunCount(atLeast: Int, file: StaticString = #file, line: UInt = #line) {
        XCTAssertTrue(onRunCount > atLeast, file: file, line: line)
    }
    public func assertCompletedCount(expected: Int, file: StaticString = #file, line: UInt = #line) {
        XCTAssertEqual(expected, onCompletedCount, file: file, line: line)
    }
    public func assertRetriedCount(expected: Int, file: StaticString = #file, line: UInt = #line) {
        XCTAssertEqual(expected, onRetryCount, file: file, line: line)
    }
    public func assertRetriedCount(atLeast: Int, file: StaticString = #file, line: UInt = #line) {
        XCTAssertTrue(onRetryCount > atLeast, file: file, line: line)
    }
    public func assertCanceledCount(expected: Int, file: StaticString = #file, line: UInt = #line) {
        XCTAssertEqual(expected, onCanceledCount, file: file, line: line)
    }
    public func assertError(file: StaticString = #file, line: UInt = #line) {
        XCTAssertTrue(lastError is JobError, file: file, line: line)
    }
    public func assertError(queueError: SwiftQueueError, file: StaticString = #file, line: UInt = #line) {
        XCTAssertEqual(lastError as? SwiftQueueError, queueError, file: file, line: line)
    }

    public func assertNoError(file: StaticString = #file, line: UInt = #line) {
        XCTAssertNil(lastError, file: file, line: line)
    }
    public func assertNoRun(file: StaticString = #file, line: UInt = #line) {
        self.assertRunCount(expected: 0, file: file, line: line)
        self.assertCompletedCount(expected: 0, file: file, line: line)
        self.assertRetriedCount(expected: 0, file: file, line: line)
        self.assertCanceledCount(expected: 0, file: file, line: line)
        self.assertNoError(file: file, line: line)
    }
    // Job has run once without error and completed
    public func assertSingleCompletion(file: StaticString = #file, line: UInt = #line) {
        self.assertRunCount(expected: 1, file: file, line: line)
        self.assertCompletedCount(expected: 1, file: file, line: line)
        self.assertRetriedCount(expected: 0, file: file, line: line)
        self.assertCanceledCount(expected: 0, file: file, line: line)
        self.assertNoError(file: file, line: line)
    }

    public func assertRemovedBeforeRun(reason: SwiftQueueError, file: StaticString = #file, line: UInt = #line) {
        self.assertRunCount(expected: 0, file: file, line: line)
        self.assertCompletedCount(expected: 0, file: file, line: line)
        self.assertRetriedCount(expected: 0, file: file, line: line)
        self.assertCanceledCount(expected: 1, file: file, line: line)
        self.assertError(queueError: reason, file: file, line: line)
    }

}

class TestCreator: JobCreator {
    private let job: [String: Job]

    public init(_ job: [String: Job]) {
        self.job = job
    }

    func create(type: String, params: [String: Any]?) -> Job? {
        return job[type] as? TestJob
    }
}

class PersisterTracker: UserDefaultsPersister {
    var restoreQueueName = ""

    var putQueueName: [String] = [String]()
    var putJobUUID: [String] = [String]()
    var putData: [String] = [String]()

    var removeQueueName: [String] = [String]()
    var removeJobUUID: [String] = [String]()

    override func restore(queueName: String) -> [String] {
        restoreQueueName = queueName
        return super.restore(queueName: queueName)
    }

    override func put(queueName: String, taskId: String, data: String) {
        putQueueName.append(queueName)
        putJobUUID.append(taskId)
        putData.append(data)
        super.put(queueName: queueName, taskId: taskId, data: data)
    }

    override func remove(queueName: String, taskId: String) {
        removeQueueName.append(queueName)
        removeJobUUID.append(taskId)
        super.remove(queueName: queueName, taskId: taskId)
    }
}

class JobError: Error {

}
