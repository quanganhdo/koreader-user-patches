# KOReader User Patches

Some of my personal user patches to add extra bells and whistles to your KOReader experience.

Current version: `1.1.0`

Screenshots were captured in the KOReader emulator with books from [Standard Ebooks](https://standardebooks.org/). Reading progress and statistics use sample data.

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

<a href="resources/chapter-time-format.png"><img src="resources/chapter-time-format-detail.png" width="640" alt="Reader footer showing chapter title and hours and minutes left in the book"></a>

### `2-author-series.lua`

Adds gesture-driven virtual folders for browsing the library by `Author` and `Series`, with representative covers for each leaf folder.
Assign gestures via `Gesture Manager` to trigger `File browser > Browse by author` and `File browser > Browse by series`.

<img src="resources/author-series.png" width="320" alt="Author folders with representative covers, author names, and book counts">

### `2-filemanager-metadata-tabs.lua`

Adds Books, Series, and Authors tabs to the file browser. Install it with `2-author-series.lua` for author and series browsing.

<img src="resources/filemanager-metadata-tabs.png" width="320" alt="Books, Series, and Authors tabs above a three-by-three library of Standard Ebooks">

### `2-finished-badge.lua`

Replaces the opened-book dog-ear with a checkmark on finished books in mosaic mode. Finished-book badges now live in this separate patch; install it alongside `2-reading-percentage.lua` to keep both badges.

<img src="resources/finished-badge.png" width="320" alt="Finished books marked with circular checkmarks on their covers">

### `2-reading-percentage.lua`

Replaces the file browser dog-ear with a top-right reading percentage badge for in-progress books in mosaic mode.

<img src="resources/reading-percentage.png" width="320" alt="Reading percentages displayed at the top right of book covers">

### `2-reading-insights-popup.lua`

Reading Insights overlay with today stats (time/pages), streaks, yearly totals, a monthly chart, and a books list on tap.
Assign a gesture via `Gesture Manager` to trigger `Reader > Reading statistics: reading insights`.

<img src="resources/reading-insights-popup.png" width="320" alt="Reading Insights showing sample streaks, yearly totals, and monthly reading days">
<img src="resources/reading-insights-popup-book-list.png" width="320" alt="Reading Insights book list with nine Standard Ebooks titles">

### `2-reading-stats-popup.lua`

Kobo-style reading stats overlay: chapter time left, next chapter time, book progress, and reading pace.
Assign a gesture via `Gesture Manager` to trigger `Reader > Reading statistics: book overview`.

<img src="resources/reading-stats-popup.png" width="320" alt="Book overview showing chapter time, reading progress, and pace for The Wind in the Willows">

## License

MIT License. See `LICENSE`.
