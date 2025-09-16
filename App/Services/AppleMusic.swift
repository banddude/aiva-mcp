import Foundation
import JSONSchema
import OSLog
@preconcurrency import MusicKit

private let log = Logger.service("applemusic")

@MainActor
final class AppleMusicService: Service, Sendable {
    static let shared = AppleMusicService()
    
    // MusicKit configuration
    private let teamID = "6D4T7VB2AF" // Michael Shaffer's Team ID
    private let keyID = "UFY5C8RBAH" // Your MusicKit key ID
    private let bundleID = "com.mikeshaffer.AIVA" // Your bundle ID
    
    var isActivated: Bool {
        get async {
            // Check MusicKit authorization status
            let status = MusicAuthorization.currentStatus
            return status == .authorized
        }
    }
    
    func activate() async throws {
        // Request MusicKit authorization
        let status = await MusicAuthorization.request()
        
        switch status {
        case .authorized:
            log.info("Apple Music service activated successfully")
            print("✅ Apple Music service activated successfully")
        case .denied:
            log.error("Apple Music authorization denied")
            print("❌ Apple Music authorization denied")
            throw AppleMusicError.authorizationDenied
        case .restricted:
            log.error("Apple Music access restricted")
            print("❌ Apple Music access restricted")
            throw AppleMusicError.accessRestricted
        case .notDetermined:
            log.error("Apple Music authorization not determined")
            print("❌ Apple Music authorization not determined")
            throw AppleMusicError.authorizationNotDetermined
        @unknown default:
            log.error("Unknown Apple Music authorization status")
            print("❌ Unknown Apple Music authorization status")
            throw AppleMusicError.unknownAuthorizationStatus
        }
    }
    
    nonisolated var tools: [Tool] {
        [
            // Check subscription status
            Tool(
                name: "apple_music_subscription_status",
                description: "Check if user has an active Apple Music subscription",
                inputSchema: .object(
                    properties: [:],
                    required: [],
                    additionalProperties: false
                ),
                annotations: .init(title: "Check Apple Music Subscription", readOnlyHint: true, openWorldHint: false)
            ) { _ in
                let canPlayCatalogContent = try await MusicSubscription.current.canPlayCatalogContent
                let canBecomeSubscriber = try await MusicSubscription.current.canBecomeSubscriber
                
                return """
                Apple Music Subscription Status:
                - Can play catalog content: \(canPlayCatalogContent ? "Yes" : "No")
                - Can become subscriber: \(canBecomeSubscriber ? "Yes" : "No")
                """
            },
            
            // Search Apple Music catalog
            Tool(
                name: "apple_music_search",
                description: "Search the Apple Music catalog for songs, albums, or artists",
                inputSchema: .object(
                    properties: [
                        "query": .string(description: "Search query (song name, artist, album)"),
                        "types": .array(
                            description: "Types of content to search for (default: songs)",
                            items: .string(enum: ["songs", "albums", "artists", "playlists"])
                        ),
                        "limit": .integer(description: "Maximum number of results (default: 10)")
                    ],
                    required: ["query"],
                    additionalProperties: false
                ),
                annotations: .init(title: "Search Apple Music", readOnlyHint: true, openWorldHint: false)
            ) { params in
                let query = params["query"]?.stringValue ?? ""
                let limit = params["limit"]?.intValue ?? 10
                let types = params["types"]?.arrayValue?.compactMap { $0.stringValue } ?? ["songs"]
                
                return try await self.searchAppleMusic(query: query, types: types, limit: limit)
            },
            
            // Play a song
            Tool(
                name: "apple_music_play_song",
                description: "Play a specific song by ID from Apple Music catalog",
                inputSchema: .object(
                    properties: [
                        "songID": .string(description: "Apple Music song ID"),
                        "startTime": .number(description: "Start time in seconds (optional)")
                    ],
                    required: ["songID"],
                    additionalProperties: false
                ),
                annotations: .init(title: "Play Apple Music Song", readOnlyHint: false, openWorldHint: false)
            ) { params in
                let songID = params["songID"]?.stringValue ?? ""
                let startTime = params["startTime"]?.doubleValue
                
                return try await self.playSong(id: songID, startTime: startTime)
            },
            
            // Playback controls
            Tool(
                name: "apple_music_play",
                description: "Start or resume Apple Music playback",
                inputSchema: .object(
                    properties: [:],
                    required: [],
                    additionalProperties: false
                ),
                annotations: .init(title: "Play Apple Music", readOnlyHint: false, openWorldHint: false)
            ) { _ in
                try await self.play()
                return "Apple Music playback started"
            },
            
            Tool(
                name: "apple_music_pause",
                description: "Pause Apple Music playback",
                inputSchema: .object(
                    properties: [:],
                    required: [],
                    additionalProperties: false
                ),
                annotations: .init(title: "Pause Apple Music", readOnlyHint: false, openWorldHint: false)
            ) { _ in
                try await self.pause()
                return "Apple Music playback paused"
            },
            
            Tool(
                name: "apple_music_skip_forward",
                description: "Skip to next track in Apple Music",
                inputSchema: .object(
                    properties: [:],
                    required: [],
                    additionalProperties: false
                ),
                annotations: .init(title: "Next Track", readOnlyHint: false, openWorldHint: false)
            ) { _ in
                try await self.skipForward()
                return "Skipped to next track"
            },
            
            Tool(
                name: "apple_music_skip_backward",
                description: "Skip to previous track in Apple Music",
                inputSchema: .object(
                    properties: [:],
                    required: [],
                    additionalProperties: false
                ),
                annotations: .init(title: "Previous Track", readOnlyHint: false, openWorldHint: false)
            ) { _ in
                try await self.skipBackward()
                return "Skipped to previous track"
            },
            
            // Current playback status
            Tool(
                name: "apple_music_now_playing",
                description: "Get information about the currently playing track",
                inputSchema: .object(
                    properties: [:],
                    required: [],
                    additionalProperties: false
                ),
                annotations: .init(title: "Now Playing", readOnlyHint: true, openWorldHint: false)
            ) { _ in
                return try await self.getCurrentlyPlaying()
            },
            
            // Play album
            Tool(
                name: "apple_music_play_album",
                description: "Play an entire album from Apple Music catalog",
                inputSchema: .object(
                    properties: [
                        "albumID": .string(description: "Apple Music album ID"),
                        "startSong": .string(description: "Optional song ID to start from (default: first track)")
                    ],
                    required: ["albumID"],
                    additionalProperties: false
                ),
                annotations: .init(title: "Play Apple Music Album", readOnlyHint: false, openWorldHint: false)
            ) { params in
                let albumID = params["albumID"]?.stringValue ?? ""
                let startSongID = params["startSong"]?.stringValue
                
                return try await self.playAlbum(id: albumID, startSongID: startSongID)
            },
            
            // Play playlist
            Tool(
                name: "apple_music_play_playlist",
                description: "Play an entire playlist from Apple Music catalog",
                inputSchema: .object(
                    properties: [
                        "playlistID": .string(description: "Apple Music playlist ID"),
                        "shuffle": .boolean(description: "Shuffle the playlist (default: false)")
                    ],
                    required: ["playlistID"],
                    additionalProperties: false
                ),
                annotations: .init(title: "Play Apple Music Playlist", readOnlyHint: false, openWorldHint: false)
            ) { params in
                let playlistID = params["playlistID"]?.stringValue ?? ""
                let shuffle = params["shuffle"]?.boolValue ?? false
                
                return try await self.playPlaylist(id: playlistID, shuffle: shuffle)
            }
        ]
    }
}

// MARK: - Implementation Methods
extension AppleMusicService {
    
    private func searchAppleMusic(query: String, types: [String], limit: Int) async throws -> String {
        // Create search request for songs by default
        var request = MusicCatalogSearchRequest(term: query, types: [Song.self])
        
        // Handle multiple types
        if types.contains("albums") {
            request = MusicCatalogSearchRequest(term: query, types: [Album.self])
        } else if types.contains("artists") {
            request = MusicCatalogSearchRequest(term: query, types: [Artist.self])
        } else if types.contains("playlists") {
            request = MusicCatalogSearchRequest(term: query, types: [Playlist.self])
        }
        
        request.limit = limit
        
        let response = try await request.response()
        
        var results: [String] = []
        
        // Handle song results
        for song in response.songs {
            let artist = song.artistName
            let album = song.albumTitle ?? "Unknown Album"
            results.append("🎵 \(song.title) by \(artist) (\(album)) - ID: \(song.id)")
        }
        
        // Handle album results  
        for album in response.albums {
            let artist = album.artistName
            results.append("💿 \(album.title) by \(artist) - ID: \(album.id)")
        }
        
        // Handle artist results
        for artist in response.artists {
            results.append("👨‍🎤 \(artist.name) - ID: \(artist.id)")
        }
        
        // Handle playlist results
        for playlist in response.playlists {
            let curator = playlist.curatorName ?? "Apple Music"
            results.append("📻 \(playlist.name) by \(curator) - ID: \(playlist.id)")
        }
        
        if results.isEmpty {
            return "No results found for '\(query)'"
        }
        
        return "Search results for '\(query)':\n\n" + results.joined(separator: "\n")
    }
    
    private func playSong(id: String, startTime: Double? = nil) async throws -> String {
        let player = ApplicationMusicPlayer.shared
        
        // Create a queue with the specific song
        let request = MusicCatalogResourceRequest<Song>(matching: \.id, equalTo: MusicItemID(id))
        let response = try await request.response()
        
        guard let song = response.items.first else {
            throw AppleMusicError.songNotFound
        }
        
        player.queue = ApplicationMusicPlayer.Queue(for: [song], startingAt: song)
        
        if let startTime = startTime {
            player.playbackTime = startTime
        }
        
        try await player.play()
        
        return "Now playing: \(song.title) by \(song.artistName)"
    }
    
    private func play() async throws {
        let player = ApplicationMusicPlayer.shared
        try await player.play()
    }
    
    private func pause() async throws {
        let player = ApplicationMusicPlayer.shared
        player.pause()
    }
    
    private func skipForward() async throws {
        let player = ApplicationMusicPlayer.shared
        try await player.skipToNextEntry()
    }
    
    private func skipBackward() async throws {
        let player = ApplicationMusicPlayer.shared
        try await player.skipToPreviousEntry()
    }
    
    private func getCurrentlyPlaying() async throws -> String {
        let player = ApplicationMusicPlayer.shared
        
        guard player.queue.currentEntry != nil else {
            return "No song currently playing"
        }
        
        let playbackTime = player.playbackTime
        let state = player.state.playbackStatus
        
        // For now, just show basic playback info to avoid casting issues
        // MusicKit's type system can be complex across different content types
        return """
        Now Playing:
        🎵 Current track
        ⏱️ \(formatTime(playbackTime))
        ▶️ Status: \(state)
        """
    }
    
    private func formatTime(_ timeInterval: TimeInterval) -> String {
        let minutes = Int(timeInterval) / 60
        let seconds = Int(timeInterval) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    private func playAlbum(id: String, startSongID: String? = nil) async throws -> String {
        let player = ApplicationMusicPlayer.shared
        
        // Get the album from the catalog
        let request = MusicCatalogResourceRequest<Album>(matching: \.id, equalTo: MusicItemID(id))
        let response = try await request.response()
        
        guard let album = response.items.first else {
            throw AppleMusicError.songNotFound // Reusing this error for albums
        }
        
        // Get album tracks
        let detailedAlbum = try await album.with(.tracks)
        guard let tracks = detailedAlbum.tracks else {
            return "Album found but no tracks available"
        }
        
        // Find starting song or use first track
        let startingTrack: Track
        if let startSongID = startSongID,
           let specificTrack = tracks.first(where: { $0.id.rawValue == startSongID }) {
            startingTrack = specificTrack
        } else {
            guard let firstTrack = tracks.first else {
                return "Album has no playable tracks"
            }
            startingTrack = firstTrack
        }
        
        // Create queue with all album tracks starting from the specified song
        let tracksArray: [Track] = Array(tracks)
        player.queue = ApplicationMusicPlayer.Queue(for: tracksArray, startingAt: startingTrack)
        
        try await player.play()
        
        return "Now playing album: \(album.title) by \(album.artistName) (\(tracksArray.count) tracks)"
    }
    
    private func playPlaylist(id: String, shuffle: Bool = false) async throws -> String {
        let player = ApplicationMusicPlayer.shared
        
        // Get the playlist from the catalog
        let request = MusicCatalogResourceRequest<Playlist>(matching: \.id, equalTo: MusicItemID(id))
        let response = try await request.response()
        
        guard let playlist = response.items.first else {
            throw AppleMusicError.songNotFound // Reusing this error for playlists
        }
        
        // Get playlist tracks
        let detailedPlaylist = try await playlist.with(.tracks)
        guard let tracks = detailedPlaylist.tracks else {
            return "Playlist found but no tracks available"
        }
        
        // Convert to array and optionally shuffle
        var tracksArray: [Track] = Array(tracks)
        if shuffle {
            tracksArray.shuffle()
        }
        
        guard !tracksArray.isEmpty else {
            return "Playlist has no playable tracks"
        }
        
        // Create queue with all playlist tracks
        player.queue = ApplicationMusicPlayer.Queue(for: tracksArray)
        
        try await player.play()
        
        let shuffleStatus = shuffle ? " (shuffled)" : ""
        return "Now playing playlist: \(playlist.name) (\(tracksArray.count) tracks)\(shuffleStatus)"
    }
}

// MARK: - Error Types
enum AppleMusicError: Error, LocalizedError {
    case authorizationDenied
    case accessRestricted
    case authorizationNotDetermined
    case unknownAuthorizationStatus
    case songNotFound
    case subscriptionRequired
    
    var errorDescription: String? {
        switch self {
        case .authorizationDenied:
            return "Apple Music authorization was denied"
        case .accessRestricted:
            return "Apple Music access is restricted"
        case .authorizationNotDetermined:
            return "Apple Music authorization status not determined"
        case .unknownAuthorizationStatus:
            return "Unknown Apple Music authorization status"
        case .songNotFound:
            return "The requested song was not found"
        case .subscriptionRequired:
            return "An active Apple Music subscription is required"
        }
    }
}