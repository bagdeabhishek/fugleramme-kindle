# Fugleramme for KOReader

This KOReader plugin runs on Kobo and Kindle. It asks Fugleramme for an image at
the device's current screen size, requests colour on colour E Ink devices, and
downloads a frame only when its version changes.

Copy `fugleramme.koplugin` into KOReader's `plugins` directory, restart KOReader,
then open **Tools > Fugleramme frame > Set server URL**. See the repository README
for exact Kobo and Kindle paths and troubleshooting.

Tap the frame to check immediately. Hold anywhere on the frame, or press Back on
a device with keys, to close it. Network failures keep the last successful image
and are written to KOReader's normal log.
