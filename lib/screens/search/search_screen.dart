import 'package:fladder/oxplayer/oxplayer_config.dart';
import 'package:fladder/oxplayer/widgets/oxplayer_search_landing.dart';
import 'package:fladder/oxplayer/widgets/oxplayer_search_tmdb_suggestions.dart';
import 'package:fladder/providers/search_provider.dart';
import 'package:fladder/screens/shared/media/poster_grid.dart';
import 'package:fladder/util/debouncer.dart';
import 'package:fladder/util/string_extensions.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<ConsumerStatefulWidget> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final TextEditingController _controller = TextEditingController();

  final Debouncer searchDebouncer = Debouncer(const Duration(milliseconds: 500));

  // OXPlayer: tracks the committed query (updated when debouncer fires, same
  // cadence as the Jellyfin search) to avoid hammering /search/suggestions on
  // every keystroke.
  String _tmdbQuery = '';

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref.read(searchProvider.notifier).clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final searchResults = ref.watch(searchProvider);

    return Scaffold(
      appBar: AppBar(
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(0),
          child: Stack(
            children: [
              Transform.translate(
                offset: const Offset(0, 4),
                child: Container(
                  height: 1,
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
              ),
              Transform.translate(
                offset: const Offset(0, -4),
                child: AnimatedOpacity(
                  opacity: searchResults.loading ? 1 : 0,
                  duration: const Duration(milliseconds: 250),
                  child: Transform.translate(
                    offset: const Offset(0, 5),
                    child: const LinearProgressIndicator(),
                  ),
                ),
              ),
            ],
          ),
        ),
        title: TextField(
          controller: _controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: "Search library...",
            border: InputBorder.none,
          ),
                  onSubmitted: (value) {
                    ref.read(searchProvider.notifier).searchQuery();
                    if (OxplayerConfig.isEnabled) {
                      if (kDebugMode) {
                        debugPrint('[OX_TMDB] onSubmitted: setting _tmdbQuery="${value.trim()}"');
                      }
                      setState(() => _tmdbQuery = value.trim());
                    }
                  },
                  onChanged: (query) {
                    ref.read(searchProvider.notifier).setQuery(query);
                    searchDebouncer.run(() {
                      ref.read(searchProvider.notifier).searchQuery();
                      if (OxplayerConfig.isEnabled) {
                        if (kDebugMode) {
                          debugPrint('[OX_TMDB] debouncer fired: setting _tmdbQuery="${query.trim()}"');
                        }
                        setState(() => _tmdbQuery = query.trim());
                      }
                    });
                  },
        ),
      ),
      body: ListView(
        children: [
          if (OxplayerConfig.isEnabled && searchResults.searchQuery.trim().isEmpty)
            const OxplayerSearchLanding(),
          // Library results (top 3 per type when OXPlayer is enabled, all results otherwise)
          ...searchResults.results.entries.map(
            (e) => PosterGrid(
              stickyHeader: false,
              name: e.key.name.capitalize(),
              posters: OxplayerConfig.isEnabled
                  ? e.value.take(3).toList()
                  : e.value,
            ),
          ),
          // OXPlayer: server-gated TMDB suggestions (silently empty for general users via 403).
          // Uses the debounced _tmdbQuery so it only fires after the user stops typing.
          if (OxplayerConfig.isEnabled)
            OxplayerSearchTmdbSuggestions(query: _tmdbQuery),
        ],
      ),
    );
  }
}
