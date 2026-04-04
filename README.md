# KOReader User Patches

Some of my personal user patches to add extra bells and whistles to your KOReader experience.

Current version: `1.0.4`

## Installation

1. Make sure you have the `Reading statistics` plugin enabled in `Plugin management`.
2. Create a `patches` directory inside your KOReader folder on the device (if not exists).
3. Copy any `.lua` patch from this repo into `patches/`. They can be used individually or together.
4. Restart KOReader and make sure the patches are enabled in `Patch management`.

## Patches

### `2-chapter-time-format.lua`

More readable time remaining format for the footer. Shows "X hr Y mins left in chapter/book" when hours are present; otherwise falls back to minutes.

Recommended `Status bar items` settings:

- Chapter title
- Dynamic filler
- Time left to finish chapter or Time left to finish book

Screenshot:
<br>
<img src="resources/chapter-time-format.png" width="320px" alt="Chapter time format in footer">

### `2-author-series.lua`

Adds gesture-driven virtual folders for browsing the library by `Author` and `Series`, with representative covers for each leaf folder.
Assign gestures via `Gesture Manager` to trigger `File browser > Browse by author` and `File browser > Browse by series`.

### `2-reading-percentage.lua`

Replaces the file browser dog-ear with a top-right reading percentage badge for in-progress books in mosaic mode.

### `2-reading-insights-popup.lua`

Reading Insights overlay with today stats (time/pages), streaks, yearly totals, a monthly chart, and a books list on tap.
Assign a gesture via `Gesture Manager` to trigger `Reader > Reading statistics: reading insights`.

Screenshot:
<br>
<img src="resources/reading-insights-popup.png" width="320px" alt="Reading insights popup">
<br>
<img src="resources/reading-insights-popup-book-list.png" width="320px" alt="Reading insights book list">

### `2-reading-stats-popup.lua`

Kobo-style reading stats overlay: chapter time left, next chapter time, book progress, and reading pace.
Assign a gesture via `Gesture Manager` to trigger `Reader > Reading statistics: overview`.

Screenshot:
<br>
<img src="resources/reading-stats-popup.png" width="320px" alt="Reading stats popup">

## License

MIT License. See `LICENSE`.
