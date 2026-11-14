{{flutter_js}}
{{flutter_build_config}}
// Bundle the renderer with the application so first load does not depend on
// an additional CDN. The path follows the document base for subpath hosting.
_flutter.loader.load({config: {canvasKitBaseUrl: 'canvaskit/'}});
