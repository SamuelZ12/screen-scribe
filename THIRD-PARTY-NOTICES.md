# Third-party notices

## KaTeX 0.16.22

Offline equation preview bundles the prebuilt JavaScript, CSS and fonts from the official `katex` npm package (https://registry.npmjs.org/katex/-/katex-0.16.22.tgz).

Project: https://github.com/KaTeX/KaTeX

License: MIT. The full upstream notice is retained at `ScreenScribe/Resources/MathPreview/LICENSE-KaTeX.txt` and is copied inside the application bundle with the renderer.

No CDN is used at runtime. User equations are passed as data to the renderer with trust disabled. KaTeX renders a supported subset of LaTeX; it is not a TikZ compiler.
