# Changelog

## 1.0.1

- Files that aren't real Office documents (for example a web page or a "404 Not Found" error saved as `.xls`) are now caught before upload, with a clear message, instead of being uploaded to OneDrive and downloaded again by the browser.

## 1.0.0

First public release.

- Open Word, PowerPoint and Excel documents in Microsoft 365 for the web with a double-click.
- Documents outside OneDrive are copied to `OneDrive › Open in Office Web`, with upload progress read from macOS File Provider.
- Optional sync helper (login item) that copies web edits back to the original file and local edits up to OneDrive, with conflict copies.
- Welcome window to make the app the default for Office documents and turn sync on or off.
- English and Spanish.
