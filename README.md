# Sequential-Text-Interaction

This repository is an experimental macOS AppKit project exploring caret navigation and text selection across multiple sequential `NSTextView`s.

## The goal was to enable

**Seamless cursor movement with arrow keys**

By default, `NSTextView` enforces a hard boundary, that prevents the caret from moving outside its own view. This means the user cannot navigate from one text view to another by using the arrow keys.
My goal was to create a setup where multiple text views can be vertically and the caret can move between them in sequential order (starting from the topmost text view) simply by using the arrow keys.

**Text selection by dragging**

For the same reason, text selection normally cannot extend beyond the `NSTextView` that is currently the `FirstResponder`.

This implementation enables selection across multiple text views and supports editing actions such as:
- copying text (gaps between text views are represented as double line breaks `\n\n`),
- deleting text that spans across text views.


Please note: this project was developed by an inexperienced Software Engineering student 😅
