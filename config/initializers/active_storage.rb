# Brand assets (logo / mark / favicon) are rendered in <img> and <link rel="icon">.
# Rails serves SVG as application/octet-stream + attachment by default, which browsers
# refuse to display inline. Allow trusted tenant brand SVGs to be served as images.
Rails.application.config.active_storage.content_types_to_serve_as_binary -= ["image/svg+xml"]
Rails.application.config.active_storage.content_types_allowed_inline += ["image/svg+xml"]
