import Combine
import CoreGraphics
import Testing
import FridayCore
@testable import FridayApp

private func artwork(frames count: Int) -> MascotArtwork {
    let pixel = CGContext(
        data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!.makeImage()!
    return MascotArtwork(frames: Array(repeating: pixel, count: count), frameDuration: 0.1)
}

@Test func reactionLoopsWithoutRest() {
    let reaction = artwork(frames: 5)
    #expect(reaction.frameIndex(at: 0.05, rest: 0) == 0)
    #expect(reaction.frameIndex(at: 0.35, rest: 0) == 3)
    #expect(reaction.frameIndex(at: 0.65, rest: 0) == 1)
}

@Test func normalMascotRestsOnFirstFrameBetweenLoops() {
    let normal = artwork(frames: 5)
    #expect(normal.frameIndex(at: 1.95, rest: 2) == 0)
    #expect(normal.frameIndex(at: 2.25, rest: 2) == 2)
    #expect(normal.frameIndex(at: 2.55, rest: 2) == 0)
}

@Test func staticMascotAlwaysShowsItsOnlyFrame() {
    #expect(artwork(frames: 1).frameIndex(at: 12.3, rest: 0) == 0)
}

@MainActor @Test func missingReactionFallsBackToBundledNormalMascot() throws {
    let normal = try #require(MascotLibrary.artwork(named: MascotLibrary.normal))
    let fallback = try #require(MascotLibrary.artwork(named: "mascot-missing"))
    #expect(fallback.frames.count == normal.frames.count)
    #expect(normal.frameDuration > 0)
}

@MainActor @Test func queuedReactionsEachPlayOneLoopBeforeTheMascotSettlesAndDozes() async throws {
    let director = MascotDirector(loopDuration: { _ in 0.02 }, dozeDelay: 0.05)
    var poses: [String] = []
    let subscription = director.$pose.sink { poses.append($0) }
    defer { subscription.cancel() }

    director.react(to: .deciding)
    director.react(to: .acting)
    director.react(to: .idle)
    try await Task.sleep(for: .milliseconds(400))

    #expect(poses == ["mascot", "mascot-focused", "mascot-excited", "mascot", "mascot-sleeping"])
}

@MainActor @Test func carryingInterruptsQueuedReactions() async throws {
    let director = MascotDirector(loopDuration: { _ in 0.02 }, dozeDelay: 10)
    director.react(to: .deciding)
    director.react(to: .reasoning)
    director.carry(true, phase: .reasoning)
    try await Task.sleep(for: .milliseconds(150))
    #expect(director.pose == MascotLibrary.held)

    director.carry(false, phase: .idle)
    try await Task.sleep(for: .milliseconds(150))
    #expect(director.pose == MascotLibrary.normal)
}

@MainActor @Test func failureIsShownOnceBeforeTheMascotCalmsDown() async throws {
    let director = MascotDirector(loopDuration: { _ in 0.02 }, dozeDelay: 10)
    var poses: [String] = []
    let subscription = director.$pose.sink { poses.append($0) }
    defer { subscription.cancel() }

    director.react(to: .failed)
    try await Task.sleep(for: .milliseconds(200))

    #expect(poses == ["mascot", "mascot-worried", "mascot"])
}
