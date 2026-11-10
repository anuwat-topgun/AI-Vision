# Flutter UI shell

Source only. Platform runner folders are not committed yet; generate them once Flutter is installed:

```bash
cd app/flutter_ui && flutter create --platforms=ios,macos,android,windows --org com.example.aivision .
```

Rules (README §4.1, §19.1): never pass raw 60fps frames across the Dart boundary (use native textures);
no touch-only or Apple-only navigation; File Input tile must stay on Home (ADR-0003, AC-004).
