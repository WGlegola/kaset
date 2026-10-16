# ADR-0042: Single Now Playing entry

## Status

Accepted

## Context

Music plays in a `WKWebView` (ADR-0001), and WebKit publishes its own Now Playing card for the
page: artwork, artist and album, and the page's media-session actions. Since #387, Kaset also
publishes a small tagged entry (title and artist) through `MPNowPlayingInfoCenter`, so the Play key
resumes Kaset instead of Apple Music while music is paused.

The handoff assumed WebKit's card replaces the app's metadata. It does not: WebKit's card is a
separate Now Playing entry. Kaset's entry stayed alongside it, marked as playing during playback,
so Control Center showed Kaset twice (#457).

Measured with a trace of remote commands, Now Playing decisions, page media-session actions and
observed page state:

- Kaset's own entry is a media-key target only while it is the most recently playing one. Keeping
  it marked as playing during playback is what routed media keys to Kaset, which is also what made
  it a visible duplicate.
- With Kaset's entry withdrawn, media keys go to WebKit's card. A pause from the card or a media key
  works, but after an in-app pause the page's playback suppression (`__kasetPlaybackSuppressed`)
  cancels the card's play, so Play did nothing.
- An entry with playback state but no metadata does not appear in Control Center.

## Decision

- WebKit's play and pause media-session actions are Kaset-owned, like next and previous: the
  document-start wrapper keeps YouTube from registering them, and the override script installs
  handlers that post `REMOTE_PLAY` and `REMOTE_PAUSE`. These go through the same native transport
  queue as media keys, so a play after an in-app pause clears Kaset's pause intent.
- Once the current music page (by document generation) has confirmed playback, Kaset publishes
  playback state only (no metadata). WebKit's card is then the single Kaset entry, and Kaset's own
  player stays a media-key target.
- Before that page has played, inactive music keeps the tagged minimal entry from #387, since
  WebKit has no card for it yet. This includes a page replaced by a full load or recovery. A
  loading track keeps an existing entry without publishing a new one.
- YouTube video keeps its existing fallback behavior.

## Consequences

### Positive

- One Kaset entry in Control Center for music, playing or paused.
- Play and pause on WebKit's card, media keys and Kaset's own controls all go through the native
  player, whichever entry macOS routes the key to.

### Negative

- YouTube video still keeps its fallback entry next to WebKit's card while a video plays. Its
  watch page would need the same play/pause routing before it can drop the fallback.
- The music page no longer runs YouTube's own play/pause handlers; Kaset's native resume and pause
  drive the page instead.
