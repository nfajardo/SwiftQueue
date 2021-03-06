//
// Created by Lucas Nelaupe on 11/8/17.
// Copyright (c) 2017 Lucas Nelaupe. All rights reserved.
//

import XCTest
@testable import SwiftQueue

class ConstraintTests: XCTestCase {

    func testPeriodicJob() {
        let job = TestJob()
        let type = UUID().uuidString

        let creator = TestCreator([type: job])

        let manager = SwiftQueueManager(creators: [creator])
        JobBuilder(type: type)
                .periodic(limit: .limited(5))
                .schedule(manager: manager)

        job.awaitForRemoval()
        job.assertRunCount(expected: 5)
        job.assertCompletedCount(expected: 1)
        job.assertRetriedCount(expected: 0)
        job.assertCanceledCount(expected: 0)
        job.assertNoError()
    }

    func testPeriodicJobUnlimited() {
        let job = TestJob()
        let type = UUID().uuidString

        let creator = TestCreator([type: job])

        let manager = SwiftQueueManager(creators: [creator])
        JobBuilder(type: type)
                .periodic(limit: .unlimited)
                .schedule(manager: manager)

        // Should run at least 100 times
        job.awaitForRun(value: 10000)
        job.assertRunCount(atLeast: 50)
        job.assertCompletedCount(expected: 0)
        job.assertRetriedCount(expected: 0)
        job.assertCanceledCount(expected: 0)
        job.assertNoError()

    }

    func testRetryFailJobWithRetryConstraint() {
        let job = TestJob(completion: .fail(JobError()), retry: .retry(delay: 0))
        let type = UUID().uuidString

        let creator = TestCreator([type: job])

        let manager = SwiftQueueManager(creators: [creator])
        JobBuilder(type: type)
                .retry(limit: .limited(2))
                .schedule(manager: manager)

        job.awaitForRemoval()
        job.assertRunCount(expected: 3)
        job.assertCompletedCount(expected: 0)
        job.assertRetriedCount(expected: 2)
        job.assertCanceledCount(expected: 1)
        job.assertError()
    }

    func testRetryFailJobWithRetryDelayConstraint() {
        let job = TestJob(completion: .fail(JobError()), retry: .retry(delay: Double.leastNonzeroMagnitude))
        let type = UUID().uuidString

        let creator = TestCreator([type: job])

        let manager = SwiftQueueManager(creators: [creator])
        JobBuilder(type: type)
                .retry(limit: .limited(2))
                .schedule(manager: manager)

        job.awaitForRemoval()
        job.assertRunCount(expected: 3)
        job.assertCompletedCount(expected: 0)
        job.assertRetriedCount(expected: 2)
        job.assertCanceledCount(expected: 1)
        job.assertError()
    }

    func testRetryUnlimitedShouldRetryManyTimes() {
        let job = TestJob(completion: .fail(JobError()), retry: .retry(delay: 0))
        let type = UUID().uuidString

        let creator = TestCreator([type: job])

        let manager = SwiftQueueManager(creators: [creator])
        JobBuilder(type: type)
                .retry(limit: .unlimited)
                .schedule(manager: manager)

        job.awaitForRun(value: 10000)
        job.assertRunCount(atLeast: 50)
        job.assertCompletedCount(expected: 0)
        job.assertRetriedCount(atLeast: 50)
        job.assertCanceledCount(expected: 0)
        job.assertError()
    }

    func testRetryFailJobWithCancelConstraint() {
        let job = TestJob(completion: .fail(JobError()), retry: .cancel)
        let type = UUID().uuidString

        let creator = TestCreator([type: job])

        let manager = SwiftQueueManager(creators: [creator])
        JobBuilder(type: type)
                .retry(limit: .limited(2))
                .schedule(manager: manager)

        job.awaitForRemoval()
        job.assertRunCount(expected: 1)
        job.assertCompletedCount(expected: 0)
        job.assertRetriedCount(expected: 1)
        job.assertCanceledCount(expected: 1)
        // TODO here the error is not forwared
        job.assertError(queueError: .canceled)
    }

    func testRetryFailJobWithExponentialConstraint() {
        let job = TestJob(completion: .fail(JobError()), retry: .exponential(initial: 0))
        let type = UUID().uuidString

        let creator = TestCreator([type: job])

        let manager = SwiftQueueManager(creators: [creator])
        JobBuilder(type: type)
                .retry(limit: .limited(2))
                .schedule(manager: manager)

        job.awaitForRemoval()
        job.assertRunCount(expected: 3)
        job.assertCompletedCount(expected: 0)
        job.assertRetriedCount(expected: 2)
        job.assertCanceledCount(expected: 1)
        job.assertError()
    }

    func testRepeatableJobWithExponentialBackoffRetry() {
        let type = UUID().uuidString
        let job = TestJob(completion: .fail(JobError()), retry: .exponential(initial: Double.leastNonzeroMagnitude))

        let creator = TestCreator([type: job])

        let manager = SwiftQueueManager(creators: [creator])
        JobBuilder(type: type)
                .retry(limit: .limited(1))
                .periodic()
                .schedule(manager: manager)

        job.awaitForRemoval()
        job.assertRunCount(expected: 2)
        job.assertCompletedCount(expected: 0)
        job.assertRetriedCount(expected: 1)
        job.assertCanceledCount(expected: 1)
        job.assertError()
    }

    func testRepeatableJobWithDelay() {
        let job = TestJob()
        let type = UUID().uuidString

        let creator = TestCreator([type: job])

        let manager = SwiftQueueManager(creators: [creator])
        JobBuilder(type: type)
                .periodic(limit: .limited(2), interval: Double.leastNonzeroMagnitude)
                .schedule(manager: manager)

        job.awaitForRemoval()
        job.assertRunCount(expected: 2)
        job.assertCompletedCount(expected: 1)
        job.assertRetriedCount(expected: 0)
        job.assertCanceledCount(expected: 0)
        job.assertNoError()
    }

    func testCancelRunningOperation() {
        let job = TestJob(10)
        let type = UUID().uuidString

        let creator = TestCreator([type: job])

        let manager = SwiftQueueManager(creators: [creator])
        JobBuilder(type: type)
                .schedule(manager: manager)

        runInBackgroundAfter(0.01) {
            manager.cancelAllOperations()
        }

        job.awaitForRemoval()
        job.assertRunCount(expected: 1)
        job.assertCompletedCount(expected: 0)
        job.assertRetriedCount(expected: 0)
        job.assertCanceledCount(expected: 1)
        job.assertError(queueError: .canceled)
    }

    func testCancelRunningOperationByTag() {
        let job = TestJob(10)
        let type = UUID().uuidString

        let tag = UUID().uuidString

        let creator = TestCreator([type: job])

        let manager = SwiftQueueManager(creators: [creator])
        JobBuilder(type: type)
                .addTag(tag: tag)
                .schedule(manager: manager)

        runInBackgroundAfter(0.01) {
            manager.cancelOperations(tag: tag)
        }

        job.awaitForRemoval()
        job.assertRunCount(expected: 1)
        job.assertCompletedCount(expected: 0)
        job.assertRetriedCount(expected: 0)
        job.assertCanceledCount(expected: 1)
        job.assertError(queueError: .canceled)
    }
}
