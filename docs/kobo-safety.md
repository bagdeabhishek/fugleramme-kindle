# Kobo installation safety

KOReader and the Fugleramme plugin do not need a change to Kobo's library scanner.
The guarded installer in this repository places KOReader at
`.kobo/koreader`, installs a NickelMenu launcher, and leaves
`.kobo/Kobo/Kobo eReader.conf` unchanged.

## The rule

Do not add or rewrite `ExcludeSyncFolders` while installing Fugleramme.

Some KOReader instructions use this setting to keep Nickel from scanning the
standard `.adds/koreader` directory. The value is a regular expression stored in
a Qt INI file. Backslashes can be consumed when the file is parsed and written
again. A pattern which looks correct before a reboot can therefore become much
broader afterward.

The guarded installer avoids the problem rather than trying to escape the pattern
correctly. `.kobo` is already private to Kobo software, so no scanner exception is
needed.

## Before writing to a reader

Keep a host-side copy of:

```text
.kobo/KoboReader.sqlite
.kobo/Kobo/Kobo eReader.conf
.kobo/version
metadata.calibre
```

The installer creates this backup automatically. A database backup preserves
library records, reading positions, and annotations. It does not contain the
book files, so keep the original Calibre library or another copy of sideloaded
books as well.

Use a direct USB port and a known-good data cable. A disconnect while the library
database or FAT allocation table is changing can turn a recoverable configuration
mistake into missing files.

## Incident and recovery

During the first Kobo Libra Colour deployment, an `ExcludeSyncFolders` expression
was added manually. Kobo later serialized it without the expected backslashes.
The resulting expression was over-broad. After Nickel re-indexed the reader, the
database fell from 2,748 content records to 336 and roughly 172 MB of sideloaded
files disappeared, leaving their author directories empty.

Recovery followed these steps:

1. Stop all installation work and prevent further writes.
2. Copy the current and pre-change databases and configuration to the host.
3. Unmount the reader and make a complete sector image.
4. Run TestDisk against the image, never against the reader.
5. Validate recovered EPUB and KEPUB files with ZIP CRC checks and validate PDFs
   separately.
6. Restore only files which pass validation.
7. Restore the known-good database and configuration, sync, verify by reading the
   files back, and cleanly unmount.

The filesystem-aware pass recovered every expected filename, but some files were
fragmented. Only 31 of 42 user items passed integrity checks. The corrupt copies
were retained for forensic work but were not written back to the reader.

## Safe install flow

Download the Kobo KOReader archive and NickelMenu's `KoboRoot.tgz`, mount the Kobo,
then run:

```bash
examples/koreader-fugleramme/install-kobo.sh \
  /media/$USER/KOBOeReader \
  ~/Downloads/koreader-kobo.zip \
  ~/Downloads/KoboRoot.tgz \
  http://fugleramme.local
```

The installer:

- verifies that the mount looks like a Kobo;
- refuses to overwrite an existing managed KOReader installation;
- backs up the database, configuration, version, and Calibre metadata to the host;
- installs KOReader under `.kobo/koreader`;
- installs the Fugleramme plugin and optional server setting;
- stages NickelMenu's update archive and launcher configuration;
- confirms that `Kobo eReader.conf` did not change;
- calls `sync` before returning.

Safely eject the Kobo. It processes `KoboRoot.tgz` and restarts. Open NickelMenu,
launch KOReader, then choose **Tools > Fugleramme frame > Open frame**.

## If books disappear

Do not copy more files to the Kobo and do not run a filesystem repair in write
mode. Every write can reuse clusters belonging to deleted books. Unmount it, make
a complete image, and work from the image. Restoring only `KoboReader.sqlite` can
make titles visible again, but it cannot restore missing EPUB data.
