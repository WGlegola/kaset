import Foundation
import MediaPlayer
import Testing
@testable import Kaset

// MARK: - NowPlayingClaimTests

@Suite("Now playing claim", .serialized, .tags(.service))
struct NowPlayingClaimTests {
    @Test("Confirmed playback publishes state only (WebKit owns the card)")
    func activePlaybackIsStateOnly() {
        let track = (title: "Song", artist: "Artist")
        for webKitCardAvailable in [false, true] {
            #expect(NowPlayingManager.desiredClaim(
                state: .playing,
                track: track,
                activeVideo: nil,
                webKitCardAvailable: webKitCardAvailable
            ) == .stateOnly(.playing))
        }
    }

    @Test("Starting playback keeps an existing claim until playback is confirmed")
    func startingPlaybackIsHandsOff() {
        let track = (title: "Song", artist: "Artist")
        for state in [PlayerService.PlaybackState.loading, .buffering] {
            #expect(NowPlayingManager.desiredClaim(
                state: state,
                track: track,
                activeVideo: nil,
                webKitCardAvailable: false
            ) == .handsOff)
        }
    }

    @Test("Not playing with a track yields a minimal claim before the page has played")
    func pausedWithTrackClaims() {
        let track = (title: "Song", artist: "Artist")
        let expected = NowPlayingManager.NowPlayingClaim.claim(
            title: "Song",
            artist: "Artist",
            playbackState: .paused
        )
        for state in [PlayerService.PlaybackState.paused, .ended, .idle, .error("boom")] {
            #expect(NowPlayingManager.desiredClaim(
                state: state,
                track: track,
                activeVideo: nil,
                webKitCardAvailable: false
            ) == expected)
        }
    }

    /// WebKit publishes its card as a separate Now Playing entry, so a titled claim next to it
    /// shows up as a second Kaset entry in Control Center (#457).
    @Test("Not playing with a track publishes state only once WebKit's card exists")
    func pausedAfterPlaybackIsStateOnly() {
        let track = (title: "Song", artist: "Artist")
        for state in [PlayerService.PlaybackState.paused, .ended, .idle, .error("boom")] {
            #expect(NowPlayingManager.desiredClaim(
                state: state,
                track: track,
                activeVideo: nil,
                webKitCardAvailable: true
            ) == .stateOnly(.paused))
        }
    }

    @Test("Not playing with no track releases the native claim")
    func idleWithoutTrackReleasesClaim() {
        for webKitCardAvailable in [false, true] {
            #expect(NowPlayingManager.desiredClaim(
                state: .idle,
                track: nil,
                activeVideo: nil,
                webKitCardAvailable: webKitCardAvailable
            ) == .release)
            #expect(NowPlayingManager.desiredClaim(
                state: .paused,
                track: nil,
                activeVideo: nil,
                webKitCardAvailable: webKitCardAvailable
            ) == .release)
        }
    }

    @Test("Video media-key ownership uses video metadata until playback is confirmed")
    func videoOwnershipUsesFallbackClaim() {
        let track = (title: "Song", artist: "Artist")
        let video = NowPlayingManager.ActiveVideoClaim(
            title: "Video",
            artist: "Channel",
            playbackState: .paused,
            isPlaybackConfirmed: false
        )
        let expected = NowPlayingManager.NowPlayingClaim.claim(
            title: "Video",
            artist: "Channel",
            playbackState: .paused
        )

        #expect(NowPlayingManager.desiredClaim(
            state: .paused,
            track: track,
            activeVideo: video,
            webKitCardAvailable: true
        ) == expected)
    }

    @Test("Confirmed video playback hands the Now Playing card to WebKit")
    func playingVideoIsHandsOff() {
        let track = (title: "Song", artist: "Artist")
        let video = NowPlayingManager.ActiveVideoClaim(
            title: "Video",
            artist: "Channel",
            playbackState: .playing,
            isPlaybackConfirmed: true
        )

        #expect(NowPlayingManager.desiredClaim(
            state: .paused,
            track: track,
            activeVideo: video,
            webKitCardAvailable: true
        ) == .handsOff)
    }

    @Test("A loading video keeps its fallback even if the previous document was playing")
    func loadingVideoWithStalePlayingStateKeepsClaim() {
        let video = NowPlayingManager.ActiveVideoClaim(
            title: "Next Video",
            artist: "Channel",
            playbackState: .playing,
            isPlaybackConfirmed: false
        )
        let expected = NowPlayingManager.NowPlayingClaim.claim(
            title: "Next Video",
            artist: "Channel",
            playbackState: .playing
        )

        #expect(NowPlayingManager.desiredClaim(
            state: .paused,
            track: nil,
            activeVideo: video,
            webKitCardAvailable: false
        ) == expected)
    }

    @Test("Confirmed playback drops the claim's metadata but keeps Kaset's playback state")
    @MainActor
    func stateOnlyDropsClaimMetadata() {
        let center = FakeNowPlayingCenter()
        var ownership = NowPlayingManager.apply(
            .claim(title: "Song", artist: "Artist", playbackState: .paused),
            to: center,
            ownership: .none
        )

        ownership = NowPlayingManager.apply(.stateOnly(.playing), to: center, ownership: ownership)

        #expect(ownership == .stateOnly)
        #expect(center.nowPlayingInfo == nil)
        #expect(center.playbackState == .playing)
    }

    @Test("Pausing after the page has played publishes no metadata")
    @MainActor
    func stateOnlyPauseHasNoMetadata() {
        let center = FakeNowPlayingCenter()
        var ownership = NowPlayingManager.apply(.stateOnly(.playing), to: center, ownership: .none)

        ownership = NowPlayingManager.apply(.stateOnly(.paused), to: center, ownership: ownership)

        #expect(ownership == .stateOnly)
        #expect(center.nowPlayingInfo == nil)
        #expect(center.playbackState == .paused)
    }

    @Test("Hands-off keeps an existing claim marked as playing")
    @MainActor
    func handsOffKeepsClaim() {
        let center = FakeNowPlayingCenter()
        var ownership = NowPlayingManager.apply(
            .claim(title: "Song", artist: "Artist", playbackState: .paused),
            to: center,
            ownership: .none
        )

        ownership = NowPlayingManager.apply(.handsOff, to: center, ownership: ownership)

        #expect(ownership == .claim)
        #expect(NowPlayingManager.isNativeClaim(center.nowPlayingInfo))
        #expect(center.playbackState == .playing)
    }

    /// A track change mid-playback passes through `.loading` while WebKit's card is up, so
    /// hands-off must not publish an entry of its own.
    @Test("Hands-off never publishes a new claim")
    @MainActor
    func handsOffDoesNotPublish() {
        let center = FakeNowPlayingCenter()

        let ownership = NowPlayingManager.apply(.handsOff, to: center, ownership: .none)

        #expect(ownership == .none)
        #expect(center.nowPlayingInfo == nil)
        #expect(center.playbackState == .unknown)
    }

    @Test("Releasing after state-only playback stops Kaset's player")
    @MainActor
    func releaseAfterStateOnlyStops() {
        let center = FakeNowPlayingCenter()
        var ownership = NowPlayingManager.apply(.stateOnly(.paused), to: center, ownership: .none)

        ownership = NowPlayingManager.apply(.release, to: center, ownership: ownership)

        #expect(ownership == .none)
        #expect(center.nowPlayingInfo == nil)
        #expect(center.playbackState == .stopped)
    }

    @Test("State-only never clears metadata Kaset did not publish")
    @MainActor
    func stateOnlyLeavesForeignMetadata() {
        let center = FakeNowPlayingCenter()
        center.nowPlayingInfo = [MPMediaItemPropertyTitle: "Someone else's card"]

        _ = NowPlayingManager.apply(.stateOnly(.paused), to: center, ownership: .claim)

        #expect(center.nowPlayingInfo?[MPMediaItemPropertyTitle] as? String == "Someone else's card")
    }

    @Test("A titled claim hands over to state only and back through a session")
    @MainActor
    func claimLifecycleThroughPlaybackSession() {
        let center = FakeNowPlayingCenter()
        // Cold launch with a restored track: WebKit has no card yet.
        var ownership = NowPlayingManager.apply(
            .claim(title: "Song", artist: "Artist", playbackState: .paused),
            to: center,
            ownership: .none
        )
        #expect(NowPlayingManager.isNativeClaim(center.nowPlayingInfo))

        // Loading keeps the claim; confirmed playback drops its metadata.
        ownership = NowPlayingManager.apply(.handsOff, to: center, ownership: ownership)
        #expect(NowPlayingManager.isNativeClaim(center.nowPlayingInfo))
        ownership = NowPlayingManager.apply(.stateOnly(.playing), to: center, ownership: ownership)
        #expect(center.nowPlayingInfo == nil)

        // Pausing, loading the next track and playing it never brings metadata back.
        for claim in [NowPlayingManager.NowPlayingClaim.stateOnly(.paused), .handsOff, .stateOnly(.playing)] {
            ownership = NowPlayingManager.apply(claim, to: center, ownership: ownership)
            #expect(ownership == .stateOnly)
            #expect(center.nowPlayingInfo == nil)
        }
        #expect(center.playbackState == .playing)

        ownership = NowPlayingManager.apply(.release, to: center, ownership: ownership)
        #expect(ownership == .none)
        #expect(center.playbackState == .stopped)
    }

    @Test("WebKit's card is available once the current page has played")
    func cardAvailableAfterCurrentPagePlays() {
        var tracker = NowPlayingManager.WebKitCardTracker()

        let beforePlaying = tracker.observe(isPlaying: false, hasTrack: true, documentGeneration: 1)
        let whilePlaying = tracker.observe(isPlaying: true, hasTrack: true, documentGeneration: 1)
        let afterPausing = tracker.observe(isPlaying: false, hasTrack: true, documentGeneration: 1)

        #expect(!beforePlaying)
        #expect(whilePlaying)
        #expect(afterPausing)
    }

    @Test("A replaced page has no card until it plays")
    func replacedPageHasNoCardUntilItPlays() {
        var tracker = NowPlayingManager.WebKitCardTracker()
        _ = tracker.observe(isPlaying: true, hasTrack: true, documentGeneration: 1)

        let replacedBeforePlaying = tracker.observe(isPlaying: false, hasTrack: true, documentGeneration: 2)
        let replacedWhilePlaying = tracker.observe(isPlaying: true, hasTrack: true, documentGeneration: 2)

        #expect(!replacedBeforePlaying)
        #expect(replacedWhilePlaying)
    }

    @Test("Clearing the track forgets the card")
    func clearingTrackForgetsCard() {
        var tracker = NowPlayingManager.WebKitCardTracker()
        _ = tracker.observe(isPlaying: true, hasTrack: true, documentGeneration: 1)

        let withoutTrack = tracker.observe(isPlaying: false, hasTrack: false, documentGeneration: 1)
        let nextTrackBeforePlaying = tracker.observe(isPlaying: false, hasTrack: true, documentGeneration: 1)

        #expect(!withoutTrack)
        #expect(!nextTrackBeforePlaying)
    }

    @Test("Only tagged native metadata is treated as Kaset's claim")
    func nativeClaimOwnershipTag() {
        let nativeInfo: [String: Any] = [
            MPNowPlayingInfoPropertyServiceIdentifier: NowPlayingManager.nativeClaimServiceIdentifier,
        ]
        let webKitInfo: [String: Any] = [MPMediaItemPropertyTitle: "Song"]

        #expect(NowPlayingManager.isNativeClaim(nativeInfo))
        #expect(NowPlayingManager.isNativeClaim(webKitInfo) == false)
        #expect(NowPlayingManager.isNativeClaim(nil) == false)
    }
}

// MARK: - FakeNowPlayingCenter

@MainActor
private final class FakeNowPlayingCenter: NowPlayingInfoPublishing {
    var nowPlayingInfo: [String: Any]?
    var playbackState: MPNowPlayingPlaybackState = .unknown
}
